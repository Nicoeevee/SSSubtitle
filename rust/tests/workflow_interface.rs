//! Red interface tests for the accepted Rust subtitle workflow.
//!
//! These tests deliberately use `SubtitleWorkflow::with_mock`; the mock is a
//! deterministic Xunlei transport and must never open a network connection.
//! The production FRB functions (`search_subtitles`, `preview_subtitle`, and
//! `acquire_subtitle`) should delegate to the same workflow implementation.
//!
//! These tests are the deterministic public-seam acceptance surface for the
//! replacement workflow. They must not be made green by falling back to
//! `api::xunlei` or by reaching into old synchronous preview/ranking helpers.

use std::future::Future;

use ss_subtitle_core::api::workflow::{
    MatchReasonKind, MockXunleiTransport, SubtitleFailureKind, SubtitleFormat, SubtitleOperation,
    SubtitleWorkflow, WorkflowSubtitlePreviewPage,
};

fn block_on<F: Future>(future: F) -> F::Output {
    tokio::runtime::Runtime::new()
        .expect("the test runtime should start")
        .block_on(future)
}

fn fixture_workflow() -> (MockXunleiTransport, SubtitleWorkflow) {
    let mock = MockXunleiTransport::fixture();
    let workflow = SubtitleWorkflow::with_mock(mock.clone());
    (mock, workflow)
}

fn first_candidate_id(workflow: &SubtitleWorkflow, query: &str) -> String {
    block_on(workflow.search_subtitles(query.to_owned()))
        .expect("the deterministic mock search should succeed")
        .into_iter()
        .next()
        .expect("the deterministic mock should return a Candidate")
        .id
}

fn first_page(workflow: &SubtitleWorkflow, candidate_id: &str) -> WorkflowSubtitlePreviewPage {
    block_on(workflow.preview_subtitle(candidate_id.to_owned(), 1))
        .expect("page one should materialize from the mock")
}

fn acquire_fixture(
    bytes: Vec<u8>,
    extension: &str,
) -> (MockXunleiTransport, SubtitleWorkflow, String) {
    let mock = MockXunleiTransport::single_artifact(bytes, extension);
    let workflow = SubtitleWorkflow::with_mock(mock.clone());
    let candidate_id = first_candidate_id(&workflow, "Fixture");
    (mock, workflow, candidate_id)
}

#[test]
fn search_normalizes_filters_deduplicates_and_returns_ranked_reasons() {
    let workflow = SubtitleWorkflow::with_mock(MockXunleiTransport::fixture());

    let candidates = block_on(workflow.search_subtitles("  Documentary Episode  ".into()))
        .expect("the deterministic mock search should succeed");

    // `fixture` contains one unsupported format and one repeated provider
    // locator.  Only normalized, supported, deduplicated Candidates cross the
    // domain boundary, with stable score ordering and structured reasons.
    assert_eq!(
        candidates
            .iter()
            .map(|candidate| candidate.name.as_str())
            .collect::<Vec<_>>(),
        [
            "Documentary Episode.zh-CN.srt",
            "Documentary Episode.en.srt",
            "Documentary Episode.fr.srt"
        ]
    );
    assert!(candidates[0].match_score >= candidates[1].match_score);
    assert_eq!(
        candidates[0]
            .match_reasons
            .iter()
            .map(|reason| reason.kind)
            .collect::<Vec<_>>(),
        vec![
            MatchReasonKind::TitleContains,
            MatchReasonKind::LanguageMatch,
            MatchReasonKind::FingerprintMatch,
            MatchReasonKind::ProviderScore,
            MatchReasonKind::SupportedFormat,
        ]
    );
    assert_eq!(
        candidates[0].match_reasons[1].value.as_deref(),
        Some("zh-CN")
    );
    assert_eq!(candidates[0].languages, ["zh-CN"]);
    assert_eq!(candidates[1].languages, ["zh-TW"]);
    assert_eq!(candidates[2].languages, ["fr"]);
}

#[test]
fn invalid_search_name_is_structured_and_does_not_call_the_mock_provider() {
    let (mock, workflow) = fixture_workflow();

    let failure = block_on(workflow.search_subtitles(" \t ".into()))
        .expect_err("whitespace-only Suggested Search Name must fail");

    assert_eq!(
        failure.kind,
        SubtitleFailureKind::InvalidSuggestedSearchName
    );
    assert_eq!(mock.search_call_count(), 0);
}

#[test]
fn preview_is_one_authoritative_page_and_acquisition_reuses_materialization() {
    let (mock, workflow) = fixture_workflow();
    let candidate_id = first_candidate_id(&workflow, "Documentary Episode");

    let page = first_page(&workflow, &candidate_id);
    assert_eq!(page.candidate_id, candidate_id);
    assert_eq!(page.page, 1);
    assert!(page.lines.len() <= 30);
    assert!(page.total_pages >= 1);

    let artifact = block_on(workflow.acquire_subtitle(candidate_id.clone()))
        .expect("Acquisition should use the validated mock Artifact");
    assert_eq!(artifact.candidate_id, candidate_id);
    assert_eq!(artifact.format, SubtitleFormat::Srt);
    assert!(!artifact.bytes.is_empty());
    assert_eq!(mock.download_call_count(), 1);

    let later_page = block_on(workflow.preview_subtitle(candidate_id, page.total_pages))
        .expect("an arbitrary valid page should be directly addressable");
    assert_eq!(later_page.page, page.total_pages);
    assert!(later_page.lines.len() <= 30);
    assert_eq!(mock.download_call_count(), 1);
}

#[test]
fn acquisition_first_reuses_materialization_for_preview() {
    let (mock, workflow) = fixture_workflow();
    let candidate_id = first_candidate_id(&workflow, "Documentary Episode");

    let artifact = block_on(workflow.acquire_subtitle(candidate_id.clone()))
        .expect("Acquisition should materialize the mock Artifact");
    let page = block_on(workflow.preview_subtitle(candidate_id, 1))
        .expect("Preview should reuse the acquired Artifact");

    assert_eq!(artifact.format, SubtitleFormat::Srt);
    assert_eq!(page.page, 1);
    assert_eq!(mock.download_call_count(), 1);
    assert_eq!(mock.parse_call_count(), 1);
}

#[test]
fn canonical_materialization_accepts_supported_encodings_and_formats() {
    let utf8 = b"1\n00:00:01 --> 00:00:02\nUTF-8".to_vec();
    let utf8_bom = [vec![0xEF, 0xBB, 0xBF], utf8.clone()].concat();
    let utf16le = [
        vec![0xFF, 0xFE],
        "[Script Info]\nDialogue: 0,0:00:01.00,0:00:02.00,Default,LE"
            .encode_utf16()
            .flat_map(u16::to_le_bytes)
            .collect(),
    ]
    .concat();
    let utf16be = [
        vec![0xFE, 0xFF],
        "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nBE"
            .encode_utf16()
            .flat_map(u16::to_be_bytes)
            .collect(),
    ]
    .concat();
    let (gbk, _, _) = encoding_rs::GBK.encode("1\n00:00:01 --> 00:00:02\n中文");
    let cases = [
        (utf8, "srt", SubtitleFormat::Srt),
        (utf8_bom, "srt", SubtitleFormat::Srt),
        (utf16le, "ass", SubtitleFormat::Ass),
        (utf16be, "vtt", SubtitleFormat::Vtt),
        (gbk.into_owned(), "srt", SubtitleFormat::Srt),
        (
            b"Dialogue: 0,0:00:01.00,0:00:02.00,Default,SSA".to_vec(),
            "ssa",
            SubtitleFormat::Ssa,
        ),
    ];

    for (bytes, extension, expected_format) in cases {
        let (mock, workflow, candidate_id) = acquire_fixture(bytes, extension);
        let artifact = block_on(workflow.acquire_subtitle(candidate_id.clone()))
            .expect("supported encoding and format should materialize");
        let preview = block_on(workflow.preview_subtitle(candidate_id, 1))
            .expect("Preview should use the canonical materialization");

        assert_eq!(artifact.format, expected_format);
        assert!(!preview.lines.is_empty());
        assert_eq!(mock.download_call_count(), 1);
        assert_eq!(mock.parse_call_count(), 1);
    }
}

#[test]
fn canonical_materialization_rejects_html_and_json_documents() {
    for bytes in [
        b"<!doctype html><html>denied</html>".to_vec(),
        br#"{"error":"denied"}"#.to_vec(),
    ] {
        let (mock, workflow, candidate_id) = acquire_fixture(bytes, "srt");
        let failure = block_on(workflow.preview_subtitle(candidate_id, 1))
            .expect_err("error documents must not cross the Preview seam");

        assert_eq!(failure.kind, SubtitleFailureKind::ArtifactInvalid);
        assert_eq!(failure.operation, SubtitleOperation::Preview);
        assert_eq!(mock.download_call_count(), 1);
    }
}

#[test]
fn concurrent_preview_and_acquisition_are_single_flight() {
    let (mock, workflow) = fixture_workflow();
    let candidate_id = first_candidate_id(&workflow, "Documentary Episode");

    let (preview, artifact) = block_on(async {
        futures_util::future::join(
            workflow.preview_subtitle(candidate_id.clone(), 1),
            workflow.acquire_subtitle(candidate_id),
        )
        .await
    });

    assert!(preview.is_ok());
    assert!(artifact.is_ok());
    assert_eq!(mock.download_call_count(), 1);
    assert_eq!(mock.parse_call_count(), 1);
}

#[test]
fn shared_materialization_failure_keeps_each_callers_operation() {
    let mock = MockXunleiTransport::invalid_artifact();
    let workflow = SubtitleWorkflow::with_mock(mock.clone());
    let candidate_id = first_candidate_id(&workflow, "Invalid Artifact");

    let (preview, acquisition) = block_on(async {
        futures_util::future::join(
            workflow.preview_subtitle(candidate_id.clone(), 1),
            workflow.acquire_subtitle(candidate_id),
        )
        .await
    });

    assert_eq!(
        preview
            .expect_err("Preview should reject invalid content")
            .operation,
        SubtitleOperation::Preview
    );
    assert_eq!(
        acquisition
            .expect_err("Acquisition should reject invalid content")
            .operation,
        SubtitleOperation::Acquisition
    );
    assert_eq!(mock.download_call_count(), 1);
}

#[test]
fn artifact_byte_budget_causes_transparent_refetch() {
    let mock = MockXunleiTransport::fixture().with_artifact_budget(2, 1);
    let workflow = SubtitleWorkflow::with_mock(mock.clone());
    let candidate_id = first_candidate_id(&workflow, "Documentary Episode");

    block_on(workflow.preview_subtitle(candidate_id.clone(), 1))
        .expect("Preview should succeed even when its Artifact is too large to cache");
    block_on(workflow.acquire_subtitle(candidate_id))
        .expect("Acquisition should transparently refetch an uncached Artifact");

    assert_eq!(mock.download_call_count(), 2);
    assert_eq!(mock.parse_call_count(), 2);
}

#[test]
fn artifact_entry_eviction_refetches_only_the_oldest_untouched_candidate() {
    let mock = MockXunleiTransport::fixture().with_artifact_budget(2, usize::MAX);
    let workflow = SubtitleWorkflow::with_mock(mock.clone());
    let candidates = block_on(workflow.search_subtitles("Documentary Episode".into()))
        .expect("the deterministic mock search should succeed");
    let first = candidates[0].id.clone();
    let second = candidates[1].id.clone();
    let third = candidates[2].id.clone();

    block_on(workflow.preview_subtitle(first.clone(), 1)).unwrap();
    block_on(workflow.preview_subtitle(second.clone(), 1)).unwrap();
    block_on(workflow.preview_subtitle(first.clone(), 2)).unwrap();
    block_on(workflow.preview_subtitle(third, 1)).unwrap();
    block_on(workflow.preview_subtitle(first, 1)).unwrap();
    block_on(workflow.preview_subtitle(second, 1)).unwrap();

    assert_eq!(mock.download_call_count(), 4);
}

#[test]
fn arbitrary_preview_pages_preserve_every_source_line_in_order() {
    let (_, workflow) = fixture_workflow();
    let candidate_id = first_candidate_id(&workflow, "Documentary Episode");
    let first = first_page(&workflow, &candidate_id);
    let mut lines = Vec::new();
    for page in 1..=first.total_pages {
        lines.extend(
            block_on(workflow.preview_subtitle(candidate_id.clone(), page))
                .expect("every page should be addressable")
                .lines,
        );
    }
    assert_eq!(lines.len(), 93);
    assert_eq!(
        &lines[..4],
        [
            "1",
            "00:00:01,000 --> 00:00:02,000",
            "ZH subtitle line 1",
            "2"
        ]
    );
    assert_eq!(
        &lines[90..],
        ["31", "00:00:01,000 --> 00:00:02,000", "ZH subtitle line 31"]
    );
}

#[test]
fn stable_failures_cover_page_range_invalid_artifact_and_expired_candidate() {
    let (_, workflow) = fixture_workflow();
    let candidate_id = first_candidate_id(&workflow, "Documentary Episode");

    let page = first_page(&workflow, &candidate_id);
    let out_of_range =
        block_on(workflow.preview_subtitle(candidate_id.clone(), page.total_pages + 1))
            .expect_err("a page after the authoritative total must fail");
    assert_eq!(
        out_of_range.kind,
        SubtitleFailureKind::PreviewPageOutOfRange
    );

    let invalid_workflow = SubtitleWorkflow::with_mock(MockXunleiTransport::invalid_artifact());
    let invalid_id = block_on(invalid_workflow.search_subtitles("Invalid Artifact".into()))
        .expect("the invalid-artifact fixture search should succeed")
        .remove(0)
        .id;
    let invalid = block_on(invalid_workflow.acquire_subtitle(invalid_id))
        .expect_err("invalid provider content must be rejected");
    assert_eq!(invalid.kind, SubtitleFailureKind::ArtifactInvalid);

    let unavailable_workflow =
        SubtitleWorkflow::with_mock(MockXunleiTransport::provider_unavailable());
    let unavailable = block_on(unavailable_workflow.search_subtitles("Unavailable".into()))
        .expect_err("provider failure must remain a structured failure");
    assert_eq!(unavailable.kind, SubtitleFailureKind::ProviderUnavailable);

    let too_large_workflow = SubtitleWorkflow::with_mock(MockXunleiTransport::too_large_artifact());
    let too_large_id = block_on(too_large_workflow.search_subtitles("Too Large".into()))
        .expect("the too-large fixture search should succeed")
        .remove(0)
        .id;
    let too_large = block_on(too_large_workflow.acquire_subtitle(too_large_id))
        .expect_err("an over-limit Artifact must be rejected");
    assert_eq!(too_large.kind, SubtitleFailureKind::ArtifactTooLarge);

    let expired_workflow =
        SubtitleWorkflow::with_mock(MockXunleiTransport::fixture().with_candidate_budget(1));
    let first_id = block_on(expired_workflow.search_subtitles("Documentary Episode".into()))
        .expect("the deterministic mock search should succeed")
        .remove(0)
        .id;
    let _ = block_on(expired_workflow.search_subtitles("Second Search".into()))
        .expect("the deterministic mock second search should succeed");
    let expired = block_on(expired_workflow.preview_subtitle(first_id, 1))
        .expect_err("an evicted Candidate identity must not be reused");
    assert_eq!(expired.kind, SubtitleFailureKind::CandidateExpired);
}
