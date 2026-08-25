use std::collections::HashSet;

use ss_subtitle_core::api::workflow::{
    acquire_subtitle, preview_subtitle, search_subtitles, MatchReasonKind, SubtitleFormat,
};

const LIVE_ENV: &str = "SSSUBTITLE_LIVE_XUNLEI";
const MAX_ARTIFACT_BYTES: usize = 20 * 1024 * 1024;

#[tokio::test(flavor = "multi_thread")]
#[ignore = "requires explicit live Xunlei network access"]
async fn real_movie_and_tv_queries_cross_the_production_workflow() {
    assert_eq!(std::env::var(LIVE_ENV).as_deref(), Ok("1"));

    for suggested_search_name in ["Interstellar", "Breaking Bad S01E01"] {
        let candidates = search_subtitles(suggested_search_name.to_owned())
            .await
            .expect("live Xunlei Search should succeed");
        assert!(!candidates.is_empty());

        let mut ids = HashSet::new();
        for pair in candidates.windows(2) {
            assert!(pair[0].match_score >= pair[1].match_score);
        }
        for candidate in &candidates {
            assert!(!candidate.id.is_empty());
            assert!(!candidate.name.trim().is_empty());
            assert!(ids.insert(candidate.id.as_str()));
            assert!(candidate
                .match_reasons
                .iter()
                .any(|reason| reason.kind == MatchReasonKind::SupportedFormat));
            assert!(candidate
                .languages
                .iter()
                .all(|language| !matches!(language.as_str(), "简体" | "繁体" | "chs" | "cht")));
        }

        for candidate in candidates.iter().take(3) {
            println!(
                "{suggested_search_name}: name={:?}, languages={:?}, format={:?}, score={}, reasons={:?}",
                candidate.name,
                candidate.languages,
                candidate.format,
                candidate.match_score,
                candidate
                    .match_reasons
                    .iter()
                    .map(|reason| reason.kind)
                    .collect::<Vec<_>>()
            );
        }

        let mut selected = None;
        for candidate in candidates.into_iter().take(3) {
            match preview_subtitle(candidate.id.clone(), 1).await {
                Ok(preview) => {
                    selected = Some((candidate, preview));
                    break;
                }
                Err(failure) => {
                    eprintln!(
                        "{suggested_search_name}: preview candidate failed: operation={:?}, kind={:?}",
                        failure.operation, failure.kind
                    );
                }
            }
        }
        let (candidate, preview) =
            selected.expect("one of the first three Candidates should preview");
        assert_eq!(preview.candidate_id, candidate.id);
        assert_eq!(preview.page, 1);
        assert!(preview.lines.len() <= 30);
        assert!(preview.total_pages >= 1);

        let artifact = acquire_subtitle(candidate.id.clone())
            .await
            .expect("the previewed live Candidate should be acquired");
        assert_eq!(artifact.candidate_id, candidate.id);
        assert_eq!(artifact.format, candidate.format);
        assert!((8..=MAX_ARTIFACT_BYTES).contains(&artifact.bytes.len()));
        assert!(matches!(
            artifact.format,
            SubtitleFormat::Srt | SubtitleFormat::Ass | SubtitleFormat::Ssa | SubtitleFormat::Vtt
        ));
    }
}
