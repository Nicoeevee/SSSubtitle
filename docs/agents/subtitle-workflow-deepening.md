# Rust Subtitle Workflow Deepening Handoff

## Status and authority

The architecture is accepted; implementation has not started. Implement this document as a replacement of the existing production path, not as an alternative path.

Read first:

- `CONTEXT.md` for the canonical domain terms.
- `docs/adr/0001-flutter-platform-shell-rust-subtitle-core.md` for Flutter/Rust ownership.
- `docs/adr/0002-deepen-the-rust-subtitle-workflow.md` for the accepted interface and trade-offs.
- `docs/development.md` for supported platforms, FRB generation, builds, and quality commands.

Do not hand-edit `lib/src/rust/` or `rust/src/frb_generated.rs`; regenerate them after changing the Rust FRB interface.

## Objective

Replace the current shallow Search and Subtitle Preview chain with deep Rust modules so that:

```text
Suggested Search Name
  -> Rust Search
  -> normalized, ranked Subtitle Candidates

opaque Candidate identity + page
  -> Rust Preview
  -> one authoritative Subtitle Preview page

opaque Candidate identity
  -> Rust Artifact materialization
  -> validated Subtitle Artifact
  -> Dart RustSubtitleCore
  -> platform save/export
```

The implementation is complete only when the old production calls, Dart bytes cache, all-page collector, and Controller-side second pagination no longer exist and both Windows and Web satisfy the production-path gates below.

## Scope

### In scope

- Three strongly typed asynchronous Rust operations: Search, Preview, and Subtitle Artifact materialization.
- Rust-owned Provider filtering, deduplication, normalization, stable ranking, Match Score, and structured Match Reasons.
- One authoritative Rust Subtitle Format model for the new path.
- A private Xunlei transport seam with production and deterministic mock adapters.
- A private bounded Candidate/Artifact store with entry and total-byte budgets.
- Single-flight Artifact acquisition for concurrent Preview and Acquisition requests.
- One canonical validation/decode path used by Preview and Acquisition.
- Rust-owned 30-line Subtitle Preview pagination.
- Structured Rust failures and typed Dart failure mapping.
- A thin `RustSubtitleCore` adapter and typed acquisition save outcome.
- Minimal Flutter request-relevance guards for Search, Candidate selection, page changes, and cancel.
- FRB regeneration, test replacement, Windows/Web non-blocking execution, and production-path smoke evidence.
- A final Deslop rescan of every changed hand-written source path.

### Out of scope

- Full Video Profile/CID integration.
- User-configurable ranking preferences or weights.
- A second Subtitle Provider or a public multi-Provider seam.
- Cache inspection, flushing, capacity, or prefetch controls in the external interface.
- Automatic network retries.
- Full `SubtitleController` state-model deepening.
- A general `PlatformSubtitleSaver` refactor.
- General UI refactoring, including the existing duplicate responsive form layout.
- Vendored `rust_builder/cargokit` refactoring.
- Durable Candidate identities across process or WASM-instance restarts.
- Live Xunlei access as a default test or acceptance dependency.

## Target interface contract

The exact Rust names may follow local conventions, but preserve this shape:

```rust
async fn search_subtitles(
    suggested_search_name: String,
) -> Result<Vec<SubtitleCandidate>, SubtitleFailure>;

async fn preview_subtitle(
    candidate_id: SubtitleCandidateId,
    page: u32,
) -> Result<SubtitlePreviewPage, SubtitleFailure>;

async fn acquire_subtitle(
    candidate_id: SubtitleCandidateId,
) -> Result<SubtitleArtifact, SubtitleFailure>;
```

Do not replace the three results with one tagged command/result pair. Search does not fetch the first Preview.

### Subtitle Candidate

Expose only:

- Opaque Candidate identity.
- Display name.
- Normalized language labels.
- Typed Subtitle Format.
- Match Score.
- Ordered structured Match Reasons.

Keep Provider URLs, Xunlei identifiers and payloads, raw ranking inputs, ranking weights, and cache state private. Rust decides which Match Reasons apply and their order; Flutter only localizes them and must not recompute Match Score.

Search accepts only the current Suggested Search Name. Do not add empty optional Video Profile, preference, or Provider fields before a real caller supplies them. Sort by descending Match Score and preserve normalized Provider order for ties.

### Subtitle Preview

The request page and returned page are 1-based. The result contains:

- Candidate identity.
- Authoritative current page.
- Total pages.
- At most 30 lines in source order.

Keep page size, total lines, encoding label, full decoded lines, bytes, and cache state private. Arbitrary valid pages are directly addressable; callers need not request preceding pages.

Preserve the current observable decoding and rejection behavior for UTF-8, UTF-8 BOM, UTF-16LE/BE BOM, GBK, SRT, ASS, SSA, VTT, HTML/JSON error documents, invalid content, and the 20 MiB limit. Treat intentional acceptance-set changes as a separate decision with explicit tests.

### Subtitle Artifact and save

Rust Artifact materialization returns validated bytes and authoritative typed Subtitle Format. It does not return a file name, path, MIME string, save result, or presentation message.

The Dart `RustSubtitleCore` adapter immediately passes the generated Artifact to `PlatformSubtitleSaver` and returns a typed stable outcome such as `Saved` or `Cancelled`. Platform save failure maps to a typed Flutter failure such as `SaveFailed`; it is not a Rust `SubtitleFailure` and must not be reduced to a free-form string or catch-all notice. The Controller does not receive Artifact bytes or generated Artifact types. Flutter derives platform save metadata from the typed format.

### Candidate identity and state

- Candidate identity is opaque and may be passed back only unchanged.
- New Search, Preview, Acquisition, and successful platform save do not consume it.
- It remains valid until natural bounded-store eviction, then returns `CandidateExpired`.
- Artifact eviction while Candidate metadata remains causes a transparent refetch.
- Process or WASM-instance restart may invalidate every identity.
- Concurrent materialization of one Candidate joins one in-flight operation.
- Preview and Acquisition share the same validated bytes and decoded lines.
- Preview, returning to an earlier page, and Acquisition touch Candidate and Artifact recent-use state; a small-budget test must prove a recently used entry is not evicted before an older untouched entry.

The Candidate/Artifact store is private. Its capacities, total-byte budget, recent-use data structure, locks, tasks, and hit/miss state are test-configurable implementation details, not FRB fields.

### Failures and recovery

The stable Rust failure carries an operation/stage, or the Dart adapter attaches equivalent stable operation context at the call site. Recovery must distinguish Search, Preview, and Artifact materialization without parsing an error string. Failure kinds include at least:

- `InvalidSuggestedSearchName`.
- `CandidateExpired`.
- `ProviderUnavailable` with safe network/HTTP/protocol classification.
- `ArtifactTooLarge`.
- `ArtifactInvalid` with safe encoding/format/content classification.
- `PreviewPageOutOfRange`.
- `Internal`.

Do not expose Provider URLs, response bodies, credentials, Subtitle Artifact content, or unstable internal error strings. Map safe details to Rust logging and stable failures to a typed Dart failure view.

Flutter recovery behavior:

| Failure | Recovery |
| --- | --- |
| Invalid Suggested Search Name | Keep the input, show an input error, and do not call the Provider. |
| Search Provider unavailable | Keep the input and allow manual retry. |
| Candidate expired | Clear that Candidate's Preview and ask the user to search again. |
| Artifact too large | Keep the Candidate, treat the current request as non-retryable, and allow another Candidate. Do not create a Flutter-side Candidate blacklist. |
| Artifact invalid | Keep the Candidate, treat the current request as non-retryable, and allow another Candidate. Do not mirror Artifact validity in Flutter state. |
| Transient Preview/Acquisition Provider failure | Keep the Candidate and last successful Preview; allow manual retry. |
| Preview page out of range | Restore page 1 and record safe diagnostics. |
| Internal | Preserve usable state, show a generic failure, and record safe diagnostics. |

Do not add automatic Provider retries in this change.

## Module ownership

Use one FRB-facing Rust subtitle domain entry with two internal deep modules and one shared private store:

```text
FRB subtitle seam
|
+-- Candidate Search module
|   +-- private Xunlei transport port
|   +-- production adapter
|   +-- mock adapter
|   +-- payload normalization
|   +-- ranking and structured Match Reasons
|
+-- Preview / Artifact module
|   +-- Candidate lookup
|   +-- single-flight acquisition
|   +-- validation and decode once
|   +-- Preview page projection
|   `-- Artifact projection
|
`-- private Candidate / Artifact store
    +-- Provider locator registry
    +-- in-flight state
    +-- validated bytes and decoded lines
    `-- entry and byte-budget eviction
```

Xunlei is a true external dependency. Its production and mock transports justify a private seam. Ranking, normalization, validation, decode, pagination, and cache policy are in-process implementation and do not justify external adapters.

## Source entry points

Inspect these hand-written files before editing:

- `rust/src/api/simple.rs`: Suggested Search Name, sampling/CID primitives, current Preview decode/validation/pagination, ranking, and tests.
- `rust/src/api/xunlei.rs`: Provider protocol, opaque registry, download validation, URL safety, and tests.
- `rust/src/api/mod.rs` and `rust/src/lib.rs`: Rust module exports.
- `lib/src/core/subtitle_core.dart`: stable Dart interface, Candidate view, Demo adapter, naming helpers.
- `lib/src/core/rust_subtitle_core.dart`: generated-type adapter, ranking projection, bytes cache, all-page collector, platform save composition.
- `lib/src/controller/subtitle_controller.dart`: current all-lines state, second pagination, async result application.
- `lib/src/ui/subtitle_home_page.dart`: Candidate, Preview page, navigation, failure, and save presentation.
- `lib/src/platform/subtitle_saver.dart`: Flutter-owned platform save implementation.
- `test/rust_subtitle_core_test.dart`, `test/subtitle_controller_test.dart`, `test/subtitle_home_page_test.dart`, and `test/subtitle_saver_test.dart`.
- `integration_test/simple_test.dart`: currently initializes Rust but injects `DemoSubtitleCore`; it is not production-path evidence.

Generated paths are outputs, not editing entry points:

- `lib/src/rust/`.
- `rust/src/frb_generated.rs`.

## Implementation sequence and completion criteria

Each step ends at its criterion. Keep the external replacement atomic even if local development temporarily contains both paths.

### 1. Establish red interface tests

- Add Rust interface tests using a deterministic mock Xunlei transport.
- Cover Search normalization/ranking/reasons, one-page Preview, Acquisition, shared materialization, structured failures, natural eviction, and single-flight.
- Add Flutter tests for page-based fakes and stale Search/Preview/cancel completions.

Complete when the new tests fail for the missing behavior and no test accesses the live Provider.

### 2. Deepen Candidate Search

- Move unsupported Candidate filtering, deduplication, Xunlei-to-domain normalization, default ranking policy, Match Score, and structured Match Reasons behind one Search interface.
- Register only private Provider locators under opaque identities.
- Keep tie ordering stable and reject invalid Suggested Search Names before transport access.

Complete when Search interface tests prove filtering, deduplication, stable ordering, Match Score, and Match Reasons without Dart ranking/projection logic or Provider-specific output fields.

### 3. Create the shared Candidate/Artifact store

- Bound Candidate entries and Artifact bytes separately.
- Represent empty/loading/ready Artifact state so concurrent callers join one load.
- Keep validated original bytes and decoded lines together.
- Make eviction deterministic under test without exposing production cache controls through FRB.
- Touch recent-use state for Preview, returning to an earlier page, and Artifact materialization.

Complete when tests prove one fetch/parse for concurrent Preview/Acquisition, transparent Artifact refetch, recent-use ordering under a small budget, and `CandidateExpired` after Candidate eviction.

### 4. Deepen Preview and Artifact materialization

- Consolidate the current acquisition/Preview validation and decode path needed by this workflow.
- Parse and split once per materialized Artifact.
- Return one 1-based page of at most 30 lines without transferring full bytes or full lines.
- Return validated bytes and typed format for Acquisition.

Complete when encoding/format/security invariants pass through the new module, paging is random-access and lossless, and Preview/Acquisition reuse is observed through the external interface.

### 5. Make Windows and Web execution non-blocking

- Move native CPU-heavy materialization off the Flutter UI execution path.
- Run Web/WASM materialization in a Worker or equivalent execution path that preserves browser event-loop responsiveness.
- Keep the same business interface on both targets.
- Ensure Search, Preview page access, and Artifact materialization all avoid FRB synchronous execution.

Complete when production-path tests observe event progress while Search waits, while a Preview page is requested, and while a near-limit local Artifact is first materialized. A `Future` return type or code inspection alone does not complete this step.

### 6. Regenerate FRB and adapt Dart

- Generate bridge code from the three Rust operations and structured types.
- Keep generated types inside `RustSubtitleCore`.
- Reuse stable Dart Candidate types where they remain the presentation test surface.
- Add stable Preview page, failure, and acquisition outcome views only where the Controller/UI consumes them.
- Keep platform save composition inside `RustSubtitleCore`; Artifact bytes end there.
- Map platform save failure to a typed Flutter failure separate from Rust failures.

Complete when Controller and Widget code imports no generated types, save success/cancel/failure are typed, and the Dart adapter contains no ranking, Match Reason decisions, bytes cache, all-page collection, or pagination.

### 7. Replace Controller and Widget assumptions

- Store only the current authoritative Preview page instead of every decoded line.
- Request explicit pages from `SubtitleCore`.
- Preserve 30-line presentation, `N/M`, keyboard navigation, Candidate reset to page 1, and Saved/Cancelled messages.
- Before applying completions, verify the current Search generation, Candidate identity, requested page, and cancel generation.

Complete when reversed completion order and cancel tests pass without a full Controller state-model refactor.

### 8. Delete the shallow production path

- Remove granular Xunlei/ranking/page FRB calls no longer used by production.
- Remove Dart `_downloadCache`, `_matchReasons`, `collectSubtitlePreviewLines`, and Controller second pagination.
- Remove compatibility selectors and duplicate production routes.
- Replace tests coupled to full-line collection or primitive ranking.

Complete when repository search finds no production caller for the old operations or helper names and every new call passes through the accepted interface.

### 9. Validate the complete replacement

- Run every quality, build, production-path, and Deslop gate below.
- Record observed pass/fail evidence separately for Rust, Flutter, Windows, Web, and optional live-network smoke.

Complete only when every required gate passes. A focused unit test, successful code generation, or one platform build does not complete the change.

## Test replacement matrix

| Existing test surface | Required action |
| --- | --- |
| `collectSubtitlePreviewLines` helper test | Delete with the helper. |
| Controller/Widget fakes returning 45/65 complete lines | Replace with explicit `SubtitlePreviewPage` responses. |
| Controller-side 2/3-page slicing assertions | Replace with requested page, authoritative page, total pages, and call-count assertions. |
| Primitive ranking tests | Migrate observable ranking and reasons to Search interface tests; retain only non-duplicated private invariants. |
| Existing Provider result projection | Add Search interface tests for unsupported Candidate filtering and deduplication before deleting the Dart projection. |
| Xunlei payload and URL safety tests | Keep as internal security invariants. |
| Encoding and subtitle format tests | Keep/move to the canonical Artifact path and also cover the external Preview result. |
| Existing integration test using `DemoSubtitleCore` | Keep as a shell test if useful, but add separate production-path FRB smoke; do not relabel it as production evidence. |

Add tests for:

- Stable Search ordering and structured Match Reasons.
- Unsupported Candidate filtering and Candidate deduplication.
- First, last, and out-of-range Preview pages.
- Line order without duplication or loss.
- Preview then Acquisition and Acquisition then Preview reuse.
- Concurrent single-flight materialization.
- Artifact and Candidate eviction semantics.
- Recent-use touch ordering under a small test budget.
- Every stable failure kind and Flutter recovery mapping.
- Platform save success, cancellation, and typed Flutter save failure.
- Reversed Search/Preview completion and cancel relevance.
- Native and Web production-path responsiveness.

## Deslop gate

Before writing each new function, method, class, helper, fixture, parser branch, error type, store type, Worker glue path, or test setup larger than a few lines, call Deslop `find-similar` with the proposed snippet or existing byte range. Reuse the canonical occurrence for `fused >= 0.85` and `identical`/`nearly_identical` results; inspect borderline matches before deciding.

Do not create a second decoder, format validator, pagination helper, bytes cache, ranking projection, or candidate mapper. Treat the current hash-encoding and path-normalization matches according to domain meaning, not AST shape alone. Vendored `rust_builder/cargokit` findings are outside this scope.

After implementation, rescan every changed hand-written source path. Existing unrelated clusters need not be removed, but the change must introduce no new high-confidence clone.

## Required validation

Run the repository quality gates from `docs/development.md`:

```powershell
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test

Set-Location rust
cargo fmt --all -- --check
cargo test
cargo clippy --all-targets -- -D warnings
```

Regenerate the bridge after Rust interface changes:

```powershell
flutter_rust_bridge_codegen generate
```

### Windows

- Build release with `flutter build windows --release`.
- Run an offline production-path smoke through native FRB and `RustSubtitleCore`.
- Cover Search, page 1, another page, return to page 1, Candidate switch, Acquisition, save success, and save cancellation.
- Prove heartbeat/frame/event progress while Search waits, while a page is requested, and during first materialization of a near-limit fixture.

### Web

- Run `flutter_rust_bridge_codegen build-web --release`.
- Build with `flutter build web --release`.
- Use the COOP/COEP headers documented in `docs/development.md`.
- Run an offline production-path smoke through the actual WASM/Worker and `RustSubtitleCore`.
- Cover the same Search/Preview/Acquisition path and prove browser main-event-loop progress during first materialization.
- Observe browser event progress while Search waits and while a Preview page is requested, not only during Artifact materialization.
- Prove Preview and Acquisition do not repeat acquisition or parsing.

Live Xunlei access is optional and conditional on Provider availability and CORS. Report it separately; it never substitutes for or blocks deterministic offline acceptance.

## Final handoff checklist

- [ ] ADR-0002 remains satisfied without an undocumented exception.
- [ ] Exactly three strongly typed asynchronous Rust operations form the production subtitle interface.
- [ ] Rust owns normalization, ranking, structured Match Reasons, validation, decode, and pagination.
- [ ] Xunlei transport and Provider locators remain private.
- [ ] Candidate and Artifact state is bounded; concurrent materialization is single-flight.
- [ ] Flutter owns localization and platform save; Artifact bytes stop inside `RustSubtitleCore`.
- [ ] Controller applies only relevant asynchronous completions.
- [ ] Old production paths and implementation-coupled tests are deleted.
- [ ] Default tests perform no live network access.
- [ ] Rust, Flutter, Windows, Web, and Deslop gates each have observed evidence.
- [ ] The working-tree diff contains only this feature and regenerated bridge outputs.
