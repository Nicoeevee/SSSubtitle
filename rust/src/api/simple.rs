pub const SAMPLE_SIZE: u64 = 0x5000;
pub const PREVIEW_PAGE_SIZE: u32 = 30;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ByteRange {
    pub offset: u64,
    pub length: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VideoSamplePlan {
    pub file_size: u64,
    pub ranges: Vec<ByteRange>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SampleChunk {
    pub offset: u64,
    pub bytes: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SubtitlePreviewPage {
    pub lines: Vec<String>,
    pub page: u32,
    pub page_size: u32,
    pub total_lines: u32,
    pub total_pages: u32,
    pub encoding: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SubtitleCandidate {
    pub id: String,
    pub name: String,
    pub cid: Option<String>,
    pub duration_millis: Option<u64>,
    pub language: Option<String>,
    pub format: String,
    pub upstream_score: i64,
    pub fingerprint_match: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CandidateRankingContext {
    pub search_name: String,
    pub video_cid: Option<String>,
    pub video_duration_millis: Option<u64>,
    pub preferred_languages: Vec<String>,
    pub preferred_formats: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RankedSubtitleCandidate {
    pub candidate: SubtitleCandidate,
    pub score: i64,
}

#[flutter_rust_bridge::frb(sync)]
pub fn derive_search_name(filename: String) -> String {
    let filename = filename.trim();
    let basename = filename
        .rsplit(['/', '\\'])
        .next()
        .unwrap_or(filename)
        .trim();
    let stem = basename
        .rsplit_once('.')
        .map_or(basename, |(stem, _)| stem)
        .trim();
    let candidate = stem
        .rsplit_once('@')
        .map_or(stem, |(_, suffix)| suffix)
        .trim();
    if candidate.is_empty() {
        if stem.is_empty() {
            basename.to_owned()
        } else {
            stem.to_owned()
        }
    } else {
        candidate.to_owned()
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn plan_video_sample(file_size: u64) -> VideoSamplePlan {
    let ranges = if file_size == 0 {
        Vec::new()
    } else if file_size < SAMPLE_SIZE * 3 {
        vec![ByteRange {
            offset: 0,
            length: file_size,
        }]
    } else {
        vec![
            ByteRange {
                offset: 0,
                length: SAMPLE_SIZE,
            },
            ByteRange {
                offset: file_size / 3,
                length: SAMPLE_SIZE,
            },
            ByteRange {
                offset: file_size - SAMPLE_SIZE,
                length: SAMPLE_SIZE,
            },
        ]
    };
    VideoSamplePlan { file_size, ranges }
}

#[flutter_rust_bridge::frb(sync)]
pub fn compute_cid(file_size: u64, mut chunks: Vec<SampleChunk>) -> Result<String, String> {
    use sha1::{Digest, Sha1};

    let expected = plan_video_sample(file_size);
    if chunks.len() != expected.ranges.len() {
        return Err(format!(
            "expected {} sample chunks, got {}",
            expected.ranges.len(),
            chunks.len()
        ));
    }
    chunks.sort_by_key(|chunk| chunk.offset);
    for (chunk, range) in chunks.iter().zip(&expected.ranges) {
        if chunk.offset != range.offset || chunk.bytes.len() as u64 != range.length {
            return Err(format!("invalid sample chunk at offset {}", chunk.offset));
        }
    }
    let mut sha1 = Sha1::new();
    for chunk in chunks {
        sha1.update(chunk.bytes);
    }
    let digest = sha1.finalize();
    const HEX: &[u8; 16] = b"0123456789ABCDEF";
    let mut cid = String::with_capacity(digest.len() * 2);
    for byte in digest {
        cid.push(HEX[(byte >> 4) as usize] as char);
        cid.push(HEX[(byte & 0x0f) as usize] as char);
    }
    Ok(cid)
}

#[flutter_rust_bridge::frb(sync)]
pub fn subtitle_preview_page(
    bytes: Vec<u8>,
    page: u32,
    format: String,
) -> Result<SubtitlePreviewPage, String> {
    const MAX_SUBTITLE_BYTES: usize = 20 * 1024 * 1024;
    if !(8..=MAX_SUBTITLE_BYTES).contains(&bytes.len()) {
        return Err("subtitle must be between 8 bytes and 20 MiB".into());
    }
    if page == 0 {
        return Err("page numbers start at 1".into());
    }
    let (text, encoding) = decode_subtitle(&bytes)?;
    validate_subtitle_text(&text, &format)?;
    let lines: Vec<String> = text
        .lines()
        .map(|line| line.trim_end_matches('\r').to_owned())
        .collect();
    let total_lines = u32::try_from(lines.len()).map_err(|_| "subtitle has too many lines")?;
    let total_pages = total_lines.max(1).div_ceil(PREVIEW_PAGE_SIZE);
    if page > total_pages {
        return Err(format!("page {page} exceeds total pages {total_pages}"));
    }
    let start = ((page - 1) * PREVIEW_PAGE_SIZE) as usize;
    let end = (start + PREVIEW_PAGE_SIZE as usize).min(lines.len());
    Ok(SubtitlePreviewPage {
        lines: lines[start..end].to_vec(),
        page,
        page_size: PREVIEW_PAGE_SIZE,
        total_lines,
        total_pages,
        encoding,
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn rank_subtitle_candidates(
    candidates: Vec<SubtitleCandidate>,
    context: CandidateRankingContext,
) -> Vec<RankedSubtitleCandidate> {
    let mut ranked: Vec<_> = candidates
        .into_iter()
        .map(|candidate| {
            let score = candidate_score(&candidate, &context);
            RankedSubtitleCandidate { candidate, score }
        })
        .collect();
    ranked.sort_by(|left, right| right.score.cmp(&left.score));
    ranked
}

fn decode_subtitle(bytes: &[u8]) -> Result<(String, String), String> {
    if let Some(body) = bytes.strip_prefix(&[0xEF, 0xBB, 0xBF]) {
        return String::from_utf8(body.to_vec())
            .map(|s| (s, "UTF-8 BOM".into()))
            .map_err(|_| "invalid UTF-8 BOM subtitle".into());
    }
    if let Some(body) = bytes.strip_prefix(&[0xFF, 0xFE]) {
        return decode_utf16(body, true).map(|s| (s, "UTF-16LE".into()));
    }
    if let Some(body) = bytes.strip_prefix(&[0xFE, 0xFF]) {
        return decode_utf16(body, false).map(|s| (s, "UTF-16BE".into()));
    }
    if let Ok(text) = std::str::from_utf8(bytes) {
        return Ok((text.to_owned(), "UTF-8".into()));
    }
    let (decoded, _, had_errors) = encoding_rs::GBK.decode(bytes);
    if !had_errors {
        return Ok((decoded.into_owned(), "GBK".into()));
    }
    Ok((
        String::from_utf8_lossy(bytes).into_owned(),
        "UTF-8 lossy".into(),
    ))
}

fn decode_utf16(bytes: &[u8], little_endian: bool) -> Result<String, String> {
    if !bytes.len().is_multiple_of(2) {
        return Err("UTF-16 subtitle has an odd byte count".into());
    }
    let units = bytes.as_chunks::<2>().0.iter().map(|pair| {
        if little_endian {
            u16::from_le_bytes([pair[0], pair[1]])
        } else {
            u16::from_be_bytes([pair[0], pair[1]])
        }
    });
    std::char::decode_utf16(units)
        .collect::<Result<String, _>>()
        .map_err(|_| "invalid UTF-16 subtitle".into())
}

fn validate_subtitle_text(text: &str, format: &str) -> Result<(), String> {
    let trimmed = text.trim_start().to_ascii_lowercase();
    if trimmed.starts_with("<!doctype html")
        || trimmed.starts_with("<html")
        || ((trimmed.starts_with('{') && trimmed.trim_end().ends_with('}'))
            || (trimmed.starts_with('[') && trimmed.trim_end().ends_with(']')))
    {
        return Err("downloaded content is HTML or JSON, not a subtitle".into());
    }
    match format
        .trim()
        .trim_start_matches('.')
        .to_ascii_lowercase()
        .as_str()
    {
        "srt" if !text.contains("-->") => Err("SRT subtitle has no timing arrow".into()),
        "ass" | "ssa" if !(trimmed.contains("[script info]") || trimmed.contains("dialogue:")) => {
            Err("ASS/SSA subtitle has no script header or dialogue".into())
        }
        "srt" | "ass" | "ssa" | "vtt" | "txt" => Ok(()),
        other => Err(format!("unsupported subtitle format: {other}")),
    }
}

fn normalized_title(value: &str) -> String {
    let value = value.rsplit_once('.').map_or(value, |(stem, _)| stem);
    value
        .to_lowercase()
        .chars()
        .map(|ch| {
            if ch.is_alphanumeric() || ('\u{4e00}'..='\u{9fff}').contains(&ch) {
                ch
            } else {
                ' '
            }
        })
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

fn candidate_score(candidate: &SubtitleCandidate, context: &CandidateRankingContext) -> i64 {
    let mut score = 0;
    if candidate
        .cid
        .as_deref()
        .zip(context.video_cid.as_deref())
        .is_some_and(|(a, b)| a.eq_ignore_ascii_case(b))
    {
        score += 10_000;
    }
    let title = normalized_title(&candidate.name);
    let query = normalized_title(&context.search_name);
    if !query.is_empty() && title == query {
        score += 900;
    } else if !query.is_empty() && (title.contains(&query) || query.contains(&title)) {
        score += 650;
    } else {
        let tokens: Vec<_> = query
            .split_whitespace()
            .filter(|token| token.chars().count() >= 2)
            .collect();
        if !tokens.is_empty() {
            score += 500
                * tokens
                    .iter()
                    .filter(|token| title.contains(**token))
                    .count() as i64
                / tokens.len() as i64;
        }
    }
    if let (Some(actual), Some(expected)) =
        (candidate.duration_millis, context.video_duration_millis)
    {
        if expected > 0 {
            let difference = actual.abs_diff(expected) as f64 / expected as f64;
            score += if difference <= 0.01 {
                1_200
            } else if difference <= 0.03 {
                800
            } else if difference <= 0.05 {
                500
            } else if difference <= 0.10 {
                150
            } else if difference > 0.30 {
                -300
            } else {
                0
            };
        }
    }
    let language = candidate
        .language
        .as_deref()
        .unwrap_or("")
        .to_ascii_lowercase();
    score += if language.is_empty() {
        100
    } else if matches!(
        language.as_str(),
        "zh-cn" | "zh-hans" | "chs" | "简体" | "简中"
    ) {
        500
    } else if matches!(language.as_str(), "zh" | "chi" | "zho" | "chinese" | "中文") {
        350
    } else if matches!(
        language.as_str(),
        "zh-tw" | "zh-hant" | "cht" | "繁体" | "繁中"
    ) {
        220
    } else {
        context
            .preferred_languages
            .iter()
            .position(|preferred| preferred.eq_ignore_ascii_case(&language))
            .map_or(0, |index| (180 - index as i64 * 20).max(20))
    };
    score += match candidate
        .format
        .trim()
        .trim_start_matches('.')
        .to_ascii_lowercase()
        .as_str()
    {
        "srt" => 80,
        "ass" => 60,
        "ssa" => 50,
        "vtt" => 40,
        _ => 0,
    };
    score += candidate.upstream_score.clamp(0, 100);
    if candidate.fingerprint_match {
        score += 100;
    }
    score
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Default utilities - feel free to customize
    flutter_rust_bridge::setup_default_user_utils();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn derives_search_name_from_last_at_sign_before_extension() {
        assert_eq!(
            derive_search_name("archive.example@documentary_episode.mp4".into()),
            "documentary_episode"
        );
        assert_eq!(
            derive_search_name("publisher@collection@concert_recording.mkv".into()),
            "concert_recording"
        );
        assert_eq!(
            derive_search_name("  travel_video.mp4  ".into()),
            "travel_video"
        );
        assert_eq!(derive_search_name("site@  .mp4".into()), "site@");
    }

    #[test]
    fn plans_whole_small_file_once_and_three_non_overlapping_large_samples() {
        assert_eq!(plan_video_sample(0).ranges, vec![]);
        assert_eq!(
            plan_video_sample(12).ranges,
            vec![ByteRange {
                offset: 0,
                length: 12
            }]
        );

        let plan = plan_video_sample(SAMPLE_SIZE * 10);
        assert_eq!(plan.ranges.len(), 3);
        assert!(plan.ranges.iter().all(|range| range.length == SAMPLE_SIZE));
        assert_eq!(plan.ranges[0].offset, 0);
        assert_eq!(plan.ranges[1].offset, SAMPLE_SIZE * 10 / 3);
        assert_eq!(plan.ranges[2].offset, SAMPLE_SIZE * 9);
        for pair in plan.ranges.windows(2) {
            assert!(pair[0].offset + pair[0].length <= pair[1].offset);
        }
        assert_eq!(
            plan_video_sample(SAMPLE_SIZE * 3)
                .ranges
                .iter()
                .map(|range| range.offset)
                .collect::<Vec<_>>(),
            vec![0, SAMPLE_SIZE, SAMPLE_SIZE * 2],
        );
    }

    #[test]
    fn computes_uppercase_sha1_only_for_the_exact_plan() {
        let chunks = vec![SampleChunk {
            offset: 0,
            bytes: b"abc".to_vec(),
        }];
        assert_eq!(
            compute_cid(3, chunks).unwrap(),
            "A9993E364706816ABA3E25717850C26C9CD0D89D"
        );
        assert!(compute_cid(
            3,
            vec![SampleChunk {
                offset: 1,
                bytes: b"abc".to_vec()
            }]
        )
        .is_err());
        assert!(compute_cid(
            3,
            vec![
                SampleChunk {
                    offset: 0,
                    bytes: b"abc".to_vec()
                },
                SampleChunk {
                    offset: 0,
                    bytes: b"abc".to_vec()
                },
            ]
        )
        .is_err());
    }

    #[test]
    fn decodes_and_paginates_utf8_utf16_and_gbk_subtitles() {
        let text = (1..=31)
            .map(|n| format!("{n}\n00:00:01,000 --> 00:00:02,000\nline {n}"))
            .collect::<Vec<_>>()
            .join("\n");
        let page = subtitle_preview_page(text.as_bytes().to_vec(), 4, "srt".into()).unwrap();
        assert_eq!(
            page.lines,
            vec!["31", "00:00:01,000 --> 00:00:02,000", "line 31"]
        );
        assert_eq!(
            (page.page_size, page.total_lines, page.total_pages),
            (30, 93, 4)
        );
        assert_eq!(page.encoding, "UTF-8");

        let utf16le = [
            vec![0xFF, 0xFE],
            "[Script Info]\n字幕"
                .encode_utf16()
                .flat_map(u16::to_le_bytes)
                .collect(),
        ]
        .concat();
        assert_eq!(
            subtitle_preview_page(utf16le, 1, "ass".into())
                .unwrap()
                .lines,
            vec!["[Script Info]", "字幕"]
        );

        let utf16be = [
            vec![0xFE, 0xFF],
            "WEBVTT\n字幕"
                .encode_utf16()
                .flat_map(u16::to_be_bytes)
                .collect(),
        ]
        .concat();
        assert_eq!(
            subtitle_preview_page(utf16be, 1, "vtt".into())
                .unwrap()
                .encoding,
            "UTF-16BE"
        );

        let (gbk, _, _) = encoding_rs::GBK.encode("1\n00:00:01 --> 00:00:02\n中文字幕");
        let preview = subtitle_preview_page(gbk.into_owned(), 1, "srt".into()).unwrap();
        assert_eq!(preview.lines.last().unwrap(), "中文字幕");
        assert_eq!(preview.encoding, "GBK");
        assert!(subtitle_preview_page(b"one two three".to_vec(), 0, "txt".into()).is_err());
        assert!(subtitle_preview_page(b"one two three".to_vec(), 2, "txt".into()).is_err());
        assert!(subtitle_preview_page(b"<html>error</html>".to_vec(), 1, "txt".into()).is_err());
        assert!(subtitle_preview_page(br#"{"error":"denied"}"#.to_vec(), 1, "txt".into()).is_err());
    }

    #[test]
    fn ranks_candidates_by_all_signals_and_keeps_ties_stable() {
        let candidate = |id: &str, cid: Option<&str>, duration, language: &str, format: &str| {
            SubtitleCandidate {
                id: id.into(),
                name: "documentary episode Chinese".into(),
                cid: cid.map(Into::into),
                duration_millis: duration,
                language: Some(language.into()),
                format: format.into(),
                upstream_score: 0,
                fingerprint_match: false,
            }
        };
        let ranked = rank_subtitle_candidates(
            vec![
                candidate("weak", None, None, "en", "ass"),
                candidate("best", Some("matching-cid"), Some(100_500), "zh-CN", "srt"),
                candidate("tie-a", None, Some(110_000), "zh-CN", "srt"),
                candidate("tie-b", None, Some(110_000), "zh-CN", "srt"),
            ],
            CandidateRankingContext {
                search_name: "documentary episode".into(),
                video_cid: Some("MATCHING-CID".into()),
                video_duration_millis: Some(100_000),
                preferred_languages: vec!["zh-CN".into()],
                preferred_formats: vec!["srt".into()],
            },
        );
        assert_eq!(
            ranked
                .iter()
                .map(|r| r.candidate.id.as_str())
                .collect::<Vec<_>>(),
            vec!["best", "tie-a", "tie-b", "weak"]
        );
        assert_eq!(ranked[0].score, 12_430);
        assert!(ranked[0].score > ranked[1].score);
    }
}
