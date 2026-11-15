//! Optional Miniflux transport for the local SavedMedia domain.

use chrono::Utc;
use std::collections::HashMap;

use crate::domain::{
    CoreError, CreateFeedRequest, SavedMediaMarkerState, SavedMediaSyncConfiguration,
    SavedMediaSyncSetupInfo,
};
use crate::miniflux::{MinifluxCapability, RemoteSource};
use crate::storage::{SavedMediaRemoteState, Store};
use crate::sync_cancellation::{Cancellable, SyncCancellation};

pub const BOOTSTRAP_URL: &str =
    "https://raw.githubusercontent.com/KevinCFechtel/Flux/main/init.xml";
pub const TECHNICAL_FEED_TITLE: &str = "Flux Saved Media";
const MARKER_PREFIX: &str = "flux:saved-media:v1:";

pub fn setup_info() -> SavedMediaSyncSetupInfo {
    SavedMediaSyncSetupInfo {
        bootstrap_url: BOOTSTRAP_URL.to_string(),
        technical_feed_title: TECHNICAL_FEED_TITLE.to_string(),
        explanation: "Optional replication uses a dedicated Miniflux feed. Miniflux fetches Flux's public bootstrap XML once during automatic setup, then Flux disables that feed. Saved media remains local and works without this feature.".to_string(),
    }
}

pub fn setup_automatic(remote: &dyn RemoteSource, store: &Store) -> Result<(), CoreError> {
    require_capability(remote)?;
    let matches = canonical_feeds(remote)?;
    let feed_id = match matches.as_slice() {
        [feed] => feed.id,
        [] => {
            let created = remote.create_feed(CreateFeedRequest {
                feed_url: BOOTSTRAP_URL.to_string(),
                category_id: None,
                username: None,
                password: None,
                crawler: None,
                user_agent: None,
                scraper_rules: None,
                rewrite_rules: None,
                blocklist_rules: None,
                keeplist_rules: None,
                disabled: None,
                ignore_http_cache: None,
                fetch_via_proxy: None,
            })?;
            remote.update_saved_media_sync_feed(
                created.feed_id,
                Some(TECHNICAL_FEED_TITLE),
                true,
            )?;
            let verified = canonical_feeds(remote)?;
            if verified
                .iter()
                .filter(|feed| feed.id == created.feed_id)
                .count()
                != 1
            {
                return Err(CoreError::data(
                    "created SavedMedia technical feed could not be verified",
                ));
            }
            created.feed_id
        }
        _ => {
            return Err(CoreError::data(
                "multiple SavedMedia technical feeds match the canonical bootstrap URL; resolve duplicates in Miniflux",
            ));
        }
    };
    store.enable_saved_media_sync(feed_id)
}

/// Enables replication using exactly one manually created canonical feed. This never modifies it.
pub fn setup_manual(remote: &dyn RemoteSource, store: &Store) -> Result<(), CoreError> {
    require_capability(remote)?;
    let matches = canonical_feeds(remote)?;
    let [feed] = matches.as_slice() else {
        return Err(CoreError::data(if matches.is_empty() {
            "no SavedMedia technical feed matches the canonical bootstrap URL"
        } else {
            "multiple SavedMedia technical feeds match the canonical bootstrap URL; resolve duplicates in Miniflux"
        }));
    };
    if !feed.disabled {
        return Err(CoreError::data(
            "manual SavedMedia technical feed is enabled; disable it explicitly before enabling replication",
        ));
    }
    store.enable_saved_media_sync(feed.id)
}

pub fn run(remote: &dyn RemoteSource, store: &Store) -> Result<bool, CoreError> {
    let cancellation = SyncCancellation::new();
    match run_cancellable(remote, store, &cancellation)? {
        Cancellable::Completed(changed) => Ok(changed),
        Cancellable::Cancelled => unreachable!("fresh cancellation signal cannot be cancelled"),
    }
}

pub(crate) fn run_cancellable(
    remote: &dyn RemoteSource,
    store: &Store,
    cancellation: &SyncCancellation,
) -> Result<Cancellable<bool>, CoreError> {
    if cancellation.is_cancelled() {
        return Ok(Cancellable::Cancelled);
    }
    let configuration = store.saved_media_sync_configuration()?;
    if !configuration.enabled {
        return Ok(Cancellable::Completed(false));
    }

    let feed_result = configured_feed(remote, store, &configuration);
    if cancellation.is_cancelled() {
        return Ok(Cancellable::Cancelled);
    }
    let feed_id = feed_result?;
    let mut successfully_written = HashMap::new();

    for pending in store.pending_saved_media_replication()? {
        if cancellation.is_cancelled() {
            return Ok(Cancellable::Cancelled);
        }
        let external_id = marker_external_id(pending.article_id, pending.enclosure_id);
        let Some(mut markers) = remote.saved_media_markers_cancellable(feed_id, cancellation)?
        else {
            return Ok(Cancellable::Cancelled);
        };
        let marker = markers
            .iter()
            .find(|marker| marker.external_id == external_id);
        let marker_id = match marker {
            Some(marker) => marker.entry_id,
            None => {
                let import_result = remote.import_saved_media_marker(
                    feed_id,
                    &external_id,
                    pending.article_id,
                    pending.enclosure_id,
                );
                if cancellation.is_cancelled() {
                    return Ok(Cancellable::Cancelled);
                }
                import_result?;
                let Some(refetched) =
                    remote.saved_media_markers_cancellable(feed_id, cancellation)?
                else {
                    return Ok(Cancellable::Cancelled);
                };
                markers = refetched;
                markers
                    .iter()
                    .find(|marker| marker.external_id == external_id)
                    .ok_or_else(|| {
                        CoreError::data("Miniflux did not return the imported SavedMedia marker")
                    })?
                    .entry_id
            }
        };

        let write_result = remote.set_saved_media_marker_state(
            marker_id,
            pending.desired == SavedMediaMarkerState::Saved,
        );
        if let Err(error) = write_result {
            if cancellation.is_cancelled() {
                return Ok(Cancellable::Cancelled);
            }
            return Err(error);
        }

        // Remote marker state and its local acknowledgement form one durable safe unit.
        let state = pending.desired;
        store.acknowledge_saved_media_replication_with_remote_state(
            &SavedMediaRemoteState {
                enclosure_id: pending.enclosure_id,
                article_id: pending.article_id,
                marker_entry_id: marker_id,
                state,
            },
            pending.desired,
        )?;
        successfully_written.insert(pending.enclosure_id, state);
        if cancellation.is_cancelled() {
            return Ok(Cancellable::Cancelled);
        }
    }

    let Some(markers) = remote.saved_media_markers_cancellable(feed_id, cancellation)? else {
        return Ok(Cancellable::Cancelled);
    };
    let mut changed = false;
    for marker in markers {
        if cancellation.is_cancelled() {
            return Ok(Cancellable::Cancelled);
        }
        let Some((article_id, enclosure_id)) = parse_marker_external_id(&marker.external_id) else {
            if marker.external_id.starts_with("flux:saved-media:") {
                tracing::warn!(target: "saved_media_sync", "ignoring malformed SavedMedia marker");
            }
            continue;
        };
        if store.saved_media_replication_pending(enclosure_id)? {
            continue;
        }
        let state = if marker.status == "removed" {
            SavedMediaMarkerState::Unsaved
        } else {
            SavedMediaMarkerState::Saved
        };
        if same_run_snapshot_is_stale(successfully_written.get(&enclosure_id), state) {
            tracing::debug!(target: "saved_media_sync", "ignoring contradictory same-run SavedMedia marker snapshot enclosure_id={enclosure_id}");
            continue;
        }
        let previous = store.saved_media_remote_state(enclosure_id)?;
        if previous.as_ref().is_none_or(|previous| {
            previous.state != state || previous.marker_entry_id != marker.entry_id
        }) {
            match store.apply_remote_saved_media_state(
                enclosure_id,
                state,
                &Utc::now().to_rfc3339(),
            ) {
                Ok(()) => changed = true,
                Err(error) if state == SavedMediaMarkerState::Saved => {
                    if cancellation.is_cancelled() {
                        return Ok(Cancellable::Cancelled);
                    }
                    let resolved_result = remote.fetch_saved_media_article(article_id);
                    if cancellation.is_cancelled() {
                        return Ok(Cancellable::Cancelled);
                    }
                    let resolution = resolved_result.and_then(|resolved| {
                        let enclosure = resolved
                            .enclosures
                            .into_iter()
                            .find(|item| item.id == enclosure_id)
                            .ok_or_else(|| {
                                CoreError::data(
                                    "SavedMedia marker enclosure is absent from its original Miniflux entry",
                                )
                            })?;
                        store.materialize_saved_media(
                            &resolved.article,
                            &enclosure,
                            &Utc::now().to_rfc3339(),
                        )
                    });
                    match resolution {
                        Ok(()) => changed = true,
                        Err(resolve_error) => {
                            // Do not advance the baseline, so a later normal sync retries resolution.
                            tracing::warn!(target: "saved_media_sync", "SavedMedia marker resolution deferred article_id={} enclosure_id={} original_kind={:?} resolution_kind={:?}", article_id, enclosure_id, error.kind, resolve_error.kind);
                            continue;
                        }
                    }
                }
                Err(error) => return Err(error),
            }
        }
        if cancellation.is_cancelled() {
            return Ok(Cancellable::Cancelled);
        }
        store.record_saved_media_remote_state(&SavedMediaRemoteState {
            enclosure_id,
            article_id,
            marker_entry_id: marker.entry_id,
            state,
        })?;
        if cancellation.is_cancelled() {
            return Ok(Cancellable::Cancelled);
        }
    }

    if cancellation.is_cancelled() {
        Ok(Cancellable::Cancelled)
    } else {
        Ok(Cancellable::Completed(changed))
    }
}

pub fn marker_external_id(article_id: i64, enclosure_id: i64) -> String {
    format!("{MARKER_PREFIX}{article_id}:{enclosure_id}")
}

fn parse_marker_external_id(value: &str) -> Option<(i64, i64)> {
    let suffix = value.strip_prefix(MARKER_PREFIX)?;
    let (article, enclosure) = suffix.split_once(':')?;
    if enclosure.contains(':') {
        return None;
    }
    let article_id = article.parse().ok()?;
    let enclosure_id = enclosure.parse().ok()?;
    (article_id > 0 && enclosure_id > 0).then_some((article_id, enclosure_id))
}

fn same_run_snapshot_is_stale(
    successfully_written: Option<&SavedMediaMarkerState>,
    observed: SavedMediaMarkerState,
) -> bool {
    successfully_written.is_some_and(|written| *written != observed)
}

fn require_capability(remote: &dyn RemoteSource) -> Result<(), CoreError> {
    remote
        .miniflux_capabilities()?
        .contains(&MinifluxCapability::SavedMediaSync)
        .then_some(())
        .ok_or_else(|| CoreError::data("SavedMedia Sync requires Miniflux 2.2.16 or newer"))
}

fn canonical_feeds(
    remote: &dyn RemoteSource,
) -> Result<Vec<crate::miniflux::RemoteFeedInfo>, CoreError> {
    Ok(remote
        .saved_media_sync_feeds()?
        .into_iter()
        .filter(|feed| feed.feed_url == BOOTSTRAP_URL)
        .collect())
}

fn configured_feed(
    remote: &dyn RemoteSource,
    store: &Store,
    configuration: &SavedMediaSyncConfiguration,
) -> Result<i64, CoreError> {
    let Some(feed_id) = configuration.sync_feed_id else {
        store.mark_saved_media_sync_repair_required()?;
        return Err(CoreError::data("SavedMedia Sync setup requires repair"));
    };
    let matching = canonical_feeds(remote)?
        .into_iter()
        .any(|feed| feed.id == feed_id);
    if !matching {
        store.mark_saved_media_sync_repair_required()?;
        return Err(CoreError::data(
            "configured SavedMedia technical feed is missing or invalid; setup requires repair",
        ));
    }
    Ok(feed_id)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn marker_identity_is_stable_and_strict() {
        assert_eq!(marker_external_id(3, 4), "flux:saved-media:v1:3:4");
        assert_eq!(
            parse_marker_external_id("flux:saved-media:v1:3:4"),
            Some((3, 4))
        );
        assert_eq!(parse_marker_external_id("flux:saved-media:v2:3:4"), None);
        assert_eq!(parse_marker_external_id("flux:saved-media:v1:3:4:5"), None);
    }

    #[test]
    fn same_run_stale_snapshot_protection_is_directional_and_temporary() {
        assert!(same_run_snapshot_is_stale(
            Some(&SavedMediaMarkerState::Saved),
            SavedMediaMarkerState::Unsaved
        ));
        assert!(same_run_snapshot_is_stale(
            Some(&SavedMediaMarkerState::Unsaved),
            SavedMediaMarkerState::Saved
        ));
        assert!(!same_run_snapshot_is_stale(
            Some(&SavedMediaMarkerState::Saved),
            SavedMediaMarkerState::Saved
        ));
        // A later run has no transient write record, so a genuine remote change can apply.
        assert!(!same_run_snapshot_is_stale(
            None,
            SavedMediaMarkerState::Unsaved
        ));
    }
}
