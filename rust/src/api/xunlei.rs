use crate::api::workflow::SubtitleFormat;
use futures_util::StreamExt;
use serde::Deserialize;
use std::collections::HashSet;
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
#[derive(Debug, Clone, PartialEq)]
#[flutter_rust_bridge::frb(ignore)]
pub(crate) struct XunleiCandidate {
    pub(crate) locator: String,
    pub(crate) extension: String,
    pub(crate) name: String,
    pub(crate) duration_ms: Option<u64>,
    pub(crate) languages: Vec<String>,
    pub(crate) upstream_score: Option<f64>,
    pub(crate) fingerprint_score: Option<f64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum XunleiFailure {
    Network,
    Http(u16),
    Protocol,
    ArtifactTooLarge,
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
#[flutter_rust_bridge::frb(ignore)]
pub(crate) async fn search_xunlei(query: String) -> Result<Vec<XunleiCandidate>, XunleiFailure> {
    let query = query.trim();
    if query.is_empty() {
        return Err(XunleiFailure::Protocol);
    }
    if query.chars().count() > 512 {
        return Err(XunleiFailure::Protocol);
    }

    let mut endpoint = Url::parse(SEARCH_ENDPOINT).map_err(|_| XunleiFailure::Protocol)?;
    endpoint.query_pairs_mut().append_pair("name", query);

    let client = build_client(SEARCH_TIMEOUT).map_err(|_| XunleiFailure::Network)?;
    let request = client
        .get(endpoint)
        .header(reqwest::header::ACCEPT, "application/json");
    #[cfg(not(target_family = "wasm"))]
    let request = request
        .timeout(SEARCH_TIMEOUT)
        .header(reqwest::header::USER_AGENT, USER_AGENT);

    let response = request.send().await.map_err(|_| XunleiFailure::Network)?;
    validate_response_url(response.url()).map_err(|_| XunleiFailure::Protocol)?;
    if !response.status().is_success() {
        return Err(XunleiFailure::Http(response.status().as_u16()));
    }

    let body = read_limited(response, SEARCH_RESPONSE_LIMIT, XunleiFailure::Protocol).await?;
    parse_search_payload(&body)
}

/// Download a previously searched Xunlei Subtitle Candidate.
#[flutter_rust_bridge::frb(ignore)]
pub(crate) async fn download_xunlei(locator: String) -> Result<Vec<u8>, XunleiFailure> {
    let url = Url::parse(&locator).map_err(|_| XunleiFailure::Protocol)?;
    validate_download_url(&url).map_err(|_| XunleiFailure::Protocol)?;
    let client = build_client(DOWNLOAD_TIMEOUT).map_err(|_| XunleiFailure::Network)?;
    let request = client.get(url);
    #[cfg(not(target_family = "wasm"))]
    let request = request
        .timeout(DOWNLOAD_TIMEOUT)
        .header(reqwest::header::USER_AGENT, USER_AGENT)
        .header(reqwest::header::REFERER, XUNLEI_REFERER);

    let response = request.send().await.map_err(|_| XunleiFailure::Network)?;
    validate_download_url(response.url()).map_err(|_| XunleiFailure::Protocol)?;
    if !response.status().is_success() {
        return Err(XunleiFailure::Http(response.status().as_u16()));
    }

    read_limited(
        response,
        SUBTITLE_DOWNLOAD_LIMIT,
        XunleiFailure::ArtifactTooLarge,
    )
    .await
}

fn parse_search_payload(body: &[u8]) -> Result<Vec<XunleiCandidate>, XunleiFailure> {
    let response: XunleiSearchResponse =
        serde_json::from_slice(body).map_err(|_| XunleiFailure::Protocol)?;

    if response.code.is_some_and(|code| code != 0) {
        return Err(XunleiFailure::Protocol);
    }
    if let Some(result) = response.result.as_deref() {
        let result = result.trim();
        if !result.is_empty() && !result.eq_ignore_ascii_case("ok") {
            return Err(XunleiFailure::Protocol);
        }
    }

    let mut candidates = Vec::new();
    let mut seen_locators = HashSet::new();

    for wire in response.data.unwrap_or_default() {
        let Some(extension_text) = wire.ext.as_deref() else {
            continue;
        };
        let Some(extension) = SubtitleFormat::parse(extension_text) else {
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

        let locator = url.to_string();
        if !seen_locators.insert(locator.clone()) {
            continue;
        }
        candidates.push(XunleiCandidate {
            locator,
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
    over_limit: XunleiFailure,
) -> Result<Vec<u8>, XunleiFailure> {
    if response
        .content_length()
        .is_some_and(|length| length > limit as u64)
    {
        return Err(over_limit);
    }

    let mut bytes = Vec::new();
    let mut stream = response.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|_| XunleiFailure::Network)?;
        if bytes.len().saturating_add(chunk.len()) > limit {
            return Err(over_limit);
        }
        bytes.extend_from_slice(&chunk);
    }
    Ok(bytes)
}

#[cfg(test)]
fn validate_subtitle_content(bytes: &[u8], extension: SubtitleFormat) -> Result<(), String> {
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
        SubtitleFormat::Srt => sample.contains("-->"),
        SubtitleFormat::Ass | SubtitleFormat::Ssa => {
            lower.contains("[script info]") || lower.contains("dialogue:")
        }
        SubtitleFormat::Vtt => lower.starts_with("webvtt") || sample.contains("-->"),
    };
    if !valid {
        return Err(format!(
            "Downloaded content is not valid {} subtitle data",
            extension.as_str().to_ascii_uppercase()
        ));
    }
    Ok(())
}

#[cfg(test)]
fn subtitle_sample_text(bytes: &[u8]) -> String {
    const SAMPLE_LIMIT: usize = 64 * 1024;
    let sample = &bytes[..bytes.len().min(SAMPLE_LIMIT)];

    if sample.starts_with(&[0xff, 0xfe]) {
        let units = sample[2..]
            .as_chunks::<2>()
            .0
            .iter()
            .map(|pair| u16::from_le_bytes([pair[0], pair[1]]))
            .collect::<Vec<_>>();
        return String::from_utf16_lossy(&units);
    }
    if sample.starts_with(&[0xfe, 0xff]) {
        let units = sample[2..]
            .as_chunks::<2>()
            .0
            .iter()
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
            candidates[0].locator,
            "https://subtitle.v.geilijiasu.com/fixtures/sample-subtitle.srt"
        );
    }

    #[test]
    fn business_error_is_bounded_as_a_protocol_failure() {
        let error = parse_search_payload(br#"{"code": 17, "result": "failed"}"#).unwrap_err();

        assert_eq!(error, XunleiFailure::Protocol);
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
            SubtitleFormat::Srt,
        )
        .unwrap();
        validate_subtitle_content(
            b"WEBVTT\n\n00:01.000 --> 00:02.000\nHello\n",
            SubtitleFormat::Vtt,
        )
        .unwrap();
        assert!(validate_subtitle_content(
            b"<!doctype html><html>upstream error</html>",
            SubtitleFormat::Srt,
        )
        .is_err());
        assert!(
            validate_subtitle_content(br#"{"error":"rate limited"}"#, SubtitleFormat::Ass).is_err()
        );
    }

    #[test]
    fn utf16_subtitle_content_is_detected_before_validation() {
        let mut bytes = vec![0xff, 0xfe];
        for unit in "1\r\n00:00:01,000 --> 00:00:02,000\r\n你好\r\n".encode_utf16() {
            bytes.extend_from_slice(&unit.to_le_bytes());
        }

        validate_subtitle_content(&bytes, SubtitleFormat::Srt).unwrap();
    }
}
