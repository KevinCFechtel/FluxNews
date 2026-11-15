use crate::domain::{
    CoreError, DiscoveryMode, NewArticlesByFeed, ReadArticleRetention, SyncReason,
    SystemNotificationCandidate,
};
use crate::miniflux::RemoteSource;
use crate::storage::Store;
use crate::sync_cancellation::{Cancellable, SyncCancellation};
use chrono::{Duration, Utc};
use std::collections::{HashMap, HashSet};
use std::time::Instant;

/// Normal-sync orchestration after pending mutation delivery.
#[derive(Clone, Debug, Default)]
pub struct SyncData {
    pub new_articles: u32,
    pub updated_articles: u32,
    pub data_changed: bool,
    pub navigation_changed: bool,
    pub new_articles_by_feed: Vec<NewArticlesByFeed>,
    pub system_notification_candidates: Vec<SystemNotificationCandidate>,
}

const FULL_SYNC_MAX_AGE_HOURS: i64 = 24;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum SyncPlan {
    Full,
    Delta { cursor: i64 },
    BackgroundNeedsFull,
}

struct ProtectedFetchState<'a> {
    snapshot: &'a mut crate::miniflux::RemoteSnapshot,
    known_articles: &'a mut HashSet<i64>,
    known_enclosures: &'a mut HashSet<i64>,
}

fn sync_plan(store: &Store, reason: SyncReason) -> Result<SyncPlan, CoreError> {
    match reason {
        SyncReason::Background => {
            if store.full_sync_required()? {
                return Ok(SyncPlan::BackgroundNeedsFull);
            }
            match store.delta_sync_cursor()? {
                Some(cursor) => Ok(SyncPlan::Delta { cursor }),
                None => Ok(SyncPlan::BackgroundNeedsFull),
            }
        }
        SyncReason::Resume => {
            if store.full_sync_required()? || store.full_sync_due(FULL_SYNC_MAX_AGE_HOURS)? {
                return Ok(SyncPlan::Full);
            }
            match store.delta_sync_cursor()? {
                Some(cursor) => Ok(SyncPlan::Delta { cursor }),
                None => Ok(SyncPlan::Full),
            }
        }
        SyncReason::Manual | SyncReason::AppStart | SyncReason::Periodic | SyncReason::Widget => {
            Ok(SyncPlan::Full)
        }
    }
}

pub fn run(
    remote: &dyn RemoteSource,
    store: &Store,
    retention: ReadArticleRetention,
    reason: SyncReason,
    media_progress_writes: HashMap<i64, u64>,
) -> Result<SyncData, CoreError> {
    let cancellation = SyncCancellation::new();
    match run_cancellable(
        remote,
        store,
        retention,
        reason,
        media_progress_writes,
        &cancellation,
    )? {
        Cancellable::Completed(data) => Ok(data),
        Cancellable::Cancelled => unreachable!("fresh cancellation signal cannot be cancelled"),
    }
}

pub(crate) fn run_cancellable(
    remote: &dyn RemoteSource,
    store: &Store,
    retention: ReadArticleRetention,
    reason: SyncReason,
    media_progress_writes: HashMap<i64, u64>,
    cancellation: &SyncCancellation,
) -> Result<Cancellable<SyncData>, CoreError> {
    match sync_plan(store, reason)? {
        SyncPlan::Full => run_full_cancellable(
            remote,
            store,
            retention,
            reason,
            media_progress_writes,
            cancellation,
        ),
        SyncPlan::Delta { cursor } => run_delta_cancellable(
            remote,
            store,
            retention,
            reason,
            media_progress_writes,
            cursor,
            cancellation,
        ),
        SyncPlan::BackgroundNeedsFull => {
            store.mark_full_sync_required("missing_or_invalid_delta_baseline")?;
            tracing::info!(
                target: "sync",
                "background delta deferred until Full Sync establishes a valid baseline"
            );
            Ok(Cancellable::Completed(SyncData::default()))
        }
    }
}

fn run_full_cancellable(
    remote: &dyn RemoteSource,
    store: &Store,
    retention: ReadArticleRetention,
    reason: SyncReason,
    media_progress_writes: HashMap<i64, u64>,
    cancellation: &SyncCancellation,
) -> Result<Cancellable<SyncData>, CoreError> {
    if cancellation.is_cancelled() {
        return Ok(Cancellable::Cancelled);
    }

    // Capture the server-side high-water mark before the Full snapshot begins.
    // Changes racing the Full fetch will therefore remain visible to a later Delta.
    let delta_baseline = match remote.delta_watermark_cancellable(cancellation) {
        Ok(value) => value,
        Err(error) => {
            tracing::warn!(
                target: "sync",
                "Full Sync could not establish Delta baseline kind={:?}",
                error.kind
            );
            None
        }
    };
    if cancellation.is_cancelled() {
        return Ok(Cancellable::Cancelled);
    }

    let fetch_started = Instant::now();
    tracing::info!(target: "sync", "remote fetch started plan=full");
    let Some(mut snapshot) = remote.fetch_initial_articles_cancellable(cancellation)? else {
        return Ok(Cancellable::Cancelled);
    };
    tracing::info!(target: "sync", "remote fetch completed articles={} elapsed_ms={}", snapshot.articles.len(), fetch_started.elapsed().as_millis());
    if cancellation.is_cancelled() {
        return Ok(Cancellable::Cancelled);
    }

    // Marker entries are transport metadata, never user-visible articles or feeds.
    let saved_media_sync = store.saved_media_sync_configuration()?;
    let mut known_articles = snapshot
        .articles
        .iter()
        .map(|article| article.id)
        .collect::<HashSet<_>>();
    let mut known_enclosures = snapshot
        .enclosures
        .iter()
        .map(|enclosure| enclosure.id)
        .collect::<HashSet<_>>();
    let mut fetched_protected_articles = HashSet::new();
    let protected_requirements = store.protected_playback_requirements()?;
    let download_requirements = store.protected_download_requirements()?;

    for article_id in store.protected_playback_article_ids()? {
        if cancellation.is_cancelled() {
            return Ok(Cancellable::Cancelled);
        }
        let article_needs_enclosures = protected_requirements
            .iter()
            .filter(|(required_article_id, _)| *required_article_id == article_id)
            .any(|(_, enclosure_id)| {
                !snapshot
                    .enclosures
                    .iter()
                    .any(|enclosure| enclosure.id == *enclosure_id)
            });
        let article_missing = !known_articles.contains(&article_id);
        if ((article_missing && store.article_has_remote_present_enclosure(article_id)?)
            || (!article_missing && article_needs_enclosures))
            && fetched_protected_articles.insert(article_id)
        {
            match fetch_protected_article_cancellable(
                remote,
                store,
                article_id,
                protected_fetch_reason(article_id, &protected_requirements, &download_requirements),
                &mut ProtectedFetchState {
                    snapshot: &mut snapshot,
                    known_articles: &mut known_articles,
                    known_enclosures: &mut known_enclosures,
                },
                cancellation,
            )? {
                Cancellable::Completed(()) => {}
                Cancellable::Cancelled => return Ok(Cancellable::Cancelled),
            }
        }
    }

    for (article_id, enclosure_id) in &download_requirements {
        if cancellation.is_cancelled() {
            return Ok(Cancellable::Cancelled);
        }
        let article_missing = !known_articles.contains(article_id);
        let enclosure_missing = !known_enclosures.contains(enclosure_id);
        if (article_missing && store.article_has_remote_present_enclosure(*article_id)?)
            || (!article_missing && enclosure_missing)
        {
            if fetched_protected_articles.insert(*article_id) {
                match fetch_protected_article_cancellable(
                    remote,
                    store,
                    *article_id,
                    protected_fetch_reason(
                        *article_id,
                        &protected_requirements,
                        &download_requirements,
                    ),
                    &mut ProtectedFetchState {
                        snapshot: &mut snapshot,
                        known_articles: &mut known_articles,
                        known_enclosures: &mut known_enclosures,
                    },
                    cancellation,
                )? {
                    Cancellable::Completed(()) => {}
                    Cancellable::Cancelled => return Ok(Cancellable::Cancelled),
                }
            } else {
                tracing::debug!(
                    target: "sync",
                    "protected fetch skipped article_id={} reason=download already_fetched=true",
                    article_id
                );
            }
        }
    }

    if saved_media_sync.enabled {
        let Some(feed_id) = saved_media_sync.sync_feed_id else {
            return Err(CoreError::data("SavedMedia Sync setup requires repair"));
        };
        let technical_article_ids = snapshot
            .articles
            .iter()
            .filter(|article| article.feed_id == feed_id)
            .map(|article| article.id)
            .collect::<std::collections::HashSet<_>>();
        snapshot.feeds.retain(|feed| feed.id != feed_id);
        snapshot
            .articles
            .retain(|article| article.feed_id != feed_id);
        snapshot
            .enclosures
            .retain(|enclosure| !technical_article_ids.contains(&enclosure.article_id));
    }

    if cancellation.is_cancelled() {
        return Ok(Cancellable::Cancelled);
    }

    let reconcile_started = Instant::now();
    let discovery_mode = if store.last_successful_sync_at()?.is_some() {
        DiscoveryMode::LiveDiscovery
    } else {
        DiscoveryMode::Restore
    };
    // Reconciliation is one SQLite transaction. Do not split it with cancellation checks.
    let stats = store.reconcile_with_enclosures_and_progress_mode(
        &snapshot.categories,
        &snapshot.feeds,
        &snapshot.articles,
        &snapshot.enclosures,
        &media_progress_writes,
        discovery_mode,
    )?;
    if cancellation.is_cancelled() {
        return Ok(Cancellable::Cancelled);
    }

    let saved_media_changed =
        match crate::saved_media_sync::run_cancellable(remote, store, cancellation)? {
            Cancellable::Completed(changed) => changed,
            Cancellable::Cancelled => return Ok(Cancellable::Cancelled),
        };
    tracing::info!(target: "storage", "reconciliation completed new={} updated={} elapsed_ms={}", stats.new_articles, stats.updated_articles, reconcile_started.elapsed().as_millis());

    if cancellation.is_cancelled() {
        return Ok(Cancellable::Cancelled);
    }
    let cutoff = Utc::now() - Duration::days(retention.days());
    let cleanup_started = Instant::now();
    let removed_articles = store.cleanup_expired_read_articles(&cutoff.to_rfc3339())?;
    if cancellation.is_cancelled() {
        return Ok(Cancellable::Cancelled);
    }
    let removed_media = store.evaluate_media_cleanup(Utc::now())?;
    if cancellation.is_cancelled() {
        return Ok(Cancellable::Cancelled);
    }
    tracing::info!(target: "retention", "retention cleanup completed removed={} elapsed_ms={}", removed_articles, cleanup_started.elapsed().as_millis());
    tracing::info!(target: "retention", "media cleanup evaluated delete_requested={}", removed_media.len());

    let new_articles_by_feed = stats
        .new_article_ids_by_feed
        .iter()
        .map(|(&feed_id, article_ids)| NewArticlesByFeed {
            feed_id,
            count: article_ids.len() as u32,
        })
        .collect();
    let system_notification_candidates =
        if matches!(reason, SyncReason::Background | SyncReason::Periodic) {
            if cancellation.is_cancelled() {
                return Ok(Cancellable::Cancelled);
            }
            let candidates =
                store.prepare_system_notification_candidates(&stats.new_article_ids_by_feed)?;
            if cancellation.is_cancelled() {
                return Ok(Cancellable::Cancelled);
            }
            candidates
        } else {
            Vec::new()
        };

    // This is the final cancellation checkpoint. Once the successful-sync timestamp is committed,
    // the run is considered complete even if the caller requests cancellation immediately after it.
    if cancellation.is_cancelled() {
        return Ok(Cancellable::Cancelled);
    }
    store.commit_full_sync_success(delta_baseline)?;
    Ok(Cancellable::Completed(SyncData {
        new_articles: stats.new_articles,
        updated_articles: stats.updated_articles,
        data_changed: stats.new_articles > 0
            || stats.updated_articles > 0
            || removed_articles > 0
            || stats.navigation_changed
            || saved_media_changed,
        navigation_changed: stats.navigation_changed,
        new_articles_by_feed,
        system_notification_candidates,
    }))
}

fn run_delta_cancellable(
    remote: &dyn RemoteSource,
    store: &Store,
    retention: ReadArticleRetention,
    reason: SyncReason,
    media_progress_writes: HashMap<i64, u64>,
    cursor: i64,
    cancellation: &SyncCancellation,
) -> Result<Cancellable<SyncData>, CoreError> {
    if cancellation.is_cancelled() {
        return Ok(Cancellable::Cancelled);
    }

    let fetch_started = Instant::now();
    tracing::info!(target: "sync", "remote fetch started plan=delta cursor={cursor}");
    let Some(mut delta) = remote.fetch_changed_articles_cancellable(cursor, cancellation)? else {
        return Ok(Cancellable::Cancelled);
    };
    tracing::info!(
        target: "sync",
        "remote delta fetch completed articles={} cursor={} elapsed_ms={}",
        delta.articles.len(),
        delta.cursor,
        fetch_started.elapsed().as_millis()
    );
    if cancellation.is_cancelled() {
        return Ok(Cancellable::Cancelled);
    }

    // SavedMedia marker entries are transport metadata, never user-visible articles.
    let saved_media_sync = store.saved_media_sync_configuration()?;
    if let Some(feed_id) = saved_media_sync.sync_feed_id {
        let technical_article_ids = delta
            .articles
            .iter()
            .filter(|article| article.feed_id == feed_id)
            .map(|article| article.id)
            .collect::<HashSet<_>>();
        delta.articles.retain(|article| article.feed_id != feed_id);
        delta
            .enclosures
            .retain(|enclosure| !technical_article_ids.contains(&enclosure.article_id));
    }

    let reconcile_started = Instant::now();
    let (stats, unknown_feed_ids) = store.reconcile_delta_articles(
        &delta.articles,
        &delta.enclosures,
        &media_progress_writes,
    )?;
    if !unknown_feed_ids.is_empty() {
        store.mark_full_sync_required("unknown_feed_in_delta")?;
        tracing::info!(
            target: "sync",
            "delta skipped unknown feeds count={} ids={:?}; Full Sync requested",
            unknown_feed_ids.len(),
            unknown_feed_ids
        );
    }
    if cancellation.is_cancelled() {
        return Ok(Cancellable::Cancelled);
    }

    let saved_media_changed =
        match crate::saved_media_sync::run_cancellable(remote, store, cancellation)? {
            Cancellable::Completed(changed) => changed,
            Cancellable::Cancelled => return Ok(Cancellable::Cancelled),
        };

    let cutoff = Utc::now() - Duration::days(retention.days());
    let removed_articles = store.cleanup_expired_read_articles(&cutoff.to_rfc3339())?;
    if cancellation.is_cancelled() {
        return Ok(Cancellable::Cancelled);
    }
    let _removed_media = store.evaluate_media_cleanup(Utc::now())?;
    if cancellation.is_cancelled() {
        return Ok(Cancellable::Cancelled);
    }

    let new_articles_by_feed = stats
        .new_article_ids_by_feed
        .iter()
        .map(|(&feed_id, article_ids)| NewArticlesByFeed {
            feed_id,
            count: article_ids.len() as u32,
        })
        .collect();
    let system_notification_candidates =
        if matches!(reason, SyncReason::Background | SyncReason::Periodic) {
            let candidates =
                store.prepare_system_notification_candidates(&stats.new_article_ids_by_feed)?;
            if cancellation.is_cancelled() {
                return Ok(Cancellable::Cancelled);
            }
            candidates
        } else {
            Vec::new()
        };

    // Cursor commit is intentionally independent from full_sync_required. Unknown
    // feeds are skipped, the usable Delta work is retained, and the later Full
    // Sync does not depend on this cursor.
    if cancellation.is_cancelled() {
        return Ok(Cancellable::Cancelled);
    }
    store.commit_delta_sync_success(delta.cursor)?;
    tracing::info!(
        target: "storage",
        "delta reconciliation completed new={} updated={} unknown_feeds={} elapsed_ms={}",
        stats.new_articles,
        stats.updated_articles,
        unknown_feed_ids.len(),
        reconcile_started.elapsed().as_millis()
    );

    Ok(Cancellable::Completed(SyncData {
        new_articles: stats.new_articles,
        updated_articles: stats.updated_articles,
        data_changed: stats.new_articles > 0
            || stats.updated_articles > 0
            || removed_articles > 0
            || saved_media_changed,
        navigation_changed: false,
        new_articles_by_feed,
        system_notification_candidates,
    }))
}

fn fetch_protected_article_cancellable(
    remote: &dyn RemoteSource,
    store: &Store,
    article_id: i64,
    reason: &str,
    state: &mut ProtectedFetchState<'_>,
    cancellation: &SyncCancellation,
) -> Result<Cancellable<()>, CoreError> {
    if cancellation.is_cancelled() {
        return Ok(Cancellable::Cancelled);
    }
    tracing::debug!(
        target: "sync",
        "protected fetch planned article_id={} reason={}",
        article_id,
        reason
    );
    let protected_result = remote.fetch_article_by_id(article_id);
    if cancellation.is_cancelled() {
        return Ok(Cancellable::Cancelled);
    }
    let protected = match protected_result {
        Ok(protected) => protected,
        Err(error) if matches!(error.http_status(), Some(404 | 410)) => {
            store.mark_article_enclosures_remote_absent(article_id)?;
            tracing::info!(
                target: "sync",
                "protected fetch unavailable article_id={} reason={} status={}",
                article_id,
                reason,
                error.http_status().unwrap_or_default()
            );
            return Ok(Cancellable::Completed(()));
        }
        Err(error) => return Err(error),
    };
    state.known_articles.insert(protected.article.id);
    state
        .known_enclosures
        .extend(protected.enclosures.iter().map(|enclosure| enclosure.id));
    state.snapshot.articles.push(protected.article);
    state.snapshot.enclosures.extend(protected.enclosures);
    Ok(Cancellable::Completed(()))
}

fn protected_fetch_reason(
    article_id: i64,
    playback_requirements: &[(i64, i64)],
    download_requirements: &[(i64, i64)],
) -> &'static str {
    match (
        playback_requirements
            .iter()
            .any(|(required_article_id, _)| *required_article_id == article_id),
        download_requirements
            .iter()
            .any(|(required_article_id, _)| *required_article_id == article_id),
    ) {
        (true, true) => "playback+download",
        (true, false) => "playback",
        (false, true) => "download",
        (false, false) => "unknown",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::{Article, Category, Enclosure, Feed};
    use crate::miniflux::{RemoteSnapshot, RemoteSource};
    use tempfile::TempDir;

    struct ProtectedFetchFailure;
    struct ProtectedRecoveryRemote {
        response: Result<crate::miniflux::RemoteSavedMediaArticle, CoreError>,
        fetch_calls: std::sync::atomic::AtomicUsize,
    }

    impl RemoteSource for ProtectedFetchFailure {
        fn fetch_initial_articles(&self) -> Result<RemoteSnapshot, CoreError> {
            Ok(RemoteSnapshot {
                categories: vec![Category {
                    id: 1,
                    title: "Category".into(),
                }],
                feeds: vec![Feed {
                    id: 2,
                    category_id: 1,
                    title: "Feed".into(),
                }],
                articles: Vec::new(),
                enclosures: Vec::new(),
            })
        }
        fn set_read_state(&self, _: &[i64], _: bool) -> Result<(), CoreError> {
            Ok(())
        }
        fn set_starred_state(&self, _: i64, _: bool) -> Result<(), CoreError> {
            Ok(())
        }
        fn fetch_article_by_id(
            &self,
            _: i64,
        ) -> Result<crate::miniflux::RemoteSavedMediaArticle, CoreError> {
            Err(CoreError::server_transient("protected fetch failed"))
        }
    }
    impl RemoteSource for ProtectedRecoveryRemote {
        fn fetch_initial_articles(&self) -> Result<RemoteSnapshot, CoreError> {
            Ok(RemoteSnapshot {
                categories: vec![Category {
                    id: 1,
                    title: "Category".into(),
                }],
                feeds: vec![Feed {
                    id: 2,
                    category_id: 1,
                    title: "Feed".into(),
                }],
                articles: Vec::new(),
                enclosures: Vec::new(),
            })
        }
        fn set_read_state(&self, _: &[i64], _: bool) -> Result<(), CoreError> {
            Ok(())
        }
        fn set_starred_state(&self, _: i64, _: bool) -> Result<(), CoreError> {
            Ok(())
        }
        fn fetch_article_by_id(
            &self,
            _: i64,
        ) -> Result<crate::miniflux::RemoteSavedMediaArticle, CoreError> {
            self.fetch_calls
                .fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            self.response.clone()
        }
    }

    fn protected_article() -> Article {
        Article {
            id: 9,
            feed_id: 2,
            title: "Protected".into(),
            url: "https://example.test/9".into(),
            comments_url: String::new(),
            published_at: "2020-01-01T00:00:00Z".into(),
            is_read: true,
            is_starred: false,
            raw_html_content: String::new(),
            reading_time_minutes: 0,
            preview: String::new(),
            image_url: None,
        }
    }

    fn protected_enclosure() -> Enclosure {
        Enclosure {
            id: 90,
            article_id: 9,
            url: "https://example.test/90.mp3".into(),
            mime_type: "audio/mpeg".into(),
            size_bytes: None,
            remote_media_progression_seconds: 0,
        }
    }

    fn protected_store(temp: &TempDir, playback: bool, downloaded: bool) -> Store {
        let data = temp.path().join("data");
        let cache = temp.path().join("cache");
        let media = temp.path().join("media");
        std::fs::create_dir_all(&data).unwrap();
        std::fs::create_dir_all(&cache).unwrap();
        std::fs::create_dir_all(&media).unwrap();
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
                &[protected_article()],
                &[protected_enclosure()],
            )
            .unwrap();
        if playback {
            store
                .checkpoint_playback(90, 1_000, None, "2026-01-01T00:00:00Z", false)
                .unwrap();
        }
        if downloaded {
            store
                .request_download(90, crate::domain::DownloadOrigin::Manual)
                .unwrap();
            store
                .download_finished(90, "downloads/90.mp3", 1024)
                .unwrap();
        }
        store
    }

    fn run_protected_recovery(
        remote: &ProtectedRecoveryRemote,
        store: &Store,
    ) -> Result<SyncData, CoreError> {
        run(
            remote,
            store,
            ReadArticleRetention::Days30,
            SyncReason::Manual,
            HashMap::new(),
        )
    }

    #[test]
    fn downloaded_media_summary_tracks_physical_storage_until_deletion_confirmation() {
        let temp = TempDir::new().unwrap();
        let store = protected_store(&temp, false, true);

        assert_eq!(
            store.downloaded_media_summary().unwrap(),
            crate::domain::DownloadedMediaSummary {
                file_count: 1,
                total_size_bytes: 1024,
            }
        );

        assert_eq!(store.request_all_download_deletions().unwrap(), 1);
        assert_eq!(
            store.media_download(90).unwrap().unwrap().state,
            crate::domain::DownloadState::DeleteRequested
        );
        assert_eq!(
            store.downloaded_media_summary().unwrap(),
            crate::domain::DownloadedMediaSummary {
                file_count: 1,
                total_size_bytes: 1024,
            }
        );

        store.download_deleted(90).unwrap();
        assert_eq!(
            store.downloaded_media_summary().unwrap(),
            crate::domain::DownloadedMediaSummary::default()
        );
        assert_eq!(store.request_all_download_deletions().unwrap(), 0);
    }

    #[test]
    fn required_protected_fetch_failure_aborts_sync() {
        let temp = TempDir::new().unwrap();
        let data = temp.path().join("data");
        let cache = temp.path().join("cache");
        let media = temp.path().join("media");
        std::fs::create_dir_all(&data).unwrap();
        std::fs::create_dir_all(&cache).unwrap();
        std::fs::create_dir_all(&media).unwrap();
        let store = Store::open(&data, &cache, &media).unwrap();
        let article = Article {
            id: 9,
            feed_id: 2,
            title: "Protected".into(),
            url: "https://example.test/9".into(),
            comments_url: String::new(),
            published_at: "2020-01-01T00:00:00Z".into(),
            is_read: true,
            is_starred: false,
            raw_html_content: String::new(),
            reading_time_minutes: 0,
            preview: String::new(),
            image_url: None,
        };
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
                std::slice::from_ref(&article),
                &[Enclosure {
                    id: 90,
                    article_id: 9,
                    url: "https://example.test/90.mp3".into(),
                    mime_type: "audio/mpeg".into(),
                    size_bytes: None,
                    remote_media_progression_seconds: 0,
                }],
            )
            .unwrap();
        store
            .checkpoint_playback(90, 1_000, None, "2026-01-01T00:00:00Z", false)
            .unwrap();

        let result = run(
            &ProtectedFetchFailure,
            &store,
            ReadArticleRetention::Days30,
            SyncReason::Manual,
            HashMap::new(),
        );

        assert_eq!(
            result.unwrap_err().kind,
            crate::domain::CoreErrorKind::ServerTransient
        );
        assert!(store.last_successful_sync_at().unwrap().is_none());
    }

    #[test]
    fn protected_playback_fetch_successfully_restores_missing_remote_article() {
        let temp = TempDir::new().unwrap();
        let store = protected_store(&temp, true, false);
        let remote = ProtectedRecoveryRemote {
            response: Ok(crate::miniflux::RemoteSavedMediaArticle {
                article: protected_article(),
                enclosures: vec![protected_enclosure()],
            }),
            fetch_calls: std::sync::atomic::AtomicUsize::new(0),
        };

        run_protected_recovery(&remote, &store).unwrap();

        assert_eq!(
            remote.fetch_calls.load(std::sync::atomic::Ordering::SeqCst),
            1
        );
        assert!(store.enclosure(90).unwrap().unwrap().remote_present);
        assert!(store.playback_state(90).unwrap().is_some());
    }

    #[test]
    fn terminally_missing_protected_playback_is_retained_and_not_refetched() {
        for status in [404, 410] {
            let temp = TempDir::new().unwrap();
            let store = protected_store(&temp, true, false);
            let remote = ProtectedRecoveryRemote {
                response: Err(CoreError::invalid_configuration(format!(
                    "Miniflux returned HTTP {status}"
                ))
                .with_http_status(status)),
                fetch_calls: std::sync::atomic::AtomicUsize::new(0),
            };

            run_protected_recovery(&remote, &store).unwrap();
            run_protected_recovery(&remote, &store).unwrap();

            assert_eq!(
                remote.fetch_calls.load(std::sync::atomic::Ordering::SeqCst),
                1
            );
            assert!(!store.enclosure(90).unwrap().unwrap().remote_present);
            assert_eq!(
                store.playback_state(90).unwrap().unwrap().position_ms,
                1_000
            );
            assert!(store.last_successful_sync_at().unwrap().is_some());
        }
    }

    #[test]
    fn terminally_missing_protected_download_retains_local_file_reference() {
        let temp = TempDir::new().unwrap();
        let store = protected_store(&temp, false, true);
        let remote = ProtectedRecoveryRemote {
            response: Err(
                CoreError::invalid_configuration("Miniflux returned HTTP 404")
                    .with_http_status(404),
            ),
            fetch_calls: std::sync::atomic::AtomicUsize::new(0),
        };

        run_protected_recovery(&remote, &store).unwrap();

        assert!(!store.enclosure(90).unwrap().unwrap().remote_present);
        let download = store.media_download(90).unwrap().unwrap();
        assert_eq!(download.state, crate::domain::DownloadState::Downloaded);
        assert_eq!(download.local_file.as_deref(), Some("downloads/90.mp3"));
    }

    #[test]
    fn terminally_missing_article_with_playback_and_download_is_fetched_once_and_retained() {
        let temp = TempDir::new().unwrap();
        let store = protected_store(&temp, true, true);
        let remote = ProtectedRecoveryRemote {
            response: Err(
                CoreError::invalid_configuration("Miniflux returned HTTP 404")
                    .with_http_status(404),
            ),
            fetch_calls: std::sync::atomic::AtomicUsize::new(0),
        };

        run_protected_recovery(&remote, &store).unwrap();

        assert_eq!(
            remote.fetch_calls.load(std::sync::atomic::Ordering::SeqCst),
            1
        );
        assert!(store.playback_state(90).unwrap().is_some());
        assert_eq!(
            store.media_download(90).unwrap().unwrap().state,
            crate::domain::DownloadState::Downloaded
        );
    }

    #[test]
    fn non_terminal_protected_fetch_failures_remain_sync_failures() {
        for error in [
            CoreError::server_transient("Miniflux server returned HTTP 500").with_http_status(500),
            CoreError::server_transient("Miniflux server returned HTTP 429").with_http_status(429),
            CoreError::connectivity("offline"),
            CoreError::authentication("Miniflux rejected credentials").with_http_status(401),
            CoreError::authentication("Miniflux rejected credentials").with_http_status(403),
            CoreError::invalid_configuration("Miniflux returned HTTP 400").with_http_status(400),
        ] {
            let temp = TempDir::new().unwrap();
            let store = protected_store(&temp, true, false);
            let expected_kind = error.kind.clone();
            let remote = ProtectedRecoveryRemote {
                response: Err(error),
                fetch_calls: std::sync::atomic::AtomicUsize::new(0),
            };

            assert_eq!(
                run_protected_recovery(&remote, &store).unwrap_err().kind,
                expected_kind
            );
            assert!(store.enclosure(90).unwrap().unwrap().remote_present);
            assert!(store.last_successful_sync_at().unwrap().is_none());
        }
    }

    #[test]
    fn protected_download_requirements_track_enclosure_scoped_protection() {
        let temp = TempDir::new().unwrap();
        let data = temp.path().join("data");
        let cache = temp.path().join("cache");
        let media = temp.path().join("media");
        std::fs::create_dir_all(&data).unwrap();
        std::fs::create_dir_all(&cache).unwrap();
        std::fs::create_dir_all(&media).unwrap();
        let store = Store::open(&data, &cache, &media).unwrap();

        let article = Article {
            id: 9,
            feed_id: 2,
            title: "Download-protected".into(),
            url: "https://example.test/9".into(),
            comments_url: String::new(),
            published_at: "2020-01-01T00:00:00Z".into(),
            is_read: true,
            is_starred: false,
            raw_html_content: String::new(),
            reading_time_minutes: 0,
            preview: String::new(),
            image_url: None,
        };
        let enclosure = Enclosure {
            id: 90,
            article_id: 9,
            url: "https://example.test/90.mp3".into(),
            mime_type: "audio/mpeg".into(),
            size_bytes: None,
            remote_media_progression_seconds: 0,
        };
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
                std::slice::from_ref(&article),
                std::slice::from_ref(&enclosure),
            )
            .unwrap();
        // Requested + Downloaded must appear in the protected set;
        // Failed + DeleteRequested must not.
        store
            .request_download(90, crate::domain::DownloadOrigin::Manual)
            .unwrap();
        assert_eq!(
            store.protected_download_requirements().unwrap(),
            vec![(9, 90)]
        );
        store
            .download_finished(90, "enclosure/90.mp3", 1024)
            .unwrap();
        assert_eq!(
            store.protected_download_requirements().unwrap(),
            vec![(9, 90)]
        );
        store.request_download_deletion(90).unwrap();
        assert_eq!(
            store.protected_download_requirements().unwrap(),
            Vec::<(i64, i64)>::new()
        );
        store.download_deleted(90).unwrap();
        store
            .request_download(90, crate::domain::DownloadOrigin::Manual)
            .unwrap();
        store
            .download_failed(90, crate::domain::DownloadFailureKind::Network)
            .unwrap();
        assert_eq!(
            store.protected_download_requirements().unwrap(),
            Vec::<(i64, i64)>::new()
        );
    }

    #[test]
    fn protected_download_fetch_protects_article_even_when_already_in_snapshot() {
        use crate::domain::CoreErrorKind;
        use std::sync::Mutex;
        use std::sync::atomic::{AtomicUsize, Ordering};

        struct TrackingRemote {
            snapshot: RemoteSnapshot,
            fetch_calls: AtomicUsize,
            fetched_articles: Mutex<Vec<i64>>,
        }
        impl crate::miniflux::RemoteSource for TrackingRemote {
            fn fetch_initial_articles(&self) -> Result<RemoteSnapshot, crate::domain::CoreError> {
                Ok(self.snapshot.clone())
            }
            fn set_read_state(&self, _: &[i64], _: bool) -> Result<(), crate::domain::CoreError> {
                Ok(())
            }
            fn set_starred_state(&self, _: i64, _: bool) -> Result<(), crate::domain::CoreError> {
                Ok(())
            }
            fn fetch_article_by_id(
                &self,
                article_id: i64,
            ) -> Result<crate::miniflux::RemoteSavedMediaArticle, crate::domain::CoreError>
            {
                self.fetch_calls.fetch_add(1, Ordering::SeqCst);
                self.fetched_articles.lock().unwrap().push(article_id);
                Err(crate::domain::CoreError::data("test fetch failure"))
            }
        }
        let temp = TempDir::new().unwrap();
        let data = temp.path().join("data");
        let cache = temp.path().join("cache");
        let media = temp.path().join("media");
        std::fs::create_dir_all(&data).unwrap();
        std::fs::create_dir_all(&cache).unwrap();
        std::fs::create_dir_all(&media).unwrap();
        let store = Store::open(&data, &cache, &media).unwrap();
        // Set up: Article present locally with two enclosures; only Enclosure 10 has a Required download.
        let category = [Category {
            id: 1,
            title: "Category".into(),
        }];
        let feeds = [Feed {
            id: 2,
            category_id: 1,
            title: "Feed".into(),
        }];
        let article = Article {
            id: 9,
            feed_id: 2,
            title: "Article".into(),
            url: "https://example.test/9".into(),
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
                id: 10,
                article_id: 9,
                url: "https://example.test/10.mp3".into(),
                mime_type: "audio/mpeg".into(),
                size_bytes: None,
                remote_media_progression_seconds: 0,
            },
            Enclosure {
                id: 11,
                article_id: 9,
                url: "https://example.test/11.mp3".into(),
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
            .request_download(10, crate::domain::DownloadOrigin::Manual)
            .unwrap();

        // The remote snapshot contains Article 9 and Enclosure 11, but not Enclosure 10.
        let snapshot = RemoteSnapshot {
            categories: category.to_vec(),
            feeds: feeds.to_vec(),
            articles: vec![article.clone()],
            enclosures: vec![enclosures[1].clone()],
        };
        let remote = TrackingRemote {
            snapshot,
            fetch_calls: AtomicUsize::new(0),
            fetched_articles: Mutex::new(Vec::new()),
        };
        let result = run(
            &remote,
            &store,
            ReadArticleRetention::Days30,
            SyncReason::Manual,
            HashMap::new(),
        );
        // The protected fetch must be attempted exactly once because the protected Enclosure is absent
        // from the normal snapshot, even though the parent Article is present.
        assert_eq!(remote.fetch_calls.load(Ordering::SeqCst), 1);
        assert_eq!(*remote.fetched_articles.lock().unwrap(), vec![9]);
        // Fetch errors propagate as the normal sync error.
        assert_eq!(result.unwrap_err().kind, CoreErrorKind::Data);
        assert!(store.last_successful_sync_at().unwrap().is_none());
    }

    #[test]
    fn protected_fetch_coalesces_playback_and_download_on_same_article() {
        use std::sync::Mutex;
        use std::sync::atomic::{AtomicUsize, Ordering};

        struct CountingRemote {
            snapshot: RemoteSnapshot,
            fetch_calls: AtomicUsize,
            fetched_articles: Mutex<Vec<i64>>,
        }
        impl crate::miniflux::RemoteSource for CountingRemote {
            fn fetch_initial_articles(&self) -> Result<RemoteSnapshot, crate::domain::CoreError> {
                Ok(self.snapshot.clone())
            }
            fn set_read_state(&self, _: &[i64], _: bool) -> Result<(), crate::domain::CoreError> {
                Ok(())
            }
            fn set_starred_state(&self, _: i64, _: bool) -> Result<(), crate::domain::CoreError> {
                Ok(())
            }
            fn fetch_article_by_id(
                &self,
                article_id: i64,
            ) -> Result<crate::miniflux::RemoteSavedMediaArticle, crate::domain::CoreError>
            {
                self.fetch_calls.fetch_add(1, Ordering::SeqCst);
                self.fetched_articles.lock().unwrap().push(article_id);
                Ok(crate::miniflux::RemoteSavedMediaArticle {
                    article: crate::domain::Article {
                        id: article_id,
                        feed_id: 2,
                        title: format!("Fetched {article_id}"),
                        url: format!("https://example.test/{article_id}"),
                        comments_url: String::new(),
                        published_at: "2020-01-01T00:00:00Z".into(),
                        is_read: true,
                        is_starred: false,
                        raw_html_content: String::new(),
                        reading_time_minutes: 0,
                        preview: String::new(),
                        image_url: None,
                    },
                    enclosures: vec![],
                })
            }
        }
        let temp = TempDir::new().unwrap();
        let data = temp.path().join("data");
        let cache = temp.path().join("cache");
        let media = temp.path().join("media");
        std::fs::create_dir_all(&data).unwrap();
        std::fs::create_dir_all(&cache).unwrap();
        std::fs::create_dir_all(&media).unwrap();
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
        let article = Article {
            id: 9,
            feed_id: 2,
            title: "Article".into(),
            url: "https://example.test/9".into(),
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
                id: 10,
                article_id: 9,
                url: "https://example.test/10.mp3".into(),
                mime_type: "audio/mpeg".into(),
                size_bytes: None,
                remote_media_progression_seconds: 0,
            },
            Enclosure {
                id: 11,
                article_id: 9,
                url: "https://example.test/11.mp3".into(),
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
            .request_download(10, crate::domain::DownloadOrigin::Manual)
            .unwrap();
        store
            .request_download(11, crate::domain::DownloadOrigin::Manual)
            .unwrap();
        store
            .checkpoint_playback(10, 1_000, None, "2026-01-01T00:00:00Z", false)
            .unwrap();

        // The remote snapshot does not contain either Article 9 nor its protected Enclosures.
        let snapshot = RemoteSnapshot {
            categories: category.to_vec(),
            feeds: feeds.to_vec(),
            articles: Vec::new(),
            enclosures: Vec::new(),
        };
        let remote = CountingRemote {
            snapshot,
            fetch_calls: AtomicUsize::new(0),
            fetched_articles: Mutex::new(Vec::new()),
        };
        let result = run(
            &remote,
            &store,
            ReadArticleRetention::Days30,
            SyncReason::Manual,
            HashMap::new(),
        );
        assert!(result.is_ok());
        // Playback and two protected downloads on the same article must produce one fetch.
        assert_eq!(remote.fetch_calls.load(Ordering::SeqCst), 1);
        assert_eq!(*remote.fetched_articles.lock().unwrap(), vec![9]);
    }

    #[test]
    fn protected_fetch_skips_article_and_enclosures_already_in_snapshot() {
        use std::sync::atomic::{AtomicUsize, Ordering};

        struct NoFetchRemote {
            snapshot: RemoteSnapshot,
            fetch_calls: AtomicUsize,
        }
        impl crate::miniflux::RemoteSource for NoFetchRemote {
            fn fetch_initial_articles(&self) -> Result<RemoteSnapshot, CoreError> {
                Ok(self.snapshot.clone())
            }
            fn set_read_state(&self, _: &[i64], _: bool) -> Result<(), CoreError> {
                Ok(())
            }
            fn set_starred_state(&self, _: i64, _: bool) -> Result<(), CoreError> {
                Ok(())
            }
            fn fetch_article_by_id(
                &self,
                _: i64,
            ) -> Result<crate::miniflux::RemoteSavedMediaArticle, CoreError> {
                self.fetch_calls.fetch_add(1, Ordering::SeqCst);
                Err(CoreError::data("unexpected protected fetch"))
            }
        }

        let temp = TempDir::new().unwrap();
        let data = temp.path().join("data");
        let cache = temp.path().join("cache");
        let media = temp.path().join("media");
        std::fs::create_dir_all(&data).unwrap();
        std::fs::create_dir_all(&cache).unwrap();
        std::fs::create_dir_all(&media).unwrap();
        let store = Store::open(&data, &cache, &media).unwrap();
        let category = Category {
            id: 1,
            title: "Category".into(),
        };
        let feed = Feed {
            id: 2,
            category_id: 1,
            title: "Feed".into(),
        };
        let article = Article {
            id: 9,
            feed_id: 2,
            title: "Article".into(),
            url: "https://example.test/9".into(),
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
                id: 10,
                article_id: 9,
                url: "https://example.test/10.mp3".into(),
                mime_type: "audio/mpeg".into(),
                size_bytes: None,
                remote_media_progression_seconds: 0,
            },
            Enclosure {
                id: 11,
                article_id: 9,
                url: "https://example.test/11.mp3".into(),
                mime_type: "audio/mpeg".into(),
                size_bytes: None,
                remote_media_progression_seconds: 0,
            },
        ];
        store
            .reconcile_with_enclosures(
                std::slice::from_ref(&category),
                std::slice::from_ref(&feed),
                std::slice::from_ref(&article),
                &enclosures,
            )
            .unwrap();
        store
            .request_download(10, crate::domain::DownloadOrigin::Manual)
            .unwrap();
        store
            .checkpoint_playback(11, 1_000, None, "2026-01-01T00:00:00Z", false)
            .unwrap();

        let remote = NoFetchRemote {
            snapshot: RemoteSnapshot {
                categories: vec![category],
                feeds: vec![feed],
                articles: vec![article],
                enclosures: enclosures.to_vec(),
            },
            fetch_calls: AtomicUsize::new(0),
        };
        assert!(
            run(
                &remote,
                &store,
                ReadArticleRetention::Days30,
                SyncReason::Manual,
                HashMap::new(),
            )
            .is_ok()
        );
        assert_eq!(remote.fetch_calls.load(Ordering::SeqCst), 0);
    }
}
