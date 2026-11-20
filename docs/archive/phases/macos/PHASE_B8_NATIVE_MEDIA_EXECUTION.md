# Phase B8 - Native Media Execution

Phase B8 adds macOS execution for the media operations exposed by the B7
UniFFI boundary. The native client owns OS playback and transfer facilities;
Core remains authoritative for durable state and policy.

## Playback

`MediaPlaybackCoordinator` uses `AVPlayer` and accepts only Core-owned
`PlaybackPreparation` data. It prefers a validated local media file, falls
back to the Core-resolved remote URL, restores the Core position for in-progress
items, and does not implicitly restart completed items. The AVPlayer runtime
position is updated by a native periodic time observer while playback is
running. Position checkpoints are written on pause, seek, lifecycle
transitions, and a periodic 20-second cadence; the observer does not checkpoint
Core on every callback. Natural completion calls `playback_completed` once and
records the observed duration through Core.

AVPlayer duration can be unavailable during initial preparation. The native
engine observes the current item and reports each newly discovered valid
duration through the existing Core `observe_media_duration` operation. Invalid,
indefinite, zero, and non-finite durations are ignored. Replacing an item
removes its observers and guards queued callbacks against the active item.

Application deactivation checkpoints the active item but does not pause
playback. Explicit pause and real playback/session interruptions remain
playback controls; lifecycle checkpointing is separate from playback control.

The coordinator also publishes duration, chapters, artwork, and Now Playing
metadata to the macOS media session. It does not mark articles read or mutate
playback state outside the Core API.

## Transfers

`MediaTransferCoordinator` consumes Core transfer and deletion work. It uses
`URLSession` for downloads, applies Core's network policy, writes only beneath
the configured media root, and reports finished or failed work back to Core.
Temporary files are moved into deterministic Core-provided destinations only
after a successful transfer. Deletion work is completed only after the local
file is absent. Duplicate active tasks are suppressed and cancellation is
best-effort through URLSession. When Core no longer returns requested work,
the coordinator cancels the matching native task where possible. A late native
completion or failure is still sent through the existing Core callback path;
Core's stale-callback rules decide whether it changes durable state. Native
cancellation is not reported as a transfer failure.

`DeleteRequested` work is reconstructed and processed on reconciliation. A
missing local file is idempotently treated as deleted. Physical deletion is
deferred while the playback coordinator is actively using the enclosure; the
Core deletion intent remains unchanged and is retried on the next
reconciliation after playback stops.

`AnyNetwork` permits expensive and constrained URLSession access. `UnmeteredOnly`
sets `allowsExpensiveNetworkAccess` and `allowsConstrainedNetworkAccess` to
false. This is macOS's closest available approximation; it does not promise a
perfect carrier-metering distinction. Downloads waiting for that constraint
remain Core `Requested` rather than becoming `Failed`.

Successful completion is reported to Core only after the temporary URL has
been safely finalized beneath the media root and its size has been read.
Transport errors map to `Network`; finalization and filesystem errors map to
`Storage`. A rejected Core completion callback is logged as a stale/domain
callback result and is not converted into a second failure callback.

Core durable `Requested` and `DeleteRequested` intent survives process death.
On startup/resume, a fresh coordinator reconstructs execution by querying Core
and restarting valid requested transfers or processing pending deletions. The
current implementation uses foreground URLSession downloads, so an in-flight
foreground task itself is not guaranteed to survive process termination. True
OS-persistent background URLSession execution remains deferred.

Optional Saved Media Sync remains outside this coordinator. Local playback and
transfers do not depend on it.

## Integration And Tests

Both coordinators are application-scoped and configured from the existing
`BrowserStore` Core instance. `MediaCoordinatorTests` covers Core-authoritative
resume, explicit restart, natural completion idempotence, checkpoint behavior,
media-root path containment, duplicate suppression, cancellation and stale
callbacks, relaunch reconstruction, finalization ordering, failure mapping,
deletion idempotence/playback protection, and network policy mapping.

Generated UniFFI bindings remain build artifacts. The macOS test target hosts
the app so it can test app-internal coordinator types.

## Deferred

User-facing player UX remains Phase C. True OS-persistent background transfer
execution, richer queue UX, download progress presentation, and automotive or
legacy integration remain deferred to the appropriate later phase. No iOS or
Android client is introduced in this step.
