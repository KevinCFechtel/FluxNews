//! SQLite persistence. Pending rows coalesce by article/field; acknowledgement
//! deletes only the exact sent revision so later local intent always survives.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::io::Cursor;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use crate::domain::{
    Article, ArticleAudioActionProjection, ArticlePage, ArticleQuery, ArticleScope, ArticleSort,
    ArticleSummary, Category, ContinueListeningItem, CoreError, CoreSettings, DeliveryMode,
    DetailRenderingMode, DiscoveryMode, DownloadFailureKind, DownloadNetworkPolicy, DownloadOrigin,
    DownloadRetention, DownloadState, DownloadedMediaSummary, Enclosure, Feed, FeedPreferences,
    FeedPreferencesPatch, FeedSystemNotificationSetting, LegacyDownloadImportOutcome,
    LegacyFeedOpenInMinifluxImportOutcome, LegacyPlaybackImport, LegacyPlaybackImportResult,
    ListeningListEnclosure, ListeningListFeed, ListeningListItem, ListeningListSort,
    MediaArtworkSource, MediaChapter, MediaChapterSource, MediaDownload, MediaMetadata,
    MediaTransferWork, MutationField, NavigationCatalog, NavigationCountMode, NavigationProjection,
    NavigationScopedCount, PlaybackState, PlaybackStatus, ReadArticleRetention, ReadFilter,
    SavedMedia, SavedMediaMarkerState, SavedMediaSyncConfiguration, SavedPlayableMediaItem,
    StarredFilter, SystemNotificationCandidate, WidgetArticle, WidgetCounts, WidgetData,
    WidgetScopedCount,
};
use crate::media_metadata::{
    AnalyzedMedia, analyze_file, article_chapters, resolve_media_reference, to_domain_chapters,
};
use crate::miniflux::normalize_installation_base;
use chrono::Utc;
use rusqlite::{Connection, OptionalExtension, Transaction, params};
use sha2::{Digest, Sha256};

const SCHEMA_VERSION: i64 = 22;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PendingSavedMediaReplication {
    pub enclosure_id: i64,
    pub article_id: i64,
    pub desired: SavedMediaMarkerState,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SavedMediaRemoteState {
    pub enclosure_id: i64,
    pub article_id: i64,
    pub marker_entry_id: i64,
    pub state: SavedMediaMarkerState,
}

#[derive(Clone, Debug)]
pub struct PendingMutation {
    pub article_id: i64,
    pub field: MutationField,
    pub desired: bool,
    pub revision: i64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PendingMediaProgressMutation {
    pub enclosure_id: i64,
    pub progression_seconds: u64,
    pub revision: i64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct LocalArticleState {
    pub is_read: bool,
    pub is_starred: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct StoredEnclosure {
    pub enclosure: Enclosure,
    pub remote_present: bool,
}

pub(crate) struct ReaderArticle {
    pub feed_id: i64,
    pub url: String,
    pub raw_html_content: String,
    pub image_url: Option<String>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ReconciliationStats {
    pub new_articles: u32,
    pub updated_articles: u32,
    pub navigation_changed: bool,
    pub new_article_ids_by_feed: BTreeMap<i64, Vec<i64>>,
}

pub struct Store {
    connection: Mutex<Connection>,
    database_path: PathBuf,
    media_root: PathBuf,
}

impl Store {
    pub fn open(persistent_data: &Path, _cache: &Path, media: &Path) -> Result<Self, CoreError> {
        let database_path = persistent_data.join("flux.sqlite3");
        let mut connection = Connection::open(&database_path).map_err(sql_error)?;
        connection
            .busy_timeout(std::time::Duration::from_secs(5))
            .map_err(sql_error)?;
        connection
            .pragma_update(None, "foreign_keys", "ON")
            .map_err(sql_error)?;
        migrate(&mut connection)?;
        initialize_core_settings(&connection)?;
        let schema_version: i64 = connection
            .query_row("PRAGMA user_version", [], |row| row.get(0))
            .map_err(sql_error)?;
        tracing::info!(target: "storage", "storage initialized schema_version={schema_version}");
        Ok(Self {
            connection: Mutex::new(connection),
            database_path,
            media_root: media.to_path_buf(),
        })
    }
    pub fn database_path(&self) -> PathBuf {
        self.database_path.clone()
    }
    pub fn schema_version(&self) -> Result<i64, CoreError> {
        self.connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?
            .query_row("PRAGMA user_version", [], |r| r.get(0))
            .map_err(sql_error)
    }
    pub fn set_base_url(&self, base_url: &str) -> Result<(), CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let previous: Option<String> = connection
            .query_row(
                "SELECT value FROM core_settings WHERE key='base_url'",
                [],
                |row| row.get(0),
            )
            .optional()
            .map_err(sql_error)?;
        let tx = connection.transaction().map_err(sql_error)?;
        let same_installation = previous.as_deref().is_some_and(|previous| {
            normalize_installation_base(previous)
                .map(|previous| previous == base_url)
                .unwrap_or(false)
        });
        if previous.is_some() && !same_installation {
            clear_synchronized_state(&tx, true)?;
        }
        tx.execute("INSERT INTO core_settings (key, value) VALUES ('base_url', ?1) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [base_url]).map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
        Ok(())
    }
    /// Discards reconstructable synchronized state while preserving durable local media work.
    pub fn clear_synchronized_state_for_rebuild(&self) -> Result<(), CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;

        // Rebuild intentionally drops ordinary article mutation/notification bookkeeping, but
        // Phase-B media state and Phase-C Listening List membership are durable local state
        // rather than reconstructable sync state. Keep the minimal Article -> Feed -> Category
        // graph required by protecting media/listening state so Listening List, SavedMedia,
        // active/downloaded transfers and in-progress playback survive
        // the fresh authoritative sync that follows this clear.
        tx.execute_batch(
            "DELETE FROM notification_candidate_articles;
             DELETE FROM system_notification_candidates;
             DELETE FROM pending_system_notifications;
             DELETE FROM system_notified_articles;
             DELETE FROM pending_mutations;",
        )
        .map_err(sql_error)?;

        // Clearing the ordinary article mutation outbox also relinquishes those local
        // desired read/star values. Protected media Articles fall back to the last remote state
        // until the following Full Sync refreshes them.
        tx.execute(
            "UPDATE articles
             SET is_read=COALESCE(remote_is_read,is_read),
                 is_starred=COALESCE(remote_is_starred,is_starred)",
            [],
        )
        .map_err(sql_error)?;

        tx.execute(
            "DELETE FROM articles
             WHERE NOT EXISTS(
                 SELECT 1
                 FROM listening_list l
                 WHERE l.article_id=articles.id
             )
             AND NOT EXISTS(
                 SELECT 1
                 FROM saved_media s
                 JOIN enclosures e ON e.id=s.enclosure_id
                 WHERE e.article_id=articles.id
             )
             AND NOT EXISTS(
                 SELECT 1
                 FROM playback_states p
                 JOIN enclosures e ON e.id=p.enclosure_id
                 WHERE e.article_id=articles.id AND p.status='in_progress'
             )
             AND NOT EXISTS(
                 SELECT 1
                 FROM pending_media_progress_mutations m
                 JOIN enclosures e ON e.id=m.enclosure_id
                 WHERE e.article_id=articles.id
             )
             AND NOT EXISTS(
                 SELECT 1
                 FROM media_downloads d
                 JOIN enclosures e ON e.id=d.enclosure_id
                 WHERE e.article_id=articles.id AND d.state IN ('requested','downloaded')
             )",
            [],
        )
        .map_err(sql_error)?;

        // Parent rows are synchronized data too, but protected Articles still require their
        // foreign-key parents until the following Full Sync refreshes the authoritative catalog.
        tx.execute(
            "DELETE FROM feeds
             WHERE NOT EXISTS(SELECT 1 FROM articles a WHERE a.feed_id=feeds.id)",
            [],
        )
        .map_err(sql_error)?;
        tx.execute(
            "DELETE FROM categories
             WHERE NOT EXISTS(SELECT 1 FROM feeds f WHERE f.category_id=categories.id)",
            [],
        )
        .map_err(sql_error)?;

        tx.execute(
            "DELETE FROM core_settings
             WHERE key IN ('last_successful_sync_at','last_full_sync_at','delta_sync_cursor','full_sync_required','full_sync_reason')",
            [],
        )
        .map_err(sql_error)?;
        tx.commit().map_err(sql_error)
    }
    /// Restores all Core-owned persistent state to fresh-install defaults.
    pub fn reset_core_state(&self) -> Result<(), CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        clear_synchronized_state(&tx, true)?;
        tx.execute("DELETE FROM core_settings", [])
            .map_err(sql_error)?;
        for (key, value) in core_setting_defaults() {
            tx.execute(
                "INSERT INTO core_settings (key, value) VALUES (?1, ?2)",
                params![key, value],
            )
            .map_err(sql_error)?;
        }
        tx.commit().map_err(sql_error)
    }
    /// Removes the current account's local state while preserving Core settings.
    pub fn remove_account_state(&self) -> Result<(), CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        clear_synchronized_state(&tx, true)?;
        tx.execute("DELETE FROM core_settings WHERE key='base_url'", [])
            .map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;

        if self.media_root.exists() {
            for entry in std::fs::read_dir(&self.media_root)
                .map_err(|error| CoreError::persistence(format!("read media root: {error}")))?
            {
                let path = entry
                    .map_err(|error| CoreError::persistence(format!("read media entry: {error}")))?
                    .path();
                if path.is_dir() {
                    std::fs::remove_dir_all(path).map_err(|error| {
                        CoreError::persistence(format!("remove account media: {error}"))
                    })?;
                } else {
                    std::fs::remove_file(path).map_err(|error| {
                        CoreError::persistence(format!("remove account media: {error}"))
                    })?;
                }
            }
        }
        Ok(())
    }
    pub fn base_url(&self) -> Result<Option<String>, CoreError> {
        self.connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?
            .query_row(
                "SELECT value FROM core_settings WHERE key='base_url'",
                [],
                |r| r.get(0),
            )
            .optional()
            .map_err(sql_error)
    }
    pub fn core_settings(&self) -> Result<CoreSettings, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let retention = setting_value(&connection, "read_article_retention")?;
        let delivery_mode = setting_value(&connection, "delivery_mode")?;
        let background_sync_enabled = setting_value(&connection, "background_sync_enabled")?;
        let detail_character_limit = setting_value(&connection, "detail_character_limit")?;
        let download_network_policy = setting_value(&connection, "download_network_policy")?;
        let download_retention = setting_value(&connection, "download_retention")?;
        let delete_after_playback = setting_value(&connection, "delete_after_playback")?;
        let auto_download_listening_list =
            setting_value(&connection, "auto_download_listening_list")?;
        let remove_completed_listening_list =
            setting_value(&connection, "remove_completed_listening_list")?;
        Ok(CoreSettings {
            retention: ReadArticleRetention::from_days(&retention)?,
            delivery_mode: match delivery_mode.as_str() {
                "live" => DeliveryMode::Live,
                "deferred" => DeliveryMode::Deferred,
                _ => return Err(CoreError::persistence("invalid delivery mode setting")),
            },
            background_sync_enabled: match background_sync_enabled.as_str() {
                "0" => false,
                "1" => true,
                _ => return Err(CoreError::persistence("invalid background sync setting")),
            },
            detail_character_limit: detail_character_limit
                .parse()
                .map_err(|_| CoreError::persistence("invalid detail character limit setting"))?,
            download_network_policy: match download_network_policy.as_str() {
                "any_network" => DownloadNetworkPolicy::AnyNetwork,
                "unmetered_only" => DownloadNetworkPolicy::UnmeteredOnly,
                _ => {
                    return Err(CoreError::persistence(
                        "invalid download network policy setting",
                    ));
                }
            },
            download_retention: download_retention_from_db(&download_retention)?,
            delete_after_playback: match delete_after_playback.as_str() {
                "0" => false,
                "1" => true,
                _ => {
                    return Err(CoreError::persistence(
                        "invalid delete after playback setting",
                    ));
                }
            },
            auto_download_listening_list: parse_bool_setting(
                &auto_download_listening_list,
                "invalid auto-download Listening List setting",
            )?,
            remove_completed_listening_list: parse_bool_setting(
                &remove_completed_listening_list,
                "invalid remove-completed Listening List setting",
            )?,
        })
    }
    pub fn all_feed_preferences(&self) -> Result<Vec<FeedPreferences>, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let mut statement = connection
            .prepare("SELECT feed_id, system_notifications_enabled, detail_rendering, truncate_detail, open_in_miniflux, auto_download_audio FROM feed_preferences ORDER BY feed_id")
            .map_err(sql_error)?;
        statement
            .query_map([], |row| {
                Ok(FeedPreferences {
                    feed_id: row.get(0)?,
                    system_notifications_enabled: row.get(1)?,
                    detail_rendering: match row.get::<_, String>(2)?.as_str() {
                        "rendered" => DetailRenderingMode::Rendered,
                        "text_only" => DetailRenderingMode::TextOnly,
                        _ => return Err(rusqlite::Error::InvalidQuery),
                    },
                    truncate_detail: row.get(3)?,
                    open_in_miniflux: row.get(4)?,
                    auto_download_audio: row.get(5)?,
                })
            })
            .map_err(sql_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(sql_error)
    }
    /// Replaces all Core configuration and discards server-derived state in one transaction.
    pub fn replace_configuration(
        &self,
        base_url: &str,
        settings: &CoreSettings,
        preferences: &[FeedPreferences],
    ) -> Result<(), CoreError> {
        if !matches!(settings.detail_character_limit, 5_000 | 10_000 | 20_000) {
            return Err(CoreError::data("unsupported detail character limit"));
        }
        let mut ids = HashSet::with_capacity(preferences.len());
        if preferences
            .iter()
            .any(|preference| preference.feed_id <= 0 || !ids.insert(preference.feed_id))
        {
            return Err(CoreError::data(
                "feed preferences must have unique positive feed IDs",
            ));
        }
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        clear_synchronized_state(&tx, true)?;
        tx.execute("INSERT INTO core_settings (key, value) VALUES ('base_url', ?1) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [base_url]).map_err(sql_error)?;
        tx.execute("INSERT INTO core_settings (key, value) VALUES ('read_article_retention', ?1) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [settings.retention.days().to_string()]).map_err(sql_error)?;
        tx.execute("INSERT INTO core_settings (key, value) VALUES ('delivery_mode', ?1) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [match settings.delivery_mode { DeliveryMode::Live => "live", DeliveryMode::Deferred => "deferred" }]).map_err(sql_error)?;
        tx.execute("INSERT INTO core_settings (key, value) VALUES ('background_sync_enabled', ?1) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [if settings.background_sync_enabled { "1" } else { "0" }]).map_err(sql_error)?;
        tx.execute("INSERT INTO core_settings (key, value) VALUES ('background_sync_enabled_explicit', '1') ON CONFLICT(key) DO UPDATE SET value = '1'", []).map_err(sql_error)?;
        tx.execute("INSERT INTO core_settings (key, value) VALUES ('detail_character_limit', ?1) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [settings.detail_character_limit.to_string()]).map_err(sql_error)?;
        write_media_settings(&tx, settings)?;
        for preference in preferences {
            tx.execute("INSERT INTO feed_preferences(feed_id, system_notifications_enabled, detail_rendering, truncate_detail, open_in_miniflux, auto_download_audio) VALUES(?1, ?2, ?3, ?4, ?5, ?6)", params![preference.feed_id, preference.system_notifications_enabled, match preference.detail_rendering { DetailRenderingMode::Rendered => "rendered", DetailRenderingMode::TextOnly => "text_only" }, preference.truncate_detail, preference.open_in_miniflux, preference.auto_download_audio]).map_err(sql_error)?;
        }
        tx.commit().map_err(sql_error)
    }
    pub fn set_retention(&self, retention: ReadArticleRetention) -> Result<(), CoreError> {
        self.set_setting("read_article_retention", &retention.days().to_string())
    }
    pub fn set_delivery_mode(&self, mode: DeliveryMode) -> Result<(), CoreError> {
        self.set_setting(
            "delivery_mode",
            match mode {
                DeliveryMode::Live => "live",
                DeliveryMode::Deferred => "deferred",
            },
        )
    }
    pub fn set_download_network_policy(
        &self,
        policy: DownloadNetworkPolicy,
    ) -> Result<(), CoreError> {
        self.set_setting(
            "download_network_policy",
            match policy {
                DownloadNetworkPolicy::AnyNetwork => "any_network",
                DownloadNetworkPolicy::UnmeteredOnly => "unmetered_only",
            },
        )
    }
    pub fn set_download_retention(&self, retention: DownloadRetention) -> Result<(), CoreError> {
        if matches!(retention, DownloadRetention::Days(0)) {
            return Err(CoreError::data("download retention days must be positive"));
        }
        self.set_setting("download_retention", &download_retention_db(retention))
    }
    pub fn set_delete_after_playback(&self, enabled: bool) -> Result<(), CoreError> {
        self.set_setting("delete_after_playback", if enabled { "1" } else { "0" })
    }
    pub fn import_legacy_media_settings(
        &self,
        unmetered_only: Option<bool>,
        retention: Option<DownloadRetention>,
        delete_after_playback: Option<bool>,
    ) -> Result<(), CoreError> {
        if matches!(retention, Some(DownloadRetention::Days(0))) {
            return Err(CoreError::data("download retention days must be positive"));
        }
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        if let Some(unmetered_only) = unmetered_only {
            tx.execute(
                "INSERT INTO core_settings (key, value) VALUES ('download_network_policy', ?1) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                [if unmetered_only { "unmetered_only" } else { "any_network" }],
            ).map_err(sql_error)?;
        }
        if let Some(retention) = retention {
            tx.execute(
                "INSERT INTO core_settings (key, value) VALUES ('download_retention', ?1) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                [download_retention_db(retention)],
            ).map_err(sql_error)?;
        }
        if let Some(delete_after_playback) = delete_after_playback {
            tx.execute(
                "INSERT INTO core_settings (key, value) VALUES ('delete_after_playback', ?1) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                [if delete_after_playback { "1" } else { "0" }],
            ).map_err(sql_error)?;
        }
        tx.commit().map_err(sql_error)
    }
    pub fn set_auto_download_listening_list(&self, enabled: bool) -> Result<(), CoreError> {
        self.set_owned_bool_setting("auto_download_listening_list", enabled)
    }
    pub fn set_remove_completed_listening_list(&self, enabled: bool) -> Result<(), CoreError> {
        self.set_setting(
            "remove_completed_listening_list",
            if enabled { "1" } else { "0" },
        )
    }
    pub fn set_background_sync_enabled(&self, enabled: bool) -> Result<(), CoreError> {
        self.set_owned_bool_setting("background_sync_enabled", enabled)
    }
    pub fn import_legacy_policy_settings(
        &self,
        background_sync_enabled: Option<bool>,
        auto_download_listening_list: Option<bool>,
    ) -> Result<(), CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        for (key, value) in [
            ("background_sync_enabled", background_sync_enabled),
            ("auto_download_listening_list", auto_download_listening_list),
        ] {
            let ownership_key = format!("{key}_explicit");
            let explicit: String = tx
                .query_row(
                    "SELECT value FROM core_settings WHERE key = ?1",
                    [&ownership_key],
                    |row| row.get(0),
                )
                .map_err(sql_error)?;
            if explicit == "0" {
                if let Some(value) = value {
                    tx.execute(
                        "UPDATE core_settings SET value = ?1 WHERE key = ?2",
                        params![if value { "1" } else { "0" }, key],
                    )
                    .map_err(sql_error)?;
                    tx.execute(
                        "UPDATE core_settings SET value = '1' WHERE key = ?1",
                        [&ownership_key],
                    )
                    .map_err(sql_error)?;
                }
            } else if explicit != "1" {
                return Err(CoreError::persistence("invalid core setting ownership"));
            }
        }
        tx.commit().map_err(sql_error)
    }
    pub fn set_detail_character_limit(&self, limit: u32) -> Result<(), CoreError> {
        if !matches!(limit, 5_000 | 10_000 | 20_000) {
            return Err(CoreError::data("unsupported detail character limit"));
        }
        self.set_setting("detail_character_limit", &limit.to_string())
    }
    fn set_setting(&self, key: &str, value: &str) -> Result<(), CoreError> {
        self.connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?
            .execute(
                "INSERT INTO core_settings (key, value) VALUES (?1, ?2) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                params![key, value],
            )
            .map_err(sql_error)?;
        Ok(())
    }
    fn set_owned_bool_setting(&self, key: &str, enabled: bool) -> Result<(), CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        tx.execute(
            "UPDATE core_settings SET value = ?1 WHERE key = ?2",
            params![if enabled { "1" } else { "0" }, key],
        )
        .map_err(sql_error)?;
        tx.execute(
            "UPDATE core_settings SET value = '1' WHERE key = ?1",
            [format!("{key}_explicit")],
        )
        .map_err(sql_error)?;
        tx.commit().map_err(sql_error)
    }
    pub fn reconcile(
        &self,
        categories: &[Category],
        feeds: &[Feed],
        articles: &[Article],
    ) -> Result<ReconciliationStats, CoreError> {
        self.reconcile_with_enclosures(categories, feeds, articles, &[])
    }
    pub fn reconcile_with_enclosures(
        &self,
        categories: &[Category],
        feeds: &[Feed],
        articles: &[Article],
        enclosures: &[Enclosure],
    ) -> Result<ReconciliationStats, CoreError> {
        self.reconcile_with_enclosures_and_progress_mode(
            categories,
            feeds,
            articles,
            enclosures,
            &HashMap::new(),
            DiscoveryMode::Restore,
        )
    }
    pub fn reconcile_with_enclosures_and_progress(
        &self,
        categories: &[Category],
        feeds: &[Feed],
        articles: &[Article],
        enclosures: &[Enclosure],
        media_progress_writes: &HashMap<i64, u64>,
    ) -> Result<ReconciliationStats, CoreError> {
        self.reconcile_with_enclosures_and_progress_mode(
            categories,
            feeds,
            articles,
            enclosures,
            media_progress_writes,
            DiscoveryMode::Restore,
        )
    }

    pub fn reconcile_with_enclosures_and_progress_mode(
        &self,
        categories: &[Category],
        feeds: &[Feed],
        articles: &[Article],
        enclosures: &[Enclosure],
        media_progress_writes: &HashMap<i64, u64>,
        discovery_mode: DiscoveryMode,
    ) -> Result<ReconciliationStats, CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        let mut stats = ReconciliationStats::default();
        for c in categories {
            let existing = tx
                .query_row("SELECT title FROM categories WHERE id=?1", [c.id], |row| {
                    row.get::<_, String>(0)
                })
                .optional()
                .map_err(sql_error)?;
            stats.navigation_changed |= existing.as_deref() != Some(c.title.as_str());
            tx.execute("INSERT INTO categories (id,title) VALUES (?1,?2) ON CONFLICT(id) DO UPDATE SET title=excluded.title", params![c.id,c.title]).map_err(sql_error)?;
        }
        for f in feeds {
            let existing = tx
                .query_row(
                    "SELECT category_id,title FROM feeds WHERE id=?1",
                    [f.id],
                    |row| Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?)),
                )
                .optional()
                .map_err(sql_error)?;
            stats.navigation_changed |=
                existing.as_ref() != Some(&(f.category_id, f.title.clone()));
            tx.execute("INSERT INTO feeds (id,category_id,title) VALUES (?1,?2,?3) ON CONFLICT(id) DO UPDATE SET category_id=excluded.category_id,title=excluded.title", params![f.id,f.category_id,f.title]).map_err(sql_error)?;
        }
        let remote_feed_ids: HashSet<i64> = feeds.iter().map(|feed| feed.id).collect();
        let stale_feed_ids = {
            let mut statement = tx.prepare("SELECT id FROM feeds").map_err(sql_error)?;
            statement
                .query_map([], |row| row.get::<_, i64>(0))
                .map_err(sql_error)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(sql_error)?
                .into_iter()
                .filter(|feed_id| !remote_feed_ids.contains(feed_id))
                .collect::<Vec<_>>()
        };
        let removed_preference_ids = {
            let mut statement = tx
                .prepare("SELECT feed_id FROM feed_preferences")
                .map_err(sql_error)?;
            statement
                .query_map([], |row| row.get::<_, i64>(0))
                .map_err(sql_error)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(sql_error)?
                .into_iter()
                .filter(|feed_id| !remote_feed_ids.contains(feed_id))
                .collect::<Vec<_>>()
        };
        for feed_id in &stale_feed_ids {
            // Pending mutations do not cascade from articles; all notification state cascades.
            tx.execute("DELETE FROM pending_mutations WHERE article_id IN (SELECT id FROM articles WHERE feed_id=?1)", [feed_id]).map_err(sql_error)?;
            tx.execute("DELETE FROM articles WHERE feed_id=?1", [feed_id])
                .map_err(sql_error)?;
            tx.execute("DELETE FROM feeds WHERE id=?1", [feed_id])
                .map_err(sql_error)?;
        }
        for feed_id in removed_preference_ids {
            tx.execute("DELETE FROM feed_preferences WHERE feed_id=?1", [feed_id])
                .map_err(sql_error)?;
            tx.execute(
                "DELETE FROM feed_open_in_miniflux_overrides WHERE feed_id=?1",
                [feed_id],
            )
            .map_err(sql_error)?;
        }
        stats.navigation_changed |= !stale_feed_ids.is_empty();
        let remote_article_ids: HashSet<i64> = articles.iter().map(|article| article.id).collect();
        let absent_articles = {
            let mut statement = tx
                .prepare("SELECT id,remote_is_read,remote_is_starred FROM articles")
                .map_err(sql_error)?;
            statement
                .query_map([], |row| {
                    Ok((
                        row.get::<_, i64>(0)?,
                        row.get::<_, bool>(1)?,
                        row.get::<_, bool>(2)?,
                    ))
                })
                .map_err(sql_error)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(sql_error)?
        };
        // The remote snapshot is the union of unread and starred articles. An absent local
        // article is therefore remotely read and unstarred, unless local intent is pending.
        for (id, remote_is_read, remote_is_starred) in absent_articles {
            if remote_article_ids.contains(&id) {
                continue;
            }
            if !remote_is_read || remote_is_starred {
                stats.updated_articles += 1;
            }
            tx.execute("UPDATE articles SET remote_is_read=1,remote_is_starred=0,is_read=CASE WHEN EXISTS(SELECT 1 FROM pending_mutations p WHERE p.article_id=articles.id AND p.field='read') THEN is_read ELSE 1 END,is_starred=CASE WHEN EXISTS(SELECT 1 FROM pending_mutations p WHERE p.article_id=articles.id AND p.field='starred') THEN is_starred ELSE 0 END WHERE id=?1", [id]).map_err(sql_error)?;
        }
        for a in articles {
            let existing = tx
                .query_row("SELECT feed_id,title,url,comments_url,published_at,remote_is_read,remote_is_starred,raw_html_content,reading_time_minutes,preview,image_url FROM articles WHERE id=?1", [a.id], |row| Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?, row.get::<_, String>(2)?, row.get::<_, String>(3)?, row.get::<_, String>(4)?, row.get::<_, bool>(5)?, row.get::<_, bool>(6)?, row.get::<_, String>(7)?, row.get::<_, u32>(8)?, row.get::<_, String>(9)?, row.get::<_, Option<String>>(10)?)))
                .optional()
                .map_err(sql_error)?;
            match existing {
                None => {
                    stats.new_articles += 1;
                    stats
                        .new_article_ids_by_feed
                        .entry(a.feed_id)
                        .or_default()
                        .push(a.id);
                }
                Some(existing)
                    if existing
                        != (
                            a.feed_id,
                            a.title.clone(),
                            a.url.clone(),
                            a.comments_url.clone(),
                            a.published_at.clone(),
                            a.is_read,
                            a.is_starred,
                            a.raw_html_content.clone(),
                            a.reading_time_minutes,
                            a.preview.clone(),
                            a.image_url.clone(),
                        ) =>
                {
                    stats.updated_articles += 1
                }
                Some(_) => {}
            }
            tx.execute("INSERT INTO articles (id,feed_id,title,url,comments_url,published_at,is_read,is_starred,remote_is_read,remote_is_starred,raw_html_content,reading_time_minutes,preview,image_url,content_processing_version) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?7,?8,?9,?10,?11,?12,?13) ON CONFLICT(id) DO UPDATE SET feed_id=excluded.feed_id,title=excluded.title,url=excluded.url,comments_url=excluded.comments_url,published_at=excluded.published_at,remote_is_read=excluded.remote_is_read,remote_is_starred=excluded.remote_is_starred,is_read=CASE WHEN EXISTS(SELECT 1 FROM pending_mutations p WHERE p.article_id=excluded.id AND p.field='read') THEN articles.is_read ELSE excluded.is_read END,is_starred=CASE WHEN EXISTS(SELECT 1 FROM pending_mutations p WHERE p.article_id=excluded.id AND p.field='starred') THEN articles.is_starred ELSE excluded.is_starred END,raw_html_content=excluded.raw_html_content,reading_time_minutes=excluded.reading_time_minutes,preview=excluded.preview,image_url=excluded.image_url,content_processing_version=excluded.content_processing_version", params![a.id,a.feed_id,a.title,a.url,a.comments_url,a.published_at,a.is_read,a.is_starred,a.raw_html_content,a.reading_time_minutes,a.preview,a.image_url,crate::article::PROCESSING_VERSION]).map_err(sql_error)?;
        }
        let new_live_enclosures = if matches!(discovery_mode, DiscoveryMode::LiveDiscovery) {
            enclosures
                .iter()
                .filter(|enclosure| {
                    !tx.query_row(
                        "SELECT EXISTS(SELECT 1 FROM enclosures WHERE id=?1)",
                        [enclosure.id],
                        |row| row.get(0),
                    )
                    .unwrap_or(true)
                })
                .map(|enclosure| enclosure.id)
                .collect::<Vec<_>>()
        } else {
            Vec::new()
        };
        reconcile_remote_enclosures(&tx, articles, enclosures, media_progress_writes)?;
        let mut auto_download_articles = HashSet::new();
        for enclosure_id in new_live_enclosures {
            let article_id: i64 = tx
                .query_row(
                    "SELECT article_id FROM enclosures WHERE id=?1",
                    [enclosure_id],
                    |row| row.get(0),
                )
                .map_err(sql_error)?;
            let enabled: bool = tx
                .query_row(
                    "SELECT EXISTS(SELECT 1 FROM articles a JOIN feed_preferences p ON p.feed_id=a.feed_id WHERE a.id=?1 AND p.auto_download_audio=1)",
                    [article_id],
                    |row| row.get(0),
                )
                .map_err(sql_error)?;
            if enabled && is_audio_enclosure(&tx, enclosure_id)? {
                auto_download_articles.insert(article_id);
            }
        }
        for article_id in auto_download_articles {
            ensure_listening_membership(&tx, article_id, &Utc::now().to_rfc3339())?;
            for enclosure_id in audio_enclosure_ids_for_article(&tx, article_id)? {
                let suppressed: bool = tx
                    .query_row(
                        "SELECT EXISTS(SELECT 1 FROM auto_download_suppressions WHERE enclosure_id=?1)",
                        [enclosure_id],
                        |row| row.get(0),
                    )
                    .map_err(sql_error)?;
                if !suppressed {
                    request_download_in_transaction(&tx, enclosure_id, DownloadOrigin::Automatic)?;
                }
            }
        }
        let remote_category_ids: HashSet<i64> =
            categories.iter().map(|category| category.id).collect();
        let stale_category_ids = {
            let mut statement = tx.prepare("SELECT id FROM categories").map_err(sql_error)?;
            statement
                .query_map([], |row| row.get::<_, i64>(0))
                .map_err(sql_error)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(sql_error)?
                .into_iter()
                .filter(|category_id| !remote_category_ids.contains(category_id))
                .collect::<Vec<_>>()
        };
        for category_id in &stale_category_ids {
            tx.execute("DELETE FROM categories WHERE id=?1", [category_id])
                .map_err(sql_error)?;
        }
        stats.navigation_changed |= !stale_category_ids.is_empty();
        tx.commit().map_err(sql_error)?;
        Ok(stats)
    }

    /// Stores remotely observed enclosures without deciding remote-removal state.
    pub fn upsert_remote_enclosures(&self, enclosures: &[Enclosure]) -> Result<(), CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        upsert_remote_enclosures(&tx, enclosures)?;
        tx.commit().map_err(sql_error)
    }

    pub fn enclosure(&self, enclosure_id: i64) -> Result<Option<StoredEnclosure>, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        connection
            .query_row(
                "SELECT id,article_id,url,mime_type,size_bytes,remote_media_progression_seconds,remote_present FROM enclosures WHERE id=?1",
                [enclosure_id],
                stored_enclosure_from_row,
            )
            .optional()
            .map_err(sql_error)
    }

    pub fn media_transfer_work(
        &self,
        state: DownloadState,
    ) -> Result<Vec<MediaTransferWork>, CoreError> {
        let state = match state {
            DownloadState::Requested => "requested",
            DownloadState::DeleteRequested => "delete_requested",
            _ => return Ok(Vec::new()),
        };
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let mut statement = connection
            .prepare("SELECT d.enclosure_id,e.url,e.mime_type,d.origin,d.local_file FROM media_downloads d JOIN enclosures e ON e.id=d.enclosure_id WHERE d.state=?1 ORDER BY d.enclosure_id")
            .map_err(sql_error)?;
        statement
            .query_map([state], |row| {
                Ok(MediaTransferWork {
                    enclosure_id: row.get(0)?,
                    url: row.get(1)?,
                    mime_type: row.get(2)?,
                    origin: origin_from_db(&row.get::<_, String>(3)?)?,
                    local_file: row.get(4)?,
                })
            })
            .map_err(sql_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(sql_error)
    }

    pub fn enclosures_for_article(
        &self,
        article_id: i64,
    ) -> Result<Vec<StoredEnclosure>, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let mut statement = connection
            .prepare("SELECT id,article_id,url,mime_type,size_bytes,remote_media_progression_seconds,remote_present FROM enclosures WHERE article_id=?1 ORDER BY id")
            .map_err(sql_error)?;
        statement
            .query_map([article_id], stored_enclosure_from_row)
            .map_err(sql_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(sql_error)
    }

    pub fn article_presentation(&self, article_id: i64) -> Result<(String, String), CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        connection
            .query_row(
                "SELECT a.title,f.title FROM articles a JOIN feeds f ON f.id=a.feed_id WHERE a.id=?1",
                [article_id],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .map_err(sql_error)
    }

    pub fn article_audio_action_states(
        &self,
        article_ids: &[i64],
    ) -> Result<Vec<ArticleAudioActionProjection>, CoreError> {
        if article_ids.is_empty() {
            return Ok(Vec::new());
        }
        let placeholders = std::iter::repeat_n("?", article_ids.len())
            .collect::<Vec<_>>()
            .join(",");
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let mut statement = connection
            .prepare(&format!(
                "SELECT e.article_id,e.id,e.url,e.mime_type,e.size_bytes,e.remote_media_progression_seconds,EXISTS(SELECT 1 FROM listening_list l WHERE l.article_id=e.article_id),d.enclosure_id,d.state,d.origin,d.local_file,d.file_size_bytes,d.downloaded_at,d.failure_kind FROM enclosures e LEFT JOIN media_downloads d ON d.enclosure_id=e.id WHERE e.article_id IN ({placeholders}) AND lower(e.mime_type) LIKE 'audio/%' ORDER BY e.article_id,e.id"
            ))
            .map_err(sql_error)?;
        let mut states = HashMap::new();
        let rows = statement
            .query_map(rusqlite::params_from_iter(article_ids.iter()), |row| {
                let article_id: i64 = row.get(0)?;
                let enclosure = Enclosure {
                    id: row.get(1)?,
                    article_id,
                    url: row.get(2)?,
                    mime_type: row.get(3)?,
                    size_bytes: row
                        .get::<_, Option<i64>>(4)?
                        .map(|value| {
                            u64::try_from(value).map_err(|_| rusqlite::Error::InvalidQuery)
                        })
                        .transpose()?,
                    remote_media_progression_seconds: u64::try_from(row.get::<_, i64>(5)?)
                        .map_err(|_| rusqlite::Error::InvalidQuery)?,
                };
                let state =
                    states
                        .entry(article_id)
                        .or_insert_with(|| ArticleAudioActionProjection {
                            article_id,
                            enclosures: Vec::new(),
                            is_in_listening_list: row.get(6).unwrap_or(false),
                            downloads: Vec::new(),
                        });
                state.enclosures.push(enclosure);
                if let Some(enclosure_id) = row.get::<_, Option<i64>>(7)? {
                    let download_state = download_state_from_db(&row.get::<_, String>(8)?)?;
                    let origin = row
                        .get::<_, Option<String>>(9)?
                        .map(|value| origin_from_db(&value))
                        .transpose()?;
                    let failure_kind = row
                        .get::<_, Option<String>>(13)?
                        .map(|value| failure_kind_from_db(&value))
                        .transpose()?;
                    state.downloads.push(MediaDownload {
                        enclosure_id,
                        state: download_state,
                        origin,
                        local_file: row.get(10)?,
                        file_size_bytes: row
                            .get::<_, Option<i64>>(11)?
                            .map(|value| {
                                u64::try_from(value).map_err(|_| rusqlite::Error::InvalidQuery)
                            })
                            .transpose()?,
                        downloaded_at: row.get(12)?,
                        failure_kind,
                    });
                }
                Ok(())
            })
            .map_err(sql_error)?;
        for row in rows {
            row.map_err(sql_error)?;
        }
        Ok(article_ids
            .iter()
            .filter_map(|article_id| states.remove(article_id))
            .collect())
    }

    pub fn add_to_listening_list(
        &self,
        article_id: i64,
        added_at: &str,
    ) -> Result<bool, CoreError> {
        self.add_to_listening_list_with_policy(article_id, added_at, false)
    }

    pub fn add_to_listening_list_with_policy(
        &self,
        article_id: i64,
        added_at: &str,
        auto_download: bool,
    ) -> Result<bool, CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        let article_exists: bool = tx
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM articles WHERE id=?1)",
                [article_id],
                |row| row.get(0),
            )
            .map_err(sql_error)?;
        if !article_exists {
            return Err(CoreError::data(format!(
                "article {article_id} does not exist"
            )));
        }
        let audio_ids = audio_enclosure_ids_for_article(&tx, article_id)?;
        if audio_ids.is_empty() {
            return Err(CoreError::data(
                "article must have at least one audio enclosure",
            ));
        }
        let inserted = tx
            .execute(
                "INSERT INTO listening_list(article_id,added_at) VALUES(?1,?2) ON CONFLICT(article_id) DO NOTHING",
                params![article_id, added_at],
            )
            .map_err(sql_error)?
            > 0;
        if auto_download && inserted {
            for enclosure_id in audio_ids {
                request_download_in_transaction(&tx, enclosure_id, DownloadOrigin::Automatic)?;
            }
        }
        tx.commit().map_err(sql_error)?;
        Ok(inserted)
    }

    pub fn remove_from_listening_list(&self, article_id: i64) -> Result<bool, CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        let removed = tx
            .execute(
                "DELETE FROM listening_list WHERE article_id=?1",
                [article_id],
            )
            .map_err(sql_error)?
            > 0;
        if removed {
            for enclosure_id in audio_enclosure_ids_for_article(&tx, article_id)? {
                request_download_deletion_in_transaction(&tx, enclosure_id)?;
            }
        }
        tx.commit().map_err(sql_error)?;
        Ok(removed)
    }

    pub fn is_in_listening_list(&self, article_id: i64) -> Result<bool, CoreError> {
        self.connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM listening_list WHERE article_id=?1)",
                [article_id],
                |row| row.get(0),
            )
            .map_err(sql_error)
    }

    pub fn listening_list(
        &self,
        feed_id: Option<i64>,
        sort: ListeningListSort,
    ) -> Result<Vec<ListeningListItem>, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let order = match sort {
            ListeningListSort::RecentlyAdded => "l.added_at DESC,l.article_id DESC,e.id ASC",
            ListeningListSort::PublicationDate => "a.published_at DESC,a.id DESC,e.id ASC",
        };
        let sql = format!(
            "SELECT l.article_id,a.feed_id,a.title,f.title,a.published_at,l.added_at, \
                    e.id,e.article_id,e.url,e.mime_type,e.size_bytes,e.remote_media_progression_seconds,e.remote_present, \
                    p.position_ms,p.duration_ms,p.status,p.updated_at, \
                    d.state,d.origin,d.local_file,d.file_size_bytes,d.downloaded_at,d.failure_kind, \
                    m.duration_ms \
             FROM listening_list l \
             JOIN articles a ON a.id=l.article_id \
             JOIN feeds f ON f.id=a.feed_id \
             LEFT JOIN enclosures e ON e.article_id=a.id AND lower(e.mime_type) LIKE 'audio/%' \
             LEFT JOIN playback_states p ON p.enclosure_id=e.id \
             LEFT JOIN media_downloads d ON d.enclosure_id=e.id \
             LEFT JOIN media_metadata m ON m.enclosure_id=e.id \
             WHERE (?1 IS NULL OR a.feed_id=?1) \
             ORDER BY {order}"
        );
        let mut statement = connection.prepare(&sql).map_err(sql_error)?;
        let mut items = Vec::new();
        let mut current: Option<ListeningListItem> = None;
        let rows = statement
            .query_map([feed_id], listening_list_row)
            .map_err(sql_error)?;
        for row in rows {
            let (article_id, feed_id, title, feed_title, published_at, added_at, enclosure) =
                row.map_err(sql_error)?;
            if current
                .as_ref()
                .is_none_or(|item| item.article_id != article_id)
            {
                if let Some(item) = current
                    .take()
                    .filter(|item| !item.audio_enclosures.is_empty())
                {
                    items.push(item);
                }
                current = Some(ListeningListItem {
                    article_id,
                    feed_id,
                    title,
                    feed_title,
                    published_at,
                    added_at,
                    remote_present: true,
                    audio_enclosures: Vec::new(),
                    active_enclosure_id: None,
                });
            }
            if let Some(enclosure) = enclosure {
                let item = current.as_mut().expect("listening list row has an item");
                item.remote_present &= enclosure.remote_present;
                if enclosure.playback_state.as_ref().is_some_and(|state| {
                    item.active_enclosure_id
                        .and_then(|active| {
                            item.audio_enclosures
                                .iter()
                                .find(|e| e.enclosure.id == active)
                        })
                        .and_then(|active| active.playback_state.as_ref())
                        .is_none_or(|active| state.updated_at > active.updated_at)
                }) {
                    item.active_enclosure_id = Some(enclosure.enclosure.id);
                }
                item.audio_enclosures.push(enclosure);
            }
        }
        if let Some(item) = current.filter(|item| !item.audio_enclosures.is_empty()) {
            items.push(item);
        }
        Ok(items)
    }

    pub fn listening_list_feeds(&self) -> Result<Vec<ListeningListFeed>, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let mut statement = connection
            .prepare("SELECT a.feed_id,f.title,COUNT(*) FROM listening_list l JOIN articles a ON a.id=l.article_id JOIN feeds f ON f.id=a.feed_id WHERE EXISTS(SELECT 1 FROM enclosures e WHERE e.article_id=a.id AND lower(e.mime_type) LIKE 'audio/%') GROUP BY a.feed_id,f.title ORDER BY f.title COLLATE NOCASE,a.feed_id")
            .map_err(sql_error)?;
        statement
            .query_map([], |row| {
                Ok(ListeningListFeed {
                    feed_id: row.get(0)?,
                    feed_title: row.get(1)?,
                    item_count: row
                        .get::<_, i64>(2)?
                        .try_into()
                        .map_err(|_| rusqlite::Error::InvalidQuery)?,
                })
            })
            .map_err(sql_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(sql_error)
    }

    pub fn set_enclosure_remote_present(
        &self,
        enclosure_id: i64,
        remote_present: bool,
    ) -> Result<(), CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        if connection
            .execute(
                "UPDATE enclosures SET remote_present=?2 WHERE id=?1",
                params![enclosure_id, remote_present],
            )
            .map_err(sql_error)?
            == 0
        {
            return Err(CoreError::data(format!(
                "enclosure {enclosure_id} does not exist"
            )));
        }
        Ok(())
    }
    /// Records that an article can no longer be recovered remotely while retaining its local media.
    pub fn mark_article_enclosures_remote_absent(&self, article_id: i64) -> Result<(), CoreError> {
        self.connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?
            .execute(
                "UPDATE enclosures SET remote_present=0 WHERE article_id=?1",
                [article_id],
            )
            .map_err(sql_error)?;
        Ok(())
    }
    pub fn article_has_remote_present_enclosure(&self, article_id: i64) -> Result<bool, CoreError> {
        self.connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM enclosures WHERE article_id=?1 AND remote_present=1)",
                [article_id],
                |row| row.get(0),
            )
            .map_err(sql_error)
    }

    pub fn save_media(&self, enclosure_id: i64, added_at: &str) -> Result<bool, CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        let inserted = save_media(&tx, enclosure_id, added_at)?;
        if inserted {
            queue_saved_media_replication(&tx, enclosure_id, SavedMediaMarkerState::Saved)?;
        }
        tx.commit().map_err(sql_error)?;
        Ok(inserted)
    }

    /// Atomically materializes a remote-search article/enclosure before saving it locally.
    pub fn materialize_saved_media(
        &self,
        article: &Article,
        enclosure: &Enclosure,
        added_at: &str,
    ) -> Result<(), CoreError> {
        if enclosure.article_id != article.id {
            return Err(CoreError::data(
                "search enclosure does not belong to the materialized article",
            ));
        }
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        tx.execute("INSERT INTO articles (id,feed_id,title,url,comments_url,published_at,is_read,is_starred,remote_is_read,remote_is_starred,raw_html_content,reading_time_minutes,preview,image_url,content_processing_version) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?7,?8,?9,?10,?11,?12,?13) ON CONFLICT(id) DO NOTHING", params![article.id,article.feed_id,article.title,article.url,article.comments_url,article.published_at,article.is_read,article.is_starred,article.raw_html_content,article.reading_time_minutes,article.preview,article.image_url,crate::article::PROCESSING_VERSION]).map_err(sql_error)?;
        upsert_remote_enclosures(&tx, std::slice::from_ref(enclosure))?;
        save_media(&tx, enclosure.id, added_at)?;
        tx.commit().map_err(sql_error)
    }

    pub fn unsave_media(&self, enclosure_id: i64) -> Result<bool, CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        let removed = tx
            .execute(
                "DELETE FROM saved_media WHERE enclosure_id=?1",
                [enclosure_id],
            )
            .map_err(sql_error)?
            > 0;
        if removed {
            queue_saved_media_replication(&tx, enclosure_id, SavedMediaMarkerState::Unsaved)?;
        }
        tx.commit().map_err(sql_error)?;
        Ok(removed)
    }

    pub fn saved_media_sync_configuration(&self) -> Result<SavedMediaSyncConfiguration, CoreError> {
        self.connection.lock().map_err(|_| CoreError::internal("database lock poisoned"))?
            .query_row("SELECT enabled,sync_feed_id,requires_repair FROM saved_media_sync_config WHERE id=1", [], |row| Ok(SavedMediaSyncConfiguration { enabled: row.get(0)?, sync_feed_id: row.get(1)?, requires_repair: row.get(2)? })).map_err(sql_error)
    }

    pub fn enable_saved_media_sync(&self, feed_id: i64) -> Result<(), CoreError> {
        if feed_id <= 0 {
            return Err(CoreError::data("SavedMedia sync feed ID must be positive"));
        }
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        tx.execute("UPDATE saved_media_sync_config SET enabled=1,sync_feed_id=?1,requires_repair=0 WHERE id=1", [feed_id]).map_err(sql_error)?;
        tx.execute("INSERT INTO pending_saved_media_replication(enclosure_id,article_id,desired) SELECT s.enclosure_id,e.article_id,'saved' FROM saved_media s JOIN enclosures e ON e.id=s.enclosure_id ON CONFLICT(enclosure_id) DO UPDATE SET article_id=excluded.article_id,desired=excluded.desired", []).map_err(sql_error)?;
        tx.execute("INSERT INTO pending_saved_media_replication(enclosure_id,article_id,desired) SELECT r.enclosure_id,r.article_id,'unsaved' FROM saved_media_remote_state r WHERE NOT EXISTS(SELECT 1 FROM saved_media s WHERE s.enclosure_id=r.enclosure_id) ON CONFLICT(enclosure_id) DO UPDATE SET article_id=excluded.article_id,desired=excluded.desired", []).map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
        Ok(())
    }

    pub fn disable_saved_media_sync(&self) -> Result<(), CoreError> {
        self.connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?
            .execute(
                "UPDATE saved_media_sync_config SET enabled=0 WHERE id=1",
                [],
            )
            .map_err(sql_error)?;
        Ok(())
    }

    pub fn mark_saved_media_sync_repair_required(&self) -> Result<(), CoreError> {
        self.connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?
            .execute(
                "UPDATE saved_media_sync_config SET requires_repair=1 WHERE id=1",
                [],
            )
            .map_err(sql_error)?;
        Ok(())
    }

    pub fn pending_saved_media_replication(
        &self,
    ) -> Result<Vec<PendingSavedMediaReplication>, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let mut statement = connection.prepare("SELECT enclosure_id,article_id,desired FROM pending_saved_media_replication ORDER BY enclosure_id").map_err(sql_error)?;
        statement
            .query_map([], |row| {
                Ok(PendingSavedMediaReplication {
                    enclosure_id: row.get(0)?,
                    article_id: row.get(1)?,
                    desired: marker_state_from_db(&row.get::<_, String>(2)?)?,
                })
            })
            .map_err(sql_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(sql_error)
    }

    pub fn acknowledge_saved_media_replication(
        &self,
        enclosure_id: i64,
        desired: SavedMediaMarkerState,
    ) -> Result<(), CoreError> {
        self.connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?
            .execute(
                "DELETE FROM pending_saved_media_replication WHERE enclosure_id=?1 AND desired=?2",
                params![enclosure_id, marker_state_db(desired)],
            )
            .map_err(sql_error)?;
        Ok(())
    }

    /// Records the remote write before conditionally clearing the matching local intent.
    pub fn acknowledge_saved_media_replication_with_remote_state(
        &self,
        state: &SavedMediaRemoteState,
        desired: SavedMediaMarkerState,
    ) -> Result<(), CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        tx.execute("INSERT INTO saved_media_remote_state(enclosure_id,article_id,marker_entry_id,state) VALUES(?1,?2,?3,?4) ON CONFLICT(enclosure_id) DO UPDATE SET article_id=excluded.article_id,marker_entry_id=excluded.marker_entry_id,state=excluded.state", params![state.enclosure_id,state.article_id,state.marker_entry_id,marker_state_db(state.state)]).map_err(sql_error)?;
        tx.execute(
            "DELETE FROM pending_saved_media_replication WHERE enclosure_id=?1 AND desired=?2",
            params![state.enclosure_id, marker_state_db(desired)],
        )
        .map_err(sql_error)?;
        tx.commit().map_err(sql_error)
    }

    pub fn saved_media_replication_pending(&self, enclosure_id: i64) -> Result<bool, CoreError> {
        self.connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM pending_saved_media_replication WHERE enclosure_id=?1)",
                [enclosure_id],
                |row| row.get(0),
            )
            .map_err(sql_error)
    }

    pub fn saved_media_remote_state(
        &self,
        enclosure_id: i64,
    ) -> Result<Option<SavedMediaRemoteState>, CoreError> {
        self.connection.lock().map_err(|_| CoreError::internal("database lock poisoned"))?
            .query_row("SELECT enclosure_id,article_id,marker_entry_id,state FROM saved_media_remote_state WHERE enclosure_id=?1", [enclosure_id], |row| Ok(SavedMediaRemoteState { enclosure_id: row.get(0)?, article_id: row.get(1)?, marker_entry_id: row.get(2)?, state: marker_state_from_db(&row.get::<_, String>(3)?)? })).optional().map_err(sql_error)
    }

    pub fn record_saved_media_remote_state(
        &self,
        state: &SavedMediaRemoteState,
    ) -> Result<(), CoreError> {
        self.connection.lock().map_err(|_| CoreError::internal("database lock poisoned"))?
            .execute("INSERT INTO saved_media_remote_state(enclosure_id,article_id,marker_entry_id,state) VALUES(?1,?2,?3,?4) ON CONFLICT(enclosure_id) DO UPDATE SET article_id=excluded.article_id,marker_entry_id=excluded.marker_entry_id,state=excluded.state", params![state.enclosure_id,state.article_id,state.marker_entry_id,marker_state_db(state.state)]).map_err(sql_error)?;
        Ok(())
    }

    pub fn apply_remote_saved_media_state(
        &self,
        enclosure_id: i64,
        state: SavedMediaMarkerState,
        added_at: &str,
    ) -> Result<(), CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        match state {
            SavedMediaMarkerState::Saved => {
                save_media(&tx, enclosure_id, added_at)?;
            }
            SavedMediaMarkerState::Unsaved => {
                tx.execute(
                    "DELETE FROM saved_media WHERE enclosure_id=?1",
                    [enclosure_id],
                )
                .map_err(sql_error)?;
            }
        }
        tx.commit().map_err(sql_error)
    }

    pub fn saved_media(&self, enclosure_id: i64) -> Result<Option<SavedMedia>, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        connection
            .query_row(
                "SELECT enclosure_id,added_at FROM saved_media WHERE enclosure_id=?1",
                [enclosure_id],
                |row| {
                    Ok(SavedMedia {
                        enclosure_id: row.get(0)?,
                        added_at: row.get(1)?,
                    })
                },
            )
            .optional()
            .map_err(sql_error)
    }

    pub fn playback_state(&self, enclosure_id: i64) -> Result<Option<PlaybackState>, CoreError> {
        self.connection.lock().map_err(|_| CoreError::internal("database lock poisoned"))?
            .query_row("SELECT enclosure_id,position_ms,duration_ms,status,updated_at FROM playback_states WHERE enclosure_id=?1", [enclosure_id], playback_state_from_row).optional().map_err(sql_error)
    }

    pub fn protected_playback_article_ids(&self) -> Result<Vec<i64>, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let mut statement = connection.prepare("SELECT DISTINCT e.article_id FROM enclosures e LEFT JOIN playback_states p ON p.enclosure_id=e.id AND p.status='in_progress' LEFT JOIN pending_media_progress_mutations m ON m.enclosure_id=e.id WHERE p.enclosure_id IS NOT NULL OR m.enclosure_id IS NOT NULL ORDER BY e.article_id").map_err(sql_error)?;
        statement
            .query_map([], |row| row.get(0))
            .map_err(sql_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(sql_error)
    }

    pub fn protected_playback_enclosure_ids(&self) -> Result<Vec<i64>, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let mut statement = connection.prepare("SELECT DISTINCT e.id FROM enclosures e LEFT JOIN playback_states p ON p.enclosure_id=e.id AND p.status='in_progress' LEFT JOIN pending_media_progress_mutations m ON m.enclosure_id=e.id WHERE p.enclosure_id IS NOT NULL OR m.enclosure_id IS NOT NULL ORDER BY e.id").map_err(sql_error)?;
        statement
            .query_map([], |row| row.get(0))
            .map_err(sql_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(sql_error)
    }

    pub fn protected_playback_requirements(&self) -> Result<Vec<(i64, i64)>, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let mut statement = connection.prepare("SELECT DISTINCT e.article_id,e.id FROM enclosures e LEFT JOIN playback_states p ON p.enclosure_id=e.id AND p.status='in_progress' LEFT JOIN pending_media_progress_mutations m ON m.enclosure_id=e.id WHERE p.enclosure_id IS NOT NULL OR m.enclosure_id IS NOT NULL ORDER BY e.article_id,e.id").map_err(sql_error)?;
        statement
            .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
            .map_err(sql_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(sql_error)
    }

    pub fn checkpoint_playback(
        &self,
        enclosure_id: i64,
        position_ms: u64,
        duration_ms: Option<u64>,
        updated_at: &str,
        queue_progress: bool,
    ) -> Result<(), CoreError> {
        if duration_ms.is_some_and(|duration| position_ms > duration) {
            return Err(CoreError::data("playback position exceeds duration"));
        }
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        ensure_enclosure(&tx, enclosure_id)?;
        upsert_playback_state(
            &tx,
            enclosure_id,
            position_ms,
            duration_ms,
            PlaybackStatus::InProgress,
            updated_at,
        )?;
        if queue_progress {
            queue_media_progress(&tx, enclosure_id, milliseconds_to_seconds(position_ms)?)?;
        }
        tx.commit().map_err(sql_error)
    }

    pub fn observe_media_duration(
        &self,
        enclosure_id: i64,
        duration_ms: u64,
        updated_at: &str,
    ) -> Result<(), CoreError> {
        let state = self.playback_state(enclosure_id)?;
        let Some(state) = state else {
            let exists: bool = {
                let connection = self
                    .connection
                    .lock()
                    .map_err(|_| CoreError::internal("database lock poisoned"))?;
                connection
                    .query_row(
                        "SELECT EXISTS(SELECT 1 FROM enclosures WHERE id=?1)",
                        [enclosure_id],
                        |row| row.get(0),
                    )
                    .map_err(sql_error)?
            };
            if !exists {
                return Err(CoreError::data(format!(
                    "enclosure {enclosure_id} does not exist"
                )));
            }
            return self.observe_media_metadata_duration(enclosure_id, duration_ms);
        };
        let (position, status) = (state.position_ms.min(duration_ms), state.status);
        {
            let mut connection = self
                .connection
                .lock()
                .map_err(|_| CoreError::internal("database lock poisoned"))?;
            let tx = connection.transaction().map_err(sql_error)?;
            ensure_enclosure(&tx, enclosure_id)?;
            upsert_playback_state(
                &tx,
                enclosure_id,
                position,
                Some(duration_ms),
                status,
                updated_at,
            )?;
            tx.commit().map_err(sql_error)?;
        }
        self.observe_media_metadata_duration(enclosure_id, duration_ms)
    }

    pub fn media_download(&self, enclosure_id: i64) -> Result<Option<MediaDownload>, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        connection
            .query_row(
                "SELECT enclosure_id,state,origin,local_file,file_size_bytes,downloaded_at,failure_kind FROM media_downloads WHERE enclosure_id=?1",
                [enclosure_id],
                media_download_from_row,
            )
            .optional()
            .map_err(sql_error)
    }

    pub fn downloaded_media_summary(&self) -> Result<DownloadedMediaSummary, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        connection
            .query_row(
                "SELECT COUNT(*), COALESCE(SUM(file_size_bytes), 0) FROM media_downloads WHERE state IN ('downloaded','delete_requested') AND local_file IS NOT NULL",
                [],
                |row| {
                    let count = row.get::<_, i64>(0)?;
                    let total = row.get::<_, i64>(1)?;
                    Ok(DownloadedMediaSummary {
                        file_count: u64::try_from(count)
                            .map_err(|_| rusqlite::Error::InvalidQuery)?,
                        total_size_bytes: u64::try_from(total)
                            .map_err(|_| rusqlite::Error::InvalidQuery)?,
                    })
                },
            )
            .map_err(sql_error)
    }

    pub fn media_metadata(&self, enclosure_id: i64) -> Result<Option<MediaMetadata>, CoreError> {
        self.connection.lock().map_err(|_| CoreError::internal("database lock poisoned"))?.query_row("SELECT enclosure_id,duration_ms,embedded_artwork_reference FROM media_metadata WHERE enclosure_id=?1", [enclosure_id], |row| Ok(MediaMetadata { enclosure_id: row.get(0)?, duration_ms: row.get::<_, Option<i64>>(1)?.map(|value| u64::try_from(value).map_err(|_| rusqlite::Error::InvalidQuery)).transpose()?, embedded_artwork_reference: row.get(2)? })).optional().map_err(sql_error)
    }

    pub fn media_artwork_source(
        &self,
        enclosure_id: i64,
    ) -> Result<Option<MediaArtworkSource>, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        connection
            .query_row(
                "SELECT (SELECT e2.url FROM enclosures e2 WHERE e2.article_id=e.article_id AND lower(e2.mime_type) LIKE 'image/%' ORDER BY e2.id LIMIT 1),m.embedded_artwork_reference,a.image_url FROM enclosures e JOIN articles a ON a.id=e.article_id LEFT JOIN media_metadata m ON m.enclosure_id=e.id WHERE e.id=?1",
                [enclosure_id],
                |row| {
                    let image_enclosure_url: Option<String> = row.get(0)?;
                    let embedded_artwork_reference: Option<String> = row.get(1)?;
                    let article_image_url: Option<String> = row.get(2)?;
                    Ok(crate::domain::select_media_artwork(
                        image_enclosure_url.as_deref(),
                        embedded_artwork_reference.as_deref(),
                        article_image_url.as_deref(),
                    ))
                },
            )
            .optional()
            .map(|value| value.flatten())
            .map_err(sql_error)
    }

    pub fn persist_probed_media_artwork(
        &self,
        enclosure_id: i64,
        artwork: Vec<u8>,
    ) -> Result<bool, CoreError> {
        let existing = self
            .media_metadata(enclosure_id)?
            .and_then(|metadata| metadata.embedded_artwork_reference);
        if existing.is_some() {
            return Ok(false);
        }

        let artwork_reference = self.persist_artwork(&Some(artwork))?;
        let Some(artwork_reference) = artwork_reference else {
            return Ok(false);
        };

        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        ensure_enclosure(&tx, enclosure_id)?;
        tx.execute(
            "INSERT INTO media_metadata(enclosure_id,duration_ms,duration_source,embedded_artwork_reference) VALUES(?1,NULL,'native',?2) ON CONFLICT(enclosure_id) DO UPDATE SET embedded_artwork_reference=COALESCE(media_metadata.embedded_artwork_reference,excluded.embedded_artwork_reference)",
            params![enclosure_id, artwork_reference],
        )
        .map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
        Ok(true)
    }

    pub fn media_artwork(&self, reference: &str) -> Result<Option<Vec<u8>>, CoreError> {
        let Some(path) = resolve_media_reference(&self.media_root, reference) else {
            return Ok(None);
        };
        match std::fs::read(path) {
            Ok(data) => Ok(Some(data)),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(error) => Err(CoreError::persistence(format!(
                "unable to read media artwork: {error}"
            ))),
        }
    }

    pub fn media_chapters(&self, enclosure_id: i64) -> Result<Vec<MediaChapter>, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let mut statement = connection.prepare("SELECT title,start_ms,end_ms,source FROM media_chapters WHERE enclosure_id=?1 ORDER BY sequence").map_err(sql_error)?;
        statement
            .query_map([enclosure_id], |row| {
                Ok(MediaChapter {
                    enclosure_id,
                    title: row.get(0)?,
                    start_ms: u64::try_from(row.get::<_, i64>(1)?)
                        .map_err(|_| rusqlite::Error::InvalidQuery)?,
                    end_ms: row
                        .get::<_, Option<i64>>(2)?
                        .map(|value| {
                            u64::try_from(value).map_err(|_| rusqlite::Error::InvalidQuery)
                        })
                        .transpose()?,
                    source: match row.get::<_, String>(3)?.as_str() {
                        "embedded" => MediaChapterSource::Embedded,
                        "article_content" => MediaChapterSource::ArticleContent,
                        _ => return Err(rusqlite::Error::InvalidQuery),
                    },
                })
            })
            .map_err(sql_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(sql_error)
    }

    pub fn prepare_article_chapters(&self, enclosure_id: i64) -> Result<(), CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let (article_html, duration_ms, has_embedded): (String, Option<i64>, bool) = connection
            .query_row(
                "SELECT a.raw_html_content,m.duration_ms,EXISTS(SELECT 1 FROM media_chapters c WHERE c.enclosure_id=e.id AND c.source='embedded') FROM enclosures e JOIN articles a ON a.id=e.article_id LEFT JOIN media_metadata m ON m.enclosure_id=e.id WHERE e.id=?1",
                [enclosure_id],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .optional()
            .map_err(sql_error)?
            .ok_or_else(|| CoreError::data(format!("enclosure {enclosure_id} does not exist")))?;
        if has_embedded {
            return Ok(());
        }
        let duration_ms = duration_ms
            .map(|value| {
                u64::try_from(value).map_err(|_| CoreError::data("media duration is invalid"))
            })
            .transpose()?;
        let chapters = to_domain_chapters(
            enclosure_id,
            MediaChapterSource::ArticleContent,
            &article_chapters(&article_html, duration_ms),
        );
        let tx = connection.transaction().map_err(sql_error)?;
        let has_embedded: bool = tx
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM media_chapters WHERE enclosure_id=?1 AND source='embedded')",
                [enclosure_id],
                |row| row.get(0),
            )
            .map_err(sql_error)?;
        if !has_embedded {
            persist_chapters(&tx, enclosure_id, &chapters)?;
        }
        tx.commit().map_err(sql_error)
    }

    pub fn replace_media_metadata(
        &self,
        enclosure_id: i64,
        metadata: &MediaMetadata,
        chapters: &[MediaChapter],
    ) -> Result<(), CoreError> {
        if metadata.enclosure_id != enclosure_id
            || chapters
                .iter()
                .any(|chapter| chapter.enclosure_id != enclosure_id)
        {
            return Err(CoreError::data("media metadata enclosure IDs do not match"));
        }
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        ensure_enclosure(&tx, enclosure_id)?;
        tx.execute("INSERT INTO media_metadata(enclosure_id,duration_ms,duration_source,embedded_artwork_reference) VALUES(?1,?2,'local',?3) ON CONFLICT(enclosure_id) DO UPDATE SET duration_ms=excluded.duration_ms,duration_source=CASE WHEN excluded.duration_ms IS NOT NULL THEN 'local' ELSE media_metadata.duration_source END,embedded_artwork_reference=excluded.embedded_artwork_reference", params![enclosure_id, metadata.duration_ms.map(i64::try_from).transpose().map_err(|_| CoreError::data("media duration exceeds SQLite integer range"))?, metadata.embedded_artwork_reference]).map_err(sql_error)?;
        let has_embedded: bool = tx
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM media_chapters WHERE enclosure_id=?1 AND source='embedded')",
                [enclosure_id],
                |row| row.get(0),
            )
            .map_err(sql_error)?;
        if has_embedded
            && chapters
                .iter()
                .all(|chapter| chapter.source != MediaChapterSource::Embedded)
        {
            tx.commit().map_err(sql_error)?;
            return Ok(());
        }
        tx.execute(
            "DELETE FROM media_chapters WHERE enclosure_id=?1",
            [enclosure_id],
        )
        .map_err(sql_error)?;
        for (sequence, chapter) in chapters.iter().enumerate() {
            if chapter.end_ms.is_some_and(|end| end <= chapter.start_ms) {
                continue;
            }
            tx.execute("INSERT INTO media_chapters(enclosure_id,sequence,title,start_ms,end_ms,source) VALUES(?1,?2,?3,?4,?5,?6)", params![enclosure_id, sequence as i64, chapter.title, i64::try_from(chapter.start_ms).map_err(|_| CoreError::data("chapter start exceeds SQLite integer range"))?, chapter.end_ms.map(i64::try_from).transpose().map_err(|_| CoreError::data("chapter end exceeds SQLite integer range"))?, match chapter.source { MediaChapterSource::Embedded => "embedded", MediaChapterSource::ArticleContent => "article_content" }]).map_err(sql_error)?;
        }
        tx.commit().map_err(sql_error)
    }

    pub fn analyze_downloaded_media(&self, enclosure_id: i64) -> Result<(), CoreError> {
        let (local_file, article_html): (String, String) = self.connection.lock().map_err(|_| CoreError::internal("database lock poisoned"))?.query_row("SELECT d.local_file,a.raw_html_content FROM media_downloads d JOIN enclosures e ON e.id=d.enclosure_id JOIN articles a ON a.id=e.article_id WHERE d.enclosure_id=?1 AND d.state='downloaded'", [enclosure_id], |row| Ok((row.get(0)?, row.get(1)?))).map_err(sql_error)?;
        let analyzed = resolve_media_reference(&self.media_root, &local_file)
            .map(|path| analyze_file(&path))
            .unwrap_or_default();
        let artwork_reference = self.persist_artwork(&analyzed.artwork)?;
        let chapters = if analyzed.embedded_chapters.is_empty() {
            article_chapters(&article_html, analyzed.duration_ms)
        } else {
            analyzed.embedded_chapters.clone()
        };
        let source = if analyzed.embedded_chapters.is_empty() {
            MediaChapterSource::ArticleContent
        } else {
            MediaChapterSource::Embedded
        };
        self.replace_media_metadata(
            enclosure_id,
            &MediaMetadata {
                enclosure_id,
                duration_ms: analyzed.duration_ms,
                embedded_artwork_reference: artwork_reference,
            },
            &to_domain_chapters(enclosure_id, source, &chapters),
        )
    }

    fn persist_artwork(&self, data: &Option<Vec<u8>>) -> Result<Option<String>, CoreError> {
        let Some(data) = data else { return Ok(None) };
        let Ok(image) = image::load_from_memory(data) else {
            return Ok(None);
        };
        let mut png = Cursor::new(Vec::new());
        if image.write_to(&mut png, image::ImageFormat::Png).is_err() {
            return Ok(None);
        }
        let png = png.into_inner();
        let digest = Sha256::digest(&png);
        let relative = format!("metadata/artwork-{}.png", hex_digest(&digest));
        let path = self.media_root.join(&relative);
        if std::fs::create_dir_all(path.parent().expect("artwork path has parent")).is_err() {
            return Ok(None);
        }
        if !path.exists() && std::fs::write(&path, png).is_err() {
            return Ok(None);
        }
        Ok(Some(relative))
    }

    pub fn observe_media_metadata_duration(
        &self,
        enclosure_id: i64,
        duration_ms: u64,
    ) -> Result<(), CoreError> {
        let duration = i64::try_from(duration_ms)
            .map_err(|_| CoreError::data("media duration exceeds SQLite integer range"))?;
        if duration == 0 {
            return Err(CoreError::data("media duration must be positive"));
        }
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        ensure_enclosure(&tx, enclosure_id)?;
        let duration_source: Option<String> = tx
            .query_row(
                "SELECT duration_source FROM media_metadata WHERE enclosure_id=?1",
                [enclosure_id],
                |row| row.get(0),
            )
            .optional()
            .map_err(sql_error)?
            .flatten();
        if duration_source.as_deref() != Some("local") {
            tx.execute("INSERT INTO media_metadata(enclosure_id,duration_ms,duration_source) VALUES(?1,?2,'native') ON CONFLICT(enclosure_id) DO UPDATE SET duration_ms=excluded.duration_ms,duration_source='native'", params![enclosure_id, duration]).map_err(sql_error)?;
        }
        tx.commit().map_err(sql_error)
    }

    pub fn request_download(
        &self,
        enclosure_id: i64,
        origin: DownloadOrigin,
    ) -> Result<(), CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        ensure_enclosure(&tx, enclosure_id)?;
        if is_audio_enclosure(&tx, enclosure_id)? {
            let article_id: i64 = tx
                .query_row(
                    "SELECT article_id FROM enclosures WHERE id=?1",
                    [enclosure_id],
                    |row| row.get(0),
                )
                .map_err(sql_error)?;
            ensure_listening_membership(&tx, article_id, &Utc::now().to_rfc3339())?;
        }
        request_download_in_transaction(&tx, enclosure_id, origin)?;
        tx.commit().map_err(sql_error)
    }

    pub fn cancel_download(&self, enclosure_id: i64) -> Result<(), CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        let origin: Option<String> = tx
            .query_row(
                "SELECT origin FROM media_downloads WHERE enclosure_id=?1",
                [enclosure_id],
                |row| row.get(0),
            )
            .optional()
            .map_err(sql_error)?;
        match read_download_state(&tx, enclosure_id)? {
            None => return Ok(()),
            Some(DownloadState::Requested) | Some(DownloadState::Failed) => {
                tx.execute(
                    "DELETE FROM media_downloads WHERE enclosure_id=?1",
                    [enclosure_id],
                )
                .map_err(sql_error)?;
                if origin.as_deref() == Some("automatic") {
                    tx.execute(
                        "INSERT OR IGNORE INTO auto_download_suppressions(enclosure_id) VALUES(?1)",
                        [enclosure_id],
                    )
                    .map_err(sql_error)?;
                }
            }
            Some(other) => {
                return Err(CoreError::data(format!(
                    "cannot cancel download in {other:?}"
                )));
            }
        }
        tx.commit().map_err(sql_error)
    }

    pub fn retry_download(&self, enclosure_id: i64) -> Result<(), CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        match read_download_state(&tx, enclosure_id)? {
            Some(DownloadState::Failed) => {
                tx.execute("UPDATE media_downloads SET state='requested',failure_kind=NULL,local_file=NULL,file_size_bytes=NULL,downloaded_at=NULL WHERE enclosure_id=?1", [enclosure_id]).map_err(sql_error)?;
            }
            Some(other) => {
                return Err(CoreError::data(format!(
                    "cannot retry download in {other:?}"
                )));
            }
            None => {
                return Err(CoreError::data("cannot retry download in NotDownloaded"));
            }
        }
        tx.commit().map_err(sql_error)
    }

    pub fn download_finished(
        &self,
        enclosure_id: i64,
        local_file: &str,
        file_size_bytes: u64,
    ) -> Result<(), CoreError> {
        if local_file.trim().is_empty() {
            return Err(CoreError::data(
                "download_finished requires a non-empty local file reference",
            ));
        }
        let size = i64::try_from(file_size_bytes)
            .map_err(|_| CoreError::data("download_finished file size exceeds SQLite range"))?;
        let analyzed = resolve_media_reference(&self.media_root, local_file)
            .map(|path| analyze_file(&path))
            .unwrap_or_default();
        let article_html = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?
            .query_row(
                "SELECT a.raw_html_content FROM articles a JOIN enclosures e ON e.article_id=a.id WHERE e.id=?1",
                [enclosure_id],
                |row| row.get::<_, String>(0),
            )
            .optional()
            .map_err(sql_error)?
            .unwrap_or_default();
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        match read_download_state(&tx, enclosure_id)? {
            Some(DownloadState::Requested) => {
                tx.execute(
                    "UPDATE media_downloads SET state='downloaded',local_file=?1,file_size_bytes=?2,downloaded_at=?3,failure_kind=NULL WHERE enclosure_id=?4",
                    params![local_file, size, Utc::now().to_rfc3339(), enclosure_id],
                )
                .map_err(sql_error)?;
                let artwork_reference = self.persist_artwork(&analyzed.artwork)?;
                persist_media_metadata(
                    &tx,
                    enclosure_id,
                    &article_html,
                    &analyzed,
                    artwork_reference.as_deref(),
                )?;
            }
            _ => {
                return Err(CoreError::data(
                    "download_finished requires Requested state",
                ));
            }
        }
        tx.commit().map_err(sql_error)
    }

    /// Persist a specifically fetched legacy article only if its feed/category
    /// already belong to the authoritative current navigation catalog. Does not
    /// reconcile absent articles or change existing native article state.
    pub fn restore_legacy_media_article(
        &self,
        article: &Article,
        enclosures: &[Enclosure],
        expected_enclosure_id: i64,
    ) -> Result<bool, CoreError> {
        if !enclosures.iter().any(|e| {
            e.id == expected_enclosure_id
                && e.article_id == article.id
                && e.mime_type.to_ascii_lowercase().starts_with("audio/")
        }) || enclosures.iter().any(|e| e.article_id != article.id)
        {
            return Ok(false);
        }
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        let feed_is_current: bool = tx.query_row(
            "SELECT EXISTS(SELECT 1 FROM feeds f JOIN categories c ON c.id=f.category_id WHERE f.id=?1)",
            [article.feed_id], |row| row.get(0),
        ).map_err(sql_error)?;
        if !feed_is_current {
            return Ok(false);
        }
        tx.execute(
            "INSERT OR IGNORE INTO articles (id,feed_id,title,url,comments_url,published_at,is_read,is_starred,remote_is_read,remote_is_starred,raw_html_content,reading_time_minutes,preview,image_url,content_processing_version) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?7,?8,?9,?10,?11,?12,?13)",
            params![article.id,article.feed_id,article.title,article.url,article.comments_url,article.published_at,article.is_read,article.is_starred,article.raw_html_content,article.reading_time_minutes,article.preview,article.image_url,crate::article::PROCESSING_VERSION],
        ).map_err(sql_error)?;
        upsert_remote_enclosures(&tx, enclosures)?;
        tx.commit().map_err(sql_error)?;
        Ok(true)
    }

    /// Rehydrates a download-backed historical article from a platform-verified
    /// local legacy database snapshot. Existing Core rows always win, the
    /// current navigation catalog must still contain the feed, and the legacy
    /// enclosure is explicitly marked as not remotely present.
    pub fn restore_legacy_local_playback_article(
        &self,
        article: &Article,
        enclosure: &Enclosure,
    ) -> Result<bool, CoreError> {
        if article.id <= 0
            || article.feed_id <= 0
            || enclosure.id <= 0
            || enclosure.article_id != article.id
            || !enclosure
                .mime_type
                .to_ascii_lowercase()
                .starts_with("audio/")
            || enclosure.url.trim().is_empty()
        {
            return Ok(false);
        }

        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;

        let feed_is_current: bool = tx
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM feeds f JOIN categories c ON c.id=f.category_id WHERE f.id=?1)",
                [article.feed_id],
                |row| row.get(0),
            )
            .map_err(sql_error)?;
        if !feed_is_current {
            return Ok(false);
        }

        let existing_article_feed = tx
            .query_row(
                "SELECT feed_id FROM articles WHERE id=?1",
                [article.id],
                |row| row.get::<_, i64>(0),
            )
            .optional()
            .map_err(sql_error)?;
        if existing_article_feed.is_some_and(|feed_id| feed_id != article.feed_id) {
            return Ok(false);
        }

        let existing_enclosure = tx
            .query_row(
                "SELECT article_id,mime_type FROM enclosures WHERE id=?1",
                [enclosure.id],
                |row| Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?)),
            )
            .optional()
            .map_err(sql_error)?;
        if let Some((article_id, mime_type)) = existing_enclosure {
            return Ok(
                article_id == article.id && mime_type.to_ascii_lowercase().starts_with("audio/")
            );
        }

        let existing_audio_count: i64 = tx
            .query_row(
                "SELECT COUNT(*) FROM enclosures WHERE article_id=?1 AND lower(mime_type) LIKE 'audio/%'",
                [article.id],
                |row| row.get(0),
            )
            .map_err(sql_error)?;
        if existing_audio_count > 0 {
            // A matching enclosure ID was handled above. Any other existing
            // native audio identity must win rather than letting legacy progress
            // attach to a potentially different enclosure.
            return Ok(false);
        }

        tx.execute(
            "INSERT OR IGNORE INTO articles (id,feed_id,title,url,comments_url,published_at,is_read,is_starred,remote_is_read,remote_is_starred,raw_html_content,reading_time_minutes,preview,image_url,content_processing_version) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,NULL,NULL,?9,?10,?11,?12,?13)",
            params![
                article.id,
                article.feed_id,
                article.title,
                article.url,
                article.comments_url,
                article.published_at,
                article.is_read,
                article.is_starred,
                article.raw_html_content,
                article.reading_time_minutes,
                article.preview,
                article.image_url,
                crate::article::PROCESSING_VERSION
            ],
        )
        .map_err(sql_error)?;

        tx.execute(
            "INSERT OR IGNORE INTO enclosures (id,article_id,url,mime_type,size_bytes,remote_media_progression_seconds,remote_present) VALUES (?1,?2,?3,?4,NULL,0,0)",
            params![
                enclosure.id,
                enclosure.article_id,
                enclosure.url,
                enclosure.mime_type
            ],
        )
        .map_err(sql_error)?;

        let restored = tx
            .query_row(
                "SELECT article_id,mime_type FROM enclosures WHERE id=?1",
                [enclosure.id],
                |row| Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?)),
            )
            .optional()
            .map_err(sql_error)?
            .is_some_and(|(article_id, mime_type)| {
                article_id == article.id && mime_type.to_ascii_lowercase().starts_with("audio/")
            });
        tx.commit().map_err(sql_error)?;
        Ok(restored)
    }

    /// Reprocess migrated Flutter media once after the initial import. Existing
    /// artwork, duration, chapters and download/playback state always win.
    /// A failed scan does not set the platform completion marker and can retry.
    pub fn repair_legacy_download_metadata(&self) -> Result<(u32, u32), CoreError> {
        let entries: Vec<(i64, String, String)> = {
            let connection = self
                .connection
                .lock()
                .map_err(|_| CoreError::internal("database lock poisoned"))?;
            let mut statement = connection.prepare(
                "SELECT d.enclosure_id,d.local_file,a.raw_html_content FROM media_downloads d JOIN enclosures e ON e.id=d.enclosure_id JOIN articles a ON a.id=e.article_id WHERE d.state='downloaded' AND d.local_file LIKE 'downloads/legacy/%'"
            ).map_err(sql_error)?;
            statement
                .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
                .map_err(sql_error)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(sql_error)?
        };
        let mut scanned = 0u32;
        let mut recovered = 0u32;
        for (enclosure_id, reference, article_html) in entries {
            let path = resolve_media_reference(&self.media_root, &reference)
                .ok_or_else(|| CoreError::data("invalid legacy media path"))?;
            if !path.is_file() {
                return Err(CoreError::persistence(
                    "legacy media file missing during metadata repair",
                ));
            }
            let analyzed = analyze_file(&path);
            let prior = self.media_metadata(enclosure_id)?;
            let has_artwork = prior
                .as_ref()
                .and_then(|m| m.embedded_artwork_reference.as_ref())
                .is_some();
            let artwork_reference = if has_artwork {
                None
            } else {
                self.persist_artwork(&analyzed.artwork)?
            };
            let mut connection = self
                .connection
                .lock()
                .map_err(|_| CoreError::internal("database lock poisoned"))?;
            let tx = connection.transaction().map_err(sql_error)?;
            let had_chapters: bool = tx
                .query_row(
                    "SELECT EXISTS(SELECT 1 FROM media_chapters WHERE enclosure_id=?1)",
                    [enclosure_id],
                    |row| row.get(0),
                )
                .map_err(sql_error)?;
            let duration = analyzed
                .duration_ms
                .map(i64::try_from)
                .transpose()
                .map_err(|_| CoreError::data("legacy duration exceeds SQLite range"))?;
            tx.execute(
                "INSERT INTO media_metadata(enclosure_id,duration_ms,duration_source,embedded_artwork_reference) VALUES(?1,?2,'local',?3) ON CONFLICT(enclosure_id) DO UPDATE SET duration_ms=COALESCE(media_metadata.duration_ms,excluded.duration_ms),embedded_artwork_reference=COALESCE(media_metadata.embedded_artwork_reference,excluded.embedded_artwork_reference)",
                params![enclosure_id,duration,artwork_reference],
            ).map_err(sql_error)?;
            if !had_chapters {
                let chapters = if analyzed.embedded_chapters.is_empty() {
                    article_chapters(&article_html, analyzed.duration_ms)
                } else {
                    analyzed.embedded_chapters.clone()
                };
                let source = if analyzed.embedded_chapters.is_empty() {
                    MediaChapterSource::ArticleContent
                } else {
                    MediaChapterSource::Embedded
                };
                persist_chapters(
                    &tx,
                    enclosure_id,
                    &to_domain_chapters(enclosure_id, source, &chapters),
                )?;
            }
            tx.commit().map_err(sql_error)?;
            scanned += 1;
            if artwork_reference.is_some() {
                recovered += 1;
            }
        }
        Ok((scanned, recovered))
    }

    pub fn import_legacy_download(
        &self,
        enclosure_id: i64,
        local_file: &str,
        file_size_bytes: u64,
    ) -> Result<LegacyDownloadImportOutcome, CoreError> {
        if local_file.trim().is_empty() {
            return Err(CoreError::data(
                "legacy download requires a non-empty local file reference",
            ));
        }
        let size = i64::try_from(file_size_bytes)
            .map_err(|_| CoreError::data("legacy download file size exceeds SQLite range"))?;
        let analyzed = resolve_media_reference(&self.media_root, local_file)
            .map(|path| analyze_file(&path))
            .unwrap_or_default();
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        let article_html: Option<String> = tx.query_row(
            "SELECT a.raw_html_content FROM articles a JOIN enclosures e ON e.article_id=a.id WHERE e.id=?1",
            [enclosure_id], |row| row.get(0),
        ).optional().map_err(sql_error)?;
        let Some(article_html) = article_html else {
            return Ok(LegacyDownloadImportOutcome::MissingEnclosure);
        };
        let existing_state = read_download_state(&tx, enclosure_id)?;
        if existing_state.is_some() && existing_state != Some(DownloadState::Downloaded) {
            // Native requested/failed/deleting media remains authoritative.
            return Ok(LegacyDownloadImportOutcome::AlreadyPresent);
        }
        if is_audio_enclosure(&tx, enclosure_id)? {
            let article_id: i64 = tx
                .query_row(
                    "SELECT article_id FROM enclosures WHERE id=?1",
                    [enclosure_id],
                    |row| row.get(0),
                )
                .map_err(sql_error)?;
            // A previous migration may have persisted the download before its
            // Listening List projection was restored. Repair it on safe retry.
            ensure_listening_membership(&tx, article_id, &Utc::now().to_rfc3339())?;
        }
        if existing_state.is_some() {
            tx.commit().map_err(sql_error)?;
            return Ok(LegacyDownloadImportOutcome::AlreadyPresent);
        }
        tx.execute(
            "INSERT INTO media_downloads(enclosure_id,state,origin,local_file,file_size_bytes,downloaded_at,failure_kind) VALUES(?1,'downloaded','manual',?2,?3,?4,NULL)",
            params![enclosure_id, local_file, size, Utc::now().to_rfc3339()],
        ).map_err(sql_error)?;
        let artwork_reference = self.persist_artwork(&analyzed.artwork)?;
        persist_media_metadata(
            &tx,
            enclosure_id,
            &article_html,
            &analyzed,
            artwork_reference.as_deref(),
        )?;
        tx.commit().map_err(sql_error)?;
        Ok(LegacyDownloadImportOutcome::Imported)
    }

    pub fn download_failed(
        &self,
        enclosure_id: i64,
        failure_kind: DownloadFailureKind,
    ) -> Result<(), CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        match read_download_state(&tx, enclosure_id)? {
            Some(DownloadState::Requested) => {
                tx.execute(
                    "UPDATE media_downloads SET state='failed',local_file=NULL,file_size_bytes=NULL,downloaded_at=NULL,failure_kind=?1 WHERE enclosure_id=?2",
                    params![failure_kind_db(failure_kind), enclosure_id],
                )
                .map_err(sql_error)?;
            }
            // A late native failure callback after the user has cancelled or otherwise
            // cleared the download must not resurrect a stale Failed state.
            None | Some(DownloadState::Failed) => {}
            Some(other) => {
                return Err(CoreError::data(format!(
                    "download_failed is not expected from {other:?}"
                )));
            }
        }
        tx.commit().map_err(sql_error)
    }

    pub fn request_download_deletion(&self, enclosure_id: i64) -> Result<(), CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        match read_download_state(&tx, enclosure_id)? {
            Some(DownloadState::Downloaded) => {
                tx.execute(
                    "UPDATE media_downloads SET state='delete_requested' WHERE enclosure_id=?1",
                    [enclosure_id],
                )
                .map_err(sql_error)?;
                if tx.query_row("SELECT EXISTS(SELECT 1 FROM articles a JOIN enclosures e ON e.article_id=a.id JOIN feed_preferences p ON p.feed_id=a.feed_id WHERE e.id=?1 AND p.auto_download_audio=1)", [enclosure_id], |row| row.get::<_, bool>(0)).map_err(sql_error)? {
                    tx.execute("INSERT OR IGNORE INTO auto_download_suppressions(enclosure_id) VALUES(?1)", [enclosure_id]).map_err(sql_error)?;
                }
            }
            Some(DownloadState::DeleteRequested) => {}
            Some(other) => {
                return Err(CoreError::data(format!(
                    "cannot request download deletion from {other:?}"
                )));
            }
            None => return Err(CoreError::data("cannot delete a non-downloaded enclosure")),
        }
        tx.commit().map_err(sql_error)
    }

    pub fn request_all_download_deletions(&self) -> Result<u64, CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;

        tx.execute(
            "INSERT OR IGNORE INTO auto_download_suppressions(enclosure_id)
             SELECT d.enclosure_id
             FROM media_downloads d
             JOIN enclosures e ON e.id=d.enclosure_id
             JOIN articles a ON a.id=e.article_id
             JOIN feed_preferences p ON p.feed_id=a.feed_id
             WHERE d.state='downloaded' AND p.auto_download_audio=1",
            [],
        )
        .map_err(sql_error)?;

        let changed = tx
            .execute(
                "UPDATE media_downloads SET state='delete_requested' WHERE state='downloaded'",
                [],
            )
            .map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
        u64::try_from(changed).map_err(|_| CoreError::internal("download deletion count overflow"))
    }

    pub fn download_deleted(&self, enclosure_id: i64) -> Result<(), CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        match read_download_state(&tx, enclosure_id)? {
            Some(DownloadState::DeleteRequested) => {
                tx.execute(
                    "DELETE FROM media_downloads WHERE enclosure_id=?1",
                    [enclosure_id],
                )
                .map_err(sql_error)?;
            }
            Some(other) => {
                return Err(CoreError::data(format!(
                    "download_deleted requires DeleteRequested state, found {other:?}"
                )));
            }
            None => return Ok(()),
        }
        tx.commit().map_err(sql_error)
    }

    pub fn downloads_requiring_transfer(&self) -> Result<Vec<i64>, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let mut statement = connection
            .prepare("SELECT enclosure_id FROM media_downloads WHERE state='requested' ORDER BY enclosure_id")
            .map_err(sql_error)?;
        statement
            .query_map([], |row| row.get(0))
            .map_err(sql_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(sql_error)
    }

    pub fn auto_download_suppressed(&self, enclosure_id: i64) -> Result<bool, CoreError> {
        self.connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM auto_download_suppressions WHERE enclosure_id=?1)",
                [enclosure_id],
                |row| row.get(0),
            )
            .map_err(sql_error)
    }

    pub fn evaluate_media_cleanup(
        &self,
        now: chrono::DateTime<chrono::Utc>,
    ) -> Result<Vec<i64>, CoreError> {
        let settings = self.core_settings()?;
        let cutoff = match settings.download_retention {
            DownloadRetention::Forever => None,
            DownloadRetention::Days(days) => Some(now - chrono::Duration::days(i64::from(days))),
        };
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        let mut statement = tx.prepare("SELECT d.enclosure_id,d.downloaded_at,EXISTS(SELECT 1 FROM playback_states p WHERE p.enclosure_id=d.enclosure_id AND p.status='completed') FROM media_downloads d WHERE d.state='downloaded'").map_err(sql_error)?;
        let candidates = statement
            .query_map([], |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, bool>(2)?,
                ))
            })
            .map_err(sql_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(sql_error)?;
        drop(statement);
        let mut deleted = Vec::new();
        for (enclosure_id, downloaded_at, completed) in candidates {
            let expired = cutoff.is_some_and(|cutoff| {
                chrono::DateTime::parse_from_rfc3339(&downloaded_at)
                    .map(|value| value.with_timezone(&chrono::Utc) <= cutoff)
                    .unwrap_or(false)
            });
            if expired || (settings.delete_after_playback && completed) {
                tx.execute("UPDATE media_downloads SET state='delete_requested' WHERE enclosure_id=?1 AND state='downloaded'", [enclosure_id]).map_err(sql_error)?;
                deleted.push(enclosure_id);
            }
        }
        tx.commit().map_err(sql_error)?;
        Ok(deleted)
    }

    pub fn materialize_download_request(
        &self,
        article: &Article,
        enclosure: &Enclosure,
        origin: DownloadOrigin,
    ) -> Result<(), CoreError> {
        if enclosure.article_id != article.id {
            return Err(CoreError::data(
                "search enclosure does not belong to the materialized article",
            ));
        }
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        tx.execute(
            "INSERT INTO articles (id,feed_id,title,url,comments_url,published_at,is_read,is_starred,remote_is_read,remote_is_starred,raw_html_content,reading_time_minutes,preview,image_url,content_processing_version) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?7,?8,?9,?10,?11,?12,?13) ON CONFLICT(id) DO NOTHING",
            params![article.id, article.feed_id, article.title, article.url, article.comments_url, article.published_at, article.is_read, article.is_starred, article.raw_html_content, article.reading_time_minutes, article.preview, article.image_url, crate::article::PROCESSING_VERSION],
        )
        .map_err(sql_error)?;
        upsert_remote_enclosures(&tx, std::slice::from_ref(enclosure))?;
        if is_audio_enclosure(&tx, enclosure.id)? {
            ensure_listening_membership(&tx, article.id, &Utc::now().to_rfc3339())?;
        }
        tx.execute(
            "INSERT INTO media_downloads(enclosure_id,state,origin,local_file,file_size_bytes,downloaded_at,failure_kind) VALUES(?1,'requested',?2,NULL,NULL,NULL,NULL) ON CONFLICT(enclosure_id) DO UPDATE SET state='requested',origin=excluded.origin,local_file=NULL,file_size_bytes=NULL,downloaded_at=NULL,failure_kind=NULL",
            params![enclosure.id, origin_db(origin)],
        )
        .map_err(sql_error)?;
        tx.commit().map_err(sql_error)
    }

    pub fn protected_download_requirements(&self) -> Result<Vec<(i64, i64)>, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let mut statement = connection
            .prepare("SELECT e.article_id,e.id FROM enclosures e JOIN media_downloads d ON d.enclosure_id=e.id WHERE d.state IN ('requested','downloaded') ORDER BY e.article_id,e.id")
            .map_err(sql_error)?;
        statement
            .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
            .map_err(sql_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(sql_error)
    }

    pub fn complete_playback(
        &self,
        enclosure_id: i64,
        duration_ms: Option<u64>,
        updated_at: &str,
        queue_progress: bool,
    ) -> Result<(), CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        ensure_enclosure(&tx, enclosure_id)?;
        let existing: Option<(i64, Option<i64>)> = tx
            .query_row(
                "SELECT position_ms,duration_ms FROM playback_states WHERE enclosure_id=?1",
                [enclosure_id],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .optional()
            .map_err(sql_error)?;
        let duration_ms = duration_ms.or_else(|| {
            existing.and_then(|(_, duration)| duration.and_then(|value| u64::try_from(value).ok()))
        });
        let position_ms = duration_ms
            .or_else(|| existing.and_then(|(position, _)| u64::try_from(position).ok()))
            .ok_or_else(|| {
                CoreError::data(
                    "playback completion requires a duration or prior playback position",
                )
            })?;
        upsert_playback_state(
            &tx,
            enclosure_id,
            position_ms,
            duration_ms,
            PlaybackStatus::Completed,
            updated_at,
        )?;
        if queue_progress && let Some(duration) = duration_ms {
            queue_media_progress(&tx, enclosure_id, milliseconds_to_seconds(duration)?)?;
        }
        let delete_after_playback: bool = tx
            .query_row(
                "SELECT value='1' FROM core_settings WHERE key='delete_after_playback'",
                [],
                |row| row.get(0),
            )
            .map_err(sql_error)?;
        if delete_after_playback {
            tx.execute("UPDATE media_downloads SET state='delete_requested' WHERE enclosure_id=?1 AND state='downloaded'", [enclosure_id]).map_err(sql_error)?;
        }
        let remove_completed: bool = tx
            .query_row(
                "SELECT value='1' FROM core_settings WHERE key='remove_completed_listening_list'",
                [],
                |row| row.get(0),
            )
            .map_err(sql_error)?;
        if remove_completed {
            let article_id: i64 = tx
                .query_row(
                    "SELECT article_id FROM enclosures WHERE id=?1",
                    [enclosure_id],
                    |row| row.get(0),
                )
                .map_err(sql_error)?;
            let all_completed: bool = tx
                .query_row(
                    "SELECT EXISTS(SELECT 1 FROM enclosures WHERE article_id=?1 AND lower(mime_type) LIKE 'audio/%') AND NOT EXISTS(SELECT 1 FROM enclosures e LEFT JOIN playback_states p ON p.enclosure_id=e.id WHERE e.article_id=?1 AND lower(e.mime_type) LIKE 'audio/%' AND (p.status IS NULL OR p.status != 'completed'))",
                    [article_id],
                    |row| row.get(0),
                )
                .map_err(sql_error)?;
            if all_completed {
                let removed = tx
                    .execute(
                        "DELETE FROM listening_list WHERE article_id=?1",
                        [article_id],
                    )
                    .map_err(sql_error)?;
                if removed > 0 {
                    for audio_id in audio_enclosure_ids_for_article(&tx, article_id)? {
                        request_download_deletion_in_transaction(&tx, audio_id)?;
                    }
                }
            }
        }
        tx.commit().map_err(sql_error)
    }

    pub fn restart_playback(
        &self,
        enclosure_id: i64,
        updated_at: &str,
        queue_progress: bool,
    ) -> Result<(), CoreError> {
        self.checkpoint_playback(
            enclosure_id,
            0,
            self.playback_state(enclosure_id)?
                .and_then(|state| state.duration_ms),
            updated_at,
            queue_progress,
        )
    }

    pub fn promote_playback_progress(&self) -> Result<(), CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        let states = {
            let mut statement = tx
                .prepare("SELECT enclosure_id,position_ms,duration_ms,status FROM playback_states")
                .map_err(sql_error)?;
            statement
                .query_map([], |row| {
                    Ok((
                        row.get::<_, i64>(0)?,
                        row.get::<_, i64>(1)?,
                        row.get::<_, Option<i64>>(2)?,
                        row.get::<_, String>(3)?,
                    ))
                })
                .map_err(sql_error)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(sql_error)?
        };
        for (enclosure_id, position, duration, status) in states {
            let milliseconds = if status == "completed" {
                duration
            } else {
                Some(position)
            };
            if let Some(milliseconds) = milliseconds {
                queue_media_progress(
                    &tx,
                    enclosure_id,
                    milliseconds_to_seconds(
                        u64::try_from(milliseconds)
                            .map_err(|_| CoreError::persistence("invalid playback position"))?,
                    )?,
                )?;
            }
        }
        tx.commit().map_err(sql_error)
    }

    pub fn saved_playable_media(&self) -> Result<Vec<SavedPlayableMediaItem>, CoreError> {
        self.saved_playable_media_query(None)
    }

    pub fn saved_media_by_feed(
        &self,
        feed_id: i64,
    ) -> Result<Vec<SavedPlayableMediaItem>, CoreError> {
        self.saved_playable_media_query(Some(feed_id))
    }

    pub fn continue_listening(&self) -> Result<Vec<ContinueListeningItem>, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let mut statement = connection
            .prepare("SELECT p.enclosure_id,e.article_id,a.feed_id,a.title,f.title,a.published_at,e.url,e.mime_type,p.position_ms,p.duration_ms,p.updated_at,d.local_file FROM playback_states p JOIN enclosures e ON e.id=p.enclosure_id JOIN articles a ON a.id=e.article_id JOIN feeds f ON f.id=a.feed_id LEFT JOIN media_downloads d ON d.enclosure_id=e.id AND d.state IN ('downloaded','delete_requested') WHERE p.status='in_progress' ORDER BY p.updated_at DESC,p.enclosure_id DESC")
            .map_err(sql_error)?;
        statement
            .query_map([], |row| {
                Ok(ContinueListeningItem {
                    enclosure_id: row.get(0)?,
                    article_id: row.get(1)?,
                    feed_id: row.get(2)?,
                    title: row.get(3)?,
                    feed_title: row.get(4)?,
                    published_at: row.get(5)?,
                    url: row.get(6)?,
                    mime_type: row.get(7)?,
                    position_ms: u64::try_from(row.get::<_, i64>(8)?)
                        .map_err(|_| rusqlite::Error::InvalidQuery)?,
                    duration_ms: row
                        .get::<_, Option<i64>>(9)?
                        .map(|value| {
                            u64::try_from(value).map_err(|_| rusqlite::Error::InvalidQuery)
                        })
                        .transpose()?,
                    updated_at: row.get(10)?,
                    local_file: row.get(11)?,
                })
            })
            .map_err(sql_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(sql_error)
    }

    /// Imports article-keyed legacy progress without guessing an enclosure.
    /// An unknown legacy timestamp is persisted as the oldest sortable value so
    /// it cannot be promoted above known playback in Continue Listening.
    /// Completion of the overall platform migration belongs to the native
    /// coordinator, which also evaluates non-Core legacy sources.
    pub fn import_legacy_playback(
        &self,
        records: &[LegacyPlaybackImport],
    ) -> Result<LegacyPlaybackImportResult, CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        let mut result = LegacyPlaybackImportResult::default();
        for record in records {
            // Legacy zero means reset/completion-like input, not resumable
            // progress. Keep the new model neutral and do not queue a PUT.
            if record.position_ms == 0 {
                continue;
            }
            let article_exists: bool = tx
                .query_row(
                    "SELECT EXISTS(SELECT 1 FROM articles WHERE id=?1)",
                    [record.article_id],
                    |row| row.get(0),
                )
                .map_err(sql_error)?;
            if !article_exists {
                result.skipped_missing += 1;
                continue;
            }
            let mut statement = tx
                .prepare("SELECT id FROM enclosures WHERE article_id=?1 AND lower(mime_type) LIKE 'audio/%' ORDER BY id")
                .map_err(sql_error)?;
            let enclosure_ids: Vec<i64> = statement
                .query_map([record.article_id], |row| row.get(0))
                .map_err(sql_error)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(sql_error)?;
            let Some(enclosure_id) = enclosure_ids.first().copied() else {
                result.skipped_missing += 1;
                continue;
            };
            if enclosure_ids.len() != 1 {
                result.skipped_ambiguous += 1;
                continue;
            }
            let exists: bool = tx
                .query_row(
                    "SELECT EXISTS(SELECT 1 FROM playback_states WHERE enclosure_id=?1)",
                    [enclosure_id],
                    |row| row.get(0),
                )
                .map_err(sql_error)?;
            if exists {
                result.already_present += 1;
                continue;
            }
            upsert_playback_state(
                &tx,
                enclosure_id,
                record.position_ms,
                None,
                PlaybackStatus::InProgress,
                record
                    .updated_at
                    .as_deref()
                    .unwrap_or(LEGACY_PLAYBACK_UPDATED_AT_UNKNOWN),
            )?;
            queue_media_progress(&tx, enclosure_id, record.position_ms / 1_000)?;
            result.imported += 1;
        }
        tx.commit().map_err(sql_error)?;
        Ok(result)
    }

    fn saved_playable_media_query(
        &self,
        feed_id: Option<i64>,
    ) -> Result<Vec<SavedPlayableMediaItem>, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let sql = if feed_id.is_some() {
            "SELECT s.enclosure_id,e.article_id,a.feed_id,a.title,f.title,a.published_at,s.added_at,e.url,e.mime_type,e.remote_present,(SELECT duration_ms FROM media_metadata m WHERE m.enclosure_id=e.id),(SELECT e2.url FROM enclosures e2 WHERE e2.article_id=e.article_id AND lower(e2.mime_type) LIKE 'image/%' ORDER BY e2.id LIMIT 1),(SELECT m.embedded_artwork_reference FROM media_metadata m WHERE m.enclosure_id=e.id),a.image_url FROM saved_media s JOIN enclosures e ON e.id=s.enclosure_id JOIN articles a ON a.id=e.article_id JOIN feeds f ON f.id=a.feed_id WHERE a.feed_id=?1 ORDER BY a.published_at DESC,a.id DESC,e.id DESC"
        } else {
            "SELECT s.enclosure_id,e.article_id,a.feed_id,a.title,f.title,a.published_at,s.added_at,e.url,e.mime_type,e.remote_present,(SELECT duration_ms FROM media_metadata m WHERE m.enclosure_id=e.id),(SELECT e2.url FROM enclosures e2 WHERE e2.article_id=e.article_id AND lower(e2.mime_type) LIKE 'image/%' ORDER BY e2.id LIMIT 1),(SELECT m.embedded_artwork_reference FROM media_metadata m WHERE m.enclosure_id=e.id),a.image_url FROM saved_media s JOIN enclosures e ON e.id=s.enclosure_id JOIN articles a ON a.id=e.article_id JOIN feeds f ON f.id=a.feed_id ORDER BY s.added_at DESC,s.enclosure_id DESC"
        };
        let mut statement = connection.prepare(sql).map_err(sql_error)?;
        let rows = if let Some(feed_id) = feed_id {
            statement.query_map([feed_id], saved_playable_media_from_row)
        } else {
            statement.query_map([], saved_playable_media_from_row)
        }
        .map_err(sql_error)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(sql_error)?;
        Ok(rows
            .into_iter()
            .filter(|item| {
                matches!(
                    item.media_kind,
                    crate::domain::MediaKind::Audio | crate::domain::MediaKind::Video
                )
            })
            .collect())
    }

    pub fn feed_system_notification_settings(
        &self,
    ) -> Result<Vec<FeedSystemNotificationSetting>, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let mut statement = connection.prepare("SELECT f.id,f.title,COALESCE(p.system_notifications_enabled,0) FROM feeds f LEFT JOIN feed_preferences p ON p.feed_id=f.id ORDER BY f.category_id,f.title COLLATE NOCASE,f.id").map_err(sql_error)?;
        statement
            .query_map([], |row| {
                Ok(FeedSystemNotificationSetting {
                    feed_id: row.get(0)?,
                    feed_title: row.get(1)?,
                    system_notifications_enabled: row.get(2)?,
                })
            })
            .map_err(sql_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(sql_error)
    }

    pub fn set_feed_system_notifications_enabled(
        &self,
        feed_id: i64,
        enabled: bool,
    ) -> Result<(), CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        if tx
            .query_row("SELECT 1 FROM feeds WHERE id=?1", [feed_id], |_| Ok(()))
            .optional()
            .map_err(sql_error)?
            .is_none()
        {
            return Err(CoreError::data(format!("feed {feed_id} does not exist")));
        }
        tx.execute(
            "INSERT INTO feed_preferences(feed_id,system_notifications_enabled) VALUES(?1,?2) ON CONFLICT(feed_id) DO UPDATE SET system_notifications_enabled=excluded.system_notifications_enabled",
            params![feed_id, enabled],
        )
        .map_err(sql_error)?;

        // Toggling notification delivery establishes a new delivery baseline.
        // Never release articles that were queued before the user's current choice.
        tx.execute(
            "DELETE FROM pending_system_notifications WHERE article_id IN (SELECT id FROM articles WHERE feed_id=?1)",
            [feed_id],
        )
        .map_err(sql_error)?;
        tx.execute(
            "DELETE FROM system_notification_candidates WHERE feed_id=?1",
            [feed_id],
        )
        .map_err(sql_error)?;
        if enabled {
            // Establish a durable baseline: replayed IDs from an earlier sync may not
            // generate notifications after the user enables delivery.
            tx.execute(
                "INSERT INTO system_notified_articles(article_id) SELECT id FROM articles WHERE feed_id=?1 ON CONFLICT(article_id) DO NOTHING",
                [feed_id],
            )
            .map_err(sql_error)?;
        }
        tx.commit().map_err(sql_error)
    }

    pub fn feed_preferences_bulk(
        &self,
        feed_ids: &[i64],
    ) -> Result<Vec<FeedPreferences>, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let mut preferences = Vec::with_capacity(feed_ids.len());
        for &feed_id in feed_ids {
            let exists = connection
                .query_row("SELECT 1 FROM feeds WHERE id=?1", [feed_id], |_| Ok(()))
                .optional()
                .map_err(sql_error)?
                .is_some();
            if !exists {
                return Err(CoreError::data(format!("feed {feed_id} does not exist")));
            }
            let preference = connection
                .query_row(
                    "SELECT system_notifications_enabled,detail_rendering,truncate_detail,open_in_miniflux,auto_download_audio FROM feed_preferences WHERE feed_id=?1",
                    [feed_id],
                    |row| {
                        Ok(FeedPreferences {
                            feed_id,
                            system_notifications_enabled: row.get(0)?,
                            detail_rendering: match row.get::<_, String>(1)?.as_str() {
                                "rendered" => DetailRenderingMode::Rendered,
                                "text_only" => DetailRenderingMode::TextOnly,
                                _ => return Err(rusqlite::Error::InvalidQuery),
                            },
                            truncate_detail: row.get(2)?,
                            open_in_miniflux: row.get(3)?,
                            auto_download_audio: row.get(4)?,
                        })
                    },
                )
                .optional()
                .map_err(sql_error)?
                .unwrap_or_else(|| FeedPreferences::defaults(feed_id));
            preferences.push(preference);
        }
        Ok(preferences)
    }

    pub fn patch_feed_preferences_bulk(
        &self,
        feed_ids: &[i64],
        patch: FeedPreferencesPatch,
    ) -> Result<(), CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;

        for &feed_id in feed_ids {
            if tx
                .query_row("SELECT 1 FROM feeds WHERE id=?1", [feed_id], |_| Ok(()))
                .optional()
                .map_err(sql_error)?
                .is_none()
            {
                return Err(CoreError::data(format!("feed {feed_id} does not exist")));
            }
        }

        for &feed_id in feed_ids {
            if let Some(enabled) = patch.system_notifications_enabled {
                tx.execute(
                    "INSERT INTO feed_preferences(feed_id,system_notifications_enabled) VALUES(?1,?2) ON CONFLICT(feed_id) DO UPDATE SET system_notifications_enabled=excluded.system_notifications_enabled",
                    params![feed_id, enabled],
                )
                .map_err(sql_error)?;
                tx.execute(
                    "DELETE FROM pending_system_notifications WHERE article_id IN (SELECT id FROM articles WHERE feed_id=?1)",
                    [feed_id],
                )
                .map_err(sql_error)?;
                tx.execute(
                    "DELETE FROM system_notification_candidates WHERE feed_id=?1",
                    [feed_id],
                )
                .map_err(sql_error)?;
                if enabled {
                    // Match single-feed toggles: previously visible articles are
                    // already part of the baseline, even if sync replays their IDs.
                    tx.execute(
                        "INSERT INTO system_notified_articles(article_id) SELECT id FROM articles WHERE feed_id=?1 ON CONFLICT(article_id) DO NOTHING",
                        [feed_id],
                    )
                    .map_err(sql_error)?;
                }
            }
            if let Some(mode) = patch.detail_rendering {
                tx.execute(
                    "INSERT INTO feed_preferences(feed_id,detail_rendering) VALUES(?1,?2) ON CONFLICT(feed_id) DO UPDATE SET detail_rendering=excluded.detail_rendering",
                    params![
                        feed_id,
                        match mode {
                            DetailRenderingMode::Rendered => "rendered",
                            DetailRenderingMode::TextOnly => "text_only",
                        }
                    ],
                )
                .map_err(sql_error)?;
            }
            if let Some(enabled) = patch.truncate_detail {
                tx.execute(
                    "INSERT INTO feed_preferences(feed_id,truncate_detail) VALUES(?1,?2) ON CONFLICT(feed_id) DO UPDATE SET truncate_detail=excluded.truncate_detail",
                    params![feed_id, enabled],
                )
                .map_err(sql_error)?;
            }
            if let Some(enabled) = patch.open_in_miniflux {
                tx.execute(
                    "INSERT INTO feed_preferences(feed_id,open_in_miniflux) VALUES(?1,?2) ON CONFLICT(feed_id) DO UPDATE SET open_in_miniflux=excluded.open_in_miniflux",
                    params![feed_id, enabled],
                )
                .map_err(sql_error)?;
                tx.execute(
                    "INSERT INTO feed_open_in_miniflux_overrides(feed_id) VALUES(?1) ON CONFLICT(feed_id) DO NOTHING",
                    [feed_id],
                )
                .map_err(sql_error)?;
            }
            if let Some(enabled) = patch.auto_download_audio {
                tx.execute(
                    "INSERT INTO feed_preferences(feed_id,auto_download_audio) VALUES(?1,?2) ON CONFLICT(feed_id) DO UPDATE SET auto_download_audio=excluded.auto_download_audio",
                    params![feed_id, enabled],
                )
                .map_err(sql_error)?;
            }
        }

        tx.commit().map_err(sql_error)
    }

    pub fn feed_preferences(&self, feed_id: i64) -> Result<FeedPreferences, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        connection.query_row("SELECT system_notifications_enabled,detail_rendering,truncate_detail,open_in_miniflux,auto_download_audio FROM feed_preferences WHERE feed_id=?1", [feed_id], |row| {
            Ok(FeedPreferences {
                feed_id,
                system_notifications_enabled: row.get(0)?,
                detail_rendering: match row.get::<_, String>(1)?.as_str() {
                    "rendered" => DetailRenderingMode::Rendered,
                    "text_only" => DetailRenderingMode::TextOnly,
                    _ => return Err(rusqlite::Error::InvalidQuery),
                },
                truncate_detail: row.get(2)?,
                open_in_miniflux: row.get(3)?,
                auto_download_audio: row.get(4)?,
            })
        }).optional().map_err(sql_error)?.map_or_else(|| {
            let exists = connection.query_row("SELECT 1 FROM feeds WHERE id=?1", [feed_id], |_| Ok(())).optional().map_err(sql_error)?.is_some();
            if exists { Ok(FeedPreferences::defaults(feed_id)) } else { Err(CoreError::data(format!("feed {feed_id} does not exist"))) }
        }, Ok)
    }

    pub fn set_feed_detail_rendering(
        &self,
        feed_id: i64,
        mode: DetailRenderingMode,
    ) -> Result<(), CoreError> {
        self.set_feed_preference(
            feed_id,
            "detail_rendering",
            match mode {
                DetailRenderingMode::Rendered => "rendered",
                DetailRenderingMode::TextOnly => "text_only",
            },
        )
    }
    pub fn set_feed_truncate_detail(&self, feed_id: i64, enabled: bool) -> Result<(), CoreError> {
        self.set_feed_preference(feed_id, "truncate_detail", if enabled { "1" } else { "0" })
    }
    pub fn set_feed_open_in_miniflux(&self, feed_id: i64, enabled: bool) -> Result<(), CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        let exists = tx
            .query_row("SELECT 1 FROM feeds WHERE id=?1", [feed_id], |_| Ok(()))
            .optional()
            .map_err(sql_error)?
            .is_some();
        if !exists {
            return Err(CoreError::data(format!("feed {feed_id} does not exist")));
        }
        tx.execute("INSERT INTO feed_preferences(feed_id,open_in_miniflux) VALUES(?1,?2) ON CONFLICT(feed_id) DO UPDATE SET open_in_miniflux=excluded.open_in_miniflux", params![feed_id, enabled]).map_err(sql_error)?;
        tx.execute("INSERT INTO feed_open_in_miniflux_overrides(feed_id) VALUES(?1) ON CONFLICT(feed_id) DO NOTHING", [feed_id]).map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
        Ok(())
    }
    pub fn import_legacy_feed_open_in_miniflux(
        &self,
        feed_id: i64,
    ) -> Result<LegacyFeedOpenInMinifluxImportOutcome, CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        let exists = tx
            .query_row("SELECT 1 FROM feeds WHERE id=?1", [feed_id], |_| Ok(()))
            .optional()
            .map_err(sql_error)?
            .is_some();
        if !exists {
            return Ok(LegacyFeedOpenInMinifluxImportOutcome::MissingFeed);
        }
        let native_override_exists = tx
            .query_row(
                "SELECT 1 FROM feed_open_in_miniflux_overrides WHERE feed_id=?1",
                [feed_id],
                |_| Ok(()),
            )
            .optional()
            .map_err(sql_error)?
            .is_some();
        if native_override_exists {
            return Ok(LegacyFeedOpenInMinifluxImportOutcome::AlreadyPresent);
        }
        tx.execute("INSERT INTO feed_preferences(feed_id,open_in_miniflux) VALUES(?1,1) ON CONFLICT(feed_id) DO UPDATE SET open_in_miniflux=1", [feed_id]).map_err(sql_error)?;
        tx.execute(
            "INSERT INTO feed_open_in_miniflux_overrides(feed_id) VALUES(?1)",
            [feed_id],
        )
        .map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
        Ok(LegacyFeedOpenInMinifluxImportOutcome::Imported)
    }
    pub fn set_feed_auto_download_audio(
        &self,
        feed_id: i64,
        enabled: bool,
    ) -> Result<(), CoreError> {
        self.set_feed_preference(
            feed_id,
            "auto_download_audio",
            if enabled { "1" } else { "0" },
        )
    }
    fn set_feed_preference(
        &self,
        feed_id: i64,
        column: &str,
        value: &str,
    ) -> Result<(), CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let exists = connection
            .query_row("SELECT 1 FROM feeds WHERE id=?1", [feed_id], |_| Ok(()))
            .optional()
            .map_err(sql_error)?
            .is_some();
        if !exists {
            return Err(CoreError::data(format!("feed {feed_id} does not exist")));
        }
        let sql = format!(
            "INSERT INTO feed_preferences(feed_id,{column}) VALUES(?1,?2) ON CONFLICT(feed_id) DO UPDATE SET {column}=excluded.{column}"
        );
        connection
            .execute(&sql, params![feed_id, value])
            .map_err(sql_error)?;
        Ok(())
    }

    pub fn prepare_system_notification_candidates(
        &self,
        new_article_ids_by_feed: &BTreeMap<i64, Vec<i64>>,
    ) -> Result<Vec<SystemNotificationCandidate>, CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        for article_ids in new_article_ids_by_feed.values() {
            for article_id in article_ids {
                tx.execute(
                    "INSERT INTO pending_system_notifications(article_id)
                     SELECT a.id
                     FROM articles a
                     JOIN feed_preferences p ON p.feed_id=a.feed_id
                     WHERE a.id=?1 AND p.system_notifications_enabled=1
                     ON CONFLICT(article_id) DO NOTHING",
                    [article_id],
                )
                .map_err(sql_error)?;
            }
        }
        let feeds = {
            let mut statement = tx.prepare("SELECT f.id,f.title FROM feeds f JOIN feed_preferences p ON p.feed_id=f.id WHERE p.system_notifications_enabled=1 ORDER BY f.id").map_err(sql_error)?;
            statement
                .query_map([], |row| {
                    Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?))
                })
                .map_err(sql_error)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(sql_error)?
        };
        let mut candidates = Vec::new();
        for (feed_id, feed_title) in feeds {
            let article_ids = {
                let mut statement = tx.prepare("SELECT p.article_id FROM pending_system_notifications p JOIN articles a ON a.id=p.article_id WHERE a.feed_id=?1 AND NOT EXISTS(SELECT 1 FROM system_notified_articles n WHERE n.article_id=p.article_id) ORDER BY p.article_id").map_err(sql_error)?;
                statement
                    .query_map([feed_id], |row| row.get::<_, i64>(0))
                    .map_err(sql_error)?
                    .collect::<Result<Vec<_>, _>>()
                    .map_err(sql_error)?
            };
            if article_ids.is_empty() {
                continue;
            }
            tx.execute(
                "INSERT INTO system_notification_candidates(feed_id,feed_title) VALUES(?1,?2)",
                params![feed_id, feed_title],
            )
            .map_err(sql_error)?;
            let candidate_id = tx.last_insert_rowid();
            for article_id in &article_ids {
                tx.execute("INSERT INTO notification_candidate_articles(candidate_id,article_id) VALUES(?1,?2)", params![candidate_id, article_id]).map_err(sql_error)?;
            }
            candidates.push(SystemNotificationCandidate {
                candidate_id,
                feed_id,
                feed_title,
                new_count: article_ids.len() as u32,
            });
        }
        tx.commit().map_err(sql_error)?;
        Ok(candidates)
    }

    pub fn acknowledge_system_notification(&self, candidate_id: i64) -> Result<(), CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        let exists = tx
            .query_row(
                "SELECT 1 FROM system_notification_candidates WHERE id=?1",
                [candidate_id],
                |_| Ok(()),
            )
            .optional()
            .map_err(sql_error)?
            .is_some();
        if !exists {
            return Ok(());
        }
        tx.execute("INSERT INTO system_notified_articles(article_id) SELECT article_id FROM notification_candidate_articles WHERE candidate_id=?1 ON CONFLICT(article_id) DO NOTHING", [candidate_id]).map_err(sql_error)?;
        tx.execute("DELETE FROM pending_system_notifications WHERE article_id IN (SELECT article_id FROM notification_candidate_articles WHERE candidate_id=?1)", [candidate_id]).map_err(sql_error)?;
        tx.execute(
            "DELETE FROM system_notification_candidates WHERE id=?1",
            [candidate_id],
        )
        .map_err(sql_error)?;
        tx.execute("DELETE FROM system_notification_candidates WHERE NOT EXISTS(SELECT 1 FROM notification_candidate_articles ca WHERE ca.candidate_id=system_notification_candidates.id AND NOT EXISTS(SELECT 1 FROM system_notified_articles n WHERE n.article_id=ca.article_id))", []).map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
        Ok(())
    }

    pub fn cleanup_expired_read_articles(&self, cutoff: &str) -> Result<u32, CoreError> {
        let deleted = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?
            .execute(
                "DELETE FROM articles WHERE is_read=1 AND is_starred=0 AND published_at < ?1 AND NOT EXISTS(SELECT 1 FROM listening_list l WHERE l.article_id=articles.id) AND NOT EXISTS(SELECT 1 FROM saved_media s JOIN enclosures e ON e.id=s.enclosure_id WHERE e.article_id=articles.id) AND NOT EXISTS(SELECT 1 FROM playback_states p JOIN enclosures e ON e.id=p.enclosure_id WHERE e.article_id=articles.id AND p.status='in_progress') AND NOT EXISTS(SELECT 1 FROM pending_media_progress_mutations m JOIN enclosures e ON e.id=m.enclosure_id WHERE e.article_id=articles.id) AND NOT EXISTS(SELECT 1 FROM media_downloads d JOIN enclosures e ON e.id=d.enclosure_id WHERE e.article_id=articles.id AND d.state IN ('requested','downloaded'))",
                [cutoff],
            )
            .map_err(sql_error)?;
        Ok(deleted as u32)
    }

    pub fn local_article_state(
        &self,
        article_id: i64,
    ) -> Result<Option<LocalArticleState>, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        connection
            .query_row(
                "SELECT is_read,is_starred FROM articles WHERE id=?1",
                [article_id],
                |row| {
                    Ok(LocalArticleState {
                        is_read: row.get(0)?,
                        is_starred: row.get(1)?,
                    })
                },
            )
            .optional()
            .map_err(sql_error)
    }
    pub(crate) fn reader_article(&self, article_id: i64) -> Result<ReaderArticle, CoreError> {
        self.connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?
            .query_row(
                "SELECT feed_id,url,raw_html_content,image_url FROM articles WHERE id=?1",
                [article_id],
                |row| {
                    Ok(ReaderArticle {
                        feed_id: row.get(0)?,
                        url: row.get(1)?,
                        raw_html_content: row.get(2)?,
                        image_url: row.get(3)?,
                    })
                },
            )
            .optional()
            .map_err(sql_error)?
            .ok_or_else(|| CoreError::data(format!("article {article_id} does not exist")))
    }

    pub fn set_state_bulk(
        &self,
        article_ids: &[i64],
        field: MutationField,
        desired: bool,
    ) -> Result<Vec<PendingMutation>, CoreError> {
        let mut ids = article_ids.to_vec();
        ids.sort_unstable();
        ids.dedup();
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        let field_name = field_name(field);
        let mut pending = Vec::with_capacity(ids.len());
        for id in ids {
            let column = match field {
                MutationField::Read => "is_read",
                MutationField::Starred => "is_starred",
            };
            if tx
                .execute(
                    &format!("UPDATE articles SET {column}=?1 WHERE id=?2"),
                    params![desired, id],
                )
                .map_err(sql_error)?
                == 0
            {
                return Err(CoreError::data(format!("article {id} does not exist")));
            }
            tx.execute("INSERT INTO pending_mutations(article_id,field,desired,revision) VALUES(?1,?2,?3,1) ON CONFLICT(article_id,field) DO UPDATE SET desired=excluded.desired,revision=pending_mutations.revision+1",params![id,field_name,desired]).map_err(sql_error)?;
            let revision = tx
                .query_row(
                    "SELECT revision FROM pending_mutations WHERE article_id=?1 AND field=?2",
                    params![id, field_name],
                    |r| r.get(0),
                )
                .map_err(sql_error)?;
            pending.push(PendingMutation {
                article_id: id,
                field,
                desired,
                revision,
            });
        }
        tx.commit().map_err(sql_error)?;
        Ok(pending)
    }
    pub fn pending_mutations(&self) -> Result<Vec<PendingMutation>, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let mut statement=connection.prepare("SELECT article_id,field,desired,revision FROM pending_mutations ORDER BY article_id,field").map_err(sql_error)?;
        statement
            .query_map([], |r| {
                Ok(PendingMutation {
                    article_id: r.get(0)?,
                    field: parse_field(r.get::<_, String>(1)?.as_str())?,
                    desired: r.get(2)?,
                    revision: r.get(3)?,
                })
            })
            .map_err(sql_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(sql_error)
    }

    pub fn pending_media_progress_mutations(
        &self,
    ) -> Result<Vec<PendingMediaProgressMutation>, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let mut statement = connection.prepare("SELECT enclosure_id,progression_seconds,revision FROM pending_media_progress_mutations ORDER BY enclosure_id").map_err(sql_error)?;
        statement
            .query_map([], |row| {
                Ok(PendingMediaProgressMutation {
                    enclosure_id: row.get(0)?,
                    progression_seconds: u64::try_from(row.get::<_, i64>(1)?)
                        .map_err(|_| rusqlite::Error::InvalidQuery)?,
                    revision: row.get(2)?,
                })
            })
            .map_err(sql_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(sql_error)
    }

    pub fn acknowledge_media_progress(
        &self,
        pending: &PendingMediaProgressMutation,
    ) -> Result<bool, CoreError> {
        let progression_seconds = i64::try_from(pending.progression_seconds)
            .map_err(|_| CoreError::data("media progression exceeds SQLite integer range"))?;
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        tx.execute(
            "UPDATE enclosures SET remote_media_progression_seconds=?1 WHERE id=?2",
            params![progression_seconds, pending.enclosure_id],
        )
        .map_err(sql_error)?;
        let deleted = tx.execute("DELETE FROM pending_media_progress_mutations WHERE enclosure_id=?1 AND progression_seconds=?2 AND revision=?3", params![pending.enclosure_id, progression_seconds, pending.revision]).map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
        Ok(deleted == 1)
    }
    /// Removes one obsolete remote delivery intent without changing local playback or its remote baseline.
    pub fn discard_media_progress(
        &self,
        pending: &PendingMediaProgressMutation,
    ) -> Result<bool, CoreError> {
        let progression_seconds = i64::try_from(pending.progression_seconds)
            .map_err(|_| CoreError::data("media progression exceeds SQLite integer range"))?;
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let deleted = connection
            .execute(
                "DELETE FROM pending_media_progress_mutations WHERE enclosure_id=?1 AND progression_seconds=?2 AND revision=?3",
                params![pending.enclosure_id, progression_seconds, pending.revision],
            )
            .map_err(sql_error)?;
        Ok(deleted == 1)
    }
    pub fn acknowledge(&self, pending: &PendingMutation) -> Result<bool, CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        let remote_column = match pending.field {
            MutationField::Read => "remote_is_read",
            MutationField::Starred => "remote_is_starred",
        };
        tx.execute(
            &format!("UPDATE articles SET {remote_column}=?1 WHERE id=?2"),
            params![pending.desired, pending.article_id],
        )
        .map_err(sql_error)?;
        let deleted = tx
            .execute(
                "DELETE FROM pending_mutations WHERE article_id=?1 AND field=?2 AND revision=?3",
                params![
                    pending.article_id,
                    field_name(pending.field),
                    pending.revision
                ],
            )
            .map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
        Ok(deleted == 1)
    }

    pub fn mark_sync_success(&self) -> Result<(), CoreError> {
        self.connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?
            .execute(
                "INSERT INTO core_settings (key,value) VALUES ('last_successful_sync_at',datetime('now')) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                [],
            )
            .map_err(sql_error)?;
        Ok(())
    }
    pub fn last_successful_sync_at(&self) -> Result<Option<String>, CoreError> {
        self.connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?
            .query_row(
                "SELECT value FROM core_settings WHERE key='last_successful_sync_at'",
                [],
                |row| row.get(0),
            )
            .optional()
            .map_err(sql_error)
    }

    pub fn delta_sync_cursor(&self) -> Result<Option<i64>, CoreError> {
        self.connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?
            .query_row(
                "SELECT value FROM core_settings WHERE key='delta_sync_cursor'",
                [],
                |row| row.get::<_, String>(0),
            )
            .optional()
            .map_err(sql_error)?
            .map(|value| {
                value
                    .parse::<i64>()
                    .map_err(|_| CoreError::persistence("invalid delta sync cursor"))
            })
            .transpose()
    }

    pub fn last_full_sync_at(&self) -> Result<Option<String>, CoreError> {
        self.connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?
            .query_row(
                "SELECT value FROM core_settings WHERE key='last_full_sync_at'",
                [],
                |row| row.get(0),
            )
            .optional()
            .map_err(sql_error)
    }

    #[cfg(test)]
    pub(crate) fn set_last_full_sync_at_for_testing(&self, value: &str) -> Result<(), CoreError> {
        self.connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?
            .execute(
                "INSERT INTO core_settings(key,value) VALUES('last_full_sync_at',?1) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                [value],
            )
            .map_err(sql_error)?;
        Ok(())
    }

    pub fn full_sync_required(&self) -> Result<bool, CoreError> {
        let value: Option<String> = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?
            .query_row(
                "SELECT value FROM core_settings WHERE key='full_sync_required'",
                [],
                |row| row.get(0),
            )
            .optional()
            .map_err(sql_error)?;
        match value.as_deref() {
            None | Some("0") => Ok(false),
            Some("1") => Ok(true),
            Some(_) => Err(CoreError::persistence("invalid full sync required setting")),
        }
    }
    pub fn full_sync_due(&self, max_age_hours: i64) -> Result<bool, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let due: bool = connection
            .query_row(
                "SELECT NOT EXISTS(SELECT 1 FROM core_settings WHERE key='last_full_sync_at') OR EXISTS(SELECT 1 FROM core_settings WHERE key='last_full_sync_at' AND datetime(value) <= datetime('now', ?1))",
                [format!("-{max_age_hours} hours")],
                |row| row.get(0),
            )
            .map_err(sql_error)?;
        Ok(due)
    }

    pub fn successful_sync_due(&self, max_age_minutes: i64) -> Result<bool, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let due: bool = connection
            .query_row(
                "SELECT NOT EXISTS(SELECT 1 FROM core_settings WHERE key='last_successful_sync_at') OR EXISTS(SELECT 1 FROM core_settings WHERE key='last_successful_sync_at' AND datetime(value) <= datetime('now', ?1))",
                [format!("-{max_age_minutes} minutes")],
                |row| row.get(0),
            )
            .map_err(sql_error)?;
        Ok(due)
    }

    pub fn mark_full_sync_required(&self, reason: &str) -> Result<(), CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        connection
            .execute(
                "INSERT INTO core_settings(key,value) VALUES('full_sync_required','1') ON CONFLICT(key) DO UPDATE SET value='1'",
                [],
            )
            .map_err(sql_error)?;
        connection
            .execute(
                "INSERT INTO core_settings(key,value) VALUES('full_sync_reason',?1) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                [reason],
            )
            .map_err(sql_error)?;
        Ok(())
    }

    pub fn commit_delta_sync_success(&self, cursor: i64) -> Result<(), CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        tx.execute(
            "INSERT INTO core_settings(key,value) VALUES('delta_sync_cursor',?1) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            [cursor.to_string()],
        )
        .map_err(sql_error)?;
        tx.execute(
            "INSERT INTO core_settings(key,value) VALUES('last_successful_sync_at',datetime('now')) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            [],
        )
        .map_err(sql_error)?;
        tx.commit().map_err(sql_error)
    }

    pub fn commit_full_sync_success(&self, delta_cursor: Option<i64>) -> Result<(), CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        if let Some(delta_cursor) = delta_cursor {
            tx.execute(
                "INSERT INTO core_settings(key,value) VALUES('delta_sync_cursor',?1) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                [delta_cursor.to_string()],
            )
            .map_err(sql_error)?;
            tx.execute(
                "INSERT INTO core_settings(key,value) VALUES('full_sync_required','0') ON CONFLICT(key) DO UPDATE SET value='0'",
                [],
            )
            .map_err(sql_error)?;
            tx.execute("DELETE FROM core_settings WHERE key='full_sync_reason'", [])
                .map_err(sql_error)?;
        } else {
            tx.execute(
                "DELETE FROM core_settings WHERE key='delta_sync_cursor'",
                [],
            )
            .map_err(sql_error)?;
            tx.execute(
                "INSERT INTO core_settings(key,value) VALUES('full_sync_required','1') ON CONFLICT(key) DO UPDATE SET value='1'",
                [],
            )
            .map_err(sql_error)?;
            tx.execute(
                "INSERT INTO core_settings(key,value) VALUES('full_sync_reason','missing_delta_baseline') ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                [],
            )
            .map_err(sql_error)?;
        }
        tx.execute(
            "INSERT INTO core_settings(key,value) VALUES('last_successful_sync_at',datetime('now')) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            [],
        )
        .map_err(sql_error)?;
        tx.execute(
            "INSERT INTO core_settings(key,value) VALUES('last_full_sync_at',datetime('now')) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            [],
        )
        .map_err(sql_error)?;
        tx.commit().map_err(sql_error)
    }

    pub fn reconcile_delta_articles(
        &self,
        articles: &[Article],
        enclosures: &[Enclosure],
        media_progress_writes: &HashMap<i64, u64>,
    ) -> Result<(ReconciliationStats, Vec<i64>), CoreError> {
        let mut connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let tx = connection.transaction().map_err(sql_error)?;
        let mut stats = ReconciliationStats::default();
        let mut skipped_unknown_feeds = Vec::new();
        let mut accepted_article_ids = HashSet::new();

        for article in articles {
            let feed_exists: bool = tx
                .query_row(
                    "SELECT EXISTS(SELECT 1 FROM feeds WHERE id=?1)",
                    [article.feed_id],
                    |row| row.get(0),
                )
                .map_err(sql_error)?;
            if !feed_exists {
                skipped_unknown_feeds.push(article.feed_id);
                continue;
            }

            accepted_article_ids.insert(article.id);
            let existing = tx
                .query_row(
                    "SELECT feed_id,title,url,comments_url,published_at,remote_is_read,remote_is_starred,raw_html_content,reading_time_minutes,preview,image_url FROM articles WHERE id=?1",
                    [article.id],
                    |row| {
                        Ok((
                            row.get::<_, i64>(0)?,
                            row.get::<_, String>(1)?,
                            row.get::<_, String>(2)?,
                            row.get::<_, String>(3)?,
                            row.get::<_, String>(4)?,
                            row.get::<_, bool>(5)?,
                            row.get::<_, bool>(6)?,
                            row.get::<_, String>(7)?,
                            row.get::<_, u32>(8)?,
                            row.get::<_, String>(9)?,
                            row.get::<_, Option<String>>(10)?,
                        ))
                    },
                )
                .optional()
                .map_err(sql_error)?;

            match existing {
                None => {
                    stats.new_articles += 1;
                    stats
                        .new_article_ids_by_feed
                        .entry(article.feed_id)
                        .or_default()
                        .push(article.id);
                }
                Some(existing)
                    if existing
                        != (
                            article.feed_id,
                            article.title.clone(),
                            article.url.clone(),
                            article.comments_url.clone(),
                            article.published_at.clone(),
                            article.is_read,
                            article.is_starred,
                            article.raw_html_content.clone(),
                            article.reading_time_minutes,
                            article.preview.clone(),
                            article.image_url.clone(),
                        ) =>
                {
                    stats.updated_articles += 1;
                }
                Some(_) => {}
            }

            tx.execute(
                "INSERT INTO articles (id,feed_id,title,url,comments_url,published_at,is_read,is_starred,remote_is_read,remote_is_starred,raw_html_content,reading_time_minutes,preview,image_url,content_processing_version) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?7,?8,?9,?10,?11,?12,?13) ON CONFLICT(id) DO UPDATE SET feed_id=excluded.feed_id,title=excluded.title,url=excluded.url,comments_url=excluded.comments_url,published_at=excluded.published_at,remote_is_read=excluded.remote_is_read,remote_is_starred=excluded.remote_is_starred,is_read=CASE WHEN EXISTS(SELECT 1 FROM pending_mutations p WHERE p.article_id=excluded.id AND p.field='read') THEN articles.is_read ELSE excluded.is_read END,is_starred=CASE WHEN EXISTS(SELECT 1 FROM pending_mutations p WHERE p.article_id=excluded.id AND p.field='starred') THEN articles.is_starred ELSE excluded.is_starred END,raw_html_content=excluded.raw_html_content,reading_time_minutes=excluded.reading_time_minutes,preview=excluded.preview,image_url=excluded.image_url,content_processing_version=excluded.content_processing_version",
                params![
                    article.id,
                    article.feed_id,
                    article.title,
                    article.url,
                    article.comments_url,
                    article.published_at,
                    article.is_read,
                    article.is_starred,
                    article.raw_html_content,
                    article.reading_time_minutes,
                    article.preview,
                    article.image_url,
                    crate::article::PROCESSING_VERSION
                ],
            )
            .map_err(sql_error)?;
        }

        let accepted_enclosures = enclosures
            .iter()
            .filter(|enclosure| accepted_article_ids.contains(&enclosure.article_id))
            .cloned()
            .collect::<Vec<_>>();
        let accepted_articles = articles
            .iter()
            .filter(|article| accepted_article_ids.contains(&article.id))
            .cloned()
            .collect::<Vec<_>>();

        let new_live_enclosures = accepted_enclosures
            .iter()
            .filter(|enclosure| {
                !tx.query_row(
                    "SELECT EXISTS(SELECT 1 FROM enclosures WHERE id=?1)",
                    [enclosure.id],
                    |row| row.get(0),
                )
                .unwrap_or(true)
            })
            .map(|enclosure| enclosure.id)
            .collect::<Vec<_>>();

        reconcile_remote_enclosures(
            &tx,
            &accepted_articles,
            &accepted_enclosures,
            media_progress_writes,
        )?;

        let mut auto_download_articles = HashSet::new();
        for enclosure_id in new_live_enclosures {
            let article_id: i64 = tx
                .query_row(
                    "SELECT article_id FROM enclosures WHERE id=?1",
                    [enclosure_id],
                    |row| row.get(0),
                )
                .map_err(sql_error)?;
            let enabled: bool = tx
                .query_row(
                    "SELECT EXISTS(SELECT 1 FROM articles a JOIN feed_preferences p ON p.feed_id=a.feed_id WHERE a.id=?1 AND p.auto_download_audio=1)",
                    [article_id],
                    |row| row.get(0),
                )
                .map_err(sql_error)?;
            if enabled && is_audio_enclosure(&tx, enclosure_id)? {
                auto_download_articles.insert(article_id);
            }
        }
        for article_id in auto_download_articles {
            ensure_listening_membership(&tx, article_id, &Utc::now().to_rfc3339())?;
            for enclosure_id in audio_enclosure_ids_for_article(&tx, article_id)? {
                let suppressed: bool = tx
                    .query_row(
                        "SELECT EXISTS(SELECT 1 FROM auto_download_suppressions WHERE enclosure_id=?1)",
                        [enclosure_id],
                        |row| row.get(0),
                    )
                    .map_err(sql_error)?;
                if !suppressed {
                    request_download_in_transaction(&tx, enclosure_id, DownloadOrigin::Automatic)?;
                }
            }
        }

        skipped_unknown_feeds.sort_unstable();
        skipped_unknown_feeds.dedup();
        tx.commit().map_err(sql_error)?;
        Ok((stats, skipped_unknown_feeds))
    }
    pub fn navigation_catalog(&self) -> Result<NavigationCatalog, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        self.navigation_catalog_locked(&connection)
    }
    /// Holds the Store connection lock through catalog and aggregate reads so a
    /// concurrent local mutation or reconciliation cannot mix their states.
    pub fn navigation_projection(
        &self,
        count_mode: NavigationCountMode,
    ) -> Result<NavigationProjection, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let catalog = self.navigation_catalog_locked(&connection)?;
        let (unread_total, starred_total) = connection
            .query_row(
                "SELECT \
                    COALESCE(SUM(CASE WHEN is_read=0 THEN 1 ELSE 0 END),0), \
                    COALESCE(SUM(CASE WHEN is_starred=1 THEN 1 ELSE 0 END),0) \
                 FROM articles",
                [],
                |row| Ok((row_u64(row, 0)?, row_u64(row, 1)?)),
            )
            .map_err(sql_error)?;
        let (feed_sql, category_sql) = match count_mode {
            NavigationCountMode::Unread => (
                "SELECT f.id,COUNT(a.id) FROM feeds f \
                 LEFT JOIN articles a ON a.feed_id=f.id AND a.is_read=0 \
                 GROUP BY f.id ORDER BY f.id",
                "SELECT c.id,COUNT(a.id) FROM categories c \
                 LEFT JOIN feeds f ON f.category_id=c.id \
                 LEFT JOIN articles a ON a.feed_id=f.id AND a.is_read=0 \
                 GROUP BY c.id ORDER BY c.id",
            ),
            NavigationCountMode::All => (
                "SELECT f.id,COUNT(a.id) FROM feeds f \
                 LEFT JOIN articles a ON a.feed_id=f.id \
                 GROUP BY f.id ORDER BY f.id",
                "SELECT c.id,COUNT(a.id) FROM categories c \
                 LEFT JOIN feeds f ON f.category_id=c.id \
                 LEFT JOIN articles a ON a.feed_id=f.id \
                 GROUP BY c.id ORDER BY c.id",
            ),
        };
        Ok(NavigationProjection {
            catalog,
            unread_total,
            starred_total,
            category_counts: navigation_scoped_counts(&connection, category_sql)?,
            feed_counts: navigation_scoped_counts(&connection, feed_sql)?,
        })
    }
    pub fn count_articles(&self, query: &ArticleQuery) -> Result<u64, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        Self::count_articles_locked(&connection, query)
    }
    pub fn query_articles(&self, query: &ArticleQuery) -> Result<Vec<ArticleSummary>, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        Self::query_articles_locked(&connection, query)
    }

    pub fn article_summary(&self, article_id: i64) -> Result<Option<ArticleSummary>, CoreError> {
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        connection
            .query_row(
                "SELECT a.id,a.feed_id,f.category_id,f.title,a.title,a.url,a.comments_url,a.published_at,a.is_read,a.is_starred,a.reading_time_minutes,a.preview,a.image_url FROM articles a JOIN feeds f ON f.id=a.feed_id WHERE a.id=?1",
                [article_id],
                |r| {
                    Ok(ArticleSummary {
                        id: r.get(0)?,
                        feed_id: r.get(1)?,
                        category_id: r.get(2)?,
                        feed_title: r.get(3)?,
                        title: r.get(4)?,
                        url: r.get(5)?,
                        comments_url: r.get(6)?,
                        published_at: r.get(7)?,
                        is_read: r.get(8)?,
                        is_starred: r.get(9)?,
                        reading_time_minutes: r.get::<_, u32>(10)?,
                        preview: r.get(11)?,
                        image_url: r.get(12)?,
                    })
                },
            )
            .optional()
            .map_err(sql_error)
    }

    pub fn article_page(
        &self,
        query: &ArticleQuery,
        include_total: bool,
    ) -> Result<ArticlePage, CoreError> {
        if query.limit == 0 {
            return Err(CoreError::data("article page limit must be positive"));
        }
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let total = if include_total {
            let mut total_query = query.clone();
            total_query.cursor = None;
            Some(Self::count_articles_locked(&connection, &total_query)?)
        } else {
            None
        };
        let mut fetch_query = query.clone();
        fetch_query.limit = query.limit.saturating_add(1);
        let mut articles = Self::query_articles_locked(&connection, &fetch_query)?;
        let has_more = articles.len() > query.limit as usize;
        if has_more {
            articles.pop();
        }
        let next_cursor = has_more
            .then(|| {
                articles.last().map(|article| crate::domain::ArticleCursor {
                    published_at: article.published_at.clone(),
                    article_id: article.id,
                })
            })
            .flatten();
        Ok(ArticlePage {
            articles,
            total,
            next_cursor,
        })
    }

    fn count_articles_locked(
        connection: &Connection,
        query: &ArticleQuery,
    ) -> Result<u64, CoreError> {
        let (sql, values) = article_filter_sql(
            "SELECT COUNT(*) FROM articles a JOIN feeds f ON f.id=a.feed_id WHERE 1=1".into(),
            query,
        );
        connection
            .query_row(&sql, rusqlite::params_from_iter(values), |row| {
                row_u64(row, 0)
            })
            .map_err(sql_error)
    }

    fn query_articles_locked(
        connection: &Connection,
        query: &ArticleQuery,
    ) -> Result<Vec<ArticleSummary>, CoreError> {
        let (mut sql,mut values)=article_filter_sql("SELECT a.id,a.feed_id,f.category_id,f.title,a.title,a.url,a.comments_url,a.published_at,a.is_read,a.is_starred,a.reading_time_minutes,a.preview,a.image_url FROM articles a JOIN feeds f ON f.id=a.feed_id WHERE 1=1".into(),query);
        let descending = query.sort == ArticleSort::NewestFirst;
        if let Some(cursor) = &query.cursor {
            let op = if descending { "<" } else { ">" };
            sql.push_str(&format!(
                " AND (a.published_at {op} ? OR (a.published_at = ? AND a.id {op} ?))"
            ));
            values.push(cursor.published_at.clone().into());
            values.push(cursor.published_at.clone().into());
            values.push(cursor.article_id.into());
        }
        let direction = if descending { "DESC" } else { "ASC" };
        sql.push_str(&format!(
            " ORDER BY a.published_at {direction}, a.id {direction}"
        ));
        if query.limit != 0 {
            sql.push_str(" LIMIT ?");
            values.push((query.limit as i64).into());
        }
        let mut statement = connection.prepare(&sql).map_err(sql_error)?;
        statement
            .query_map(rusqlite::params_from_iter(values), |r| {
                Ok(ArticleSummary {
                    id: r.get(0)?,
                    feed_id: r.get(1)?,
                    category_id: r.get(2)?,
                    feed_title: r.get(3)?,
                    title: r.get(4)?,
                    url: r.get(5)?,
                    comments_url: r.get(6)?,
                    published_at: r.get(7)?,
                    is_read: r.get(8)?,
                    is_starred: r.get(9)?,
                    reading_time_minutes: r.get::<_, u32>(10)?,
                    preview: r.get(11)?,
                    image_url: r.get(12)?,
                })
            })
            .map_err(sql_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(sql_error)
    }
    pub fn widget_data(&self) -> Result<WidgetData, CoreError> {
        const CANDIDATES_PER_FEED_AND_DIRECTION: i64 = 12;
        const BOOKMARK_CANDIDATES_PER_DIRECTION: i64 = 48;
        let connection = self
            .connection
            .lock()
            .map_err(|_| CoreError::internal("database lock poisoned"))?;
        let catalog = self.navigation_catalog_locked(&connection)?;
        let mut statement = connection.prepare(
            "WITH ranked AS (\
                SELECT a.id,a.feed_id,f.category_id,f.title AS feed_title,a.title AS article_title,a.published_at,a.is_read,a.is_starred,\
                    ROW_NUMBER() OVER (PARTITION BY a.feed_id ORDER BY a.published_at DESC,a.id DESC) AS newest_position,\
                    ROW_NUMBER() OVER (PARTITION BY a.feed_id ORDER BY a.published_at ASC,a.id ASC) AS oldest_position,\
                    ROW_NUMBER() OVER (PARTITION BY a.feed_id,a.is_read ORDER BY a.published_at DESC,a.id DESC) AS newest_read_position,\
                    ROW_NUMBER() OVER (PARTITION BY a.feed_id,a.is_read ORDER BY a.published_at ASC,a.id ASC) AS oldest_read_position \
                FROM articles a JOIN feeds f ON f.id=a.feed_id \
             ), selected_feed_candidates AS (\
                SELECT * FROM ranked WHERE \
                    newest_position <= ?1 OR oldest_position <= ?1 OR \
                    newest_read_position <= ?1 OR oldest_read_position <= ?1 \
             ), bookmarked AS (\
                SELECT a.id,a.feed_id,f.category_id,f.title AS feed_title,a.title AS article_title,a.published_at,a.is_read,a.is_starred,\
                    ROW_NUMBER() OVER (ORDER BY a.published_at DESC,a.id DESC) AS newest_position,\
                    ROW_NUMBER() OVER (ORDER BY a.published_at ASC,a.id ASC) AS oldest_position,\
                    ROW_NUMBER() OVER (PARTITION BY a.is_read ORDER BY a.published_at DESC,a.id DESC) AS newest_read_position,\
                    ROW_NUMBER() OVER (PARTITION BY a.is_read ORDER BY a.published_at ASC,a.id ASC) AS oldest_read_position \
                FROM articles a JOIN feeds f ON f.id=a.feed_id WHERE a.is_starred=1 \
             ), selected_bookmarks AS (\
                SELECT * FROM bookmarked WHERE \
                    newest_position <= ?2 OR oldest_position <= ?2 OR \
                    newest_read_position <= ?2 OR oldest_read_position <= ?2 \
             ) \
             SELECT id,feed_id,category_id,feed_title,article_title,published_at,is_read,is_starred FROM selected_feed_candidates \
             UNION \
             SELECT id,feed_id,category_id,feed_title,article_title,published_at,is_read,is_starred FROM selected_bookmarks \
             ORDER BY published_at DESC,id DESC",
        ).map_err(sql_error)?;
        let articles = statement
            .query_map(
                params![
                    CANDIDATES_PER_FEED_AND_DIRECTION,
                    BOOKMARK_CANDIDATES_PER_DIRECTION
                ],
                |r| {
                    Ok(WidgetArticle {
                        id: r.get(0)?,
                        feed_id: r.get(1)?,
                        category_id: r.get(2)?,
                        feed_title: r.get(3)?,
                        title: r.get(4)?,
                        published_at: r.get(5)?,
                        is_read: r.get(6)?,
                        is_starred: r.get(7)?,
                    })
                },
            )
            .map_err(sql_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(sql_error)?;
        let all_unread = connection
            .query_row("SELECT COUNT(*) FROM articles WHERE is_read=0", [], |r| {
                row_u64(r, 0)
            })
            .map_err(sql_error)?;
        let all_articles = connection
            .query_row("SELECT COUNT(*) FROM articles", [], |r| row_u64(r, 0))
            .map_err(sql_error)?;
        let bookmarks = connection
            .query_row(
                "SELECT COUNT(*) FROM articles WHERE is_starred=1",
                [],
                |r| row_u64(r, 0),
            )
            .map_err(sql_error)?;
        let bookmarks_unread = connection
            .query_row(
                "SELECT COUNT(*) FROM articles WHERE is_starred=1 AND is_read=0",
                [],
                |r| row_u64(r, 0),
            )
            .map_err(sql_error)?;
        let feed_unread = scoped_counts(
            &connection,
            "SELECT feed_id,COUNT(*) FROM articles WHERE is_read=0 GROUP BY feed_id ORDER BY feed_id",
        )?;
        let feed_all = scoped_counts(
            &connection,
            "SELECT feed_id,COUNT(*) FROM articles GROUP BY feed_id ORDER BY feed_id",
        )?;
        let category_unread = scoped_counts(
            &connection,
            "SELECT f.category_id,COUNT(*) FROM articles a JOIN feeds f ON f.id=a.feed_id WHERE a.is_read=0 GROUP BY f.category_id ORDER BY f.category_id",
        )?;
        let category_all = scoped_counts(
            &connection,
            "SELECT f.category_id,COUNT(*) FROM articles a JOIN feeds f ON f.id=a.feed_id GROUP BY f.category_id ORDER BY f.category_id",
        )?;
        let last_successful_sync_at = connection
            .query_row(
                "SELECT value FROM core_settings WHERE key='last_successful_sync_at'",
                [],
                |r| r.get(0),
            )
            .optional()
            .map_err(sql_error)?;
        Ok(WidgetData {
            categories: catalog.categories,
            feeds: catalog.feeds,
            articles,
            counts: WidgetCounts {
                all_unread,
                all_articles,
                bookmarks,
                bookmarks_unread,
                feed_unread,
                feed_all,
                category_unread,
                category_all,
            },
            last_successful_sync_at,
        })
    }
    fn navigation_catalog_locked(
        &self,
        connection: &Connection,
    ) -> Result<NavigationCatalog, CoreError> {
        let mut categories = connection
            .prepare("SELECT id,title FROM categories ORDER BY title COLLATE NOCASE,id")
            .map_err(sql_error)?;
        let categories = categories
            .query_map([], |row| {
                Ok(Category {
                    id: row.get(0)?,
                    title: row.get(1)?,
                })
            })
            .map_err(sql_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(sql_error)?;
        let mut feeds = connection.prepare("SELECT id,category_id,title FROM feeds ORDER BY category_id,title COLLATE NOCASE,id").map_err(sql_error)?;
        let feeds = feeds
            .query_map([], |row| {
                Ok(Feed {
                    id: row.get(0)?,
                    category_id: row.get(1)?,
                    title: row.get(2)?,
                })
            })
            .map_err(sql_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(sql_error)?;
        Ok(NavigationCatalog { categories, feeds })
    }
}

const LEGACY_PLAYBACK_UPDATED_AT_UNKNOWN: &str = "0001-01-01T00:00:00Z";
fn scoped_counts(connection: &Connection, sql: &str) -> Result<Vec<WidgetScopedCount>, CoreError> {
    let mut statement = connection.prepare(sql).map_err(sql_error)?;
    statement
        .query_map([], |r| {
            Ok(WidgetScopedCount {
                id: r.get(0)?,
                count: row_u64(r, 1)?,
            })
        })
        .map_err(sql_error)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(sql_error)
}
fn navigation_scoped_counts(
    connection: &Connection,
    sql: &str,
) -> Result<Vec<NavigationScopedCount>, CoreError> {
    let mut statement = connection.prepare(sql).map_err(sql_error)?;
    statement
        .query_map([], |row| {
            Ok(NavigationScopedCount {
                id: row.get(0)?,
                count: row_u64(row, 1)?,
            })
        })
        .map_err(sql_error)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(sql_error)
}
fn article_filter_sql(
    mut sql: String,
    query: &ArticleQuery,
) -> (String, Vec<rusqlite::types::Value>) {
    let mut values = Vec::new();
    match query.scope {
        ArticleScope::All => {}
        ArticleScope::Category(id) => {
            sql.push_str(" AND f.category_id=?");
            values.push(id.into())
        }
        ArticleScope::Feed(id) => {
            sql.push_str(" AND a.feed_id=?");
            values.push(id.into())
        }
    }
    match query.read_filter {
        ReadFilter::All => {}
        ReadFilter::Read => sql.push_str(" AND a.is_read=1"),
        ReadFilter::Unread => sql.push_str(" AND a.is_read=0"),
    }
    match query.starred_filter {
        StarredFilter::All => {}
        StarredFilter::Starred => sql.push_str(" AND a.is_starred=1"),
        StarredFilter::Unstarred => sql.push_str(" AND a.is_starred=0"),
    }
    (sql, values)
}
fn migrate(connection: &mut Connection) -> Result<(), CoreError> {
    let current: i64 = connection
        .query_row("PRAGMA user_version", [], |r| r.get(0))
        .map_err(sql_error)?;
    if current > SCHEMA_VERSION {
        return Err(CoreError::persistence(
            "database schema is newer than this core",
        ));
    }
    if current == 0 {
        let tx = connection.transaction().map_err(sql_error)?;
        tx.execute_batch("CREATE TABLE core_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL); CREATE TABLE categories (id INTEGER PRIMARY KEY, title TEXT NOT NULL); CREATE TABLE feeds (id INTEGER PRIMARY KEY, category_id INTEGER NOT NULL REFERENCES categories(id), title TEXT NOT NULL); CREATE TABLE articles (id INTEGER PRIMARY KEY, feed_id INTEGER NOT NULL REFERENCES feeds(id), title TEXT NOT NULL, url TEXT NOT NULL, comments_url TEXT NOT NULL DEFAULT '', published_at TEXT NOT NULL, is_read INTEGER NOT NULL CHECK(is_read IN(0,1)), is_starred INTEGER NOT NULL CHECK(is_starred IN(0,1)), raw_html_content TEXT NOT NULL); CREATE INDEX articles_published ON articles(published_at,id); CREATE INDEX articles_feed_published ON articles(feed_id,published_at,id); CREATE INDEX feeds_category ON feeds(category_id); PRAGMA user_version=1;").map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
    }
    if current < 2 {
        let tx = connection.transaction().map_err(sql_error)?;
        tx.execute_batch("ALTER TABLE articles ADD COLUMN remote_is_read INTEGER; ALTER TABLE articles ADD COLUMN remote_is_starred INTEGER; UPDATE articles SET remote_is_read=is_read, remote_is_starred=is_starred WHERE remote_is_read IS NULL; CREATE TABLE pending_mutations (article_id INTEGER NOT NULL REFERENCES articles(id), field TEXT NOT NULL CHECK(field IN ('read','starred')), desired INTEGER NOT NULL CHECK(desired IN(0,1)), revision INTEGER NOT NULL, PRIMARY KEY(article_id,field)); PRAGMA user_version=2;").map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
    }
    if current < 3 {
        let tx = connection.transaction().map_err(sql_error)?;
        tx.execute_batch("ALTER TABLE articles ADD COLUMN preview TEXT NOT NULL DEFAULT ''; ALTER TABLE articles ADD COLUMN image_url TEXT; PRAGMA user_version=3;").map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
    }
    if current < 4 {
        let tx = connection.transaction().map_err(sql_error)?;
        tx.execute_batch("ALTER TABLE articles ADD COLUMN content_processing_version INTEGER NOT NULL DEFAULT 0;").map_err(sql_error)?;
        let rows = {
            let mut statement = tx.prepare("SELECT id,url,raw_html_content FROM articles WHERE content_processing_version < ?1").map_err(sql_error)?;
            statement
                .query_map([crate::article::PROCESSING_VERSION], |row| {
                    Ok((
                        row.get::<_, i64>(0)?,
                        row.get::<_, String>(1)?,
                        row.get::<_, String>(2)?,
                    ))
                })
                .map_err(sql_error)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(sql_error)?
        };
        tracing::info!(target: "storage", "article content reprocessing started");
        for (id, url, html) in &rows {
            let processed = crate::article::process(html, url, &[]);
            tx.execute("UPDATE articles SET preview=?1,image_url=?2,content_processing_version=?3 WHERE id=?4", params![processed.preview, processed.image_url, crate::article::PROCESSING_VERSION, id]).map_err(sql_error)?;
        }
        tx.pragma_update(None, "user_version", 4)
            .map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
        tracing::info!(target: "storage", "article content reprocessing completed processed={}", rows.len());
    }
    if current < 5 {
        let tx = connection.transaction().map_err(sql_error)?;
        tx.execute_batch("CREATE TABLE feed_system_notification_preferences (feed_id INTEGER PRIMARY KEY REFERENCES feeds(id) ON DELETE CASCADE, enabled INTEGER NOT NULL CHECK(enabled IN(0,1))); CREATE TABLE pending_system_notifications (article_id INTEGER PRIMARY KEY REFERENCES articles(id) ON DELETE CASCADE); CREATE TABLE system_notified_articles (article_id INTEGER PRIMARY KEY REFERENCES articles(id) ON DELETE CASCADE); CREATE TABLE system_notification_candidates (id INTEGER PRIMARY KEY, feed_id INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE, feed_title TEXT NOT NULL); CREATE TABLE notification_candidate_articles (candidate_id INTEGER NOT NULL REFERENCES system_notification_candidates(id) ON DELETE CASCADE, article_id INTEGER NOT NULL REFERENCES articles(id) ON DELETE CASCADE, PRIMARY KEY(candidate_id,article_id)); CREATE INDEX pending_system_notifications_article ON pending_system_notifications(article_id); PRAGMA user_version=5;").map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
    }
    if current < 6 {
        let tx = connection.transaction().map_err(sql_error)?;
        tx.execute_batch("CREATE TABLE feed_preferences (feed_id INTEGER PRIMARY KEY, system_notifications_enabled INTEGER NOT NULL DEFAULT 0 CHECK(system_notifications_enabled IN(0,1)), detail_rendering TEXT NOT NULL DEFAULT 'rendered' CHECK(detail_rendering IN('rendered','text_only')), truncate_detail INTEGER NOT NULL DEFAULT 0 CHECK(truncate_detail IN(0,1)), open_in_miniflux INTEGER NOT NULL DEFAULT 0 CHECK(open_in_miniflux IN(0,1))); INSERT INTO feed_preferences(feed_id,system_notifications_enabled) SELECT feed_id,enabled FROM feed_system_notification_preferences; DROP TABLE feed_system_notification_preferences; PRAGMA user_version=7;").map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
    }
    if current == 6 {
        let tx = connection.transaction().map_err(sql_error)?;
        tx.execute_batch("CREATE TABLE feed_preferences_replacement (feed_id INTEGER PRIMARY KEY, system_notifications_enabled INTEGER NOT NULL DEFAULT 0 CHECK(system_notifications_enabled IN(0,1)), detail_rendering TEXT NOT NULL DEFAULT 'rendered' CHECK(detail_rendering IN('rendered','text_only')), truncate_detail INTEGER NOT NULL DEFAULT 0 CHECK(truncate_detail IN(0,1)), open_in_miniflux INTEGER NOT NULL DEFAULT 0 CHECK(open_in_miniflux IN(0,1))); INSERT INTO feed_preferences_replacement (feed_id,system_notifications_enabled,detail_rendering,truncate_detail,open_in_miniflux) SELECT feed_id,system_notifications_enabled,detail_rendering,truncate_detail,open_in_miniflux FROM feed_preferences; DROP TABLE feed_preferences; ALTER TABLE feed_preferences_replacement RENAME TO feed_preferences; PRAGMA user_version=7;").map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
    }
    if current < 8 {
        let tx = connection.transaction().map_err(sql_error)?;
        tx.execute_batch("CREATE TABLE IF NOT EXISTS feed_preferences (feed_id INTEGER PRIMARY KEY, system_notifications_enabled INTEGER NOT NULL DEFAULT 0 CHECK(system_notifications_enabled IN(0,1)), detail_rendering TEXT NOT NULL DEFAULT 'rendered' CHECK(detail_rendering IN('rendered','text_only')), truncate_detail INTEGER NOT NULL DEFAULT 0 CHECK(truncate_detail IN(0,1)), open_in_miniflux INTEGER NOT NULL DEFAULT 0 CHECK(open_in_miniflux IN(0,1))); CREATE TABLE enclosures (id INTEGER PRIMARY KEY, article_id INTEGER NOT NULL REFERENCES articles(id) ON DELETE CASCADE, url TEXT NOT NULL, mime_type TEXT NOT NULL, size_bytes INTEGER, remote_media_progression_seconds INTEGER NOT NULL CHECK(remote_media_progression_seconds >= 0), remote_present INTEGER NOT NULL DEFAULT 1 CHECK(remote_present IN(0,1)), CHECK(size_bytes IS NULL OR size_bytes > 0)); CREATE INDEX enclosures_article ON enclosures(article_id,id); PRAGMA user_version=8;").map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
    }
    if current < 9 {
        let tx = connection.transaction().map_err(sql_error)?;
        tx.execute_batch("CREATE TABLE saved_media (enclosure_id INTEGER PRIMARY KEY REFERENCES enclosures(id) ON DELETE CASCADE, added_at TEXT NOT NULL); CREATE INDEX saved_media_added_at ON saved_media(added_at DESC,enclosure_id DESC); PRAGMA user_version=9;").map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
    }
    if current < 10 {
        let tx = connection.transaction().map_err(sql_error)?;
        tx.execute_batch("CREATE TABLE saved_media_sync_config (id INTEGER PRIMARY KEY CHECK(id=1), enabled INTEGER NOT NULL DEFAULT 0 CHECK(enabled IN(0,1)), sync_feed_id INTEGER, requires_repair INTEGER NOT NULL DEFAULT 0 CHECK(requires_repair IN(0,1))); INSERT INTO saved_media_sync_config(id) VALUES(1); CREATE TABLE pending_saved_media_replication (enclosure_id INTEGER PRIMARY KEY, article_id INTEGER NOT NULL, desired TEXT NOT NULL CHECK(desired IN ('saved','unsaved'))); CREATE TABLE saved_media_remote_state (enclosure_id INTEGER PRIMARY KEY, article_id INTEGER NOT NULL, marker_entry_id INTEGER NOT NULL, state TEXT NOT NULL CHECK(state IN ('saved','unsaved'))); PRAGMA user_version=10;").map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
    }
    if current < 11 {
        let tx = connection.transaction().map_err(sql_error)?;
        tx.execute_batch("CREATE TABLE IF NOT EXISTS pending_mutations (article_id INTEGER NOT NULL, field TEXT NOT NULL CHECK(field IN ('read','starred')), desired INTEGER NOT NULL CHECK(desired IN(0,1)), revision INTEGER NOT NULL, PRIMARY KEY(article_id,field)); CREATE TABLE pending_mutations_replacement (article_id INTEGER NOT NULL, field TEXT NOT NULL CHECK(field IN ('read','starred','media_progress')), desired INTEGER NOT NULL CHECK(desired IN(0,1)), progression_seconds INTEGER, revision INTEGER NOT NULL, PRIMARY KEY(article_id,field), CHECK((field IN ('read','starred') AND progression_seconds IS NULL) OR (field='media_progress' AND progression_seconds >= 0))); INSERT INTO pending_mutations_replacement(article_id,field,desired,progression_seconds,revision) SELECT article_id,field,desired,NULL,revision FROM pending_mutations; DROP TABLE pending_mutations; ALTER TABLE pending_mutations_replacement RENAME TO pending_mutations; CREATE TABLE playback_states (enclosure_id INTEGER PRIMARY KEY REFERENCES enclosures(id) ON DELETE CASCADE, position_ms INTEGER NOT NULL CHECK(position_ms >= 0), duration_ms INTEGER CHECK(duration_ms >= 0), status TEXT NOT NULL CHECK(status IN ('in_progress','completed')), updated_at TEXT NOT NULL, CHECK(duration_ms IS NULL OR position_ms <= duration_ms)); PRAGMA user_version=11;").map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
    }
    if current < 12 {
        let tx = connection.transaction().map_err(sql_error)?;
        tx.execute_batch("CREATE TABLE pending_media_progress_mutations (enclosure_id INTEGER PRIMARY KEY REFERENCES enclosures(id) ON DELETE CASCADE, progression_seconds INTEGER NOT NULL CHECK(progression_seconds >= 0), revision INTEGER NOT NULL); INSERT INTO pending_media_progress_mutations(enclosure_id,progression_seconds,revision) SELECT article_id,progression_seconds,revision FROM pending_mutations WHERE field='media_progress'; CREATE TABLE pending_mutations_repaired (article_id INTEGER NOT NULL REFERENCES articles(id), field TEXT NOT NULL CHECK(field IN ('read','starred')), desired INTEGER NOT NULL CHECK(desired IN(0,1)), revision INTEGER NOT NULL, PRIMARY KEY(article_id,field)); INSERT INTO pending_mutations_repaired(article_id,field,desired,revision) SELECT article_id,field,desired,revision FROM pending_mutations WHERE field IN ('read','starred'); DROP TABLE pending_mutations; ALTER TABLE pending_mutations_repaired RENAME TO pending_mutations; PRAGMA user_version=12;").map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
    }
    if current < 13 {
        let tx = connection.transaction().map_err(sql_error)?;
        tx.execute_batch("CREATE TABLE media_downloads (enclosure_id INTEGER PRIMARY KEY REFERENCES enclosures(id) ON DELETE CASCADE, state TEXT NOT NULL CHECK(state IN ('requested','downloaded','failed','delete_requested')), origin TEXT CHECK(origin IN ('manual','automatic')), local_file TEXT, file_size_bytes INTEGER CHECK(file_size_bytes IS NULL OR file_size_bytes >= 0), downloaded_at TEXT, failure_kind TEXT CHECK(failure_kind IS NULL OR failure_kind IN ('network','storage','invalid_media','unknown')), CHECK(state IN ('downloaded','delete_requested') OR local_file IS NULL), CHECK(state IN ('downloaded','delete_requested') OR file_size_bytes IS NULL), CHECK(state IN ('downloaded','delete_requested') OR downloaded_at IS NULL), CHECK(state != 'failed' OR failure_kind IS NOT NULL), CHECK(state = 'failed' OR failure_kind IS NULL)); PRAGMA user_version=13;").map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
    }
    if current < 14 {
        let tx = connection.transaction().map_err(sql_error)?;
        // Rebuild media_downloads with strict state-vs-metadata invariants.
        // The CHECK clauses use the form `state != S OR ...` so they only constrain rows
        // currently in state S; otherwise the AND form would reject INSERTs into other states
        // because the inner predicates are not yet true at INSERT time.
        tx.execute_batch("CREATE TABLE media_downloads_replacement (enclosure_id INTEGER PRIMARY KEY REFERENCES enclosures(id) ON DELETE CASCADE, state TEXT NOT NULL CHECK(state IN ('requested','downloaded','failed','delete_requested')), origin TEXT NOT NULL CHECK(origin IN ('manual','automatic')), local_file TEXT, file_size_bytes INTEGER CHECK(file_size_bytes IS NULL OR file_size_bytes > 0), downloaded_at TEXT, failure_kind TEXT CHECK(failure_kind IS NULL OR failure_kind IN ('network','storage','invalid_media','unknown')), CHECK(state != 'requested' OR (local_file IS NULL AND file_size_bytes IS NULL AND downloaded_at IS NULL AND failure_kind IS NULL)), CHECK(state != 'failed' OR (local_file IS NULL AND file_size_bytes IS NULL AND downloaded_at IS NULL AND failure_kind IS NOT NULL)), CHECK(state NOT IN ('downloaded','delete_requested') OR (local_file IS NOT NULL AND file_size_bytes IS NOT NULL AND downloaded_at IS NOT NULL AND failure_kind IS NULL))); INSERT INTO media_downloads_replacement(enclosure_id,state,origin,local_file,file_size_bytes,downloaded_at,failure_kind) SELECT enclosure_id,state,origin,local_file,file_size_bytes,downloaded_at,failure_kind FROM media_downloads; DROP TABLE media_downloads; ALTER TABLE media_downloads_replacement RENAME TO media_downloads; PRAGMA user_version=14;").map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
    }
    if current < 15 {
        let tx = connection.transaction().map_err(sql_error)?;
        tx.execute_batch("CREATE TABLE IF NOT EXISTS feed_preferences (feed_id INTEGER PRIMARY KEY, system_notifications_enabled INTEGER NOT NULL DEFAULT 0 CHECK(system_notifications_enabled IN(0,1)), detail_rendering TEXT NOT NULL DEFAULT 'rendered' CHECK(detail_rendering IN('rendered','text_only')), truncate_detail INTEGER NOT NULL DEFAULT 0 CHECK(truncate_detail IN(0,1)), open_in_miniflux INTEGER NOT NULL DEFAULT 0 CHECK(open_in_miniflux IN(0,1))); ALTER TABLE feed_preferences ADD COLUMN auto_download_audio INTEGER NOT NULL DEFAULT 0 CHECK(auto_download_audio IN(0,1)); CREATE TABLE auto_download_suppressions (enclosure_id INTEGER PRIMARY KEY REFERENCES enclosures(id) ON DELETE CASCADE); PRAGMA user_version=15;").map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
    }
    if current < 16 {
        let tx = connection.transaction().map_err(sql_error)?;
        tx.execute_batch("CREATE TABLE media_metadata (enclosure_id INTEGER PRIMARY KEY REFERENCES enclosures(id) ON DELETE CASCADE, duration_ms INTEGER CHECK(duration_ms IS NULL OR duration_ms > 0), duration_source TEXT NOT NULL DEFAULT 'native' CHECK(duration_source IN ('native','local')), embedded_artwork_reference TEXT); CREATE TABLE media_chapters (enclosure_id INTEGER NOT NULL REFERENCES enclosures(id) ON DELETE CASCADE, sequence INTEGER NOT NULL CHECK(sequence >= 0), title TEXT NOT NULL, start_ms INTEGER NOT NULL CHECK(start_ms >= 0), end_ms INTEGER CHECK(end_ms IS NULL OR end_ms > start_ms), source TEXT NOT NULL CHECK(source IN ('embedded','article_content')), PRIMARY KEY(enclosure_id,sequence)); PRAGMA user_version=16;").map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
    }
    if current < 17 {
        let tx = connection.transaction().map_err(sql_error)?;
        tx.execute_batch("CREATE TABLE listening_list (article_id INTEGER PRIMARY KEY REFERENCES articles(id) ON DELETE CASCADE, added_at TEXT NOT NULL); CREATE INDEX listening_list_added_at ON listening_list(added_at DESC,article_id DESC); PRAGMA user_version=17;").map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
    }
    if current < 18 {
        let tx = connection.transaction().map_err(sql_error)?;
        tx.execute_batch("ALTER TABLE articles ADD COLUMN reading_time_minutes INTEGER NOT NULL DEFAULT 0 CHECK(reading_time_minutes >= 0); PRAGMA user_version=18;").map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
    }
    if current < 19 {
        let tx = connection.transaction().map_err(sql_error)?;
        // Older databases did not retain per-field provenance. Treat any saved
        // preference row as native-owned rather than risk replacing a user's choice.
        tx.execute_batch("CREATE TABLE feed_open_in_miniflux_overrides (feed_id INTEGER PRIMARY KEY); INSERT INTO feed_open_in_miniflux_overrides(feed_id) SELECT feed_id FROM feed_preferences; PRAGMA user_version=19;").map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
    }
    if current < 20 {
        let tx = connection.transaction().map_err(sql_error)?;
        // v19 stored these values but had no provenance. A saved historical
        // value, including false, is conservatively native-owned.
        tx.execute_batch("INSERT INTO core_settings(key,value) SELECT 'background_sync_enabled_explicit','1' WHERE EXISTS(SELECT 1 FROM core_settings WHERE key='background_sync_enabled') ON CONFLICT(key) DO UPDATE SET value='1'; INSERT INTO core_settings(key,value) SELECT 'auto_download_listening_list_explicit','1' WHERE EXISTS(SELECT 1 FROM core_settings WHERE key='auto_download_listening_list') ON CONFLICT(key) DO UPDATE SET value='1'; PRAGMA user_version=20;").map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
    }
    if current < 21 {
        let tx = connection.transaction().map_err(sql_error)?;
        // Older notification code queued new articles even while a feed was disabled.
        // Drop that ambiguous backlog once so enabling notifications starts from "now".
        tx.execute_batch("DELETE FROM notification_candidate_articles; DELETE FROM system_notification_candidates; DELETE FROM pending_system_notifications; PRAGMA user_version=21;").map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
    }
    if current < 22 {
        let tx = connection.transaction().map_err(sql_error)?;
        // Candidate IDs are also platform notification identifiers. SQLite may reuse an
        // INTEGER PRIMARY KEY after acknowledgement deletes the row, causing a later Android
        // notification to replace an older visible notification. AUTOINCREMENT preserves
        // monotonic candidate identity for the lifetime of this database.
        tx.execute_batch("CREATE TABLE system_notification_candidates_v22 (id INTEGER PRIMARY KEY AUTOINCREMENT, feed_id INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE, feed_title TEXT NOT NULL); INSERT INTO system_notification_candidates_v22(id,feed_id,feed_title) SELECT id,feed_id,feed_title FROM system_notification_candidates; CREATE TABLE notification_candidate_articles_v22 (candidate_id INTEGER NOT NULL REFERENCES system_notification_candidates_v22(id) ON DELETE CASCADE, article_id INTEGER NOT NULL REFERENCES articles(id) ON DELETE CASCADE, PRIMARY KEY(candidate_id,article_id)); INSERT INTO notification_candidate_articles_v22(candidate_id,article_id) SELECT candidate_id,article_id FROM notification_candidate_articles; DROP TABLE notification_candidate_articles; DROP TABLE system_notification_candidates; ALTER TABLE system_notification_candidates_v22 RENAME TO system_notification_candidates; ALTER TABLE notification_candidate_articles_v22 RENAME TO notification_candidate_articles; PRAGMA user_version=22;").map_err(sql_error)?;
        tx.commit().map_err(sql_error)?;
    }
    Ok(())
}
fn initialize_core_settings(connection: &Connection) -> Result<(), CoreError> {
    for (key, value) in core_setting_defaults() {
        connection
            .execute(
                "INSERT INTO core_settings (key, value) VALUES (?1, ?2) ON CONFLICT(key) DO NOTHING",
                params![key, value],
            )
            .map_err(sql_error)?;
    }
    Ok(())
}
fn core_setting_defaults() -> Vec<(&'static str, String)> {
    let defaults = CoreSettings::default();
    vec![
        (
            "read_article_retention",
            defaults.retention.days().to_string(),
        ),
        ("delivery_mode", "deferred".to_string()),
        (
            "background_sync_enabled",
            if defaults.background_sync_enabled {
                "1".to_string()
            } else {
                "0".to_string()
            },
        ),
        (
            "detail_character_limit",
            defaults.detail_character_limit.to_string(),
        ),
        ("download_network_policy", "any_network".to_string()),
        ("download_retention", "forever".to_string()),
        (
            "delete_after_playback",
            if defaults.delete_after_playback {
                "1"
            } else {
                "0"
            }
            .to_string(),
        ),
        ("auto_download_listening_list", "0".to_string()),
        ("background_sync_enabled_explicit", "0".to_string()),
        ("auto_download_listening_list_explicit", "0".to_string()),
        ("remove_completed_listening_list", "0".to_string()),
    ]
}

fn parse_bool_setting(value: &str, message: &'static str) -> Result<bool, CoreError> {
    match value {
        "0" => Ok(false),
        "1" => Ok(true),
        _ => Err(CoreError::persistence(message)),
    }
}

fn download_retention_db(retention: DownloadRetention) -> String {
    match retention {
        DownloadRetention::Forever => "forever".to_string(),
        DownloadRetention::Days(days) => format!("days:{days}"),
    }
}

fn download_retention_from_db(value: &str) -> Result<DownloadRetention, CoreError> {
    if value == "forever" {
        return Ok(DownloadRetention::Forever);
    }
    match value
        .strip_prefix("days:")
        .and_then(|value| value.parse().ok())
    {
        Some(days) if days > 0 => Ok(DownloadRetention::Days(days)),
        _ => Err(CoreError::persistence("invalid download retention setting")),
    }
}

fn write_media_settings(tx: &Transaction<'_>, settings: &CoreSettings) -> Result<(), CoreError> {
    tx.execute("INSERT INTO core_settings(key,value) VALUES('download_network_policy',?1) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [match settings.download_network_policy { DownloadNetworkPolicy::AnyNetwork => "any_network", DownloadNetworkPolicy::UnmeteredOnly => "unmetered_only" }]).map_err(sql_error)?;
    tx.execute("INSERT INTO core_settings(key,value) VALUES('download_retention',?1) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [download_retention_db(settings.download_retention)]).map_err(sql_error)?;
    tx.execute("INSERT INTO core_settings(key,value) VALUES('delete_after_playback',?1) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [if settings.delete_after_playback { "1" } else { "0" }]).map_err(sql_error)?;
    tx.execute("INSERT INTO core_settings(key,value) VALUES('auto_download_listening_list',?1) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [if settings.auto_download_listening_list { "1" } else { "0" }]).map_err(sql_error)?;
    tx.execute("INSERT INTO core_settings(key,value) VALUES('auto_download_listening_list_explicit','1') ON CONFLICT(key) DO UPDATE SET value='1'", []).map_err(sql_error)?;
    tx.execute("INSERT INTO core_settings(key,value) VALUES('remove_completed_listening_list',?1) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [if settings.remove_completed_listening_list { "1" } else { "0" }]).map_err(sql_error)?;
    Ok(())
}
fn clear_synchronized_state(
    tx: &Transaction<'_>,
    remove_feed_preferences: bool,
) -> Result<(), CoreError> {
    tx.execute_batch("DELETE FROM notification_candidate_articles; DELETE FROM system_notification_candidates; DELETE FROM pending_system_notifications; DELETE FROM system_notified_articles; DELETE FROM pending_mutations; DELETE FROM articles;").map_err(sql_error)?;
    if remove_feed_preferences {
        tx.execute("DELETE FROM feed_preferences", [])
            .map_err(sql_error)?;
        tx.execute("DELETE FROM feed_open_in_miniflux_overrides", [])
            .map_err(sql_error)?;
        // Technical feed IDs and remote baselines are scoped to the previous account.
        tx.execute_batch("DELETE FROM pending_saved_media_replication; DELETE FROM saved_media_remote_state; UPDATE saved_media_sync_config SET enabled=0,sync_feed_id=NULL,requires_repair=0 WHERE id=1;").map_err(sql_error)?;
    }
    tx.execute_batch("DELETE FROM feeds; DELETE FROM categories; DELETE FROM core_settings WHERE key IN ('last_successful_sync_at','last_full_sync_at','delta_sync_cursor','full_sync_required','full_sync_reason');").map_err(sql_error)
}
fn upsert_remote_enclosures(
    tx: &Transaction<'_>,
    enclosures: &[Enclosure],
) -> Result<(), CoreError> {
    for enclosure in enclosures {
        let size_bytes = enclosure
            .size_bytes
            .map(i64::try_from)
            .transpose()
            .map_err(|_| CoreError::data("enclosure size exceeds SQLite integer range"))?;
        let remote_media_progression_seconds =
            i64::try_from(enclosure.remote_media_progression_seconds)
                .map_err(|_| CoreError::data("media progression exceeds SQLite integer range"))?;
        tx.execute(
            "INSERT INTO enclosures (id,article_id,url,mime_type,size_bytes,remote_media_progression_seconds,remote_present) VALUES (?1,?2,?3,?4,?5,?6,1) ON CONFLICT(id) DO UPDATE SET article_id=excluded.article_id,url=excluded.url,mime_type=excluded.mime_type,size_bytes=excluded.size_bytes,remote_media_progression_seconds=excluded.remote_media_progression_seconds,remote_present=1",
            params![enclosure.id, enclosure.article_id, enclosure.url, enclosure.mime_type, size_bytes, remote_media_progression_seconds],
        )
        .map_err(sql_error)?;
    }
    Ok(())
}

fn persist_media_metadata(
    tx: &Transaction<'_>,
    enclosure_id: i64,
    article_html: &str,
    analyzed: &AnalyzedMedia,
    artwork_reference: Option<&str>,
) -> Result<(), CoreError> {
    let duration_ms = analyzed
        .duration_ms
        .map(i64::try_from)
        .transpose()
        .map_err(|_| CoreError::data("media duration exceeds SQLite integer range"))?;
    tx.execute("INSERT INTO media_metadata(enclosure_id,duration_ms,duration_source,embedded_artwork_reference) VALUES(?1,?2,'local',?3) ON CONFLICT(enclosure_id) DO UPDATE SET duration_ms=COALESCE(excluded.duration_ms,media_metadata.duration_ms),duration_source=CASE WHEN excluded.duration_ms IS NOT NULL THEN 'local' ELSE media_metadata.duration_source END,embedded_artwork_reference=excluded.embedded_artwork_reference", params![enclosure_id, duration_ms, artwork_reference]).map_err(sql_error)?;
    let has_embedded: bool = tx
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM media_chapters WHERE enclosure_id=?1 AND source='embedded')",
            [enclosure_id],
            |row| row.get(0),
        )
        .map_err(sql_error)?;
    if has_embedded && analyzed.embedded_chapters.is_empty() {
        return Ok(());
    }
    tx.execute(
        "DELETE FROM media_chapters WHERE enclosure_id=?1",
        [enclosure_id],
    )
    .map_err(sql_error)?;
    let chapters = if analyzed.embedded_chapters.is_empty() {
        article_chapters(article_html, analyzed.duration_ms)
    } else {
        analyzed.embedded_chapters.clone()
    };
    let source = if analyzed.embedded_chapters.is_empty() {
        MediaChapterSource::ArticleContent
    } else {
        MediaChapterSource::Embedded
    };
    let chapters = to_domain_chapters(enclosure_id, source, &chapters);
    for (sequence, chapter) in chapters.iter().enumerate() {
        tx.execute("INSERT INTO media_chapters(enclosure_id,sequence,title,start_ms,end_ms,source) VALUES(?1,?2,?3,?4,?5,?6)", params![enclosure_id, sequence as i64, chapter.title, i64::try_from(chapter.start_ms).map_err(|_| CoreError::data("chapter start exceeds SQLite integer range"))?, chapter.end_ms.map(i64::try_from).transpose().map_err(|_| CoreError::data("chapter end exceeds SQLite integer range"))?, match chapter.source { MediaChapterSource::Embedded => "embedded", MediaChapterSource::ArticleContent => "article_content" }]).map_err(sql_error)?;
    }
    Ok(())
}

fn persist_chapters(
    tx: &Transaction<'_>,
    enclosure_id: i64,
    chapters: &[MediaChapter],
) -> Result<(), CoreError> {
    tx.execute(
        "DELETE FROM media_chapters WHERE enclosure_id=?1",
        [enclosure_id],
    )
    .map_err(sql_error)?;
    for (sequence, chapter) in chapters.iter().enumerate() {
        if chapter.end_ms.is_some_and(|end| end <= chapter.start_ms) {
            continue;
        }
        tx.execute("INSERT INTO media_chapters(enclosure_id,sequence,title,start_ms,end_ms,source) VALUES(?1,?2,?3,?4,?5,?6)", params![enclosure_id, sequence as i64, chapter.title, i64::try_from(chapter.start_ms).map_err(|_| CoreError::data("chapter start exceeds SQLite integer range"))?, chapter.end_ms.map(i64::try_from).transpose().map_err(|_| CoreError::data("chapter end exceeds SQLite integer range"))?, match chapter.source { MediaChapterSource::Embedded => "embedded", MediaChapterSource::ArticleContent => "article_content" }]).map_err(sql_error)?;
    }
    Ok(())
}

fn hex_digest(digest: &[u8]) -> String {
    digest.iter().map(|byte| format!("{byte:02x}")).collect()
}
fn save_media(tx: &Transaction<'_>, enclosure_id: i64, added_at: &str) -> Result<bool, CoreError> {
    let enclosure = tx
        .query_row(
            "SELECT id,article_id,url,mime_type,size_bytes,remote_media_progression_seconds,remote_present FROM enclosures WHERE id=?1",
            [enclosure_id],
            stored_enclosure_from_row,
        )
        .optional()
        .map_err(sql_error)?
        .ok_or_else(|| CoreError::data(format!("enclosure {enclosure_id} does not exist")))?;
    if !matches!(
        enclosure.enclosure.media_kind(),
        crate::domain::MediaKind::Audio | crate::domain::MediaKind::Video
    ) {
        return Err(CoreError::data(
            "only audio or video enclosures can be saved",
        ));
    }
    Ok(tx
        .execute(
            "INSERT INTO saved_media(enclosure_id,added_at) VALUES(?1,?2) ON CONFLICT(enclosure_id) DO NOTHING",
            params![enclosure_id, added_at],
        )
        .map_err(sql_error)?
        > 0)
}
fn playback_state_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<PlaybackState> {
    Ok(PlaybackState {
        enclosure_id: row.get(0)?,
        position_ms: u64::try_from(row.get::<_, i64>(1)?)
            .map_err(|_| rusqlite::Error::InvalidQuery)?,
        duration_ms: row
            .get::<_, Option<i64>>(2)?
            .map(|value| u64::try_from(value).map_err(|_| rusqlite::Error::InvalidQuery))
            .transpose()?,
        status: match row.get::<_, String>(3)?.as_str() {
            "in_progress" => PlaybackStatus::InProgress,
            "completed" => PlaybackStatus::Completed,
            _ => return Err(rusqlite::Error::InvalidQuery),
        },
        updated_at: row.get(4)?,
    })
}
fn ensure_enclosure(tx: &Transaction<'_>, enclosure_id: i64) -> Result<(), CoreError> {
    let exists: bool = tx
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM enclosures WHERE id=?1)",
            [enclosure_id],
            |row| row.get(0),
        )
        .map_err(sql_error)?;
    exists
        .then_some(())
        .ok_or_else(|| CoreError::data(format!("enclosure {enclosure_id} does not exist")))
}
fn upsert_playback_state(
    tx: &Transaction<'_>,
    enclosure_id: i64,
    position_ms: u64,
    duration_ms: Option<u64>,
    status: PlaybackStatus,
    updated_at: &str,
) -> Result<(), CoreError> {
    let position = i64::try_from(position_ms)
        .map_err(|_| CoreError::data("playback position exceeds SQLite range"))?;
    let duration = duration_ms
        .map(i64::try_from)
        .transpose()
        .map_err(|_| CoreError::data("playback duration exceeds SQLite range"))?;
    tx.execute("INSERT INTO playback_states(enclosure_id,position_ms,duration_ms,status,updated_at) VALUES(?1,?2,?3,?4,?5) ON CONFLICT(enclosure_id) DO UPDATE SET position_ms=excluded.position_ms,duration_ms=COALESCE(excluded.duration_ms,playback_states.duration_ms),status=excluded.status,updated_at=excluded.updated_at", params![enclosure_id,position,duration,match status { PlaybackStatus::InProgress => "in_progress", PlaybackStatus::Completed => "completed" },updated_at]).map_err(sql_error)?;
    Ok(())
}
fn milliseconds_to_seconds(milliseconds: u64) -> Result<u64, CoreError> {
    Ok(milliseconds / 1_000)
}
fn read_download_state(
    tx: &Transaction<'_>,
    enclosure_id: i64,
) -> Result<Option<DownloadState>, CoreError> {
    let value: Option<String> = tx
        .query_row(
            "SELECT state FROM media_downloads WHERE enclosure_id=?1",
            [enclosure_id],
            |row| row.get(0),
        )
        .optional()
        .map_err(sql_error)?;
    match value {
        None => Ok(None),
        Some(state) => match download_state_from_db(&state) {
            Ok(parsed) => Ok(Some(parsed)),
            Err(error) => Err(sql_error(error)),
        },
    }
}
fn origin_db(origin: DownloadOrigin) -> &'static str {
    match origin {
        DownloadOrigin::Manual => "manual",
        DownloadOrigin::Automatic => "automatic",
    }
}
fn origin_from_db(value: &str) -> rusqlite::Result<DownloadOrigin> {
    match value {
        "manual" => Ok(DownloadOrigin::Manual),
        "automatic" => Ok(DownloadOrigin::Automatic),
        _ => Err(rusqlite::Error::InvalidQuery),
    }
}
fn failure_kind_db(kind: DownloadFailureKind) -> &'static str {
    match kind {
        DownloadFailureKind::Network => "network",
        DownloadFailureKind::Storage => "storage",
        DownloadFailureKind::InvalidMedia => "invalid_media",
        DownloadFailureKind::Unknown => "unknown",
    }
}
fn failure_kind_from_db(value: &str) -> rusqlite::Result<DownloadFailureKind> {
    match value {
        "network" => Ok(DownloadFailureKind::Network),
        "storage" => Ok(DownloadFailureKind::Storage),
        "invalid_media" => Ok(DownloadFailureKind::InvalidMedia),
        "unknown" => Ok(DownloadFailureKind::Unknown),
        _ => Err(rusqlite::Error::InvalidQuery),
    }
}
fn download_state_from_db(value: &str) -> rusqlite::Result<DownloadState> {
    match value {
        "requested" => Ok(DownloadState::Requested),
        "downloaded" => Ok(DownloadState::Downloaded),
        "failed" => Ok(DownloadState::Failed),
        "delete_requested" => Ok(DownloadState::DeleteRequested),
        _ => Err(rusqlite::Error::InvalidQuery),
    }
}
fn media_download_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<MediaDownload> {
    let state = download_state_from_db(&row.get::<_, String>(1)?)?;
    let origin = row
        .get::<_, Option<String>>(2)?
        .map(|value| origin_from_db(&value))
        .transpose()?;
    let failure_kind = row
        .get::<_, Option<String>>(6)?
        .map(|value| failure_kind_from_db(&value))
        .transpose()?;
    let file_size_bytes = row
        .get::<_, Option<i64>>(4)?
        .map(|value| u64::try_from(value).map_err(|_| rusqlite::Error::InvalidQuery))
        .transpose()?;
    Ok::<MediaDownload, rusqlite::Error>(MediaDownload {
        enclosure_id: row.get(0)?,
        state,
        origin,
        local_file: row.get(3)?,
        file_size_bytes,
        downloaded_at: row.get(5)?,
        failure_kind,
    })
}
fn queue_media_progress(
    tx: &Transaction<'_>,
    enclosure_id: i64,
    seconds: u64,
) -> Result<(), CoreError> {
    let seconds = i64::try_from(seconds)
        .map_err(|_| CoreError::data("media progression exceeds SQLite range"))?;
    let remote_baseline: i64 = tx
        .query_row(
            "SELECT remote_media_progression_seconds FROM enclosures WHERE id=?1",
            [enclosure_id],
            |row| row.get(0),
        )
        .map_err(sql_error)?;

    if remote_baseline == seconds {
        // A lifecycle checkpoint at the already-known remote position is not a
        // new local intent. Remove any obsolete pending write so another device
        // may advance Miniflux without this device writing the old baseline back
        // before its next fetch.
        tx.execute(
            "DELETE FROM pending_media_progress_mutations WHERE enclosure_id=?1",
            [enclosure_id],
        )
        .map_err(sql_error)?;
        return Ok(());
    }

    tx.execute("INSERT INTO pending_media_progress_mutations(enclosure_id,progression_seconds,revision) VALUES(?1,?2,1) ON CONFLICT(enclosure_id) DO UPDATE SET progression_seconds=excluded.progression_seconds,revision=pending_media_progress_mutations.revision+1 WHERE pending_media_progress_mutations.progression_seconds != excluded.progression_seconds", params![enclosure_id,seconds]).map_err(sql_error)?;
    Ok(())
}
fn queue_saved_media_replication(
    tx: &Transaction<'_>,
    enclosure_id: i64,
    desired: SavedMediaMarkerState,
) -> Result<(), CoreError> {
    let enabled: bool = tx
        .query_row(
            "SELECT enabled FROM saved_media_sync_config WHERE id=1",
            [],
            |row| row.get(0),
        )
        .map_err(sql_error)?;
    if !enabled {
        return Ok(());
    }
    let article_id: i64 = tx
        .query_row(
            "SELECT article_id FROM enclosures WHERE id=?1",
            [enclosure_id],
            |row| row.get(0),
        )
        .map_err(sql_error)?;
    tx.execute(
        "INSERT INTO pending_saved_media_replication(enclosure_id,article_id,desired) VALUES(?1,?2,?3) ON CONFLICT(enclosure_id) DO UPDATE SET article_id=excluded.article_id,desired=excluded.desired",
        params![enclosure_id, article_id, marker_state_db(desired)],
    ).map_err(sql_error)?;
    Ok(())
}
fn marker_state_db(state: SavedMediaMarkerState) -> &'static str {
    match state {
        SavedMediaMarkerState::Saved => "saved",
        SavedMediaMarkerState::Unsaved => "unsaved",
    }
}
fn marker_state_from_db(value: &str) -> rusqlite::Result<SavedMediaMarkerState> {
    match value {
        "saved" => Ok(SavedMediaMarkerState::Saved),
        "unsaved" => Ok(SavedMediaMarkerState::Unsaved),
        _ => Err(rusqlite::Error::InvalidQuery),
    }
}
fn reconcile_remote_enclosures(
    tx: &Transaction<'_>,
    articles: &[Article],
    enclosures: &[Enclosure],
    media_progress_writes: &HashMap<i64, u64>,
) -> Result<(), CoreError> {
    let fetched_article_ids: HashSet<i64> = articles.iter().map(|article| article.id).collect();
    let mut enclosure_ids = HashSet::with_capacity(enclosures.len());
    for enclosure in enclosures {
        if !fetched_article_ids.contains(&enclosure.article_id) {
            return Err(CoreError::data(format!(
                "enclosure {} references article {} absent from the remote snapshot",
                enclosure.id, enclosure.article_id
            )));
        }
        if !enclosure_ids.insert(enclosure.id) {
            return Err(CoreError::data(format!(
                "remote snapshot contains duplicate enclosure {}",
                enclosure.id
            )));
        }
    }
    for article_id in fetched_article_ids {
        tx.execute(
            "UPDATE enclosures SET remote_present=0 WHERE article_id=?1",
            [article_id],
        )
        .map_err(sql_error)?;
    }
    let old_progressions = enclosures
        .iter()
        .map(|enclosure| {
            let old = tx
                .query_row(
                    "SELECT remote_media_progression_seconds FROM enclosures WHERE id=?1",
                    [enclosure.id],
                    |row| row.get::<_, i64>(0),
                )
                .optional()
                .map_err(sql_error)?
                .map(|value| {
                    u64::try_from(value)
                        .map_err(|_| CoreError::persistence("invalid stored media progression"))
                })
                .transpose()?;
            Ok::<_, CoreError>((enclosure.id, old))
        })
        .collect::<Result<HashMap<_, _>, _>>()?;
    upsert_remote_enclosures(tx, enclosures)?;
    for enclosure in enclosures {
        let old = old_progressions.get(&enclosure.id).copied().flatten();
        let pending: bool = tx.query_row("SELECT EXISTS(SELECT 1 FROM pending_media_progress_mutations WHERE enclosure_id=?1)", [enclosure.id], |row| row.get(0)).map_err(sql_error)?;
        let written = media_progress_writes.get(&enclosure.id).copied();
        let stale_write =
            written.is_some_and(|value| value != enclosure.remote_media_progression_seconds);
        let should_adopt =
            !pending && !stale_write && old != Some(enclosure.remote_media_progression_seconds);
        if should_adopt {
            reconcile_playback_progress(tx, enclosure, old)?;
        }
        if stale_write && let Some(written) = written {
            let written = i64::try_from(written)
                .map_err(|_| CoreError::data("media progression exceeds SQLite integer range"))?;
            tx.execute(
                "UPDATE enclosures SET remote_media_progression_seconds=?1 WHERE id=?2",
                params![written, enclosure.id],
            )
            .map_err(sql_error)?;
        }
    }
    Ok(())
}

const COMPLETION_TOLERANCE_SECONDS: u64 = 3;

fn reconcile_playback_progress(
    tx: &Transaction<'_>,
    enclosure: &Enclosure,
    old: Option<u64>,
) -> Result<(), CoreError> {
    let local = tx.query_row("SELECT position_ms,duration_ms,status,updated_at FROM playback_states WHERE enclosure_id=?1", [enclosure.id], |row| Ok((row.get::<_, i64>(0)?, row.get::<_, Option<i64>>(1)?, row.get::<_, String>(2)?, row.get::<_, String>(3)?))).optional().map_err(sql_error)?;
    let progression = enclosure.remote_media_progression_seconds;
    if local.is_none() && progression == 0 {
        return Ok(());
    }
    let duration = local
        .as_ref()
        .and_then(|(_, duration, _, _)| duration.and_then(|value| u64::try_from(value).ok()));
    let status = if progression == 0 {
        "in_progress"
    } else if duration.is_some_and(|duration| {
        duration.abs_diff(progression.saturating_mul(1000)) <= COMPLETION_TOLERANCE_SECONDS * 1000
    }) {
        "completed"
    } else {
        "in_progress"
    };
    let position_ms =
        if status == "completed" {
            duration.unwrap_or(progression.checked_mul(1000).ok_or_else(|| {
                CoreError::data("remote media progression exceeds playback range")
            })?)
        } else {
            progression
                .checked_mul(1000)
                .ok_or_else(|| CoreError::data("remote media progression exceeds playback range"))?
        };
    let position = i64::try_from(position_ms)
        .map_err(|_| CoreError::data("remote media progression exceeds playback range"))?;
    if local.is_some() && old == Some(progression) {
        return Ok(());
    }
    let duration = duration
        .map(i64::try_from)
        .transpose()
        .map_err(|_| CoreError::data("media duration exceeds SQLite integer range"))?;
    tx.execute("INSERT INTO playback_states(enclosure_id,position_ms,duration_ms,status,updated_at) VALUES(?1,?2,?3,?4,datetime('now')) ON CONFLICT(enclosure_id) DO UPDATE SET position_ms=excluded.position_ms,duration_ms=COALESCE(excluded.duration_ms,playback_states.duration_ms),status=excluded.status,updated_at=excluded.updated_at", params![enclosure.id,position,duration, status]).map_err(sql_error)?;
    Ok(())
}
fn stored_enclosure_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<StoredEnclosure> {
    let size_bytes = row
        .get::<_, Option<i64>>(4)?
        .map(|size| u64::try_from(size).map_err(|_| rusqlite::Error::InvalidQuery))
        .transpose()?;
    let remote_media_progression_seconds =
        u64::try_from(row.get::<_, i64>(5)?).map_err(|_| rusqlite::Error::InvalidQuery)?;
    Ok(StoredEnclosure {
        enclosure: Enclosure {
            id: row.get(0)?,
            article_id: row.get(1)?,
            url: row.get(2)?,
            mime_type: row.get(3)?,
            size_bytes,
            remote_media_progression_seconds,
        },
        remote_present: row.get(6)?,
    })
}

fn audio_enclosure_ids_for_article(
    tx: &Transaction<'_>,
    article_id: i64,
) -> Result<Vec<i64>, CoreError> {
    tx.prepare("SELECT id FROM enclosures WHERE article_id=?1 AND lower(mime_type) LIKE 'audio/%' ORDER BY id")
        .map_err(sql_error)?
        .query_map([article_id], |row| row.get(0))
        .map_err(sql_error)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(sql_error)
}

fn is_audio_enclosure(tx: &Transaction<'_>, enclosure_id: i64) -> Result<bool, CoreError> {
    tx.query_row(
        "SELECT lower(mime_type) LIKE 'audio/%' FROM enclosures WHERE id=?1",
        [enclosure_id],
        |row| row.get(0),
    )
    .map_err(sql_error)
}

fn ensure_listening_membership(
    tx: &Transaction<'_>,
    article_id: i64,
    added_at: &str,
) -> Result<(), CoreError> {
    tx.execute(
        "INSERT INTO listening_list(article_id,added_at) VALUES(?1,?2) ON CONFLICT(article_id) DO NOTHING",
        params![article_id, added_at],
    )
    .map_err(sql_error)?;
    Ok(())
}

fn request_download_in_transaction(
    tx: &Transaction<'_>,
    enclosure_id: i64,
    origin: DownloadOrigin,
) -> Result<(), CoreError> {
    ensure_enclosure(tx, enclosure_id)?;
    match read_download_state(tx, enclosure_id)? {
        None | Some(DownloadState::Failed) => {
            if matches!(origin, DownloadOrigin::Manual) {
                tx.execute(
                    "DELETE FROM auto_download_suppressions WHERE enclosure_id=?1",
                    [enclosure_id],
                )
                .map_err(sql_error)?;
            }
            tx.execute(
                "INSERT INTO media_downloads(enclosure_id,state,origin,local_file,file_size_bytes,downloaded_at,failure_kind) VALUES(?1,'requested',?2,NULL,NULL,NULL,NULL) ON CONFLICT(enclosure_id) DO UPDATE SET state='requested',origin=excluded.origin,local_file=NULL,file_size_bytes=NULL,downloaded_at=NULL,failure_kind=NULL",
                params![enclosure_id, origin_db(origin)],
            )
            .map_err(sql_error)?;
            Ok(())
        }
        Some(DownloadState::Requested | DownloadState::Downloaded) => Ok(()),
        Some(other) => Err(CoreError::data(format!(
            "cannot request download from {other:?}"
        ))),
    }
}

fn request_download_deletion_in_transaction(
    tx: &Transaction<'_>,
    enclosure_id: i64,
) -> Result<(), CoreError> {
    let Some(state) = read_download_state(tx, enclosure_id)? else {
        return Ok(());
    };
    let automatic: bool = tx
        .query_row(
            "SELECT origin='automatic' FROM media_downloads WHERE enclosure_id=?1",
            [enclosure_id],
            |row| row.get(0),
        )
        .map_err(sql_error)?;
    match state {
        DownloadState::Downloaded => {
            tx.execute(
                "UPDATE media_downloads SET state='delete_requested' WHERE enclosure_id=?1",
                [enclosure_id],
            )
            .map_err(sql_error)?;
        }
        DownloadState::DeleteRequested => {}
        DownloadState::Requested | DownloadState::Failed => {
            tx.execute(
                "DELETE FROM media_downloads WHERE enclosure_id=?1",
                [enclosure_id],
            )
            .map_err(sql_error)?;
        }
        DownloadState::NotDownloaded => {}
    }
    if automatic {
        tx.execute(
            "INSERT OR IGNORE INTO auto_download_suppressions(enclosure_id) VALUES(?1)",
            [enclosure_id],
        )
        .map_err(sql_error)?;
    }
    Ok(())
}

type ListeningListRow = (
    i64,
    i64,
    String,
    String,
    String,
    String,
    Option<ListeningListEnclosure>,
);

fn listening_list_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<ListeningListRow> {
    let enclosure_id = row.get::<_, Option<i64>>(6)?;
    let enclosure = enclosure_id
        .map(|id| {
            let mime_type: String = row.get(9)?;
            let playback_state = if row.get::<_, Option<i64>>(13)?.is_some() {
                Some(PlaybackState {
                    enclosure_id: id,
                    position_ms: u64::try_from(row.get::<_, i64>(13)?)
                        .map_err(|_| rusqlite::Error::InvalidQuery)?,
                    duration_ms: row
                        .get::<_, Option<i64>>(14)?
                        .map(|value| {
                            u64::try_from(value).map_err(|_| rusqlite::Error::InvalidQuery)
                        })
                        .transpose()?,
                    status: match row.get::<_, String>(15)?.as_str() {
                        "in_progress" => PlaybackStatus::InProgress,
                        "completed" => PlaybackStatus::Completed,
                        _ => return Err(rusqlite::Error::InvalidQuery),
                    },
                    updated_at: row.get(16)?,
                })
            } else {
                None
            };
            let download = row
                .get::<_, Option<String>>(17)?
                .map(|state| {
                    Ok::<MediaDownload, rusqlite::Error>(MediaDownload {
                        enclosure_id: id,
                        state: download_state_from_db(&state)?,
                        origin: row
                            .get::<_, Option<String>>(18)?
                            .map(|value| origin_from_db(&value))
                            .transpose()?,
                        local_file: row.get(19)?,
                        file_size_bytes: row
                            .get::<_, Option<i64>>(20)?
                            .map(|value| {
                                u64::try_from(value).map_err(|_| rusqlite::Error::InvalidQuery)
                            })
                            .transpose()?,
                        downloaded_at: row.get(21)?,
                        failure_kind: row
                            .get::<_, Option<String>>(22)?
                            .map(|value| failure_kind_from_db(&value))
                            .transpose()?,
                    })
                })
                .transpose()?;
            Ok(ListeningListEnclosure {
                enclosure: Enclosure {
                    id,
                    article_id: row.get(7)?,
                    url: row.get(8)?,
                    mime_type,
                    size_bytes: row
                        .get::<_, Option<i64>>(10)?
                        .map(|value| {
                            u64::try_from(value).map_err(|_| rusqlite::Error::InvalidQuery)
                        })
                        .transpose()?,
                    remote_media_progression_seconds: u64::try_from(row.get::<_, i64>(11)?)
                        .map_err(|_| rusqlite::Error::InvalidQuery)?,
                },
                remote_present: row.get(12)?,
                duration_ms: row
                    .get::<_, Option<i64>>(23)?
                    .map(|value| u64::try_from(value).map_err(|_| rusqlite::Error::InvalidQuery))
                    .transpose()?
                    .or_else(|| playback_state.as_ref().and_then(|state| state.duration_ms)),
                playback_state,
                download,
            })
        })
        .transpose()?;
    Ok((
        row.get(0)?,
        row.get(1)?,
        row.get(2)?,
        row.get(3)?,
        row.get(4)?,
        row.get(5)?,
        enclosure,
    ))
}
fn saved_playable_media_from_row(
    row: &rusqlite::Row<'_>,
) -> rusqlite::Result<SavedPlayableMediaItem> {
    let mime_type: String = row.get(8)?;
    Ok(SavedPlayableMediaItem {
        enclosure_id: row.get(0)?,
        article_id: row.get(1)?,
        feed_id: row.get(2)?,
        title: row.get(3)?,
        feed_title: row.get(4)?,
        published_at: row.get(5)?,
        added_at: row.get(6)?,
        url: row.get(7)?,
        media_kind: crate::domain::MediaKind::from_mime_type(&mime_type),
        mime_type,
        remote_present: row.get(9)?,
        duration_ms: row
            .get::<_, Option<i64>>(10)?
            .map(|value| u64::try_from(value).map_err(|_| rusqlite::Error::InvalidQuery))
            .transpose()?,
        artwork_source: {
            let image_enclosure_url: Option<String> = row.get(11)?;
            let embedded_artwork_reference: Option<String> = row.get(12)?;
            let article_image_url: Option<String> = row.get(13)?;
            crate::domain::select_media_artwork(
                image_enclosure_url.as_deref(),
                embedded_artwork_reference.as_deref(),
                article_image_url.as_deref(),
            )
        },
    })
}
fn setting_value(connection: &Connection, key: &str) -> Result<String, CoreError> {
    connection
        .query_row(
            "SELECT value FROM core_settings WHERE key=?1",
            [key],
            |row| row.get(0),
        )
        .map_err(sql_error)
}
fn field_name(field: MutationField) -> &'static str {
    match field {
        MutationField::Read => "read",
        MutationField::Starred => "starred",
    }
}
fn parse_field(field: &str) -> Result<MutationField, rusqlite::Error> {
    match field {
        "read" => Ok(MutationField::Read),
        "starred" => Ok(MutationField::Starred),
        _ => Err(rusqlite::Error::InvalidQuery),
    }
}
fn row_u64(row: &rusqlite::Row<'_>, index: usize) -> rusqlite::Result<u64> {
    u64::try_from(row.get::<_, i64>(index)?).map_err(|_| rusqlite::Error::InvalidQuery)
}
fn sql_error(error: rusqlite::Error) -> CoreError {
    CoreError::persistence(error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn roots(temp: &TempDir) -> (std::path::PathBuf, std::path::PathBuf, std::path::PathBuf) {
        let data = temp.path().join("data");
        let cache = temp.path().join("cache");
        let media = temp.path().join("media");
        std::fs::create_dir_all(&data).unwrap();
        (data, cache, media)
    }

    #[test]
    fn navigation_projection_aggregates_catalog_counts_for_each_mode_in_constant_queries() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let categories = [
            Category {
                id: 1,
                title: "First".into(),
            },
            Category {
                id: 2,
                title: "Second".into(),
            },
        ];
        let feeds = [
            Feed {
                id: 10,
                category_id: 1,
                title: "First".into(),
            },
            Feed {
                id: 20,
                category_id: 1,
                title: "Second".into(),
            },
            Feed {
                id: 30,
                category_id: 2,
                title: "No articles".into(),
            },
        ];
        let article = |id, feed_id, is_read, is_starred| Article {
            id,
            feed_id,
            title: format!("Article {id}"),
            url: format!("https://example.test/{id}"),
            comments_url: String::new(),
            published_at: "2026-01-01T00:00:00Z".into(),
            is_read,
            is_starred,
            raw_html_content: String::new(),
            reading_time_minutes: 0,
            preview: String::new(),
            image_url: None,
        };
        store
            .reconcile(
                &categories,
                &feeds,
                &[
                    article(1, 10, false, false),
                    article(2, 10, true, true),
                    article(3, 20, false, true),
                ],
            )
            .unwrap();

        let unread = store
            .navigation_projection(NavigationCountMode::Unread)
            .unwrap();
        assert_eq!(unread.catalog.categories, categories);
        assert_eq!(unread.catalog.feeds, feeds);
        assert_eq!(unread.unread_total, 2);
        assert_eq!(unread.starred_total, 2);
        assert_eq!(
            unread.category_counts,
            vec![
                NavigationScopedCount { id: 1, count: 2 },
                NavigationScopedCount { id: 2, count: 0 },
            ]
        );
        assert_eq!(
            unread.feed_counts,
            vec![
                NavigationScopedCount { id: 10, count: 1 },
                NavigationScopedCount { id: 20, count: 1 },
                NavigationScopedCount { id: 30, count: 0 },
            ]
        );

        let all = store
            .navigation_projection(NavigationCountMode::All)
            .unwrap();
        assert_eq!(all.unread_total, 2);
        assert_eq!(all.starred_total, 2);
        assert_eq!(
            all.category_counts,
            vec![
                NavigationScopedCount { id: 1, count: 3 },
                NavigationScopedCount { id: 2, count: 0 },
            ]
        );
        assert_eq!(
            all.feed_counts,
            vec![
                NavigationScopedCount { id: 10, count: 2 },
                NavigationScopedCount { id: 20, count: 1 },
                NavigationScopedCount { id: 30, count: 0 },
            ]
        );
    }

    #[test]
    fn article_chapters_are_prepared_for_streaming_and_embedded_chapters_win_later() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let article = Article {
            id: 1,
            feed_id: 2,
            title: "Episode".into(),
            url: "https://example.test/episode".into(),
            comments_url: String::new(),
            published_at: "2026-01-01T00:00:00Z".into(),
            is_read: false,
            is_starred: false,
            raw_html_content: "<p>00:00 Intro</p><p>03:42 Topic</p>".into(),
            reading_time_minutes: 0,
            preview: String::new(),
            image_url: None,
        };
        let enclosure = Enclosure {
            id: 10,
            article_id: 1,
            url: "https://example.test/episode.mp3".into(),
            mime_type: "audio/mpeg".into(),
            size_bytes: None,
            remote_media_progression_seconds: 0,
        };
        store
            .reconcile_with_enclosures(
                &[Category {
                    id: 3,
                    title: "Category".into(),
                }],
                &[Feed {
                    id: 2,
                    category_id: 3,
                    title: "Feed".into(),
                }],
                &[article],
                std::slice::from_ref(&enclosure),
            )
            .unwrap();

        assert!(store.media_chapters(10).unwrap().is_empty());
        store.prepare_article_chapters(10).unwrap();
        let article_chapters = store.media_chapters(10).unwrap();
        assert_eq!(article_chapters.len(), 2);
        assert_eq!(
            article_chapters[0].source,
            MediaChapterSource::ArticleContent
        );
        assert_eq!(article_chapters[1].start_ms, 222_000);

        let embedded = vec![MediaChapter {
            enclosure_id: 10,
            title: "Embedded Intro".into(),
            start_ms: 0,
            end_ms: Some(30_000),
            source: MediaChapterSource::Embedded,
        }];
        store
            .replace_media_metadata(
                10,
                &MediaMetadata {
                    enclosure_id: 10,
                    duration_ms: Some(60_000),
                    embedded_artwork_reference: None,
                },
                &embedded,
            )
            .unwrap();
        store.prepare_article_chapters(10).unwrap();
        assert_eq!(store.media_chapters(10).unwrap(), embedded);
    }

    #[test]
    fn media_artwork_source_is_shared_by_playback_and_saved_media_projection() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let article = Article {
            id: 10,
            feed_id: 2,
            title: "Episode".into(),
            url: "https://example.test/episode".into(),
            comments_url: String::new(),
            published_at: "2026-01-01T00:00:00Z".into(),
            is_read: false,
            is_starred: false,
            raw_html_content: String::new(),
            reading_time_minutes: 0,
            preview: String::new(),
            image_url: Some("https://example.test/article.jpg".into()),
        };
        let enclosures = [
            Enclosure {
                id: 100,
                article_id: 10,
                url: "https://example.test/episode.mp3".into(),
                mime_type: "audio/mpeg".into(),
                size_bytes: None,
                remote_media_progression_seconds: 0,
            },
            Enclosure {
                id: 200,
                article_id: 10,
                url: "https://example.test/cover-a.jpg".into(),
                mime_type: "image/jpeg".into(),
                size_bytes: None,
                remote_media_progression_seconds: 0,
            },
            Enclosure {
                id: 201,
                article_id: 10,
                url: "https://example.test/cover-b.jpg".into(),
                mime_type: "image/jpeg".into(),
                size_bytes: None,
                remote_media_progression_seconds: 0,
            },
        ];
        store
            .reconcile_with_enclosures(
                &[Category {
                    id: 1,
                    title: "Category".into(),
                }],
                &[Feed {
                    id: 2,
                    category_id: 1,
                    title: "Feed".into(),
                }],
                &[article],
                &enclosures,
            )
            .unwrap();
        store
            .replace_media_metadata(
                100,
                &MediaMetadata {
                    enclosure_id: 100,
                    duration_ms: None,
                    embedded_artwork_reference: Some("metadata/artwork.png".into()),
                },
                &[],
            )
            .unwrap();

        let expected = Some(MediaArtworkSource::RemoteUrl(
            "https://example.test/cover-a.jpg".into(),
        ));
        assert_eq!(store.media_artwork_source(100).unwrap(), expected);
        store.save_media(100, "2026-01-02T00:00:00Z").unwrap();
        assert_eq!(
            store.saved_playable_media().unwrap()[0].artwork_source,
            expected
        );
    }

    #[test]
    fn legacy_api_url_keeps_the_existing_server_context_when_canonicalized() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        store
            .set_base_url("https://miniflux.example/news/v1")
            .unwrap();
        store
            .connection
            .lock()
            .unwrap()
            .execute(
                "INSERT INTO categories (id, title) VALUES (1, 'Existing')",
                [],
            )
            .unwrap();

        store.set_base_url("https://miniflux.example/news").unwrap();

        assert_eq!(
            store.base_url().unwrap().as_deref(),
            Some("https://miniflux.example/news")
        );
        let category_count: i64 = store
            .connection
            .lock()
            .unwrap()
            .query_row("SELECT COUNT(*) FROM categories", [], |row| row.get(0))
            .unwrap();
        assert_eq!(category_count, 1);
    }

    #[test]
    fn configuration_replacement_discards_server_state_and_replaces_orphan_preferences() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        store.set_base_url("https://old.example").unwrap();
        store
            .connection
            .lock()
            .unwrap()
            .execute_batch("INSERT INTO categories VALUES(1, 'Old'); INSERT INTO feeds VALUES(2, 1, 'Old Feed'); INSERT INTO articles(id,feed_id,title,url,published_at,is_read,is_starred,raw_html_content,preview) VALUES(3,2,'Old','https://old.example/post','2024-01-01T00:00:00Z',0,0,'',''); INSERT INTO pending_mutations VALUES(3,'read',1,1);")
            .unwrap();
        store.set_feed_open_in_miniflux(2, true).unwrap();

        let settings = CoreSettings {
            retention: ReadArticleRetention::Days30,
            delivery_mode: DeliveryMode::Live,
            background_sync_enabled: true,
            detail_character_limit: 5_000,
            download_network_policy: DownloadNetworkPolicy::AnyNetwork,
            download_retention: DownloadRetention::Forever,
            delete_after_playback: false,
            auto_download_listening_list: false,
            remove_completed_listening_list: false,
        };
        let preferences = vec![FeedPreferences {
            feed_id: 999,
            system_notifications_enabled: true,
            detail_rendering: DetailRenderingMode::TextOnly,
            truncate_detail: true,
            open_in_miniflux: true,
            auto_download_audio: false,
        }];
        store
            .replace_configuration("https://new.example", &settings, &preferences)
            .unwrap();

        assert_eq!(
            store.base_url().unwrap().as_deref(),
            Some("https://new.example")
        );
        assert_eq!(store.core_settings().unwrap(), settings);
        assert_eq!(store.all_feed_preferences().unwrap(), preferences);
        let connection = store.connection.lock().unwrap();
        assert_eq!(
            connection
                .query_row::<i64, _, _>("SELECT COUNT(*) FROM articles", [], |row| row.get(0))
                .unwrap(),
            0
        );
        assert_eq!(
            connection
                .query_row::<i64, _, _>("SELECT COUNT(*) FROM pending_mutations", [], |row| row
                    .get(0))
                .unwrap(),
            0
        );
    }

    #[test]
    fn remove_account_state_clears_account_data_but_preserves_core_settings() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        store.set_base_url("https://old.example").unwrap();
        store.set_retention(ReadArticleRetention::Days30).unwrap();
        store
            .connection
            .lock()
            .unwrap()
            .execute_batch("INSERT INTO categories VALUES(1, 'Old'); INSERT INTO feeds VALUES(2, 1, 'Old Feed'); INSERT INTO articles(id,feed_id,title,url,published_at,is_read,is_starred,raw_html_content) VALUES(3,2,'Old','https://old.example/post','2024-01-01T00:00:00Z',0,0,''); INSERT INTO enclosures(id,article_id,url,mime_type,remote_media_progression_seconds) VALUES(4,3,'https://old.example/audio.mp3','audio/mpeg',0);")
            .unwrap();
        store.set_feed_open_in_miniflux(2, true).unwrap();
        store
            .set_state_bulk(&[3], MutationField::Read, true)
            .unwrap();
        store.save_media(4, "2026-01-01T00:00:00Z").unwrap();
        store
            .checkpoint_playback(4, 10_000, Some(60_000), "2026-01-01T00:00:00Z", true)
            .unwrap();
        std::fs::create_dir_all(&media).unwrap();
        std::fs::write(media.join("old-account.mp3"), b"account data").unwrap();

        store.remove_account_state().unwrap();

        assert_eq!(store.base_url().unwrap(), None);
        assert_eq!(
            store.core_settings().unwrap().retention,
            ReadArticleRetention::Days30
        );
        assert!(store.all_feed_preferences().unwrap().is_empty());
        assert!(!media.join("old-account.mp3").exists());
        let connection = store.connection.lock().unwrap();
        assert_eq!(
            connection
                .query_row::<i64, _, _>("SELECT COUNT(*) FROM articles", [], |row| row.get(0))
                .unwrap(),
            0
        );
        assert_eq!(
            connection
                .query_row::<i64, _, _>("SELECT COUNT(*) FROM feeds", [], |row| row.get(0))
                .unwrap(),
            0
        );
        for table in [
            "pending_mutations",
            "enclosures",
            "saved_media",
            "playback_states",
            "pending_media_progress_mutations",
            "media_downloads",
        ] {
            assert_eq!(
                connection
                    .query_row::<i64, _, _>(&format!("SELECT COUNT(*) FROM {table}"), [], |row| row
                        .get(0))
                    .unwrap(),
                0,
                "{table} should be empty after account removal"
            );
        }
    }

    #[test]
    fn v3_migration_reprocesses_and_preserves_article_state() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let path = data.join("flux.sqlite3");
        let connection = Connection::open(&path).unwrap();
        connection.execute_batch("CREATE TABLE core_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL); CREATE TABLE categories (id INTEGER PRIMARY KEY, title TEXT NOT NULL); CREATE TABLE feeds (id INTEGER PRIMARY KEY, category_id INTEGER NOT NULL, title TEXT NOT NULL); CREATE TABLE articles (id INTEGER PRIMARY KEY, feed_id INTEGER NOT NULL, title TEXT NOT NULL, url TEXT NOT NULL, comments_url TEXT NOT NULL DEFAULT '', published_at TEXT NOT NULL, is_read INTEGER NOT NULL, is_starred INTEGER NOT NULL, raw_html_content TEXT NOT NULL, remote_is_read INTEGER, remote_is_starred INTEGER, preview TEXT NOT NULL DEFAULT '', image_url TEXT); CREATE TABLE pending_mutations (article_id INTEGER NOT NULL, field TEXT NOT NULL, desired INTEGER NOT NULL, revision INTEGER NOT NULL, PRIMARY KEY(article_id,field)); INSERT INTO core_settings VALUES ('base_url','https://miniflux.example'); INSERT INTO categories VALUES (1,'Category'); INSERT INTO feeds VALUES (2,1,'Feed'); INSERT INTO articles VALUES (3,2,'Title','https://example.test/post','', '2024-01-01T00:00:00Z',1,1,'<p>Hello <b>world</b></p><img src=\"/cover.jpg\">',1,1,'',''); INSERT INTO pending_mutations VALUES (3,'read',0,7); PRAGMA user_version=3;").unwrap();
        drop(connection);
        let store = Store::open(&data, &cache, &media).unwrap();
        let connection = store.connection.lock().unwrap();
        let row: (i64, String, Option<String>, String, bool, bool, i64, i64) = connection.query_row("SELECT content_processing_version,preview,image_url,raw_html_content,is_read,is_starred,feed_id,(SELECT COUNT(*) FROM pending_mutations) FROM articles WHERE id=3", [], |row| Ok((row.get(0)?,row.get(1)?,row.get(2)?,row.get(3)?,row.get(4)?,row.get(5)?,row.get(6)?,row.get(7)?))).unwrap();
        drop(connection);
        assert_eq!(store.schema_version().unwrap(), SCHEMA_VERSION);
        assert_eq!(row.0, crate::article::PROCESSING_VERSION);
        assert_eq!(row.1, "Hello world");
        assert_eq!(row.2.as_deref(), Some("https://example.test/cover.jpg"));
        assert!(row.3.contains("<b>world</b>"));
        assert!(row.4 && row.5);
        assert_eq!((row.6, row.7), (2, 1));
        assert_eq!(store.core_settings().unwrap(), CoreSettings::default());
        assert_eq!(
            store.base_url().unwrap().as_deref(),
            Some("https://miniflux.example")
        );
    }

    #[test]
    fn v5_migration_preserves_notification_preferences_and_adds_reader_defaults() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let path = data.join("flux.sqlite3");
        let connection = Connection::open(&path).unwrap();
        connection.execute_batch("CREATE TABLE core_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL); CREATE TABLE categories (id INTEGER PRIMARY KEY, title TEXT NOT NULL); CREATE TABLE feeds (id INTEGER PRIMARY KEY, category_id INTEGER NOT NULL REFERENCES categories(id), title TEXT NOT NULL); CREATE TABLE articles (id INTEGER PRIMARY KEY, feed_id INTEGER NOT NULL REFERENCES feeds(id), title TEXT NOT NULL, url TEXT NOT NULL, comments_url TEXT NOT NULL DEFAULT '', published_at TEXT NOT NULL, is_read INTEGER NOT NULL CHECK(is_read IN(0,1)), is_starred INTEGER NOT NULL CHECK(is_starred IN(0,1)), raw_html_content TEXT NOT NULL, remote_is_read INTEGER, remote_is_starred INTEGER, preview TEXT NOT NULL DEFAULT '', image_url TEXT, content_processing_version INTEGER NOT NULL DEFAULT 0); CREATE TABLE pending_mutations (article_id INTEGER NOT NULL REFERENCES articles(id), field TEXT NOT NULL CHECK(field IN ('read','starred')), desired INTEGER NOT NULL CHECK(desired IN(0,1)), revision INTEGER NOT NULL, PRIMARY KEY(article_id,field)); CREATE TABLE feed_system_notification_preferences (feed_id INTEGER PRIMARY KEY REFERENCES feeds(id) ON DELETE CASCADE, enabled INTEGER NOT NULL CHECK(enabled IN(0,1))); CREATE TABLE pending_system_notifications (article_id INTEGER PRIMARY KEY REFERENCES articles(id) ON DELETE CASCADE); CREATE TABLE system_notified_articles (article_id INTEGER PRIMARY KEY REFERENCES articles(id) ON DELETE CASCADE); CREATE TABLE system_notification_candidates (id INTEGER PRIMARY KEY, feed_id INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE, feed_title TEXT NOT NULL); CREATE TABLE notification_candidate_articles (candidate_id INTEGER NOT NULL REFERENCES system_notification_candidates(id) ON DELETE CASCADE, article_id INTEGER NOT NULL REFERENCES articles(id) ON DELETE CASCADE, PRIMARY KEY(candidate_id,article_id)); CREATE INDEX pending_system_notifications_article ON pending_system_notifications(article_id); INSERT INTO categories VALUES (1,'Category'); INSERT INTO feeds VALUES (2,1,'Enabled'),(3,1,'Disabled'); INSERT INTO feed_system_notification_preferences VALUES (2,1),(3,0); PRAGMA user_version=5;").unwrap();
        drop(connection);

        let store = Store::open(&data, &cache, &media).unwrap();
        assert_eq!(store.schema_version().unwrap(), SCHEMA_VERSION);
        assert_eq!(
            store.feed_preferences(2).unwrap(),
            FeedPreferences {
                feed_id: 2,
                system_notifications_enabled: true,
                detail_rendering: DetailRenderingMode::Rendered,
                truncate_detail: false,
                open_in_miniflux: false,
                auto_download_audio: false
            }
        );
        assert_eq!(
            store.feed_preferences(3).unwrap(),
            FeedPreferences::defaults(3)
        );
        assert_eq!(
            store.core_settings().unwrap().detail_character_limit,
            10_000
        );
    }

    #[test]
    fn v21_migration_makes_notification_candidate_ids_autoincrement() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);

        {
            let store = Store::open(&data, &cache, &media).unwrap();
            let connection = store.connection.lock().unwrap();
            connection.execute_batch("DROP TABLE notification_candidate_articles; DROP TABLE system_notification_candidates; CREATE TABLE system_notification_candidates (id INTEGER PRIMARY KEY, feed_id INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE, feed_title TEXT NOT NULL); CREATE TABLE notification_candidate_articles (candidate_id INTEGER NOT NULL REFERENCES system_notification_candidates(id) ON DELETE CASCADE, article_id INTEGER NOT NULL REFERENCES articles(id) ON DELETE CASCADE, PRIMARY KEY(candidate_id,article_id)); PRAGMA user_version=21;").unwrap();
        }

        let migrated = Store::open(&data, &cache, &media).unwrap();
        assert_eq!(migrated.schema_version().unwrap(), SCHEMA_VERSION);
        let sql: String = migrated
            .connection
            .lock()
            .unwrap()
            .query_row(
                "SELECT sql FROM sqlite_master WHERE type='table' AND name='system_notification_candidates'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert!(sql.contains("AUTOINCREMENT"));
    }

    #[test]
    fn schema_22_database_reopens_after_migration() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);

        {
            let store = Store::open(&data, &cache, &media).unwrap();
            assert_eq!(store.schema_version().unwrap(), SCHEMA_VERSION);
        }

        let reopened = Store::open(&data, &cache, &media).unwrap();
        assert_eq!(reopened.schema_version().unwrap(), SCHEMA_VERSION);
    }

    #[test]
    fn bulk_feed_preferences_patch_is_atomic_and_preserves_unpatched_values() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let categories = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [
            Feed {
                id: 10,
                category_id: 1,
                title: "One".into(),
            },
            Feed {
                id: 20,
                category_id: 1,
                title: "Two".into(),
            },
        ];
        store.reconcile(&categories, &feeds, &[]).unwrap();
        store.set_feed_truncate_detail(10, true).unwrap();

        store
            .patch_feed_preferences_bulk(
                &[10, 20],
                FeedPreferencesPatch {
                    detail_rendering: Some(DetailRenderingMode::TextOnly),
                    open_in_miniflux: Some(true),
                    ..FeedPreferencesPatch::default()
                },
            )
            .unwrap();

        let values = store.feed_preferences_bulk(&[10, 20]).unwrap();
        assert_eq!(values.len(), 2);
        assert_eq!(values[0].detail_rendering, DetailRenderingMode::TextOnly);
        assert!(values[0].truncate_detail);
        assert!(values[0].open_in_miniflux);
        assert_eq!(values[1].detail_rendering, DetailRenderingMode::TextOnly);
        assert!(!values[1].truncate_detail);
        assert!(values[1].open_in_miniflux);

        let before = store.feed_preferences(10).unwrap();
        assert!(
            store
                .patch_feed_preferences_bulk(
                    &[10, 999],
                    FeedPreferencesPatch {
                        truncate_detail: Some(false),
                        ..FeedPreferencesPatch::default()
                    },
                )
                .is_err()
        );
        assert_eq!(store.feed_preferences(10).unwrap(), before);
    }

    #[test]
    fn bulk_notification_enablement_starts_from_current_point() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let categories = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 2,
            category_id: 1,
            title: "Feed".into(),
        }];
        let article = |id| Article {
            id,
            feed_id: 2,
            title: format!("Article {id}"),
            url: format!("https://example.test/{id}"),
            comments_url: String::new(),
            published_at: format!("2026-02-0{id}T00:00:00Z"),
            is_read: false,
            is_starred: false,
            raw_html_content: String::new(),
            reading_time_minutes: 0,
            preview: String::new(),
            image_url: None,
        };

        let before_enable = store.reconcile(&categories, &feeds, &[article(1)]).unwrap();
        assert!(
            store
                .prepare_system_notification_candidates(&before_enable.new_article_ids_by_feed)
                .unwrap()
                .is_empty()
        );

        store
            .patch_feed_preferences_bulk(
                &[2],
                FeedPreferencesPatch {
                    system_notifications_enabled: Some(true),
                    ..FeedPreferencesPatch::default()
                },
            )
            .unwrap();

        assert!(
            store
                .prepare_system_notification_candidates(&before_enable.new_article_ids_by_feed)
                .unwrap()
                .is_empty()
        );

        let after_enable = store
            .reconcile(&categories, &feeds, &[article(1), article(2)])
            .unwrap();
        let candidates = store
            .prepare_system_notification_candidates(&after_enable.new_article_ids_by_feed)
            .unwrap();
        assert_eq!(candidates.len(), 1);
        assert_eq!(candidates[0].new_count, 1);
    }

    #[test]
    fn system_notification_candidate_ids_are_not_reused_after_acknowledgement() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let categories = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 2,
            category_id: 1,
            title: "Feed".into(),
        }];
        let article = |id| Article {
            id,
            feed_id: 2,
            title: format!("Article {id}"),
            url: format!("https://example.test/{id}"),
            comments_url: String::new(),
            published_at: format!("2026-03-0{id}T00:00:00Z"),
            is_read: false,
            is_starred: false,
            raw_html_content: String::new(),
            reading_time_minutes: 0,
            preview: String::new(),
            image_url: None,
        };

        store.reconcile(&categories, &feeds, &[article(1)]).unwrap();
        store
            .set_feed_system_notifications_enabled(2, true)
            .unwrap();

        let first_stats = store
            .reconcile(&categories, &feeds, &[article(1), article(2)])
            .unwrap();
        let first = store
            .prepare_system_notification_candidates(&first_stats.new_article_ids_by_feed)
            .unwrap()
            .into_iter()
            .next()
            .unwrap();
        store
            .acknowledge_system_notification(first.candidate_id)
            .unwrap();

        let second_stats = store
            .reconcile(&categories, &feeds, &[article(1), article(2), article(3)])
            .unwrap();
        let second = store
            .prepare_system_notification_candidates(&second_stats.new_article_ids_by_feed)
            .unwrap()
            .into_iter()
            .next()
            .unwrap();

        assert!(second.candidate_id > first.candidate_id);
    }

    #[test]
    fn system_notifications_only_queue_articles_after_feed_enablement() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let categories = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 2,
            category_id: 1,
            title: "Feed".into(),
        }];
        let article = |id| Article {
            id,
            feed_id: 2,
            title: format!("Article {id}"),
            url: format!("https://example.test/{id}"),
            comments_url: String::new(),
            published_at: format!("2026-01-0{id}T00:00:00Z"),
            is_read: false,
            is_starred: false,
            raw_html_content: String::new(),
            reading_time_minutes: 0,
            preview: String::new(),
            image_url: None,
        };

        let before_enable = store.reconcile(&categories, &feeds, &[article(1)]).unwrap();
        assert!(
            store
                .prepare_system_notification_candidates(&before_enable.new_article_ids_by_feed)
                .unwrap()
                .is_empty()
        );

        store
            .set_feed_system_notifications_enabled(2, true)
            .unwrap();

        // Replaying pre-enable IDs must not create a notification backlog.
        assert!(
            store
                .prepare_system_notification_candidates(&before_enable.new_article_ids_by_feed)
                .unwrap()
                .is_empty()
        );

        let after_enable = store
            .reconcile(&categories, &feeds, &[article(1), article(2)])
            .unwrap();
        let candidates = store
            .prepare_system_notification_candidates(&after_enable.new_article_ids_by_feed)
            .unwrap();
        assert_eq!(candidates.len(), 1);
        assert_eq!(candidates[0].feed_id, 2);
        assert_eq!(candidates[0].new_count, 1);

        store
            .set_feed_system_notifications_enabled(2, false)
            .unwrap();
        let connection = store.connection.lock().unwrap();
        assert_eq!(
            connection
                .query_row(
                    "SELECT COUNT(*) FROM pending_system_notifications",
                    [],
                    |row| row.get::<_, i64>(0)
                )
                .unwrap(),
            0
        );
        assert_eq!(
            connection
                .query_row(
                    "SELECT COUNT(*) FROM system_notification_candidates",
                    [],
                    |row| row.get::<_, i64>(0)
                )
                .unwrap(),
            0
        );
    }

    #[test]
    fn feed_preferences_are_independent_persistent_and_reset_after_feed_reappears() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let categories = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 2,
            category_id: 1,
            title: "Feed".into(),
        }];
        store.reconcile(&categories, &feeds, &[]).unwrap();
        assert_eq!(
            store.feed_preferences(2).unwrap(),
            FeedPreferences::defaults(2)
        );
        store
            .set_feed_system_notifications_enabled(2, true)
            .unwrap();
        store
            .set_feed_detail_rendering(2, DetailRenderingMode::TextOnly)
            .unwrap();
        store.set_feed_truncate_detail(2, true).unwrap();
        store.set_feed_open_in_miniflux(2, true).unwrap();
        store.set_feed_auto_download_audio(2, true).unwrap();
        assert_eq!(
            store.feed_preferences(2).unwrap(),
            FeedPreferences {
                feed_id: 2,
                system_notifications_enabled: true,
                detail_rendering: DetailRenderingMode::TextOnly,
                truncate_detail: true,
                open_in_miniflux: true,
                auto_download_audio: true
            }
        );
        drop(store);
        let store = Store::open(&data, &cache, &media).unwrap();
        assert_eq!(
            store.feed_preferences(2).unwrap(),
            FeedPreferences {
                feed_id: 2,
                system_notifications_enabled: true,
                detail_rendering: DetailRenderingMode::TextOnly,
                truncate_detail: true,
                open_in_miniflux: true,
                auto_download_audio: true
            }
        );
        store.reconcile(&categories, &[], &[]).unwrap();
        assert!(store.feed_preferences(2).is_err());
        store.reconcile(&categories, &feeds, &[]).unwrap();
        assert_eq!(
            store.feed_preferences(2).unwrap(),
            FeedPreferences::defaults(2)
        );
    }

    #[test]
    fn legacy_open_in_miniflux_import_respects_native_presence_and_missing_feeds() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let categories = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [
            Feed {
                id: 2,
                category_id: 1,
                title: "Legacy".into(),
            },
            Feed {
                id: 3,
                category_id: 1,
                title: "Native".into(),
            },
        ];
        store.reconcile(&categories, &feeds, &[]).unwrap();

        assert_eq!(
            store.import_legacy_feed_open_in_miniflux(2).unwrap(),
            LegacyFeedOpenInMinifluxImportOutcome::Imported
        );
        assert!(store.feed_preferences(2).unwrap().open_in_miniflux);
        assert_eq!(
            store.import_legacy_feed_open_in_miniflux(2).unwrap(),
            LegacyFeedOpenInMinifluxImportOutcome::AlreadyPresent
        );

        store.set_feed_open_in_miniflux(3, false).unwrap();
        assert_eq!(
            store.import_legacy_feed_open_in_miniflux(3).unwrap(),
            LegacyFeedOpenInMinifluxImportOutcome::AlreadyPresent
        );
        assert!(!store.feed_preferences(3).unwrap().open_in_miniflux);
        assert_eq!(
            store.import_legacy_feed_open_in_miniflux(4).unwrap(),
            LegacyFeedOpenInMinifluxImportOutcome::MissingFeed
        );
    }

    #[test]
    fn v19_marks_historical_feed_preferences_as_native_owned() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let categories = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 2,
            category_id: 1,
            title: "Historical native preference".into(),
        }];
        store.reconcile(&categories, &feeds, &[]).unwrap();
        store.set_feed_open_in_miniflux(2, false).unwrap();
        {
            let connection = store.connection.lock().unwrap();
            connection
                .execute_batch(
                    "DROP TABLE feed_open_in_miniflux_overrides; PRAGMA user_version=18;",
                )
                .unwrap();
        }
        drop(store);

        let store = Store::open(&data, &cache, &media).unwrap();
        assert_eq!(store.schema_version().unwrap(), SCHEMA_VERSION);
        assert_eq!(
            store.import_legacy_feed_open_in_miniflux(2).unwrap(),
            LegacyFeedOpenInMinifluxImportOutcome::AlreadyPresent
        );
        assert!(!store.feed_preferences(2).unwrap().open_in_miniflux);
    }

    #[test]
    fn v20_marks_historical_policy_settings_as_native_owned() {
        for (background_sync_enabled, auto_download_listening_list) in
            [(false, false), (false, true), (true, false), (true, true)]
        {
            let temp = TempDir::new().unwrap();
            let (data, cache, media) = roots(&temp);
            let store = Store::open(&data, &cache, &media).unwrap();
            {
                let connection = store.connection.lock().unwrap();
                connection
                    .execute(
                        "UPDATE core_settings SET value = ?1 WHERE key = 'background_sync_enabled'",
                        [if background_sync_enabled { "1" } else { "0" }],
                    )
                    .unwrap();
                connection.execute(
                    "UPDATE core_settings SET value = ?1 WHERE key = 'auto_download_listening_list'",
                    [if auto_download_listening_list { "1" } else { "0" }],
                ).unwrap();
                connection.execute_batch("DELETE FROM core_settings WHERE key IN ('background_sync_enabled_explicit', 'auto_download_listening_list_explicit'); PRAGMA user_version=19;").unwrap();
            }
            drop(store);

            let store = Store::open(&data, &cache, &media).unwrap();
            assert_eq!(store.schema_version().unwrap(), SCHEMA_VERSION);
            {
                let connection = store.connection.lock().unwrap();
                for key in [
                    "background_sync_enabled_explicit",
                    "auto_download_listening_list_explicit",
                ] {
                    assert_eq!(
                        connection
                            .query_row(
                                "SELECT value FROM core_settings WHERE key = ?1",
                                [key],
                                |row| row.get::<_, String>(0)
                            )
                            .unwrap(),
                        "1"
                    );
                }
            }
            store
                .import_legacy_policy_settings(
                    Some(!background_sync_enabled),
                    Some(!auto_download_listening_list),
                )
                .unwrap();
            let settings = store.core_settings().unwrap();
            assert_eq!(settings.background_sync_enabled, background_sync_enabled);
            assert_eq!(
                settings.auto_download_listening_list,
                auto_download_listening_list
            );
        }
    }

    #[test]
    fn fresh_v20_policy_defaults_are_not_owned_until_a_legacy_import() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        assert_eq!(store.schema_version().unwrap(), SCHEMA_VERSION);
        {
            let connection = store.connection.lock().unwrap();
            for key in [
                "background_sync_enabled_explicit",
                "auto_download_listening_list_explicit",
            ] {
                assert_eq!(
                    connection
                        .query_row(
                            "SELECT value FROM core_settings WHERE key = ?1",
                            [key],
                            |row| row.get::<_, String>(0)
                        )
                        .unwrap(),
                    "0"
                );
            }
        }
        store
            .import_legacy_policy_settings(Some(false), Some(true))
            .unwrap();
        let settings = store.core_settings().unwrap();
        assert!(!settings.background_sync_enabled);
        assert!(settings.auto_download_listening_list);
    }

    #[test]
    fn media_policy_settings_persist_independently() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();

        store.set_auto_download_listening_list(true).unwrap();
        store.set_delete_after_playback(false).unwrap();
        store.set_remove_completed_listening_list(true).unwrap();

        let settings = store.core_settings().unwrap();
        assert!(settings.auto_download_listening_list);
        assert!(!settings.delete_after_playback);
        assert!(settings.remove_completed_listening_list);

        drop(store);
        let store = Store::open(&data, &cache, &media).unwrap();
        assert_eq!(store.core_settings().unwrap(), settings);
    }

    #[test]
    fn legacy_policy_import_uses_presence_not_default_values_and_is_atomic() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();

        store
            .import_legacy_policy_settings(Some(false), Some(true))
            .unwrap();
        let settings = store.core_settings().unwrap();
        assert!(!settings.background_sync_enabled);
        assert!(settings.auto_download_listening_list);

        // Imported values now own their fields, including false, just like an
        // explicit native Settings write does.
        store
            .import_legacy_policy_settings(Some(true), Some(false))
            .unwrap();
        let settings = store.core_settings().unwrap();
        assert!(!settings.background_sync_enabled);
        assert!(settings.auto_download_listening_list);
    }

    #[test]
    fn legacy_media_settings_import_is_atomic() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        {
            let connection = store.connection.lock().unwrap();
            connection
                .execute_batch("CREATE TRIGGER reject_legacy_delete_after_playback BEFORE INSERT ON core_settings WHEN NEW.key = 'delete_after_playback' BEGIN SELECT RAISE(ABORT, 'test failure'); END;")
                .unwrap();
        }

        assert!(
            store
                .import_legacy_media_settings(
                    Some(true),
                    Some(DownloadRetention::Days(14)),
                    Some(true),
                )
                .is_err()
        );
        assert_eq!(store.core_settings().unwrap(), CoreSettings::default());
    }

    #[test]
    fn v7_migration_preserves_preferences_and_removes_feed_foreign_key() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let path = data.join("flux.sqlite3");
        let connection = Connection::open(&path).unwrap();
        connection.execute_batch("CREATE TABLE core_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL); CREATE TABLE categories (id INTEGER PRIMARY KEY, title TEXT NOT NULL); CREATE TABLE feeds (id INTEGER PRIMARY KEY, category_id INTEGER NOT NULL REFERENCES categories(id), title TEXT NOT NULL); CREATE TABLE articles (id INTEGER PRIMARY KEY, feed_id INTEGER NOT NULL REFERENCES feeds(id), title TEXT NOT NULL, url TEXT NOT NULL, comments_url TEXT NOT NULL DEFAULT '', published_at TEXT NOT NULL, is_read INTEGER NOT NULL CHECK(is_read IN(0,1)), is_starred INTEGER NOT NULL CHECK(is_starred IN(0,1)), raw_html_content TEXT NOT NULL, remote_is_read INTEGER, remote_is_starred INTEGER, preview TEXT NOT NULL DEFAULT '', image_url TEXT, content_processing_version INTEGER NOT NULL DEFAULT 0); CREATE TABLE pending_mutations (article_id INTEGER NOT NULL REFERENCES articles(id), field TEXT NOT NULL CHECK(field IN ('read','starred')), desired INTEGER NOT NULL CHECK(desired IN(0,1)), revision INTEGER NOT NULL, PRIMARY KEY(article_id,field)); CREATE TABLE pending_system_notifications (article_id INTEGER PRIMARY KEY REFERENCES articles(id) ON DELETE CASCADE); CREATE TABLE system_notified_articles (article_id INTEGER PRIMARY KEY REFERENCES articles(id) ON DELETE CASCADE); CREATE TABLE system_notification_candidates (id INTEGER PRIMARY KEY, feed_id INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE, feed_title TEXT NOT NULL); CREATE TABLE notification_candidate_articles (candidate_id INTEGER NOT NULL REFERENCES system_notification_candidates(id) ON DELETE CASCADE, article_id INTEGER NOT NULL REFERENCES articles(id) ON DELETE CASCADE, PRIMARY KEY(candidate_id,article_id)); CREATE TABLE feed_preferences (feed_id INTEGER PRIMARY KEY REFERENCES feeds(id) ON DELETE CASCADE, system_notifications_enabled INTEGER NOT NULL DEFAULT 0 CHECK(system_notifications_enabled IN(0,1)), detail_rendering TEXT NOT NULL DEFAULT 'rendered' CHECK(detail_rendering IN('rendered','text_only')), truncate_detail INTEGER NOT NULL DEFAULT 0 CHECK(truncate_detail IN(0,1)), open_in_miniflux INTEGER NOT NULL DEFAULT 0 CHECK(open_in_miniflux IN(0,1))); INSERT INTO categories VALUES (1,'Category'); INSERT INTO feeds VALUES (123,1,'One'); INSERT INTO feeds VALUES (456,1,'Two'); INSERT INTO articles VALUES (9,123,'Article','https://example.test','', '2026-01-01T00:00:00Z',0,0,0,0,'content','',NULL,0); INSERT INTO feed_preferences VALUES (123,1,'text_only',1,1); INSERT INTO feed_preferences VALUES (456,0,'rendered',0,1); PRAGMA user_version=6;").unwrap();
        drop(connection);

        let store = Store::open(&data, &cache, &media).unwrap();
        assert_eq!(store.schema_version().unwrap(), SCHEMA_VERSION);
        assert_eq!(
            store.feed_preferences(123).unwrap(),
            FeedPreferences {
                feed_id: 123,
                system_notifications_enabled: true,
                detail_rendering: DetailRenderingMode::TextOnly,
                truncate_detail: true,
                open_in_miniflux: true,
                auto_download_audio: false
            }
        );
        assert_eq!(
            store.feed_preferences(456).unwrap(),
            FeedPreferences {
                feed_id: 456,
                system_notifications_enabled: false,
                detail_rendering: DetailRenderingMode::Rendered,
                truncate_detail: false,
                open_in_miniflux: true,
                auto_download_audio: false
            }
        );
        let connection = store.connection.lock().unwrap();
        assert_eq!(
            connection
                .query_row("SELECT feed_id FROM articles WHERE id=9", [], |row| row
                    .get::<_, i64>(0))
                .unwrap(),
            123
        );
        let foreign_key_count: i64 = connection
            .query_row(
                "SELECT COUNT(*) FROM pragma_foreign_key_list('feed_preferences')",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(foreign_key_count, 0);
    }

    // Legacy migration fixtures must include the notification tables introduced
    // in schema v5. The tests below otherwise model impossible v7-v13 schemas.
    fn add_legacy_notification_fixture_tables(connection: &Connection) {
        connection.execute_batch(
            "CREATE TABLE pending_system_notifications (article_id INTEGER PRIMARY KEY REFERENCES articles(id) ON DELETE CASCADE);
             CREATE TABLE system_notified_articles (article_id INTEGER PRIMARY KEY REFERENCES articles(id) ON DELETE CASCADE);
             CREATE TABLE system_notification_candidates (id INTEGER PRIMARY KEY, feed_id INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE, feed_title TEXT NOT NULL);
             CREATE TABLE notification_candidate_articles (candidate_id INTEGER NOT NULL REFERENCES system_notification_candidates(id) ON DELETE CASCADE, article_id INTEGER NOT NULL REFERENCES articles(id) ON DELETE CASCADE, PRIMARY KEY(candidate_id,article_id));",
        ).unwrap();
    }

    #[test]
    fn v8_migration_preserves_phase_a_data_and_creates_enclosures() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let path = data.join("flux.sqlite3");
        let connection = Connection::open(&path).unwrap();
        connection.execute_batch("CREATE TABLE core_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL); CREATE TABLE categories (id INTEGER PRIMARY KEY, title TEXT NOT NULL); CREATE TABLE feeds (id INTEGER PRIMARY KEY, category_id INTEGER NOT NULL REFERENCES categories(id), title TEXT NOT NULL); CREATE TABLE articles (id INTEGER PRIMARY KEY, feed_id INTEGER NOT NULL REFERENCES feeds(id), title TEXT NOT NULL, url TEXT NOT NULL, comments_url TEXT NOT NULL DEFAULT '', published_at TEXT NOT NULL, is_read INTEGER NOT NULL, is_starred INTEGER NOT NULL, raw_html_content TEXT NOT NULL, remote_is_read INTEGER, remote_is_starred INTEGER, preview TEXT NOT NULL DEFAULT '', image_url TEXT, content_processing_version INTEGER NOT NULL DEFAULT 0); INSERT INTO core_settings VALUES ('base_url','https://miniflux.example'); INSERT INTO categories VALUES (1,'Category'); INSERT INTO feeds VALUES (2,1,'Feed'); INSERT INTO articles VALUES (3,2,'Title','https://example.test/post','', '2024-01-01T00:00:00Z',1,0,'<p>Saved</p>',1,0,'Saved',NULL,1); PRAGMA user_version=7;").unwrap();
        add_legacy_notification_fixture_tables(&connection);
        drop(connection);

        let store = Store::open(&data, &cache, &media).unwrap();
        assert_eq!(store.schema_version().unwrap(), SCHEMA_VERSION);
        let connection = store.connection.lock().unwrap();
        assert_eq!(
            connection
                .query_row("SELECT title FROM articles WHERE id=3", [], |row| row
                    .get::<_, String>(0))
                .unwrap(),
            "Title"
        );
        let columns = connection
            .prepare("SELECT name FROM pragma_table_info('enclosures') ORDER BY cid")
            .unwrap()
            .query_map([], |row| row.get::<_, String>(0))
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();
        assert_eq!(
            columns,
            vec![
                "id",
                "article_id",
                "url",
                "mime_type",
                "size_bytes",
                "remote_media_progression_seconds",
                "remote_present",
            ]
        );
    }

    #[test]
    fn enclosure_storage_round_trips_updates_and_cascades_from_articles() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let categories = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 2,
            category_id: 1,
            title: "Feed".into(),
        }];
        let articles = [Article {
            id: 3,
            feed_id: 2,
            title: "Article".into(),
            url: "https://example.test/article".into(),
            comments_url: String::new(),
            published_at: "2024-01-01T00:00:00Z".into(),
            is_read: false,
            is_starred: false,
            raw_html_content: String::new(),
            reading_time_minutes: 0,
            preview: String::new(),
            image_url: None,
        }];
        let enclosures = [
            Enclosure {
                id: 11,
                article_id: 3,
                url: "https://cdn.test/episode.mp3?token=raw".into(),
                mime_type: "audio/mpeg; codecs=mp3".into(),
                size_bytes: Some(123_456),
                remote_media_progression_seconds: 42,
            },
            Enclosure {
                id: 12,
                article_id: 3,
                url: "https://cdn.test/cover.custom".into(),
                mime_type: "application/x-cover".into(),
                size_bytes: None,
                remote_media_progression_seconds: 0,
            },
        ];

        store
            .reconcile_with_enclosures(&categories, &feeds, &articles, &enclosures)
            .unwrap();
        assert_eq!(
            store.enclosures_for_article(3).unwrap(),
            enclosures
                .iter()
                .cloned()
                .map(|enclosure| StoredEnclosure {
                    enclosure,
                    remote_present: true,
                })
                .collect::<Vec<_>>()
        );

        store
            .reconcile_with_enclosures(&categories, &feeds, &articles, &[])
            .unwrap();
        assert_eq!(
            store
                .enclosures_for_article(3)
                .unwrap()
                .iter()
                .map(|enclosure| enclosure.remote_present)
                .collect::<Vec<_>>(),
            vec![false, false]
        );

        store.set_enclosure_remote_present(11, false).unwrap();
        assert!(!store.enclosure(11).unwrap().unwrap().remote_present);
        let updated = Enclosure {
            id: 11,
            article_id: 3,
            url: "https://cdn.test/episode-updated.mp3".into(),
            mime_type: "audio/ogg".into(),
            size_bytes: None,
            remote_media_progression_seconds: 99,
        };
        store
            .upsert_remote_enclosures(std::slice::from_ref(&updated))
            .unwrap();
        assert_eq!(
            store.enclosure(11).unwrap(),
            Some(StoredEnclosure {
                enclosure: updated,
                remote_present: true,
            })
        );
        assert_eq!(store.enclosures_for_article(3).unwrap().len(), 2);

        store
            .connection
            .lock()
            .unwrap()
            .execute("DELETE FROM articles WHERE id=3", [])
            .unwrap();
        assert!(store.enclosure(11).unwrap().is_none());
        assert!(store.enclosures_for_article(3).unwrap().is_empty());
    }

    #[test]
    fn reconciliation_marks_missing_enclosures_only_for_fetched_articles() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let categories = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 2,
            category_id: 1,
            title: "Feed".into(),
        }];
        let article = |id| Article {
            id,
            feed_id: 2,
            title: format!("Article {id}"),
            url: format!("https://example.test/{id}"),
            comments_url: String::new(),
            published_at: "2024-01-01T00:00:00Z".into(),
            is_read: false,
            is_starred: false,
            raw_html_content: String::new(),
            reading_time_minutes: 0,
            preview: String::new(),
            image_url: None,
        };
        let articles = [article(1), article(2)];
        store
            .reconcile_with_enclosures(
                &categories,
                &feeds,
                &articles,
                &[
                    Enclosure {
                        id: 10,
                        article_id: 1,
                        url: "https://cdn.test/10.mp3".into(),
                        mime_type: "audio/mpeg".into(),
                        size_bytes: Some(10),
                        remote_media_progression_seconds: 1,
                    },
                    Enclosure {
                        id: 11,
                        article_id: 1,
                        url: "https://cdn.test/11.mp3".into(),
                        mime_type: "audio/mpeg".into(),
                        size_bytes: Some(11),
                        remote_media_progression_seconds: 2,
                    },
                    Enclosure {
                        id: 20,
                        article_id: 2,
                        url: "https://cdn.test/20.mp3".into(),
                        mime_type: "audio/mpeg".into(),
                        size_bytes: Some(20),
                        remote_media_progression_seconds: 3,
                    },
                ],
            )
            .unwrap();

        let reappearing = Enclosure {
            id: 10,
            article_id: 1,
            url: "https://cdn.test/10-new.mp3".into(),
            mime_type: "audio/ogg".into(),
            size_bytes: None,
            remote_media_progression_seconds: 99,
        };
        let inserted = Enclosure {
            id: 12,
            article_id: 1,
            url: "https://cdn.test/12.mp3".into(),
            mime_type: "video/mp4".into(),
            size_bytes: Some(12),
            remote_media_progression_seconds: 4,
        };
        store
            .reconcile_with_enclosures(
                &categories,
                &feeds,
                &[article(1)],
                &[reappearing.clone(), inserted],
            )
            .unwrap();
        assert_eq!(
            store.enclosure(10).unwrap(),
            Some(StoredEnclosure {
                enclosure: reappearing.clone(),
                remote_present: true,
            })
        );
        assert!(!store.enclosure(11).unwrap().unwrap().remote_present);
        assert!(store.enclosure(12).unwrap().unwrap().remote_present);
        assert!(store.enclosure(20).unwrap().unwrap().remote_present);

        store
            .reconcile_with_enclosures(&categories, &feeds, &[article(1)], &[])
            .unwrap();
        assert!(!store.enclosure(10).unwrap().unwrap().remote_present);
        assert!(!store.enclosure(12).unwrap().unwrap().remote_present);
        assert!(store.enclosure(20).unwrap().unwrap().remote_present);

        store
            .reconcile_with_enclosures(
                &categories,
                &feeds,
                &[article(1)],
                std::slice::from_ref(&reappearing),
            )
            .unwrap();
        assert_eq!(
            store.enclosure(10).unwrap(),
            Some(StoredEnclosure {
                enclosure: reappearing,
                remote_present: true,
            })
        );
    }

    #[test]
    fn v9_migration_preserves_enclosures() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let connection = Connection::open(data.join("flux.sqlite3")).unwrap();
        connection.execute_batch("CREATE TABLE core_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL); CREATE TABLE categories (id INTEGER PRIMARY KEY, title TEXT NOT NULL); CREATE TABLE feeds (id INTEGER PRIMARY KEY, category_id INTEGER NOT NULL REFERENCES categories(id), title TEXT NOT NULL); CREATE TABLE articles (id INTEGER PRIMARY KEY, feed_id INTEGER NOT NULL REFERENCES feeds(id), title TEXT NOT NULL, url TEXT NOT NULL, comments_url TEXT NOT NULL DEFAULT '', published_at TEXT NOT NULL, is_read INTEGER NOT NULL, is_starred INTEGER NOT NULL, raw_html_content TEXT NOT NULL, remote_is_read INTEGER, remote_is_starred INTEGER, preview TEXT NOT NULL DEFAULT '', image_url TEXT, content_processing_version INTEGER NOT NULL DEFAULT 0); CREATE TABLE enclosures (id INTEGER PRIMARY KEY, article_id INTEGER NOT NULL REFERENCES articles(id) ON DELETE CASCADE, url TEXT NOT NULL, mime_type TEXT NOT NULL, size_bytes INTEGER, remote_media_progression_seconds INTEGER NOT NULL, remote_present INTEGER NOT NULL DEFAULT 1); INSERT INTO categories VALUES(1,'Category'); INSERT INTO feeds VALUES(2,1,'Feed'); INSERT INTO articles VALUES(3,2,'Article','https://example.test/article','','2024-01-01T00:00:00Z',1,0,'',1,0,'',NULL,1); INSERT INTO enclosures VALUES(10,3,'https://cdn.test/episode.mp3','audio/mpeg',123,4,0); PRAGMA user_version=8;").unwrap();
        add_legacy_notification_fixture_tables(&connection);
        drop(connection);

        let store = Store::open(&data, &cache, &media).unwrap();
        assert_eq!(store.schema_version().unwrap(), SCHEMA_VERSION);
        assert!(!store.enclosure(10).unwrap().unwrap().remote_present);
        assert_eq!(
            store
                .connection
                .lock()
                .unwrap()
                .query_row("SELECT COUNT(*) FROM saved_media", [], |row| row
                    .get::<_, i64>(0))
                .unwrap(),
            0
        );
    }

    #[test]
    fn v12_migration_creates_media_downloads_and_preserves_phase_b_data() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let connection = Connection::open(data.join("flux.sqlite3")).unwrap();
        connection.execute_batch(
            "CREATE TABLE core_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL); \
             CREATE TABLE categories (id INTEGER PRIMARY KEY, title TEXT NOT NULL); \
             CREATE TABLE feeds (id INTEGER PRIMARY KEY, category_id INTEGER NOT NULL REFERENCES categories(id), title TEXT NOT NULL); \
             CREATE TABLE articles (id INTEGER PRIMARY KEY, feed_id INTEGER NOT NULL REFERENCES feeds(id), title TEXT NOT NULL, url TEXT NOT NULL, comments_url TEXT NOT NULL DEFAULT '', published_at TEXT NOT NULL, is_read INTEGER NOT NULL, is_starred INTEGER NOT NULL, raw_html_content TEXT NOT NULL, remote_is_read INTEGER, remote_is_starred INTEGER, preview TEXT NOT NULL DEFAULT '', image_url TEXT, content_processing_version INTEGER NOT NULL DEFAULT 0); \
             CREATE TABLE pending_mutations (article_id INTEGER NOT NULL, field TEXT NOT NULL CHECK(field IN ('read','starred')), desired INTEGER NOT NULL CHECK(desired IN(0,1)), revision INTEGER NOT NULL, PRIMARY KEY(article_id,field)); \
             CREATE TABLE enclosures (id INTEGER PRIMARY KEY, article_id INTEGER NOT NULL REFERENCES articles(id) ON DELETE CASCADE, url TEXT NOT NULL, mime_type TEXT NOT NULL, size_bytes INTEGER, remote_media_progression_seconds INTEGER NOT NULL, remote_present INTEGER NOT NULL DEFAULT 1); \
             CREATE TABLE saved_media (enclosure_id INTEGER PRIMARY KEY REFERENCES enclosures(id) ON DELETE CASCADE, added_at TEXT NOT NULL); \
             CREATE TABLE playback_states (enclosure_id INTEGER PRIMARY KEY REFERENCES enclosures(id) ON DELETE CASCADE, position_ms INTEGER NOT NULL, duration_ms INTEGER, status TEXT NOT NULL CHECK(status IN ('in_progress','completed')), updated_at TEXT NOT NULL); \
             CREATE TABLE pending_media_progress_mutations (enclosure_id INTEGER PRIMARY KEY REFERENCES enclosures(id) ON DELETE CASCADE, progression_seconds INTEGER NOT NULL, revision INTEGER NOT NULL); \
             INSERT INTO categories VALUES(1,'Category'); \
             INSERT INTO feeds VALUES(2,1,'Feed'); \
             INSERT INTO articles VALUES(3,2,'Article','https://example.test/article','','2024-01-01T00:00:00Z',1,0,'',1,0,'',NULL,1); \
             INSERT INTO enclosures VALUES(10,3,'https://cdn.test/episode.mp3','audio/mpeg',123,4,1); \
             INSERT INTO saved_media VALUES(10,'2024-01-01T00:00:00Z'); \
             INSERT INTO playback_states VALUES(10,5000,NULL,'in_progress','2024-01-02T00:00:00Z'); \
             INSERT INTO pending_media_progress_mutations VALUES(10,5,1); \
             PRAGMA user_version=12;",
        ).unwrap();
        add_legacy_notification_fixture_tables(&connection);
        drop(connection);

        let store = Store::open(&data, &cache, &media).unwrap();
        assert_eq!(store.schema_version().unwrap(), SCHEMA_VERSION);
        // existing B1/B2/B3 data survives
        assert!(store.saved_media(10).unwrap().is_some());
        assert_eq!(store.playback_state(10).unwrap().unwrap().position_ms, 5000);
        let pending = store.pending_media_progress_mutations().unwrap();
        assert_eq!(pending.len(), 1);
        assert_eq!(pending[0].progression_seconds, 5);
        // new download table is usable right away
        store.request_download(10, DownloadOrigin::Manual).unwrap();
        assert_eq!(
            store.media_download(10).unwrap().unwrap().state,
            DownloadState::Requested
        );
    }

    #[test]
    fn v13_migration_strengthens_media_download_invariants() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let connection = Connection::open(data.join("flux.sqlite3")).unwrap();
        connection.execute_batch(
            "CREATE TABLE core_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL); \
             CREATE TABLE categories (id INTEGER PRIMARY KEY, title TEXT NOT NULL); \
             CREATE TABLE feeds (id INTEGER PRIMARY KEY, category_id INTEGER NOT NULL REFERENCES categories(id), title TEXT NOT NULL); \
             CREATE TABLE articles (id INTEGER PRIMARY KEY, feed_id INTEGER NOT NULL REFERENCES feeds(id), title TEXT NOT NULL, url TEXT NOT NULL, comments_url TEXT NOT NULL DEFAULT '', published_at TEXT NOT NULL, is_read INTEGER NOT NULL, is_starred INTEGER NOT NULL, raw_html_content TEXT NOT NULL, remote_is_read INTEGER, remote_is_starred INTEGER, preview TEXT NOT NULL DEFAULT '', image_url TEXT, content_processing_version INTEGER NOT NULL DEFAULT 0); \
             CREATE TABLE enclosures (id INTEGER PRIMARY KEY, article_id INTEGER NOT NULL REFERENCES articles(id) ON DELETE CASCADE, url TEXT NOT NULL, mime_type TEXT NOT NULL, size_bytes INTEGER, remote_media_progression_seconds INTEGER NOT NULL, remote_present INTEGER NOT NULL DEFAULT 1); \
             CREATE TABLE media_downloads (enclosure_id INTEGER PRIMARY KEY REFERENCES enclosures(id) ON DELETE CASCADE, state TEXT NOT NULL CHECK(state IN ('requested','downloaded','failed','delete_requested')), origin TEXT, local_file TEXT, file_size_bytes INTEGER, downloaded_at TEXT, failure_kind TEXT); \
             INSERT INTO categories VALUES(1,'Category'); \
             INSERT INTO feeds VALUES(2,1,'Feed'); \
             INSERT INTO articles VALUES(3,2,'Article','https://example.test/article','','2024-01-01T00:00:00Z',1,0,'',1,0,'',NULL,1); \
             INSERT INTO enclosures VALUES(10,3,'https://cdn.test/episode.mp3','audio/mpeg',123,4,1); \
             INSERT INTO enclosures VALUES(11,3,'https://cdn.test/episode2.mp3','audio/mpeg',123,4,1); \
             INSERT INTO media_downloads VALUES(10,'requested','manual',NULL,NULL,NULL,NULL); \
             INSERT INTO media_downloads VALUES(11,'failed','manual',NULL,NULL,NULL,'network'); \
             PRAGMA user_version=13;",
        ).unwrap();
        add_legacy_notification_fixture_tables(&connection);
        drop(connection);

        let store = Store::open(&data, &cache, &media).unwrap();
        assert_eq!(store.schema_version().unwrap(), SCHEMA_VERSION);
        // Existing valid v13 rows survive intact.
        let requested = store.media_download(10).unwrap().unwrap();
        assert_eq!(requested.state, DownloadState::Requested);
        assert_eq!(requested.origin, Some(DownloadOrigin::Manual));
        let failed = store.media_download(11).unwrap().unwrap();
        assert_eq!(failed.state, DownloadState::Failed);
        assert_eq!(failed.failure_kind, Some(DownloadFailureKind::Network));
    }

    #[test]
    fn saved_media_is_local_idempotent_and_protects_its_article() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let categories = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [
            Feed {
                id: 2,
                category_id: 1,
                title: "Alpha".into(),
            },
            Feed {
                id: 3,
                category_id: 1,
                title: "Beta".into(),
            },
        ];
        let articles = [
            Article {
                id: 10,
                feed_id: 2,
                title: "Older".into(),
                url: "https://example.test/10".into(),
                comments_url: String::new(),
                published_at: "2020-01-01T00:00:00Z".into(),
                is_read: true,
                is_starred: false,
                raw_html_content: String::new(),
                reading_time_minutes: 0,
                preview: String::new(),
                image_url: None,
            },
            Article {
                id: 11,
                feed_id: 2,
                title: "Newer".into(),
                url: "https://example.test/11".into(),
                comments_url: String::new(),
                published_at: "2021-01-01T00:00:00Z".into(),
                is_read: true,
                is_starred: false,
                raw_html_content: String::new(),
                reading_time_minutes: 0,
                preview: String::new(),
                image_url: None,
            },
            Article {
                id: 12,
                feed_id: 3,
                title: "Other Feed".into(),
                url: "https://example.test/12".into(),
                comments_url: String::new(),
                published_at: "2022-01-01T00:00:00Z".into(),
                is_read: false,
                is_starred: false,
                raw_html_content: String::new(),
                reading_time_minutes: 0,
                preview: String::new(),
                image_url: None,
            },
        ];
        store
            .reconcile_with_enclosures(
                &categories,
                &feeds,
                &articles,
                &[
                    Enclosure {
                        id: 100,
                        article_id: 10,
                        url: "https://cdn.test/100.mp3".into(),
                        mime_type: "audio/mpeg".into(),
                        size_bytes: Some(100),
                        remote_media_progression_seconds: 0,
                    },
                    Enclosure {
                        id: 101,
                        article_id: 10,
                        url: "https://cdn.test/101.mp3".into(),
                        mime_type: "audio/mpeg".into(),
                        size_bytes: None,
                        remote_media_progression_seconds: 0,
                    },
                    Enclosure {
                        id: 110,
                        article_id: 11,
                        url: "https://cdn.test/110.mp4".into(),
                        mime_type: "video/mp4".into(),
                        size_bytes: None,
                        remote_media_progression_seconds: 0,
                    },
                    Enclosure {
                        id: 120,
                        article_id: 12,
                        url: "https://cdn.test/120.jpg".into(),
                        mime_type: "image/jpeg".into(),
                        size_bytes: None,
                        remote_media_progression_seconds: 0,
                    },
                ],
            )
            .unwrap();
        store.set_enclosure_remote_present(100, false).unwrap();

        assert!(store.save_media(100, "2024-01-01T00:00:00Z").unwrap());
        assert!(!store.save_media(100, "2025-01-01T00:00:00Z").unwrap());
        assert_eq!(
            store.saved_media(100).unwrap(),
            Some(SavedMedia {
                enclosure_id: 100,
                added_at: "2024-01-01T00:00:00Z".into()
            })
        );
        assert!(!store.enclosure(100).unwrap().unwrap().remote_present);
        assert!(!store.local_article_state(10).unwrap().unwrap().is_starred);
        store
            .reconcile_with_enclosures(
                &categories,
                &feeds,
                &[articles[0].clone()],
                &[Enclosure {
                    id: 100,
                    article_id: 10,
                    url: "https://cdn.test/100-reappeared.mp3".into(),
                    mime_type: "audio/mpeg".into(),
                    size_bytes: Some(101),
                    remote_media_progression_seconds: 0,
                }],
            )
            .unwrap();
        assert!(store.saved_media(100).unwrap().is_some());
        assert!(store.enclosure(100).unwrap().unwrap().remote_present);
        assert!(store.save_media(110, "2024-02-01T00:00:00Z").unwrap());
        assert!(store.save_media(120, "2024-03-01T00:00:00Z").is_err());
        assert!(store.saved_media(101).unwrap().is_none());

        let library = store.saved_playable_media().unwrap();
        assert_eq!(
            library
                .iter()
                .map(|item| item.enclosure_id)
                .collect::<Vec<_>>(),
            vec![110, 100]
        );
        assert_eq!(library[1].title, "Older");
        assert_eq!(library[1].feed_title, "Alpha");
        assert!(library[1].remote_present);
        assert_eq!(
            store
                .saved_media_by_feed(2)
                .unwrap()
                .iter()
                .map(|item| item.enclosure_id)
                .collect::<Vec<_>>(),
            vec![110, 100]
        );

        assert_eq!(
            store
                .cleanup_expired_read_articles("2021-01-01T00:00:00Z")
                .unwrap(),
            0
        );
        assert!(store.enclosure(100).unwrap().is_some());
        assert!(store.unsave_media(100).unwrap());
        assert!(!store.unsave_media(100).unwrap());
        assert_eq!(
            store
                .cleanup_expired_read_articles("2021-01-01T00:00:00Z")
                .unwrap(),
            1
        );
        assert!(store.enclosure(100).unwrap().is_none());
        assert!(store.enclosure(101).unwrap().is_none());
        assert!(store.enclosure(110).unwrap().is_some());
    }

    #[test]
    fn materializes_search_article_enclosure_and_saved_media_atomically() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        store
            .reconcile(
                &[Category {
                    id: 1,
                    title: "Category".into(),
                }],
                &[Feed {
                    id: 2,
                    category_id: 1,
                    title: "Feed".into(),
                }],
                &[],
            )
            .unwrap();
        let article = Article {
            id: 10,
            feed_id: 2,
            title: "Search result".into(),
            url: "https://example.test/10".into(),
            comments_url: String::new(),
            published_at: "2024-01-01T00:00:00Z".into(),
            is_read: false,
            is_starred: false,
            raw_html_content: "<p>Search result</p>".into(),
            reading_time_minutes: 0,
            preview: "Search result".into(),
            image_url: None,
        };
        let enclosure = Enclosure {
            id: 100,
            article_id: 10,
            url: "https://cdn.test/100.mp3".into(),
            mime_type: "audio/mpeg".into(),
            size_bytes: None,
            remote_media_progression_seconds: 0,
        };
        store
            .materialize_saved_media(&article, &enclosure, "2024-02-01T00:00:00Z")
            .unwrap();
        assert_eq!(
            store.saved_media(100).unwrap().unwrap().added_at,
            "2024-02-01T00:00:00Z"
        );
        assert_eq!(store.saved_playable_media().unwrap()[0].article_id, 10);

        let invalid = Enclosure {
            id: 101,
            article_id: 11,
            ..enclosure
        };
        assert!(
            store
                .materialize_saved_media(&article, &invalid, "2024-02-01T00:00:00Z")
                .is_err()
        );
        assert!(store.enclosure(101).unwrap().is_none());
    }

    #[test]
    fn fresh_schema_permits_orphan_preferences_without_cascade() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        assert_eq!(store.schema_version().unwrap(), SCHEMA_VERSION);
        let connection = store.connection.lock().unwrap();
        let foreign_key_count: i64 = connection
            .query_row(
                "SELECT COUNT(*) FROM pragma_foreign_key_list('feed_preferences')",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(foreign_key_count, 0);
        connection.execute("INSERT INTO feed_preferences(feed_id,system_notifications_enabled,detail_rendering,truncate_detail,open_in_miniflux) VALUES(999,1,'text_only',1,1)", []).unwrap();
        drop(connection);
        assert_eq!(
            store.feed_preferences(999).unwrap(),
            FeedPreferences {
                feed_id: 999,
                system_notifications_enabled: true,
                detail_rendering: DetailRenderingMode::TextOnly,
                truncate_detail: true,
                open_in_miniflux: true,
                auto_download_audio: false
            }
        );
    }

    #[test]
    fn local_feed_removal_does_not_delete_orphan_preferences() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let categories = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 123,
            category_id: 1,
            title: "Feed".into(),
        }];
        store.reconcile(&categories, &feeds, &[]).unwrap();
        store
            .set_feed_system_notifications_enabled(123, true)
            .unwrap();
        store
            .set_feed_detail_rendering(123, DetailRenderingMode::TextOnly)
            .unwrap();
        store.set_feed_truncate_detail(123, true).unwrap();
        store.set_feed_open_in_miniflux(123, true).unwrap();
        store
            .connection
            .lock()
            .unwrap()
            .execute("DELETE FROM feeds WHERE id=123", [])
            .unwrap();
        assert_eq!(
            store.feed_preferences(123).unwrap(),
            FeedPreferences {
                feed_id: 123,
                system_notifications_enabled: true,
                detail_rendering: DetailRenderingMode::TextOnly,
                truncate_detail: true,
                open_in_miniflux: true,
                auto_download_audio: false
            }
        );
    }

    #[test]
    fn changing_installations_explicitly_removes_all_preferences() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        store.set_base_url("https://server-a.example").unwrap();
        let categories = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 123,
            category_id: 1,
            title: "Feed".into(),
        }];
        store.reconcile(&categories, &feeds, &[]).unwrap();
        store
            .set_feed_system_notifications_enabled(123, true)
            .unwrap();

        store.set_base_url("https://server-b.example").unwrap();

        assert!(store.navigation_catalog().unwrap().feeds.is_empty());
        let connection = store.connection.lock().unwrap();
        assert_eq!(
            connection
                .query_row("SELECT COUNT(*) FROM feed_preferences", [], |row| {
                    row.get::<_, i64>(0)
                })
                .unwrap(),
            0
        );
    }

    #[test]
    fn reconciliation_removes_only_preferences_for_remotely_removed_feeds() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let categories = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [
            Feed {
                id: 123,
                category_id: 1,
                title: "Removed".into(),
            },
            Feed {
                id: 456,
                category_id: 1,
                title: "Remaining".into(),
            },
        ];
        store.reconcile(&categories, &feeds, &[]).unwrap();
        store
            .set_feed_system_notifications_enabled(123, true)
            .unwrap();
        store
            .set_feed_detail_rendering(123, DetailRenderingMode::TextOnly)
            .unwrap();
        store.set_feed_open_in_miniflux(456, true).unwrap();

        store.reconcile(&categories, &feeds[1..], &[]).unwrap();

        assert!(store.feed_preferences(123).is_err());
        assert_eq!(
            store.feed_preferences(456).unwrap(),
            FeedPreferences {
                feed_id: 456,
                system_notifications_enabled: false,
                detail_rendering: DetailRenderingMode::Rendered,
                truncate_detail: false,
                open_in_miniflux: true,
                auto_download_audio: false
            }
        );
    }

    #[test]
    fn reconciliation_removes_orphan_preferences_absent_from_authoritative_catalog() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        store
            .connection
            .lock()
            .unwrap()
            .execute("INSERT INTO feed_preferences(feed_id) VALUES(999)", [])
            .unwrap();

        store
            .reconcile(
                &[Category {
                    id: 1,
                    title: "Category".into(),
                }],
                &[],
                &[],
            )
            .unwrap();

        assert!(store.feed_preferences(999).is_err());
    }

    #[test]
    fn reconcile_round_trip_returns_processed_summary_and_version() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let processed = crate::article::process(
            "<p>Hello &amp; goodbye</p><img data-original=\"/image.jpg\">",
            "https://example.test/post",
            &[],
        );
        store
            .reconcile(
                &[Category {
                    id: 1,
                    title: "Category".into(),
                }],
                &[Feed {
                    id: 2,
                    category_id: 1,
                    title: "Feed".into(),
                }],
                &[Article {
                    id: 3,
                    feed_id: 2,
                    title: "Title".into(),
                    url: "https://example.test/post".into(),
                    comments_url: String::new(),
                    published_at: "2024-01-01T00:00:00Z".into(),
                    is_read: false,
                    is_starred: false,
                    raw_html_content:
                        "<p>Hello &amp; goodbye</p><img data-original=\"/image.jpg\">".into(),
                    reading_time_minutes: 0,
                    preview: processed.preview.clone(),
                    image_url: processed.image_url.clone(),
                }],
            )
            .unwrap();
        let article = store
            .query_articles(&ArticleQuery {
                limit: 0,
                ..Default::default()
            })
            .unwrap()
            .pop()
            .unwrap();
        assert_eq!(article.preview, processed.preview);
        assert_eq!(article.image_url, processed.image_url);
        assert_eq!(
            store
                .connection
                .lock()
                .unwrap()
                .query_row(
                    "SELECT content_processing_version FROM articles WHERE id=3",
                    [],
                    |row| row.get::<_, i64>(0)
                )
                .unwrap(),
            crate::article::PROCESSING_VERSION
        );
    }

    #[test]
    fn reconcile_absent_unread_starred_articles_as_remote_read_unstarred_without_overwriting_pending_intent()
     {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let categories = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 2,
            category_id: 1,
            title: "Feed".into(),
        }];
        let articles = [1, 2].map(|id| Article {
            id,
            feed_id: 2,
            title: format!("Title {id}"),
            url: format!("https://example.test/{id}"),
            comments_url: String::new(),
            published_at: "2024-01-01T00:00:00Z".into(),
            is_read: false,
            is_starred: true,
            raw_html_content: String::new(),
            reading_time_minutes: 0,
            preview: String::new(),
            image_url: None,
        });
        store.reconcile(&categories, &feeds, &articles).unwrap();

        store
            .set_state_bulk(&[2], MutationField::Read, false)
            .unwrap();
        store
            .set_state_bulk(&[2], MutationField::Starred, true)
            .unwrap();
        let stats = store.reconcile(&categories, &feeds, &[]).unwrap();

        let rows = store
            .connection
            .lock()
            .unwrap()
            .prepare("SELECT id,is_read,is_starred,remote_is_read,remote_is_starred FROM articles ORDER BY id")
            .unwrap()
            .query_map([], |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, bool>(1)?,
                    row.get::<_, bool>(2)?,
                    row.get::<_, bool>(3)?,
                    row.get::<_, bool>(4)?,
                ))
            })
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();
        assert_eq!(stats.updated_articles, 2);
        assert_eq!(
            rows,
            vec![(1, true, false, true, false), (2, false, true, true, false)]
        );
    }

    #[test]
    fn reconcile_removes_absent_feed_data_and_notification_candidates() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let categories = [
            Category {
                id: 1,
                title: "A".into(),
            },
            Category {
                id: 2,
                title: "B".into(),
            },
        ];
        let feeds = [
            Feed {
                id: 10,
                category_id: 1,
                title: "Keep".into(),
            },
            Feed {
                id: 20,
                category_id: 2,
                title: "Remove".into(),
            },
        ];
        let articles = [
            Article {
                id: 1,
                feed_id: 10,
                title: "Keep".into(),
                url: "https://example.test/1".into(),
                comments_url: String::new(),
                published_at: "2024-01-01T00:00:00Z".into(),
                is_read: false,
                is_starred: false,
                raw_html_content: String::new(),
                reading_time_minutes: 0,
                preview: String::new(),
                image_url: None,
            },
            Article {
                id: 2,
                feed_id: 20,
                title: "Unread".into(),
                url: "https://example.test/2".into(),
                comments_url: String::new(),
                published_at: "2024-01-01T00:00:00Z".into(),
                is_read: false,
                is_starred: false,
                raw_html_content: String::new(),
                reading_time_minutes: 0,
                preview: String::new(),
                image_url: None,
            },
            Article {
                id: 3,
                feed_id: 20,
                title: "Starred".into(),
                url: "https://example.test/3".into(),
                comments_url: String::new(),
                published_at: "2024-01-01T00:00:00Z".into(),
                is_read: true,
                is_starred: true,
                raw_html_content: String::new(),
                reading_time_minutes: 0,
                preview: String::new(),
                image_url: None,
            },
        ];
        let initial = store.reconcile(&categories, &feeds, &articles).unwrap();
        store
            .set_feed_system_notifications_enabled(20, true)
            .unwrap();
        // An older sync result must not notify articles that already existed
        // when notifications were enabled.
        assert!(
            store
                .prepare_system_notification_candidates(&initial.new_article_ids_by_feed)
                .unwrap()
                .is_empty()
        );

        // Create a genuine post-enable notification candidate for the feed
        // that will subsequently be removed. This exercises the cascade cleanup.
        let mut new_article = articles[1].clone();
        new_article.id = 4;
        new_article.title = "New after enablement".into();
        new_article.url = "https://example.test/4".into();
        let mut refreshed_articles = articles.to_vec();
        refreshed_articles.push(new_article);
        let after_enable = store
            .reconcile(&categories, &feeds, &refreshed_articles)
            .unwrap();
        let candidates = store
            .prepare_system_notification_candidates(&after_enable.new_article_ids_by_feed)
            .unwrap();
        assert_eq!(candidates.len(), 1);
        assert_eq!(candidates[0].feed_id, 20);
        assert_eq!(candidates[0].new_count, 1);
        store
            .set_feed_system_notifications_enabled(10, true)
            .unwrap();
        store
            .set_state_bulk(&[2], MutationField::Read, true)
            .unwrap();

        let stats = store.reconcile(&categories[..1], &feeds[..1], &[]).unwrap();
        assert!(stats.navigation_changed);
        assert_eq!(
            store
                .navigation_catalog()
                .unwrap()
                .feeds
                .iter()
                .map(|feed| feed.id)
                .collect::<Vec<_>>(),
            vec![10]
        );
        assert_eq!(
            store
                .query_articles(&ArticleQuery {
                    limit: 0,
                    ..Default::default()
                })
                .unwrap()
                .iter()
                .map(|article| article.id)
                .collect::<Vec<_>>(),
            vec![1]
        );
        assert!(store.pending_mutations().unwrap().is_empty());
        assert_eq!(
            store
                .feed_system_notification_settings()
                .unwrap()
                .iter()
                .map(|setting| setting.feed_id)
                .collect::<Vec<_>>(),
            vec![10]
        );
        assert!(store.feed_system_notification_settings().unwrap()[0].system_notifications_enabled);
        let connection = store.connection.lock().unwrap();
        assert_eq!(
            connection
                .query_row(
                    "SELECT COUNT(*) FROM feed_preferences WHERE feed_id=20",
                    [],
                    |row| row.get::<_, i64>(0)
                )
                .unwrap(),
            0
        );
        assert_eq!(connection.query_row("SELECT COUNT(*) FROM pending_system_notifications p LEFT JOIN articles a ON a.id=p.article_id WHERE a.id IS NULL", [], |row| row.get::<_, i64>(0)).unwrap(), 0);
        assert_eq!(connection.query_row("SELECT COUNT(*) FROM system_notified_articles n LEFT JOIN articles a ON a.id=n.article_id WHERE a.id IS NULL", [], |row| row.get::<_, i64>(0)).unwrap(), 0);
        assert_eq!(
            connection
                .query_row(
                    "SELECT COUNT(*) FROM system_notification_candidates WHERE feed_id=20",
                    [],
                    |row| row.get::<_, i64>(0)
                )
                .unwrap(),
            0
        );
        assert_eq!(
            connection
                .query_row(
                    "SELECT COUNT(*) FROM notification_candidate_articles",
                    [],
                    |row| row.get::<_, i64>(0)
                )
                .unwrap(),
            0
        );
        drop(connection);
        store.reconcile(&categories, &feeds, &[]).unwrap();
        assert!(
            !store
                .feed_system_notification_settings()
                .unwrap()
                .iter()
                .find(|setting| setting.feed_id == 20)
                .unwrap()
                .system_notifications_enabled
        );
    }

    #[test]
    fn reconcile_removes_only_categories_absent_from_the_remote_catalog() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let categories = [
            Category {
                id: 1,
                title: "A".into(),
            },
            Category {
                id: 2,
                title: "Removed".into(),
            },
            Category {
                id: 3,
                title: "Empty".into(),
            },
        ];
        let feeds = [Feed {
            id: 10,
            category_id: 1,
            title: "Feed".into(),
        }];
        store.reconcile(&categories, &feeds, &[]).unwrap();

        let stats = store
            .reconcile(&[categories[0].clone(), categories[2].clone()], &feeds, &[])
            .unwrap();
        assert!(stats.navigation_changed);
        let catalog = store.navigation_catalog().unwrap();
        assert_eq!(
            catalog
                .categories
                .iter()
                .map(|category| category.id)
                .collect::<Vec<_>>(),
            vec![1, 3]
        );
        assert_eq!(
            catalog.feeds.iter().map(|feed| feed.id).collect::<Vec<_>>(),
            vec![10]
        );
        assert!(
            !store
                .reconcile(&[categories[0].clone(), categories[2].clone()], &feeds, &[])
                .unwrap()
                .navigation_changed
        );
    }

    #[test]
    fn playback_state_is_enclosure_scoped_and_progress_coalesces() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let categories = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 2,
            category_id: 1,
            title: "Feed".into(),
        }];
        let articles = [Article {
            id: 1,
            feed_id: 2,
            title: "Article".into(),
            url: "https://example.test/1".into(),
            comments_url: String::new(),
            published_at: "2026-01-01T00:00:00Z".into(),
            is_read: false,
            is_starred: false,
            raw_html_content: String::new(),
            reading_time_minutes: 0,
            preview: String::new(),
            image_url: None,
        }];
        let enclosures = [
            Enclosure {
                id: 10,
                article_id: 1,
                url: "https://cdn.test/a.mp3".into(),
                mime_type: "audio/mpeg".into(),
                size_bytes: None,
                remote_media_progression_seconds: 0,
            },
            Enclosure {
                id: 11,
                article_id: 1,
                url: "https://cdn.test/b.mp3".into(),
                mime_type: "audio/mpeg".into(),
                size_bytes: None,
                remote_media_progression_seconds: 0,
            },
        ];
        store
            .reconcile_with_enclosures(&categories, &feeds, &articles, &enclosures)
            .unwrap();
        store
            .checkpoint_playback(10, 120_000, None, "2026-01-01T00:00:00Z", true)
            .unwrap();
        store
            .checkpoint_playback(10, 60_000, None, "2026-01-01T00:01:00Z", true)
            .unwrap();
        assert_eq!(
            store.playback_state(10).unwrap().unwrap().position_ms,
            60_000
        );
        assert!(store.playback_state(11).unwrap().is_none());
        let pending = store.pending_media_progress_mutations().unwrap();
        assert_eq!(pending.len(), 1);
        assert_eq!(pending[0].progression_seconds, 60);
        store
            .complete_playback(10, None, "2026-01-01T00:02:00Z", true)
            .unwrap();
        assert_eq!(
            store.playback_state(10).unwrap().unwrap().status,
            PlaybackStatus::Completed
        );
        assert_eq!(
            store.pending_media_progress_mutations().unwrap()[0].progression_seconds,
            60
        );
        store
            .complete_playback(10, Some(180_000), "2026-01-01T00:03:00Z", true)
            .unwrap();
        let completed = store.playback_state(10).unwrap().unwrap();
        assert_eq!(completed.position_ms, 180_000);
        assert_eq!(completed.duration_ms, Some(180_000));
        assert_eq!(
            store.pending_media_progress_mutations().unwrap()[0].progression_seconds,
            180
        );
        store
            .restart_playback(10, "2026-01-01T00:04:00Z", true)
            .unwrap();
        let restarted = store.playback_state(10).unwrap().unwrap();
        assert_eq!(restarted.status, PlaybackStatus::InProgress);
        assert_eq!(restarted.position_ms, 0);
        assert!(store.pending_media_progress_mutations().unwrap().is_empty());
    }

    #[test]
    fn continue_listening_returns_only_in_progress_items_newest_first() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let category = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 2,
            category_id: 1,
            title: "Feed".into(),
        }];
        let article = |id: i64, title: &str, published_at: &str| Article {
            id,
            feed_id: 2,
            title: title.into(),
            url: format!("https://example.test/{id}"),
            comments_url: String::new(),
            published_at: published_at.into(),
            is_read: false,
            is_starred: false,
            raw_html_content: String::new(),
            reading_time_minutes: 0,
            preview: String::new(),
            image_url: None,
        };
        let articles = [
            article(1, "Older", "2026-01-01T00:00:00Z"),
            article(2, "Newer", "2026-01-02T00:00:00Z"),
        ];
        let enclosure = |id, article_id| Enclosure {
            id,
            article_id,
            url: format!("https://cdn.test/{id}.mp3"),
            mime_type: "audio/mpeg".into(),
            size_bytes: None,
            remote_media_progression_seconds: 0,
        };
        store
            .reconcile_with_enclosures(
                &category,
                &feeds,
                &articles,
                &[enclosure(10, 1), enclosure(20, 2)],
            )
            .unwrap();
        store
            .checkpoint_playback(10, 10_000, None, "2026-01-01T00:01:00Z", false)
            .unwrap();
        store
            .checkpoint_playback(20, 20_000, None, "2026-01-01T00:02:00Z", false)
            .unwrap();
        store
            .complete_playback(10, None, "2026-01-01T00:03:00Z", false)
            .unwrap();

        let items = store.continue_listening().unwrap();
        assert_eq!(items.len(), 1);
        assert_eq!(items[0].enclosure_id, 20);
        assert_eq!(items[0].position_ms, 20_000);
    }

    #[test]
    fn listening_list_is_article_centered_and_projects_audio_state() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let category = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [
            Feed {
                id: 2,
                category_id: 1,
                title: "Feed".into(),
            },
            Feed {
                id: 3,
                category_id: 1,
                title: "Other".into(),
            },
        ];
        let article = |id: i64, feed_id: i64, title: &str, published_at: &str| Article {
            id,
            feed_id,
            title: title.into(),
            url: format!("https://example.test/{id}"),
            comments_url: String::new(),
            published_at: published_at.into(),
            is_read: false,
            is_starred: false,
            raw_html_content: String::new(),
            reading_time_minutes: 0,
            preview: String::new(),
            image_url: None,
        };
        let enclosure = |id: i64, article_id: i64, mime_type: &str| Enclosure {
            id,
            article_id,
            url: format!("https://cdn.test/{id}"),
            mime_type: mime_type.into(),
            size_bytes: Some(100),
            remote_media_progression_seconds: 0,
        };
        let articles = [
            article(10, 2, "Older", "2026-01-01T00:00:00Z"),
            article(20, 2, "Newer", "2026-01-02T00:00:00Z"),
            article(30, 3, "Other feed", "2026-01-03T00:00:00Z"),
        ];
        let enclosures = [
            enclosure(100, 10, "audio/mpeg"),
            enclosure(101, 10, "audio/ogg"),
            enclosure(102, 10, "image/jpeg"),
            enclosure(200, 20, "audio/mpeg"),
            enclosure(300, 30, "audio/mpeg"),
        ];
        store
            .reconcile_with_enclosures(&category, &feeds, &articles, &enclosures)
            .unwrap();
        assert!(
            store
                .add_to_listening_list(10, "2026-02-01T00:00:00Z")
                .unwrap()
        );
        assert!(
            !store
                .add_to_listening_list(10, "2026-02-02T00:00:00Z")
                .unwrap()
        );
        store
            .add_to_listening_list(20, "2026-02-03T00:00:00Z")
            .unwrap();
        store
            .add_to_listening_list(30, "2026-02-04T00:00:00Z")
            .unwrap();
        store
            .checkpoint_playback(101, 12_000, Some(60_000), "2026-02-05T00:00:00Z", false)
            .unwrap();
        store.request_download(100, DownloadOrigin::Manual).unwrap();
        store.download_finished(100, "100.mp3", 100).unwrap();

        let recently_added = store
            .listening_list(None, ListeningListSort::RecentlyAdded)
            .unwrap();
        assert_eq!(
            recently_added
                .iter()
                .map(|item| item.article_id)
                .collect::<Vec<_>>(),
            vec![30, 20, 10]
        );
        let item = &recently_added[2];
        assert_eq!(item.audio_enclosures.len(), 2);
        assert_eq!(item.active_enclosure_id, Some(101));
        assert_eq!(item.audio_enclosures[0].enclosure.id, 100);
        assert_eq!(
            item.audio_enclosures[0].download.as_ref().unwrap().state,
            DownloadState::Downloaded
        );
        assert_eq!(
            item.audio_enclosures[1]
                .playback_state
                .as_ref()
                .unwrap()
                .position_ms,
            12_000
        );
        assert_eq!(item.audio_enclosures[1].duration_ms, Some(60_000));

        let by_publication = store
            .listening_list(Some(2), ListeningListSort::PublicationDate)
            .unwrap();
        assert_eq!(
            by_publication
                .iter()
                .map(|item| item.article_id)
                .collect::<Vec<_>>(),
            vec![20, 10]
        );
        assert_eq!(
            store
                .listening_list_feeds()
                .unwrap()
                .iter()
                .map(|feed| (feed.feed_id, feed.item_count))
                .collect::<Vec<_>>(),
            vec![(2, 2), (3, 1)]
        );
        assert!(store.is_in_listening_list(10).unwrap());
        assert!(!store.is_in_listening_list(999).unwrap());

        let action_states = store.article_audio_action_states(&[20, 10, 30]).unwrap();
        assert_eq!(
            action_states
                .iter()
                .map(|state| state.article_id)
                .collect::<Vec<_>>(),
            vec![20, 10, 30]
        );
        assert!(action_states[0].is_in_listening_list);
        assert!(action_states[1].is_in_listening_list);
        assert_eq!(action_states[1].enclosures.len(), 2);
        assert_eq!(action_states[1].downloads.len(), 1);
    }

    #[test]
    fn article_enclosures_returns_all_enclosures_in_id_order() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        store
            .reconcile_with_enclosures(
                &[Category {
                    id: 1,
                    title: "Category".into(),
                }],
                &[Feed {
                    id: 2,
                    category_id: 1,
                    title: "Feed".into(),
                }],
                &[Article {
                    id: 10,
                    feed_id: 2,
                    title: "Article".into(),
                    url: "https://example.test/10".into(),
                    comments_url: String::new(),
                    published_at: "2026-01-01T00:00:00Z".into(),
                    is_read: false,
                    is_starred: false,
                    raw_html_content: String::new(),
                    reading_time_minutes: 0,
                    preview: String::new(),
                    image_url: None,
                }],
                &[
                    Enclosure {
                        id: 20,
                        article_id: 10,
                        url: "https://cdn.test/20".into(),
                        mime_type: "audio/mpeg".into(),
                        size_bytes: None,
                        remote_media_progression_seconds: 0,
                    },
                    Enclosure {
                        id: 10,
                        article_id: 10,
                        url: "https://cdn.test/10".into(),
                        mime_type: "audio/mpeg".into(),
                        size_bytes: None,
                        remote_media_progression_seconds: 0,
                    },
                ],
            )
            .unwrap();
        assert_eq!(
            store
                .enclosures_for_article(10)
                .unwrap()
                .iter()
                .map(|row| row.enclosure.id)
                .collect::<Vec<_>>(),
            vec![10, 20]
        );
        assert!(store.enclosures_for_article(999).unwrap().is_empty());
    }

    #[test]
    fn legacy_playback_import_is_conservative_and_idempotent() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let category = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 2,
            category_id: 1,
            title: "Feed".into(),
        }];
        let articles = (1..=5)
            .map(|id| Article {
                id,
                feed_id: 2,
                title: format!("Article {id}"),
                url: format!("https://example.test/{id}"),
                comments_url: String::new(),
                published_at: "2026-01-01T00:00:00Z".into(),
                is_read: false,
                is_starred: false,
                raw_html_content: String::new(),
                reading_time_minutes: 0,
                preview: String::new(),
                image_url: None,
            })
            .collect::<Vec<_>>();
        let enclosures = [
            Enclosure {
                id: 10,
                article_id: 1,
                url: "https://cdn.test/1.mp3".into(),
                mime_type: "audio/mpeg".into(),
                size_bytes: None,
                remote_media_progression_seconds: 0,
            },
            Enclosure {
                id: 20,
                article_id: 2,
                url: "https://cdn.test/2a.mp3".into(),
                mime_type: "audio/mpeg".into(),
                size_bytes: None,
                remote_media_progression_seconds: 0,
            },
            Enclosure {
                id: 21,
                article_id: 2,
                url: "https://cdn.test/2b.mp3".into(),
                mime_type: "audio/mpeg".into(),
                size_bytes: None,
                remote_media_progression_seconds: 0,
            },
            Enclosure {
                id: 30,
                article_id: 3,
                url: "https://cdn.test/3.mp3".into(),
                mime_type: "audio/mpeg".into(),
                size_bytes: None,
                remote_media_progression_seconds: 0,
            },
            Enclosure {
                id: 40,
                article_id: 4,
                url: "https://cdn.test/4.mp3".into(),
                mime_type: "audio/mpeg".into(),
                size_bytes: None,
                remote_media_progression_seconds: 0,
            },
            Enclosure {
                id: 50,
                article_id: 5,
                url: "https://cdn.test/5.mp3".into(),
                mime_type: "audio/mpeg".into(),
                size_bytes: None,
                remote_media_progression_seconds: 0,
            },
        ];
        store
            .reconcile_with_enclosures(&category, &feeds, &articles, &enclosures)
            .unwrap();
        let records = [
            LegacyPlaybackImport {
                article_id: 1,
                position_ms: 0,
                updated_at: Some("2026-01-01T00:00:00Z".into()),
            },
            LegacyPlaybackImport {
                article_id: 2,
                position_ms: 2_000,
                updated_at: Some("2026-01-01T00:00:00Z".into()),
            },
            LegacyPlaybackImport {
                article_id: 3,
                position_ms: 3_000,
                updated_at: None,
            },
            LegacyPlaybackImport {
                article_id: 4,
                position_ms: 4_000,
                updated_at: Some("2026-01-01T00:00:00Z".into()),
            },
            LegacyPlaybackImport {
                article_id: 99,
                position_ms: 3_000,
                updated_at: Some("2026-01-01T00:00:00Z".into()),
            },
        ];
        store
            .checkpoint_playback(40, 9_000, None, "2026-01-01T00:00:00Z", false)
            .unwrap();
        let result = store.import_legacy_playback(&records).unwrap();
        assert_eq!(result.imported, 1);
        assert_eq!(result.skipped_ambiguous, 1);
        assert_eq!(result.skipped_missing, 1);
        assert_eq!(store.playback_state(10).unwrap(), None);
        assert_eq!(
            store.playback_state(30).unwrap().unwrap().position_ms,
            3_000
        );
        assert_eq!(
            store.playback_state(30).unwrap().unwrap().updated_at,
            LEGACY_PLAYBACK_UPDATED_AT_UNKNOWN
        );
        assert_eq!(
            store.playback_state(40).unwrap().unwrap().position_ms,
            9_000
        );
        assert!(
            store
                .continue_listening()
                .unwrap()
                .iter()
                .all(|item| item.enclosure_id != 10)
        );
        assert!(
            store
                .pending_media_progress_mutations()
                .unwrap()
                .iter()
                .all(|mutation| mutation.enclosure_id != 10)
        );
        assert_eq!(
            store
                .continue_listening()
                .unwrap()
                .into_iter()
                .map(|item| item.enclosure_id)
                .collect::<Vec<_>>(),
            vec![40, 30]
        );
        assert_eq!(
            store.import_legacy_playback(&records).unwrap(),
            LegacyPlaybackImportResult {
                skipped_missing: 1,
                skipped_ambiguous: 1,
                already_present: 2,
                ..LegacyPlaybackImportResult::default()
            }
        );
        let later = [LegacyPlaybackImport {
            article_id: 5,
            position_ms: 5_000,
            updated_at: Some("2026-01-01T00:00:00Z".into()),
        }];
        assert_eq!(store.import_legacy_playback(&later).unwrap().imported, 1);
        assert_eq!(
            store.import_legacy_playback(&[]).unwrap(),
            LegacyPlaybackImportResult::default()
        );
        assert_eq!(
            store
                .connection
                .lock()
                .unwrap()
                .query_row(
                    "SELECT COUNT(*) FROM core_settings WHERE key='legacy_media_migration_v1'",
                    [],
                    |row| row.get::<_, i64>(0)
                )
                .unwrap(),
            0
        );
    }

    #[test]
    fn playback_reconciliation_preserves_local_and_handles_remote_changes() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let category = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 2,
            category_id: 1,
            title: "Feed".into(),
        }];
        let article = [Article {
            id: 1,
            feed_id: 2,
            title: "Article".into(),
            url: "https://example.test/1".into(),
            comments_url: String::new(),
            published_at: "2026-01-01T00:00:00Z".into(),
            is_read: false,
            is_starred: false,
            raw_html_content: String::new(),
            reading_time_minutes: 0,
            preview: String::new(),
            image_url: None,
        }];
        let enclosure = |progression| Enclosure {
            id: 10,
            article_id: 1,
            url: "https://cdn.test/a.mp3".into(),
            mime_type: "audio/mpeg".into(),
            size_bytes: None,
            remote_media_progression_seconds: progression,
        };
        store
            .reconcile_with_enclosures(&category, &feeds, &article, &[enclosure(100)])
            .unwrap();
        assert_eq!(
            store.playback_state(10).unwrap().unwrap().position_ms,
            100_000
        );
        store
            .checkpoint_playback(10, 150_000, None, "2026-01-01T00:01:00Z", false)
            .unwrap();
        store
            .reconcile_with_enclosures(&category, &feeds, &article, &[enclosure(100)])
            .unwrap();
        assert_eq!(
            store.playback_state(10).unwrap().unwrap().position_ms,
            150_000
        );
        store
            .reconcile_with_enclosures(&category, &feeds, &article, &[enclosure(50)])
            .unwrap();
        assert_eq!(
            store.playback_state(10).unwrap().unwrap().position_ms,
            50_000
        );
        store
            .checkpoint_playback(10, 120_000, None, "2026-01-01T00:02:00Z", false)
            .unwrap();
        store.upsert_remote_enclosures(&[enclosure(120)]).unwrap();
        store
            .reconcile_with_enclosures_and_progress(
                &category,
                &feeds,
                &article,
                &[enclosure(50)],
                &[(10, 120)].into_iter().collect(),
            )
            .unwrap();
        assert_eq!(
            store.playback_state(10).unwrap().unwrap().position_ms,
            120_000
        );
        assert_eq!(
            store
                .enclosure(10)
                .unwrap()
                .unwrap()
                .enclosure
                .remote_media_progression_seconds,
            120
        );
    }

    fn media_article_enclosure_pair() -> (Article, Enclosure) {
        (
            Article {
                id: 100,
                feed_id: 10,
                title: "Article".into(),
                url: "https://example.test/100".into(),
                comments_url: String::new(),
                published_at: "2020-01-01T00:00:00Z".into(),
                is_read: true,
                is_starred: false,
                raw_html_content: String::new(),
                reading_time_minutes: 0,
                preview: String::new(),
                image_url: None,
            },
            Enclosure {
                id: 1000,
                article_id: 100,
                url: "https://cdn.test/100.mp3".into(),
                mime_type: "audio/mpeg".into(),
                size_bytes: None,
                remote_media_progression_seconds: 0,
            },
        )
    }

    #[test]
    fn local_legacy_playback_restore_is_non_destructive_and_importable() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let (article, enclosure) = media_article_enclosure_pair();

        // Local legacy rows are accepted only into the current navigation catalog.
        assert!(
            !store
                .restore_legacy_local_playback_article(&article, &enclosure)
                .unwrap()
        );
        store
            .reconcile_with_enclosures(
                &[Category {
                    id: 1,
                    title: "Category".into(),
                }],
                &[Feed {
                    id: 10,
                    category_id: 1,
                    title: "Feed".into(),
                }],
                &[],
                &[],
            )
            .unwrap();

        assert!(
            store
                .restore_legacy_local_playback_article(&article, &enclosure)
                .unwrap()
        );
        let restored = store.enclosure(enclosure.id).unwrap().unwrap();
        assert_eq!(restored.enclosure.article_id, article.id);
        assert!(!restored.remote_present);

        let result = store
            .import_legacy_playback(&[LegacyPlaybackImport {
                article_id: article.id,
                position_ms: 42_000,
                updated_at: None,
            }])
            .unwrap();
        assert_eq!(result.imported, 1);
        assert_eq!(
            store
                .playback_state(enclosure.id)
                .unwrap()
                .unwrap()
                .position_ms,
            42_000
        );

        // Neither repeated local hydration nor repeated progress import may
        // replace native playback state.
        let changed = Article {
            title: "Legacy title must not replace native".into(),
            ..article.clone()
        };
        assert!(
            store
                .restore_legacy_local_playback_article(&changed, &enclosure)
                .unwrap()
        );
        assert_eq!(
            store
                .import_legacy_playback(&[LegacyPlaybackImport {
                    article_id: article.id,
                    position_ms: 99_000,
                    updated_at: None,
                }])
                .unwrap()
                .already_present,
            1
        );
        assert_eq!(
            store
                .playback_state(enclosure.id)
                .unwrap()
                .unwrap()
                .position_ms,
            42_000
        );
    }

    #[test]
    fn historical_media_restore_requires_current_feed_and_matching_audio_identity() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let (article, enclosure) = media_article_enclosure_pair();

        // No remotely synced feed/category: do not create orphan articles.
        assert!(
            !store
                .restore_legacy_media_article(
                    &article,
                    std::slice::from_ref(&enclosure),
                    enclosure.id,
                )
                .unwrap()
        );
        assert!(store.enclosure(enclosure.id).unwrap().is_none());

        store
            .reconcile_with_enclosures(
                &[Category {
                    id: 1,
                    title: "Category".into(),
                }],
                &[Feed {
                    id: 10,
                    category_id: 1,
                    title: "Feed".into(),
                }],
                &[],
                &[],
            )
            .unwrap();

        // Wrong or non-audio enclosures may never count as verified.
        assert!(
            !store
                .restore_legacy_media_article(&article, std::slice::from_ref(&enclosure), 9999)
                .unwrap()
        );
        assert!(
            !store
                .restore_legacy_media_article(
                    &article,
                    &[Enclosure {
                        mime_type: "video/mp4".into(),
                        ..enclosure.clone()
                    }],
                    enclosure.id,
                )
                .unwrap()
        );
        assert!(store.enclosure(enclosure.id).unwrap().is_none());

        assert!(
            store
                .restore_legacy_media_article(
                    &article,
                    std::slice::from_ref(&enclosure),
                    enclosure.id,
                )
                .unwrap()
        );
        assert_eq!(
            store
                .enclosure(enclosure.id)
                .unwrap()
                .unwrap()
                .enclosure
                .article_id,
            article.id
        );
        // A retry must be harmless.
        assert!(
            store
                .restore_legacy_media_article(&article, &[enclosure], 1000)
                .unwrap()
        );
    }

    #[test]
    fn media_download_request_lifecycle() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let category = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 10,
            category_id: 1,
            title: "Feed".into(),
        }];
        let (article, enclosure) = media_article_enclosure_pair();
        store
            .reconcile_with_enclosures(
                &category,
                &feeds,
                std::slice::from_ref(&article),
                std::slice::from_ref(&enclosure),
            )
            .unwrap();

        assert!(store.media_download(1000).unwrap().is_none());

        store
            .request_download(1000, DownloadOrigin::Manual)
            .unwrap();
        let requested = store.media_download(1000).unwrap().unwrap();
        assert_eq!(requested.state, DownloadState::Requested);
        assert_eq!(requested.origin, Some(DownloadOrigin::Manual));
        assert!(requested.local_file.is_none());
        assert!(requested.failure_kind.is_none());
        assert!(store.is_in_listening_list(100).unwrap());

        // stale completion after cancel must not resurrect into Downloaded
        store.cancel_download(1000).unwrap();
        store
            .download_finished(1000, "enclosure/1000.mp3", 4096)
            .unwrap_err();
        assert!(store.media_download(1000).unwrap().is_none());

        // Failed -> Requested with cleared failure and preserved origin
        store
            .request_download(1000, DownloadOrigin::Manual)
            .unwrap();
        store
            .download_failed(1000, DownloadFailureKind::Network)
            .unwrap();
        let failed = store.media_download(1000).unwrap().unwrap();
        assert_eq!(failed.state, DownloadState::Failed);
        assert_eq!(failed.failure_kind, Some(DownloadFailureKind::Network));
        assert_eq!(failed.origin, Some(DownloadOrigin::Manual));

        store.retry_download(1000).unwrap();
        let retried = store.media_download(1000).unwrap().unwrap();
        assert_eq!(retried.state, DownloadState::Requested);
        assert!(retried.failure_kind.is_none());

        store
            .download_finished(1000, "enclosure/1000.mp3", 4096)
            .unwrap();
        let finished = store.media_download(1000).unwrap().unwrap();
        assert_eq!(finished.state, DownloadState::Downloaded);
        assert_eq!(finished.local_file.as_deref(), Some("enclosure/1000.mp3"));
        assert_eq!(finished.file_size_bytes, Some(4096));
        assert!(finished.downloaded_at.is_some());
        assert_eq!(finished.origin, Some(DownloadOrigin::Manual));

        // deletion flow
        store.set_feed_auto_download_audio(10, true).unwrap();
        store.request_download_deletion(1000).unwrap();
        let deleting = store.media_download(1000).unwrap().unwrap();
        assert_eq!(deleting.state, DownloadState::DeleteRequested);
        assert_eq!(deleting.local_file.as_deref(), Some("enclosure/1000.mp3"));
        assert!(store.auto_download_suppressed(1000).unwrap());
        store.download_deleted(1000).unwrap();
        assert!(store.media_download(1000).unwrap().is_none());

        store
            .request_download(1000, DownloadOrigin::Automatic)
            .unwrap();
        store
            .download_finished(1000, "enclosure/1000.mp3", 4096)
            .unwrap();
        store.request_download_deletion(1000).unwrap();
        assert!(store.auto_download_suppressed(1000).unwrap());
    }

    #[test]
    fn legacy_download_import_is_idempotent_and_preserves_existing_core_state() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let category = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 10,
            category_id: 1,
            title: "Feed".into(),
        }];
        let (article, enclosure) = media_article_enclosure_pair();
        store
            .reconcile_with_enclosures(&category, &feeds, &[article], &[enclosure])
            .unwrap();

        assert_eq!(
            store
                .import_legacy_download(1000, "downloads/legacy/enclosure-1000.mp3", 4096)
                .unwrap(),
            LegacyDownloadImportOutcome::Imported
        );
        let imported = store.media_download(1000).unwrap().unwrap();
        assert_eq!(imported.state, DownloadState::Downloaded);
        assert_eq!(imported.origin, Some(DownloadOrigin::Manual));
        assert!(store.is_in_listening_list(100).unwrap());
        assert_eq!(
            store
                .import_legacy_download(1000, "downloads/legacy/enclosure-1000.mp3", 4096)
                .unwrap(),
            LegacyDownloadImportOutcome::AlreadyPresent
        );
        assert_eq!(
            store
                .import_legacy_download(9999, "downloads/legacy/enclosure-9999.mp3", 4096)
                .unwrap(),
            LegacyDownloadImportOutcome::MissingEnclosure
        );
    }

    #[test]
    fn listening_list_mutations_and_completion_policy_are_article_centered() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let article = Article {
            id: 200,
            feed_id: 10,
            title: "Article".into(),
            url: "https://example.test/200".into(),
            comments_url: String::new(),
            published_at: "2026-01-01T00:00:00Z".into(),
            is_read: false,
            is_starred: false,
            raw_html_content: String::new(),
            reading_time_minutes: 0,
            preview: String::new(),
            image_url: None,
        };
        let enclosures = [
            Enclosure {
                id: 2000,
                article_id: 200,
                url: "https://cdn.test/2000.mp3".into(),
                mime_type: "audio/mpeg".into(),
                size_bytes: None,
                remote_media_progression_seconds: 0,
            },
            Enclosure {
                id: 2001,
                article_id: 200,
                url: "https://cdn.test/2001.mp3".into(),
                mime_type: "audio/mpeg".into(),
                size_bytes: None,
                remote_media_progression_seconds: 0,
            },
        ];
        store
            .reconcile_with_enclosures(
                &[Category {
                    id: 1,
                    title: "Category".into(),
                }],
                &[Feed {
                    id: 10,
                    category_id: 1,
                    title: "Feed".into(),
                }],
                std::slice::from_ref(&article),
                &enclosures,
            )
            .unwrap();
        store.set_auto_download_listening_list(true).unwrap();
        store
            .add_to_listening_list_with_policy(200, "2026-01-02T00:00:00Z", true)
            .unwrap();
        assert_eq!(
            store.media_download(2000).unwrap().unwrap().state,
            DownloadState::Requested
        );
        assert_eq!(
            store.media_download(2001).unwrap().unwrap().state,
            DownloadState::Requested
        );
        store.set_remove_completed_listening_list(true).unwrap();
        store
            .complete_playback(2000, Some(60_000), "2026-01-03T00:00:00Z", false)
            .unwrap();
        assert!(store.is_in_listening_list(200).unwrap());
        store
            .complete_playback(2001, Some(60_000), "2026-01-03T00:01:00Z", false)
            .unwrap();
        assert!(!store.is_in_listening_list(200).unwrap());
        assert!(store.media_download(2000).unwrap().is_none());
        assert!(store.media_download(2001).unwrap().is_none());
        store
            .connection
            .lock()
            .unwrap()
            .execute(
                "INSERT INTO media_downloads(enclosure_id,state,origin,local_file,file_size_bytes,downloaded_at) VALUES(2000,'downloaded','manual','legacy.mp3',10,'2026-01-01T00:00:00Z')",
                [],
            )
            .unwrap();
        assert!(!store.remove_from_listening_list(200).unwrap());
        assert_eq!(
            store.media_download(2000).unwrap().unwrap().state,
            DownloadState::Downloaded
        );
    }

    #[test]
    fn live_discovery_auto_downloads_only_new_audio_and_never_backfills() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let categories = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 10,
            category_id: 1,
            title: "Feed".into(),
        }];
        let (article, enclosure) = media_article_enclosure_pair();
        store
            .reconcile_with_enclosures(
                &categories,
                &feeds,
                std::slice::from_ref(&article),
                std::slice::from_ref(&enclosure),
            )
            .unwrap();
        store.set_feed_auto_download_audio(10, true).unwrap();
        assert!(store.media_download(1000).unwrap().is_none());
        let new_article = Article {
            id: 101,
            title: "New".into(),
            ..article
        };
        let audio = Enclosure {
            id: 1001,
            article_id: 101,
            ..enclosure
        };
        let video = Enclosure {
            id: 1002,
            article_id: 101,
            mime_type: "video/mp4".into(),
            ..audio.clone()
        };
        store
            .reconcile_with_enclosures_and_progress_mode(
                &categories,
                &feeds,
                std::slice::from_ref(&new_article),
                &[audio.clone(), video],
                &HashMap::new(),
                DiscoveryMode::LiveDiscovery,
            )
            .unwrap();
        assert_eq!(
            store.media_download(1001).unwrap().unwrap().origin,
            Some(DownloadOrigin::Automatic)
        );
        assert!(store.media_download(1002).unwrap().is_none());
        let later_audio = Enclosure {
            id: 1003,
            article_id: 101,
            url: "https://cdn.test/1003.mp3".into(),
            mime_type: "audio/mpeg".into(),
            ..audio
        };
        store
            .reconcile_with_enclosures_and_progress_mode(
                &categories,
                &feeds,
                &[new_article],
                &[audio, later_audio],
                &HashMap::new(),
                DiscoveryMode::LiveDiscovery,
            )
            .unwrap();
        assert_eq!(
            store.media_download(1003).unwrap().unwrap().state,
            DownloadState::Requested
        );
    }

    #[test]
    fn automatic_cancel_and_manual_download_manage_suppression_atomically() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let (article, enclosure) = media_article_enclosure_pair();
        store
            .reconcile_with_enclosures(
                &[Category {
                    id: 1,
                    title: "Category".into(),
                }],
                &[Feed {
                    id: 10,
                    category_id: 1,
                    title: "Feed".into(),
                }],
                &[article],
                &[enclosure],
            )
            .unwrap();
        store
            .request_download(1000, DownloadOrigin::Automatic)
            .unwrap();
        store.cancel_download(1000).unwrap();
        assert!(store.auto_download_suppressed(1000).unwrap());
        store
            .request_download(1000, DownloadOrigin::Manual)
            .unwrap();
        assert!(!store.auto_download_suppressed(1000).unwrap());
        assert_eq!(
            store.media_download(1000).unwrap().unwrap().origin,
            Some(DownloadOrigin::Manual)
        );
    }

    #[test]
    fn cleanup_uses_download_age_and_completed_playback_without_touching_other_domains() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let (article, enclosure) = media_article_enclosure_pair();
        store
            .reconcile_with_enclosures(
                &[Category {
                    id: 1,
                    title: "Category".into(),
                }],
                &[Feed {
                    id: 10,
                    category_id: 1,
                    title: "Feed".into(),
                }],
                &[article],
                &[enclosure],
            )
            .unwrap();
        store
            .request_download(1000, DownloadOrigin::Automatic)
            .unwrap();
        store.download_finished(1000, "episode.mp3", 10).unwrap();
        store
            .connection
            .lock()
            .unwrap()
            .execute(
                "UPDATE media_downloads SET downloaded_at='2026-01-01T00:00:00Z' WHERE enclosure_id=1000",
                [],
            )
            .unwrap();
        store.save_media(1000, "2026-01-01T00:00:00Z").unwrap();
        store
            .set_download_retention(DownloadRetention::Days(30))
            .unwrap();
        let now = chrono::DateTime::parse_from_rfc3339("2026-02-01T00:00:00Z")
            .unwrap()
            .with_timezone(&chrono::Utc);
        assert_eq!(store.evaluate_media_cleanup(now).unwrap(), vec![1000]);
        assert!(!store.auto_download_suppressed(1000).unwrap());
        assert!(store.saved_media(1000).unwrap().is_some());
        assert!(store.playback_state(1000).unwrap().is_none());
    }

    #[test]
    fn download_operations_are_independent_from_saved_media_and_playback() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let category = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 10,
            category_id: 1,
            title: "Feed".into(),
        }];
        let (article, enclosure) = media_article_enclosure_pair();
        store
            .reconcile_with_enclosures(
                &category,
                &feeds,
                std::slice::from_ref(&article),
                std::slice::from_ref(&enclosure),
            )
            .unwrap();
        store
            .checkpoint_playback(1000, 30_000, None, "2026-01-01T00:00:00Z", false)
            .unwrap();

        store
            .request_download(1000, DownloadOrigin::Manual)
            .unwrap();
        store
            .download_finished(1000, "enclosure/1000.mp3", 1024)
            .unwrap();
        // download lifecycle must not save or unsave media
        assert!(store.saved_media(1000).unwrap().is_none());
        // playback state must be preserved
        assert_eq!(
            store.playback_state(1000).unwrap().unwrap().position_ms,
            30_000
        );

        store.save_media(1000, "2026-01-01T00:00:00Z").unwrap();
        // unsaving SavedMedia must not delete the download row
        store.unsave_media(1000).unwrap();
        let after_unsave = store.media_download(1000).unwrap().unwrap();
        assert_eq!(after_unsave.state, DownloadState::Downloaded);

        store.request_download_deletion(1000).unwrap();
        assert!(!store.auto_download_suppressed(1000).unwrap());
        store.download_deleted(1000).unwrap();
        // deletion must not unsave
        assert!(store.saved_media(1000).unwrap().is_none());
        // playback must survive
        assert_eq!(
            store.playback_state(1000).unwrap().unwrap().position_ms,
            30_000
        );
    }

    #[test]
    fn download_state_protects_old_articles_but_failed_does_not() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let category = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 10,
            category_id: 1,
            title: "Feed".into(),
        }];
        let (article, mut enclosure) = media_article_enclosure_pair();
        // This test isolates the Phase-B DownloadState retention contract. Audio download
        // requests intentionally create independent Phase-C Listening List membership, which
        // would keep protecting the Article after the Download itself becomes Failed.
        enclosure.mime_type = "video/mp4".into();
        store
            .reconcile_with_enclosures(
                &category,
                &feeds,
                std::slice::from_ref(&article),
                std::slice::from_ref(&enclosure),
            )
            .unwrap();

        store
            .request_download(1000, DownloadOrigin::Manual)
            .unwrap();
        assert!(!store.is_in_listening_list(article.id).unwrap());
        assert_eq!(
            store
                .cleanup_expired_read_articles("2030-01-01T00:00:00Z")
                .unwrap(),
            0
        );

        store
            .download_failed(1000, DownloadFailureKind::Network)
            .unwrap();
        assert_eq!(
            store
                .cleanup_expired_read_articles("2030-01-01T00:00:00Z")
                .unwrap(),
            1
        );
    }

    #[test]
    fn download_state_is_enclosure_scoped_across_the_same_article() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let category = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 10,
            category_id: 1,
            title: "Feed".into(),
        }];
        let article = Article {
            id: 200,
            feed_id: 10,
            title: "Article".into(),
            url: "https://example.test/200".into(),
            comments_url: String::new(),
            published_at: "2020-01-01T00:00:00Z".into(),
            is_read: true,
            is_starred: false,
            raw_html_content: String::new(),
            reading_time_minutes: 0,
            preview: String::new(),
            image_url: None,
        };
        let enclosures = [
            Enclosure {
                id: 2000,
                article_id: 200,
                url: "https://cdn.test/a.mp3".into(),
                mime_type: "audio/mpeg".into(),
                size_bytes: None,
                remote_media_progression_seconds: 0,
            },
            Enclosure {
                id: 2001,
                article_id: 200,
                url: "https://cdn.test/b.mp3".into(),
                mime_type: "audio/mpeg".into(),
                size_bytes: None,
                remote_media_progression_seconds: 0,
            },
        ];
        store
            .reconcile_with_enclosures(
                &category,
                &feeds,
                std::slice::from_ref(&article),
                &enclosures,
            )
            .unwrap();

        store
            .request_download(2000, DownloadOrigin::Manual)
            .unwrap();
        assert!(store.media_download(2000).unwrap().is_some());
        assert!(store.media_download(2001).unwrap().is_none());
        // failure on 2001 must not affect 2000
        store
            .request_download(2001, DownloadOrigin::Automatic)
            .unwrap();
        store
            .download_failed(2001, DownloadFailureKind::Storage)
            .unwrap();
        let first = store.media_download(2000).unwrap().unwrap();
        assert_eq!(first.state, DownloadState::Requested);
        let second = store.media_download(2001).unwrap().unwrap();
        assert_eq!(second.state, DownloadState::Failed);
    }

    #[test]
    fn download_origin_is_persisted_for_manual_and_automatic() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let category = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 10,
            category_id: 1,
            title: "Feed".into(),
        }];
        let (article, enclosure) = media_article_enclosure_pair();
        store
            .reconcile_with_enclosures(
                &category,
                &feeds,
                std::slice::from_ref(&article),
                std::slice::from_ref(&enclosure),
            )
            .unwrap();

        store
            .request_download(1000, DownloadOrigin::Manual)
            .unwrap();
        assert_eq!(
            store.media_download(1000).unwrap().unwrap().origin,
            Some(DownloadOrigin::Manual)
        );

        store.cancel_download(1000).unwrap();
        store
            .request_download(1000, DownloadOrigin::Automatic)
            .unwrap();
        assert_eq!(
            store.media_download(1000).unwrap().unwrap().origin,
            Some(DownloadOrigin::Automatic)
        );
    }

    #[test]
    fn download_failed_after_cancel_is_a_no_op() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let category = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 10,
            category_id: 1,
            title: "Feed".into(),
        }];
        let (article, enclosure) = media_article_enclosure_pair();
        store
            .reconcile_with_enclosures(
                &category,
                &feeds,
                std::slice::from_ref(&article),
                std::slice::from_ref(&enclosure),
            )
            .unwrap();
        store
            .request_download(1000, DownloadOrigin::Manual)
            .unwrap();
        store.cancel_download(1000).unwrap();
        // Late native failure callback after user cancellation must not resurrect
        // a stale Failed state.
        store
            .download_failed(1000, DownloadFailureKind::Network)
            .unwrap();
        assert!(store.media_download(1000).unwrap().is_none());
    }

    #[test]
    fn download_finished_rejects_oversized_file_size() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let category = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 10,
            category_id: 1,
            title: "Feed".into(),
        }];
        let (article, enclosure) = media_article_enclosure_pair();
        store
            .reconcile_with_enclosures(
                &category,
                &feeds,
                std::slice::from_ref(&article),
                std::slice::from_ref(&enclosure),
            )
            .unwrap();
        store
            .request_download(1000, DownloadOrigin::Manual)
            .unwrap();
        let oversized = (i64::MAX as u64).saturating_add(1);
        let err = store
            .download_finished(1000, "enclosure/1000.mp3", oversized)
            .unwrap_err();
        assert_eq!(err.kind, crate::domain::CoreErrorKind::Data);
    }

    #[test]
    fn download_finished_rejects_empty_local_file() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let category = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 10,
            category_id: 1,
            title: "Feed".into(),
        }];
        let (article, enclosure) = media_article_enclosure_pair();
        store
            .reconcile_with_enclosures(
                &category,
                &feeds,
                std::slice::from_ref(&article),
                std::slice::from_ref(&enclosure),
            )
            .unwrap();
        store
            .request_download(1000, DownloadOrigin::Manual)
            .unwrap();
        let err = store.download_finished(1000, "   ", 1024).unwrap_err();
        assert_eq!(err.kind, crate::domain::CoreErrorKind::Data);
    }

    #[test]
    fn downloaded_row_requires_file_metadata() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let category = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 10,
            category_id: 1,
            title: "Feed".into(),
        }];
        let (article, enclosure) = media_article_enclosure_pair();
        store
            .reconcile_with_enclosures(
                &category,
                &feeds,
                std::slice::from_ref(&article),
                std::slice::from_ref(&enclosure),
            )
            .unwrap();
        store
            .request_download(1000, DownloadOrigin::Manual)
            .unwrap();
        // Direct INSERT violating state invariants must be rejected by the CHECK.
        let connection = store.connection.lock().unwrap();
        let err = connection
            .execute(
                "UPDATE media_downloads SET state='downloaded', local_file=NULL, file_size_bytes=NULL, downloaded_at=NULL WHERE enclosure_id=?1",
                [1000],
            )
            .unwrap_err();
        drop(connection);
        assert!(
            matches!(err, rusqlite::Error::SqliteFailure(_, _)),
            "expected sqlite CHECK violation, got {err:?}"
        );
    }

    #[test]
    fn requested_and_failed_rows_reject_file_metadata() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let category = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 10,
            category_id: 1,
            title: "Feed".into(),
        }];
        let (article, enclosure) = media_article_enclosure_pair();
        store
            .reconcile_with_enclosures(
                &category,
                &feeds,
                std::slice::from_ref(&article),
                std::slice::from_ref(&enclosure),
            )
            .unwrap();
        store
            .request_download(1000, DownloadOrigin::Manual)
            .unwrap();
        let connection = store.connection.lock().unwrap();
        let result = connection.execute(
            "UPDATE media_downloads SET state='requested', local_file='enclosure/x.mp3', file_size_bytes=4096, downloaded_at='2026-01-01T00:00:00Z' WHERE enclosure_id=?1",
            [1000],
        );
        drop(connection);
        assert!(
            matches!(result, Err(rusqlite::Error::SqliteFailure(_, _))),
            "expected requested to reject file metadata, got {result:?}"
        );

        // Failed also cannot carry file metadata.
        store
            .download_failed(1000, DownloadFailureKind::Network)
            .unwrap();
        let connection = store.connection.lock().unwrap();
        let result = connection.execute(
            "UPDATE media_downloads SET state='failed', local_file='enclosure/x.mp3', file_size_bytes=4096, downloaded_at='2026-01-01T00:00:00Z' WHERE enclosure_id=?1",
            [1000],
        );
        drop(connection);
        assert!(
            matches!(result, Err(rusqlite::Error::SqliteFailure(_, _))),
            "expected failed to reject file metadata, got {result:?}"
        );
    }

    #[test]
    fn delete_requested_retains_required_file_metadata() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let category = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 10,
            category_id: 1,
            title: "Feed".into(),
        }];
        let (article, enclosure) = media_article_enclosure_pair();
        store
            .reconcile_with_enclosures(
                &category,
                &feeds,
                std::slice::from_ref(&article),
                std::slice::from_ref(&enclosure),
            )
            .unwrap();
        store
            .request_download(1000, DownloadOrigin::Manual)
            .unwrap();
        store
            .download_finished(1000, "enclosure/1000.mp3", 4096)
            .unwrap();
        store.request_download_deletion(1000).unwrap();
        let deleting = store.media_download(1000).unwrap().unwrap();
        assert_eq!(deleting.state, DownloadState::DeleteRequested);
        assert_eq!(deleting.local_file.as_deref(), Some("enclosure/1000.mp3"));
        assert_eq!(deleting.file_size_bytes, Some(4096));
        assert!(deleting.downloaded_at.is_some());

        // Forcing a DeleteRequested row without file metadata must be rejected.
        let connection = store.connection.lock().unwrap();
        let result = connection.execute(
            "UPDATE media_downloads SET state='delete_requested', local_file=NULL, file_size_bytes=NULL, downloaded_at=NULL WHERE enclosure_id=?1",
            [1000],
        );
        drop(connection);
        assert!(
            matches!(result, Err(rusqlite::Error::SqliteFailure(_, _))),
            "expected delete_requested to require file metadata, got {result:?}"
        );
    }

    #[test]
    fn origin_required_for_every_persisted_media_download_row() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let category = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 10,
            category_id: 1,
            title: "Feed".into(),
        }];
        let (article, enclosure) = media_article_enclosure_pair();
        store
            .reconcile_with_enclosures(
                &category,
                &feeds,
                std::slice::from_ref(&article),
                std::slice::from_ref(&enclosure),
            )
            .unwrap();
        // Direct INSERT without origin must be rejected.
        let connection = store.connection.lock().unwrap();
        let result = connection.execute(
            "INSERT INTO media_downloads(enclosure_id,state,origin,local_file,file_size_bytes,downloaded_at,failure_kind) VALUES(?1,'requested',NULL,NULL,NULL,NULL,NULL)",
            [1000],
        );
        drop(connection);
        assert!(
            matches!(result, Err(rusqlite::Error::SqliteFailure(_, _))),
            "expected origin NOT NULL CHECK violation, got {result:?}"
        );
    }

    #[test]
    fn media_metadata_is_enclosure_scoped_ordered_and_idempotently_replaced() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let (article, enclosure) = media_article_enclosure_pair();
        store
            .reconcile_with_enclosures(
                &[Category {
                    id: 1,
                    title: "Category".into(),
                }],
                &[Feed {
                    id: 10,
                    category_id: 1,
                    title: "Feed".into(),
                }],
                &[article],
                &[enclosure],
            )
            .unwrap();
        let metadata = MediaMetadata {
            enclosure_id: 1000,
            duration_ms: Some(90_000),
            embedded_artwork_reference: None,
        };
        let chapters = vec![
            MediaChapter {
                enclosure_id: 1000,
                title: "Intro".into(),
                start_ms: 0,
                end_ms: Some(30_000),
                source: MediaChapterSource::ArticleContent,
            },
            MediaChapter {
                enclosure_id: 1000,
                title: "Topic".into(),
                start_ms: 30_000,
                end_ms: None,
                source: MediaChapterSource::ArticleContent,
            },
        ];
        store
            .observe_media_metadata_duration(1000, 120_000)
            .unwrap();
        store
            .replace_media_metadata(1000, &metadata, &chapters)
            .unwrap();
        store
            .replace_media_metadata(1000, &metadata, &chapters)
            .unwrap();
        assert_eq!(store.media_metadata(1000).unwrap(), Some(metadata));
        assert_eq!(store.media_chapters(1000).unwrap(), chapters);
        store
            .observe_media_metadata_duration(1000, 120_000)
            .unwrap();
        assert_eq!(
            store.media_metadata(1000).unwrap().unwrap().duration_ms,
            Some(90_000)
        );
    }

    #[test]
    fn checkpoint_at_known_remote_progress_does_not_queue_media_mutation() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let (article, mut enclosure) = media_article_enclosure_pair();
        enclosure.remote_media_progression_seconds = 36;
        store
            .reconcile_with_enclosures(
                &[Category {
                    id: 1,
                    title: "Category".into(),
                }],
                &[Feed {
                    id: 10,
                    category_id: 1,
                    title: "Feed".into(),
                }],
                &[article],
                &[enclosure.clone()],
            )
            .unwrap();

        store
            .checkpoint_playback(enclosure.id, 36_000, None, "2026-09-25T18:00:00Z", true)
            .unwrap();

        assert!(store.pending_media_progress_mutations().unwrap().is_empty());
    }

    #[test]
    fn checkpoint_returning_to_remote_baseline_clears_obsolete_pending_intent() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let (article, mut enclosure) = media_article_enclosure_pair();
        enclosure.remote_media_progression_seconds = 36;
        store
            .reconcile_with_enclosures(
                &[Category {
                    id: 1,
                    title: "Category".into(),
                }],
                &[Feed {
                    id: 10,
                    category_id: 1,
                    title: "Feed".into(),
                }],
                &[article],
                &[enclosure.clone()],
            )
            .unwrap();

        store
            .checkpoint_playback(enclosure.id, 40_000, None, "2026-09-25T18:00:00Z", true)
            .unwrap();
        assert_eq!(
            store
                .pending_media_progress_mutations()
                .unwrap()
                .first()
                .map(|pending| pending.progression_seconds),
            Some(40)
        );

        store
            .checkpoint_playback(enclosure.id, 36_000, None, "2026-09-25T18:01:00Z", true)
            .unwrap();

        assert!(store.pending_media_progress_mutations().unwrap().is_empty());
    }

    #[test]
    fn pending_media_progress_mutation_protects_completed_article_from_retention() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let (mut article, enclosure) = media_article_enclosure_pair();
        article.published_at = "2020-01-01T00:00:00Z".into();
        article.is_read = true;
        article.is_starred = false;
        store
            .reconcile_with_enclosures(
                &[Category {
                    id: 1,
                    title: "Category".into(),
                }],
                &[Feed {
                    id: 10,
                    category_id: 1,
                    title: "Feed".into(),
                }],
                std::slice::from_ref(&article),
                std::slice::from_ref(&enclosure),
            )
            .unwrap();

        store
            .complete_playback(enclosure.id, Some(60_000), "2026-01-01T00:00:00Z", true)
            .unwrap();
        assert_eq!(
            store.playback_state(enclosure.id).unwrap().unwrap().status,
            PlaybackStatus::Completed
        );
        assert_eq!(store.pending_media_progress_mutations().unwrap().len(), 1);

        assert_eq!(
            store
                .cleanup_expired_read_articles("2025-01-01T00:00:00Z")
                .unwrap(),
            0
        );
        assert!(store.local_article_state(article.id).unwrap().is_some());
        assert_eq!(store.pending_media_progress_mutations().unwrap().len(), 1);

        // Once the durable pending mutation has been acknowledged, Completed-only playback
        // no longer protects the Article from normal retention.
        let pending = store.pending_media_progress_mutations().unwrap();
        store.acknowledge_media_progress(&pending[0]).unwrap();
        assert_eq!(
            store
                .cleanup_expired_read_articles("2025-01-01T00:00:00Z")
                .unwrap(),
            1
        );
        assert!(store.local_article_state(article.id).unwrap().is_none());
    }

    #[test]
    fn listening_list_membership_protects_article_from_normal_retention() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let categories = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 10,
            category_id: 1,
            title: "Feed".into(),
        }];
        let articles = [
            Article {
                id: 101,
                feed_id: 10,
                title: "Listening List".into(),
                url: "https://example.test/listening".into(),
                comments_url: String::new(),
                published_at: "2020-01-01T00:00:00Z".into(),
                is_read: true,
                is_starred: false,
                raw_html_content: String::new(),
                reading_time_minutes: 0,
                preview: String::new(),
                image_url: None,
            },
            Article {
                id: 102,
                feed_id: 10,
                title: "Expired".into(),
                url: "https://example.test/expired".into(),
                comments_url: String::new(),
                published_at: "2020-01-01T00:00:00Z".into(),
                is_read: true,
                is_starred: false,
                raw_html_content: String::new(),
                reading_time_minutes: 0,
                preview: String::new(),
                image_url: None,
            },
        ];
        let enclosures = [
            Enclosure {
                id: 1001,
                article_id: 101,
                url: "https://cdn.test/1001.mp3".into(),
                mime_type: "audio/mpeg".into(),
                size_bytes: None,
                remote_media_progression_seconds: 0,
            },
            Enclosure {
                id: 1002,
                article_id: 102,
                url: "https://cdn.test/1002.mp3".into(),
                mime_type: "audio/mpeg".into(),
                size_bytes: None,
                remote_media_progression_seconds: 0,
            },
        ];
        store
            .reconcile_with_enclosures(&categories, &feeds, &articles, &enclosures)
            .unwrap();
        store
            .add_to_listening_list(101, "2026-01-01T00:00:00Z")
            .unwrap();

        assert_eq!(
            store
                .cleanup_expired_read_articles("2025-01-01T00:00:00Z")
                .unwrap(),
            1
        );
        assert!(store.local_article_state(101).unwrap().is_some());
        assert!(store.is_in_listening_list(101).unwrap());
        assert!(store.local_article_state(102).unwrap().is_none());
    }

    #[test]
    fn rebuild_clear_preserves_durable_media_and_listening_state() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();

        let categories = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 10,
            category_id: 1,
            title: "Feed".into(),
        }];
        let articles = (1_i64..=9)
            .map(|offset| Article {
                id: 100 + offset,
                feed_id: 10,
                title: format!("Article {offset}"),
                url: format!("https://example.test/{offset}"),
                comments_url: String::new(),
                published_at: "2026-01-01T00:00:00Z".into(),
                is_read: true,
                is_starred: false,
                raw_html_content: String::new(),
                reading_time_minutes: 0,
                preview: String::new(),
                image_url: None,
            })
            .collect::<Vec<_>>();
        let enclosures = articles
            .iter()
            .enumerate()
            .map(|(index, article)| {
                let enclosure_id = 1001 + index as i64;
                Enclosure {
                    id: enclosure_id,
                    article_id: article.id,
                    url: format!("https://cdn.test/{enclosure_id}.mp3"),
                    // Articles 105/106 exercise Failed/DeleteRequested as explicitly
                    // non-protecting Phase-B states. Keep those enclosures non-audio so
                    // request_download() does not add the separate Phase-C Listening List
                    // protection that this matrix is not testing.
                    mime_type: if matches!(article.id, 105 | 106) {
                        "video/mp4".into()
                    } else {
                        "audio/mpeg".into()
                    },
                    size_bytes: Some(4096),
                    remote_media_progression_seconds: 0,
                }
            })
            .collect::<Vec<_>>();
        store
            .reconcile_with_enclosures(&categories, &feeds, &articles, &enclosures)
            .unwrap();

        // Protect Article 101 through SavedMedia.
        store.save_media(1001, "2026-01-01T00:00:00Z").unwrap();
        store
            .add_to_listening_list(101, "2026-01-01T00:00:00Z")
            .unwrap();

        // Protect Article 102 through InProgress playback + a pending media progression.
        store
            .checkpoint_playback(1002, 5_000, Some(60_000), "2026-01-01T00:00:01Z", true)
            .unwrap();

        // Protect Article 103 through Requested download.
        store
            .request_download(1003, DownloadOrigin::Manual)
            .unwrap();

        // Protect Article 104 through a completed local download and verify the physical file
        // is not treated as reconstructable cache.
        let local_dir = media.join("enclosure");
        std::fs::create_dir_all(&local_dir).unwrap();
        let local_file = local_dir.join("1004.mp3");
        std::fs::write(&local_file, b"media").unwrap();
        store
            .request_download(1004, DownloadOrigin::Manual)
            .unwrap();
        store
            .download_finished(1004, "enclosure/1004.mp3", 5)
            .unwrap();

        // These states are explicitly non-protecting in the frozen Phase-B contract.
        store
            .request_download(1005, DownloadOrigin::Manual)
            .unwrap();
        store
            .download_failed(1005, DownloadFailureKind::Network)
            .unwrap();

        store
            .request_download(1006, DownloadOrigin::Manual)
            .unwrap();
        let deleting_file = local_dir.join("1006.mp3");
        std::fs::write(&deleting_file, b"media").unwrap();
        store
            .download_finished(1006, "enclosure/1006.mp3", 5)
            .unwrap();
        store.request_download_deletion(1006).unwrap();

        store
            .checkpoint_playback(1007, 30_000, Some(30_000), "2026-01-01T00:00:02Z", false)
            .unwrap();
        store
            .complete_playback(1007, Some(30_000), "2026-01-01T00:00:03Z", false)
            .unwrap();

        // Pure Phase-C Listening List membership is durable user state and must protect
        // the News even without SavedMedia, playback or a download.
        store
            .add_to_listening_list(109, "2026-01-01T00:00:04Z")
            .unwrap();

        // Article 108 has no media/listening protection at all.
        store
            .set_state_bulk(&[101], MutationField::Read, false)
            .unwrap();

        store.clear_synchronized_state_for_rebuild().unwrap();

        for article_id in [101, 102, 103, 104, 109] {
            assert!(
                store.local_article_state(article_id).unwrap().is_some(),
                "media-protected Article {article_id} must survive rebuild clear"
            );
        }
        for article_id in [105, 106, 107, 108] {
            assert!(
                store.local_article_state(article_id).unwrap().is_none(),
                "non-protecting Article {article_id} must be reconstructable"
            );
        }

        assert!(store.saved_media(1001).unwrap().is_some());
        assert!(store.is_in_listening_list(101).unwrap());
        assert!(store.is_in_listening_list(109).unwrap());
        assert!(
            store.local_article_state(101).unwrap().unwrap().is_read,
            "discarded ordinary read mutation must fall back to last remote state"
        );
        assert_eq!(
            store.playback_state(1002).unwrap().unwrap().status,
            PlaybackStatus::InProgress
        );
        assert_eq!(
            store
                .pending_media_progress_mutations()
                .unwrap()
                .into_iter()
                .map(|mutation| mutation.enclosure_id)
                .collect::<Vec<_>>(),
            vec![1002]
        );
        assert_eq!(
            store.media_download(1003).unwrap().unwrap().state,
            DownloadState::Requested
        );
        assert_eq!(
            store.media_download(1004).unwrap().unwrap().state,
            DownloadState::Downloaded
        );
        assert!(local_file.exists());

        assert!(store.media_download(1005).unwrap().is_none());
        assert!(store.media_download(1006).unwrap().is_none());
        assert!(store.playback_state(1007).unwrap().is_none());
        assert!(store.pending_mutations().unwrap().is_empty());

        // The minimal FK parents of protected media remain until the subsequent Full Sync
        // refreshes the authoritative catalog.
        let catalog = store.navigation_catalog().unwrap();
        assert_eq!(catalog.categories, categories);
        assert_eq!(catalog.feeds, feeds);
    }

    #[test]
    fn observe_media_duration_updates_playback_and_metadata_without_nested_locking() {
        let temp = TempDir::new().unwrap();
        let (data, cache, media) = roots(&temp);
        let store = Store::open(&data, &cache, &media).unwrap();
        let (article, enclosure) = media_article_enclosure_pair();
        store
            .reconcile_with_enclosures(
                &[Category {
                    id: 1,
                    title: "Category".into(),
                }],
                &[Feed {
                    id: 10,
                    category_id: 1,
                    title: "Feed".into(),
                }],
                &[article],
                &[enclosure],
            )
            .unwrap();

        store
            .observe_media_duration(1000, 120_000, "2026-01-01T00:00:00Z")
            .unwrap();
        assert_eq!(
            store.media_metadata(1000).unwrap().unwrap().duration_ms,
            Some(120_000)
        );

        store
            .checkpoint_playback(1000, 30_000, None, "2026-01-01T00:00:01Z", false)
            .unwrap();
        store
            .observe_media_duration(1000, 60_000, "2026-01-01T00:00:02Z")
            .unwrap();

        let playback = store.playback_state(1000).unwrap().unwrap();
        assert_eq!(playback.position_ms, 30_000);
        assert_eq!(playback.duration_ms, Some(60_000));
        assert_eq!(
            store.media_metadata(1000).unwrap().unwrap().duration_ms,
            Some(60_000)
        );
    }
}
