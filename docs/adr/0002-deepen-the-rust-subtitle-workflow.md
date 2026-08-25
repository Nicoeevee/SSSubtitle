---
status: accepted
---

# Deepen the Rust subtitle workflow behind three asynchronous operations

ADR-0001 assigns Subtitle Provider protocols, normalization, ranking, validation, decoding, and Subtitle Preview pagination to Rust while Flutter owns presentation and platform save/export. The initial implementation did not realize that depth: Flutter still projected and ranked Xunlei results, Rust paginated a complete Subtitle Artifact only for Dart to collect every page and paginate it again, and each Rust page call synchronously retransferred and reparsed the whole Artifact. Replace those shallow interfaces with three strongly typed asynchronous Rust operations for Search, Preview, and Subtitle Artifact materialization. Search returns normalized and ranked Subtitle Candidates with an opaque process-local identity, Match Score, and structured Match Reasons; Preview returns one authoritative page; Artifact materialization returns validated bytes and their typed subtitle format to a Flutter adapter, which hands the Artifact to the platform save/export flow to complete Acquisition.

The Rust implementation consists of a Subtitle Candidate Search module and a Subtitle Preview/Artifact module sharing a private, bounded Candidate/Artifact store. The store owns Provider locators, natural identity eviction, byte-budgeted Artifact caching, and single-flight materialization so concurrent Preview and Acquisition work downloads, validates, and decodes a Candidate once per cached materialization. Xunlei remains the only production Subtitle Provider and sits behind a private true-external transport seam with production and mock adapters; cache controls, Provider selection, ranking weights, and transport types do not cross the FRB seam. Candidate identities survive new searches and successful Preview, Acquisition, or save operations until natural eviction, but are not durable across process or WASM-instance restarts.

All three operations must keep the Flutter UI execution path responsive on Windows and Web; returning a `Future` without production-path evidence is insufficient. Generated bridge types stop at the Dart `RustSubtitleCore` adapter. Flutter localizes structured Match Reasons and failures, preserves only relevant asynchronous completions, and keeps platform saving outside Rust. The migration replaces the old granular search/rank/page calls, Dart bytes cache, all-page collector, and Controller-side second pagination rather than retaining compatibility paths.

## Considered options

- Two entry points with tagged Preview/Acquisition requests and results were rejected because runtime request/result pairing makes the interface harder to learn and test than three strongly typed operations.
- Returning the first Preview inside Search was rejected because Provider discovery and Artifact materialization have independent latency, failure, and retry semantics.
- A public multi-Provider seam was deferred because Xunlei is the only real production Subtitle Provider; the private production/mock transport seam is sufficient for current variation.
- Giving Artifact bytes to the Controller was rejected because generated content and platform-save orchestration would leak into presentation rather than stop at the Flutter adapter.
- Permanent compatibility paths were rejected because they would preserve two production interfaces and two sets of invariants.

## Consequences

- Default tests use a mock Xunlei transport and never depend on the live Provider; live-network checks are explicit and conditional.
- Existing Xunlei protocol, URL-safety, size-limit, encoding, and format invariants remain tested inside the deep implementation, while orchestration is tested through the new interface.
- Windows and Web require production-path smoke evidence through FRB and `RustSubtitleCore`, including UI responsiveness during first Artifact materialization.
- The accepted implementation and completion plan is `docs/agents/subtitle-workflow-deepening.md`.
