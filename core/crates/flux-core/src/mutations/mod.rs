use std::collections::HashMap;

use crate::MediaProgressCapability;
use crate::domain::{CoreError, CoreEvent, MutationField};
use crate::miniflux::RemoteSource;
use crate::storage::Store;
use crate::sync_cancellation::{Cancellable, SyncCancellation};

#[derive(Clone, Debug, Default)]
pub(crate) struct DeliveryResult {
    pub count: u32,
    pub media_progress: HashMap<i64, u64>,
}

/// Sends article and enclosure mutations using their typed durable stores.
pub(crate) fn deliver_pending(
    remote: &dyn RemoteSource,
    store: &Store,
    media_progress_capability: MediaProgressCapability,
    emit: &dyn Fn(CoreEvent),
) -> Result<DeliveryResult, CoreError> {
    let cancellation = SyncCancellation::new();
    match deliver_pending_cancellable(
        remote,
        store,
        media_progress_capability,
        emit,
        &cancellation,
    )? {
        Cancellable::Completed(result) => Ok(result),
        Cancellable::Cancelled => unreachable!("fresh cancellation signal cannot be cancelled"),
    }
}

pub(crate) fn deliver_pending_cancellable(
    remote: &dyn RemoteSource,
    store: &Store,
    media_progress_capability: MediaProgressCapability,
    emit: &dyn Fn(CoreEvent),
    cancellation: &SyncCancellation,
) -> Result<Cancellable<DeliveryResult>, CoreError> {
    let mut result = DeliveryResult::default();
    for pending in store.pending_mutations()? {
        if cancellation.is_cancelled() {
            return Ok(Cancellable::Cancelled);
        }

        match pending.field {
            MutationField::Read => {
                let remote_result = remote.set_read_state(&[pending.article_id], pending.desired);
                if let Err(error) = remote_result {
                    if cancellation.is_cancelled() {
                        return Ok(Cancellable::Cancelled);
                    }
                    return Err(error);
                }
            }
            MutationField::Starred => {
                if !remote.set_starred_state_cancellable(
                    pending.article_id,
                    pending.desired,
                    cancellation,
                )? {
                    return Ok(Cancellable::Cancelled);
                }
            }
        }

        // A successful remote write and its durable acknowledgement are one safe unit. Cancellation
        // must not strand an already-applied remote mutation as locally pending.
        store.acknowledge(&pending)?;
        result.count += 1;
        emit(CoreEvent::MutationDeliverySucceeded {
            article_id: pending.article_id,
            field: pending.field,
        });
        if cancellation.is_cancelled() {
            return Ok(Cancellable::Cancelled);
        }
    }

    for pending in store.pending_media_progress_mutations()? {
        if cancellation.is_cancelled() {
            return Ok(Cancellable::Cancelled);
        }

        match media_progress_capability {
            MediaProgressCapability::Unsupported => {
                // The local checkpoint remains authoritative; only its unsupported remote intent is obsolete.
                store.discard_media_progress(&pending)?;
            }
            MediaProgressCapability::Unknown => {}
            MediaProgressCapability::Supported => {
                let remote_result =
                    remote.set_media_progression(pending.enclosure_id, pending.progression_seconds);
                match remote_result {
                    Ok(()) => {
                        // Preserve the same remote-write/local-ack safe unit as article mutations.
                        store.acknowledge_media_progress(&pending)?;
                        result.count += 1;
                        result
                            .media_progress
                            .insert(pending.enclosure_id, pending.progression_seconds);
                    }
                    Err(error) if matches!(error.http_status(), Some(404 | 410)) => {
                        // A gone enclosure cannot accept progress, but it must not remove local playback.
                        store.discard_media_progress(&pending)?;
                    }
                    Err(error) => {
                        if cancellation.is_cancelled() {
                            return Ok(Cancellable::Cancelled);
                        }
                        return Err(error);
                    }
                }
            }
        }

        if cancellation.is_cancelled() {
            return Ok(Cancellable::Cancelled);
        }
    }

    if cancellation.is_cancelled() {
        Ok(Cancellable::Cancelled)
    } else {
        Ok(Cancellable::Completed(result))
    }
}
