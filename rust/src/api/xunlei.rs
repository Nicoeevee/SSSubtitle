use futures_util::StreamExt;
use serde::Deserialize;
use sha1::{Digest, Sha1};
use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::{Mutex, OnceLock};
use std::time::Duration;
use url::Url;

const SEARCH_ENDPOINT: &str = "https://api-shoulei-ssl.xunlei.com/oracle/subtitle";
#[cfg(not(target_family = "wasm"))]
const XUNLEI_REFERER: &str = "https://sl-m-ssl.xunlei.com/";
#[cfg(not(target_family = "wasm"))]
const USER_AGENT: &str = "SSSubtitle/0.1 (Xunlei subtitle provider)";
const SEARCH_TIMEOUT: Duration = Duration::from_secs(15);
const DOWNLOAD_TIMEOUT: Duration = Duration::from_secs(30);
const SEARCH_RESPONSE_LIMIT: usize = 2 * 1024 * 1024;
const SUBTITLE_DOWNLOAD_LIMIT: usize = 20 * 1024 * 1024;
#[cfg(not(target_family = "wasm"))]
const MAX_REDIRECTS: usize = 5;
const MAX_REGISTRY_ENTRIES: usize = 4_096;

/// A Xunlei subtitle candidate safe to send across flutter_rust_bridge.
///
/// The provider download URL is deliberately absent. Callers can download a
/// candidate only through its opaque `candidate_id`.
#[derive(Debug, Clone, PartialEq)]
pub struct XunleiCandidate {
    pub candidate_id: String,
    pub extension: String,
    pub name: String,
    pub duration_ms: Option<u64>,
    pub languages: Vec<String>,
    pub upstream_score: Option<f64>,
    pub fingerprint_score: Option<f64>,
}

#[derive(Debug, Clone)]
struct RegisteredCandidate {
    url: Url,
    extension: SubtitleExtension,
}

#[derive(Default)]
#[flutter_rust_bridge::frb(ignore)]
struct CandidateRegistry {
    entries: HashMap<String, RegisteredCandidate>,
    insertion_order: VecDeque<String>,
}

impl CandidateRegistry {
    fn insert(&mut self, id: String, candidate: RegisteredCandidate) {
        if !self.entries.contains_key(&id) {
            self.insertion_order.push_back(id.clone());
        }
        self.entries.insert(id, candidate);

        while self.entries.len() > MAX_REGISTRY_ENTRIES {
            if let Some(expired_id) = self.insertion_order.pop_front() {
                self.entries.remove(&expired_id);
            } else {
                break;
            }
        }
    }
}

static CANDIDATE_REGISTRY: OnceLock<Mutex<CandidateRegistry>> = OnceLock::new();

fn candidate_registry() -> &'static Mutex<CandidateRegistry> {
    CANDIDATE_REGISTRY.get_or_init(|| Mutex::new(CandidateRegistry::default()))
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SubtitleExtension {
    Srt,
    Ass,
    Ssa,
    Vtt,
}

impl SubtitleExtension {
    fn parse(value: &str) -> Result<Self, String> {
        match value
            .trim()
            .trim_start_matches('.')
            .to_ascii_lowercase()
            .as_str()
        {
            "srt" => Ok(Self::Srt),
            "ass" => Ok(Self::Ass),
            "ssa" => Ok(Self::Ssa),
            "vtt" => Ok(Self::Vtt),
            _ => Err("Xunlei returned an unsupported subtitle format".to_owned()),
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::Srt => "srt",
            Self::Ass => "ass",
            Self::Ssa => "ssa",
            Self::Vtt => "vtt",
        }
    }
}

#[derive(Debug, Deserialize)]
struct XunleiSearchResponse {
    #[serde(default)]
    code: Option<i64>,
    #[serde(default)]
    result: Option<String>,
    #[serde(default)]
    data: Option<Vec<XunleiCandidateWire>>,
}

#[derive(Debug, Deserialize)]
struct XunleiCandidateWire {
    #[serde(default)]
    url: Option<String>,
    #[serde(default)]
    ext: Option<String>,
    #[serde(default)]
    name: String,
    #[serde(default)]
    duration: Option<u64>,
    #[serde(default)]
    languages: Vec<String>,
    #[serde(default)]
    score: Option<f64>,
    #[serde(default, rename = "fingerprintf_score")]
    fingerprint_score: Option<f64>,
}

/// Search Xunlei by an editable Suggested Search Name.
///
/// Only `query` is sent to Xunlei. Candidate URLs remain in a bounded native
/// registry and are represented across FRB by opaque SHA-1 identifiers.
pub async fn search_xunlei(query: String) -> Result<Vec<XunleiCandidate>, String> {
    let query = query.trim();
    if query.is_empty() {
        return Err("Search name cannot be empty".to_owned());
    }
    if query.chars().count() > 512 {
        return Err("Search name is too long".to_owned());
    }

    let mut endpoint = Url::parse(SEARCH_ENDPOINT)
        .map_err(|_| "The Xunlei search endpoint is invalid".to_owned())?;
    endpoint.query_pairs_mut().append_pair("name", query);

    let client = build_client(SEARCH_TIMEOUT)?;
    let request = client
        .get(endpoint)
        .header(reqwest::header::ACCEPT, "application/json");
    #[cfg(not(target_family = "wasm"))]
    let request = request
        .timeout(SEARCH_TIMEOUT)
        .header(reqwest::header::USER_AGENT, USER_AGENT);

    let response = request
        .send()
        .await
        .map_err(|_| "Xunlei search request failed".to_owned())?;
    validate_response_url(response.url())?;
    if !response.status().is_success() {
        return Err(format!(
            "Xunlei search returned HTTP {}",
            response.status().as_u16()
        ));
    }

    let body = read_limited(response, SEARCH_RESPONSE_LIMIT, "Xunlei search response").await?;
    parse_search_payload(&body)
}

/// Download a previously searched Xunlei Subtitle Candidate.
///
/// The opaque ID must still exist in the process-local bounded registry. The
/// implementation streams the response and aborts before it exceeds 20 MiB.
pub async fn download_xunlei(candidate_id: String) -> Result<Vec<u8>, String> {
    let registered = {
        let registry = candidate_registry()
            .lock()
            .map_err(|_| "The Xunlei candidate registry is unavailable".to_owned())?;
        registry
            .entries
            .get(&candidate_id)
            .cloned()
            .ok_or_else(|| "The Xunlei candidate is unknown or expired".to_owned())?
    };

    validate_download_url(&registered.url)?;
    let client = build_client(DOWNLOAD_TIMEOUT)?;
    let request = client.get(registered.url);
    #[cfg(not(target_family = "wasm"))]
    let request = request
        .timeout(DOWNLOAD_TIMEOUT)
        .header(reqwest::header::USER_AGENT, USER_AGENT)
        .header(reqwest::header::REFERER, XUNLEI_REFERER);

    let response = request
        .send()
        .await
        .map_err(|_| "Xunlei subtitle download failed".to_owned())?;
    validate_download_url(response.url())?;
    if !response.status().is_success() {
        return Err(format!(
            "Xunlei subtitle download returned HTTP {}",
            response.status().as_u16()
        ));
    }

    let bytes = read_limited(response, SUBTITLE_DOWNLOAD_LIMIT, "Subtitle download").await?;
    validate_subtitle_content(&bytes, registered.extension)?;
    Ok(bytes)
}

fn parse_search_payload(body: &[u8]) -> Result<Vec<XunleiCandidate>, String> {
    let response: XunleiSearchResponse =
        serde_json::from_slice(body).map_err(|_| "Xunlei returned invalid JSON".to_owned())?;

    if response.code.is_some_and(|code| code != 0) {
        return Err(format!(
            "Xunlei returned business error code {}",
            response.code.unwrap_or_default()
        ));
    }
    if let Some(result) = response.result.as_deref() {
        let result = result.trim();
        if !result.is_empty() && !result.eq_ignore_ascii_case("ok") {
            return Err("Xunlei returned an unsuccessful result".to_owned());
        }
    }

    let mut candidates = Vec::new();
    let mut seen_ids = HashSet::new();
    let mut registry = candidate_registry()
        .lock()
        .map_err(|_| "The Xunlei candidate registry is unavailable".to_owned())?;

    for wire in response.data.unwrap_or_default() {
        let Some(extension_text) = wire.ext.as_deref() else {
            continue;
        };
        let Ok(extension) = SubtitleExtension::parse(extension_text) else {
            continue;
        };
        let Some(url_text) = wire.url.as_deref() else {
            continue;
        };
        let Ok(url) = Url::parse(url_text) else {
            continue;
        };
        if validate_download_url(&url).is_err() {
            continue;
        }

        let candidate_id = stable_candidate_id(url.as_str());
        if !seen_ids.insert(candidate_id.clone()) {
            continue;
        }
        registry.insert(candidate_id.clone(), RegisteredCandidate { url, extension });
        candidates.push(XunleiCandidate {
            candidate_id,
            extension: extension.as_str().to_owned(),
            name: wire.name,
            duration_ms: wire.duration.filter(|duration| *duration > 0),
            languages: wire.languages,
            upstream_score: wire.score,
            fingerprint_score: wire.fingerprint_score,
        });
    }

    Ok(candidates)
}

fn stable_candidate_id(url: &str) -> String {
    format!("{:x}", Sha1::digest(url.as_bytes()))
}

fn build_client(timeout: Duration) -> Result<reqwest::Client, String> {
    let builder = reqwest::Client::builder();

    // Browser fetch owns redirects on WASM, so it cannot expose each hop to a
    // reqwest policy. Both public operations still check the final URL.
    #[cfg(not(target_family = "wasm"))]
    let builder = builder
        .timeout(timeout)
        .redirect(reqwest::redirect::Policy::custom(|attempt| {
            if attempt.previous().len() >= MAX_REDIRECTS {
                return attempt.error("too many redirects");
            }
            if validate_download_url(attempt.url()).is_err() {
                return attempt.error("redirect target is not allowed");
            }
            attempt.follow()
        }));

    #[cfg(target_family = "wasm")]
    let _ = timeout;

    builder
        .build()
        .map_err(|error| format!("Could not create the Xunlei HTTP client: {error}"))
}

fn validate_response_url(url: &Url) -> Result<(), String> {
    validate_download_url(url)
}

fn validate_download_url(url: &Url) -> Result<(), String> {
    if url.scheme() != "https" {
        return Err("Xunlei download URL must use HTTPS".to_owned());
    }
    if !url.username().is_empty() || url.password().is_some() {
        return Err("Xunlei download URL must not contain credentials".to_owned());
    }
    if url.port().is_some_and(|port| port != 443) {
        return Err("Xunlei download URL must use the standard HTTPS port".to_owned());
    }
    let host = url
        .host_str()
        .ok_or_else(|| "Xunlei download URL has no host".to_owned())?
        .trim_end_matches('.')
        .to_ascii_lowercase();
    if !allowed_host(&host) {
        return Err("Xunlei download URL host is not allowed".to_owned());
    }
    Ok(())
}

fn allowed_host(host: &str) -> bool {
    host == "xunlei.com"
        || host.ends_with(".xunlei.com")
        || host == "geilijiasu.com"
        || host.ends_with(".geilijiasu.com")
}

async fn read_limited(
    response: reqwest::Response,
    limit: usize,
    description: &str,
) -> Result<Vec<u8>, String> {
    if response
        .content_length()
        .is_some_and(|length| length > limit as u64)
    {
        return Err(format!("{description} exceeds the size limit"));
    }

    let mut bytes = Vec::new();
    let mut stream = response.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|_| format!("Could not read {description}"))?;
        if bytes.len().saturating_add(chunk.len()) > limit {
            return Err(format!("{description} exceeds the size limit"));
        }
        bytes.extend_from_slice(&chunk);
    }
    Ok(bytes)
}

fn validate_subtitle_content(bytes: &[u8], extension: SubtitleExtension) -> Result<(), String> {
    if bytes.len() < 8 {
        return Err("Subtitle content is empty or too short".to_owned());
    }

    let sample = subtitle_sample_text(bytes);
    let trimmed = sample.trim_start_matches('\u{feff}').trim_start();
    let lower = trimmed.to_lowercase();
    if lower.starts_with("<!doctype html")
        || lower.starts_with("<html")
        || trimmed.starts_with('{')
        || trimmed.starts_with('[') && !lower.starts_with("[script info]")
    {
        return Err("Downloaded content is not a subtitle".to_owned());
    }

    let valid = match extension {
        SubtitleExtension::Srt => sample.contains("-->"),
        SubtitleExtension::Ass | SubtitleExtension::Ssa => {
            lower.contains("[script info]") || lower.contains("dialogue:")
        }
        SubtitleExtension::Vtt => lower.starts_with("webvtt") || sample.contains("-->"),
    };
    if !valid {
        return Err(format!(
            "Downloaded content is not valid {} subtitle data",
            extension.as_str().to_ascii_uppercase()
        ));
    }
    Ok(())
}

fn subtitle_sample_text(bytes: &[u8]) -> String {
    const SAMPLE_LIMIT: usize = 64 * 1024;
    let sample = &bytes[..bytes.len().min(SAMPLE_LIMIT)];

    if sample.starts_with(&[0xff, 0xfe]) {
        let units = sample[2..]
            .chunks_exact(2)
            .map(|pair| u16::from_le_bytes([pair[0], pair[1]]))
            .collect::<Vec<_>>();
        return String::from_utf16_lossy(&units);
    }
    if sample.starts_with(&[0xfe, 0xff]) {
        let units = sample[2..]
            .chunks_exact(2)
            .map(|pair| u16::from_be_bytes([pair[0], pair[1]]))
            .collect::<Vec<_>>();
        return String::from_utf16_lossy(&units);
    }

    String::from_utf8_lossy(sample.strip_prefix(&[0xef, 0xbb, 0xbf]).unwrap_or(sample)).into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    const SUCCESS_RESPONSE: &str = r#"{
        "code": 0,
        "result": "ok",
        "data": [{
            "gcid": "fixture-gcid",
            "cid": "fixture-cid",
            "url": "https://subtitle.v.geilijiasu.com/fixtures/sample-subtitle.srt",
            "ext": "srt",
            "name": "big_buck_scenes.srt",
            "duration": 596458,
            "languages": ["英语"],
            "source": 0,
            "score": 12.5,
            "fingerprintf_score": 7,
            "extra_name": "（网友上传）",
            "mt": 2
        }]
    }"#;

    #[test]
    fn successful_payload_maps_the_observed_xunlei_contract() {
        let candidates = parse_search_payload(SUCCESS_RESPONSE.as_bytes()).unwrap();

        assert_eq!(candidates.len(), 1);
        assert_eq!(candidates[0].name, "big_buck_scenes.srt");
        assert_eq!(candidates[0].extension, "srt");
        assert_eq!(candidates[0].duration_ms, Some(596_458));
        assert_eq!(candidates[0].languages, ["英语"]);
        assert_eq!(candidates[0].upstream_score, Some(12.5));
        assert_eq!(candidates[0].fingerprint_score, Some(7.0));
        assert_eq!(
            candidates[0].candidate_id,
            stable_candidate_id("https://subtitle.v.geilijiasu.com/fixtures/sample-subtitle.srt")
        );
    }

    #[test]
    fn business_error_is_not_exposed_as_an_empty_search() {
        let error = parse_search_payload(br#"{"code": 17, "result": "failed"}"#).unwrap_err();

        assert_eq!(error, "Xunlei returned business error code 17");
    }

    #[test]
    fn unsafe_and_unsupported_candidates_are_omitted() {
        let payload = br#"{
            "code": 0,
            "data": [
                {"url":"http://subtitle.v.geilijiasu.com/a.srt","ext":"srt","name":"plain HTTP"},
                {"url":"https://example.com/a.srt","ext":"srt","name":"foreign host"},
                {"url":"https://subtitle.v.geilijiasu.com/a.exe","ext":"exe","name":"bad format"}
            ]
        }"#;

        assert!(parse_search_payload(payload).unwrap().is_empty());
    }

    #[test]
    fn allowed_host_requires_a_real_dns_suffix_boundary() {
        assert!(allowed_host("subtitle.v.geilijiasu.com"));
        assert!(allowed_host("api-shoulei-ssl.xunlei.com"));
        assert!(!allowed_host("geilijiasu.com.example.org"));
        assert!(!allowed_host("evilxunlei.com"));
    }

    #[test]
    fn subtitle_validation_accepts_supported_formats_and_rejects_error_documents() {
        validate_subtitle_content(
            b"1\r\n00:00:01,000 --> 00:00:02,000\r\nHello\r\n",
            SubtitleExtension::Srt,
        )
        .unwrap();
        validate_subtitle_content(
            b"WEBVTT\n\n00:01.000 --> 00:02.000\nHello\n",
            SubtitleExtension::Vtt,
        )
        .unwrap();
        assert!(validate_subtitle_content(
            b"<!doctype html><html>upstream error</html>",
            SubtitleExtension::Srt,
        )
        .is_err());
        assert!(
            validate_subtitle_content(br#"{"error":"rate limited"}"#, SubtitleExtension::Ass)
                .is_err()
        );
    }

    #[test]
    fn utf16_subtitle_content_is_detected_before_validation() {
        let mut bytes = vec![0xff, 0xfe];
        for unit in "1\r\n00:00:01,000 --> 00:00:02,000\r\n你好\r\n".encode_utf16() {
            bytes.extend_from_slice(&unit.to_le_bytes());
        }

        validate_subtitle_content(&bytes, SubtitleExtension::Srt).unwrap();
    }
}
