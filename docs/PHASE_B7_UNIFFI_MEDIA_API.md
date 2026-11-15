# Phase B7 — UniFFI Media API

The existing `Flux` UniFFI object exposes the Phase B media domain without
moving playback or transfer execution into the core.

## Native-facing API

- Enclosures and saved playable media use real Miniflux enclosure IDs.
- Saved media: `save_media`, `unsave_media`, `is_media_saved`, `saved_media`,
  `saved_media_by_feed`.
- Optional Saved Media Sync: configuration/status, setup info, automatic/manual
  setup, and disablement.
- Playback: `prepare_playback`, `playback_state`, `checkpoint_playback`,
  `playback_completed`, `restart_playback`, and `observe_media_duration`.
- Capability: `media_progress_capability` exposes `Unknown`, `Supported`, or
  `Unsupported`.
- Downloads: durable state, request/cancel/retry, finished/failed callbacks,
  deletion request/completion, transfer work, and deletion work.
- Policies: feed `auto_download_audio`, download network policy, retention, and
  delete-after-playback through `CoreSettings` and dedicated setters.
- Metadata: `media_metadata` and ordered `media_chapters` with explicit chapter
  source values.
- Artwork: playback and saved-media projections expose the canonical Core
  `MediaArtworkSource` (`LocalReference` or `RemoteUrl`). `media_artwork`
  resolves only Core-owned local references and returns the stored bytes;
  native clients load remote URLs. Remote embedded artwork is not currently
  represented by the Phase-B metadata model.
- Cleanup: `evaluate_media_cleanup` asks Core to evaluate durable cleanup at
  the current time.

## Ownership

UniFFI performs only type conversion and forwards operations to `FluxCore`.
Core remains authoritative for persistence, state-machine validation,
reconciliation, mutation semantics, suppression, policy, cleanup, metadata,
and chapters. Native clients perform playback, filesystem/network transfers,
OS scheduling, and media presentation.

No database, SQL, mutation-outbox, playback-engine, or transfer-engine API is
exported. Schema version is 17, including the Phase-C article-centered
Listening List membership table.
