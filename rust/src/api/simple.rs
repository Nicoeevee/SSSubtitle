pub const SAMPLE_SIZE: u64 = 0x5000;

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

pub(crate) fn decode_subtitle(bytes: &[u8]) -> Result<(String, String), String> {
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

pub(crate) fn validate_subtitle_text(text: &str, format: &str) -> Result<(), String> {
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

pub(crate) fn normalized_title(value: &str) -> String {
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
}
