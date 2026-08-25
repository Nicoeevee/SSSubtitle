use crate::api::simple;
#[cfg(all(not(frb_expand), not(feature = "offline-smoke")))]
use crate::api::xunlei;
use futures_util::future::{FutureExt, Shared};
#[cfg(target_family = "wasm")]
use std::cell::{BorrowMutError, OnceCell, RefCell, RefMut};
use std::collections::{HashMap, HashSet, VecDeque};
use std::fmt::{Display, Formatter};
use std::future::Future;
#[cfg(target_family = "wasm")]
use std::rc::Rc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
#[cfg(not(target_family = "wasm"))]
use std::sync::{Mutex, OnceLock};
#[cfg(all(not(frb_expand), not(feature = "offline-smoke")))]
use std::task::Poll;

const DEFAULT_CANDIDATE_CAPACITY: usize = 4_096;
const DEFAULT_ARTIFACT_CAPACITY: usize = 128;
const DEFAULT_ARTIFACT_BYTES: usize = 64 * 1024 * 1024;
const PREVIEW_PAGE_SIZE: u32 = 30;

#[cfg(not(target_family = "wasm"))]
type WorkflowBoxFuture<'a, T> = futures_util::future::BoxFuture<'a, T>;

#[cfg(target_family = "wasm")]
type WorkflowBoxFuture<'a, T> = futures_util::future::LocalBoxFuture<'a, T>;

#[cfg(not(target_family = "wasm"))]
fn boxed_workflow_future<'a, F, T>(future: F) -> WorkflowBoxFuture<'a, T>
where
    F: Future<Output = T> + Send + 'a,
{
    future.boxed()
}

#[cfg(target_family = "wasm")]
fn boxed_workflow_future<'a, F, T>(future: F) -> WorkflowBoxFuture<'a, T>
where
    F: Future<Output = T> + 'a,
{
    future.boxed_local()
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SubtitleFormat {
    Srt,
    Ass,
    Ssa,
    Vtt,
}

impl SubtitleFormat {
    pub(crate) fn parse(value: &str) -> Option<Self> {
        match value
            .trim()
            .trim_start_matches('.')
            .to_ascii_lowercase()
            .as_str()
        {
            "srt" => Some(Self::Srt),
            "ass" => Some(Self::Ass),
            "ssa" => Some(Self::Ssa),
            "vtt" => Some(Self::Vtt),
            _ => None,
        }
    }

    pub(crate) fn as_str(self) -> &'static str {
        match self {
            Self::Srt => "srt",
            Self::Ass => "ass",
            Self::Ssa => "ssa",
            Self::Vtt => "vtt",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MatchReason {
    pub kind: MatchReasonKind,
    pub value: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MatchReasonKind {
    ExactTitle,
    TitleContains,
    LanguageMatch,
    ProviderScore,
    FingerprintMatch,
    SupportedFormat,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkflowSubtitleCandidate {
    pub id: String,
    pub name: String,
    pub languages: Vec<String>,
    pub format: SubtitleFormat,
    pub match_score: i64,
    pub match_reasons: Vec<MatchReason>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkflowSubtitlePreviewPage {
    pub candidate_id: String,
    pub lines: Vec<String>,
    pub page: u32,
    pub total_pages: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SubtitleArtifact {
    pub candidate_id: String,
    pub bytes: Vec<u8>,
    pub format: SubtitleFormat,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SubtitleOperation {
    Search,
    Preview,
    Acquisition,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SubtitleFailureKind {
    InvalidSuggestedSearchName,
    CandidateExpired,
    ProviderUnavailable,
    ArtifactTooLarge,
    ArtifactInvalid,
    PreviewPageOutOfRange,
    Internal,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SubtitleFailure {
    pub operation: SubtitleOperation,
    pub kind: SubtitleFailureKind,
    pub detail: Option<String>,
}

impl SubtitleFailure {
    fn new(
        operation: SubtitleOperation,
        kind: SubtitleFailureKind,
        detail: impl Into<Option<String>>,
    ) -> Self {
        Self {
            operation,
            kind,
            detail: detail.into(),
        }
    }
}

impl Display for SubtitleFailure {
    fn fmt(&self, formatter: &mut Formatter<'_>) -> std::fmt::Result {
        write!(formatter, "{:?}: {:?}", self.operation, self.kind)
    }
}

impl std::error::Error for SubtitleFailure {}

#[flutter_rust_bridge::frb(ignore)]
#[derive(Debug, Clone)]
#[cfg(not(frb_expand))]
struct ProviderCandidate {
    pub(crate) locator: String,
    pub(crate) name: String,
    pub(crate) extension: String,
    pub(crate) languages: Vec<String>,
    pub(crate) upstream_score: Option<f64>,
    pub(crate) fingerprint_score: Option<f64>,
}

#[flutter_rust_bridge::frb(ignore)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[cfg(not(frb_expand))]
enum ProviderFailure {
    Network,
    Http(u16),
    Protocol,
    ArtifactTooLarge,
}

#[flutter_rust_bridge::frb(ignore)]
#[cfg(not(frb_expand))]
trait XunleiTransport: Send + Sync {
    fn search(
        &self,
        query: String,
    ) -> WorkflowBoxFuture<'static, Result<Vec<ProviderCandidate>, ProviderFailure>>;

    fn download(
        &self,
        locator: String,
    ) -> WorkflowBoxFuture<'static, Result<Vec<u8>, ProviderFailure>>;
}

#[derive(Debug, Clone)]
#[cfg(not(frb_expand))]
struct CandidateRecord {
    locator: String,
    candidate: WorkflowSubtitleCandidate,
}

#[derive(Debug, Clone)]
#[cfg(not(frb_expand))]
struct MaterializedArtifact {
    bytes: Arc<Vec<u8>>,
    lines: Arc<Vec<String>>,
    format: SubtitleFormat,
}

#[cfg(not(frb_expand))]
type Materialization =
    Shared<WorkflowBoxFuture<'static, Result<Arc<MaterializedArtifact>, MaterializationFailure>>>;

#[cfg(not(frb_expand))]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum MaterializationFailure {
    ProviderNetwork,
    ProviderHttp,
    ProviderProtocol,
    ArtifactTooLarge,
    ArtifactInvalid,
    Internal,
}

#[cfg(not(frb_expand))]
impl MaterializationFailure {
    fn into_subtitle_failure(self, operation: SubtitleOperation) -> SubtitleFailure {
        let (kind, detail) = match self {
            Self::ProviderNetwork => (SubtitleFailureKind::ProviderUnavailable, Some("network")),
            Self::ProviderHttp => (SubtitleFailureKind::ProviderUnavailable, Some("http")),
            Self::ProviderProtocol => (SubtitleFailureKind::ProviderUnavailable, Some("protocol")),
            Self::ArtifactTooLarge => (SubtitleFailureKind::ArtifactTooLarge, None),
            Self::ArtifactInvalid => (SubtitleFailureKind::ArtifactInvalid, None),
            Self::Internal => (SubtitleFailureKind::Internal, None),
        };
        SubtitleFailure::new(operation, kind, detail.map(str::to_owned))
    }
}

#[cfg(not(frb_expand))]
impl From<ProviderFailure> for MaterializationFailure {
    fn from(failure: ProviderFailure) -> Self {
        match failure {
            ProviderFailure::Network => Self::ProviderNetwork,
            ProviderFailure::Http(_) => Self::ProviderHttp,
            ProviderFailure::Protocol => Self::ProviderProtocol,
            ProviderFailure::ArtifactTooLarge => Self::ArtifactTooLarge,
        }
    }
}

#[cfg(not(frb_expand))]
impl From<SubtitleFailureKind> for MaterializationFailure {
    fn from(kind: SubtitleFailureKind) -> Self {
        match kind {
            SubtitleFailureKind::ArtifactTooLarge => Self::ArtifactTooLarge,
            SubtitleFailureKind::ArtifactInvalid => Self::ArtifactInvalid,
            SubtitleFailureKind::Internal => Self::Internal,
            _ => Self::Internal,
        }
    }
}

#[flutter_rust_bridge::frb(ignore)]
#[derive(Debug, Clone, Copy)]
#[cfg(not(frb_expand))]
struct StoreConfig {
    pub(crate) candidate_capacity: usize,
    pub(crate) artifact_capacity: usize,
    pub(crate) artifact_byte_capacity: usize,
}

#[cfg(not(frb_expand))]
impl Default for StoreConfig {
    fn default() -> Self {
        Self {
            candidate_capacity: DEFAULT_CANDIDATE_CAPACITY,
            artifact_capacity: DEFAULT_ARTIFACT_CAPACITY,
            artifact_byte_capacity: DEFAULT_ARTIFACT_BYTES,
        }
    }
}

#[cfg(not(frb_expand))]
struct WorkflowStore {
    candidates: HashMap<String, CandidateRecord>,
    candidate_order: VecDeque<String>,
    artifacts: HashMap<String, MaterializedArtifact>,
    artifact_order: VecDeque<String>,
    artifact_bytes: usize,
    in_flight: HashMap<String, Materialization>,
    config: StoreConfig,
}

#[cfg(not(frb_expand))]
impl WorkflowStore {
    fn new(config: StoreConfig) -> Self {
        Self {
            candidates: HashMap::new(),
            candidate_order: VecDeque::new(),
            artifacts: HashMap::new(),
            artifact_order: VecDeque::new(),
            artifact_bytes: 0,
            in_flight: HashMap::new(),
            config,
        }
    }

    fn insert_candidate(&mut self, id: String, record: CandidateRecord) {
        self.candidate_order.retain(|existing| existing != &id);
        self.candidates.insert(id.clone(), record);
        self.candidate_order.push_back(id);
        while self.candidates.len() > self.config.candidate_capacity {
            let Some(expired_id) = self.candidate_order.pop_front() else {
                break;
            };
            self.candidates.remove(&expired_id);
            self.remove_artifact(&expired_id);
        }
    }

    fn touch_candidate(&mut self, id: &str) {
        if self.candidates.contains_key(id) {
            self.candidate_order.retain(|existing| existing != id);
            self.candidate_order.push_back(id.to_owned());
        }
    }

    fn touch_artifact(&mut self, id: &str) {
        self.artifact_order.retain(|existing| existing != id);
        self.artifact_order.push_back(id.to_owned());
    }

    fn insert_artifact(&mut self, id: String, artifact: MaterializedArtifact) {
        self.remove_artifact(&id);
        let size = artifact.bytes.len();
        if size > self.config.artifact_byte_capacity || self.config.artifact_capacity == 0 {
            return;
        }
        self.artifact_bytes = self.artifact_bytes.saturating_add(size);
        self.artifacts.insert(id.clone(), artifact);
        self.artifact_order.push_back(id);
        while self.artifacts.len() > self.config.artifact_capacity
            || self.artifact_bytes > self.config.artifact_byte_capacity
        {
            let Some(expired_id) = self.artifact_order.pop_front() else {
                break;
            };
            self.remove_artifact(&expired_id);
        }
    }

    fn remove_artifact(&mut self, id: &str) {
        if let Some(artifact) = self.artifacts.remove(id) {
            self.artifact_bytes = self.artifact_bytes.saturating_sub(artifact.bytes.len());
        }
        self.artifact_order.retain(|existing| existing != id);
    }
}

#[cfg(all(not(frb_expand), not(target_family = "wasm")))]
#[derive(Clone)]
struct WorkflowStoreHandle(Arc<Mutex<WorkflowStore>>);

#[cfg(all(not(frb_expand), not(target_family = "wasm")))]
impl WorkflowStoreHandle {
    fn new(store: WorkflowStore) -> Self {
        Self(Arc::new(Mutex::new(store)))
    }

    fn lock(&self) -> std::sync::LockResult<std::sync::MutexGuard<'_, WorkflowStore>> {
        self.0.lock()
    }
}

#[cfg(all(not(frb_expand), target_family = "wasm"))]
#[derive(Clone)]
struct WorkflowStoreHandle(Rc<RefCell<WorkflowStore>>);

#[cfg(all(not(frb_expand), target_family = "wasm"))]
impl WorkflowStoreHandle {
    fn new(store: WorkflowStore) -> Self {
        Self(Rc::new(RefCell::new(store)))
    }

    fn lock(&self) -> Result<RefMut<'_, WorkflowStore>, BorrowMutError> {
        self.0.try_borrow_mut()
    }
}

#[cfg(all(not(frb_expand), not(target_family = "wasm")))]
type WorkflowTransportHandle = Arc<dyn XunleiTransport>;

#[cfg(all(not(frb_expand), target_family = "wasm"))]
type WorkflowTransportHandle = Rc<dyn XunleiTransport>;

#[cfg(all(not(frb_expand), not(target_family = "wasm")))]
fn transport_handle<T: XunleiTransport + 'static>(transport: T) -> WorkflowTransportHandle {
    Arc::new(transport)
}

#[cfg(all(not(frb_expand), target_family = "wasm"))]
fn transport_handle<T: XunleiTransport + 'static>(transport: T) -> WorkflowTransportHandle {
    Rc::new(transport)
}

#[flutter_rust_bridge::frb(ignore)]
#[cfg(not(frb_expand))]
#[derive(Clone)]
pub struct SubtitleWorkflow {
    transport: WorkflowTransportHandle,
    store: WorkflowStoreHandle,
}

#[cfg(not(frb_expand))]
struct MockState {
    candidates: Vec<ProviderCandidate>,
    artifacts: HashMap<String, Vec<u8>>,
    search_calls: AtomicUsize,
    download_calls: AtomicUsize,
    parse_calls: AtomicUsize,
}

#[derive(Clone)]
#[flutter_rust_bridge::frb(ignore)]
#[cfg(not(frb_expand))]
pub struct MockXunleiTransport {
    state: Arc<MockState>,
    candidate_capacity: usize,
    artifact_capacity: usize,
    artifact_byte_capacity: usize,
    search_failure: Option<ProviderFailure>,
    oversized_artifact: bool,
    yield_steps: usize,
}

#[cfg(not(frb_expand))]
impl MockXunleiTransport {
    pub fn fixture() -> Self {
        let zh_locator = "mock://subtitle/documentary-zh".to_owned();
        let en_locator = "mock://subtitle/documentary-en".to_owned();
        let fr_locator = "mock://subtitle/documentary-fr".to_owned();
        let candidates = vec![
            ProviderCandidate {
                locator: zh_locator.clone(),
                name: "Documentary Episode.zh-CN.srt".to_owned(),
                extension: "srt".to_owned(),
                languages: vec!["简体".to_owned()],
                upstream_score: Some(98.0),
                fingerprint_score: Some(1.0),
            },
            ProviderCandidate {
                locator: zh_locator.clone(),
                name: "duplicate-provider-entry.srt".to_owned(),
                extension: "srt".to_owned(),
                languages: vec!["简体".to_owned()],
                upstream_score: Some(1.0),
                fingerprint_score: None,
            },
            ProviderCandidate {
                locator: en_locator.clone(),
                name: "Documentary Episode.en.srt".to_owned(),
                extension: "srt".to_owned(),
                languages: vec!["繁体".to_owned()],
                upstream_score: Some(20.0),
                fingerprint_score: None,
            },
            ProviderCandidate {
                locator: fr_locator.clone(),
                name: "Documentary Episode.fr.srt".to_owned(),
                extension: "srt".to_owned(),
                languages: vec!["fr".to_owned()],
                upstream_score: Some(5.0),
                fingerprint_score: None,
            },
            ProviderCandidate {
                locator: "mock://subtitle/unsupported".to_owned(),
                name: "Documentary Episode.exe".to_owned(),
                extension: "exe".to_owned(),
                languages: vec![],
                upstream_score: Some(100.0),
                fingerprint_score: None,
            },
        ];
        let artifacts = HashMap::from([
            (zh_locator, fixture_srt_bytes("ZH")),
            (en_locator, fixture_srt_bytes("EN")),
            (fr_locator, fixture_srt_bytes("FR")),
        ]);
        Self::from_parts(candidates, artifacts)
    }

    pub fn invalid_artifact() -> Self {
        let locator = "mock://subtitle/invalid".to_owned();
        Self::from_parts(
            vec![ProviderCandidate {
                locator: locator.clone(),
                name: "Invalid Artifact.srt".to_owned(),
                extension: "srt".to_owned(),
                languages: vec!["en".to_owned()],
                upstream_score: None,
                fingerprint_score: None,
            }],
            HashMap::from([(locator, b"not a subtitle".to_vec())]),
        )
    }

    pub fn single_artifact(bytes: Vec<u8>, extension: &str) -> Self {
        let extension = extension.trim().trim_start_matches('.').to_owned();
        let locator = "mock://subtitle/single".to_owned();
        Self::from_parts(
            vec![ProviderCandidate {
                locator: locator.clone(),
                name: format!("Fixture.{extension}"),
                extension,
                languages: vec!["en".to_owned()],
                upstream_score: None,
                fingerprint_score: None,
            }],
            HashMap::from([(locator, bytes)]),
        )
    }

    pub fn provider_unavailable() -> Self {
        let mut mock = Self::from_parts(Vec::new(), HashMap::new());
        mock.search_failure = Some(ProviderFailure::Network);
        mock
    }

    pub fn too_large_artifact() -> Self {
        let locator = "mock://subtitle/too-large".to_owned();
        let mut mock = Self::from_parts(
            vec![ProviderCandidate {
                locator,
                name: "Too Large.srt".to_owned(),
                extension: "srt".to_owned(),
                languages: vec!["en".to_owned()],
                upstream_score: None,
                fingerprint_score: None,
            }],
            HashMap::new(),
        );
        mock.oversized_artifact = true;
        mock
    }

    #[cfg(feature = "offline-smoke")]
    pub fn offline_smoke() -> Self {
        let base = Self::fixture();
        let locator = "mock://subtitle/near-limit".to_owned();
        let mut candidates = base.state.candidates.clone();
        candidates.push(ProviderCandidate {
            locator: locator.clone(),
            name: "Near Limit Fixture.srt".to_owned(),
            extension: "srt".to_owned(),
            languages: vec!["en".to_owned()],
            upstream_score: Some(90.0),
            fingerprint_score: None,
        });
        let mut artifacts = base.state.artifacts.clone();
        artifacts.insert(locator, near_limit_srt_bytes());
        Self::from_parts(candidates, artifacts).with_yield_steps(8)
    }

    pub fn with_candidate_budget(mut self, capacity: usize) -> Self {
        self.candidate_capacity = capacity;
        self
    }

    pub fn with_artifact_budget(mut self, entries: usize, bytes: usize) -> Self {
        self.artifact_capacity = entries;
        self.artifact_byte_capacity = bytes;
        self
    }

    pub fn with_yield_steps(mut self, steps: usize) -> Self {
        self.yield_steps = steps;
        self
    }

    pub fn search_call_count(&self) -> usize {
        self.state.search_calls.load(Ordering::SeqCst)
    }

    pub fn download_call_count(&self) -> usize {
        self.state.download_calls.load(Ordering::SeqCst)
    }

    pub fn parse_call_count(&self) -> usize {
        self.state.parse_calls.load(Ordering::SeqCst)
    }

    fn from_parts(candidates: Vec<ProviderCandidate>, artifacts: HashMap<String, Vec<u8>>) -> Self {
        Self {
            state: Arc::new(MockState {
                candidates,
                artifacts,
                search_calls: AtomicUsize::new(0),
                download_calls: AtomicUsize::new(0),
                parse_calls: AtomicUsize::new(0),
            }),
            candidate_capacity: DEFAULT_CANDIDATE_CAPACITY,
            artifact_capacity: DEFAULT_ARTIFACT_CAPACITY,
            artifact_byte_capacity: DEFAULT_ARTIFACT_BYTES,
            search_failure: None,
            oversized_artifact: false,
            yield_steps: 1,
        }
    }
}

#[cfg(not(frb_expand))]
impl XunleiTransport for MockXunleiTransport {
    fn search(
        &self,
        _query: String,
    ) -> WorkflowBoxFuture<'static, Result<Vec<ProviderCandidate>, ProviderFailure>> {
        let state = self.state.clone();
        let search_failure = self.search_failure;
        let yield_steps = self.yield_steps;
        boxed_workflow_future(async move {
            state.search_calls.fetch_add(1, Ordering::SeqCst);
            yield_pending_steps(yield_steps).await;
            if let Some(failure) = search_failure {
                return Err(failure);
            }
            Ok(state.candidates.clone())
        })
    }

    fn download(
        &self,
        locator: String,
    ) -> WorkflowBoxFuture<'static, Result<Vec<u8>, ProviderFailure>> {
        let state = self.state.clone();
        let oversized_artifact = self.oversized_artifact;
        let yield_steps = self.yield_steps;
        boxed_workflow_future(async move {
            state.download_calls.fetch_add(1, Ordering::SeqCst);
            state.parse_calls.fetch_add(1, Ordering::SeqCst);
            yield_pending_steps(yield_steps).await;
            if oversized_artifact {
                return Ok(vec![0u8; 20 * 1024 * 1024 + 1]);
            }
            state
                .artifacts
                .get(&locator)
                .cloned()
                .ok_or(ProviderFailure::Network)
        })
    }
}

#[cfg(not(frb_expand))]
fn fixture_srt_bytes(prefix: &str) -> Vec<u8> {
    (1..=31)
        .map(|line| format!("{line}\n00:00:01,000 --> 00:00:02,000\n{prefix} subtitle line {line}"))
        .collect::<Vec<_>>()
        .join("\n")
        .into_bytes()
}

#[cfg(all(not(frb_expand), not(feature = "offline-smoke")))]
async fn yield_pending_steps(mut remaining: usize) {
    futures_util::future::poll_fn(move |context| {
        if remaining == 0 {
            Poll::Ready(())
        } else {
            remaining -= 1;
            context.waker().wake_by_ref();
            Poll::Pending
        }
    })
    .await;
}

#[cfg(all(not(frb_expand), feature = "offline-smoke"))]
async fn yield_pending_steps(_remaining: usize) {
    futures_timer::Delay::new(std::time::Duration::from_millis(5)).await;
}

#[cfg(all(not(frb_expand), feature = "offline-smoke"))]
fn near_limit_srt_bytes() -> Vec<u8> {
    const TARGET_BYTES: usize = 19 * 1024 * 1024;
    let line = b"1\n00:00:01,000 --> 00:00:02,000\nNear-limit fixture\n\n";
    let mut bytes = Vec::with_capacity(TARGET_BYTES);
    while bytes.len() + line.len() <= TARGET_BYTES {
        bytes.extend_from_slice(line);
    }
    bytes
}

#[cfg(not(frb_expand))]
impl SubtitleWorkflow {
    fn with_transport(transport: WorkflowTransportHandle, config: StoreConfig) -> Self {
        Self {
            transport,
            store: WorkflowStoreHandle::new(WorkflowStore::new(config)),
        }
    }

    #[cfg(not(frb_expand))]
    pub fn with_mock(mock: MockXunleiTransport) -> Self {
        Self::with_transport(
            transport_handle(mock.clone()),
            StoreConfig {
                candidate_capacity: mock.candidate_capacity,
                artifact_capacity: mock.artifact_capacity,
                artifact_byte_capacity: mock.artifact_byte_capacity,
            },
        )
    }

    pub async fn search_subtitles(
        &self,
        suggested_search_name: String,
    ) -> Result<Vec<WorkflowSubtitleCandidate>, SubtitleFailure> {
        let query = suggested_search_name.trim().to_owned();
        if query.is_empty() || query.chars().count() > 512 {
            return Err(SubtitleFailure::new(
                SubtitleOperation::Search,
                SubtitleFailureKind::InvalidSuggestedSearchName,
                Some("empty_or_too_long".to_owned()),
            ));
        }

        let provider_candidates = self
            .transport
            .search(query.clone())
            .await
            .map_err(|failure| provider_failure(SubtitleOperation::Search, failure))?;
        let mut seen_locators = HashSet::new();
        let mut pending = Vec::new();

        for provider in provider_candidates {
            let Some(format) = SubtitleFormat::parse(&provider.extension) else {
                continue;
            };
            let name = provider.name.trim().to_owned();
            let locator = provider.locator.trim().to_owned();
            if name.is_empty() || locator.is_empty() || !seen_locators.insert(locator.clone()) {
                continue;
            }
            let id = stable_candidate_id(&locator);
            let languages = normalize_languages(&provider.languages);
            let score = provider_match_score(&provider, &query, &languages, format);
            pending.push((score, id, provider, name, languages, format, locator));
        }

        pending.sort_by_key(|entry| std::cmp::Reverse(entry.0));
        let mut result = Vec::with_capacity(pending.len());
        let mut store = self
            .store
            .lock()
            .map_err(|_| internal_failure(SubtitleOperation::Search))?;

        for (score, id, provider, name, languages, format, locator) in pending {
            let reasons = match_reasons(&provider, &query, &name, &languages, format);
            let candidate = WorkflowSubtitleCandidate {
                id: id.clone(),
                name,
                languages,
                format,
                match_score: score,
                match_reasons: reasons,
            };
            store.insert_candidate(
                id,
                CandidateRecord {
                    locator,
                    candidate: candidate.clone(),
                },
            );
            result.push(candidate);
        }
        Ok(result)
    }

    pub async fn preview_subtitle(
        &self,
        candidate_id: String,
        page: u32,
    ) -> Result<WorkflowSubtitlePreviewPage, SubtitleFailure> {
        #[cfg(feature = "offline-smoke")]
        yield_pending_steps(1).await;
        if page == 0 {
            return Err(SubtitleFailure::new(
                SubtitleOperation::Preview,
                SubtitleFailureKind::PreviewPageOutOfRange,
                Some("page_starts_at_one".to_owned()),
            ));
        }
        let artifact = self
            .materialize(&candidate_id, SubtitleOperation::Preview)
            .await?;
        let total_lines = artifact.lines.len() as u32;
        let total_pages = total_lines.max(1).div_ceil(PREVIEW_PAGE_SIZE);
        if page > total_pages {
            return Err(SubtitleFailure::new(
                SubtitleOperation::Preview,
                SubtitleFailureKind::PreviewPageOutOfRange,
                Some(format!("total_pages:{total_pages}")),
            ));
        }
        let start = ((page - 1) * PREVIEW_PAGE_SIZE) as usize;
        let end = (start + PREVIEW_PAGE_SIZE as usize).min(artifact.lines.len());
        Ok(WorkflowSubtitlePreviewPage {
            candidate_id,
            lines: artifact.lines[start..end].to_vec(),
            page,
            total_pages,
        })
    }

    pub async fn acquire_subtitle(
        &self,
        candidate_id: String,
    ) -> Result<SubtitleArtifact, SubtitleFailure> {
        #[cfg(feature = "offline-smoke")]
        yield_pending_steps(1).await;
        let artifact = self
            .materialize(&candidate_id, SubtitleOperation::Acquisition)
            .await?;
        Ok(SubtitleArtifact {
            candidate_id,
            bytes: artifact.bytes.as_ref().clone(),
            format: artifact.format,
        })
    }

    async fn materialize(
        &self,
        candidate_id: &str,
        operation: SubtitleOperation,
    ) -> Result<Arc<MaterializedArtifact>, SubtitleFailure> {
        let materialization = {
            let mut store = self.store.lock().map_err(|_| internal_failure(operation))?;
            let Some(record) = store.candidates.get(candidate_id).cloned() else {
                return Err(SubtitleFailure::new(
                    operation,
                    SubtitleFailureKind::CandidateExpired,
                    None,
                ));
            };
            if let Some(artifact) = store.artifacts.get(candidate_id).cloned() {
                store.touch_candidate(candidate_id);
                store.touch_artifact(candidate_id);
                return Ok(Arc::new(artifact));
            }
            if let Some(materialization) = store.in_flight.get(candidate_id).cloned() {
                materialization
            } else {
                let transport = self.transport.clone();
                let locator = record.locator;
                let format = record.candidate.format;
                let future = boxed_workflow_future(async move {
                    let bytes = transport
                        .download(locator)
                        .await
                        .map_err(MaterializationFailure::from)?;
                    flutter_rust_bridge::spawn_blocking_with(
                        move || {
                            materialize_bytes(bytes, format)
                                .map(Arc::new)
                                .map_err(MaterializationFailure::from)
                        },
                        crate::frb_generated::FLUTTER_RUST_BRIDGE_HANDLER.thread_pool(),
                    )
                    .await
                    .map_err(|_| MaterializationFailure::Internal)?
                })
                .shared();
                store
                    .in_flight
                    .insert(candidate_id.to_owned(), future.clone());
                future
            }
        };

        let materialized = materialization.await;
        let mut store = self.store.lock().map_err(|_| internal_failure(operation))?;
        store.in_flight.remove(candidate_id);
        if let Ok(artifact) = &materialized {
            if store.candidates.contains_key(candidate_id) {
                store.insert_artifact(candidate_id.to_owned(), artifact.as_ref().clone());
                store.touch_candidate(candidate_id);
                store.touch_artifact(candidate_id);
            }
        }
        materialized.map_err(|failure| failure.into_subtitle_failure(operation))
    }
}

#[cfg(not(frb_expand))]
fn materialize_bytes(
    bytes: Vec<u8>,
    format: SubtitleFormat,
) -> Result<MaterializedArtifact, SubtitleFailureKind> {
    const MAX_SUBTITLE_BYTES: usize = 20 * 1024 * 1024;
    if bytes.len() > MAX_SUBTITLE_BYTES {
        return Err(SubtitleFailureKind::ArtifactTooLarge);
    }
    if !(8..=MAX_SUBTITLE_BYTES).contains(&bytes.len()) {
        return Err(SubtitleFailureKind::ArtifactInvalid);
    }
    let (text, _encoding) =
        simple::decode_subtitle(&bytes).map_err(|_| SubtitleFailureKind::ArtifactInvalid)?;
    simple::validate_subtitle_text(&text, format.as_str())
        .map_err(|_| SubtitleFailureKind::ArtifactInvalid)?;
    let lines = text
        .lines()
        .map(|line| line.trim_end_matches('\r').to_owned())
        .collect::<Vec<_>>();
    Ok(MaterializedArtifact {
        bytes: Arc::new(bytes),
        lines: Arc::new(lines),
        format,
    })
}

#[cfg(not(frb_expand))]
fn provider_match_score(
    provider: &ProviderCandidate,
    query: &str,
    languages: &[String],
    format: SubtitleFormat,
) -> i64 {
    let mut score = 0;
    let title = simple::normalized_title(&provider.name);
    let query = simple::normalized_title(query);
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
    let language = languages
        .first()
        .map_or_else(String::new, |language| language.to_ascii_lowercase());
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
        ["zh-cn", "zh", "en"]
            .iter()
            .position(|preferred| preferred.eq_ignore_ascii_case(&language))
            .map_or(0, |index| (180 - index as i64 * 20).max(20))
    };
    score += match format {
        SubtitleFormat::Srt => 80,
        SubtitleFormat::Ass => 60,
        SubtitleFormat::Ssa => 50,
        SubtitleFormat::Vtt => 40,
    };
    score += provider
        .upstream_score
        .unwrap_or_default()
        .round()
        .clamp(0.0, 100.0) as i64;
    if provider.fingerprint_score.unwrap_or_default() > 0.0 {
        score += 100;
    }
    score
}

fn normalize_languages(languages: &[String]) -> Vec<String> {
    languages
        .iter()
        .map(|language| language.trim())
        .filter(|language| !language.is_empty())
        .map(|language| match language.to_ascii_lowercase().as_str() {
            "zh-cn" | "zh-hans" | "chs" | "简体" => "zh-CN".to_owned(),
            "zh-tw" | "zh-hant" | "cht" | "繁体" => "zh-TW".to_owned(),
            "zh" | "chi" | "zho" | "chinese" => "zh".to_owned(),
            "en" | "eng" | "english" => "en".to_owned(),
            _ => language.to_owned(),
        })
        .collect()
}

#[cfg(not(frb_expand))]
fn match_reasons(
    provider: &ProviderCandidate,
    query: &str,
    name: &str,
    languages: &[String],
    format: SubtitleFormat,
) -> Vec<MatchReason> {
    let normalized_query = simple::normalized_title(query);
    let normalized_name = simple::normalized_title(name);
    let mut reasons = Vec::new();
    if !normalized_query.is_empty() && normalized_name == normalized_query {
        reasons.push(MatchReason {
            kind: MatchReasonKind::ExactTitle,
            value: None,
        });
    } else if !normalized_query.is_empty()
        && (normalized_name.contains(&normalized_query)
            || normalized_query.contains(&normalized_name))
    {
        reasons.push(MatchReason {
            kind: MatchReasonKind::TitleContains,
            value: None,
        });
    }
    reasons.extend(languages.iter().cloned().map(|language| MatchReason {
        kind: MatchReasonKind::LanguageMatch,
        value: Some(language),
    }));
    if provider.fingerprint_score.unwrap_or_default() > 0.0 {
        reasons.push(MatchReason {
            kind: MatchReasonKind::FingerprintMatch,
            value: None,
        });
    }
    if provider.upstream_score.unwrap_or_default() > 0.0 {
        reasons.push(MatchReason {
            kind: MatchReasonKind::ProviderScore,
            value: None,
        });
    }
    if SubtitleFormat::parse(format.as_str()).is_some() {
        reasons.push(MatchReason {
            kind: MatchReasonKind::SupportedFormat,
            value: None,
        });
    }
    reasons
}

fn stable_candidate_id(locator: &str) -> String {
    use sha1::{Digest, Sha1};

    let digest = Sha1::digest(locator.as_bytes());
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut id = String::with_capacity(digest.len() * 2);
    for byte in digest {
        id.push(HEX[(byte >> 4) as usize] as char);
        id.push(HEX[(byte & 0x0f) as usize] as char);
    }
    id
}

#[cfg(not(frb_expand))]
fn provider_failure(operation: SubtitleOperation, failure: ProviderFailure) -> SubtitleFailure {
    let (kind, detail) = match failure {
        ProviderFailure::Network => (SubtitleFailureKind::ProviderUnavailable, Some("network")),
        ProviderFailure::Http(_) => (SubtitleFailureKind::ProviderUnavailable, Some("http")),
        ProviderFailure::Protocol => (SubtitleFailureKind::ProviderUnavailable, Some("protocol")),
        ProviderFailure::ArtifactTooLarge => (SubtitleFailureKind::ArtifactTooLarge, None),
    };
    SubtitleFailure::new(operation, kind, detail.map(str::to_owned))
}

#[cfg(all(test, not(frb_expand)))]
mod failure_classification_tests {
    use super::*;

    #[test]
    fn provider_failures_preserve_bounded_classification() {
        let cases = [
            (
                ProviderFailure::Network,
                SubtitleFailureKind::ProviderUnavailable,
                "network",
            ),
            (
                ProviderFailure::Http(503),
                SubtitleFailureKind::ProviderUnavailable,
                "http",
            ),
            (
                ProviderFailure::Protocol,
                SubtitleFailureKind::ProviderUnavailable,
                "protocol",
            ),
            (
                ProviderFailure::ArtifactTooLarge,
                SubtitleFailureKind::ArtifactTooLarge,
                "",
            ),
        ];

        for (failure, expected_kind, expected_detail) in cases {
            let mapped = provider_failure(SubtitleOperation::Acquisition, failure);
            assert_eq!(mapped.kind, expected_kind);
            assert_eq!(
                mapped.detail.as_deref().unwrap_or_default(),
                expected_detail
            );
        }
    }

    #[cfg(not(feature = "offline-smoke"))]
    #[test]
    fn xunlei_failures_map_to_provider_failure_without_free_form_text() {
        assert_eq!(
            map_xunlei_failure(xunlei::XunleiFailure::Network),
            ProviderFailure::Network
        );
        assert_eq!(
            map_xunlei_failure(xunlei::XunleiFailure::Http(503)),
            ProviderFailure::Http(503)
        );
        assert_eq!(
            map_xunlei_failure(xunlei::XunleiFailure::Protocol),
            ProviderFailure::Protocol
        );
        assert_eq!(
            map_xunlei_failure(xunlei::XunleiFailure::ArtifactTooLarge),
            ProviderFailure::ArtifactTooLarge
        );
    }

    #[test]
    fn materialization_failures_preserve_operation_and_safe_detail() {
        let cases = [
            (
                MaterializationFailure::ProviderNetwork,
                SubtitleFailureKind::ProviderUnavailable,
                "network",
            ),
            (
                MaterializationFailure::ProviderHttp,
                SubtitleFailureKind::ProviderUnavailable,
                "http",
            ),
            (
                MaterializationFailure::ProviderProtocol,
                SubtitleFailureKind::ProviderUnavailable,
                "protocol",
            ),
            (
                MaterializationFailure::ArtifactTooLarge,
                SubtitleFailureKind::ArtifactTooLarge,
                "",
            ),
            (
                MaterializationFailure::ArtifactInvalid,
                SubtitleFailureKind::ArtifactInvalid,
                "",
            ),
        ];

        for (failure, expected_kind, expected_detail) in cases {
            let mapped = failure.into_subtitle_failure(SubtitleOperation::Preview);
            assert_eq!(mapped.operation, SubtitleOperation::Preview);
            assert_eq!(mapped.kind, expected_kind);
            assert_eq!(
                mapped.detail.as_deref().unwrap_or_default(),
                expected_detail
            );
        }
    }
}

fn internal_failure(operation: SubtitleOperation) -> SubtitleFailure {
    SubtitleFailure::new(operation, SubtitleFailureKind::Internal, None)
}

#[cfg(all(not(frb_expand), not(feature = "offline-smoke")))]
struct ProductionTransport;

#[cfg(all(not(frb_expand), not(feature = "offline-smoke")))]
impl XunleiTransport for ProductionTransport {
    fn search(
        &self,
        query: String,
    ) -> WorkflowBoxFuture<'static, Result<Vec<ProviderCandidate>, ProviderFailure>> {
        boxed_workflow_future(async move {
            xunlei::search_xunlei(query)
                .await
                .map(|candidates| {
                    candidates
                        .into_iter()
                        .map(|candidate| ProviderCandidate {
                            locator: candidate.locator,
                            name: candidate.name,
                            extension: candidate.extension,
                            languages: candidate.languages,
                            upstream_score: candidate.upstream_score,
                            fingerprint_score: candidate.fingerprint_score,
                        })
                        .collect()
                })
                .map_err(map_xunlei_failure)
        })
    }

    fn download(
        &self,
        locator: String,
    ) -> WorkflowBoxFuture<'static, Result<Vec<u8>, ProviderFailure>> {
        boxed_workflow_future(async move {
            xunlei::download_xunlei(locator)
                .await
                .map_err(map_xunlei_failure)
        })
    }
}

#[cfg(all(not(frb_expand), not(feature = "offline-smoke")))]
fn map_xunlei_failure(failure: xunlei::XunleiFailure) -> ProviderFailure {
    match failure {
        xunlei::XunleiFailure::Network => ProviderFailure::Network,
        xunlei::XunleiFailure::Http(status) => ProviderFailure::Http(status),
        xunlei::XunleiFailure::Protocol => ProviderFailure::Protocol,
        xunlei::XunleiFailure::ArtifactTooLarge => ProviderFailure::ArtifactTooLarge,
    }
}

#[cfg(all(
    not(frb_expand),
    not(target_family = "wasm"),
    feature = "offline-smoke"
))]
fn default_workflow() -> SubtitleWorkflow {
    static WORKFLOW: OnceLock<SubtitleWorkflow> = OnceLock::new();
    WORKFLOW
        .get_or_init(|| SubtitleWorkflow::with_mock(MockXunleiTransport::offline_smoke()))
        .clone()
}

#[cfg(all(
    not(frb_expand),
    not(target_family = "wasm"),
    not(feature = "offline-smoke")
))]
fn default_workflow() -> SubtitleWorkflow {
    static WORKFLOW: OnceLock<SubtitleWorkflow> = OnceLock::new();
    WORKFLOW
        .get_or_init(|| {
            SubtitleWorkflow::with_transport(
                transport_handle(ProductionTransport),
                StoreConfig::default(),
            )
        })
        .clone()
}

#[cfg(all(target_family = "wasm", not(frb_expand)))]
thread_local! {
    static WORKFLOW: OnceCell<SubtitleWorkflow> = const { OnceCell::new() };
}

#[cfg(all(target_family = "wasm", not(frb_expand)))]
fn default_workflow() -> SubtitleWorkflow {
    WORKFLOW.with(|workflow| {
        workflow
            .get_or_init(|| {
                #[cfg(feature = "offline-smoke")]
                {
                    SubtitleWorkflow::with_mock(MockXunleiTransport::offline_smoke())
                }
                #[cfg(not(feature = "offline-smoke"))]
                {
                    SubtitleWorkflow::with_transport(
                        transport_handle(ProductionTransport),
                        StoreConfig::default(),
                    )
                }
            })
            .clone()
    })
}

#[cfg(frb_expand)]
#[flutter_rust_bridge::frb(ignore)]
pub struct SubtitleWorkflow;

#[cfg(frb_expand)]
impl SubtitleWorkflow {
    async fn search_subtitles(
        &self,
        _suggested_search_name: String,
    ) -> Result<Vec<WorkflowSubtitleCandidate>, SubtitleFailure> {
        unreachable!()
    }

    async fn preview_subtitle(
        &self,
        _candidate_id: String,
        _page: u32,
    ) -> Result<WorkflowSubtitlePreviewPage, SubtitleFailure> {
        unreachable!()
    }

    async fn acquire_subtitle(
        &self,
        _candidate_id: String,
    ) -> Result<SubtitleArtifact, SubtitleFailure> {
        unreachable!()
    }
}

#[cfg(frb_expand)]
fn default_workflow() -> &'static SubtitleWorkflow {
    unreachable!("the FRB expansion never executes the production workflow")
}

pub async fn search_subtitles(
    suggested_search_name: String,
) -> Result<Vec<WorkflowSubtitleCandidate>, SubtitleFailure> {
    default_workflow()
        .search_subtitles(suggested_search_name)
        .await
}

pub async fn preview_subtitle(
    candidate_id: String,
    page: u32,
) -> Result<WorkflowSubtitlePreviewPage, SubtitleFailure> {
    default_workflow()
        .preview_subtitle(candidate_id, page)
        .await
}

pub async fn acquire_subtitle(candidate_id: String) -> Result<SubtitleArtifact, SubtitleFailure> {
    default_workflow().acquire_subtitle(candidate_id).await
}
