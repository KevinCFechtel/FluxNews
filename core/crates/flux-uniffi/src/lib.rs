//! Thin UniFFI adapter around the real shared core API.

use flux_core::domain;
use flux_core::{
    CoreConfig, FluxCore, SyncCancellation as CoreSyncCancellation, SyncOutcome as CoreSyncOutcome,
};
use std::sync::Arc;

use flux_core::config_backup;

uniffi::setup_scaffolding!();

#[cfg(target_os = "android")]
mod android_tls;

#[derive(uniffi::Record)]
pub struct InitializationConfig {
    pub persistent_data: String,
    pub cache: String,
    pub media: String,
    pub base_url: String,
    pub api_key: String,
    pub custom_headers: Vec<HttpHeader>,
}
#[derive(uniffi::Record)]
pub struct HttpHeader {
    pub name: String,
    pub value: String,
}
#[derive(uniffi::Enum)]
pub enum BackupPlatform {
    Macos,
    Ios,
    Android,
}
#[derive(uniffi::Record)]
pub struct BackupAccount {
    pub installation_base: String,
    pub api_key: String,
}
#[derive(uniffi::Record)]
pub struct PlatformSettingsPayload {
    pub schema_version: u32,
    pub data_json: String,
}
#[derive(uniffi::Record)]
pub struct ConfigBackupInput {
    pub platform: BackupPlatform,
    pub account: BackupAccount,
    pub core_settings: CoreSettings,
    pub feed_preferences: Vec<FeedPreferences>,
    pub platform_settings: PlatformSettingsPayload,
}
#[derive(uniffi::Record)]
pub struct ConfigBackupRestoreModel {
    pub platform: BackupPlatform,
    pub account: BackupAccount,
    pub core_settings: CoreSettings,
    pub feed_preferences: Vec<FeedPreferences>,
    pub platform_settings: PlatformSettingsPayload,
}
#[derive(uniffi::Record)]
pub struct ConfigurationSnapshot {
    pub installation_base: String,
    pub core_settings: CoreSettings,
    pub feed_preferences: Vec<FeedPreferences>,
}
#[derive(uniffi::Record)]
pub struct AccountValidationResult {
    pub installation_base: String,
    pub version: String,
}
#[derive(uniffi::Record)]
pub struct AccountValidationDiagnostic {
    pub category: String,
    pub detail: String,
}
#[derive(uniffi::Record)]
pub struct AccountValidationAttempt {
    pub result: Option<AccountValidationResult>,
    pub error: Option<AccountValidationError>,
    pub diagnostic: Option<AccountValidationDiagnostic>,
}
#[derive(uniffi::Record)]
pub struct ArticleCursor {
    pub published_at: String,
    pub article_id: i64,
}
#[derive(uniffi::Record)]
pub struct ArticleQuery {
    pub scope: ArticleScope,
    pub read_filter: ReadFilter,
    pub starred_filter: StarredFilter,
    pub sort: ArticleSort,
    pub limit: u32,
    pub cursor: Option<ArticleCursor>,
}
#[derive(uniffi::Record)]
pub struct ArticleSummary {
    pub id: i64,
    pub feed_id: i64,
    pub category_id: i64,
    pub feed_title: String,
    pub title: String,
    pub url: String,
    pub comments_url: String,
    pub published_at: String,
    pub is_read: bool,
    pub is_starred: bool,
    pub reading_time_minutes: u32,
    pub preview: String,
    pub image_url: Option<String>,
}
#[derive(uniffi::Record)]
pub struct ArticlePage {
    pub articles: Vec<ArticleSummary>,
    pub total: Option<u64>,
    pub next_cursor: Option<ArticleCursor>,
}
#[derive(uniffi::Record)]
pub struct ArticleAudioActionProjection {
    pub article_id: i64,
    pub enclosures: Vec<Enclosure>,
    pub is_in_listening_list: bool,
    pub downloads: Vec<MediaDownload>,
}
#[derive(uniffi::Record)]
pub struct ReaderDocument {
    pub blocks: Vec<ReaderBlock>,
    pub has_simplified_content: bool,
    pub was_truncated: bool,
}
#[derive(uniffi::Enum)]
pub enum ReaderBlock {
    Paragraph {
        inlines: Vec<ReaderInline>,
    },
    Heading {
        level: u8,
        inlines: Vec<ReaderInline>,
    },
    Image {
        url: String,
        alt: Option<String>,
        link: Option<String>,
    },
    ListBlock {
        ordered: bool,
        items: Vec<ReaderListItem>,
    },
    Quote {
        blocks: Vec<ReaderBlock>,
    },
    CodeBlock {
        text: String,
    },
    HorizontalRule,
    ExternalContent {
        url: String,
        label: Option<String>,
    },
}
#[derive(uniffi::Record)]
pub struct ReaderListItem {
    pub blocks: Vec<ReaderBlock>,
}
#[derive(uniffi::Enum)]
pub enum ReaderInline {
    Text {
        text: String,
    },
    Bold {
        inlines: Vec<ReaderInline>,
    },
    Italic {
        inlines: Vec<ReaderInline>,
    },
    Code {
        text: String,
    },
    Link {
        url: String,
        inlines: Vec<ReaderInline>,
    },
}
#[derive(uniffi::Record)]
pub struct SearchArticlesRequest {
    pub query: String,
    pub offset: i64,
    pub limit: u32,
}
#[derive(uniffi::Record)]
pub struct SearchArticlesResult {
    pub total: i64,
    pub articles: Vec<ArticleSummary>,
}

#[derive(uniffi::Enum)]
pub enum SearchMutationDisposition {
    LocalFirst,
    RemoteOnly,
}

#[derive(uniffi::Enum)]
pub enum ArticleScope {
    All,
    Category { id: i64 },
    Feed { id: i64 },
}
#[derive(uniffi::Enum)]
pub enum ReadFilter {
    All,
    Read,
    Unread,
}
#[derive(uniffi::Enum)]
pub enum StarredFilter {
    All,
    Starred,
    Unstarred,
}
#[derive(uniffi::Enum)]
pub enum ArticleSort {
    NewestFirst,
    OldestFirst,
}
#[derive(uniffi::Enum)]
pub enum SyncReason {
    Manual,
    AppStart,
    Resume,
    Background,
    Periodic,
    Widget,
}
#[derive(uniffi::Record)]
pub struct Category {
    pub id: i64,
    pub title: String,
}
#[derive(uniffi::Record)]
pub struct Feed {
    pub id: i64,
    pub category_id: i64,
    pub title: String,
}
#[derive(uniffi::Enum)]
pub enum FeedIconVariant {
    Normal,
    Dark,
}
#[derive(uniffi::Record)]
pub struct FeedIcon {
    pub feed_id: i64,
    pub variant: FeedIconVariant,
    pub png_data: Vec<u8>,
}
#[derive(uniffi::Enum)]
pub enum ArticleThumbnailResult {
    Available { png_data: Vec<u8> },
    Unavailable,
}
#[derive(uniffi::Record)]
pub struct NavigationCatalog {
    pub categories: Vec<Category>,
    pub feeds: Vec<Feed>,
}
#[derive(uniffi::Enum)]
pub enum NavigationCountMode {
    Unread,
    All,
}
#[derive(uniffi::Record)]
pub struct NavigationProjection {
    pub catalog: NavigationCatalog,
    pub unread_total: u64,
    pub starred_total: u64,
    pub category_counts: Vec<NavigationScopedCount>,
    pub feed_counts: Vec<NavigationScopedCount>,
}
#[derive(uniffi::Record)]
pub struct NavigationScopedCount {
    pub id: i64,
    pub count: u64,
}
#[derive(uniffi::Record)]
pub struct WidgetData {
    pub categories: Vec<Category>,
    pub feeds: Vec<Feed>,
    pub articles: Vec<WidgetArticle>,
    pub counts: WidgetCounts,
    pub last_successful_sync_at: Option<String>,
}
#[derive(uniffi::Record)]
pub struct WidgetArticle {
    pub id: i64,
    pub feed_id: i64,
    pub category_id: i64,
    pub feed_title: String,
    pub title: String,
    pub published_at: String,
    pub is_read: bool,
    pub is_starred: bool,
}
#[derive(uniffi::Record)]
pub struct WidgetArticlePage {
    pub articles: Vec<WidgetArticle>,
    pub next_cursor: Option<ArticleCursor>,
}
#[derive(uniffi::Record)]
pub struct WidgetCounts {
    pub all_unread: u64,
    pub all_articles: u64,
    pub bookmarks: u64,
    pub bookmarks_unread: u64,
    pub feed_unread: Vec<WidgetScopedCount>,
    pub feed_all: Vec<WidgetScopedCount>,
    pub category_unread: Vec<WidgetScopedCount>,
    pub category_all: Vec<WidgetScopedCount>,
}
#[derive(uniffi::Record)]
pub struct WidgetScopedCount {
    pub id: i64,
    pub count: u64,
}
#[derive(uniffi::Enum)]
pub enum RuntimeHealth {
    Healthy,
    ConnectivityDegraded,
    ServerDegraded,
}
#[derive(uniffi::Record)]
pub struct RuntimeHealthStatus {
    pub health: RuntimeHealth,
    pub next_retry_at: Option<String>,
}
#[derive(uniffi::Record)]
pub struct SyncCompleted {
    pub reason: SyncReason,
    pub new_articles: u32,
    pub updated_articles: u32,
    pub mutations_delivered: u32,
    pub data_changed: bool,
    pub navigation_changed: bool,
    pub new_articles_by_feed: Vec<NewArticlesByFeed>,
    pub system_notification_candidates: Vec<SystemNotificationCandidate>,
}
#[derive(uniffi::Enum)]
pub enum SyncOutcome {
    Completed { metadata: SyncCompleted },
    Cancelled,
}
#[derive(uniffi::Record)]
pub struct NewArticlesByFeed {
    pub feed_id: i64,
    pub count: u32,
}
#[derive(uniffi::Record)]
pub struct FeedSystemNotificationSetting {
    pub feed_id: i64,
    pub feed_title: String,
    pub system_notifications_enabled: bool,
}
#[derive(uniffi::Enum)]
pub enum DetailRenderingMode {
    Rendered,
    TextOnly,
}
#[derive(uniffi::Enum)]
pub enum LegacyFeedOpenInMinifluxImportOutcome {
    Imported,
    AlreadyPresent,
    MissingFeed,
}
#[derive(uniffi::Record)]
pub struct FeedPreferences {
    pub feed_id: i64,
    pub system_notifications_enabled: bool,
    pub detail_rendering: DetailRenderingMode,
    pub truncate_detail: bool,
    pub open_in_miniflux: bool,
    pub auto_download_audio: bool,
}
#[derive(uniffi::Record)]
pub struct FeedPreferencesPatch {
    pub system_notifications_enabled: Option<bool>,
    pub detail_rendering: Option<DetailRenderingMode>,
    pub truncate_detail: Option<bool>,
    pub open_in_miniflux: Option<bool>,
    pub auto_download_audio: Option<bool>,
}
#[derive(uniffi::Record)]
pub struct SystemNotificationCandidate {
    pub candidate_id: i64,
    pub feed_id: i64,
    pub feed_title: String,
    pub new_count: u32,
}
#[derive(uniffi::Record)]
pub struct SyncFailed {
    pub reason: SyncReason,
    pub error_kind: ErrorKind,
    pub mutation_delivery_completed: bool,
    pub remote_fetch_started: bool,
    pub remote_fetch_completed: bool,
    pub mutations_delivered: u32,
}
#[derive(uniffi::Enum)]
pub enum DeliveryMode {
    Live,
    Deferred,
}
#[derive(uniffi::Enum)]
pub enum ReadArticleRetention {
    Days30,
    Days60,
    Days90,
    Days180,
    Days365,
}
#[derive(uniffi::Record)]
pub struct CoreSettings {
    pub retention: ReadArticleRetention,
    pub delivery_mode: DeliveryMode,
    pub background_sync_enabled: bool,
    pub detail_character_limit: u32,
    pub download_network_policy: DownloadNetworkPolicy,
    pub download_retention: DownloadRetention,
    pub delete_after_playback: bool,
    pub auto_download_listening_list: bool,
    pub remove_completed_listening_list: bool,
}

#[derive(uniffi::Enum)]
pub enum MediaKind {
    Audio,
    Video,
    Image,
    Other,
}
#[derive(uniffi::Record)]
pub struct Enclosure {
    pub id: i64,
    pub article_id: i64,
    pub url: String,
    pub mime_type: String,
    pub size_bytes: Option<u64>,
    pub remote_media_progression_seconds: u64,
    pub media_kind: MediaKind,
}
#[derive(uniffi::Record)]
pub struct ListeningListEnclosure {
    pub enclosure: Enclosure,
    pub remote_present: bool,
    pub playback_state: Option<PlaybackState>,
    pub download: Option<MediaDownload>,
    pub duration_ms: Option<u64>,
}
#[derive(uniffi::Record)]
pub struct ListeningListItem {
    pub article_id: i64,
    pub feed_id: i64,
    pub title: String,
    pub feed_title: String,
    pub published_at: String,
    pub added_at: String,
    pub remote_present: bool,
    pub audio_enclosures: Vec<ListeningListEnclosure>,
    pub active_enclosure_id: Option<i64>,
}
#[derive(uniffi::Record)]
pub struct ListeningListFeed {
    pub feed_id: i64,
    pub feed_title: String,
    pub item_count: u64,
}
#[derive(uniffi::Enum)]
pub enum ListeningListSort {
    RecentlyAdded,
    PublicationDate,
}
#[derive(uniffi::Enum)]
pub enum PlaybackStatus {
    NotStarted,
    InProgress,
    Completed,
}
#[derive(uniffi::Record)]
pub struct PlaybackState {
    pub enclosure_id: i64,
    pub position_ms: u64,
    pub duration_ms: Option<u64>,
    pub status: PlaybackStatus,
    pub updated_at: Option<String>,
}
#[derive(uniffi::Record)]
pub struct ContinueListeningItem {
    pub enclosure_id: i64,
    pub article_id: i64,
    pub feed_id: i64,
    pub title: String,
    pub feed_title: String,
    pub published_at: String,
    pub url: String,
    pub mime_type: String,
    pub position_ms: u64,
    pub duration_ms: Option<u64>,
    pub updated_at: String,
    pub local_file: Option<String>,
}
#[derive(uniffi::Record)]
pub struct LegacyLocalPlaybackArticle {
    pub article_id: i64,
    pub feed_id: i64,
    pub title: String,
    pub url: String,
    pub comments_url: String,
    pub published_at: String,
    pub is_read: bool,
    pub is_starred: bool,
    pub raw_html_content: String,
    pub reading_time_minutes: u32,
    pub preview: String,
    pub image_url: Option<String>,
    pub enclosure_id: i64,
    pub enclosure_url: String,
    pub enclosure_mime_type: String,
}

#[derive(uniffi::Record)]
pub struct LegacyPlaybackImport {
    pub article_id: i64,
    pub position_ms: u64,
    pub updated_at: Option<String>,
}
#[derive(uniffi::Record)]
pub struct LegacyPlaybackImportResult {
    pub imported: u32,
    pub skipped_missing: u32,
    pub skipped_ambiguous: u32,
    pub already_present: u32,
}
#[derive(uniffi::Record)]
pub struct LegacyMediaRepairResult {
    pub scanned: u32,
    pub recovered_artworks: u32,
}
#[derive(uniffi::Enum)]
pub enum LegacyDownloadImportOutcome {
    Imported,
    AlreadyPresent,
    MissingEnclosure,
}
#[derive(uniffi::Record)]
pub struct PlaybackPreparation {
    pub enclosure: Enclosure,
    pub article_title: String,
    pub feed_title: String,
    pub playback_state: PlaybackState,
    pub local_file: Option<String>,
    pub duration_ms: Option<u64>,
    pub artwork_source: Option<MediaArtworkSource>,
}
#[derive(uniffi::Enum)]
pub enum MediaArtworkSource {
    LocalReference { reference: String },
    RemoteUrl { url: String },
}
#[derive(uniffi::Enum)]
pub enum MediaProgressCapability {
    Unknown,
    Supported,
    Unsupported,
}
#[derive(uniffi::Enum)]
pub enum DownloadState {
    NotDownloaded,
    Requested,
    Downloaded,
    Failed,
    DeleteRequested,
}
#[derive(uniffi::Enum)]
pub enum DownloadOrigin {
    Manual,
    Automatic,
}
#[derive(uniffi::Enum)]
pub enum DownloadFailureKind {
    Network,
    Storage,
    InvalidMedia,
    Unknown,
}
#[derive(uniffi::Record)]
pub struct MediaDownload {
    pub enclosure_id: i64,
    pub state: DownloadState,
    pub origin: Option<DownloadOrigin>,
    pub local_file: Option<String>,
    pub file_size_bytes: Option<u64>,
    pub downloaded_at: Option<String>,
    pub failure_kind: Option<DownloadFailureKind>,
}
#[derive(uniffi::Record)]
pub struct DownloadedMediaSummary {
    pub file_count: u64,
    pub total_size_bytes: u64,
}
#[derive(uniffi::Record)]
pub struct MediaTransferWork {
    pub enclosure_id: i64,
    pub url: String,
    pub mime_type: String,
    pub origin: DownloadOrigin,
    pub local_file: Option<String>,
}
#[derive(uniffi::Enum)]
pub enum DownloadNetworkPolicy {
    AnyNetwork,
    UnmeteredOnly,
}
#[derive(uniffi::Enum)]
pub enum DownloadRetention {
    Forever,
    Days { days: u32 },
}
#[derive(uniffi::Enum)]
pub enum MediaChapterSource {
    Embedded,
    ArticleContent,
}
#[derive(uniffi::Record)]
pub struct MediaMetadata {
    pub enclosure_id: i64,
    pub duration_ms: Option<u64>,
    pub embedded_artwork_reference: Option<String>,
}
#[derive(uniffi::Record)]
pub struct MediaChapter {
    pub enclosure_id: i64,
    pub title: String,
    pub start_ms: u64,
    pub end_ms: Option<u64>,
    pub source: MediaChapterSource,
}
#[derive(uniffi::Record)]
pub struct SavedPlayableMediaItem {
    pub enclosure_id: i64,
    pub article_id: i64,
    pub feed_id: i64,
    pub title: String,
    pub feed_title: String,
    pub published_at: String,
    pub added_at: String,
    pub url: String,
    pub mime_type: String,
    pub media_kind: MediaKind,
    pub remote_present: bool,
    pub duration_ms: Option<u64>,
    pub artwork_source: Option<MediaArtworkSource>,
}
#[derive(uniffi::Record)]
pub struct SavedMediaSyncConfiguration {
    pub enabled: bool,
    pub sync_feed_id: Option<i64>,
    pub requires_repair: bool,
}
#[derive(uniffi::Record)]
pub struct SavedMediaSyncSetupInfo {
    pub bootstrap_url: String,
    pub technical_feed_title: String,
    pub explanation: String,
}
#[derive(uniffi::Enum)]
pub enum DeliveryDisposition {
    Queued,
    Delivered,
    DeferredByBackoff,
}
#[derive(uniffi::Record)]
pub struct MutationResult {
    pub disposition: DeliveryDisposition,
}
#[derive(uniffi::Record)]
pub struct DiscoverSubscriptionsRequest {
    pub url: String,
    pub username: Option<String>,
    pub password: Option<String>,
    pub user_agent: Option<String>,
    pub fetch_via_proxy: Option<bool>,
}
#[derive(uniffi::Record)]
pub struct DiscoveredSubscription {
    pub url: String,
    pub title: String,
    pub feed_type: String,
}
#[derive(uniffi::Record)]
pub struct CreateFeedRequest {
    pub feed_url: String,
    pub category_id: Option<i64>,
    pub username: Option<String>,
    pub password: Option<String>,
    pub crawler: Option<bool>,
    pub user_agent: Option<String>,
    pub scraper_rules: Option<String>,
    pub rewrite_rules: Option<String>,
    pub blocklist_rules: Option<String>,
    pub keeplist_rules: Option<String>,
    pub disabled: Option<bool>,
    pub ignore_http_cache: Option<bool>,
    pub fetch_via_proxy: Option<bool>,
}
#[derive(uniffi::Record)]
pub struct CreateFeedResult {
    pub feed_id: i64,
}
#[derive(uniffi::Record)]
pub struct CreateCategoryResult {
    pub category_id: i64,
}
#[derive(uniffi::Enum)]
pub enum SaveToServiceResult {
    Saved,
    NoIntegrationConfigured,
}
#[derive(uniffi::Enum)]
pub enum MutationField {
    Read,
    Starred,
}
#[derive(uniffi::Enum)]
pub enum CoreEvent {
    ArticleReadStateChanged {
        article_id: i64,
        read: bool,
    },
    ArticleStarredStateChanged {
        article_id: i64,
        starred: bool,
    },
    MutationQueued {
        article_id: i64,
        field: MutationField,
    },
    MutationDeliverySucceeded {
        article_id: i64,
        field: MutationField,
    },
    MutationDeliveryFailed {
        article_id: i64,
        field: MutationField,
        error_kind: ErrorKind,
    },
    SyncDidComplete {
        metadata: SyncCompleted,
    },
    SyncDidFail {
        metadata: SyncFailed,
    },
}
#[derive(uniffi::Enum)]
pub enum ErrorKind {
    Connectivity,
    Authentication,
    InvalidConfiguration,
    ServerTransient,
    Persistence,
    Data,
    Internal,
}
#[uniffi::export(rust, foreign)]
pub trait EventListener: Send + Sync {
    fn on_event(&self, event: CoreEvent);
}
#[derive(uniffi::Enum)]
pub enum DiagnosticLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
}
#[derive(uniffi::Record)]
pub struct DiagnosticRecord {
    pub level: DiagnosticLevel,
    pub target: String,
    pub message: String,
}
#[uniffi::export(rust, foreign)]
pub trait DiagnosticListener: Send + Sync {
    fn on_diagnostic(&self, record: DiagnosticRecord);
}

#[derive(Debug, uniffi::Error)]
pub enum FluxError {
    Connectivity { detail: String },
    Authentication { detail: String },
    InvalidConfiguration { detail: String },
    ServerTransient { detail: String },
    Persistence { detail: String },
    Data { detail: String },
    Internal { detail: String },
}

#[derive(Debug, uniffi::Error)]
pub enum AccountValidationError {
    InvalidUrl,
    UnsupportedUrlScheme,
    Network,
    Unauthorized,
    IncompatibleServer,
    InvalidResponse,
    ServerUnavailable,
    InvalidCustomHeader,
}
#[derive(Debug, uniffi::Error)]
pub enum ConfigBackupError {
    EmptyPassword,
    NotFluxBackup,
    UnsupportedVersion,
    PlatformMismatch,
    InvalidCryptoMetadata,
    DecryptionFailed,
    MalformedPayload,
    InvalidContents,
    InputTooLarge,
    Internal,
}

impl std::fmt::Display for ConfigBackupError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{self:?}")
    }
}

impl std::fmt::Display for AccountValidationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{self:?}")
    }
}

impl std::fmt::Display for FluxError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{self:?}")
    }
}

#[derive(uniffi::Object)]
pub struct SyncCancellation {
    inner: CoreSyncCancellation,
}

#[uniffi::export]
impl SyncCancellation {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            inner: CoreSyncCancellation::new(),
        })
    }

    pub fn cancel(&self) {
        self.inner.cancel();
    }

    pub fn is_cancelled(&self) -> bool {
        self.inner.is_cancelled()
    }
}

#[derive(uniffi::Object)]
pub struct Flux {
    core: Arc<FluxCore>,
}
#[derive(uniffi::Object)]
pub struct EventSubscription {
    core: Arc<FluxCore>,
    id: u64,
}
#[derive(uniffi::Object)]
pub struct DiagnosticSubscription {
    core: Arc<FluxCore>,
    id: u64,
}

#[uniffi::export]
pub fn validate_miniflux_account(
    server_url: String,
    api_key: String,
    custom_headers: Vec<HttpHeader>,
) -> Result<AccountValidationResult, AccountValidationError> {
    FluxCore::validate_miniflux_account(
        &server_url,
        &api_key,
        custom_headers.into_iter().map(Into::into).collect(),
    )
    .map(Into::into)
    .map_err(map_account_validation_error)
}
#[uniffi::export]
pub fn validate_miniflux_account_with_diagnostic(
    server_url: String,
    api_key: String,
    custom_headers: Vec<HttpHeader>,
) -> AccountValidationAttempt {
    let attempt = FluxCore::validate_miniflux_account_with_diagnostic(
        &server_url,
        &api_key,
        custom_headers.into_iter().map(Into::into).collect(),
    );
    AccountValidationAttempt {
        result: attempt.result.map(Into::into),
        error: attempt.error.map(map_account_validation_error),
        diagnostic: attempt
            .diagnostic
            .map(|diagnostic| AccountValidationDiagnostic {
                category: diagnostic.category,
                detail: diagnostic.detail,
            }),
    }
}
#[uniffi::export]
pub fn export_config_backup(
    input: ConfigBackupInput,
    password: String,
) -> Result<Vec<u8>, ConfigBackupError> {
    config_backup::export_config_backup(input.try_into()?, &password).map_err(Into::into)
}
#[uniffi::export]
pub fn parse_config_backup(
    bytes: Vec<u8>,
    password: String,
    expected_platform: BackupPlatform,
) -> Result<ConfigBackupRestoreModel, ConfigBackupError> {
    config_backup::parse_config_backup(&bytes, &password, expected_platform.into())
        .map(Into::into)
        .map_err(Into::into)
}

#[uniffi::export]
impl Flux {
    #[uniffi::constructor]
    pub fn initialize(config: InitializationConfig) -> Result<Arc<Self>, FluxError> {
        let core = FluxCore::initialize(CoreConfig {
            persistent_data: config.persistent_data.into(),
            cache: config.cache.into(),
            media: config.media.into(),
            base_url: config.base_url,
            api_key: config.api_key,
            custom_headers: config.custom_headers.into_iter().map(Into::into).collect(),
        })
        .map_err(map_error)?;
        Ok(Arc::new(Self {
            core: Arc::new(core),
        }))
    }
    #[uniffi::constructor]
    pub fn initialize_with_diagnostics(
        config: InitializationConfig,
        listener: Arc<dyn DiagnosticListener>,
    ) -> Result<Arc<Self>, FluxError> {
        let core = FluxCore::initialize_with_diagnostics(
            CoreConfig {
                persistent_data: config.persistent_data.into(),
                cache: config.cache.into(),
                media: config.media.into(),
                base_url: config.base_url,
                api_key: config.api_key,
                custom_headers: config.custom_headers.into_iter().map(Into::into).collect(),
            },
            Some(Arc::new(DiagnosticListenerBridge { listener })),
        )
        .map_err(map_error)?;
        Ok(Arc::new(Self {
            core: Arc::new(core),
        }))
    }
    pub fn sync(&self, reason: SyncReason) -> Result<SyncCompleted, FluxError> {
        self.core
            .sync(reason.into())
            .map(Into::into)
            .map_err(map_error)
    }

    pub fn sync_cancellable(
        &self,
        reason: SyncReason,
        cancellation: Arc<SyncCancellation>,
    ) -> Result<SyncOutcome, FluxError> {
        self.core
            .sync_cancellable(reason.into(), &cancellation.inner)
            .map(|outcome| match outcome {
                CoreSyncOutcome::Completed(metadata) => SyncOutcome::Completed {
                    metadata: metadata.into(),
                },
                CoreSyncOutcome::Cancelled => SyncOutcome::Cancelled,
            })
            .map_err(map_error)
    }
    pub fn rebuild_local_state(&self) -> Result<SyncCompleted, FluxError> {
        self.core
            .rebuild_local_state()
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn reset_core_state(&self) -> Result<(), FluxError> {
        self.core.reset_core_state().map_err(map_error)
    }
    pub fn remove_account_state(&self) -> Result<(), FluxError> {
        self.core.remove_account_state().map_err(map_error)
    }
    pub fn configuration_snapshot(&self) -> Result<ConfigurationSnapshot, FluxError> {
        self.core
            .configuration_snapshot()
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn replace_configuration(
        &self,
        installation_base: String,
        core_settings: CoreSettings,
        feed_preferences: Vec<FeedPreferences>,
    ) -> Result<(), FluxError> {
        self.core
            .replace_configuration(
                installation_base,
                core_settings.into(),
                feed_preferences.into_iter().map(Into::into).collect(),
            )
            .map_err(map_error)
    }
    pub fn query_articles(&self, query: ArticleQuery) -> Result<Vec<ArticleSummary>, FluxError> {
        self.core
            .query_articles(query.into())
            .map(|rows| rows.into_iter().map(Into::into).collect())
            .map_err(map_error)
    }
    pub fn article_summary(&self, article_id: i64) -> Result<Option<ArticleSummary>, FluxError> {
        self.core
            .article_summary(article_id)
            .map(|article| article.map(Into::into))
            .map_err(map_error)
    }
    pub fn article_page(
        &self,
        query: ArticleQuery,
        include_total: bool,
    ) -> Result<ArticlePage, FluxError> {
        self.core
            .article_page(query.into(), include_total)
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn article_audio_action_states(
        &self,
        article_ids: Vec<i64>,
    ) -> Result<Vec<ArticleAudioActionProjection>, FluxError> {
        self.core
            .article_audio_action_states(&article_ids)
            .map(|rows| rows.into_iter().map(Into::into).collect())
            .map_err(map_error)
    }
    pub fn reader_document(&self, article_id: i64) -> Result<ReaderDocument, FluxError> {
        self.core
            .reader_document(article_id)
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn reader_document_for_search(&self, article_id: i64) -> Result<ReaderDocument, FluxError> {
        self.core
            .reader_document_for_search(article_id)
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn miniflux_entry_url(&self, article_id: i64) -> String {
        self.core.miniflux_entry_url(article_id)
    }
    pub fn count_articles(&self, query: ArticleQuery) -> Result<u64, FluxError> {
        self.core.count_articles(query.into()).map_err(map_error)
    }
    pub fn enclosure(&self, enclosure_id: i64) -> Result<Option<Enclosure>, FluxError> {
        self.core
            .enclosure(enclosure_id)
            .map(|value| value.map(Into::into))
            .map_err(map_error)
    }
    pub fn article_enclosures(&self, article_id: i64) -> Result<Vec<Enclosure>, FluxError> {
        self.core
            .article_enclosures(article_id)
            .map(|rows| rows.into_iter().map(Into::into).collect())
            .map_err(map_error)
    }
    pub fn listening_list(
        &self,
        feed_id: Option<i64>,
        sort: ListeningListSort,
    ) -> Result<Vec<ListeningListItem>, FluxError> {
        self.core
            .listening_list(feed_id, sort.into())
            .map(|rows| rows.into_iter().map(Into::into).collect())
            .map_err(map_error)
    }
    pub fn listening_list_feeds(&self) -> Result<Vec<ListeningListFeed>, FluxError> {
        self.core
            .listening_list_feeds()
            .map(|rows| rows.into_iter().map(Into::into).collect())
            .map_err(map_error)
    }
    pub fn is_in_listening_list(&self, article_id: i64) -> Result<bool, FluxError> {
        self.core
            .is_in_listening_list(article_id)
            .map_err(map_error)
    }
    pub fn add_to_listening_list(&self, article_id: i64) -> Result<(), FluxError> {
        self.core
            .add_to_listening_list(article_id)
            .map_err(map_error)
    }
    pub fn remove_from_listening_list(&self, article_id: i64) -> Result<(), FluxError> {
        self.core
            .remove_from_listening_list(article_id)
            .map_err(map_error)
    }
    pub fn saved_media(&self) -> Result<Vec<SavedPlayableMediaItem>, FluxError> {
        self.core
            .saved_playable_media()
            .map(|rows| rows.into_iter().map(Into::into).collect())
            .map_err(map_error)
    }
    pub fn saved_media_by_feed(
        &self,
        feed_id: i64,
    ) -> Result<Vec<SavedPlayableMediaItem>, FluxError> {
        self.core
            .saved_media_by_feed(feed_id)
            .map(|rows| rows.into_iter().map(Into::into).collect())
            .map_err(map_error)
    }
    pub fn continue_listening(&self) -> Result<Vec<ContinueListeningItem>, FluxError> {
        self.core
            .continue_listening()
            .map(|rows| rows.into_iter().map(Into::into).collect())
            .map_err(map_error)
    }
    pub fn import_legacy_playback(
        &self,
        records: Vec<LegacyPlaybackImport>,
    ) -> Result<LegacyPlaybackImportResult, FluxError> {
        self.core
            .import_legacy_playback(
                &records
                    .into_iter()
                    .map(|record| record.into())
                    .collect::<Vec<_>>(),
            )
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn save_media(&self, enclosure_id: i64) -> Result<(), FluxError> {
        self.core.save_media(enclosure_id).map_err(map_error)
    }
    pub fn unsave_media(&self, enclosure_id: i64) -> Result<(), FluxError> {
        self.core.unsave_media(enclosure_id).map_err(map_error)
    }
    pub fn is_media_saved(&self, enclosure_id: i64) -> Result<bool, FluxError> {
        self.core.is_media_saved(enclosure_id).map_err(map_error)
    }
    pub fn saved_media_sync_configuration(&self) -> Result<SavedMediaSyncConfiguration, FluxError> {
        self.core
            .saved_media_sync_configuration()
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn saved_media_sync_setup_info(&self) -> SavedMediaSyncSetupInfo {
        self.core.saved_media_sync_setup_info().into()
    }
    pub fn setup_saved_media_sync_automatic(&self) -> Result<(), FluxError> {
        self.core
            .setup_saved_media_sync_automatic()
            .map_err(map_error)
    }
    pub fn setup_saved_media_sync_manual(&self) -> Result<(), FluxError> {
        self.core.setup_saved_media_sync_manual().map_err(map_error)
    }
    pub fn disable_saved_media_sync(&self) -> Result<(), FluxError> {
        self.core.disable_saved_media_sync().map_err(map_error)
    }
    pub fn prepare_playback(&self, enclosure_id: i64) -> Result<PlaybackPreparation, FluxError> {
        self.core
            .prepare_playback(enclosure_id)
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn playback_state(&self, enclosure_id: i64) -> Result<PlaybackState, FluxError> {
        self.core
            .playback_state(enclosure_id)
            .map(|state| {
                state.map(Into::into).unwrap_or_else(|| PlaybackState {
                    enclosure_id,
                    position_ms: 0,
                    duration_ms: None,
                    status: PlaybackStatus::NotStarted,
                    updated_at: None,
                })
            })
            .map_err(map_error)
    }
    pub fn checkpoint_playback(
        &self,
        enclosure_id: i64,
        position_ms: u64,
        duration_ms: Option<u64>,
    ) -> Result<(), FluxError> {
        self.core
            .checkpoint_playback(enclosure_id, position_ms, duration_ms)
            .map_err(map_error)
    }
    pub fn playback_completed(
        &self,
        enclosure_id: i64,
        duration_ms: Option<u64>,
    ) -> Result<(), FluxError> {
        self.core
            .playback_completed(enclosure_id, duration_ms)
            .map_err(map_error)
    }
    pub fn restart_playback(&self, enclosure_id: i64) -> Result<(), FluxError> {
        self.core.restart_playback(enclosure_id).map_err(map_error)
    }
    pub fn observe_media_duration(
        &self,
        enclosure_id: i64,
        duration_ms: u64,
    ) -> Result<(), FluxError> {
        self.core
            .observe_media_duration(enclosure_id, duration_ms)
            .map_err(map_error)
    }
    pub fn media_progress_capability(&self) -> MediaProgressCapability {
        self.core.media_progress_capability().into()
    }
    pub fn media_download(&self, enclosure_id: i64) -> Result<MediaDownload, FluxError> {
        self.core
            .media_download(enclosure_id)
            .map(|download| {
                download.map(Into::into).unwrap_or(MediaDownload {
                    enclosure_id,
                    state: DownloadState::NotDownloaded,
                    origin: None,
                    local_file: None,
                    file_size_bytes: None,
                    downloaded_at: None,
                    failure_kind: None,
                })
            })
            .map_err(map_error)
    }
    pub fn downloaded_media_summary(&self) -> Result<DownloadedMediaSummary, FluxError> {
        self.core
            .downloaded_media_summary()
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn request_download(
        &self,
        enclosure_id: i64,
        origin: DownloadOrigin,
    ) -> Result<(), FluxError> {
        self.core
            .request_download(enclosure_id, origin.into())
            .map_err(map_error)
    }
    pub fn cancel_download(&self, enclosure_id: i64) -> Result<(), FluxError> {
        self.core.cancel_download(enclosure_id).map_err(map_error)
    }
    pub fn retry_download(&self, enclosure_id: i64) -> Result<(), FluxError> {
        self.core.retry_download(enclosure_id).map_err(map_error)
    }
    pub fn download_finished(
        &self,
        enclosure_id: i64,
        local_file: String,
        file_size_bytes: u64,
    ) -> Result<(), FluxError> {
        self.core
            .download_finished(enclosure_id, &local_file, file_size_bytes)
            .map_err(map_error)
    }
    pub fn repair_legacy_download_metadata(&self) -> Result<LegacyMediaRepairResult, FluxError> {
        let (scanned, recovered_artworks) = self
            .core
            .repair_legacy_download_metadata()
            .map_err(map_error)?;
        Ok(LegacyMediaRepairResult {
            scanned,
            recovered_artworks,
        })
    }
    pub fn restore_legacy_playback_article(&self, article_id: i64) -> Result<bool, FluxError> {
        self.core
            .restore_legacy_playback_article(article_id)
            .map_err(map_error)
    }
    pub fn restore_legacy_local_playback_article(
        &self,
        snapshot: LegacyLocalPlaybackArticle,
    ) -> Result<bool, FluxError> {
        let article = domain::Article {
            id: snapshot.article_id,
            feed_id: snapshot.feed_id,
            title: snapshot.title,
            url: snapshot.url,
            comments_url: snapshot.comments_url,
            published_at: snapshot.published_at,
            is_read: snapshot.is_read,
            is_starred: snapshot.is_starred,
            raw_html_content: snapshot.raw_html_content,
            reading_time_minutes: snapshot.reading_time_minutes,
            preview: snapshot.preview,
            image_url: snapshot.image_url,
        };
        let enclosure = domain::Enclosure {
            id: snapshot.enclosure_id,
            article_id: snapshot.article_id,
            url: snapshot.enclosure_url,
            mime_type: snapshot.enclosure_mime_type,
            size_bytes: None,
            remote_media_progression_seconds: 0,
        };
        self.core
            .restore_legacy_local_playback_article(&article, &enclosure)
            .map_err(map_error)
    }
    pub fn restore_legacy_media_article(
        &self,
        article_id: i64,
        enclosure_id: i64,
    ) -> Result<bool, FluxError> {
        self.core
            .restore_legacy_media_article(article_id, enclosure_id)
            .map_err(map_error)
    }
    pub fn import_legacy_download(
        &self,
        enclosure_id: i64,
        local_file: String,
        file_size_bytes: u64,
    ) -> Result<LegacyDownloadImportOutcome, FluxError> {
        self.core
            .import_legacy_download(enclosure_id, &local_file, file_size_bytes)
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn download_failed(
        &self,
        enclosure_id: i64,
        failure_kind: DownloadFailureKind,
    ) -> Result<(), FluxError> {
        self.core
            .download_failed(enclosure_id, failure_kind.into())
            .map_err(map_error)
    }
    pub fn request_download_deletion(&self, enclosure_id: i64) -> Result<(), FluxError> {
        self.core
            .request_download_deletion(enclosure_id)
            .map_err(map_error)
    }
    pub fn request_all_download_deletions(&self) -> Result<u64, FluxError> {
        self.core
            .request_all_download_deletions()
            .map_err(map_error)
    }
    pub fn download_deleted(&self, enclosure_id: i64) -> Result<(), FluxError> {
        self.core.download_deleted(enclosure_id).map_err(map_error)
    }
    pub fn downloads_requiring_transfer(&self) -> Result<Vec<MediaTransferWork>, FluxError> {
        self.core
            .downloads_requiring_transfer()
            .map(|work| work.into_iter().map(Into::into).collect())
            .map_err(map_error)
    }
    pub fn downloads_requiring_deletion(&self) -> Result<Vec<MediaTransferWork>, FluxError> {
        self.core
            .downloads_requiring_deletion()
            .map(|work| work.into_iter().map(Into::into).collect())
            .map_err(map_error)
    }
    pub fn media_metadata(&self, enclosure_id: i64) -> Result<Option<MediaMetadata>, FluxError> {
        self.core
            .media_metadata(enclosure_id)
            .map(|value| value.map(Into::into))
            .map_err(map_error)
    }
    pub fn probe_media_artwork(&self, enclosure_id: i64) -> Result<bool, FluxError> {
        self.core
            .probe_media_artwork(enclosure_id)
            .map_err(map_error)
    }
    pub fn media_artwork_source(
        &self,
        enclosure_id: i64,
    ) -> Result<Option<MediaArtworkSource>, FluxError> {
        self.core
            .media_artwork_source(enclosure_id)
            .map(|value| value.map(Into::into))
            .map_err(map_error)
    }
    pub fn media_artwork(&self, reference: String) -> Result<Option<Vec<u8>>, FluxError> {
        self.core.media_artwork(&reference).map_err(map_error)
    }
    pub fn media_chapters(&self, enclosure_id: i64) -> Result<Vec<MediaChapter>, FluxError> {
        self.core
            .media_chapters(enclosure_id)
            .map(|rows| rows.into_iter().map(Into::into).collect())
            .map_err(map_error)
    }
    pub fn evaluate_media_cleanup(&self) -> Result<Vec<i64>, FluxError> {
        self.core.evaluate_media_cleanup_now().map_err(map_error)
    }
    pub fn set_download_network_policy(
        &self,
        policy: DownloadNetworkPolicy,
    ) -> Result<(), FluxError> {
        self.core
            .set_download_network_policy(policy.into())
            .map_err(map_error)
    }
    pub fn set_download_retention(&self, retention: DownloadRetention) -> Result<(), FluxError> {
        self.core
            .set_download_retention(retention.into())
            .map_err(map_error)
    }
    pub fn set_delete_after_playback(&self, enabled: bool) -> Result<(), FluxError> {
        self.core
            .set_delete_after_playback(enabled)
            .map_err(map_error)
    }
    pub fn import_legacy_media_settings(
        &self,
        unmetered_only: Option<bool>,
        retention: Option<DownloadRetention>,
        delete_after_playback: Option<bool>,
    ) -> Result<(), FluxError> {
        self.core
            .import_legacy_media_settings(
                unmetered_only,
                retention.map(Into::into),
                delete_after_playback,
            )
            .map_err(map_error)
    }
    pub fn set_auto_download_listening_list(&self, enabled: bool) -> Result<(), FluxError> {
        self.core
            .set_auto_download_listening_list(enabled)
            .map_err(map_error)
    }
    pub fn import_legacy_policy_settings(
        &self,
        background_sync_enabled: Option<bool>,
        auto_download_listening_list: Option<bool>,
    ) -> Result<(), FluxError> {
        self.core
            .import_legacy_policy_settings(background_sync_enabled, auto_download_listening_list)
            .map_err(map_error)
    }
    pub fn set_remove_completed_listening_list(&self, enabled: bool) -> Result<(), FluxError> {
        self.core
            .set_remove_completed_listening_list(enabled)
            .map_err(map_error)
    }
    pub fn set_feed_auto_download_audio(
        &self,
        feed_id: i64,
        enabled: bool,
    ) -> Result<(), FluxError> {
        self.core
            .set_feed_auto_download_audio(feed_id, enabled)
            .map_err(map_error)
    }
    pub fn search_articles(
        &self,
        request: SearchArticlesRequest,
    ) -> Result<SearchArticlesResult, FluxError> {
        self.core
            .search_articles(request.into())
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn search_set_starred_state(
        &self,
        article_id: i64,
        starred: bool,
    ) -> Result<SearchMutationDisposition, FluxError> {
        self.core
            .search_set_starred_state(article_id, starred)
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn search_set_read_state(
        &self,
        article_id: i64,
        read: bool,
    ) -> Result<SearchMutationDisposition, FluxError> {
        self.core
            .search_set_read_state(article_id, read)
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn navigation_catalog(&self) -> Result<NavigationCatalog, FluxError> {
        self.core
            .navigation_catalog()
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn navigation_projection(
        &self,
        count_mode: NavigationCountMode,
    ) -> Result<NavigationProjection, FluxError> {
        self.core
            .navigation_projection(count_mode.into())
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn feed_system_notification_settings(
        &self,
    ) -> Result<Vec<FeedSystemNotificationSetting>, FluxError> {
        self.core
            .feed_system_notification_settings()
            .map(|settings| settings.into_iter().map(Into::into).collect())
            .map_err(map_error)
    }
    pub fn set_feed_system_notifications_enabled(
        &self,
        feed_id: i64,
        enabled: bool,
    ) -> Result<(), FluxError> {
        self.core
            .set_feed_system_notifications_enabled(feed_id, enabled)
            .map_err(map_error)
    }
    pub fn feed_preferences(&self, feed_id: i64) -> Result<FeedPreferences, FluxError> {
        self.core
            .feed_preferences(feed_id)
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn feed_preferences_bulk(
        &self,
        feed_ids: Vec<i64>,
    ) -> Result<Vec<FeedPreferences>, FluxError> {
        self.core
            .feed_preferences_bulk(&feed_ids)
            .map(|values| values.into_iter().map(Into::into).collect())
            .map_err(map_error)
    }
    pub fn patch_feed_preferences_bulk(
        &self,
        feed_ids: Vec<i64>,
        patch: FeedPreferencesPatch,
    ) -> Result<(), FluxError> {
        self.core
            .patch_feed_preferences_bulk(&feed_ids, patch.into())
            .map_err(map_error)
    }
    pub fn set_feed_detail_rendering(
        &self,
        feed_id: i64,
        mode: DetailRenderingMode,
    ) -> Result<(), FluxError> {
        self.core
            .set_feed_detail_rendering(feed_id, mode.into())
            .map_err(map_error)
    }
    pub fn set_feed_truncate_detail(&self, feed_id: i64, enabled: bool) -> Result<(), FluxError> {
        self.core
            .set_feed_truncate_detail(feed_id, enabled)
            .map_err(map_error)
    }
    pub fn set_feed_open_in_miniflux(&self, feed_id: i64, enabled: bool) -> Result<(), FluxError> {
        self.core
            .set_feed_open_in_miniflux(feed_id, enabled)
            .map_err(map_error)
    }
    pub fn import_legacy_feed_open_in_miniflux(
        &self,
        feed_id: i64,
    ) -> Result<LegacyFeedOpenInMinifluxImportOutcome, FluxError> {
        self.core
            .import_legacy_feed_open_in_miniflux(feed_id)
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn acknowledge_system_notification(&self, candidate_id: i64) -> Result<(), FluxError> {
        self.core
            .acknowledge_system_notification(candidate_id)
            .map_err(map_error)
    }
    pub fn feed_icon(
        &self,
        feed_id: i64,
        variant: FeedIconVariant,
    ) -> Result<Option<FeedIcon>, FluxError> {
        self.core
            .feed_icon(feed_id, variant.into())
            .map(|icon| icon.map(Into::into))
            .map_err(map_error)
    }
    pub fn article_thumbnail(
        &self,
        article_id: i64,
        image_url: String,
    ) -> Result<ArticleThumbnailResult, FluxError> {
        self.core
            .article_thumbnail(article_id, image_url)
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn last_successful_sync_at(&self) -> Result<Option<String>, FluxError> {
        self.core.last_successful_sync_at().map_err(map_error)
    }
    pub fn widget_data(&self) -> Result<WidgetData, FluxError> {
        self.core.widget_data().map(Into::into).map_err(map_error)
    }
    pub fn widget_articles_page(
        &self,
        limit: u32,
        cursor: Option<ArticleCursor>,
    ) -> Result<WidgetArticlePage, FluxError> {
        self.core
            .widget_articles_page(
                limit,
                cursor.map(|value| domain::ArticleCursor {
                    published_at: value.published_at,
                    article_id: value.article_id,
                }),
            )
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn runtime_health(&self) -> Result<RuntimeHealthStatus, FluxError> {
        self.core
            .runtime_health()
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn set_delivery_mode(&self, mode: DeliveryMode) -> Result<(), FluxError> {
        self.core.set_delivery_mode(mode.into()).map_err(map_error)
    }
    pub fn core_settings(&self) -> Result<CoreSettings, FluxError> {
        self.core.core_settings().map(Into::into).map_err(map_error)
    }
    pub fn set_retention(&self, retention: ReadArticleRetention) -> Result<(), FluxError> {
        self.core.set_retention(retention.into()).map_err(map_error)
    }
    pub fn set_background_sync_enabled(&self, enabled: bool) -> Result<(), FluxError> {
        self.core
            .set_background_sync_enabled(enabled)
            .map_err(map_error)
    }
    pub fn set_detail_character_limit(&self, limit: u32) -> Result<(), FluxError> {
        self.core
            .set_detail_character_limit(limit)
            .map_err(map_error)
    }
    pub fn set_read_state(&self, article_id: i64, read: bool) -> Result<MutationResult, FluxError> {
        self.core
            .set_read_state(article_id, read)
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn set_read_state_bulk(
        &self,
        article_ids: Vec<i64>,
        read: bool,
    ) -> Result<MutationResult, FluxError> {
        self.core
            .set_read_state_bulk(&article_ids, read)
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn set_starred_state(
        &self,
        article_id: i64,
        starred: bool,
    ) -> Result<MutationResult, FluxError> {
        self.core
            .set_starred_state(article_id, starred)
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn set_starred_state_bulk(
        &self,
        article_ids: Vec<i64>,
        starred: bool,
    ) -> Result<MutationResult, FluxError> {
        self.core
            .set_starred_state_bulk(&article_ids, starred)
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn save_to_service(&self, article_id: i64) -> Result<SaveToServiceResult, FluxError> {
        self.core
            .save_to_service(article_id)
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn discover_subscriptions(
        &self,
        request: DiscoverSubscriptionsRequest,
    ) -> Result<Vec<DiscoveredSubscription>, FluxError> {
        self.core
            .discover_subscriptions(request.into())
            .map(|subscriptions| subscriptions.into_iter().map(Into::into).collect())
            .map_err(map_error)
    }
    pub fn create_feed(&self, request: CreateFeedRequest) -> Result<CreateFeedResult, FluxError> {
        self.core
            .create_feed(request.into())
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn create_category(&self, title: String) -> Result<CreateCategoryResult, FluxError> {
        self.core
            .create_category(title)
            .map(Into::into)
            .map_err(map_error)
    }
    pub fn subscribe_events(
        &self,
        listener: Arc<dyn EventListener>,
    ) -> Result<Arc<EventSubscription>, FluxError> {
        let id = self
            .core
            .subscribe_events(Arc::new(ListenerBridge { listener }))
            .map_err(map_error)?;
        Ok(Arc::new(EventSubscription {
            core: self.core.clone(),
            id,
        }))
    }
    pub fn subscribe_diagnostics(
        &self,
        listener: Arc<dyn DiagnosticListener>,
    ) -> Arc<DiagnosticSubscription> {
        let id = self
            .core
            .subscribe_diagnostics(Arc::new(DiagnosticListenerBridge { listener }));
        Arc::new(DiagnosticSubscription {
            core: self.core.clone(),
            id,
        })
    }
}
#[uniffi::export]
impl EventSubscription {
    pub fn unsubscribe(&self) -> Result<(), FluxError> {
        self.core.unsubscribe_events(self.id).map_err(map_error)
    }
}

// UniFFI's foreign handle may be released without an explicit unsubscribe.
// Always release the Core listener before dropping the last subscription Arc.
// unsubscribe_events is idempotent, so an earlier explicit call stays safe.
impl Drop for EventSubscription {
    fn drop(&mut self) {
        let _ = self.core.unsubscribe_events(self.id);
    }
}
#[uniffi::export]
impl DiagnosticSubscription {
    pub fn unsubscribe(&self) {
        self.core.unsubscribe_diagnostics(self.id);
    }
}
struct ListenerBridge {
    listener: Arc<dyn EventListener>,
}
impl flux_core::CoreEventListener for ListenerBridge {
    fn on_event(&self, event: domain::CoreEvent) {
        self.listener.on_event(event.into())
    }
}
struct DiagnosticListenerBridge {
    listener: Arc<dyn DiagnosticListener>,
}
impl flux_core::diagnostics::CoreDiagnosticListener for DiagnosticListenerBridge {
    fn on_diagnostic(&self, record: flux_core::diagnostics::DiagnosticRecord) {
        self.listener.on_diagnostic(record.into())
    }
}

impl From<ArticleScope> for domain::ArticleScope {
    fn from(value: ArticleScope) -> Self {
        match value {
            ArticleScope::All => Self::All,
            ArticleScope::Category { id } => Self::Category(id),
            ArticleScope::Feed { id } => Self::Feed(id),
        }
    }
}
impl From<ReadFilter> for domain::ReadFilter {
    fn from(value: ReadFilter) -> Self {
        match value {
            ReadFilter::All => Self::All,
            ReadFilter::Read => Self::Read,
            ReadFilter::Unread => Self::Unread,
        }
    }
}
impl From<StarredFilter> for domain::StarredFilter {
    fn from(value: StarredFilter) -> Self {
        match value {
            StarredFilter::All => Self::All,
            StarredFilter::Starred => Self::Starred,
            StarredFilter::Unstarred => Self::Unstarred,
        }
    }
}
impl From<ArticleSort> for domain::ArticleSort {
    fn from(value: ArticleSort) -> Self {
        match value {
            ArticleSort::NewestFirst => Self::NewestFirst,
            ArticleSort::OldestFirst => Self::OldestFirst,
        }
    }
}
impl From<SyncReason> for domain::SyncReason {
    fn from(value: SyncReason) -> Self {
        match value {
            SyncReason::Manual => Self::Manual,
            SyncReason::AppStart => Self::AppStart,
            SyncReason::Resume => Self::Resume,
            SyncReason::Background => Self::Background,
            SyncReason::Periodic => Self::Periodic,
            SyncReason::Widget => Self::Widget,
        }
    }
}
impl From<DeliveryMode> for domain::DeliveryMode {
    fn from(value: DeliveryMode) -> Self {
        match value {
            DeliveryMode::Live => Self::Live,
            DeliveryMode::Deferred => Self::Deferred,
        }
    }
}
impl From<ReadArticleRetention> for domain::ReadArticleRetention {
    fn from(value: ReadArticleRetention) -> Self {
        match value {
            ReadArticleRetention::Days30 => Self::Days30,
            ReadArticleRetention::Days60 => Self::Days60,
            ReadArticleRetention::Days90 => Self::Days90,
            ReadArticleRetention::Days180 => Self::Days180,
            ReadArticleRetention::Days365 => Self::Days365,
        }
    }
}
impl From<DetailRenderingMode> for domain::DetailRenderingMode {
    fn from(value: DetailRenderingMode) -> Self {
        match value {
            DetailRenderingMode::Rendered => Self::Rendered,
            DetailRenderingMode::TextOnly => Self::TextOnly,
        }
    }
}
impl From<CoreSettings> for domain::CoreSettings {
    fn from(value: CoreSettings) -> Self {
        Self {
            retention: value.retention.into(),
            delivery_mode: value.delivery_mode.into(),
            background_sync_enabled: value.background_sync_enabled,
            detail_character_limit: value.detail_character_limit,
            download_network_policy: value.download_network_policy.into(),
            download_retention: value.download_retention.into(),
            delete_after_playback: value.delete_after_playback,
            auto_download_listening_list: value.auto_download_listening_list,
            remove_completed_listening_list: value.remove_completed_listening_list,
        }
    }
}
impl From<FeedPreferences> for domain::FeedPreferences {
    fn from(value: FeedPreferences) -> Self {
        Self {
            feed_id: value.feed_id,
            system_notifications_enabled: value.system_notifications_enabled,
            detail_rendering: value.detail_rendering.into(),
            truncate_detail: value.truncate_detail,
            open_in_miniflux: value.open_in_miniflux,
            auto_download_audio: value.auto_download_audio,
        }
    }
}
impl From<FeedPreferencesPatch> for domain::FeedPreferencesPatch {
    fn from(value: FeedPreferencesPatch) -> Self {
        Self {
            system_notifications_enabled: value.system_notifications_enabled,
            detail_rendering: value.detail_rendering.map(Into::into),
            truncate_detail: value.truncate_detail,
            open_in_miniflux: value.open_in_miniflux,
            auto_download_audio: value.auto_download_audio,
        }
    }
}
impl From<BackupPlatform> for config_backup::BackupPlatform {
    fn from(value: BackupPlatform) -> Self {
        match value {
            BackupPlatform::Macos => Self::Macos,
            BackupPlatform::Ios => Self::Ios,
            BackupPlatform::Android => Self::Android,
        }
    }
}
impl From<config_backup::BackupPlatform> for BackupPlatform {
    fn from(value: config_backup::BackupPlatform) -> Self {
        match value {
            config_backup::BackupPlatform::Macos => Self::Macos,
            config_backup::BackupPlatform::Ios => Self::Ios,
            config_backup::BackupPlatform::Android => Self::Android,
        }
    }
}
impl TryFrom<PlatformSettingsPayload> for config_backup::PlatformSettingsPayload {
    type Error = ConfigBackupError;
    fn try_from(value: PlatformSettingsPayload) -> Result<Self, Self::Error> {
        Ok(Self {
            schema_version: value.schema_version,
            data: serde_json::from_str(&value.data_json)
                .map_err(|_| ConfigBackupError::InvalidContents)?,
        })
    }
}
impl TryFrom<ConfigBackupInput> for config_backup::ConfigBackupInput {
    type Error = ConfigBackupError;
    fn try_from(value: ConfigBackupInput) -> Result<Self, Self::Error> {
        Ok(Self {
            platform: value.platform.into(),
            account: config_backup::BackupAccount {
                installation_base: value.account.installation_base,
                api_key: value.account.api_key,
            },
            core_settings: value.core_settings.into(),
            feed_preferences: value.feed_preferences.into_iter().map(Into::into).collect(),
            platform_settings: value.platform_settings.try_into()?,
        })
    }
}
impl From<config_backup::ConfigBackupRestoreModel> for ConfigBackupRestoreModel {
    fn from(value: config_backup::ConfigBackupRestoreModel) -> Self {
        Self {
            platform: value.platform.into(),
            account: BackupAccount {
                installation_base: value.account.installation_base,
                api_key: value.account.api_key,
            },
            core_settings: value.core_settings.into(),
            feed_preferences: value.feed_preferences.into_iter().map(Into::into).collect(),
            platform_settings: PlatformSettingsPayload {
                schema_version: value.platform_settings.schema_version,
                data_json: value.platform_settings.data.to_string(),
            },
        }
    }
}
impl From<flux_core::ConfigurationSnapshot> for ConfigurationSnapshot {
    fn from(value: flux_core::ConfigurationSnapshot) -> Self {
        Self {
            installation_base: value.installation_base,
            core_settings: value.core_settings.into(),
            feed_preferences: value.feed_preferences.into_iter().map(Into::into).collect(),
        }
    }
}
impl From<config_backup::ConfigBackupError> for ConfigBackupError {
    fn from(value: config_backup::ConfigBackupError) -> Self {
        match value {
            config_backup::ConfigBackupError::EmptyPassword => Self::EmptyPassword,
            config_backup::ConfigBackupError::NotFluxBackup => Self::NotFluxBackup,
            config_backup::ConfigBackupError::UnsupportedVersion => Self::UnsupportedVersion,
            config_backup::ConfigBackupError::PlatformMismatch => Self::PlatformMismatch,
            config_backup::ConfigBackupError::InvalidCryptoMetadata => Self::InvalidCryptoMetadata,
            config_backup::ConfigBackupError::DecryptionFailed => Self::DecryptionFailed,
            config_backup::ConfigBackupError::MalformedPayload => Self::MalformedPayload,
            config_backup::ConfigBackupError::InvalidContents => Self::InvalidContents,
            config_backup::ConfigBackupError::InputTooLarge => Self::InputTooLarge,
            config_backup::ConfigBackupError::Internal => Self::Internal,
        }
    }
}
impl From<domain::CoreSettings> for CoreSettings {
    fn from(value: domain::CoreSettings) -> Self {
        Self {
            retention: match value.retention {
                domain::ReadArticleRetention::Days30 => ReadArticleRetention::Days30,
                domain::ReadArticleRetention::Days60 => ReadArticleRetention::Days60,
                domain::ReadArticleRetention::Days90 => ReadArticleRetention::Days90,
                domain::ReadArticleRetention::Days180 => ReadArticleRetention::Days180,
                domain::ReadArticleRetention::Days365 => ReadArticleRetention::Days365,
            },
            delivery_mode: match value.delivery_mode {
                domain::DeliveryMode::Live => DeliveryMode::Live,
                domain::DeliveryMode::Deferred => DeliveryMode::Deferred,
            },
            background_sync_enabled: value.background_sync_enabled,
            detail_character_limit: value.detail_character_limit,
            download_network_policy: value.download_network_policy.into(),
            download_retention: value.download_retention.into(),
            delete_after_playback: value.delete_after_playback,
            auto_download_listening_list: value.auto_download_listening_list,
            remove_completed_listening_list: value.remove_completed_listening_list,
        }
    }
}
impl From<domain::MutationResult> for MutationResult {
    fn from(value: domain::MutationResult) -> Self {
        Self {
            disposition: match value.disposition {
                domain::DeliveryDisposition::Queued => DeliveryDisposition::Queued,
                domain::DeliveryDisposition::Delivered => DeliveryDisposition::Delivered,
                domain::DeliveryDisposition::DeferredByBackoff => {
                    DeliveryDisposition::DeferredByBackoff
                }
            },
        }
    }
}
impl From<domain::SaveToServiceResult> for SaveToServiceResult {
    fn from(value: domain::SaveToServiceResult) -> Self {
        match value {
            domain::SaveToServiceResult::Saved => Self::Saved,
            domain::SaveToServiceResult::NoIntegrationConfigured => Self::NoIntegrationConfigured,
        }
    }
}
impl From<DiscoverSubscriptionsRequest> for domain::DiscoverSubscriptionsRequest {
    fn from(value: DiscoverSubscriptionsRequest) -> Self {
        Self {
            url: value.url,
            username: value.username,
            password: value.password,
            user_agent: value.user_agent,
            fetch_via_proxy: value.fetch_via_proxy,
        }
    }
}
impl From<domain::DiscoveredSubscription> for DiscoveredSubscription {
    fn from(value: domain::DiscoveredSubscription) -> Self {
        Self {
            url: value.url,
            title: value.title,
            feed_type: value.feed_type,
        }
    }
}
impl From<CreateFeedRequest> for domain::CreateFeedRequest {
    fn from(value: CreateFeedRequest) -> Self {
        Self {
            feed_url: value.feed_url,
            category_id: value.category_id,
            username: value.username,
            password: value.password,
            crawler: value.crawler,
            user_agent: value.user_agent,
            scraper_rules: value.scraper_rules,
            rewrite_rules: value.rewrite_rules,
            blocklist_rules: value.blocklist_rules,
            keeplist_rules: value.keeplist_rules,
            disabled: value.disabled,
            ignore_http_cache: value.ignore_http_cache,
            fetch_via_proxy: value.fetch_via_proxy,
        }
    }
}
impl From<domain::CreateFeedResult> for CreateFeedResult {
    fn from(value: domain::CreateFeedResult) -> Self {
        Self {
            feed_id: value.feed_id,
        }
    }
}
impl From<domain::CreateCategoryResult> for CreateCategoryResult {
    fn from(value: domain::CreateCategoryResult) -> Self {
        Self {
            category_id: value.category_id,
        }
    }
}
impl From<domain::MutationField> for MutationField {
    fn from(value: domain::MutationField) -> Self {
        match value {
            domain::MutationField::Read => Self::Read,
            domain::MutationField::Starred => Self::Starred,
        }
    }
}
impl From<flux_core::diagnostics::DiagnosticLevel> for DiagnosticLevel {
    fn from(value: flux_core::diagnostics::DiagnosticLevel) -> Self {
        match value {
            flux_core::diagnostics::DiagnosticLevel::Trace => Self::Trace,
            flux_core::diagnostics::DiagnosticLevel::Debug => Self::Debug,
            flux_core::diagnostics::DiagnosticLevel::Info => Self::Info,
            flux_core::diagnostics::DiagnosticLevel::Warn => Self::Warn,
            flux_core::diagnostics::DiagnosticLevel::Error => Self::Error,
        }
    }
}
impl From<flux_core::diagnostics::DiagnosticRecord> for DiagnosticRecord {
    fn from(value: flux_core::diagnostics::DiagnosticRecord) -> Self {
        Self {
            level: value.level.into(),
            target: value.target,
            message: value.message,
        }
    }
}
impl From<domain::CoreErrorKind> for ErrorKind {
    fn from(value: domain::CoreErrorKind) -> Self {
        match value {
            domain::CoreErrorKind::Connectivity => Self::Connectivity,
            domain::CoreErrorKind::Authentication => Self::Authentication,
            domain::CoreErrorKind::InvalidConfiguration => Self::InvalidConfiguration,
            domain::CoreErrorKind::ServerTransient => Self::ServerTransient,
            domain::CoreErrorKind::Persistence => Self::Persistence,
            domain::CoreErrorKind::Data => Self::Data,
            domain::CoreErrorKind::Internal => Self::Internal,
        }
    }
}
impl From<flux_core::miniflux::AccountValidationResult> for AccountValidationResult {
    fn from(value: flux_core::miniflux::AccountValidationResult) -> Self {
        Self {
            installation_base: value.installation_base,
            version: value.version,
        }
    }
}
impl From<HttpHeader> for flux_core::miniflux::HttpHeader {
    fn from(value: HttpHeader) -> Self {
        Self {
            name: value.name,
            value: value.value,
        }
    }
}
impl From<domain::CoreEvent> for CoreEvent {
    fn from(value: domain::CoreEvent) -> Self {
        match value {
            domain::CoreEvent::ArticleReadStateChanged { article_id, read } => {
                Self::ArticleReadStateChanged { article_id, read }
            }
            domain::CoreEvent::ArticleStarredStateChanged {
                article_id,
                starred,
            } => Self::ArticleStarredStateChanged {
                article_id,
                starred,
            },
            domain::CoreEvent::MutationQueued { article_id, field } => Self::MutationQueued {
                article_id,
                field: field.into(),
            },
            domain::CoreEvent::MutationDeliverySucceeded { article_id, field } => {
                Self::MutationDeliverySucceeded {
                    article_id,
                    field: field.into(),
                }
            }
            domain::CoreEvent::MutationDeliveryFailed {
                article_id,
                field,
                error_kind,
            } => Self::MutationDeliveryFailed {
                article_id,
                field: field.into(),
                error_kind: error_kind.into(),
            },
            domain::CoreEvent::SyncCompleted(metadata) => Self::SyncDidComplete {
                metadata: metadata.into(),
            },
            domain::CoreEvent::SyncFailed(metadata) => Self::SyncDidFail {
                metadata: metadata.into(),
            },
        }
    }
}
impl From<ArticleQuery> for domain::ArticleQuery {
    fn from(value: ArticleQuery) -> Self {
        Self {
            scope: value.scope.into(),
            read_filter: value.read_filter.into(),
            starred_filter: value.starred_filter.into(),
            sort: value.sort.into(),
            limit: value.limit,
            cursor: value.cursor.map(|c| domain::ArticleCursor {
                published_at: c.published_at,
                article_id: c.article_id,
            }),
        }
    }
}
impl From<SearchArticlesRequest> for domain::SearchArticlesRequest {
    fn from(value: SearchArticlesRequest) -> Self {
        Self {
            query: value.query,
            offset: value.offset,
            limit: value.limit,
        }
    }
}
impl From<domain::SearchArticlesResult> for SearchArticlesResult {
    fn from(value: domain::SearchArticlesResult) -> Self {
        Self {
            total: value.total,
            articles: value.articles.into_iter().map(Into::into).collect(),
        }
    }
}
impl From<domain::SearchMutationDisposition> for SearchMutationDisposition {
    fn from(value: domain::SearchMutationDisposition) -> Self {
        match value {
            domain::SearchMutationDisposition::LocalFirst => Self::LocalFirst,
            domain::SearchMutationDisposition::RemoteOnly => Self::RemoteOnly,
        }
    }
}
impl From<domain::ArticleSummary> for ArticleSummary {
    fn from(value: domain::ArticleSummary) -> Self {
        Self {
            id: value.id,
            feed_id: value.feed_id,
            category_id: value.category_id,
            feed_title: value.feed_title,
            title: value.title,
            url: value.url,
            comments_url: value.comments_url,
            published_at: value.published_at,
            is_read: value.is_read,
            is_starred: value.is_starred,
            reading_time_minutes: value.reading_time_minutes,
            preview: value.preview,
            image_url: value.image_url,
        }
    }
}
impl From<domain::ArticlePage> for ArticlePage {
    fn from(value: domain::ArticlePage) -> Self {
        Self {
            articles: value.articles.into_iter().map(Into::into).collect(),
            total: value.total,
            next_cursor: value.next_cursor.map(|cursor| ArticleCursor {
                published_at: cursor.published_at,
                article_id: cursor.article_id,
            }),
        }
    }
}
impl From<domain::ArticleAudioActionProjection> for ArticleAudioActionProjection {
    fn from(value: domain::ArticleAudioActionProjection) -> Self {
        Self {
            article_id: value.article_id,
            enclosures: value.enclosures.into_iter().map(Into::into).collect(),
            is_in_listening_list: value.is_in_listening_list,
            downloads: value.downloads.into_iter().map(Into::into).collect(),
        }
    }
}
impl From<domain::ReaderDocument> for ReaderDocument {
    fn from(value: domain::ReaderDocument) -> Self {
        Self {
            blocks: value.blocks.into_iter().map(Into::into).collect(),
            has_simplified_content: value.has_simplified_content,
            was_truncated: value.was_truncated,
        }
    }
}
impl From<domain::ReaderBlock> for ReaderBlock {
    fn from(value: domain::ReaderBlock) -> Self {
        match value {
            domain::ReaderBlock::Paragraph { inlines } => Self::Paragraph {
                inlines: inlines.into_iter().map(Into::into).collect(),
            },
            domain::ReaderBlock::Heading { level, inlines } => Self::Heading {
                level,
                inlines: inlines.into_iter().map(Into::into).collect(),
            },
            domain::ReaderBlock::Image { url, alt, link } => Self::Image { url, alt, link },
            domain::ReaderBlock::List { ordered, items } => Self::ListBlock {
                ordered,
                items: items.into_iter().map(Into::into).collect(),
            },
            domain::ReaderBlock::Quote { blocks } => Self::Quote {
                blocks: blocks.into_iter().map(Into::into).collect(),
            },
            domain::ReaderBlock::CodeBlock { text } => Self::CodeBlock { text },
            domain::ReaderBlock::HorizontalRule => Self::HorizontalRule,
            domain::ReaderBlock::ExternalContent { url, label } => {
                Self::ExternalContent { url, label }
            }
        }
    }
}
impl From<domain::ReaderListItem> for ReaderListItem {
    fn from(value: domain::ReaderListItem) -> Self {
        Self {
            blocks: value.blocks.into_iter().map(Into::into).collect(),
        }
    }
}
impl From<domain::ReaderInline> for ReaderInline {
    fn from(value: domain::ReaderInline) -> Self {
        match value {
            domain::ReaderInline::Text { text } => Self::Text { text },
            domain::ReaderInline::Bold { inlines } => Self::Bold {
                inlines: inlines.into_iter().map(Into::into).collect(),
            },
            domain::ReaderInline::Italic { inlines } => Self::Italic {
                inlines: inlines.into_iter().map(Into::into).collect(),
            },
            domain::ReaderInline::Code { text } => Self::Code { text },
            domain::ReaderInline::Link { url, inlines } => Self::Link {
                url,
                inlines: inlines.into_iter().map(Into::into).collect(),
            },
        }
    }
}
impl From<domain::Category> for Category {
    fn from(value: domain::Category) -> Self {
        Self {
            id: value.id,
            title: value.title,
        }
    }
}
impl From<domain::Feed> for Feed {
    fn from(value: domain::Feed) -> Self {
        Self {
            id: value.id,
            category_id: value.category_id,
            title: value.title,
        }
    }
}
impl From<FeedIconVariant> for domain::FeedIconVariant {
    fn from(value: FeedIconVariant) -> Self {
        match value {
            FeedIconVariant::Normal => Self::Normal,
            FeedIconVariant::Dark => Self::Dark,
        }
    }
}
impl From<domain::FeedIconVariant> for FeedIconVariant {
    fn from(value: domain::FeedIconVariant) -> Self {
        match value {
            domain::FeedIconVariant::Normal => Self::Normal,
            domain::FeedIconVariant::Dark => Self::Dark,
        }
    }
}
impl From<domain::FeedIcon> for FeedIcon {
    fn from(value: domain::FeedIcon) -> Self {
        Self {
            feed_id: value.feed_id,
            variant: value.variant.into(),
            png_data: value.png_data,
        }
    }
}
impl From<domain::ArticleThumbnailResult> for ArticleThumbnailResult {
    fn from(value: domain::ArticleThumbnailResult) -> Self {
        match value {
            domain::ArticleThumbnailResult::Available { png_data } => Self::Available { png_data },
            domain::ArticleThumbnailResult::Unavailable => Self::Unavailable,
        }
    }
}
impl From<domain::NavigationCatalog> for NavigationCatalog {
    fn from(value: domain::NavigationCatalog) -> Self {
        Self {
            categories: value.categories.into_iter().map(Into::into).collect(),
            feeds: value.feeds.into_iter().map(Into::into).collect(),
        }
    }
}
impl From<NavigationCountMode> for domain::NavigationCountMode {
    fn from(value: NavigationCountMode) -> Self {
        match value {
            NavigationCountMode::Unread => Self::Unread,
            NavigationCountMode::All => Self::All,
        }
    }
}
impl From<domain::NavigationProjection> for NavigationProjection {
    fn from(value: domain::NavigationProjection) -> Self {
        Self {
            catalog: value.catalog.into(),
            unread_total: value.unread_total,
            starred_total: value.starred_total,
            category_counts: value.category_counts.into_iter().map(Into::into).collect(),
            feed_counts: value.feed_counts.into_iter().map(Into::into).collect(),
        }
    }
}
impl From<domain::NavigationScopedCount> for NavigationScopedCount {
    fn from(value: domain::NavigationScopedCount) -> Self {
        Self {
            id: value.id,
            count: value.count,
        }
    }
}
impl From<domain::WidgetData> for WidgetData {
    fn from(value: domain::WidgetData) -> Self {
        Self {
            categories: value.categories.into_iter().map(Into::into).collect(),
            feeds: value.feeds.into_iter().map(Into::into).collect(),
            articles: value.articles.into_iter().map(Into::into).collect(),
            counts: value.counts.into(),
            last_successful_sync_at: value.last_successful_sync_at,
        }
    }
}
impl From<domain::WidgetArticle> for WidgetArticle {
    fn from(value: domain::WidgetArticle) -> Self {
        Self {
            id: value.id,
            feed_id: value.feed_id,
            category_id: value.category_id,
            feed_title: value.feed_title,
            title: value.title,
            published_at: value.published_at,
            is_read: value.is_read,
            is_starred: value.is_starred,
        }
    }
}
impl From<domain::WidgetArticlePage> for WidgetArticlePage {
    fn from(value: domain::WidgetArticlePage) -> Self {
        Self {
            articles: value.articles.into_iter().map(Into::into).collect(),
            next_cursor: value.next_cursor.map(|cursor| ArticleCursor {
                published_at: cursor.published_at,
                article_id: cursor.article_id,
            }),
        }
    }
}
impl From<domain::WidgetCounts> for WidgetCounts {
    fn from(value: domain::WidgetCounts) -> Self {
        Self {
            all_unread: value.all_unread,
            all_articles: value.all_articles,
            bookmarks: value.bookmarks,
            bookmarks_unread: value.bookmarks_unread,
            feed_unread: value.feed_unread.into_iter().map(Into::into).collect(),
            feed_all: value.feed_all.into_iter().map(Into::into).collect(),
            category_unread: value.category_unread.into_iter().map(Into::into).collect(),
            category_all: value.category_all.into_iter().map(Into::into).collect(),
        }
    }
}
impl From<domain::WidgetScopedCount> for WidgetScopedCount {
    fn from(value: domain::WidgetScopedCount) -> Self {
        Self {
            id: value.id,
            count: value.count,
        }
    }
}
impl From<domain::RuntimeHealth> for RuntimeHealth {
    fn from(value: domain::RuntimeHealth) -> Self {
        match value {
            domain::RuntimeHealth::Healthy => Self::Healthy,
            domain::RuntimeHealth::ConnectivityDegraded => Self::ConnectivityDegraded,
            domain::RuntimeHealth::ServerDegraded => Self::ServerDegraded,
        }
    }
}
impl From<domain::RuntimeHealthStatus> for RuntimeHealthStatus {
    fn from(value: domain::RuntimeHealthStatus) -> Self {
        Self {
            health: value.health.into(),
            next_retry_at: value.next_retry_at,
        }
    }
}
impl From<domain::SyncCompleted> for SyncCompleted {
    fn from(value: domain::SyncCompleted) -> Self {
        Self {
            reason: match value.reason {
                domain::SyncReason::Manual => SyncReason::Manual,
                domain::SyncReason::AppStart => SyncReason::AppStart,
                domain::SyncReason::Resume => SyncReason::Resume,
                domain::SyncReason::Background => SyncReason::Background,
                domain::SyncReason::Periodic => SyncReason::Periodic,
                domain::SyncReason::Widget => SyncReason::Widget,
            },
            new_articles: value.new_articles,
            updated_articles: value.updated_articles,
            mutations_delivered: value.mutations_delivered,
            data_changed: value.data_changed,
            navigation_changed: value.navigation_changed,
            new_articles_by_feed: value
                .new_articles_by_feed
                .into_iter()
                .map(Into::into)
                .collect(),
            system_notification_candidates: value
                .system_notification_candidates
                .into_iter()
                .map(Into::into)
                .collect(),
        }
    }
}
impl From<domain::NewArticlesByFeed> for NewArticlesByFeed {
    fn from(value: domain::NewArticlesByFeed) -> Self {
        Self {
            feed_id: value.feed_id,
            count: value.count,
        }
    }
}
impl From<domain::FeedSystemNotificationSetting> for FeedSystemNotificationSetting {
    fn from(value: domain::FeedSystemNotificationSetting) -> Self {
        Self {
            feed_id: value.feed_id,
            feed_title: value.feed_title,
            system_notifications_enabled: value.system_notifications_enabled,
        }
    }
}
impl From<domain::FeedPreferences> for FeedPreferences {
    fn from(value: domain::FeedPreferences) -> Self {
        Self {
            feed_id: value.feed_id,
            system_notifications_enabled: value.system_notifications_enabled,
            detail_rendering: match value.detail_rendering {
                domain::DetailRenderingMode::Rendered => DetailRenderingMode::Rendered,
                domain::DetailRenderingMode::TextOnly => DetailRenderingMode::TextOnly,
            },
            truncate_detail: value.truncate_detail,
            open_in_miniflux: value.open_in_miniflux,
            auto_download_audio: value.auto_download_audio,
        }
    }
}
impl From<domain::Enclosure> for Enclosure {
    fn from(value: domain::Enclosure) -> Self {
        let media_kind = value.media_kind().into();
        Self {
            id: value.id,
            article_id: value.article_id,
            url: value.url,
            mime_type: value.mime_type,
            size_bytes: value.size_bytes,
            remote_media_progression_seconds: value.remote_media_progression_seconds,
            media_kind,
        }
    }
}
impl From<ListeningListSort> for domain::ListeningListSort {
    fn from(value: ListeningListSort) -> Self {
        match value {
            ListeningListSort::RecentlyAdded => Self::RecentlyAdded,
            ListeningListSort::PublicationDate => Self::PublicationDate,
        }
    }
}
impl From<domain::ListeningListEnclosure> for ListeningListEnclosure {
    fn from(value: domain::ListeningListEnclosure) -> Self {
        Self {
            enclosure: value.enclosure.into(),
            remote_present: value.remote_present,
            playback_state: value.playback_state.map(Into::into),
            download: value.download.map(Into::into),
            duration_ms: value.duration_ms,
        }
    }
}
impl From<domain::ListeningListItem> for ListeningListItem {
    fn from(value: domain::ListeningListItem) -> Self {
        Self {
            article_id: value.article_id,
            feed_id: value.feed_id,
            title: value.title,
            feed_title: value.feed_title,
            published_at: value.published_at,
            added_at: value.added_at,
            remote_present: value.remote_present,
            audio_enclosures: value.audio_enclosures.into_iter().map(Into::into).collect(),
            active_enclosure_id: value.active_enclosure_id,
        }
    }
}
impl From<domain::ListeningListFeed> for ListeningListFeed {
    fn from(value: domain::ListeningListFeed) -> Self {
        Self {
            feed_id: value.feed_id,
            feed_title: value.feed_title,
            item_count: value.item_count,
        }
    }
}
impl From<domain::MediaKind> for MediaKind {
    fn from(value: domain::MediaKind) -> Self {
        match value {
            domain::MediaKind::Audio => Self::Audio,
            domain::MediaKind::Video => Self::Video,
            domain::MediaKind::Image => Self::Image,
            domain::MediaKind::Other => Self::Other,
        }
    }
}
impl From<domain::PlaybackStatus> for PlaybackStatus {
    fn from(value: domain::PlaybackStatus) -> Self {
        match value {
            domain::PlaybackStatus::InProgress => Self::InProgress,
            domain::PlaybackStatus::Completed => Self::Completed,
        }
    }
}
impl From<domain::PlaybackState> for PlaybackState {
    fn from(value: domain::PlaybackState) -> Self {
        Self {
            enclosure_id: value.enclosure_id,
            position_ms: value.position_ms,
            duration_ms: value.duration_ms,
            status: value.status.into(),
            updated_at: Some(value.updated_at),
        }
    }
}

impl From<domain::ContinueListeningItem> for ContinueListeningItem {
    fn from(value: domain::ContinueListeningItem) -> Self {
        Self {
            enclosure_id: value.enclosure_id,
            article_id: value.article_id,
            feed_id: value.feed_id,
            title: value.title,
            feed_title: value.feed_title,
            published_at: value.published_at,
            url: value.url,
            mime_type: value.mime_type,
            position_ms: value.position_ms,
            duration_ms: value.duration_ms,
            updated_at: value.updated_at,
            local_file: value.local_file,
        }
    }
}
impl From<LegacyPlaybackImport> for domain::LegacyPlaybackImport {
    fn from(value: LegacyPlaybackImport) -> Self {
        Self {
            article_id: value.article_id,
            position_ms: value.position_ms,
            updated_at: value.updated_at,
        }
    }
}
impl From<domain::LegacyPlaybackImportResult> for LegacyPlaybackImportResult {
    fn from(value: domain::LegacyPlaybackImportResult) -> Self {
        Self {
            imported: value.imported,
            skipped_missing: value.skipped_missing,
            skipped_ambiguous: value.skipped_ambiguous,
            already_present: value.already_present,
        }
    }
}
impl From<domain::LegacyDownloadImportOutcome> for LegacyDownloadImportOutcome {
    fn from(value: domain::LegacyDownloadImportOutcome) -> Self {
        match value {
            domain::LegacyDownloadImportOutcome::Imported => Self::Imported,
            domain::LegacyDownloadImportOutcome::AlreadyPresent => Self::AlreadyPresent,
            domain::LegacyDownloadImportOutcome::MissingEnclosure => Self::MissingEnclosure,
        }
    }
}

impl From<domain::LegacyFeedOpenInMinifluxImportOutcome> for LegacyFeedOpenInMinifluxImportOutcome {
    fn from(value: domain::LegacyFeedOpenInMinifluxImportOutcome) -> Self {
        match value {
            domain::LegacyFeedOpenInMinifluxImportOutcome::Imported => Self::Imported,
            domain::LegacyFeedOpenInMinifluxImportOutcome::AlreadyPresent => Self::AlreadyPresent,
            domain::LegacyFeedOpenInMinifluxImportOutcome::MissingFeed => Self::MissingFeed,
        }
    }
}
impl From<domain::MediaArtworkSource> for MediaArtworkSource {
    fn from(value: domain::MediaArtworkSource) -> Self {
        match value {
            domain::MediaArtworkSource::LocalReference(reference) => {
                Self::LocalReference { reference }
            }
            domain::MediaArtworkSource::RemoteUrl(url) => Self::RemoteUrl { url },
        }
    }
}
impl From<domain::PlaybackPreparation> for PlaybackPreparation {
    fn from(value: domain::PlaybackPreparation) -> Self {
        let domain::PlaybackPreparation {
            enclosure,
            article_title,
            feed_title,
            playback_state,
            local_file,
            duration_ms,
            artwork_source,
        } = value;
        let enclosure_id = enclosure.id;
        Self {
            enclosure: enclosure.into(),
            article_title,
            feed_title,
            playback_state: playback_state.map(Into::into).unwrap_or(PlaybackState {
                enclosure_id,
                position_ms: 0,
                duration_ms: None,
                status: PlaybackStatus::NotStarted,
                updated_at: None,
            }),
            local_file,
            duration_ms,
            artwork_source: artwork_source.map(Into::into),
        }
    }
}
impl From<flux_core::MediaProgressCapability> for MediaProgressCapability {
    fn from(value: flux_core::MediaProgressCapability) -> Self {
        match value {
            flux_core::MediaProgressCapability::Unknown => Self::Unknown,
            flux_core::MediaProgressCapability::Supported => Self::Supported,
            flux_core::MediaProgressCapability::Unsupported => Self::Unsupported,
        }
    }
}
impl From<DownloadOrigin> for domain::DownloadOrigin {
    fn from(value: DownloadOrigin) -> Self {
        match value {
            DownloadOrigin::Manual => Self::Manual,
            DownloadOrigin::Automatic => Self::Automatic,
        }
    }
}
impl From<domain::DownloadOrigin> for DownloadOrigin {
    fn from(value: domain::DownloadOrigin) -> Self {
        match value {
            domain::DownloadOrigin::Manual => Self::Manual,
            domain::DownloadOrigin::Automatic => Self::Automatic,
        }
    }
}
impl From<domain::DownloadFailureKind> for DownloadFailureKind {
    fn from(value: domain::DownloadFailureKind) -> Self {
        match value {
            domain::DownloadFailureKind::Network => Self::Network,
            domain::DownloadFailureKind::Storage => Self::Storage,
            domain::DownloadFailureKind::InvalidMedia => Self::InvalidMedia,
            domain::DownloadFailureKind::Unknown => Self::Unknown,
        }
    }
}
impl From<DownloadFailureKind> for domain::DownloadFailureKind {
    fn from(value: DownloadFailureKind) -> Self {
        match value {
            DownloadFailureKind::Network => Self::Network,
            DownloadFailureKind::Storage => Self::Storage,
            DownloadFailureKind::InvalidMedia => Self::InvalidMedia,
            DownloadFailureKind::Unknown => Self::Unknown,
        }
    }
}
impl From<domain::DownloadState> for DownloadState {
    fn from(value: domain::DownloadState) -> Self {
        match value {
            domain::DownloadState::NotDownloaded => Self::NotDownloaded,
            domain::DownloadState::Requested => Self::Requested,
            domain::DownloadState::Downloaded => Self::Downloaded,
            domain::DownloadState::Failed => Self::Failed,
            domain::DownloadState::DeleteRequested => Self::DeleteRequested,
        }
    }
}
impl From<domain::MediaDownload> for MediaDownload {
    fn from(value: domain::MediaDownload) -> Self {
        Self {
            enclosure_id: value.enclosure_id,
            state: value.state.into(),
            origin: value.origin.map(Into::into),
            local_file: value.local_file,
            file_size_bytes: value.file_size_bytes,
            downloaded_at: value.downloaded_at,
            failure_kind: value.failure_kind.map(Into::into),
        }
    }
}
impl From<domain::DownloadedMediaSummary> for DownloadedMediaSummary {
    fn from(value: domain::DownloadedMediaSummary) -> Self {
        Self {
            file_count: value.file_count,
            total_size_bytes: value.total_size_bytes,
        }
    }
}
impl From<DownloadNetworkPolicy> for domain::DownloadNetworkPolicy {
    fn from(value: DownloadNetworkPolicy) -> Self {
        match value {
            DownloadNetworkPolicy::AnyNetwork => Self::AnyNetwork,
            DownloadNetworkPolicy::UnmeteredOnly => Self::UnmeteredOnly,
        }
    }
}
impl From<domain::DownloadNetworkPolicy> for DownloadNetworkPolicy {
    fn from(value: domain::DownloadNetworkPolicy) -> Self {
        match value {
            domain::DownloadNetworkPolicy::AnyNetwork => Self::AnyNetwork,
            domain::DownloadNetworkPolicy::UnmeteredOnly => Self::UnmeteredOnly,
        }
    }
}
impl From<DownloadRetention> for domain::DownloadRetention {
    fn from(value: DownloadRetention) -> Self {
        match value {
            DownloadRetention::Forever => Self::Forever,
            DownloadRetention::Days { days } => Self::Days(days),
        }
    }
}
impl From<domain::DownloadRetention> for DownloadRetention {
    fn from(value: domain::DownloadRetention) -> Self {
        match value {
            domain::DownloadRetention::Forever => Self::Forever,
            domain::DownloadRetention::Days(days) => Self::Days { days },
        }
    }
}
impl From<domain::MediaTransferWork> for MediaTransferWork {
    fn from(value: domain::MediaTransferWork) -> Self {
        Self {
            enclosure_id: value.enclosure_id,
            url: value.url,
            mime_type: value.mime_type,
            origin: value.origin.into(),
            local_file: value.local_file,
        }
    }
}
impl From<domain::MediaMetadata> for MediaMetadata {
    fn from(value: domain::MediaMetadata) -> Self {
        Self {
            enclosure_id: value.enclosure_id,
            duration_ms: value.duration_ms,
            embedded_artwork_reference: value.embedded_artwork_reference,
        }
    }
}
impl From<domain::MediaChapterSource> for MediaChapterSource {
    fn from(value: domain::MediaChapterSource) -> Self {
        match value {
            domain::MediaChapterSource::Embedded => Self::Embedded,
            domain::MediaChapterSource::ArticleContent => Self::ArticleContent,
        }
    }
}
impl From<domain::MediaChapter> for MediaChapter {
    fn from(value: domain::MediaChapter) -> Self {
        Self {
            enclosure_id: value.enclosure_id,
            title: value.title,
            start_ms: value.start_ms,
            end_ms: value.end_ms,
            source: value.source.into(),
        }
    }
}
impl From<domain::SavedPlayableMediaItem> for SavedPlayableMediaItem {
    fn from(value: domain::SavedPlayableMediaItem) -> Self {
        Self {
            enclosure_id: value.enclosure_id,
            article_id: value.article_id,
            feed_id: value.feed_id,
            title: value.title,
            feed_title: value.feed_title,
            published_at: value.published_at,
            added_at: value.added_at,
            url: value.url,
            mime_type: value.mime_type,
            media_kind: value.media_kind.into(),
            remote_present: value.remote_present,
            duration_ms: value.duration_ms,
            artwork_source: value.artwork_source.map(Into::into),
        }
    }
}
impl From<domain::SavedMediaSyncConfiguration> for SavedMediaSyncConfiguration {
    fn from(value: domain::SavedMediaSyncConfiguration) -> Self {
        Self {
            enabled: value.enabled,
            sync_feed_id: value.sync_feed_id,
            requires_repair: value.requires_repair,
        }
    }
}
impl From<domain::SavedMediaSyncSetupInfo> for SavedMediaSyncSetupInfo {
    fn from(value: domain::SavedMediaSyncSetupInfo) -> Self {
        Self {
            bootstrap_url: value.bootstrap_url,
            technical_feed_title: value.technical_feed_title,
            explanation: value.explanation,
        }
    }
}
impl From<domain::SystemNotificationCandidate> for SystemNotificationCandidate {
    fn from(value: domain::SystemNotificationCandidate) -> Self {
        Self {
            candidate_id: value.candidate_id,
            feed_id: value.feed_id,
            feed_title: value.feed_title,
            new_count: value.new_count,
        }
    }
}
impl From<domain::SyncFailure> for SyncFailed {
    fn from(value: domain::SyncFailure) -> Self {
        Self {
            reason: match value.reason {
                domain::SyncReason::Manual => SyncReason::Manual,
                domain::SyncReason::AppStart => SyncReason::AppStart,
                domain::SyncReason::Resume => SyncReason::Resume,
                domain::SyncReason::Background => SyncReason::Background,
                domain::SyncReason::Periodic => SyncReason::Periodic,
                domain::SyncReason::Widget => SyncReason::Widget,
            },
            error_kind: value.error_kind.into(),
            mutation_delivery_completed: value.mutation_delivery_completed,
            remote_fetch_started: value.remote_fetch_started,
            remote_fetch_completed: value.remote_fetch_completed,
            mutations_delivered: value.mutations_delivered,
        }
    }
}
fn map_error(error: domain::CoreError) -> FluxError {
    let detail = error.message;
    match error.kind {
        domain::CoreErrorKind::Connectivity => FluxError::Connectivity { detail },
        domain::CoreErrorKind::Authentication => FluxError::Authentication { detail },
        domain::CoreErrorKind::InvalidConfiguration => FluxError::InvalidConfiguration { detail },
        domain::CoreErrorKind::ServerTransient => FluxError::ServerTransient { detail },
        domain::CoreErrorKind::Persistence => FluxError::Persistence { detail },
        domain::CoreErrorKind::Data => FluxError::Data { detail },
        domain::CoreErrorKind::Internal => FluxError::Internal { detail },
    }
}
fn map_account_validation_error(
    error: flux_core::miniflux::AccountValidationError,
) -> AccountValidationError {
    match error {
        flux_core::miniflux::AccountValidationError::InvalidUrl => {
            AccountValidationError::InvalidUrl
        }
        flux_core::miniflux::AccountValidationError::UnsupportedUrlScheme => {
            AccountValidationError::UnsupportedUrlScheme
        }
        flux_core::miniflux::AccountValidationError::Network => AccountValidationError::Network,
        flux_core::miniflux::AccountValidationError::Unauthorized => {
            AccountValidationError::Unauthorized
        }
        flux_core::miniflux::AccountValidationError::IncompatibleServer => {
            AccountValidationError::IncompatibleServer
        }
        flux_core::miniflux::AccountValidationError::InvalidResponse => {
            AccountValidationError::InvalidResponse
        }
        flux_core::miniflux::AccountValidationError::ServerUnavailable => {
            AccountValidationError::ServerUnavailable
        }
        flux_core::miniflux::AccountValidationError::InvalidCustomHeader => {
            AccountValidationError::InvalidCustomHeader
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sync_cancellation_handle_is_monotonic_and_outcome_mapping_is_explicit() {
        let cancellation = SyncCancellation::new();
        assert!(!cancellation.is_cancelled());
        cancellation.cancel();
        assert!(cancellation.is_cancelled());

        let outcome = CoreSyncOutcome::Cancelled;
        let mapped = match outcome {
            CoreSyncOutcome::Completed(metadata) => SyncOutcome::Completed {
                metadata: metadata.into(),
            },
            CoreSyncOutcome::Cancelled => SyncOutcome::Cancelled,
        };
        assert!(matches!(mapped, SyncOutcome::Cancelled));
    }

    #[test]
    fn media_state_mappings_are_explicit_and_not_stringly_typed() {
        assert!(matches!(
            domain::DownloadState::DeleteRequested.into(),
            DownloadState::DeleteRequested
        ));
        assert!(matches!(
            domain::PlaybackStatus::Completed.into(),
            PlaybackStatus::Completed
        ));
        assert!(matches!(
            flux_core::MediaProgressCapability::Unknown.into(),
            MediaProgressCapability::Unknown
        ));
    }

    #[test]
    fn navigation_projection_mapping_preserves_catalog_totals_and_scoped_counts() {
        let mapped: NavigationProjection = domain::NavigationProjection {
            catalog: domain::NavigationCatalog {
                categories: vec![domain::Category {
                    id: 1,
                    title: "Category".into(),
                }],
                feeds: vec![domain::Feed {
                    id: 10,
                    category_id: 1,
                    title: "Feed".into(),
                }],
            },
            unread_total: 4,
            starred_total: 2,
            category_counts: vec![domain::NavigationScopedCount { id: 1, count: 3 }],
            feed_counts: vec![domain::NavigationScopedCount { id: 10, count: 3 }],
        }
        .into();

        assert_eq!(mapped.catalog.categories[0].title, "Category");
        assert_eq!(mapped.catalog.feeds[0].category_id, 1);
        assert_eq!(mapped.unread_total, 4);
        assert_eq!(mapped.starred_total, 2);
        assert_eq!(mapped.category_counts[0].count, 3);
        assert_eq!(mapped.feed_counts[0].id, 10);
        assert!(matches!(
            domain::NavigationCountMode::from(NavigationCountMode::All),
            domain::NavigationCountMode::All
        ));
    }

    #[test]
    fn article_page_mapping_preserves_total_and_cursor() {
        let mapped: ArticlePage = domain::ArticlePage {
            articles: vec![domain::ArticleSummary {
                id: 7,
                feed_id: 10,
                category_id: 2,
                feed_title: "Feed".into(),
                title: "Article".into(),
                url: "https://example.test/article".into(),
                comments_url: String::new(),
                published_at: "2026-01-01T00:00:00Z".into(),
                reading_time_minutes: 0,
                is_read: false,
                is_starred: true,
                preview: String::new(),
                image_url: None,
            }],
            total: Some(12),
            next_cursor: Some(domain::ArticleCursor {
                published_at: "2026-01-01T00:00:00Z".into(),
                article_id: 7,
            }),
        }
        .into();

        assert_eq!(mapped.articles[0].id, 7);
        assert_eq!(mapped.total, Some(12));
        assert_eq!(mapped.next_cursor.unwrap().article_id, 7);
    }

    #[test]
    fn media_read_models_preserve_identity_and_order_fields() {
        let enclosure = domain::Enclosure {
            id: 42,
            article_id: 7,
            url: "https://example.test/audio.mp3".to_string(),
            mime_type: "audio/mpeg".to_string(),
            size_bytes: Some(123),
            remote_media_progression_seconds: 9,
        };
        let mapped: Enclosure = enclosure.into();
        assert_eq!(mapped.id, 42);
        assert_eq!(mapped.article_id, 7);
        assert!(matches!(mapped.media_kind, MediaKind::Audio));

        let chapter = domain::MediaChapter {
            enclosure_id: 42,
            title: "Intro".to_string(),
            start_ms: 1_000,
            end_ms: Some(2_000),
            source: domain::MediaChapterSource::Embedded,
        };
        let mapped: MediaChapter = chapter.into();
        assert_eq!(mapped.start_ms, 1_000);
        assert_eq!(mapped.end_ms, Some(2_000));
        assert!(matches!(mapped.source, MediaChapterSource::Embedded));
    }

    #[test]
    fn listening_list_projection_preserves_news_identity_and_nested_media_state() {
        let projection: ListeningListItem = domain::ListeningListItem {
            article_id: 7,
            feed_id: 3,
            title: "Episode".into(),
            feed_title: "Feed".into(),
            published_at: "2026-01-01T00:00:00Z".into(),
            added_at: "2026-01-02T00:00:00Z".into(),
            remote_present: true,
            audio_enclosures: vec![domain::ListeningListEnclosure {
                enclosure: domain::Enclosure {
                    id: 42,
                    article_id: 7,
                    url: "https://example.test/audio.mp3".into(),
                    mime_type: "audio/mpeg".into(),
                    size_bytes: None,
                    remote_media_progression_seconds: 0,
                },
                remote_present: true,
                playback_state: None,
                download: None,
                duration_ms: Some(60_000),
            }],
            active_enclosure_id: Some(42),
        }
        .into();
        assert_eq!(projection.article_id, 7);
        assert_eq!(projection.audio_enclosures.len(), 1);
        assert_eq!(projection.audio_enclosures[0].enclosure.id, 42);
        assert_eq!(projection.audio_enclosures[0].duration_ms, Some(60_000));
        assert_eq!(projection.active_enclosure_id, Some(42));
    }
}
