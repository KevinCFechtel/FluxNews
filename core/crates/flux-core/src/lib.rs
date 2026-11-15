//! Shared durable Flux domain core. Platform clients provide paths and secrets.

pub mod article;
mod article_document;
mod article_thumbnail;
pub mod config_backup;
pub mod diagnostics;
pub mod domain;
mod feed_icon;
mod html_dom;
mod media_metadata;
pub mod miniflux;
pub mod mutations;
pub mod queries;
pub mod saved_media_sync;
pub mod storage;
pub mod sync;
mod sync_cancellation;

use sync_cancellation::Cancellable;
pub use sync_cancellation::{SyncCancellation, SyncOutcome};

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use chrono::{DateTime, Utc};

use diagnostics::{CoreDiagnosticListener, Diagnostics};
use domain::{
    ArticleAudioActionProjection, ArticleQuery, ArticleSummary, ArticleThumbnailResult,
    ContinueListeningItem, CoreError, CoreErrorKind, CoreEvent, CoreSettings, CreateCategoryResult,
    CreateFeedRequest, CreateFeedResult, DeliveryDisposition, DeliveryMode, DetailRenderingMode,
    DiscoverSubscriptionsRequest, DiscoveredSubscription, DownloadFailureKind,
    DownloadNetworkPolicy, DownloadOrigin, DownloadRetention, DownloadState,
    DownloadedMediaSummary, Enclosure, FeedIcon, FeedIconVariant, FeedPreferences,
    FeedPreferencesPatch, FeedSystemNotificationSetting, LegacyDownloadImportOutcome,
    LegacyFeedOpenInMinifluxImportOutcome, LegacyPlaybackImport, LegacyPlaybackImportResult,
    ListeningListFeed, ListeningListItem, ListeningListSort, MediaChapter, MediaDownload,
    MediaMetadata, MediaTransferWork, MutationField, MutationResult, NavigationCatalog,
    NavigationCountMode, NavigationProjection, PlaybackPreparation, PlaybackState,
    ReadArticleRetention, ReaderDocument, RuntimeHealth, RuntimeHealthStatus, SaveToServiceResult,
    SavedMediaSyncConfiguration, SavedMediaSyncSetupInfo, SavedPlayableMediaItem,
    SearchArticlesRequest, SearchArticlesResult, SearchMutationDisposition, SyncCompleted,
    SyncFailure, SyncReason, WidgetData,
};
use media_metadata::{
    REMOTE_MEDIA_INITIAL_PROBE_BYTES, REMOTE_MEDIA_MAX_ID3_BYTES, REMOTE_MEDIA_MP4_PREFIX_BYTES,
    REMOTE_MEDIA_MP4_TAIL_BYTES, id3_probe_total_bytes, probe_id3_artwork, probe_mp4_artwork,
};
use miniflux::{
    AccountValidationAttempt, AccountValidationError, AccountValidationResult, HttpHeader,
    MinifluxClient, RemoteSource, miniflux_entry_url, normalize_installation_base,
    validate_custom_headers,
};
use storage::Store;

/// Platform-provided roots and runtime-only Miniflux credentials.
#[derive(Clone)]
pub struct CoreConfig {
    pub persistent_data: PathBuf,
    pub cache: PathBuf,
    pub media: PathBuf,
    pub base_url: String,
    pub api_key: String,
    pub custom_headers: Vec<HttpHeader>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ConfigurationSnapshot {
    pub installation_base: String,
    pub core_settings: CoreSettings,
    pub feed_preferences: Vec<FeedPreferences>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MediaProgressCapability {
    Unknown,
    Supported,
    Unsupported,
}

/// Long-lived, thread-safe shared core. No API key is written to disk.
pub struct FluxCore {
    store: Arc<Store>,
    remote: Arc<dyn RemoteSource>,
    installation_base: String,
    feed_icons: feed_icon::FeedIconService,
    article_thumbnails: article_thumbnail::ArticleThumbnailService,
    sync_gate: Mutex<()>,
    delivery_mode: Mutex<DeliveryMode>,
    media_progress_supported: Mutex<MediaProgressCapability>,
    runtime: Mutex<DeliveryRuntime>,
    listeners: Mutex<HashMap<u64, Arc<dyn CoreEventListener>>>,
    next_listener_id: std::sync::atomic::AtomicU64,
    diagnostics: Arc<Diagnostics>,
    diagnostic_dispatcher: tracing::Dispatch,
}

#[derive(Clone, Copy)]
struct DeliveryRuntime {
    health: RuntimeHealth,
    next_retry_at: Option<Instant>,
    next_retry_at_utc: Option<DateTime<Utc>>,
}
pub trait CoreEventListener: Send + Sync {
    fn on_event(&self, event: CoreEvent);
}

impl FluxCore {
    /// Validates candidate credentials without opening or mutating a local core store.
    pub fn validate_miniflux_account(
        server_url: &str,
        api_key: &str,
        custom_headers: Vec<HttpHeader>,
    ) -> Result<AccountValidationResult, AccountValidationError> {
        MinifluxClient::validate_account(server_url, api_key, custom_headers)
    }

    pub fn validate_miniflux_account_with_diagnostic(
        server_url: &str,
        api_key: &str,
        custom_headers: Vec<HttpHeader>,
    ) -> AccountValidationAttempt {
        MinifluxClient::validate_account_with_diagnostic(server_url, api_key, custom_headers)
    }

    pub fn initialize(config: CoreConfig) -> Result<Self, CoreError> {
        Self::initialize_with_diagnostics(config, None)
    }

    pub fn initialize_with_diagnostics(
        config: CoreConfig,
        listener: Option<Arc<dyn CoreDiagnosticListener>>,
    ) -> Result<Self, CoreError> {
        let diagnostics = Diagnostics::new();
        if let Some(listener) = listener {
            diagnostics.subscribe(listener);
        }
        let diagnostic_dispatcher = diagnostics.dispatcher();
        let result = tracing::dispatcher::with_default(&diagnostic_dispatcher, || {
            tracing::info!(target: "core", "core initialization started");
            validate_config(&config)?;
            let remote = MinifluxClient::new_with_headers(
                &config.base_url,
                &config.api_key,
                config.custom_headers.clone(),
            )?;
            let installation_base = remote.installation_base().to_string();
            let store = Arc::new(Store::open(
                &config.persistent_data,
                &config.cache,
                &config.media,
            )?);
            store.set_base_url(&installation_base)?;
            let remote: Arc<dyn RemoteSource> = Arc::new(remote);
            let feed_icons = feed_icon::FeedIconService::new(config.cache.clone())?;
            let article_thumbnails =
                article_thumbnail::ArticleThumbnailService::new(config.cache.clone())?;
            let settings = store.core_settings()?;
            Ok::<_, CoreError>((
                store,
                remote,
                installation_base,
                feed_icons,
                article_thumbnails,
                settings,
            ))
        });
        let (store, remote, installation_base, feed_icons, article_thumbnails, settings) =
            match result {
                Ok(result) => result,
                Err(error) => {
                    tracing::dispatcher::with_default(
                        &diagnostic_dispatcher,
                        || tracing::error!(target: "core", "core initialization failed kind={:?}", error.kind),
                    );
                    diagnostics.flush();
                    return Err(error);
                }
            };
        tracing::dispatcher::with_default(
            &diagnostic_dispatcher,
            || tracing::info!(target: "core", "core initialization completed"),
        );
        diagnostics.flush();
        Ok(Self {
            store,
            remote,
            installation_base,
            feed_icons,
            article_thumbnails,
            sync_gate: Mutex::new(()),
            delivery_mode: Mutex::new(settings.delivery_mode),
            media_progress_supported: Mutex::new(MediaProgressCapability::Unknown),
            runtime: Mutex::new(DeliveryRuntime {
                health: RuntimeHealth::Healthy,
                next_retry_at: None,
                next_retry_at_utc: None,
            }),
            listeners: Mutex::new(HashMap::new()),
            next_listener_id: std::sync::atomic::AtomicU64::new(1),
            diagnostics,
            diagnostic_dispatcher,
        })
    }

    /// Constructor for controlled sources in integration tests and embedders.
    pub fn with_remote(
        config: CoreConfig,
        remote: Arc<dyn RemoteSource>,
    ) -> Result<Self, CoreError> {
        let diagnostics = Diagnostics::new();
        let diagnostic_dispatcher = diagnostics.dispatcher();
        let store = tracing::dispatcher::with_default(&diagnostic_dispatcher, || {
            tracing::info!(target: "core", "core initialization started");
            validate_config(&config)?;
            let installation_base =
                normalize_installation_base(&config.base_url).map_err(|error| match error {
                    AccountValidationError::InvalidUrl => {
                        CoreError::invalid_configuration("base URL is invalid")
                    }
                    AccountValidationError::UnsupportedUrlScheme => {
                        CoreError::invalid_configuration("base URL must use HTTP(S)")
                    }
                    _ => unreachable!("URL normalization only returns URL errors"),
                })?;
            let store = Arc::new(Store::open(
                &config.persistent_data,
                &config.cache,
                &config.media,
            )?);
            store.set_base_url(&installation_base)?;
            let feed_icons = feed_icon::FeedIconService::new(config.cache.clone())?;
            let article_thumbnails =
                article_thumbnail::ArticleThumbnailService::new(config.cache.clone())?;
            let settings = store.core_settings()?;
            Ok::<_, CoreError>((
                store,
                installation_base,
                feed_icons,
                article_thumbnails,
                settings,
            ))
        })?;
        let (store, installation_base, feed_icons, article_thumbnails, settings) = store;
        tracing::dispatcher::with_default(
            &diagnostic_dispatcher,
            || tracing::info!(target: "core", "core initialization completed"),
        );
        Ok(Self {
            store,
            remote,
            installation_base,
            feed_icons,
            article_thumbnails,
            sync_gate: Mutex::new(()),
            delivery_mode: Mutex::new(settings.delivery_mode),
            media_progress_supported: Mutex::new(MediaProgressCapability::Unknown),
            runtime: Mutex::new(DeliveryRuntime {
                health: RuntimeHealth::Healthy,
                next_retry_at: None,
                next_retry_at_utc: None,
            }),
            listeners: Mutex::new(HashMap::new()),
            next_listener_id: std::sync::atomic::AtomicU64::new(1),
            diagnostics,
            diagnostic_dispatcher,
        })
    }

    pub fn sync(&self, reason: SyncReason) -> Result<SyncCompleted, CoreError> {
        let result = tracing::dispatcher::with_default(&self.diagnostic_dispatcher, || {
            self.sync_inner(reason)
        });
        self.diagnostics.flush();
        result
    }

    /// Runs Sync with a caller-owned, monotonic cancellation signal.
    ///
    /// Cancellation is a normal Sync outcome rather than a Core error. The signal is observed
    /// before Core work begins, after waiting for the Sync gate, and at safe phase or bounded-work
    /// boundaries throughout mutation delivery, remote fetch, reconciliation and cleanup.
    pub fn sync_cancellable(
        &self,
        reason: SyncReason,
        cancellation: &SyncCancellation,
    ) -> Result<SyncOutcome, CoreError> {
        let result = tracing::dispatcher::with_default(&self.diagnostic_dispatcher, || {
            self.sync_cancellable_inner(reason, cancellation)
        });
        self.diagnostics.flush();
        result
    }

    pub fn miniflux_entry_url(&self, article_id: i64) -> String {
        miniflux_entry_url(&self.installation_base, article_id)
    }

    fn sync_inner(&self, reason: SyncReason) -> Result<SyncCompleted, CoreError> {
        let _sync = self
            .sync_gate
            .lock()
            .map_err(|_| CoreError::internal("sync gate poisoned"))?;
        self.sync_locked(reason)
    }

    fn sync_cancellable_inner(
        &self,
        reason: SyncReason,
        cancellation: &SyncCancellation,
    ) -> Result<SyncOutcome, CoreError> {
        if cancellation.is_cancelled() {
            tracing::info!(target: "sync", "sync cancellation observed before start reason={reason:?}");
            return Ok(SyncOutcome::Cancelled);
        }
        let _sync = self
            .sync_gate
            .lock()
            .map_err(|_| CoreError::internal("sync gate poisoned"))?;
        if cancellation.is_cancelled() {
            tracing::info!(target: "sync", "sync cancellation observed after waiting for sync gate reason={reason:?}");
            return Ok(SyncOutcome::Cancelled);
        }
        self.sync_locked_cancellable(reason, cancellation)
    }

    fn sync_locked(&self, reason: SyncReason) -> Result<SyncCompleted, CoreError> {
        let cancellation = SyncCancellation::new();
        match self.sync_locked_cancellable(reason, &cancellation)? {
            SyncOutcome::Completed(completed) => Ok(completed),
            SyncOutcome::Cancelled => unreachable!("fresh cancellation signal cannot be cancelled"),
        }
    }

    fn sync_locked_cancellable(
        &self,
        reason: SyncReason,
        cancellation: &SyncCancellation,
    ) -> Result<SyncOutcome, CoreError> {
        let started = Instant::now();
        tracing::info!(target: "sync", "sync started reason={reason:?}");
        if cancellation.is_cancelled() {
            return Ok(SyncOutcome::Cancelled);
        }

        if reason == SyncReason::Resume {
            const RESUME_STALE_AFTER_MINUTES: i64 = 30;
            const FULL_SYNC_MAX_AGE_HOURS: i64 = 24;
            let settings = self.store.core_settings()?;
            let stale = self.store.successful_sync_due(RESUME_STALE_AFTER_MINUTES)?;
            let full_required = self.store.full_sync_required()?;
            let full_due = self.store.full_sync_due(FULL_SYNC_MAX_AGE_HOURS)?;
            if !settings.background_sync_enabled || (!stale && !full_required && !full_due) {
                tracing::info!(
                    target: "sync",
                    "resume sync skipped enabled={} stale={} full_required={} full_due={}",
                    settings.background_sync_enabled,
                    stale,
                    full_required,
                    full_due
                );
                let completed = SyncCompleted {
                    reason,
                    new_articles: 0,
                    updated_articles: 0,
                    mutations_delivered: 0,
                    data_changed: false,
                    navigation_changed: false,
                    new_articles_by_feed: Vec::new(),
                    system_notification_candidates: Vec::new(),
                };
                self.emit(CoreEvent::SyncCompleted(completed.clone()));
                return Ok(SyncOutcome::Completed(completed));
            }
        }

        if reason != SyncReason::Manual && self.in_backoff()? {
            tracing::info!(target: "sync", "sync skipped reason={reason:?} because runtime backoff is active");
            let completed = SyncCompleted {
                reason,
                new_articles: 0,
                updated_articles: 0,
                mutations_delivered: 0,
                data_changed: false,
                navigation_changed: false,
                new_articles_by_feed: Vec::new(),
                system_notification_candidates: Vec::new(),
            };
            self.emit(CoreEvent::SyncCompleted(completed.clone()));
            return Ok(SyncOutcome::Completed(completed));
        }

        // Capability discovery is advisory: an unreachable version endpoint must not block local sync.
        // Best-effort refresh also detects an upgrade from an unsupported server.
        let _ = self.update_miniflux_capabilities();
        if cancellation.is_cancelled() {
            return Ok(SyncOutcome::Cancelled);
        }

        let delivery = match self.deliver_for_sync_cancellable(reason, cancellation) {
            Ok(Cancellable::Completed(result)) => {
                tracing::info!(target: "mutation", "pending mutation delivery completed delivered={}", result.count);
                result
            }
            Ok(Cancellable::Cancelled) => return Ok(SyncOutcome::Cancelled),
            Err(_) if cancellation.is_cancelled() => return Ok(SyncOutcome::Cancelled),
            Err(error) => {
                tracing::warn!(target: "sync", "sync stopped during pending delivery kind={:?}", error.kind);
                self.emit(CoreEvent::SyncFailed(SyncFailure {
                    reason,
                    error_kind: error.kind.clone(),
                    mutation_delivery_completed: false,
                    remote_fetch_started: false,
                    remote_fetch_completed: false,
                    mutations_delivered: 0,
                }));
                return Err(error);
            }
        };

        if cancellation.is_cancelled() {
            return Ok(SyncOutcome::Cancelled);
        }
        let retention = self.store.core_settings()?.retention;
        let media_progress_writes = delivery.media_progress.clone();
        match sync::run_cancellable(
            self.remote.as_ref(),
            self.store.as_ref(),
            retention,
            reason,
            media_progress_writes,
            cancellation,
        ) {
            Ok(Cancellable::Completed(data)) => {
                tracing::info!(target: "sync", "sync completed new={} updated={} delivered={} elapsed_ms={}", data.new_articles, data.updated_articles, delivery.count, started.elapsed().as_millis());
                let completed = SyncCompleted {
                    reason,
                    new_articles: data.new_articles,
                    updated_articles: data.updated_articles,
                    mutations_delivered: delivery.count,
                    data_changed: data.data_changed,
                    navigation_changed: data.navigation_changed,
                    new_articles_by_feed: data.new_articles_by_feed,
                    system_notification_candidates: data.system_notification_candidates,
                };
                self.emit(CoreEvent::SyncCompleted(completed.clone()));
                Ok(SyncOutcome::Completed(completed))
            }
            Ok(Cancellable::Cancelled) => {
                tracing::info!(target: "sync", "sync cancelled reason={reason:?} elapsed_ms={}", started.elapsed().as_millis());
                Ok(SyncOutcome::Cancelled)
            }
            Err(_) if cancellation.is_cancelled() => {
                tracing::info!(target: "sync", "sync cancellation won error race reason={reason:?} elapsed_ms={}", started.elapsed().as_millis());
                Ok(SyncOutcome::Cancelled)
            }
            Err(error) => {
                tracing::warn!(target: "sync", "sync failed kind={:?} message={:?} elapsed_ms={}", error.kind, error.message, started.elapsed().as_millis());
                self.emit(CoreEvent::SyncFailed(SyncFailure {
                    reason,
                    error_kind: error.kind.clone(),
                    mutation_delivery_completed: true,
                    remote_fetch_started: true,
                    remote_fetch_completed: false,
                    mutations_delivered: delivery.count,
                }));
                Err(error)
            }
        }
    }

    /// Discards synchronized local state and immediately rebuilds it from Miniflux.
    pub fn rebuild_local_state(&self) -> Result<SyncCompleted, CoreError> {
        let result = tracing::dispatcher::with_default(&self.diagnostic_dispatcher, || {
            let _sync = self
                .sync_gate
                .lock()
                .map_err(|_| CoreError::internal("sync gate poisoned"))?;
            self.store.clear_synchronized_state_for_rebuild()?;
            self.clear_regenerable_caches();
            self.clear_backoff()?;
            self.sync_locked(SyncReason::Manual)
        });
        self.diagnostics.flush();
        result
    }

    /// Resets Core-owned persistent state without contacting Miniflux.
    pub fn reset_core_state(&self) -> Result<(), CoreError> {
        let result = tracing::dispatcher::with_default(&self.diagnostic_dispatcher, || {
            let _sync = self
                .sync_gate
                .lock()
                .map_err(|_| CoreError::internal("sync gate poisoned"))?;
            self.store.reset_core_state()?;
            self.clear_regenerable_caches();
            self.clear_backoff()?;
            *self
                .delivery_mode
                .lock()
                .map_err(|_| CoreError::internal("delivery mode lock poisoned"))? =
                CoreSettings::default().delivery_mode;
            Ok(())
        });
        self.diagnostics.flush();
        result
    }

    /// Removes account-bound state while preserving global Core settings.
    pub fn remove_account_state(&self) -> Result<(), CoreError> {
        let result = tracing::dispatcher::with_default(&self.diagnostic_dispatcher, || {
            let _sync = self
                .sync_gate
                .lock()
                .map_err(|_| CoreError::internal("sync gate poisoned"))?;
            self.store.remove_account_state()?;
            self.clear_regenerable_caches();
            self.clear_backoff()?;
            Ok(())
        });
        self.diagnostics.flush();
        result
    }

    pub fn configuration_snapshot(&self) -> Result<ConfigurationSnapshot, CoreError> {
        Ok(ConfigurationSnapshot {
            installation_base: self.store.base_url()?.unwrap_or_default(),
            core_settings: self.store.core_settings()?,
            feed_preferences: self.store.all_feed_preferences()?,
        })
    }

    /// Applies a previously parsed configuration backup without contacting Miniflux.
    pub fn replace_configuration(
        &self,
        installation_base: String,
        core_settings: CoreSettings,
        feed_preferences: Vec<FeedPreferences>,
    ) -> Result<(), CoreError> {
        let canonical_base = normalize_installation_base(&installation_base)
            .map_err(|_| CoreError::invalid_configuration("backup installation base is invalid"))?;
        let result = tracing::dispatcher::with_default(&self.diagnostic_dispatcher, || {
            let _sync = self
                .sync_gate
                .lock()
                .map_err(|_| CoreError::internal("sync gate poisoned"))?;
            self.store
                .replace_configuration(&canonical_base, &core_settings, &feed_preferences)?;
            self.clear_regenerable_caches();
            self.clear_backoff()?;
            *self
                .delivery_mode
                .lock()
                .map_err(|_| CoreError::internal("delivery mode lock poisoned"))? =
                core_settings.delivery_mode;
            Ok(())
        });
        self.diagnostics.flush();
        result
    }

    pub fn query_articles(&self, query: ArticleQuery) -> Result<Vec<ArticleSummary>, CoreError> {
        self.store.query_articles(&query)
    }
    pub fn article_summary(&self, article_id: i64) -> Result<Option<ArticleSummary>, CoreError> {
        self.store.article_summary(article_id)
    }
    pub fn article_page(
        &self,
        query: ArticleQuery,
        include_total: bool,
    ) -> Result<domain::ArticlePage, CoreError> {
        self.store.article_page(&query, include_total)
    }
    pub fn article_audio_action_states(
        &self,
        article_ids: &[i64],
    ) -> Result<Vec<ArticleAudioActionProjection>, CoreError> {
        self.store.article_audio_action_states(article_ids)
    }
    pub fn reader_document(&self, article_id: i64) -> Result<ReaderDocument, CoreError> {
        let article = self.store.reader_article(article_id)?;
        self.reader_document_for_article(
            article.feed_id,
            &article.raw_html_content,
            &article.url,
            article.image_url.as_deref(),
        )
    }
    pub fn reader_document_for_search(&self, article_id: i64) -> Result<ReaderDocument, CoreError> {
        if article_id <= 0 {
            return Err(CoreError::data("article ID must be positive"));
        }
        let article = self.remote.fetch_article_by_id(article_id)?.article;
        self.reader_document_for_article(
            article.feed_id,
            &article.raw_html_content,
            &article.url,
            article.image_url.as_deref(),
        )
    }
    fn reader_document_for_article(
        &self,
        feed_id: i64,
        raw_html_content: &str,
        url: &str,
        image_url: Option<&str>,
    ) -> Result<ReaderDocument, CoreError> {
        let preferences = match self.store.feed_preferences(feed_id) {
            Ok(preferences) => preferences,
            Err(error)
                if error.kind == CoreErrorKind::Data
                    && error.message == format!("feed {feed_id} does not exist") =>
            {
                FeedPreferences::defaults(feed_id)
            }
            Err(error) => return Err(error),
        };
        let limit = preferences
            .truncate_detail
            .then(|| {
                self.store
                    .core_settings()
                    .map(|settings| settings.detail_character_limit)
            })
            .transpose()?;
        Ok(article_document::project_with_fallback_image(
            article_document::parse(raw_html_content, url),
            preferences.detail_rendering,
            limit,
            image_url,
        ))
    }
    pub fn count_articles(&self, query: ArticleQuery) -> Result<u64, CoreError> {
        self.store.count_articles(&query)
    }
    pub fn article_enclosures(&self, article_id: i64) -> Result<Vec<Enclosure>, CoreError> {
        Ok(self
            .store
            .enclosures_for_article(article_id)?
            .into_iter()
            .map(|stored| stored.enclosure)
            .collect())
    }
    pub fn listening_list(
        &self,
        feed_id: Option<i64>,
        sort: ListeningListSort,
    ) -> Result<Vec<ListeningListItem>, CoreError> {
        self.store.listening_list(feed_id, sort)
    }
    pub fn listening_list_feeds(&self) -> Result<Vec<ListeningListFeed>, CoreError> {
        self.store.listening_list_feeds()
    }
    pub fn is_in_listening_list(&self, article_id: i64) -> Result<bool, CoreError> {
        self.store.is_in_listening_list(article_id)
    }
    pub fn add_to_listening_list(&self, article_id: i64) -> Result<(), CoreError> {
        if article_id <= 0 {
            return Err(CoreError::data("article ID must be positive"));
        }
        let settings = self.store.core_settings()?;
        let _sync = self
            .sync_gate
            .lock()
            .map_err(|_| CoreError::internal("sync gate poisoned"))?;
        self.store
            .add_to_listening_list_with_policy(
                article_id,
                &Utc::now().to_rfc3339(),
                settings.auto_download_listening_list,
            )
            .map(|_| ())
    }
    pub fn remove_from_listening_list(&self, article_id: i64) -> Result<(), CoreError> {
        if article_id <= 0 {
            return Err(CoreError::data("article ID must be positive"));
        }
        let _sync = self
            .sync_gate
            .lock()
            .map_err(|_| CoreError::internal("sync gate poisoned"))?;
        self.store
            .remove_from_listening_list(article_id)
            .map(|_| ())
    }
    pub fn save_media(&self, enclosure_id: i64) -> Result<(), CoreError> {
        if enclosure_id <= 0 {
            return Err(CoreError::data("enclosure ID must be positive"));
        }
        let result = tracing::dispatcher::with_default(&self.diagnostic_dispatcher, || {
            let _sync = self
                .sync_gate
                .lock()
                .map_err(|_| CoreError::internal("sync gate poisoned"))?;
            self.store
                .save_media(enclosure_id, &Utc::now().to_rfc3339())
        });
        self.diagnostics.flush();
        result.map(|_| ())
    }
    pub fn unsave_media(&self, enclosure_id: i64) -> Result<(), CoreError> {
        if enclosure_id <= 0 {
            return Err(CoreError::data("enclosure ID must be positive"));
        }
        let result = tracing::dispatcher::with_default(&self.diagnostic_dispatcher, || {
            let _sync = self
                .sync_gate
                .lock()
                .map_err(|_| CoreError::internal("sync gate poisoned"))?;
            self.store.unsave_media(enclosure_id)
        });
        self.diagnostics.flush();
        result.map(|_| ())
    }
    pub fn is_media_saved(&self, enclosure_id: i64) -> Result<bool, CoreError> {
        Ok(self.store.saved_media(enclosure_id)?.is_some())
    }
    pub fn saved_media_sync_configuration(&self) -> Result<SavedMediaSyncConfiguration, CoreError> {
        self.store.saved_media_sync_configuration()
    }
    pub fn saved_media_sync_setup_info(&self) -> SavedMediaSyncSetupInfo {
        saved_media_sync::setup_info()
    }
    pub fn setup_saved_media_sync_automatic(&self) -> Result<(), CoreError> {
        let _sync = self
            .sync_gate
            .lock()
            .map_err(|_| CoreError::internal("sync gate poisoned"))?;
        saved_media_sync::setup_automatic(self.remote.as_ref(), self.store.as_ref())
    }
    pub fn setup_saved_media_sync_manual(&self) -> Result<(), CoreError> {
        let _sync = self
            .sync_gate
            .lock()
            .map_err(|_| CoreError::internal("sync gate poisoned"))?;
        saved_media_sync::setup_manual(self.remote.as_ref(), self.store.as_ref())
    }
    pub fn disable_saved_media_sync(&self) -> Result<(), CoreError> {
        self.store.disable_saved_media_sync()
    }
    pub fn saved_playable_media(&self) -> Result<Vec<SavedPlayableMediaItem>, CoreError> {
        self.store.saved_playable_media()
    }
    pub fn saved_media_by_feed(
        &self,
        feed_id: i64,
    ) -> Result<Vec<SavedPlayableMediaItem>, CoreError> {
        self.store.saved_media_by_feed(feed_id)
    }
    pub fn continue_listening(&self) -> Result<Vec<ContinueListeningItem>, CoreError> {
        self.store.continue_listening()
    }
    pub fn import_legacy_playback(
        &self,
        records: &[LegacyPlaybackImport],
    ) -> Result<LegacyPlaybackImportResult, CoreError> {
        self.store.import_legacy_playback(records)
    }
    /// Refreshes Core-owned, non-persistent Miniflux capability state after validation/connectivity.
    pub fn update_miniflux_capabilities(&self) -> Result<(), CoreError> {
        let supported = self
            .remote
            .miniflux_capabilities()?
            .contains(&miniflux::MinifluxCapability::MediaProgressSync);
        *self
            .media_progress_supported
            .lock()
            .map_err(|_| CoreError::internal("media progression capability lock poisoned"))? =
            if supported {
                MediaProgressCapability::Supported
            } else {
                MediaProgressCapability::Unsupported
            };
        if supported {
            self.store.promote_playback_progress()?;
        }
        Ok(())
    }
    pub fn enclosure(&self, enclosure_id: i64) -> Result<Option<Enclosure>, CoreError> {
        Ok(self
            .store
            .enclosure(enclosure_id)?
            .map(|stored| stored.enclosure))
    }
    pub fn prepare_playback(&self, enclosure_id: i64) -> Result<PlaybackPreparation, CoreError> {
        let enclosure = self
            .store
            .enclosure(enclosure_id)?
            .ok_or_else(|| CoreError::data(format!("enclosure {enclosure_id} does not exist")))?;
        self.store.prepare_article_chapters(enclosure_id)?;
        let (article_title, feed_title) = self
            .store
            .article_presentation(enclosure.enclosure.article_id)?;
        let playback_state = self.store.playback_state(enclosure_id)?;
        let download = self.store.media_download(enclosure_id)?;
        let metadata = self.store.media_metadata(enclosure_id)?;
        let duration_ms = metadata
            .as_ref()
            .and_then(|metadata| metadata.duration_ms)
            .or_else(|| playback_state.as_ref().and_then(|state| state.duration_ms));
        Ok(PlaybackPreparation {
            enclosure: enclosure.enclosure,
            article_title,
            feed_title,
            playback_state,
            local_file: download.and_then(|download| download.local_file),
            duration_ms,
            artwork_source: self.store.media_artwork_source(enclosure_id)?,
        })
    }
    pub fn playback_state(&self, enclosure_id: i64) -> Result<Option<PlaybackState>, CoreError> {
        self.store.playback_state(enclosure_id)
    }
    pub fn checkpoint_playback(
        &self,
        enclosure_id: i64,
        position_ms: u64,
        duration_ms: Option<u64>,
    ) -> Result<(), CoreError> {
        let _sync = self
            .sync_gate
            .lock()
            .map_err(|_| CoreError::internal("sync gate poisoned"))?;
        let supported = *self
            .media_progress_supported
            .lock()
            .map_err(|_| CoreError::internal("media progression capability lock poisoned"))?
            == MediaProgressCapability::Supported;
        self.store.checkpoint_playback(
            enclosure_id,
            position_ms,
            duration_ms,
            &Utc::now().to_rfc3339(),
            supported,
        )
    }
    pub fn playback_completed(
        &self,
        enclosure_id: i64,
        duration_ms: Option<u64>,
    ) -> Result<(), CoreError> {
        let _sync = self
            .sync_gate
            .lock()
            .map_err(|_| CoreError::internal("sync gate poisoned"))?;
        let supported = *self
            .media_progress_supported
            .lock()
            .map_err(|_| CoreError::internal("media progression capability lock poisoned"))?
            == MediaProgressCapability::Supported;
        self.store.complete_playback(
            enclosure_id,
            duration_ms,
            &Utc::now().to_rfc3339(),
            supported,
        )
    }
    pub fn restart_playback(&self, enclosure_id: i64) -> Result<(), CoreError> {
        let _sync = self
            .sync_gate
            .lock()
            .map_err(|_| CoreError::internal("sync gate poisoned"))?;
        let supported = *self
            .media_progress_supported
            .lock()
            .map_err(|_| CoreError::internal("media progression capability lock poisoned"))?
            == MediaProgressCapability::Supported;
        self.store
            .restart_playback(enclosure_id, &Utc::now().to_rfc3339(), supported)
    }
    pub fn observe_media_duration(
        &self,
        enclosure_id: i64,
        duration_ms: u64,
    ) -> Result<(), CoreError> {
        self.store
            .observe_media_duration(enclosure_id, duration_ms, &Utc::now().to_rfc3339())
    }
    pub fn media_download(&self, enclosure_id: i64) -> Result<Option<MediaDownload>, CoreError> {
        self.store.media_download(enclosure_id)
    }
    pub fn downloaded_media_summary(&self) -> Result<DownloadedMediaSummary, CoreError> {
        self.store.downloaded_media_summary()
    }
    pub fn media_metadata(&self, enclosure_id: i64) -> Result<Option<MediaMetadata>, CoreError> {
        self.store.media_metadata(enclosure_id)
    }
    pub fn media_artwork_source(
        &self,
        enclosure_id: i64,
    ) -> Result<Option<domain::MediaArtworkSource>, CoreError> {
        self.store.media_artwork_source(enclosure_id)
    }
    pub fn probe_media_artwork(&self, enclosure_id: i64) -> Result<bool, CoreError> {
        let enclosure = self
            .store
            .enclosure(enclosure_id)?
            .ok_or_else(|| CoreError::data(format!("enclosure {enclosure_id} does not exist")))?;

        if self
            .store
            .media_metadata(enclosure_id)?
            .and_then(|metadata| metadata.embedded_artwork_reference)
            .is_some()
        {
            return Ok(false);
        }

        if self
            .store
            .media_download(enclosure_id)?
            .is_some_and(|download| {
                matches!(
                    download.state,
                    DownloadState::Requested
                        | DownloadState::Downloaded
                        | DownloadState::DeleteRequested
                )
            })
        {
            return Ok(false);
        }

        let url = enclosure.enclosure.url.trim();
        let mime = enclosure
            .enclosure
            .mime_type
            .split(';')
            .next()
            .unwrap_or_default()
            .trim()
            .to_ascii_lowercase();
        let lower_url = url.to_ascii_lowercase();
        let mp4_like = matches!(mime.as_str(), "audio/mp4" | "audio/x-m4a" | "video/mp4")
            || lower_url.ends_with(".m4a")
            || lower_url.ends_with(".mp4")
            || lower_url.ends_with(".m4v");

        let artwork = if mp4_like {
            let prefix_end = REMOTE_MEDIA_MP4_PREFIX_BYTES.saturating_sub(1);
            self.remote
                .fetch_media_range(
                    url,
                    &format!("bytes=0-{prefix_end}"),
                    REMOTE_MEDIA_MP4_PREFIX_BYTES,
                )
                .ok()
                .and_then(|prefix| probe_mp4_artwork(&prefix))
                .or_else(|| {
                    self.remote
                        .fetch_media_range(
                            url,
                            &format!("bytes=-{}", REMOTE_MEDIA_MP4_TAIL_BYTES),
                            REMOTE_MEDIA_MP4_TAIL_BYTES,
                        )
                        .ok()
                        .and_then(|tail| probe_mp4_artwork(&tail))
                })
        } else {
            let initial_end = REMOTE_MEDIA_INITIAL_PROBE_BYTES.saturating_sub(1);
            let Some(mut bytes) = self
                .remote
                .fetch_media_range(
                    url,
                    &format!("bytes=0-{initial_end}"),
                    REMOTE_MEDIA_INITIAL_PROBE_BYTES,
                )
                .ok()
            else {
                return Ok(false);
            };
            if let Some(total) = id3_probe_total_bytes(&bytes)
                && total > bytes.len()
                && total <= REMOTE_MEDIA_MAX_ID3_BYTES
            {
                let start = bytes.len();
                let end = total.saturating_sub(1);
                if let Ok(remainder) = self.remote.fetch_media_range(
                    url,
                    &format!("bytes={start}-{end}"),
                    total.saturating_sub(start),
                ) {
                    bytes.extend_from_slice(&remainder);
                }
            }
            probe_id3_artwork(&bytes)
        };

        let Some(artwork) = artwork else {
            return Ok(false);
        };
        self.store
            .persist_probed_media_artwork(enclosure_id, artwork)
    }

    pub fn media_artwork(&self, reference: &str) -> Result<Option<Vec<u8>>, CoreError> {
        self.store.media_artwork(reference)
    }
    pub fn media_chapters(&self, enclosure_id: i64) -> Result<Vec<MediaChapter>, CoreError> {
        self.store.media_chapters(enclosure_id)
    }
    pub fn media_progress_capability(&self) -> MediaProgressCapability {
        self.media_progress_supported
            .lock()
            .map(|capability| *capability)
            .unwrap_or(MediaProgressCapability::Unknown)
    }
    pub fn downloads_requiring_transfer(&self) -> Result<Vec<MediaTransferWork>, CoreError> {
        self.store.media_transfer_work(DownloadState::Requested)
    }
    pub fn downloads_requiring_deletion(&self) -> Result<Vec<MediaTransferWork>, CoreError> {
        self.store
            .media_transfer_work(DownloadState::DeleteRequested)
    }
    pub fn request_download(
        &self,
        enclosure_id: i64,
        origin: DownloadOrigin,
    ) -> Result<(), CoreError> {
        let _sync = self
            .sync_gate
            .lock()
            .map_err(|_| CoreError::internal("sync gate poisoned"))?;
        self.store.request_download(enclosure_id, origin)
    }
    pub fn cancel_download(&self, enclosure_id: i64) -> Result<(), CoreError> {
        let _sync = self
            .sync_gate
            .lock()
            .map_err(|_| CoreError::internal("sync gate poisoned"))?;
        self.store.cancel_download(enclosure_id)
    }
    pub fn retry_download(&self, enclosure_id: i64) -> Result<(), CoreError> {
        let _sync = self
            .sync_gate
            .lock()
            .map_err(|_| CoreError::internal("sync gate poisoned"))?;
        self.store.retry_download(enclosure_id)
    }
    pub fn download_finished(
        &self,
        enclosure_id: i64,
        local_file: &str,
        file_size_bytes: u64,
    ) -> Result<(), CoreError> {
        let _sync = self
            .sync_gate
            .lock()
            .map_err(|_| CoreError::internal("sync gate poisoned"))?;
        self.store
            .download_finished(enclosure_id, local_file, file_size_bytes)
    }
    /// Rehydrate a historical playback article only when Miniflux identifies
    /// exactly one audio enclosure, preserving the Core's ambiguity policy.
    /// `Ok(false)` is reserved for confirmed remote absence (HTTP 404/410), so
    /// platform migration can distinguish stale progress from unresolved data.
    pub fn restore_legacy_playback_article(&self, article_id: i64) -> Result<bool, CoreError> {
        if article_id <= 0 {
            return Err(CoreError::data(
                "legacy playback article ID must be positive",
            ));
        }
        let result = tracing::dispatcher::with_default(&self.diagnostic_dispatcher, || {
            let _sync = self
                .sync_gate
                .lock()
                .map_err(|_| CoreError::internal("sync gate poisoned"))?;
            if self
                .store
                .enclosures_for_article(article_id)?
                .iter()
                .any(|e| {
                    e.enclosure
                        .mime_type
                        .to_ascii_lowercase()
                        .starts_with("audio/")
                })
            {
                return Ok(true);
            }
            let remote = match self.remote.fetch_article_by_id(article_id) {
                Ok(remote) => remote,
                Err(error) if matches!(error.http_status(), Some(404 | 410)) => return Ok(false),
                Err(error) => return Err(error),
            };
            if remote.article.id != article_id {
                return Err(CoreError::data("legacy playback article identity mismatch"));
            }
            let audios = remote
                .enclosures
                .iter()
                .filter(|e| {
                    e.article_id == article_id
                        && e.mime_type.to_ascii_lowercase().starts_with("audio/")
                })
                .collect::<Vec<_>>();
            if audios.len() != 1 {
                return Err(CoreError::data(
                    "legacy playback article does not have exactly one audio enclosure",
                ));
            }
            self.store.restore_legacy_media_article(
                &remote.article,
                &remote.enclosures,
                audios[0].id,
            )
        });
        self.diagnostics.flush();
        result
    }

    /// Rehydrate a historical playback article from a platform-verified local
    /// legacy snapshot without contacting Miniflux. The Store preserves native
    /// rows and requires the legacy feed to still belong to the current catalog.
    pub fn restore_legacy_local_playback_article(
        &self,
        article: &domain::Article,
        enclosure: &Enclosure,
    ) -> Result<bool, CoreError> {
        if article.id <= 0 || enclosure.id <= 0 || enclosure.article_id != article.id {
            return Err(CoreError::data("invalid legacy local playback snapshot"));
        }
        let _sync = self
            .sync_gate
            .lock()
            .map_err(|_| CoreError::internal("sync gate poisoned"))?;
        self.store
            .restore_legacy_local_playback_article(article, enclosure)
    }

    /// Hydrate a historical, read article for a verified legacy download.
    /// Never fetch arbitrary URLs and never overwrite native article state.
    /// Missing remote entries or mismatched enclosure IDs remain retryable.
    pub fn restore_legacy_media_article(
        &self,
        article_id: i64,
        enclosure_id: i64,
    ) -> Result<bool, CoreError> {
        if article_id <= 0 || enclosure_id <= 0 {
            return Err(CoreError::data("legacy media IDs must be positive"));
        }
        let result = tracing::dispatcher::with_default(&self.diagnostic_dispatcher, || {
            let _sync = self
                .sync_gate
                .lock()
                .map_err(|_| CoreError::internal("sync gate poisoned"))?;
            if let Some(existing) = self.store.enclosure(enclosure_id)? {
                return Ok(existing.enclosure.article_id == article_id);
            }
            let remote = match self.remote.fetch_article_by_id(article_id) {
                Ok(remote) => remote,
                Err(error) if matches!(error.http_status(), Some(404 | 410)) => {
                    tracing::info!(target: "migration", "legacy media article unavailable article_id={article_id}");
                    return Ok(false);
                }
                Err(error) => return Err(error),
            };
            if remote.article.id != article_id {
                tracing::warn!(target: "migration", "legacy media article identity mismatch article_id={article_id}");
                return Ok(false);
            }
            let restored = self.store.restore_legacy_media_article(
                &remote.article,
                &remote.enclosures,
                enclosure_id,
            )?;
            tracing::info!(target: "migration",
                "legacy media hydration article_id={} enclosure_id={} restored={}",
                article_id, enclosure_id, restored);
            Ok(restored)
        });
        self.diagnostics.flush();
        result
    }

    pub fn repair_legacy_download_metadata(&self) -> Result<(u32, u32), CoreError> {
        let _sync = self
            .sync_gate
            .lock()
            .map_err(|_| CoreError::internal("sync gate poisoned"))?;
        self.store.repair_legacy_download_metadata()
    }

    /// Registers a verified legacy file copied by a platform adapter. Unlike
    /// normal transfer completion, this never replaces existing Core state.
    pub fn import_legacy_download(
        &self,
        enclosure_id: i64,
        local_file: &str,
        file_size_bytes: u64,
    ) -> Result<LegacyDownloadImportOutcome, CoreError> {
        let _sync = self
            .sync_gate
            .lock()
            .map_err(|_| CoreError::internal("sync gate poisoned"))?;
        self.store
            .import_legacy_download(enclosure_id, local_file, file_size_bytes)
    }
    pub fn download_failed(
        &self,
        enclosure_id: i64,
        failure_kind: DownloadFailureKind,
    ) -> Result<(), CoreError> {
        let _sync = self
            .sync_gate
            .lock()
            .map_err(|_| CoreError::internal("sync gate poisoned"))?;
        self.store.download_failed(enclosure_id, failure_kind)
    }
    pub fn request_download_deletion(&self, enclosure_id: i64) -> Result<(), CoreError> {
        let _sync = self
            .sync_gate
            .lock()
            .map_err(|_| CoreError::internal("sync gate poisoned"))?;
        self.store.request_download_deletion(enclosure_id)
    }
    pub fn evaluate_media_cleanup(&self, now: DateTime<Utc>) -> Result<Vec<i64>, CoreError> {
        let _sync = self
            .sync_gate
            .lock()
            .map_err(|_| CoreError::internal("sync gate poisoned"))?;
        self.store.evaluate_media_cleanup(now)
    }
    pub fn evaluate_media_cleanup_now(&self) -> Result<Vec<i64>, CoreError> {
        self.evaluate_media_cleanup(Utc::now())
    }
    pub fn request_all_download_deletions(&self) -> Result<u64, CoreError> {
        let _sync = self
            .sync_gate
            .lock()
            .map_err(|_| CoreError::internal("sync gate poisoned"))?;
        self.store.request_all_download_deletions()
    }
    pub fn download_deleted(&self, enclosure_id: i64) -> Result<(), CoreError> {
        let _sync = self
            .sync_gate
            .lock()
            .map_err(|_| CoreError::internal("sync gate poisoned"))?;
        self.store.download_deleted(enclosure_id)
    }
    pub fn search_articles(
        &self,
        request: SearchArticlesRequest,
    ) -> Result<SearchArticlesResult, CoreError> {
        if request.query.trim().is_empty() {
            return Err(CoreError::data("search query must not be empty"));
        }
        if request.offset < 0 {
            return Err(CoreError::data("search offset must not be negative"));
        }
        if request.limit == 0 {
            return Err(CoreError::data("search limit must be positive"));
        }
        let result = tracing::dispatcher::with_default(&self.diagnostic_dispatcher, || {
            self.remote.search_articles(request)
        })
        .and_then(|mut result| {
            for article in &mut result.articles {
                if let Some(state) = self.store.local_article_state(article.id)? {
                    article.is_read = state.is_read;
                    article.is_starred = state.is_starred;
                }
            }
            Ok(result)
        });
        self.diagnostics.flush();
        result
    }
    pub fn search_set_starred_state(
        &self,
        article_id: i64,
        starred: bool,
    ) -> Result<SearchMutationDisposition, CoreError> {
        self.search_set_state(article_id, MutationField::Starred, starred, |remote| {
            remote.set_starred_state(article_id, starred)
        })
    }
    pub fn search_set_read_state(
        &self,
        article_id: i64,
        read: bool,
    ) -> Result<SearchMutationDisposition, CoreError> {
        self.search_set_state(article_id, MutationField::Read, read, |remote| {
            remote.set_read_state(&[article_id], read)
        })
    }
    pub fn navigation_catalog(&self) -> Result<NavigationCatalog, CoreError> {
        self.store.navigation_catalog()
    }
    pub fn navigation_projection(
        &self,
        count_mode: NavigationCountMode,
    ) -> Result<NavigationProjection, CoreError> {
        self.store.navigation_projection(count_mode)
    }
    pub fn feed_system_notification_settings(
        &self,
    ) -> Result<Vec<FeedSystemNotificationSetting>, CoreError> {
        self.store.feed_system_notification_settings()
    }
    pub fn set_feed_system_notifications_enabled(
        &self,
        feed_id: i64,
        enabled: bool,
    ) -> Result<(), CoreError> {
        self.store
            .set_feed_system_notifications_enabled(feed_id, enabled)
    }
    pub fn feed_preferences(&self, feed_id: i64) -> Result<FeedPreferences, CoreError> {
        self.store.feed_preferences(feed_id)
    }
    pub fn feed_preferences_bulk(
        &self,
        feed_ids: &[i64],
    ) -> Result<Vec<FeedPreferences>, CoreError> {
        self.store.feed_preferences_bulk(feed_ids)
    }
    pub fn patch_feed_preferences_bulk(
        &self,
        feed_ids: &[i64],
        patch: FeedPreferencesPatch,
    ) -> Result<(), CoreError> {
        self.store.patch_feed_preferences_bulk(feed_ids, patch)
    }
    pub fn set_feed_detail_rendering(
        &self,
        feed_id: i64,
        mode: DetailRenderingMode,
    ) -> Result<(), CoreError> {
        self.store.set_feed_detail_rendering(feed_id, mode)
    }
    pub fn set_feed_truncate_detail(&self, feed_id: i64, enabled: bool) -> Result<(), CoreError> {
        self.store.set_feed_truncate_detail(feed_id, enabled)
    }
    pub fn set_feed_open_in_miniflux(&self, feed_id: i64, enabled: bool) -> Result<(), CoreError> {
        self.store.set_feed_open_in_miniflux(feed_id, enabled)
    }
    pub fn import_legacy_feed_open_in_miniflux(
        &self,
        feed_id: i64,
    ) -> Result<LegacyFeedOpenInMinifluxImportOutcome, CoreError> {
        self.store.import_legacy_feed_open_in_miniflux(feed_id)
    }
    pub fn set_feed_auto_download_audio(
        &self,
        feed_id: i64,
        enabled: bool,
    ) -> Result<(), CoreError> {
        self.store.set_feed_auto_download_audio(feed_id, enabled)
    }
    pub fn acknowledge_system_notification(&self, candidate_id: i64) -> Result<(), CoreError> {
        self.store.acknowledge_system_notification(candidate_id)
    }
    pub fn feed_icon(
        &self,
        feed_id: i64,
        variant: FeedIconVariant,
    ) -> Result<Option<FeedIcon>, CoreError> {
        self.feed_icons.get(self.remote.as_ref(), feed_id, variant)
    }
    pub fn article_thumbnail(
        &self,
        article_id: i64,
        image_url: String,
    ) -> Result<ArticleThumbnailResult, CoreError> {
        self.article_thumbnails
            .get(self.remote.as_ref(), article_id, &image_url)
    }
    pub fn last_successful_sync_at(&self) -> Result<Option<String>, CoreError> {
        self.store.last_successful_sync_at()
    }
    /// Builds the bounded domain data that a native client projects into its
    /// platform-owned widget snapshot.
    pub fn widget_data(&self) -> Result<WidgetData, CoreError> {
        self.store.widget_data()
    }

    /// Pages the complete compact widget article projection without changing the
    /// intentionally bounded WidgetData contract used by WidgetKit snapshots.
    pub fn widget_articles_page(
        &self,
        limit: u32,
        cursor: Option<domain::ArticleCursor>,
    ) -> Result<domain::WidgetArticlePage, CoreError> {
        let page = self.store.article_page(
            &ArticleQuery {
                scope: domain::ArticleScope::All,
                read_filter: domain::ReadFilter::All,
                starred_filter: domain::StarredFilter::All,
                sort: domain::ArticleSort::NewestFirst,
                limit,
                cursor,
            },
            false,
        )?;
        Ok(domain::WidgetArticlePage {
            articles: page
                .articles
                .into_iter()
                .map(|article| domain::WidgetArticle {
                    id: article.id,
                    feed_id: article.feed_id,
                    category_id: article.category_id,
                    feed_title: article.feed_title,
                    title: article.title,
                    published_at: article.published_at,
                    is_read: article.is_read,
                    is_starred: article.is_starred,
                })
                .collect(),
            next_cursor: page.next_cursor,
        })
    }

    pub fn database_path(&self) -> PathBuf {
        self.store.database_path()
    }
    pub fn core_settings(&self) -> Result<CoreSettings, CoreError> {
        self.store.core_settings()
    }
    pub fn set_retention(&self, retention: ReadArticleRetention) -> Result<(), CoreError> {
        self.store.set_retention(retention)
    }
    pub fn set_background_sync_enabled(&self, enabled: bool) -> Result<(), CoreError> {
        self.store.set_background_sync_enabled(enabled)
    }
    pub fn import_legacy_policy_settings(
        &self,
        background_sync_enabled: Option<bool>,
        auto_download_listening_list: Option<bool>,
    ) -> Result<(), CoreError> {
        self.store
            .import_legacy_policy_settings(background_sync_enabled, auto_download_listening_list)
    }
    pub fn set_detail_character_limit(&self, limit: u32) -> Result<(), CoreError> {
        self.store.set_detail_character_limit(limit)
    }
    pub fn set_delivery_mode(&self, mode: DeliveryMode) -> Result<(), CoreError> {
        self.store.set_delivery_mode(mode)?;
        *self
            .delivery_mode
            .lock()
            .map_err(|_| CoreError::internal("delivery mode lock poisoned"))? = mode;
        Ok(())
    }
    pub fn set_download_network_policy(
        &self,
        policy: DownloadNetworkPolicy,
    ) -> Result<(), CoreError> {
        self.store.set_download_network_policy(policy)
    }
    pub fn set_download_retention(&self, retention: DownloadRetention) -> Result<(), CoreError> {
        self.store.set_download_retention(retention)
    }
    pub fn set_delete_after_playback(&self, enabled: bool) -> Result<(), CoreError> {
        self.store.set_delete_after_playback(enabled)
    }
    pub fn import_legacy_media_settings(
        &self,
        unmetered_only: Option<bool>,
        retention: Option<DownloadRetention>,
        delete_after_playback: Option<bool>,
    ) -> Result<(), CoreError> {
        self.store
            .import_legacy_media_settings(unmetered_only, retention, delete_after_playback)
    }
    pub fn set_auto_download_listening_list(&self, enabled: bool) -> Result<(), CoreError> {
        self.store.set_auto_download_listening_list(enabled)
    }
    pub fn set_remove_completed_listening_list(&self, enabled: bool) -> Result<(), CoreError> {
        self.store.set_remove_completed_listening_list(enabled)
    }
    pub fn runtime_health(&self) -> Result<RuntimeHealthStatus, CoreError> {
        let state = self
            .runtime
            .lock()
            .map_err(|_| CoreError::internal("delivery runtime lock poisoned"))?;
        Ok(RuntimeHealthStatus {
            health: state.health,
            next_retry_at: state.next_retry_at_utc.map(|time| time.to_rfc3339()),
        })
    }
    pub fn delivery_health(&self) -> Result<RuntimeHealth, CoreError> {
        Ok(self.runtime_health()?.health)
    }
    pub fn set_read_state(&self, article_id: i64, read: bool) -> Result<MutationResult, CoreError> {
        self.set_state_bulk(&[article_id], MutationField::Read, read)
    }
    pub fn set_read_state_bulk(
        &self,
        article_ids: &[i64],
        read: bool,
    ) -> Result<MutationResult, CoreError> {
        self.set_state_bulk(article_ids, MutationField::Read, read)
    }
    pub fn set_starred_state(
        &self,
        article_id: i64,
        starred: bool,
    ) -> Result<MutationResult, CoreError> {
        self.set_state_bulk(&[article_id], MutationField::Starred, starred)
    }
    pub fn set_starred_state_bulk(
        &self,
        article_ids: &[i64],
        starred: bool,
    ) -> Result<MutationResult, CoreError> {
        self.set_state_bulk(article_ids, MutationField::Starred, starred)
    }
    pub fn save_to_service(&self, article_id: i64) -> Result<SaveToServiceResult, CoreError> {
        if article_id <= 0 {
            return Err(CoreError::data("article ID must be positive"));
        }
        let result = tracing::dispatcher::with_default(&self.diagnostic_dispatcher, || {
            self.remote.save_to_service(article_id)
        });
        self.diagnostics.flush();
        result
    }
    pub fn discover_subscriptions(
        &self,
        request: DiscoverSubscriptionsRequest,
    ) -> Result<Vec<DiscoveredSubscription>, CoreError> {
        if request.url.trim().is_empty() {
            return Err(CoreError::data("discovery URL must not be empty"));
        }
        let result = tracing::dispatcher::with_default(&self.diagnostic_dispatcher, || {
            self.remote.discover_subscriptions(request)
        });
        self.diagnostics.flush();
        result
    }
    pub fn create_feed(&self, request: CreateFeedRequest) -> Result<CreateFeedResult, CoreError> {
        if request.feed_url.trim().is_empty() {
            return Err(CoreError::data("feed URL must not be empty"));
        }
        let result = tracing::dispatcher::with_default(&self.diagnostic_dispatcher, || {
            self.remote.create_feed(request)
        });
        self.diagnostics.flush();
        result
    }
    pub fn create_category(&self, title: String) -> Result<CreateCategoryResult, CoreError> {
        if title.trim().is_empty() {
            return Err(CoreError::data("category title must not be empty"));
        }
        let result = tracing::dispatcher::with_default(&self.diagnostic_dispatcher, || {
            self.remote.create_category(title)
        });
        self.diagnostics.flush();
        result
    }
    pub fn subscribe_events(&self, listener: Arc<dyn CoreEventListener>) -> Result<u64, CoreError> {
        let id = self
            .next_listener_id
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        self.listeners
            .lock()
            .map_err(|_| CoreError::internal("event listener lock poisoned"))?
            .insert(id, listener);
        Ok(id)
    }
    pub fn unsubscribe_events(&self, id: u64) -> Result<(), CoreError> {
        self.listeners
            .lock()
            .map_err(|_| CoreError::internal("event listener lock poisoned"))?
            .remove(&id);
        Ok(())
    }
    pub fn subscribe_diagnostics(&self, listener: Arc<dyn CoreDiagnosticListener>) -> u64 {
        let id = self.diagnostics.subscribe(listener);
        self.diagnostics.flush();
        id
    }
    pub fn unsubscribe_diagnostics(&self, id: u64) {
        self.diagnostics.unsubscribe(id);
    }
    fn set_state_bulk(
        &self,
        ids: &[i64],
        field: MutationField,
        desired: bool,
    ) -> Result<MutationResult, CoreError> {
        let result = tracing::dispatcher::with_default(&self.diagnostic_dispatcher, || {
            let _sync = self
                .sync_gate
                .lock()
                .map_err(|_| CoreError::internal("sync gate poisoned"))?;
            self.set_state_bulk_inner(ids, field, desired)
        });
        self.diagnostics.flush();
        result
    }
    fn search_set_state(
        &self,
        article_id: i64,
        field: MutationField,
        desired: bool,
        operation: impl FnOnce(&dyn RemoteSource) -> Result<(), CoreError>,
    ) -> Result<SearchMutationDisposition, CoreError> {
        if article_id <= 0 {
            return Err(CoreError::data("article ID must be positive"));
        }
        let result = tracing::dispatcher::with_default(&self.diagnostic_dispatcher, || {
            let _sync = self
                .sync_gate
                .lock()
                .map_err(|_| CoreError::internal("sync gate poisoned"))?;
            if self.store.local_article_state(article_id)?.is_some() {
                self.set_state_bulk_inner(&[article_id], field, desired)
                    .map(|_| SearchMutationDisposition::LocalFirst)
            } else {
                operation(self.remote.as_ref()).map(|_| SearchMutationDisposition::RemoteOnly)
            }
        });
        self.diagnostics.flush();
        result
    }
    fn set_state_bulk_inner(
        &self,
        ids: &[i64],
        field: MutationField,
        desired: bool,
    ) -> Result<MutationResult, CoreError> {
        let pending = self.store.set_state_bulk(ids, field, desired)?;
        tracing::debug!(target: "mutation", "mutation persisted field={field:?} desired={desired} count={}", pending.len());
        for item in &pending {
            self.emit(match field {
                MutationField::Read => CoreEvent::ArticleReadStateChanged {
                    article_id: item.article_id,
                    read: desired,
                },
                MutationField::Starred => CoreEvent::ArticleStarredStateChanged {
                    article_id: item.article_id,
                    starred: desired,
                },
            });
            self.emit(CoreEvent::MutationQueued {
                article_id: item.article_id,
                field,
            });
        }
        if *self
            .delivery_mode
            .lock()
            .map_err(|_| CoreError::internal("delivery mode lock poisoned"))?
            == DeliveryMode::Deferred
        {
            return Ok(MutationResult {
                disposition: DeliveryDisposition::Queued,
            });
        }
        if self.in_backoff()? {
            return Ok(MutationResult {
                disposition: DeliveryDisposition::DeferredByBackoff,
            });
        }
        match self.deliver_pending() {
            Ok(_) => Ok(MutationResult {
                disposition: DeliveryDisposition::Delivered,
            }),
            Err(error) if retryable(&error) => {
                self.record_failure(&error)?;
                Ok(MutationResult {
                    disposition: DeliveryDisposition::Queued,
                })
            }
            Err(_) => Ok(MutationResult {
                disposition: DeliveryDisposition::Queued,
            }),
        }
    }
    fn deliver_for_sync_cancellable(
        &self,
        reason: SyncReason,
        cancellation: &SyncCancellation,
    ) -> Result<Cancellable<mutations::DeliveryResult>, CoreError> {
        if cancellation.is_cancelled() {
            return Ok(Cancellable::Cancelled);
        }
        if reason != SyncReason::Manual && self.in_backoff()? {
            return Ok(Cancellable::Completed(mutations::DeliveryResult::default()));
        }
        match self.deliver_pending_cancellable(cancellation) {
            Ok(Cancellable::Completed(result)) => {
                self.clear_backoff().ok();
                Ok(Cancellable::Completed(result))
            }
            Ok(Cancellable::Cancelled) => Ok(Cancellable::Cancelled),
            Err(_) if cancellation.is_cancelled() => Ok(Cancellable::Cancelled),
            Err(error) if retryable(&error) => {
                self.record_failure(&error)?;
                Err(error)
            }
            Err(error) => Err(error),
        }
    }

    fn deliver_pending(&self) -> Result<mutations::DeliveryResult, CoreError> {
        let media_progress_capability = self.media_progress_capability();
        mutations::deliver_pending(
            self.remote.as_ref(),
            self.store.as_ref(),
            media_progress_capability,
            &|event| self.emit(event),
        )
        .inspect(|_| {
            self.clear_backoff().ok();
        })
    }

    fn deliver_pending_cancellable(
        &self,
        cancellation: &SyncCancellation,
    ) -> Result<Cancellable<mutations::DeliveryResult>, CoreError> {
        let media_progress_capability = self.media_progress_capability();
        mutations::deliver_pending_cancellable(
            self.remote.as_ref(),
            self.store.as_ref(),
            media_progress_capability,
            &|event| self.emit(event),
            cancellation,
        )
    }

    fn in_backoff(&self) -> Result<bool, CoreError> {
        Ok(self
            .runtime
            .lock()
            .map_err(|_| CoreError::internal("delivery runtime lock poisoned"))?
            .next_retry_at
            .is_some_and(|at| at > Instant::now()))
    }
    fn record_failure(&self, error: &CoreError) -> Result<(), CoreError> {
        let mut state = self
            .runtime
            .lock()
            .map_err(|_| CoreError::internal("delivery runtime lock poisoned"))?;
        state.health = if error.kind == CoreErrorKind::ServerTransient {
            RuntimeHealth::ServerDegraded
        } else {
            RuntimeHealth::ConnectivityDegraded
        };
        state.next_retry_at = Some(Instant::now() + Duration::from_secs(5));
        state.next_retry_at_utc = Some(Utc::now() + chrono::Duration::seconds(5));
        Ok(())
    }
    fn clear_backoff(&self) -> Result<(), CoreError> {
        let mut state = self
            .runtime
            .lock()
            .map_err(|_| CoreError::internal("delivery runtime lock poisoned"))?;
        state.health = RuntimeHealth::Healthy;
        state.next_retry_at = None;
        state.next_retry_at_utc = None;
        Ok(())
    }
    fn clear_regenerable_caches(&self) {
        if let Err(error) = self.feed_icons.clear() {
            tracing::warn!(target: "storage", "feed icon cache cleanup failed kind={:?}", error.kind);
        }
        if let Err(error) = self.article_thumbnails.clear() {
            tracing::warn!(target: "storage", "article thumbnail cache cleanup failed kind={:?}", error.kind);
        }
    }
    fn emit(&self, event: CoreEvent) {
        let listeners = self
            .listeners
            .lock()
            .map(|listeners| listeners.values().cloned().collect::<Vec<_>>())
            .unwrap_or_default();
        for listener in listeners {
            listener.on_event(event.clone());
        }
    }
}
fn retryable(error: &CoreError) -> bool {
    matches!(
        error.kind,
        CoreErrorKind::Connectivity | CoreErrorKind::ServerTransient
    )
}

fn validate_config(config: &CoreConfig) -> Result<(), CoreError> {
    if config.base_url.trim().is_empty() {
        return Err(CoreError::invalid_configuration("base URL is required"));
    }
    if config.api_key.is_empty() {
        return Err(CoreError::invalid_configuration("API key is required"));
    }
    validate_custom_headers(&config.custom_headers)
        .map_err(|_| CoreError::invalid_configuration("custom HTTP headers are invalid"))?;
    for path in [&config.persistent_data, &config.cache, &config.media] {
        if path.as_os_str().is_empty() {
            return Err(CoreError::invalid_configuration(
                "storage roots are required",
            ));
        }
        std::fs::create_dir_all(path).map_err(|e| {
            CoreError::persistence(format!("create storage root {}: {e}", path.display()))
        })?;
    }
    Ok(())
}

#[allow(dead_code)]
fn _is_beneath(path: &Path, root: &Path) -> bool {
    path.starts_with(root)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::*;
    use crate::miniflux::{RemoteSavedMediaArticle, RemoteSnapshot, RemoteSource};
    use chrono::{Duration as ChronoDuration, Utc};
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::thread;
    use std::time::Duration;
    use tempfile::TempDir;

    struct Source {
        snapshot: RemoteSnapshot,
        calls: AtomicUsize,
        delay: Duration,
    }
    struct MutationSource {
        snapshot: Mutex<RemoteSnapshot>,
        read_calls: AtomicUsize,
        star_calls: AtomicUsize,
        fetch_calls: AtomicUsize,
        failure: Mutex<Option<CoreError>>,
        log: Mutex<Vec<&'static str>>,
        delay: Mutex<Duration>,
    }
    struct SearchSource {
        search_calls: AtomicUsize,
        read_calls: AtomicUsize,
        star_calls: AtomicUsize,
        failure: Mutex<Option<CoreError>>,
        search_result: Mutex<SearchArticlesResult>,
        captured_requests: Mutex<Vec<SearchArticlesRequest>>,
    }
    struct ReentrantListener {
        core: Mutex<Option<Arc<FluxCore>>>,
        events: Mutex<Vec<CoreEvent>>,
    }
    struct DiagnosticCollector {
        records: Mutex<Vec<diagnostics::DiagnosticRecord>>,
    }
    struct ControlledSyncSource {
        snapshot: RemoteSnapshot,
        calls: AtomicUsize,
        fail_first: bool,
        started: std::sync::mpsc::Sender<()>,
        release: Mutex<std::sync::mpsc::Receiver<()>>,
    }
    struct PhaseLoggingSource {
        inner: Mutex<MutationSource>,
        fail_fetch: Mutex<bool>,
    }
    struct CancellingMutationSource {
        snapshot: RemoteSnapshot,
        cancellation: SyncCancellation,
        mutation_calls: AtomicUsize,
        fetch_calls: AtomicUsize,
    }
    struct CancellingFetchSource {
        snapshot: RemoteSnapshot,
        cancellation: SyncCancellation,
        fetch_calls: AtomicUsize,
    }
    struct MediaProgressSource {
        snapshot: RemoteSnapshot,
        fetch_calls: AtomicUsize,
        media_calls: Mutex<Vec<i64>>,
        media_results: Mutex<HashMap<i64, Result<(), CoreError>>>,
        capabilities: Mutex<Result<Vec<miniflux::MinifluxCapability>, CoreError>>,
    }
    impl CoreEventListener for ReentrantListener {
        fn on_event(&self, event: CoreEvent) {
            if let Some(core) = self.core.lock().unwrap().as_ref() {
                core.query_articles(ArticleQuery::default()).unwrap();
            }
            self.events.lock().unwrap().push(event);
        }
    }
    impl CoreDiagnosticListener for DiagnosticCollector {
        fn on_diagnostic(&self, record: diagnostics::DiagnosticRecord) {
            self.records.lock().unwrap().push(record);
        }
    }
    impl RemoteSource for CancellingMutationSource {
        fn fetch_initial_articles(&self) -> Result<RemoteSnapshot, CoreError> {
            self.fetch_calls.fetch_add(1, Ordering::SeqCst);
            Ok(self.snapshot.clone())
        }
        fn set_read_state(&self, _: &[i64], _: bool) -> Result<(), CoreError> {
            if self.mutation_calls.fetch_add(1, Ordering::SeqCst) == 0 {
                self.cancellation.cancel();
            }
            Ok(())
        }
        fn set_starred_state(&self, _: i64, _: bool) -> Result<(), CoreError> {
            if self.mutation_calls.fetch_add(1, Ordering::SeqCst) == 0 {
                self.cancellation.cancel();
            }
            Ok(())
        }
    }
    impl RemoteSource for CancellingFetchSource {
        fn fetch_initial_articles(&self) -> Result<RemoteSnapshot, CoreError> {
            self.fetch_calls.fetch_add(1, Ordering::SeqCst);
            self.cancellation.cancel();
            Ok(self.snapshot.clone())
        }
        fn set_read_state(&self, _: &[i64], _: bool) -> Result<(), CoreError> {
            Ok(())
        }
        fn set_starred_state(&self, _: i64, _: bool) -> Result<(), CoreError> {
            Ok(())
        }
    }
    impl RemoteSource for MutationSource {
        fn fetch_initial_articles(&self) -> Result<RemoteSnapshot, CoreError> {
            self.fetch_calls.fetch_add(1, Ordering::SeqCst);
            self.log.lock().unwrap().push("fetch");
            if let Some(error) = self.failure.lock().unwrap().clone() {
                return Err(error);
            }
            Ok(self.snapshot.lock().unwrap().clone())
        }
        fn set_read_state(&self, ids: &[i64], read: bool) -> Result<(), CoreError> {
            self.read_calls.fetch_add(1, Ordering::SeqCst);
            self.log.lock().unwrap().push("read");
            thread::sleep(*self.delay.lock().unwrap());
            if let Some(error) = self.failure.lock().unwrap().clone() {
                return Err(error);
            }
            for article in &mut self.snapshot.lock().unwrap().articles {
                if ids.contains(&article.id) {
                    article.is_read = read;
                }
            }
            Ok(())
        }
        fn set_starred_state(&self, id: i64, starred: bool) -> Result<(), CoreError> {
            self.star_calls.fetch_add(1, Ordering::SeqCst);
            self.log.lock().unwrap().push("star");
            if let Some(error) = self.failure.lock().unwrap().clone() {
                return Err(error);
            }
            for article in &mut self.snapshot.lock().unwrap().articles {
                if article.id == id {
                    article.is_starred = starred;
                }
            }
            Ok(())
        }
    }
    impl RemoteSource for Source {
        fn fetch_initial_articles(&self) -> Result<RemoteSnapshot, CoreError> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            thread::sleep(self.delay);
            Ok(self.snapshot.clone())
        }
        fn set_read_state(&self, _article_ids: &[i64], _read: bool) -> Result<(), CoreError> {
            Ok(())
        }
        fn set_starred_state(&self, _article_id: i64, _starred: bool) -> Result<(), CoreError> {
            Ok(())
        }
    }
    impl RemoteSource for SearchSource {
        fn fetch_initial_articles(&self) -> Result<RemoteSnapshot, CoreError> {
            Ok(RemoteSnapshot {
                categories: vec![],
                feeds: vec![],
                articles: vec![],
                enclosures: vec![],
            })
        }
        fn set_read_state(&self, _: &[i64], _: bool) -> Result<(), CoreError> {
            self.read_calls.fetch_add(1, Ordering::SeqCst);
            if let Some(error) = self.failure.lock().unwrap().clone() {
                return Err(error);
            }
            Ok(())
        }
        fn set_starred_state(&self, _: i64, _: bool) -> Result<(), CoreError> {
            self.star_calls.fetch_add(1, Ordering::SeqCst);
            if let Some(error) = self.failure.lock().unwrap().clone() {
                return Err(error);
            }
            Ok(())
        }
        fn search_articles(
            &self,
            request: SearchArticlesRequest,
        ) -> Result<SearchArticlesResult, CoreError> {
            self.search_calls.fetch_add(1, Ordering::SeqCst);
            self.captured_requests.lock().unwrap().push(request.clone());
            assert_eq!(request.query, "rust");
            Ok(self.search_result.lock().unwrap().clone())
        }
        fn fetch_article_by_id(
            &self,
            article_id: i64,
        ) -> Result<RemoteSavedMediaArticle, CoreError> {
            if article_id != 99 {
                return Err(CoreError::data(format!(
                    "article {article_id} was not found remotely"
                )));
            }
            Ok(RemoteSavedMediaArticle {
                article: Article {
                    id: 99,
                    feed_id: 10,
                    title: "Remote result".into(),
                    url: "https://example.test/99".into(),
                    comments_url: String::new(),
                    published_at: "2026-01-02T03:04:05Z".into(),
                    is_read: false,
                    is_starred: false,
                    raw_html_content: "<p>Equivalent content</p>".into(),
                    reading_time_minutes: 0,
                    preview: "Remote preview".into(),
                    image_url: None,
                },
                enclosures: vec![],
            })
        }
    }
    impl RemoteSource for PhaseLoggingSource {
        fn fetch_initial_articles(&self) -> Result<RemoteSnapshot, CoreError> {
            let inner = self.inner.lock().unwrap();
            inner.fetch_calls.fetch_add(1, Ordering::SeqCst);
            inner.log.lock().unwrap().push("fetch");
            if *self.fail_fetch.lock().unwrap() {
                return Err(CoreError::connectivity("offline"));
            }
            Ok(inner.snapshot.lock().unwrap().clone())
        }
        fn set_read_state(&self, ids: &[i64], read: bool) -> Result<(), CoreError> {
            let inner = self.inner.lock().unwrap();
            inner.read_calls.fetch_add(1, Ordering::SeqCst);
            inner.log.lock().unwrap().push("read");
            if let Some(error) = inner.failure.lock().unwrap().clone() {
                return Err(error);
            }
            for article in &mut inner.snapshot.lock().unwrap().articles {
                if ids.contains(&article.id) {
                    article.is_read = read;
                }
            }
            Ok(())
        }
        fn set_starred_state(&self, id: i64, starred: bool) -> Result<(), CoreError> {
            let inner = self.inner.lock().unwrap();
            inner.star_calls.fetch_add(1, Ordering::SeqCst);
            inner.log.lock().unwrap().push("star");
            if let Some(error) = inner.failure.lock().unwrap().clone() {
                return Err(error);
            }
            for article in &mut inner.snapshot.lock().unwrap().articles {
                if article.id == id {
                    article.is_starred = starred;
                }
            }
            Ok(())
        }
    }
    impl RemoteSource for ControlledSyncSource {
        fn fetch_initial_articles(&self) -> Result<RemoteSnapshot, CoreError> {
            let call = self.calls.fetch_add(1, Ordering::SeqCst);
            self.started.send(()).unwrap();
            self.release.lock().unwrap().recv().unwrap();
            if self.fail_first && call == 0 {
                return Err(CoreError::connectivity("offline"));
            }
            Ok(self.snapshot.clone())
        }
        fn set_read_state(&self, _: &[i64], _: bool) -> Result<(), CoreError> {
            Ok(())
        }
        fn set_starred_state(&self, _: i64, _: bool) -> Result<(), CoreError> {
            Ok(())
        }
    }
    impl RemoteSource for MediaProgressSource {
        fn fetch_initial_articles(&self) -> Result<RemoteSnapshot, CoreError> {
            self.fetch_calls.fetch_add(1, Ordering::SeqCst);
            Ok(self.snapshot.clone())
        }
        fn set_read_state(&self, _: &[i64], _: bool) -> Result<(), CoreError> {
            Ok(())
        }
        fn set_starred_state(&self, _: i64, _: bool) -> Result<(), CoreError> {
            Ok(())
        }
        fn set_media_progression(&self, enclosure_id: i64, _: u64) -> Result<(), CoreError> {
            self.media_calls.lock().unwrap().push(enclosure_id);
            self.media_results
                .lock()
                .unwrap()
                .get(&enclosure_id)
                .cloned()
                .unwrap_or(Ok(()))
        }
        fn miniflux_capabilities(&self) -> Result<Vec<miniflux::MinifluxCapability>, CoreError> {
            self.capabilities.lock().unwrap().clone()
        }
    }
    fn search_result() -> SearchArticlesResult {
        SearchArticlesResult {
            total: 1,
            articles: vec![ArticleSummary {
                id: 99,
                feed_id: 10,
                category_id: 1,
                feed_title: "Feed A".into(),
                title: "Remote result".into(),
                url: "https://example.test/99".into(),
                comments_url: String::new(),
                published_at: "2026-01-02T03:04:05Z".into(),
                reading_time_minutes: 0,
                is_read: false,
                is_starred: false,
                preview: "Remote preview".into(),
                image_url: None,
            }],
        }
    }
    fn article(id: i64, feed_id: i64, published_at: String, read: bool, starred: bool) -> Article {
        Article {
            id,
            feed_id,
            title: format!("article {id}"),
            url: format!("https://example.test/{id}"),
            comments_url: String::new(),
            published_at,
            is_read: read,
            is_starred: starred,
            raw_html_content: format!("<p>{id}</p>"),
            reading_time_minutes: 0,
            preview: id.to_string(),
            image_url: None,
        }
    }
    fn snapshot() -> RemoteSnapshot {
        let now = Utc::now();
        RemoteSnapshot {
            categories: vec![
                Category {
                    id: 1,
                    title: "News".into(),
                },
                Category {
                    id: 2,
                    title: "Other".into(),
                },
            ],
            feeds: vec![
                Feed {
                    id: 10,
                    category_id: 1,
                    title: "Feed A".into(),
                },
                Feed {
                    id: 20,
                    category_id: 2,
                    title: "Feed B".into(),
                },
            ],
            articles: vec![
                article(
                    1,
                    10,
                    (now - ChronoDuration::days(1)).to_rfc3339(),
                    false,
                    false,
                ),
                article(
                    2,
                    10,
                    (now - ChronoDuration::days(2)).to_rfc3339(),
                    true,
                    true,
                ),
                article(
                    3,
                    20,
                    (now - ChronoDuration::days(3)).to_rfc3339(),
                    true,
                    false,
                ),
            ],
            enclosures: vec![],
        }
    }
    fn config(temp: &TempDir) -> CoreConfig {
        CoreConfig {
            persistent_data: temp.path().join("data"),
            cache: temp.path().join("cache"),
            media: temp.path().join("media"),
            base_url: "https://miniflux.example".into(),
            api_key: "test-secret".into(),
            custom_headers: vec![],
        }
    }
    fn core(temp: &TempDir, snapshot: RemoteSnapshot) -> (Arc<FluxCore>, Arc<Source>) {
        let source = Arc::new(Source {
            snapshot,
            calls: AtomicUsize::new(0),
            delay: Duration::ZERO,
        });
        let core = Arc::new(FluxCore::with_remote(config(temp), source.clone()).unwrap());
        (core, source)
    }
    fn mutation_core(temp: &TempDir) -> (Arc<FluxCore>, Arc<MutationSource>) {
        let source = Arc::new(MutationSource {
            snapshot: Mutex::new(snapshot()),
            read_calls: AtomicUsize::new(0),
            star_calls: AtomicUsize::new(0),
            fetch_calls: AtomicUsize::new(0),
            failure: Mutex::new(None),
            log: Mutex::new(vec![]),
            delay: Mutex::new(Duration::ZERO),
        });
        let core = Arc::new(FluxCore::with_remote(config(temp), source.clone()).unwrap());
        core.sync(SyncReason::Manual).unwrap();
        source.log.lock().unwrap().clear();
        (core, source)
    }
    fn search_core(temp: &TempDir) -> (Arc<FluxCore>, Arc<SearchSource>) {
        let source = Arc::new(SearchSource {
            search_calls: AtomicUsize::new(0),
            read_calls: AtomicUsize::new(0),
            star_calls: AtomicUsize::new(0),
            failure: Mutex::new(None),
            search_result: Mutex::new(search_result()),
            captured_requests: Mutex::new(vec![]),
        });
        let core = Arc::new(FluxCore::with_remote(config(temp), source.clone()).unwrap());
        (core, source)
    }
    fn phase_core(temp: &TempDir) -> (Arc<FluxCore>, Arc<PhaseLoggingSource>) {
        let inner = MutationSource {
            snapshot: Mutex::new(snapshot()),
            read_calls: AtomicUsize::new(0),
            star_calls: AtomicUsize::new(0),
            fetch_calls: AtomicUsize::new(0),
            failure: Mutex::new(None),
            log: Mutex::new(vec![]),
            delay: Mutex::new(Duration::ZERO),
        };
        let source = Arc::new(PhaseLoggingSource {
            inner: Mutex::new(inner),
            fail_fetch: Mutex::new(false),
        });
        let core = Arc::new(FluxCore::with_remote(config(temp), source.clone()).unwrap());
        core.sync(SyncReason::Manual).unwrap();
        source.inner.lock().unwrap().log.lock().unwrap().clear();
        (core, source)
    }
    fn media_progress_core(
        temp: &TempDir,
        capabilities: Result<Vec<miniflux::MinifluxCapability>, CoreError>,
    ) -> (Arc<FluxCore>, Arc<MediaProgressSource>) {
        let mut remote_snapshot = snapshot();
        remote_snapshot.enclosures = vec![
            Enclosure {
                id: 101,
                article_id: 1,
                url: "https://cdn.test/101.mp3".into(),
                mime_type: "audio/mpeg".into(),
                size_bytes: None,
                remote_media_progression_seconds: 0,
            },
            Enclosure {
                id: 102,
                article_id: 1,
                url: "https://cdn.test/102.mp3".into(),
                mime_type: "audio/mpeg".into(),
                size_bytes: None,
                remote_media_progression_seconds: 0,
            },
        ];
        let source = Arc::new(MediaProgressSource {
            snapshot: remote_snapshot,
            fetch_calls: AtomicUsize::new(0),
            media_calls: Mutex::new(Vec::new()),
            media_results: Mutex::new(HashMap::new()),
            capabilities: Mutex::new(capabilities),
        });
        let core = Arc::new(FluxCore::with_remote(config(temp), source.clone()).unwrap());
        (core, source)
    }

    #[test]
    fn media_progress_delivery_acknowledges_mutations_and_preserves_playback() {
        let temp = TempDir::new().unwrap();
        let (core, source) = media_progress_core(
            &temp,
            Ok(vec![miniflux::MinifluxCapability::MediaProgressSync]),
        );
        core.sync(SyncReason::Manual).unwrap();
        core.checkpoint_playback(101, 12_000, None).unwrap();

        let completed = core.sync(SyncReason::Manual).unwrap();

        assert_eq!(completed.mutations_delivered, 1);
        assert!(
            core.store
                .pending_media_progress_mutations()
                .unwrap()
                .is_empty()
        );
        assert_eq!(
            core.playback_state(101).unwrap().unwrap().position_ms,
            12_000
        );
        assert_eq!(*source.media_calls.lock().unwrap(), vec![101]);
        assert_eq!(source.fetch_calls.load(Ordering::SeqCst), 2);
    }

    #[test]
    fn missing_media_progress_target_is_discarded_without_blocking_later_delivery_or_sync() {
        let temp = TempDir::new().unwrap();
        let (core, source) = media_progress_core(
            &temp,
            Ok(vec![miniflux::MinifluxCapability::MediaProgressSync]),
        );
        core.sync(SyncReason::Manual).unwrap();
        core.checkpoint_playback(101, 12_000, None).unwrap();
        core.checkpoint_playback(102, 24_000, None).unwrap();
        source.media_results.lock().unwrap().insert(
            101,
            Err(
                CoreError::invalid_configuration("Miniflux returned HTTP 404")
                    .with_http_status(404),
            ),
        );

        let completed = core.sync(SyncReason::Manual).unwrap();

        assert_eq!(completed.mutations_delivered, 1);
        assert!(
            core.store
                .pending_media_progress_mutations()
                .unwrap()
                .is_empty()
        );
        assert_eq!(
            core.playback_state(101).unwrap().unwrap().position_ms,
            12_000
        );
        assert_eq!(*source.media_calls.lock().unwrap(), vec![101, 102]);
        assert_eq!(source.fetch_calls.load(Ordering::SeqCst), 2);
    }

    #[test]
    fn server_failure_keeps_media_progress_pending() {
        let temp = TempDir::new().unwrap();
        let (core, source) = media_progress_core(
            &temp,
            Ok(vec![miniflux::MinifluxCapability::MediaProgressSync]),
        );
        core.sync(SyncReason::Manual).unwrap();
        core.checkpoint_playback(101, 12_000, None).unwrap();
        source.media_results.lock().unwrap().insert(
            101,
            Err(
                CoreError::server_transient("Miniflux server returned HTTP 500")
                    .with_http_status(500),
            ),
        );

        assert_eq!(
            core.sync(SyncReason::Manual).unwrap_err().kind,
            CoreErrorKind::ServerTransient
        );
        assert_eq!(
            core.store.pending_media_progress_mutations().unwrap().len(),
            1
        );
        assert_eq!(source.fetch_calls.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn rate_limit_keeps_media_progress_pending() {
        let temp = TempDir::new().unwrap();
        let (core, source) = media_progress_core(
            &temp,
            Ok(vec![miniflux::MinifluxCapability::MediaProgressSync]),
        );
        core.sync(SyncReason::Manual).unwrap();
        core.checkpoint_playback(101, 12_000, None).unwrap();
        source.media_results.lock().unwrap().insert(
            101,
            Err(
                CoreError::server_transient("Miniflux server returned HTTP 429")
                    .with_http_status(429),
            ),
        );

        assert_eq!(
            core.sync(SyncReason::Manual).unwrap_err().kind,
            CoreErrorKind::ServerTransient
        );
        assert_eq!(
            core.store.pending_media_progress_mutations().unwrap().len(),
            1
        );
    }

    #[test]
    fn connectivity_and_authentication_failures_keep_media_progress_pending() {
        for error in [
            CoreError::connectivity("offline"),
            CoreError::authentication("Miniflux rejected credentials").with_http_status(401),
        ] {
            let temp = TempDir::new().unwrap();
            let (core, source) = media_progress_core(
                &temp,
                Ok(vec![miniflux::MinifluxCapability::MediaProgressSync]),
            );
            core.sync(SyncReason::Manual).unwrap();
            core.checkpoint_playback(101, 12_000, None).unwrap();
            let expected_kind = error.kind.clone();
            source.media_results.lock().unwrap().insert(101, Err(error));

            assert_eq!(
                core.sync(SyncReason::Manual).unwrap_err().kind,
                expected_kind
            );
            assert_eq!(
                core.store.pending_media_progress_mutations().unwrap().len(),
                1
            );
        }
    }

    #[test]
    fn unsupported_media_progress_discards_remote_intents_without_touching_playback() {
        let temp = TempDir::new().unwrap();
        let (core, source) = media_progress_core(&temp, Ok(Vec::new()));
        core.sync(SyncReason::Manual).unwrap();
        core.store
            .checkpoint_playback(101, 12_000, None, "2026-01-01T00:00:00Z", true)
            .unwrap();

        core.sync(SyncReason::Manual).unwrap();

        assert!(source.media_calls.lock().unwrap().is_empty());
        assert!(
            core.store
                .pending_media_progress_mutations()
                .unwrap()
                .is_empty()
        );
        assert_eq!(
            core.playback_state(101).unwrap().unwrap().position_ms,
            12_000
        );
    }

    #[test]
    fn unknown_media_progress_capability_retains_pending_intents() {
        let temp = TempDir::new().unwrap();
        let (core, source) = media_progress_core(&temp, Err(CoreError::connectivity("offline")));
        core.sync(SyncReason::Manual).unwrap();
        core.store
            .checkpoint_playback(101, 12_000, None, "2026-01-01T00:00:00Z", true)
            .unwrap();

        core.sync(SyncReason::Manual).unwrap();

        assert!(source.media_calls.lock().unwrap().is_empty());
        assert_eq!(
            core.store.pending_media_progress_mutations().unwrap().len(),
            1
        );
        assert_eq!(source.fetch_calls.load(Ordering::SeqCst), 2);
    }

    #[test]
    fn initialization_creates_versioned_database_under_platform_root() {
        let temp = TempDir::new().unwrap();
        let (core, _) = core(&temp, snapshot());
        assert_eq!(core.database_path(), temp.path().join("data/flux.sqlite3"));
        assert!(core.database_path().exists());
        let conn = rusqlite::Connection::open(core.database_path()).unwrap();
        assert_eq!(
            conn.query_row("PRAGMA user_version", [], |r| r.get::<_, i64>(0))
                .unwrap(),
            22
        );
        let bytes = std::fs::read(core.database_path()).unwrap();
        assert!(
            !bytes
                .windows(b"test-secret".len())
                .any(|w| w == b"test-secret")
        );
    }

    #[test]
    fn configured_installation_base_is_canonical_and_resolves_web_entries() {
        let temp = TempDir::new().unwrap();
        let source = Arc::new(Source {
            snapshot: snapshot(),
            calls: AtomicUsize::new(0),
            delay: Duration::ZERO,
        });
        let mut configuration = config(&temp);
        configuration.base_url = "https://miniflux.example/news/v1/".into();
        let core = FluxCore::with_remote(configuration, source).unwrap();

        assert_eq!(
            core.store.base_url().unwrap().as_deref(),
            Some("https://miniflux.example/news")
        );
        assert_eq!(
            core.miniflux_entry_url(583862),
            "https://miniflux.example/news/unread/entry/583862"
        );
    }
    #[test]
    fn core_settings_default_and_persist_without_changing_articles_or_navigation() {
        let temp = TempDir::new().unwrap();
        let (core, _) = core(&temp, snapshot());
        assert_eq!(core.core_settings().unwrap(), CoreSettings::default());

        core.sync(SyncReason::Manual).unwrap();
        assert_eq!(
            core.set_read_state(1, true).unwrap().disposition,
            DeliveryDisposition::Queued
        );
        let articles = core
            .query_articles(ArticleQuery {
                limit: 0,
                ..Default::default()
            })
            .unwrap();
        let navigation = core.navigation_catalog().unwrap();
        for retention in [
            ReadArticleRetention::Days30,
            ReadArticleRetention::Days60,
            ReadArticleRetention::Days90,
            ReadArticleRetention::Days180,
            ReadArticleRetention::Days365,
        ] {
            core.set_retention(retention).unwrap();
            assert_eq!(core.core_settings().unwrap().retention, retention);
        }
        core.set_delivery_mode(DeliveryMode::Live).unwrap();
        core.set_background_sync_enabled(true).unwrap();
        for limit in [5_000, 10_000, 20_000] {
            core.set_detail_character_limit(limit).unwrap();
            assert_eq!(core.core_settings().unwrap().detail_character_limit, limit);
        }
        assert_eq!(
            core.core_settings().unwrap(),
            CoreSettings {
                retention: ReadArticleRetention::Days365,
                delivery_mode: DeliveryMode::Live,
                background_sync_enabled: true,
                detail_character_limit: 20_000,
                ..CoreSettings::default()
            }
        );
        assert_eq!(
            core.query_articles(ArticleQuery {
                limit: 0,
                ..Default::default()
            })
            .unwrap(),
            articles
        );
        assert_eq!(core.navigation_catalog().unwrap(), navigation);

        drop(core);
        let reopened = FluxCore::with_remote(
            config(&temp),
            Arc::new(Source {
                snapshot: snapshot(),
                calls: AtomicUsize::new(0),
                delay: Duration::ZERO,
            }),
        )
        .unwrap();
        assert_eq!(
            reopened.core_settings().unwrap(),
            CoreSettings {
                retention: ReadArticleRetention::Days365,
                delivery_mode: DeliveryMode::Live,
                background_sync_enabled: true,
                detail_character_limit: 20_000,
                ..CoreSettings::default()
            }
        );
        assert_eq!(
            reopened.set_read_state(1, false).unwrap().disposition,
            DeliveryDisposition::Delivered
        );
    }
    #[test]
    fn sync_persists_categories_feeds_and_articles() {
        let temp = TempDir::new().unwrap();
        let (core, source) = core(&temp, snapshot());
        core.sync(SyncReason::Manual).unwrap();
        assert_eq!(source.calls.load(Ordering::SeqCst), 1);
        let rows = core
            .query_articles(ArticleQuery {
                limit: 0,
                ..Default::default()
            })
            .unwrap();
        assert_eq!(rows.len(), 3);
        assert_eq!(rows[0].feed_title, "Feed A");
        assert_eq!(rows[0].category_id, 1);
    }
    #[test]
    fn reader_document_loads_stored_html_using_feed_preferences_and_global_limit() {
        let temp = TempDir::new().unwrap();
        let mut data = snapshot();
        data.articles[0].raw_html_content = format!(
            "<p>First block</p><img src=\"/image.jpg\"><p>{}</p>",
            "long ".repeat(1_001)
        );
        let (core, _) = core(&temp, data);
        core.sync(SyncReason::Manual).unwrap();

        let rendered = core.reader_document(1).unwrap();
        assert!(matches!(rendered.blocks[1], ReaderBlock::Image { .. }));
        assert!(!rendered.was_truncated);

        core.set_feed_detail_rendering(10, DetailRenderingMode::TextOnly)
            .unwrap();
        core.set_feed_truncate_detail(10, true).unwrap();
        core.set_detail_character_limit(5_000).unwrap();
        let text_only = core.reader_document(1).unwrap();
        assert!(
            !text_only
                .blocks
                .iter()
                .any(|block| matches!(block, ReaderBlock::Image { .. }))
        );
        assert!(text_only.was_truncated);
        assert!(core.reader_document(999).is_err());
    }
    #[test]
    fn reader_document_loads_persisted_image_url_for_rendered_fallback() {
        let temp = TempDir::new().unwrap();
        let mut data = snapshot();
        data.articles[0].raw_html_content = "<p>Article text</p>".into();
        data.articles[0].image_url = Some("https://images.test/persisted.jpg".into());
        let (core, _) = core(&temp, data);
        core.sync(SyncReason::Manual).unwrap();

        let document = core.reader_document(1).unwrap();
        assert!(
            matches!(&document.blocks[..], [ReaderBlock::Image { url, alt: None, link: None }, ReaderBlock::Paragraph { .. }] if url == "https://images.test/persisted.jpg")
        );
    }
    #[test]
    fn diagnostics_are_structured_safe_and_advisory() {
        let temp = TempDir::new().unwrap();
        let (core, _) = core(&temp, snapshot());
        let collector = Arc::new(DiagnosticCollector {
            records: Mutex::new(vec![]),
        });
        let subscription = core.subscribe_diagnostics(collector.clone());
        let initialization_records = std::mem::take(&mut *collector.records.lock().unwrap());
        assert!(
            initialization_records
                .iter()
                .any(|record| record.target == "core" && record.message.contains("initialization"))
        );

        core.sync(SyncReason::Manual).unwrap();
        let records = std::mem::take(&mut *collector.records.lock().unwrap());
        assert!(
            records
                .iter()
                .any(|record| record.target == "sync" && record.message.contains("sync started"))
        );
        assert!(records.iter().any(|record| {
            record.target == "retention" && record.message.contains("cleanup completed")
        }));
        assert!(
            records
                .iter()
                .all(|record| !record.message.contains("test-secret"))
        );

        core.unsubscribe_diagnostics(subscription);
        core.sync(SyncReason::Manual).unwrap();
        assert!(collector.records.lock().unwrap().is_empty());
    }
    #[test]
    fn query_applies_scope_independent_state_filters_and_sorting() {
        let temp = TempDir::new().unwrap();
        let (core, _) = core(&temp, snapshot());
        core.sync(SyncReason::Manual).unwrap();
        let category = core
            .query_articles(ArticleQuery {
                scope: ArticleScope::Category(1),
                limit: 0,
                ..Default::default()
            })
            .unwrap();
        assert_eq!(
            category.iter().map(|a| a.id).collect::<Vec<_>>(),
            vec![1, 2]
        );
        let feed = core
            .query_articles(ArticleQuery {
                scope: ArticleScope::Feed(20),
                limit: 0,
                ..Default::default()
            })
            .unwrap();
        assert_eq!(feed.iter().map(|a| a.id).collect::<Vec<_>>(), vec![3]);
        let unread = core
            .query_articles(ArticleQuery {
                read_filter: ReadFilter::Unread,
                limit: 0,
                ..Default::default()
            })
            .unwrap();
        assert_eq!(unread.iter().map(|a| a.id).collect::<Vec<_>>(), vec![1]);
        let starred = core
            .query_articles(ArticleQuery {
                starred_filter: StarredFilter::Starred,
                limit: 0,
                ..Default::default()
            })
            .unwrap();
        assert_eq!(starred.iter().map(|a| a.id).collect::<Vec<_>>(), vec![2]);
        let oldest = core
            .query_articles(ArticleQuery {
                sort: ArticleSort::OldestFirst,
                limit: 0,
                ..Default::default()
            })
            .unwrap();
        assert_eq!(
            oldest.iter().map(|a| a.id).collect::<Vec<_>>(),
            vec![3, 2, 1]
        );
    }
    #[test]
    fn keyset_pagination_is_deterministic_for_identical_publication_times_and_zero_limit_is_all() {
        let temp = TempDir::new().unwrap();
        let time = Utc::now().to_rfc3339();
        let mut data = snapshot();
        data.articles = vec![
            article(3, 10, time.clone(), false, false),
            article(1, 10, time.clone(), false, false),
            article(2, 10, time, false, false),
        ];
        let (core, _) = core(&temp, data);
        core.sync(SyncReason::Manual).unwrap();
        let first = core
            .query_articles(ArticleQuery {
                limit: 2,
                ..Default::default()
            })
            .unwrap();
        assert_eq!(first.iter().map(|a| a.id).collect::<Vec<_>>(), vec![3, 2]);
        let second = core
            .query_articles(ArticleQuery {
                limit: 2,
                cursor: Some(ArticleCursor {
                    published_at: first[1].published_at.clone(),
                    article_id: first[1].id,
                }),
                ..Default::default()
            })
            .unwrap();
        assert_eq!(second.iter().map(|a| a.id).collect::<Vec<_>>(), vec![1]);
        assert_eq!(
            core.query_articles(ArticleQuery {
                limit: 0,
                ..Default::default()
            })
            .unwrap()
            .len(),
            3
        );
    }
    #[test]
    fn article_page_preserves_keyset_order_and_total_without_cursor() {
        let temp = TempDir::new().unwrap();
        let time = Utc::now().to_rfc3339();
        let mut data = snapshot();
        data.articles = vec![
            article(4, 10, time.clone(), false, true),
            article(3, 10, time.clone(), false, true),
            article(2, 10, time.clone(), true, false),
            article(1, 10, time, false, false),
        ];
        let (core, _) = core(&temp, data);
        core.sync(SyncReason::Manual).unwrap();
        let first = core
            .article_page(
                ArticleQuery {
                    limit: 2,
                    ..Default::default()
                },
                true,
            )
            .unwrap();
        assert_eq!(
            first
                .articles
                .iter()
                .map(|article| article.id)
                .collect::<Vec<_>>(),
            vec![4, 3]
        );
        assert_eq!(first.total, Some(4));
        let second = core
            .article_page(
                ArticleQuery {
                    limit: 2,
                    cursor: first.next_cursor,
                    ..Default::default()
                },
                false,
            )
            .unwrap();
        assert_eq!(
            second
                .articles
                .iter()
                .map(|article| article.id)
                .collect::<Vec<_>>(),
            vec![2, 1]
        );
        assert_eq!(second.total, None);
        assert!(second.next_cursor.is_none());
        let oldest = core
            .article_page(
                ArticleQuery {
                    sort: ArticleSort::OldestFirst,
                    limit: 2,
                    ..Default::default()
                },
                true,
            )
            .unwrap();
        assert_eq!(
            oldest
                .articles
                .iter()
                .map(|article| article.id)
                .collect::<Vec<_>>(),
            vec![1, 2]
        );
        assert_eq!(oldest.total, Some(4));
    }

    #[test]
    fn article_page_applies_scope_filters_and_tracks_local_mutations() {
        let temp = TempDir::new().unwrap();
        let (core, _) = core(&temp, snapshot());
        core.sync(SyncReason::Manual).unwrap();

        let category = core
            .article_page(
                ArticleQuery {
                    scope: ArticleScope::Category(1),
                    limit: 1,
                    ..Default::default()
                },
                true,
            )
            .unwrap();
        assert_eq!(
            category
                .articles
                .iter()
                .map(|article| article.id)
                .collect::<Vec<_>>(),
            vec![1]
        );
        assert_eq!(category.total, Some(2));
        assert!(category.next_cursor.is_some());

        let feed = core
            .article_page(
                ArticleQuery {
                    scope: ArticleScope::Feed(20),
                    limit: 1,
                    ..Default::default()
                },
                true,
            )
            .unwrap();
        assert_eq!(
            feed.articles
                .iter()
                .map(|article| article.id)
                .collect::<Vec<_>>(),
            vec![3]
        );
        assert_eq!(feed.total, Some(1));
        assert!(feed.next_cursor.is_none());

        let unread = core
            .article_page(
                ArticleQuery {
                    read_filter: ReadFilter::Unread,
                    limit: 1,
                    ..Default::default()
                },
                true,
            )
            .unwrap();
        assert_eq!(
            unread
                .articles
                .iter()
                .map(|article| article.id)
                .collect::<Vec<_>>(),
            vec![1]
        );
        assert_eq!(unread.total, Some(1));

        let starred = core
            .article_page(
                ArticleQuery {
                    starred_filter: StarredFilter::Starred,
                    limit: 1,
                    ..Default::default()
                },
                true,
            )
            .unwrap();
        assert_eq!(
            starred
                .articles
                .iter()
                .map(|article| article.id)
                .collect::<Vec<_>>(),
            vec![2]
        );
        assert_eq!(starred.total, Some(1));

        let empty = core
            .article_page(
                ArticleQuery {
                    scope: ArticleScope::Feed(999),
                    limit: 1,
                    ..Default::default()
                },
                true,
            )
            .unwrap();
        assert!(empty.articles.is_empty());
        assert_eq!(empty.total, Some(0));
        assert!(empty.next_cursor.is_none());

        core.set_read_state(1, true).unwrap();
        core.set_starred_state(2, false).unwrap();
        assert_eq!(
            core.article_page(
                ArticleQuery {
                    read_filter: ReadFilter::Unread,
                    limit: 1,
                    ..Default::default()
                },
                true
            )
            .unwrap()
            .total,
            Some(0)
        );
        assert_eq!(
            core.article_page(
                ArticleQuery {
                    starred_filter: StarredFilter::Starred,
                    limit: 1,
                    ..Default::default()
                },
                true
            )
            .unwrap()
            .total,
            Some(0)
        );
    }
    #[test]
    fn sync_retention_removes_only_expired_unstarred_read_articles() {
        let temp = TempDir::new().unwrap();
        let old = (Utc::now() - ChronoDuration::days(91)).to_rfc3339();
        let mut data = snapshot();
        data.articles = vec![
            article(1, 10, old.clone(), false, false),
            article(2, 10, old.clone(), true, true),
            article(3, 10, old, true, false),
        ];
        let (core, _) = core(&temp, data);
        core.sync(SyncReason::AppStart).unwrap();
        assert_eq!(
            core.query_articles(ArticleQuery {
                limit: 0,
                ..Default::default()
            })
            .unwrap()
            .iter()
            .map(|a| a.id)
            .collect::<Vec<_>>(),
            vec![2, 1]
        );
    }
    #[test]
    fn configured_retention_controls_cleanup() {
        let temp = TempDir::new().unwrap();
        let mut data = snapshot();
        data.articles = vec![article(
            1,
            10,
            (Utc::now() - ChronoDuration::days(45)).to_rfc3339(),
            true,
            false,
        )];
        let (core, _) = core(&temp, data);
        core.set_retention(ReadArticleRetention::Days30).unwrap();
        core.sync(SyncReason::Manual).unwrap();
        assert!(
            core.query_articles(ArticleQuery {
                limit: 0,
                ..Default::default()
            })
            .unwrap()
            .is_empty()
        );
    }
    #[test]
    fn sync_keeps_existing_recent_read_articles_absent_from_remote_sets() {
        let temp = TempDir::new().unwrap();
        let mut remote = snapshot();
        remote.articles.clear();
        let (core, _) = core(&temp, remote.clone());
        let recent_read = article(
            4,
            10,
            (Utc::now() - ChronoDuration::days(89)).to_rfc3339(),
            true,
            false,
        );
        core.store
            .reconcile(&remote.categories, &remote.feeds, &[recent_read])
            .unwrap();

        core.sync(SyncReason::Manual).unwrap();

        assert_eq!(
            core.query_articles(ArticleQuery {
                limit: 0,
                ..Default::default()
            })
            .unwrap()
            .iter()
            .map(|article| article.id)
            .collect::<Vec<_>>(),
            vec![4]
        );
    }
    #[test]
    fn sync_does_not_mark_enclosures_absent_for_articles_outside_the_remote_snapshot() {
        let temp = TempDir::new().unwrap();
        let (core, source) = mutation_core(&temp);
        core.store
            .upsert_remote_enclosures(&[
                Enclosure {
                    id: 101,
                    article_id: 1,
                    url: "https://cdn.test/101.mp3".into(),
                    mime_type: "audio/mpeg".into(),
                    size_bytes: None,
                    remote_media_progression_seconds: 0,
                },
                Enclosure {
                    id: 201,
                    article_id: 2,
                    url: "https://cdn.test/201.mp3".into(),
                    mime_type: "audio/mpeg".into(),
                    size_bytes: None,
                    remote_media_progression_seconds: 0,
                },
            ])
            .unwrap();
        {
            let mut snapshot = source.snapshot.lock().unwrap();
            snapshot.articles.retain(|article| article.id == 1);
            snapshot.enclosures.clear();
        }

        core.sync(SyncReason::Manual).unwrap();

        assert!(!core.store.enclosure(101).unwrap().unwrap().remote_present);
        assert!(core.store.enclosure(201).unwrap().unwrap().remote_present);
    }
    #[test]
    fn sync_retention_preserves_old_unread_and_starred_local_articles() {
        let temp = TempDir::new().unwrap();
        let mut remote = snapshot();
        let old = (Utc::now() - ChronoDuration::days(91)).to_rfc3339();
        remote.articles = vec![
            article(5, 10, old.clone(), false, false),
            article(6, 10, old.clone(), true, true),
        ];
        let (core, _) = core(&temp, remote.clone());
        core.store
            .reconcile(
                &remote.categories,
                &remote.feeds,
                &[
                    article(4, 10, old.clone(), true, false),
                    article(5, 10, old.clone(), false, false),
                    article(6, 10, old, true, true),
                ],
            )
            .unwrap();

        core.sync(SyncReason::Manual).unwrap();

        assert_eq!(
            core.query_articles(ArticleQuery {
                limit: 0,
                ..Default::default()
            })
            .unwrap()
            .iter()
            .map(|article| article.id)
            .collect::<Vec<_>>(),
            vec![6, 5]
        );
    }
    #[test]
    fn cancellable_sync_returns_cancelled_before_core_work_starts() {
        let temp = TempDir::new().unwrap();
        let (core, source) = core(&temp, snapshot());
        let cancellation = SyncCancellation::new();
        cancellation.cancel();

        assert_eq!(
            core.sync_cancellable(SyncReason::Manual, &cancellation)
                .unwrap(),
            SyncOutcome::Cancelled
        );
        assert_eq!(source.calls.load(Ordering::SeqCst), 0);
        assert!(core.last_successful_sync_at().unwrap().is_none());
    }

    #[test]
    fn cancellable_sync_finishes_remote_mutation_ack_before_stopping() {
        let temp = TempDir::new().unwrap();
        let cancellation = SyncCancellation::new();
        let source = Arc::new(CancellingMutationSource {
            snapshot: snapshot(),
            cancellation: cancellation.clone(),
            mutation_calls: AtomicUsize::new(0),
            fetch_calls: AtomicUsize::new(0),
        });
        let core = Arc::new(FluxCore::with_remote(config(&temp), source.clone()).unwrap());
        core.sync(SyncReason::Manual).unwrap();
        let successful_sync_before_cancel = core.last_successful_sync_at().unwrap();
        let fetch_calls_before_cancel = source.fetch_calls.load(Ordering::SeqCst);

        core.set_delivery_mode(DeliveryMode::Deferred).unwrap();
        core.set_read_state(1, true).unwrap();
        core.set_starred_state(3, true).unwrap();

        assert_eq!(
            core.sync_cancellable(SyncReason::Manual, &cancellation)
                .unwrap(),
            SyncOutcome::Cancelled
        );
        assert_eq!(source.mutation_calls.load(Ordering::SeqCst), 1);
        assert_eq!(
            source.fetch_calls.load(Ordering::SeqCst),
            fetch_calls_before_cancel
        );
        assert_eq!(core.store.pending_mutations().unwrap().len(), 1);
        assert_eq!(
            core.last_successful_sync_at().unwrap(),
            successful_sync_before_cancel
        );
    }

    #[test]
    fn cancellable_sync_stops_after_current_remote_fetch_before_reconciliation() {
        let temp = TempDir::new().unwrap();
        let cancellation = SyncCancellation::new();
        let source = Arc::new(CancellingFetchSource {
            snapshot: snapshot(),
            cancellation: cancellation.clone(),
            fetch_calls: AtomicUsize::new(0),
        });
        let core = Arc::new(FluxCore::with_remote(config(&temp), source.clone()).unwrap());

        assert_eq!(
            core.sync_cancellable(SyncReason::Manual, &cancellation)
                .unwrap(),
            SyncOutcome::Cancelled
        );
        assert_eq!(source.fetch_calls.load(Ordering::SeqCst), 1);
        assert!(
            core.query_articles(ArticleQuery::default())
                .unwrap()
                .is_empty()
        );
        assert!(core.last_successful_sync_at().unwrap().is_none());
    }

    #[test]
    fn cancellable_sync_preserves_completed_metadata_when_not_cancelled() {
        let temp = TempDir::new().unwrap();
        let (core, source) = core(&temp, snapshot());
        let cancellation = SyncCancellation::new();

        let outcome = core
            .sync_cancellable(SyncReason::Manual, &cancellation)
            .unwrap();
        let SyncOutcome::Completed(metadata) = outcome else {
            panic!("non-cancelled Sync must complete normally");
        };
        assert_eq!(metadata.reason, SyncReason::Manual);
        assert_eq!(source.calls.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn concurrent_syncs_are_serialized_while_queries_remain_safe() {
        let temp = TempDir::new().unwrap();
        let source = Arc::new(Source {
            snapshot: snapshot(),
            calls: AtomicUsize::new(0),
            delay: Duration::from_millis(80),
        });
        let core = Arc::new(FluxCore::with_remote(config(&temp), source.clone()).unwrap());
        let a = {
            let core = core.clone();
            thread::spawn(move || core.sync(SyncReason::Manual).unwrap())
        };
        let b = {
            let core = core.clone();
            thread::spawn(move || core.sync(SyncReason::Manual).unwrap())
        };
        for _ in 0..5 {
            core.query_articles(ArticleQuery::default()).unwrap();
        }
        a.join().unwrap();
        b.join().unwrap();
        assert_eq!(source.calls.load(Ordering::SeqCst), 2);
    }
    #[test]
    fn sync_serialization_waits_and_preserves_each_reason() {
        let temp = TempDir::new().unwrap();
        let (started_tx, started_rx) = std::sync::mpsc::channel();
        let (release_tx, release_rx) = std::sync::mpsc::channel();
        let source = Arc::new(ControlledSyncSource {
            snapshot: snapshot(),
            calls: AtomicUsize::new(0),
            fail_first: false,
            started: started_tx,
            release: Mutex::new(release_rx),
        });
        let core = Arc::new(FluxCore::with_remote(config(&temp), source.clone()).unwrap());
        let first = {
            let core = core.clone();
            thread::spawn(move || core.sync(SyncReason::Periodic).unwrap())
        };
        started_rx.recv().unwrap();
        let second = {
            let core = core.clone();
            thread::spawn(move || core.sync(SyncReason::Manual).unwrap())
        };
        assert!(started_rx.try_recv().is_err());
        release_tx.send(()).unwrap();
        started_rx.recv().unwrap();
        release_tx.send(()).unwrap();
        assert_eq!(first.join().unwrap().reason, SyncReason::Periodic);
        assert_eq!(second.join().unwrap().reason, SyncReason::Manual);
        assert_eq!(source.calls.load(Ordering::SeqCst), 2);
    }
    #[test]
    fn failed_sync_releases_serialization_for_the_next_request() {
        let temp = TempDir::new().unwrap();
        let (started_tx, started_rx) = std::sync::mpsc::channel();
        let (release_tx, release_rx) = std::sync::mpsc::channel();
        let source = Arc::new(ControlledSyncSource {
            snapshot: snapshot(),
            calls: AtomicUsize::new(0),
            fail_first: true,
            started: started_tx,
            release: Mutex::new(release_rx),
        });
        let core = Arc::new(FluxCore::with_remote(config(&temp), source.clone()).unwrap());
        let first = {
            let core = core.clone();
            thread::spawn(move || core.sync(SyncReason::Periodic))
        };
        started_rx.recv().unwrap();
        let second = {
            let core = core.clone();
            thread::spawn(move || core.sync(SyncReason::Manual))
        };
        release_tx.send(()).unwrap();
        assert!(first.join().unwrap().is_err());
        started_rx.recv().unwrap();
        release_tx.send(()).unwrap();
        assert_eq!(second.join().unwrap().unwrap().reason, SyncReason::Manual);
        assert_eq!(source.calls.load(Ordering::SeqCst), 2);
    }
    #[test]
    fn notification_preferences_candidates_and_acknowledgement_are_durable() {
        let temp = TempDir::new().unwrap();
        let (core, source) = mutation_core(&temp);
        assert!(
            core.feed_system_notification_settings()
                .unwrap()
                .iter()
                .all(|setting| !setting.system_notifications_enabled)
        );
        core.set_feed_system_notifications_enabled(10, true)
            .unwrap();
        source.snapshot.lock().unwrap().articles.extend([
            article(4, 10, Utc::now().to_rfc3339(), false, false),
            article(5, 10, Utc::now().to_rfc3339(), false, false),
            article(6, 20, Utc::now().to_rfc3339(), false, false),
        ]);
        let result = core.sync(SyncReason::Periodic).unwrap();
        assert_eq!(
            result.new_articles_by_feed,
            vec![
                NewArticlesByFeed {
                    feed_id: 10,
                    count: 2
                },
                NewArticlesByFeed {
                    feed_id: 20,
                    count: 1
                }
            ]
        );
        assert_eq!(result.system_notification_candidates.len(), 1);
        let candidate = result.system_notification_candidates[0].clone();
        assert_eq!(
            (
                candidate.feed_id,
                candidate.feed_title.as_str(),
                candidate.new_count
            ),
            (10, "Feed A", 2)
        );
        source.snapshot.lock().unwrap().articles.push(article(
            7,
            10,
            Utc::now().to_rfc3339(),
            false,
            false,
        ));
        let retry = core.sync(SyncReason::Periodic).unwrap();
        assert_eq!(retry.system_notification_candidates[0].new_count, 3);
        core.acknowledge_system_notification(candidate.candidate_id)
            .unwrap();
        core.acknowledge_system_notification(candidate.candidate_id)
            .unwrap();
        let after_ack = core.sync(SyncReason::Periodic).unwrap();
        assert_eq!(after_ack.system_notification_candidates.len(), 1);
        assert_eq!(after_ack.system_notification_candidates[0].new_count, 1);
        source.snapshot.lock().unwrap().articles[0].title = "updated article".into();
        assert!(
            core.sync(SyncReason::Manual)
                .unwrap()
                .new_articles_by_feed
                .is_empty()
        );
        core.set_read_state(1, true).unwrap();
        assert!(
            core.sync(SyncReason::Manual)
                .unwrap()
                .new_articles_by_feed
                .is_empty()
        );
        drop(core);
        let mut same_server_new_key = config(&temp);
        same_server_new_key.api_key = "replacement-secret".into();
        let reopened = FluxCore::with_remote(same_server_new_key, source.clone()).unwrap();
        assert!(
            reopened
                .feed_system_notification_settings()
                .unwrap()
                .iter()
                .find(|setting| setting.feed_id == 10)
                .unwrap()
                .system_notifications_enabled
        );
        assert_eq!(
            reopened
                .sync(SyncReason::Periodic)
                .unwrap()
                .system_notification_candidates[0]
                .new_count,
            1
        );
        drop(reopened);
        let mut changed_server = config(&temp);
        changed_server.base_url = "https://other-miniflux.example".into();
        let changed_server = FluxCore::with_remote(changed_server, source).unwrap();
        assert!(
            changed_server
                .feed_system_notification_settings()
                .unwrap()
                .is_empty()
        );
    }
    #[test]
    fn non_eligible_sync_reports_new_articles_without_creating_notification_backlog() {
        let temp = TempDir::new().unwrap();
        let (core, source) = mutation_core(&temp);
        core.set_feed_system_notifications_enabled(10, true)
            .unwrap();
        source.snapshot.lock().unwrap().articles.push(article(
            4,
            10,
            Utc::now().to_rfc3339(),
            false,
            false,
        ));
        let app_start = core.sync(SyncReason::AppStart).unwrap();
        assert_eq!(
            app_start.new_articles_by_feed,
            vec![NewArticlesByFeed {
                feed_id: 10,
                count: 1
            }]
        );
        assert!(app_start.system_notification_candidates.is_empty());
        assert!(
            core.sync(SyncReason::Periodic)
                .unwrap()
                .system_notification_candidates
                .is_empty()
        );
    }
    #[test]
    fn local_read_star_and_deduplicated_bulk_mutations_are_effective_and_durable() {
        let temp = TempDir::new().unwrap();
        let (core, _) = mutation_core(&temp);
        core.set_read_state_bulk(&[1, 1, 3], true).unwrap();
        core.set_starred_state(1, true).unwrap();
        core.set_starred_state(2, false).unwrap();
        let rows = core
            .query_articles(ArticleQuery {
                limit: 0,
                ..Default::default()
            })
            .unwrap();
        assert!(rows.iter().find(|a| a.id == 1).unwrap().is_read);
        assert!(rows.iter().find(|a| a.id == 1).unwrap().is_starred);
        assert!(!rows.iter().find(|a| a.id == 2).unwrap().is_starred);
        drop(core);
        let source = Arc::new(MutationSource {
            snapshot: Mutex::new(snapshot()),
            read_calls: AtomicUsize::new(0),
            star_calls: AtomicUsize::new(0),
            fetch_calls: AtomicUsize::new(0),
            failure: Mutex::new(None),
            log: Mutex::new(vec![]),
            delay: Mutex::new(Duration::ZERO),
        });
        let reopened = FluxCore::with_remote(config(&temp), source).unwrap();
        assert!(
            reopened
                .query_articles(ArticleQuery {
                    limit: 0,
                    ..Default::default()
                })
                .unwrap()
                .iter()
                .find(|a| a.id == 1)
                .unwrap()
                .is_read
        );
    }
    #[test]
    fn live_delivery_acknowledges_and_transient_failure_uses_backoff() {
        let temp = TempDir::new().unwrap();
        let (core, source) = mutation_core(&temp);
        core.set_delivery_mode(DeliveryMode::Live).unwrap();
        assert_eq!(
            core.set_read_state(1, true).unwrap().disposition,
            DeliveryDisposition::Delivered
        );
        assert_eq!(source.read_calls.load(Ordering::SeqCst), 1);
        *source.failure.lock().unwrap() = Some(CoreError::connectivity("offline"));
        assert_eq!(
            core.set_read_state(1, false).unwrap().disposition,
            DeliveryDisposition::Queued
        );
        assert_eq!(
            core.delivery_health().unwrap(),
            RuntimeHealth::ConnectivityDegraded
        );
        core.set_read_state(1, true).unwrap();
        assert_eq!(source.read_calls.load(Ordering::SeqCst), 2);
        *source.failure.lock().unwrap() = None;
        core.sync(SyncReason::Manual).unwrap();
        assert_eq!(source.read_calls.load(Ordering::SeqCst), 3);
    }
    #[test]
    fn periodic_sync_delivers_deferred_mutations_and_respects_backoff() {
        let temp = TempDir::new().unwrap();
        let (core, source) = mutation_core(&temp);
        core.set_read_state(1, true).unwrap();
        core.sync(SyncReason::Periodic).unwrap();
        assert_eq!(*source.log.lock().unwrap(), vec!["read", "fetch"]);

        source.log.lock().unwrap().clear();
        *source.failure.lock().unwrap() = Some(CoreError::connectivity("offline"));
        core.set_delivery_mode(DeliveryMode::Live).unwrap();
        core.set_read_state(1, false).unwrap();
        assert_eq!(source.read_calls.load(Ordering::SeqCst), 2);

        *source.failure.lock().unwrap() = None;
        core.sync(SyncReason::Periodic).unwrap();
        assert_eq!(source.read_calls.load(Ordering::SeqCst), 2);
        assert_eq!(*source.log.lock().unwrap(), vec!["read"]);
        core.sync(SyncReason::Manual).unwrap();
        assert_eq!(source.read_calls.load(Ordering::SeqCst), 3);
    }
    #[test]
    fn stale_delivery_acknowledgement_cannot_overwrite_newer_intent() {
        let temp = TempDir::new().unwrap();
        let (core, source) = mutation_core(&temp);
        *source.delay.lock().unwrap() = Duration::from_millis(80);
        core.set_delivery_mode(DeliveryMode::Live).unwrap();
        let first = {
            let core = core.clone();
            thread::spawn(move || core.set_read_state(1, true).unwrap())
        };
        thread::sleep(Duration::from_millis(20));
        core.set_delivery_mode(DeliveryMode::Deferred).unwrap();
        core.set_read_state(1, false).unwrap();
        first.join().unwrap();
        assert!(
            !core
                .query_articles(ArticleQuery {
                    limit: 0,
                    ..Default::default()
                })
                .unwrap()
                .iter()
                .find(|a| a.id == 1)
                .unwrap()
                .is_read
        );
    }
    #[test]
    fn sync_delivers_before_fetch_and_aborts_fetch_on_delivery_failure() {
        let temp = TempDir::new().unwrap();
        let (core, source) = mutation_core(&temp);
        core.set_read_state(1, true).unwrap();
        core.sync(SyncReason::Manual).unwrap();
        assert_eq!(*source.log.lock().unwrap(), vec!["read", "fetch"]);
        core.set_read_state(1, false).unwrap();
        source.log.lock().unwrap().clear();
        *source.failure.lock().unwrap() = Some(CoreError::server_transient("down"));
        assert!(core.sync(SyncReason::Manual).is_err());
        assert_eq!(*source.log.lock().unwrap(), vec!["read"]);
    }
    #[test]
    fn events_are_advisory_and_listener_callbacks_can_query_safely() {
        let temp = TempDir::new().unwrap();
        let (core, _) = mutation_core(&temp);
        core.set_read_state(1, true).unwrap(); // No listener must not affect durable state.
        let listener = Arc::new(ReentrantListener {
            core: Mutex::new(Some(core.clone())),
            events: Mutex::new(vec![]),
        });
        let id = core.subscribe_events(listener.clone()).unwrap();
        core.set_starred_state(1, true).unwrap();
        core.unsubscribe_events(id).unwrap();
        assert!(listener.events.lock().unwrap().iter().any(|event| matches!(
            event,
            CoreEvent::ArticleStarredStateChanged {
                article_id: 1,
                starred: true
            }
        )));
    }
    #[test]
    fn reconciliation_preserves_pending_intent_and_accepts_unconflicted_remote_state() {
        let temp = TempDir::new().unwrap();
        let (core, source) = mutation_core(&temp);
        core.set_delivery_mode(DeliveryMode::Live).unwrap();
        *source.failure.lock().unwrap() = Some(CoreError::connectivity("offline"));
        core.set_read_state(1, true).unwrap();
        source
            .snapshot
            .lock()
            .unwrap()
            .articles
            .iter_mut()
            .find(|a| a.id == 1)
            .unwrap()
            .is_read = false;
        core.sync(SyncReason::Background).unwrap();
        assert!(
            core.query_articles(ArticleQuery {
                limit: 0,
                ..Default::default()
            })
            .unwrap()
            .iter()
            .find(|a| a.id == 1)
            .unwrap()
            .is_read
        );
        *source.failure.lock().unwrap() = None;
        core.sync(SyncReason::Manual).unwrap();
        source
            .snapshot
            .lock()
            .unwrap()
            .articles
            .iter_mut()
            .find(|a| a.id == 1)
            .unwrap()
            .is_read = false;
        core.sync(SyncReason::Manual).unwrap();
        assert!(
            !core
                .query_articles(ArticleQuery {
                    limit: 0,
                    ..Default::default()
                })
                .unwrap()
                .iter()
                .find(|a| a.id == 1)
                .unwrap()
                .is_read
        );
    }
    #[test]
    fn navigation_catalog_is_complete_and_counts_use_effective_state() {
        let temp = TempDir::new().unwrap();
        let (core, _) = mutation_core(&temp);
        let catalog = core.navigation_catalog().unwrap();
        assert_eq!(catalog.categories.len(), 2);
        assert_eq!(
            catalog.feeds.iter().map(|feed| feed.id).collect::<Vec<_>>(),
            vec![10, 20]
        );
        assert_eq!(
            core.count_articles(ArticleQuery {
                limit: 1,
                ..Default::default()
            })
            .unwrap(),
            3
        );
        assert_eq!(
            core.count_articles(ArticleQuery {
                scope: ArticleScope::Category(1),
                read_filter: ReadFilter::Unread,
                limit: 0,
                ..Default::default()
            })
            .unwrap(),
            1
        );
        assert_eq!(
            core.count_articles(ArticleQuery {
                scope: ArticleScope::Feed(10),
                starred_filter: StarredFilter::Starred,
                limit: 0,
                ..Default::default()
            })
            .unwrap(),
            1
        );
        core.set_read_state_bulk(&[1, 1], true).unwrap();
        assert_eq!(
            core.count_articles(ArticleQuery {
                read_filter: ReadFilter::Unread,
                limit: 0,
                ..Default::default()
            })
            .unwrap(),
            0
        );
        core.set_read_state_bulk(&[1], false).unwrap();
        assert_eq!(
            core.count_articles(ArticleQuery {
                read_filter: ReadFilter::Unread,
                limit: 0,
                ..Default::default()
            })
            .unwrap(),
            1
        );
    }
    #[test]
    fn navigation_projection_tracks_local_read_and_starred_mutations() {
        let temp = TempDir::new().unwrap();
        let (core, _) = mutation_core(&temp);

        let initial = core
            .navigation_projection(NavigationCountMode::Unread)
            .unwrap();
        assert_eq!(initial.catalog.categories.len(), 2);
        assert_eq!(initial.catalog.feeds.len(), 2);
        assert_eq!(initial.unread_total, 1);
        assert_eq!(initial.starred_total, 1);
        assert_eq!(
            initial.category_counts,
            vec![
                NavigationScopedCount { id: 1, count: 1 },
                NavigationScopedCount { id: 2, count: 0 },
            ]
        );
        assert_eq!(
            initial.feed_counts,
            vec![
                NavigationScopedCount { id: 10, count: 1 },
                NavigationScopedCount { id: 20, count: 0 },
            ]
        );

        core.set_read_state(1, true).unwrap();
        core.set_starred_state(3, true).unwrap();
        let after_mutations = core
            .navigation_projection(NavigationCountMode::All)
            .unwrap();
        assert_eq!(after_mutations.unread_total, 0);
        assert_eq!(after_mutations.starred_total, 2);
        assert_eq!(
            after_mutations.category_counts,
            vec![
                NavigationScopedCount { id: 1, count: 2 },
                NavigationScopedCount { id: 2, count: 1 },
            ]
        );
        assert_eq!(
            after_mutations.feed_counts,
            vec![
                NavigationScopedCount { id: 10, count: 2 },
                NavigationScopedCount { id: 20, count: 1 },
            ]
        );
    }
    #[test]
    fn navigation_projection_is_empty_before_the_first_sync() {
        let temp = TempDir::new().unwrap();
        let (core, _) = core(&temp, snapshot());
        assert_eq!(
            core.navigation_projection(NavigationCountMode::Unread)
                .unwrap(),
            NavigationProjection {
                catalog: NavigationCatalog {
                    categories: vec![],
                    feeds: vec![],
                },
                unread_total: 0,
                starred_total: 0,
                category_counts: vec![],
                feed_counts: vec![],
            }
        );
    }
    #[test]
    fn successful_sync_runs_full_phase_order_and_updates_sync_timestamp() {
        let temp = TempDir::new().unwrap();
        let (core, source) = phase_core(&temp);
        let before = core.last_successful_sync_at().unwrap();
        assert!(before.is_some());
        // Sleep briefly so the new timestamp will differ if updated.
        thread::sleep(Duration::from_millis(1_100));
        core.set_read_state(1, true).unwrap();
        assert_eq!(core.store.pending_mutations().unwrap().len(), 1);

        let completed = core.sync(SyncReason::Manual).unwrap();

        assert_eq!(completed.reason, SyncReason::Manual);
        assert_eq!(completed.mutations_delivered, 1);
        assert_eq!(
            *source.inner.lock().unwrap().log.lock().unwrap(),
            vec!["read", "fetch"]
        );
        assert!(core.store.pending_mutations().unwrap().is_empty());
        assert_eq!(
            core.query_articles(ArticleQuery {
                scope: ArticleScope::Feed(10),
                read_filter: ReadFilter::Unread,
                limit: 0,
                ..Default::default()
            })
            .unwrap()
            .len(),
            0
        );
        let after = core.last_successful_sync_at().unwrap();
        assert!(
            after.as_deref().unwrap() > before.as_deref().unwrap(),
            "last_successful_sync_at must advance after a successful sync"
        );
        assert_eq!(core.delivery_health().unwrap(), RuntimeHealth::Healthy);
    }

    #[test]
    fn sync_failure_after_mutation_delivery_reports_completed_phases_and_preserves_timestamp() {
        let temp = TempDir::new().unwrap();
        let (core, source) = phase_core(&temp);
        // Seed one pending mutation that will be delivered before fetch fails.
        let before = core.last_successful_sync_at().unwrap();
        assert!(before.is_some());
        core.set_read_state(1, true).unwrap();
        *source.fail_fetch.lock().unwrap() = true;
        let listener = Arc::new(ReentrantListener {
            core: Mutex::new(None),
            events: Mutex::new(vec![]),
        });
        let id = core.subscribe_events(listener.clone()).unwrap();

        let error = core.sync(SyncReason::Manual).unwrap_err();

        assert_eq!(error.kind, CoreErrorKind::Connectivity);
        assert_eq!(
            *source.inner.lock().unwrap().log.lock().unwrap(),
            vec!["read", "fetch"]
        );
        assert!(
            core.query_articles(ArticleQuery {
                scope: ArticleScope::Feed(10),
                read_filter: ReadFilter::Read,
                limit: 0,
                ..Default::default()
            })
            .unwrap()
            .iter()
            .any(|a| a.id == 1 && a.is_read),
            "delivered mutation must remain effective after fetch failure"
        );
        assert_eq!(
            core.last_successful_sync_at().unwrap(),
            before,
            "timestamp must not advance after a failed sync"
        );
        assert!(listener.events.lock().unwrap().iter().any(|event| matches!(
            event,
            CoreEvent::SyncFailed(SyncFailure {
                reason: SyncReason::Manual,
                error_kind: CoreErrorKind::Connectivity,
                mutation_delivery_completed: true,
                remote_fetch_started: true,
                remote_fetch_completed: false,
                mutations_delivered: 1,
            })
        )));
        let _ = core.unsubscribe_events(id);
    }

    #[test]
    fn search_pagination_forwards_offsets_and_does_not_auto_persist() {
        let temp = TempDir::new().unwrap();
        let (core, source) = search_core(&temp);
        let mut page_one = Vec::with_capacity(5);
        let mut page_two = Vec::with_capacity(5);
        for id in 1..=10 {
            let summary = ArticleSummary {
                id,
                feed_id: 10,
                category_id: 1,
                feed_title: "Feed A".into(),
                title: format!("Result {id}"),
                url: format!("https://example.test/{id}"),
                comments_url: String::new(),
                published_at: format!("2026-01-02T03:04:{id:02}Z"),
                is_read: false,
                is_starred: false,
                reading_time_minutes: 0,
                preview: String::new(),
                image_url: None,
            };
            if id <= 5 {
                page_one.push(summary);
            } else {
                page_two.push(summary);
            }
        }
        source.search_result.lock().unwrap().total = 10;
        source.search_result.lock().unwrap().articles = page_one.clone();
        let first = core
            .search_articles(SearchArticlesRequest {
                query: "rust".into(),
                offset: 0,
                limit: 5,
            })
            .unwrap();
        assert_eq!(first.total, 10);
        assert_eq!(
            first.articles.iter().map(|a| a.id).collect::<Vec<_>>(),
            vec![1, 2, 3, 4, 5]
        );
        source.search_result.lock().unwrap().articles = page_two;
        let second = core
            .search_articles(SearchArticlesRequest {
                query: "rust".into(),
                offset: 5,
                limit: 5,
            })
            .unwrap();
        assert_eq!(
            second.articles.iter().map(|a| a.id).collect::<Vec<_>>(),
            vec![6, 7, 8, 9, 10]
        );
        let requests = source.captured_requests.lock().unwrap();
        assert_eq!(requests.len(), 2);
        assert_eq!(
            requests
                .iter()
                .map(|r| (r.offset, r.limit))
                .collect::<Vec<_>>(),
            vec![(0, 5), (5, 5)]
        );
        assert!(
            core.query_articles(ArticleQuery {
                limit: 0,
                ..Default::default()
            })
            .unwrap()
            .is_empty(),
            "remote search results must not be persisted automatically"
        );
    }

    #[test]
    fn comments_sync_metadata_and_runtime_health_are_public_state() {
        let temp = TempDir::new().unwrap();
        let (core, source) = mutation_core(&temp);
        assert_eq!(
            core.runtime_health().unwrap().health,
            RuntimeHealth::Healthy
        );
        assert!(core.runtime_health().unwrap().next_retry_at.is_none());
        let article = core
            .query_articles(ArticleQuery {
                limit: 0,
                ..Default::default()
            })
            .unwrap()
            .into_iter()
            .next()
            .unwrap();
        assert!(article.comments_url.is_empty());
        assert!(core.last_successful_sync_at().unwrap().is_some());
        let listener = Arc::new(ReentrantListener {
            core: Mutex::new(Some(core.clone())),
            events: Mutex::new(vec![]),
        });
        let id = core.subscribe_events(listener.clone()).unwrap();
        core.sync(SyncReason::Periodic).unwrap();
        core.unsubscribe_events(id).unwrap();
        assert!(listener.events.lock().unwrap().iter().any(|event| matches!(
            event,
            CoreEvent::SyncCompleted(SyncCompleted {
                reason: SyncReason::Periodic,
                new_articles: 0,
                updated_articles: 0,
                data_changed: false,
                navigation_changed: false,
                ..
            })
        )));
        source.snapshot.lock().unwrap().articles[0].title = "updated remotely".into();
        let listener = Arc::new(ReentrantListener {
            core: Mutex::new(Some(core.clone())),
            events: Mutex::new(vec![]),
        });
        let id = core.subscribe_events(listener.clone()).unwrap();
        core.sync(SyncReason::Manual).unwrap();
        core.unsubscribe_events(id).unwrap();
        assert!(listener.events.lock().unwrap().iter().any(|event| matches!(
            event,
            CoreEvent::SyncCompleted(SyncCompleted {
                reason: SyncReason::Manual,
                new_articles: 0,
                updated_articles: 1,
                data_changed: true,
                navigation_changed: false,
                ..
            })
        )));
        *source.failure.lock().unwrap() = Some(CoreError::connectivity("offline"));
        core.set_delivery_mode(DeliveryMode::Live).unwrap();
        core.set_read_state(1, true).unwrap();
        assert!(core.runtime_health().unwrap().next_retry_at.is_some());
    }
    #[test]
    fn search_is_remote_only_and_validates_its_request() {
        let temp = TempDir::new().unwrap();
        let (core, source) = search_core(&temp);

        let result = core
            .search_articles(SearchArticlesRequest {
                query: "rust".into(),
                offset: 0,
                limit: 20,
            })
            .unwrap();
        assert_eq!(result.total, 1);
        assert_eq!(result.articles[0].id, 99);
        assert_eq!(source.search_calls.load(Ordering::SeqCst), 1);

        for request in [
            SearchArticlesRequest {
                query: " ".into(),
                offset: 0,
                limit: 1,
            },
            SearchArticlesRequest {
                query: "rust".into(),
                offset: -1,
                limit: 1,
            },
            SearchArticlesRequest {
                query: "rust".into(),
                offset: 0,
                limit: 0,
            },
        ] {
            assert_eq!(
                core.search_articles(request).unwrap_err().kind,
                CoreErrorKind::Data
            );
        }
    }

    #[test]
    fn search_reader_loads_remote_content_without_persisting_the_result() {
        let temp = TempDir::new().unwrap();
        let (core, _) = search_core(&temp);

        let result = core
            .search_articles(SearchArticlesRequest {
                query: "rust".into(),
                offset: 0,
                limit: 20,
            })
            .unwrap();

        assert_eq!(result.articles[0].id, 99);
        let document = core
            .reader_document_for_search(result.articles[0].id)
            .unwrap();
        assert!(matches!(document.blocks[0], ReaderBlock::Paragraph { .. }));
        assert!(core.reader_document(result.articles[0].id).is_err());
        assert!(
            core.query_articles(ArticleQuery {
                limit: 0,
                ..Default::default()
            })
            .unwrap()
            .is_empty()
        );
    }

    #[test]
    fn search_reader_uses_the_same_projection_as_local_reader() {
        let local_temp = TempDir::new().unwrap();
        let mut data = snapshot();
        data.articles[0].raw_html_content = "<p>Equivalent content</p>".into();
        let (local_core, _) = core(&local_temp, data);
        local_core.sync(SyncReason::Manual).unwrap();
        let local_document = local_core.reader_document(1).unwrap();

        let remote_temp = TempDir::new().unwrap();
        let (remote_core, _) = search_core(&remote_temp);
        let remote_document = remote_core.reader_document_for_search(99).unwrap();

        assert_eq!(local_document.blocks, remote_document.blocks);
        assert_eq!(
            local_document.has_simplified_content,
            remote_document.has_simplified_content
        );
        assert_eq!(local_document.was_truncated, remote_document.was_truncated);
    }

    #[test]
    fn search_reader_reports_missing_remote_articles() {
        let temp = TempDir::new().unwrap();
        let (core, _) = search_core(&temp);

        assert_eq!(
            core.reader_document_for_search(100)
                .unwrap_err()
                .to_string(),
            "article 100 was not found remotely"
        );
    }

    #[test]
    fn search_overlays_all_local_read_and_starred_state_combinations() {
        let temp = TempDir::new().unwrap();
        let (core, source) = search_core(&temp);
        let mut data = snapshot();
        data.articles
            .push(article(4, 20, Utc::now().to_rfc3339(), false, true));
        core.store
            .reconcile(&data.categories, &data.feeds, &data.articles)
            .unwrap();
        source.search_result.lock().unwrap().articles = (1..=4)
            .map(|id| ArticleSummary {
                id,
                feed_id: 10,
                category_id: 1,
                feed_title: "Remote".into(),
                title: format!("Remote {id}"),
                url: format!("https://example.test/{id}"),
                comments_url: String::new(),
                published_at: "2026-01-02T03:04:05Z".into(),
                is_read: false,
                is_starred: false,
                reading_time_minutes: 0,
                preview: String::new(),
                image_url: None,
            })
            .collect();

        let result = core
            .search_articles(SearchArticlesRequest {
                query: "rust".into(),
                offset: 0,
                limit: 20,
            })
            .unwrap();

        assert_eq!(
            result
                .articles
                .iter()
                .map(|article| (article.is_read, article.is_starred))
                .collect::<Vec<_>>(),
            vec![(false, false), (true, true), (true, false), (false, true)]
        );
    }
    #[test]
    fn search_overlays_pending_star_and_unstar_state() {
        let temp = TempDir::new().unwrap();
        let (core, source) = search_core(&temp);
        let data = snapshot();
        core.store
            .reconcile(&data.categories, &data.feeds, &data.articles)
            .unwrap();
        source.search_result.lock().unwrap().articles[0].id = 1;

        assert_eq!(
            core.search_set_starred_state(1, true).unwrap(),
            SearchMutationDisposition::LocalFirst
        );
        assert!(
            core.search_articles(SearchArticlesRequest {
                query: "rust".into(),
                offset: 0,
                limit: 20,
            })
            .unwrap()
            .articles[0]
                .is_starred
        );
        assert_eq!(
            core.search_set_starred_state(1, false).unwrap(),
            SearchMutationDisposition::LocalFirst
        );
        let pending = core.store.pending_mutations().unwrap();
        assert_eq!(pending.len(), 1);
        assert_eq!(pending[0].field, MutationField::Starred);
        assert!(!pending[0].desired);
        assert!(
            !core
                .search_articles(SearchArticlesRequest {
                    query: "rust".into(),
                    offset: 0,
                    limit: 20,
                })
                .unwrap()
                .articles[0]
                .is_starred
        );
    }
    #[test]
    fn search_star_for_local_article_uses_local_first_mutation() {
        let temp = TempDir::new().unwrap();
        let (core, source) = search_core(&temp);
        let data = snapshot();
        core.store
            .reconcile(&data.categories, &data.feeds, &data.articles)
            .unwrap();

        assert_eq!(
            core.search_set_starred_state(1, true).unwrap(),
            SearchMutationDisposition::LocalFirst
        );

        assert!(
            core.query_articles(ArticleQuery {
                limit: 0,
                ..Default::default()
            })
            .unwrap()
            .iter()
            .find(|article| article.id == 1)
            .unwrap()
            .is_starred
        );
        let pending = core.store.pending_mutations().unwrap();
        assert_eq!(pending.len(), 1);
        assert_eq!(pending[0].article_id, 1);
        assert_eq!(pending[0].field, MutationField::Starred);
        assert!(pending[0].desired);
        assert_eq!(pending[0].revision, 1);
        assert_eq!(source.star_calls.load(Ordering::SeqCst), 0);
    }
    #[test]
    fn search_star_for_remote_only_article_is_direct_and_does_not_persist() {
        let temp = TempDir::new().unwrap();
        let (core, source) = search_core(&temp);

        assert_eq!(
            core.search_set_starred_state(99, true).unwrap(),
            SearchMutationDisposition::RemoteOnly
        );

        assert_eq!(source.star_calls.load(Ordering::SeqCst), 1);
        assert!(core.store.pending_mutations().unwrap().is_empty());
        assert!(
            core.query_articles(ArticleQuery {
                limit: 0,
                ..Default::default()
            })
            .unwrap()
            .is_empty()
        );
    }
    #[test]
    fn failed_remote_only_search_star_does_not_persist_state() {
        let temp = TempDir::new().unwrap();
        let (core, source) = search_core(&temp);
        *source.failure.lock().unwrap() = Some(CoreError::connectivity("offline"));

        assert!(core.search_set_starred_state(99, true).is_err());

        assert_eq!(source.star_calls.load(Ordering::SeqCst), 1);
        assert!(core.store.pending_mutations().unwrap().is_empty());
        assert!(
            core.query_articles(ArticleQuery {
                limit: 0,
                ..Default::default()
            })
            .unwrap()
            .is_empty()
        );
    }
    #[test]
    fn search_read_for_local_article_uses_local_first_mutation() {
        let temp = TempDir::new().unwrap();
        let (core, source) = search_core(&temp);
        let data = snapshot();
        core.store
            .reconcile(&data.categories, &data.feeds, &data.articles)
            .unwrap();

        assert_eq!(
            core.search_set_read_state(1, true).unwrap(),
            SearchMutationDisposition::LocalFirst
        );

        assert!(
            core.query_articles(ArticleQuery {
                limit: 0,
                ..Default::default()
            })
            .unwrap()
            .iter()
            .find(|article| article.id == 1)
            .unwrap()
            .is_read
        );
        let pending = core.store.pending_mutations().unwrap();
        assert_eq!(pending.len(), 1);
        assert_eq!(pending[0].article_id, 1);
        assert_eq!(pending[0].field, MutationField::Read);
        assert!(pending[0].desired);
        assert_eq!(pending[0].revision, 1);
        assert_eq!(source.read_calls.load(Ordering::SeqCst), 0);
    }
    #[test]
    fn search_read_for_remote_only_article_is_direct_and_does_not_persist() {
        let temp = TempDir::new().unwrap();
        let (core, source) = search_core(&temp);

        assert_eq!(
            core.search_set_read_state(99, true).unwrap(),
            SearchMutationDisposition::RemoteOnly
        );

        assert_eq!(source.read_calls.load(Ordering::SeqCst), 1);
        assert!(core.store.pending_mutations().unwrap().is_empty());
        assert!(
            core.query_articles(ArticleQuery {
                limit: 0,
                ..Default::default()
            })
            .unwrap()
            .is_empty()
        );
    }

    #[test]
    fn rebuild_discards_synchronized_state_and_pending_mutations_but_preserves_configuration() {
        let temp = TempDir::new().unwrap();
        let (core, source) = mutation_core(&temp);
        core.set_retention(ReadArticleRetention::Days365).unwrap();
        core.set_background_sync_enabled(false).unwrap();
        core.set_detail_character_limit(20_000).unwrap();
        core.set_feed_system_notifications_enabled(10, true)
            .unwrap();
        core.set_feed_detail_rendering(10, DetailRenderingMode::TextOnly)
            .unwrap();
        core.set_feed_truncate_detail(10, true).unwrap();
        core.set_feed_open_in_miniflux(10, true).unwrap();
        let settings = core.core_settings().unwrap();
        let preferences = core.feed_preferences(10).unwrap();
        core.set_read_state(1, true).unwrap();
        assert_eq!(core.store.pending_mutations().unwrap().len(), 1);
        source.log.lock().unwrap().clear();

        let completed = core.rebuild_local_state().unwrap();

        assert_eq!(completed.reason, SyncReason::Manual);
        assert_eq!(completed.mutations_delivered, 0);
        assert_eq!(*source.log.lock().unwrap(), vec!["fetch"]);
        assert_eq!(core.core_settings().unwrap(), settings);
        assert_eq!(core.feed_preferences(10).unwrap(), preferences);
        assert!(core.store.pending_mutations().unwrap().is_empty());
        assert!(
            !core
                .query_articles(ArticleQuery {
                    limit: 0,
                    ..Default::default()
                })
                .unwrap()
                .iter()
                .find(|article| article.id == 1)
                .unwrap()
                .is_read
        );
        assert!(core.last_successful_sync_at().unwrap().is_some());
    }

    #[test]
    fn rebuild_failure_leaves_discarded_state_empty_and_later_sync_recovers() {
        let temp = TempDir::new().unwrap();
        let (core, source) = mutation_core(&temp);
        core.set_feed_open_in_miniflux(10, true).unwrap();
        let preferences = core.feed_preferences(10).unwrap();
        core.set_read_state(1, true).unwrap();
        *source.failure.lock().unwrap() = Some(CoreError::connectivity("offline"));

        assert!(core.rebuild_local_state().is_err());

        assert!(
            core.query_articles(ArticleQuery {
                limit: 0,
                ..Default::default()
            })
            .unwrap()
            .is_empty()
        );
        assert!(core.store.pending_mutations().unwrap().is_empty());
        assert_eq!(core.feed_preferences(10).unwrap(), preferences);
        assert!(core.last_successful_sync_at().unwrap().is_none());
        *source.failure.lock().unwrap() = None;
        core.sync(SyncReason::Manual).unwrap();
        assert!(
            !core
                .query_articles(ArticleQuery {
                    limit: 0,
                    ..Default::default()
                })
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn full_reset_restores_fresh_core_state_without_remote_requests() {
        let temp = TempDir::new().unwrap();
        let (core, source) = mutation_core(&temp);
        core.set_retention(ReadArticleRetention::Days365).unwrap();
        core.set_delivery_mode(DeliveryMode::Live).unwrap();
        core.set_feed_system_notifications_enabled(10, true)
            .unwrap();
        core.set_read_state(1, true).unwrap();
        let fetches_before = source.fetch_calls.load(Ordering::SeqCst);
        let fresh = {
            let other = TempDir::new().unwrap();
            FluxCore::with_remote(
                config(&other),
                Arc::new(Source {
                    snapshot: snapshot(),
                    calls: AtomicUsize::new(0),
                    delay: Duration::ZERO,
                }),
            )
            .unwrap()
            .core_settings()
            .unwrap()
        };

        core.reset_core_state().unwrap();

        assert_eq!(core.core_settings().unwrap(), fresh);
        assert!(core.navigation_catalog().unwrap().feeds.is_empty());
        assert!(
            core.query_articles(ArticleQuery {
                limit: 0,
                ..Default::default()
            })
            .unwrap()
            .is_empty()
        );
        assert!(core.store.pending_mutations().unwrap().is_empty());
        assert!(core.store.base_url().unwrap().is_none());
        assert_eq!(source.fetch_calls.load(Ordering::SeqCst), fetches_before);
        assert_eq!(core.delivery_health().unwrap(), RuntimeHealth::Healthy);
    }

    #[test]
    fn widget_data_is_bounded_per_feed_with_authoritative_counts() {
        let temp = TempDir::new().unwrap();
        let now = Utc::now();
        let mut data = snapshot();
        data.articles.clear();
        for id in 1..=20 {
            data.articles.push(article(
                id,
                10,
                (now - ChronoDuration::minutes(id)).to_rfc3339(),
                false,
                id == 20,
            ));
        }
        data.articles.push(article(
            100,
            20,
            (now - ChronoDuration::days(1)).to_rfc3339(),
            false,
            false,
        ));
        data.articles.push(article(
            101,
            20,
            (now - ChronoDuration::days(2)).to_rfc3339(),
            true,
            true,
        ));
        data.articles.push(article(
            102,
            20,
            (now - ChronoDuration::days(3)).to_rfc3339(),
            true,
            false,
        ));
        let (core, _) = core(&temp, data);
        assert!(
            core.widget_data()
                .unwrap()
                .last_successful_sync_at
                .is_none()
        );
        core.sync(SyncReason::Manual).unwrap();

        let widget = core.widget_data().unwrap();
        assert_eq!(widget.categories.len(), 2);
        assert_eq!(
            widget.feeds.iter().map(|feed| feed.id).collect::<Vec<_>>(),
            [10, 20]
        );
        assert_eq!(widget.counts.all_unread, 21);
        assert_eq!(widget.counts.all_articles, 23);
        assert_eq!(widget.counts.bookmarks, 2);
        assert_eq!(widget.counts.bookmarks_unread, 1);
        assert_eq!(
            widget.counts.feed_unread,
            vec![
                WidgetScopedCount { id: 10, count: 20 },
                WidgetScopedCount { id: 20, count: 1 }
            ]
        );
        assert_eq!(
            widget.counts.feed_all,
            vec![
                WidgetScopedCount { id: 10, count: 20 },
                WidgetScopedCount { id: 20, count: 3 }
            ]
        );
        assert_eq!(
            widget.counts.category_unread,
            vec![
                WidgetScopedCount { id: 1, count: 20 },
                WidgetScopedCount { id: 2, count: 1 }
            ]
        );
        assert_eq!(
            widget.counts.category_all,
            vec![
                WidgetScopedCount { id: 1, count: 20 },
                WidgetScopedCount { id: 2, count: 3 }
            ]
        );
        let feed_ten_candidates = widget
            .articles
            .iter()
            .filter(|article| article.feed_id == 10)
            .collect::<Vec<_>>();
        assert!(feed_ten_candidates.len() <= 24);
        assert!(feed_ten_candidates.iter().any(|article| article.id == 1));
        assert!(feed_ten_candidates.iter().any(|article| article.id == 20));
        assert!(widget.articles.iter().any(|article| article.id == 100));
        assert!(
            widget
                .articles
                .iter()
                .any(|article| article.id == 101 && article.is_read && article.is_starred)
        );
        assert!(
            widget
                .articles
                .iter()
                .any(|article| article.id == 102 && article.is_read && !article.is_starred)
        );
        assert_eq!(
            widget
                .articles
                .iter()
                .filter(|article| article.id == 20)
                .count(),
            1
        );
        assert!(
            widget
                .articles
                .windows(2)
                .all(|pair| (pair[0].published_at.clone(), pair[0].id)
                    >= (pair[1].published_at.clone(), pair[1].id))
        );
        assert!(widget.last_successful_sync_at.is_some());
    }

    #[test]
    fn background_without_delta_baseline_requests_full_without_remote_fetch() {
        let temp = TempDir::new().unwrap();
        let (core, source) = core(&temp, snapshot());

        let completed = core.sync(SyncReason::Background).unwrap();

        assert_eq!(completed.reason, SyncReason::Background);
        assert!(!completed.data_changed);
        assert_eq!(source.calls.load(Ordering::SeqCst), 0);
        assert!(core.store.full_sync_required().unwrap());
        assert!(core.store.delta_sync_cursor().unwrap().is_none());
        assert!(core.last_successful_sync_at().unwrap().is_none());
    }

    #[test]
    fn disabled_background_sync_suppresses_resume_even_when_full_sync_is_due() {
        let temp = TempDir::new().unwrap();
        let (core, source) = mutation_core(&temp);
        core.set_background_sync_enabled(false).unwrap();
        core.store
            .set_last_full_sync_at_for_testing("2020-01-01 00:00:00")
            .unwrap();
        let fetches_before = source.fetch_calls.load(Ordering::SeqCst);

        let completed = core.sync(SyncReason::Resume).unwrap();

        assert_eq!(completed.reason, SyncReason::Resume);
        assert!(!completed.data_changed);
        assert_eq!(completed.mutations_delivered, 0);
        assert_eq!(source.fetch_calls.load(Ordering::SeqCst), fetches_before);
    }

    #[test]
    fn fresh_resume_is_noop_when_no_full_reconciliation_is_required() {
        let temp = TempDir::new().unwrap();
        let (core, source) = mutation_core(&temp);
        let fetches_before = source.fetch_calls.load(Ordering::SeqCst);

        let completed = core.sync(SyncReason::Resume).unwrap();

        assert_eq!(completed.reason, SyncReason::Resume);
        assert!(!completed.data_changed);
        assert_eq!(completed.mutations_delivered, 0);
        assert_eq!(source.fetch_calls.load(Ordering::SeqCst), fetches_before);
    }

    #[test]
    fn delta_skips_unknown_feed_commits_known_work_and_resume_repairs_with_full_sync() {
        let temp = TempDir::new().unwrap();
        let (core, source) = mutation_core(&temp);
        {
            let mut remote = source.snapshot.lock().unwrap();
            remote
                .articles
                .push(article(4, 10, Utc::now().to_rfc3339(), false, false));
            remote
                .articles
                .push(article(5, 99, Utc::now().to_rfc3339(), false, false));
        }

        let delta = core.sync(SyncReason::Background).unwrap();

        assert_eq!(delta.new_articles, 1);
        assert!(
            core.query_articles(ArticleQuery {
                limit: 0,
                ..Default::default()
            })
            .unwrap()
            .iter()
            .any(|article| article.id == 4)
        );
        assert!(
            !core
                .query_articles(ArticleQuery {
                    limit: 0,
                    ..Default::default()
                })
                .unwrap()
                .iter()
                .any(|article| article.id == 5)
        );
        assert!(core.store.full_sync_required().unwrap());
        assert!(core.store.delta_sync_cursor().unwrap().is_some());

        source.snapshot.lock().unwrap().feeds.push(Feed {
            id: 99,
            category_id: 1,
            title: "New Feed".into(),
        });

        let repaired = core.sync(SyncReason::Resume).unwrap();

        assert_eq!(repaired.reason, SyncReason::Resume);
        assert!(
            core.query_articles(ArticleQuery {
                limit: 0,
                ..Default::default()
            })
            .unwrap()
            .iter()
            .any(|article| article.id == 5)
        );
        assert!(!core.store.full_sync_required().unwrap());
    }

    #[test]
    fn resume_runs_full_when_last_full_sync_is_older_than_policy_even_after_fresh_delta() {
        let temp = TempDir::new().unwrap();
        let (core, source) = mutation_core(&temp);
        core.store
            .set_last_full_sync_at_for_testing("2020-01-01 00:00:00")
            .unwrap();

        core.sync(SyncReason::Background).unwrap();
        let fetches_after_delta = source.fetch_calls.load(Ordering::SeqCst);

        let resumed = core.sync(SyncReason::Resume).unwrap();

        assert_eq!(resumed.reason, SyncReason::Resume);
        assert_eq!(
            source.fetch_calls.load(Ordering::SeqCst),
            fetches_after_delta + 1
        );
        assert!(!core.store.full_sync_required().unwrap());
    }
}
