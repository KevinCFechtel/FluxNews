# Flux Phase B — Shared Podcast / Media Core

**Status:** Architecture frozen / implementation-ready  
**Scope:** Phase B — Shared Podcast / Media Core  
**Authority:** This document is the canonical implementation contract for Phase B.

> Phase B extends the shared Rust core with a cross-platform media and podcast domain.  
> Existing Phase A architecture remains authoritative. Phase B must integrate with the existing sync, persistence, mutation, and native-boundary architecture rather than introducing parallel systems.

---

## 1. Core Architectural Boundary

The shared Rust core owns durable domain state, policy, persistence, reconciliation, and Miniflux communication.

Native clients own OS-specific runtime mechanisms.

### Rust Core owns

- Enclosures
- Playback state and durable playback progress
- Download intent and durable download state
- Auto-download policy
- Download retention and cleanup decisions
- Media metadata
- Chapters
- Artwork selection
- Miniflux `media_progression`
- Local/remote playback reconciliation
- Query/read models
- Article/feed relationships
- Media-related article-retention protection

### Native clients own

- AVFoundation / Media3 playback engines
- Play / pause / seek / playback speed
- Sleep timer
- Buffering
- Audio session / audio focus
- Long-running OS-native transfers
- Runtime download progress
- Now Playing / lock screen integration
- CarPlay / Android Auto
- OS media/download notifications
- Dynamic Island or equivalent OS presentation
- Platform-specific transfer registry
- Physical filesystem operations required by OS transfer APIs

**Architectural rule:**

> The core decides domain state and intent. Native code performs OS-specific runtime work.

The core is not a remote control for native media engines. Do not introduce APIs such as `core.play()`, `core.pause()`, or `core.seek()`.

---

## 2. Enclosure Domain

Miniflux enclosures become full persistent core entities.

Conceptual model:

```text
Enclosure
  id: EnclosureId
  article_id: ArticleId
  url: String
  mime_type: String
  size_bytes: Option<u64>
  remote_media_progression_seconds: u64
```

Derive a media classification from the raw MIME value:

```text
MediaKind
  Audio
  Video
  Image
  Other
```

### Rules

- The Miniflux enclosure ID is the canonical enclosure identity.
- Do not introduce synthetic or negative enclosure IDs.
- `user_id` is not part of the Flux domain model.
- Normalize non-positive or otherwise unknown size values to `None`.
- Keep the raw URL and MIME type.
- Local download path, playback state, chapters, artwork, and derived metadata do not belong in `Enclosure`.
- Multiple enclosures per article must be fully supported.
- A remotely removed enclosure may remain locally if durable media state still depends on it.
- Persist a minimal remote-presence semantic such as `remote_present`.
- Definitive remote deletion of an article or enclosure must not poison synchronization or destroy locally protected playback/download state; retained local media records its remote absence and may outlive the originating Miniflux resource.

A normal remote enclosure does not exist independently of its article. If local media state still requires the enclosure, the associated article must be protected from article cleanup.

---

## 3. Playback Domain

Durable local playback state:

```text
PlaybackState
  enclosure_id
  position_ms
  duration_ms?
  status
  updated_at
```

Playback status:

```text
NotStarted
InProgress
Completed
```

### Persistence rule

No `PlaybackState` row means `NotStarted`.

Local positions are stored in milliseconds. Miniflux uses integer seconds only at the API boundary.

### Core playback operations

```text
prepare_playback(enclosure_id)

checkpoint_playback(
    enclosure_id,
    position_ms,
    duration_ms?
)

playback_completed(
    enclosure_id,
    duration_ms
)

restart_playback(enclosure_id)

observe_media_duration(
    enclosure_id,
    duration_ms
)
```

Native code should send playback checkpoints approximately every 20 seconds and on meaningful events, including:

- pause
- stop
- seek
- chapter seek
- audio interruption
- foreground → background lifecycle transition
- media switch
- playback completion

Do not send high-frequency player time callbacks across UniFFI and do not persist them continuously to SQLite.

---

## 4. Playback Completion and Restart

Completion is an explicit domain state.

```text
status = Completed
position = duration
```

Remote progression should be written as the final duration in seconds.

`0` must never mean completion.

Restart is an explicit domain operation:

```text
restart_playback(enclosure_id)
```

Result:

```text
status = InProgress
position = 0
desired remote progression = 0
```

Do not encode restart as an accidental `checkpoint(0)` semantic.

---

## 5. Local / Remote Playback Reconciliation

Miniflux exposes only integer `media_progression`. It provides no revision, timestamp, device identity, or explicit completion flag.

Therefore:

> Never reconcile by numeric `max(local, remote)`.

### Reconciliation rules

- No local `PlaybackState` → adopt remote progression.
- Remote progression unchanged since the last observed remote baseline → keep local state.
- Pending local media-progress mutation exists → local state wins.
- A checkpoint equal to the last known remote progression is not a new local
  intent and must not create or retain a pending media-progress mutation.
- Remote progression changed and no local pending intent exists → adopt remote state.
- A media-progress mutation successfully delivered during the current sync must not be overwritten by an immediately following stale remote snapshot.
- Backward seeks are legitimate desired states.
- Remote reconciliation must never force-seek an already active native player.
- True concurrent cross-device edits are effectively last-successful-writer-wins.

Remote completion may only be inferred when duration is known and remote progression is within a small technical tolerance of the duration.

If duration is unknown and remote progression is non-zero, interpret it as `InProgress`.

---

## 6. Media Progress Mutations

Reuse the existing Phase A durable mutation infrastructure.

Conceptual mutation:

```text
MediaProgressMutation
  enclosure_id
  progression_seconds
```

### Rules

- Do not create a second media mutation queue.
- Keep only the latest desired pending progression per enclosure.
- Coalescing means replacement, not maximum.
- A backward seek must be able to replace a higher pending value.
- Completion writes the duration.
- Restart writes `0`.
- Do not create undeliverable remote mutations when the server does not support media progression.
- A permanently unavailable remote enclosure must not poison normal synchronization: discard only its matching pending remote-progress intent, keep local playback state intact, and continue normal synchronization. Temporary delivery failures and unknown capability state retain the pending intent for retry.

Expose server capability conceptually as:

```text
MediaProgressSync
```

Miniflux 2.2.0+ supports remote progression synchronization.

Local playback must remain fully functional on older Miniflux versions.

---

## 7. Saved Media / Episode Library

Flux must distinguish between the user's durable intent to keep an episode in the media library and the technical decision to download that episode.

The episode library is therefore a separate core concept and must not be derived from download state.

Conceptual model:

```text
SavedMedia
  enclosure_id
  added_at
```

### Semantics

`SavedMedia` means:

> The user deliberately wants this playable enclosure to remain available in their personal episode library.

It does **not** mean that the media file must be downloaded.

These combinations are all valid:

```text
Saved + NotDownloaded
Saved + Requested
Saved + Downloaded
Saved + InProgress

NotSaved + Downloaded
NotSaved + InProgress
```

Saved/library state, download state, and playback state are independent domain dimensions.

### Core operations

Conceptually expose:

```text
save_media(enclosure_id)
unsave_media(enclosure_id)
saved_playable_media()
saved_media_by_feed(feed_id)
```

Exact public API names are implementation details.

### Persistence

Persist the library relationship in the shared core database:

```text
saved_media
--------------------------------
enclosure_id PRIMARY KEY
added_at
```

The enclosure ID is the stable identity.

Do not create article-keyed, URL-keyed, synthetic, or download-derived saved-media identities.

### Local-first with optional Miniflux replication

`SavedMedia` remains a normal durable local Core domain concept. Playback, downloads, retention protection, and the episode library must work completely without remote Saved Media synchronization.

Phase B additionally supports an **explicitly opt-in Saved Media Sync** that replicates saved/unsaved state through the user's existing Miniflux server.

This replication is an adapter above `SavedMedia`; it does not change the meaning or ownership of the local domain state.

Do not:

- map `SavedMedia` to Miniflux starred state
- encode it in `media_progression`
- make Saved Media Sync mandatory for the media core
- introduce a Flux-specific user-data synchronization service

#### Miniflux capability requirement

The optional replication requires a Miniflux version that supports importing entries into an existing feed.

Flux must expose this as a capability and keep Saved Media fully local when the server does not support it.

#### Dedicated technical sync feed

Saved Media replication uses one dedicated technical Miniflux feed as a container for Flux-managed marker entries.

The feed is not the episode library itself. It is only a replication transport.

Flux identifies the technical feed by its canonical bootstrap `feed_url`, not by its display title.

The canonical bootstrap feed is a minimal valid RSS/Atom XML file stored publicly in the Flux source repository (for example `init.xml`). Its source and contents must be inspectable by users.

The bootstrap feed contains no user data and no synthetic podcast episodes.

After successful creation, the technical feed should be disabled so Miniflux does not continue polling the bootstrap XML. Entry import remains the mechanism used for replication.

The concrete canonical repository URL is an implementation/release detail, but it must be stable for a released Flux version.

#### Explicit user consent

Saved Media Sync is disabled by default.

Before setup, Flux must briefly and clearly explain that:

- Flux will use a dedicated technical feed in the user's Miniflux account;
- automatic setup causes the user's Miniflux server to fetch the public Flux `init.xml` once during feed creation;
- the feed is then disabled and used as a container for Saved Media synchronization;
- saved-media state remains on the user's Miniflux server; the bootstrap XML contains no user data;
- the feature is optional and the local episode library works without it.

Setup must only begin after explicit user approval.

#### Setup modes

Flux offers two equivalent setup paths:

```text
Automatic setup
Manual setup
```

These are setup methods, not different long-term synchronization modes.

##### Automatic setup

After explicit approval, Flux:

1. searches for an already existing technical feed whose `feed_url` matches the canonical bootstrap URL;
2. reuses it when exactly one valid matching feed exists;
3. otherwise creates the feed through the Miniflux API using the canonical bootstrap URL;
4. gives it a recognizable title such as `Flux Saved Media`;
5. disables the feed after successful creation;
6. verifies the resulting feed;
7. stores the resolved Miniflux `feed_id` as the replication container.

Flux must not create a second technical feed merely because the feature is activated from another device.

##### Manual setup

Flux shows:

- the canonical bootstrap URL;
- a concise explanation of the required Miniflux feed;
- instructions to create it in Miniflux manually.

The user creates the feed on their own server.

Flux then discovers and verifies the feed by canonical `feed_url`.

The manual path is intentionally available for users who want full control over server-side changes.

Flux must not silently modify a manually created feed. If the feed is still enabled, Flux should explain that disabling it avoids unnecessary polling and offer either:

- an explicit action allowing Flux to disable it; or
- instructions for the user to disable it in Miniflux.

After verification, both setup paths produce the same configured synchronization state.

#### Durable configuration

Do not persist `Automatic` or `Manual` as behavioral modes.

Conceptually, only the resulting configuration matters:

```text
SavedMediaSync
  enabled
  sync_feed_id
```

The setup path has no effect on later replication semantics.

If the configured feed disappears, Flux must report that setup is required again rather than silently creating a replacement without user approval.

#### Marker identity and semantics

Each replicated enclosure uses a stable marker identity derived from the original Miniflux entities, conceptually:

```text
external_id =
  flux:saved-media:v1:<entry-id>:<enclosure-id>
```

Exact serialization is an implementation detail, but it must be deterministic and versioned.

Marker entries are metadata used for replication. They must not be treated as copied podcast episodes and must not replace the original article or enclosure.

The receiving Flux client resolves the marker back to the original Miniflux entry/enclosure and materializes the normal local `SavedMedia` state.

Save and unsave must both be representable. Unsaving must not rely on physical deletion of the marker because other devices need a durable indication that the state was intentionally removed. The marker protocol therefore needs an explicit active/removed state using supported Miniflux entry state semantics.

The detailed conflict-resolution algorithm is an implementation detail to specify before the replication adapter is implemented, but it must preserve the local-first `SavedMedia` domain and must not reuse article starring or media progression.

#### Failure behavior

Failure to create, discover, verify, or access the technical feed must never break the local media library.

The result is a Saved Media Sync setup/error state while local `SavedMedia` continues to operate normally.

Temporary unavailability of the public bootstrap XML only affects first-time automatic feed creation. Once the technical feed exists and is disabled, normal Saved Media replication must not depend on fetching the bootstrap XML.

### Relationship to article starred state

`SavedMedia` and article `starred` represent different user intents.

An article may be starred without its media being saved. A media enclosure may be saved without the article being starred.

Do not automatically couple these states.

This distinction is especially important because an article may contain multiple playable enclosures while Miniflux starring applies to the article as a whole.

### Retention protection

A saved enclosure protects both itself and its associated article from normal article retention:

```text
SavedMedia
-> protects Enclosure
-> protects Article
```

Protection remains until the user explicitly removes the enclosure from the saved-media library.

Download cleanup must not remove `SavedMedia`.

Playback completion must not remove `SavedMedia`.

### Episode overview / media library

The primary persistent episode overview must be based on `SavedMedia`, not on downloaded files.

The previous conceptual download-only episode overview is replaced by a media-library/read-model view based on saved episodes.

The core should provide an efficient denormalized read model conceptually similar to:

```text
SavedPlayableMediaItem
  enclosure_id
  article_id
  feed_id
  title
  feed_title
  published_at
  added_at
  playback_status
  resume_position_ms
  duration_ms?
  download_state
  local_source?
  artwork?
```

The exact fields are implementation details. Native clients must not reconstruct article/feed/media relationships through many UniFFI round trips.

Downloads may still have dedicated management views, but download state is no longer the definition of the episode library.

### Feed-scoped library

The saved-media layer is also the durable content basis for feed-scoped playback navigation.

The core should provide deterministic feed-scoped access, conceptually:

```text
saved_media_by_feed(feed_id)
```

Default ordering is by episode publication time unless a later explicit product decision changes it.

This allows native clients to construct temporary playback queues from the durable library.

### Foundation for next/previous playback

The core still does **not** persist the active playback queue.

Native playback coordinators continue to own:

```text
current queue
current item
current index
```

However, `SavedMedia` becomes the canonical durable episode set for features such as:

- play the next saved episode from the same feed
- continue through saved episodes of a feed
- construct a temporary "Up Next" queue
- resume from the saved episode overview

Native code may obtain an ordered feed-scoped saved-media read model and derive next/previous items from it.

Do not introduce a durable `NextEpisode`, `UpNext`, or queue state for this Phase B requirement.

If Flux later introduces a user-editable persistent queue, model it as a separate domain concept instead of overloading `SavedMedia`.

### Save and download interaction

Saving and downloading remain separate operations.

A UI flow may choose to perform both:

```text
save_media(enclosure_id)
+
request_download(enclosure_id)
```

but this is composition of two domain intents, not one shared state.

A future preference such as "automatically download saved episodes" may be added without changing the meaning of `SavedMedia`.

Manual download does not implicitly mean saved unless a later explicit product decision changes that UX.

Deleting a downloaded file must never unsave the episode.

---

## 8. Download Domain

Durable states:

```text
NotDownloaded
Requested
Downloaded
Failed
DeleteRequested
```

### Persistence rule

No `MediaDownload` row means `NotDownloaded`.

Conceptual model:

```text
MediaDownload
  enclosure_id
  state
  origin?
  local_file_reference?
  file_size?
  downloaded_at?
  failure_kind?
```

Download origin:

```text
Manual
Automatic
```

Do not persist native runtime transfer states such as:

```text
Queued
WaitingForWifi
Connecting
Downloading
PausedByOS
runtime percentage
```

Those belong to native/OS runtime state.

### State machine

```text
NotDownloaded
    -> Requested

Requested
    -> Downloaded
    -> Failed
    -> NotDownloaded

Failed
    -> Requested

Downloaded
    -> DeleteRequested

DeleteRequested
    -> NotDownloaded
```

`Failed` represents a genuine terminal transfer failure. Waiting for network constraints is not a failure.

---

## 9. Native Background Transfers

Core rule:

> The core expresses that an enclosure should be downloaded. Native code performs the actual transfer.

Native code owns a platform-specific transfer coordinator:

```text
MediaTransferCoordinator
```

and a small native transfer registry:

```text
enclosure_id <-> platform_task_id
```

The transfer registry is not part of the shared core database.

### Recovery input

Native recovery reconciles:

```text
core desired state
+
OS transfer state
+
native transfer registry
+
actual files
```

### Required recovery behavior

- `Requested` + active OS transfer → keep as-is.
- `Requested` + no OS transfer → recreate the transfer.
- `Requested` + already completed file → report completion to the core.
- `Downloaded` + file exists → valid.
- `Downloaded` + file missing → reconcile to `NotDownloaded`.
- `NotDownloaded` + orphan OS transfer → cancel it.
- `NotDownloaded` + orphan file → delete it.
- `DeleteRequested` → native deletes the physical file and confirms completion.

### Apple V1 target

Use a background `URLSession` with `URLSessionDownloadTask`.

### Android

Expose a native `MediaTransferCoordinator`.

The cross-platform contract deliberately does not freeze a single Android API. The backend may vary by Android version, transfer origin, and OS guidance.

---

## 10. Download Network Policy

Core model:

```text
DownloadNetworkPolicy
  AnyNetwork
  UnmeteredOnly
```

The core stores policy. Native code maps the policy to OS-specific transfer constraints.

A `Requested` download waiting for an allowed network remains `Requested`.

---

## 11. Auto-Download

Auto-download is a feed-level policy:

```text
FeedPreferences
  auto_download_audio: bool
```

A separate global master state is not required for V1.

An enclosure is eligible for automatic download when all of the following are true:

- `MediaKind == Audio`
- the feed has auto-download enabled
- the enclosure is first discovered during normal live synchronization
- no `Requested` download exists
- no `Downloaded` download exists
- no `DeleteRequested` download exists
- no durable auto-download suppression exists

### Rules

- Enabling auto-download on an existing feed does not backfill historical episodes.
- Initial sync / database rebuild must not create a download storm.
- Auto-download uses the same core `request_download()` path as a manual download.
- Multiple audio enclosures are treated independently.

Do not include transient Wi-Fi, power, battery, or runtime OS state in core eligibility. Those are native transfer constraints.

---

## 12. Auto-Download Suppression

Conceptual entity:

```text
AutoDownloadSuppression
  enclosure_id
```

It represents an explicit user decision.

Create suppression for cases such as:

- explicitly cancelling an automatic download
- explicitly deleting an episode while its feed is under auto-download policy

Do not create suppression for:

- automatic retention cleanup
- delete-after-playback
- other automatic policy-driven cleanup

An explicit manual re-download clears suppression.

Suppression ends with the final enclosure lifecycle.

---

## 13. Media Metadata

Persist durable deterministic media metadata separately from `Enclosure`.

Conceptual model:

```text
MediaMetadata
  enclosure_id
  duration_ms?
  artwork_reference?
```

Chapters:

```text
MediaChapter
  title
  start_ms
  end_ms?
  source
```

Chapter source:

```text
Embedded
ArticleContent
```

### Source priorities

#### Chapters

```text
local embedded
> remote embedded
> article timestamps
> none
```

Do not merge embedded and article-derived chapter sets in V1. Embedded structured chapters win as a complete set.

#### Duration

```text
local file analysis
> reliable remote analysis
> native player observation
> unknown
```

#### Artwork

```text
explicit suitable image enclosure
> local embedded artwork
> remote embedded artwork
> article/feed image
> native fallback
```

Metadata provenance is evaluated per component. Do not use one global metadata origin.

Do not store large artwork blobs in SQLite. Persist a logical or relative cache/media reference.

---

## 14. Remote Metadata Probe

The core may perform optional bounded HTTP Range probes against remote media.

### Requirements

- lazy / on-demand only
- not part of every normal sync
- never a playback prerequisite
- bounded request count
- bounded byte count
- bounded total duration / timeout
- abort if a server ignores Range and attempts to send the full file
- probe failure means metadata is currently unavailable, not a durable terminal failure
- do not probe in parallel with an already-running full download unless a later product requirement justifies it

A complete local file remains the strongest metadata source.

The shared Core now provides a bounded best-effort artwork probe used by Android E6 when media is added to the Listening List. MP3/ID3 starts with a 256 KiB prefix and may fetch only the remainder of the declared ID3 tag up to an 8 MiB hard ceiling. MP4/M4A probes at most 1 MiB from the start and 1 MiB from the end and accepts artwork only when a complete `covr/data` payload is present in one sampled region. Range-ignoring large responses, timeouts, unsupported layouts, and decode failures are treated as metadata-unavailable rather than download/playback failures. A requested or completed full download suppresses probing because local file analysis remains authoritative.

---

## 15. Playback Preparation

The core returns a durable playback snapshot.

Conceptual response:

```text
PlaybackPreparation
  enclosure_id
  article_id
  source
  resume_position_ms
  playback_status
  duration_ms?
  chapters[]
  artwork?
```

Playback source:

```text
LocalFile(...)
RemoteUrl(...)
```

### Source selection

```text
valid local downloaded file
-> LocalFile

otherwise
-> RemoteUrl
```

The core decides the source. Native code should not reconstruct this policy independently.

A remote metadata probe must never block `prepare_playback()`.

---

## 16. Native Playback Runtime

Native code owns:

- play
- pause
- seek
- ±30 second skipping
- playback speed
- buffering
- audio interruption handling
- audio routing
- sleep timer
- active playback queue
- current player item
- runtime playback state

Pause, stop, and seek only need to trigger a core checkpoint when appropriate.

Per client, Flux should behave as if there is at most one active media playback session. This is native player-coordinator policy, not a core-enforced invariant.

---

## 17. Cleanup and Download Retention

Core model:

```text
DownloadRetention
  Forever
  Days(u32)
```

Download retention is based on:

```text
downloaded_at
```

not the article publication date.

Automatic cleanup transitions:

```text
Downloaded
-> DeleteRequested
-> native physical deletion
-> NotDownloaded
```

The core decides the desired cleanup state. Native code deletes the actual file.

`delete_after_playback` is a separate policy.

`playback_completed()` may atomically transition an existing download to `DeleteRequested` when that policy is enabled.

Automatic cleanup does not create auto-download suppression.

---

## 18. Article Retention Protection

Media state protects an article when durable unfinished media work depends on it.

### Protecting states

```text
SavedMedia
MediaDownload = Requested
MediaDownload = Downloaded
PlaybackState = InProgress
pending MediaProgressMutation
```

### Non-protecting states

```text
MediaDownload = Failed
MediaDownload = DeleteRequested
PlaybackState = Completed only
AutoDownloadSuppression
```

A starred article follows existing article-retention rules, but starring an article does not indefinitely pin a large local media file.

---

## 19. Automotive and System Media Integration

Automotive is not a separate domain.

Do not introduce:

```text
CarPlayEpisode
AndroidAutoEpisode
AutomotiveMetadataCache
```

The core provides domain read models such as:

```text
downloaded_playable_media()
continue_listening()
media_by_feed(...)
prepare_playback(...)
```

Native code builds:

- CarPlay
- Android Auto
- Now Playing
- lock screen controls
- MediaSession
- system playback notification

Automotive V1 must at minimum support reliable playback and browsing of downloaded audio content.

Remote automotive streaming is not a mandatory V1 requirement.

---

## 20. Continue Listening

Expose a domain query conceptually similar to:

```text
continue_listening()
```

Candidates:

```text
PlaybackStatus == InProgress
```

Default sorting:

```text
updated_at descending
```

`Completed` and `NotStarted` do not belong in Continue Listening.

---

## 21. Queue and Next / Previous

The core does not persist an active playback queue.

Native code owns:

```text
current queue
current item
current index
```

The core provides deterministic media read models.

Default downloaded-media ordering:

```text
published_at descending
```

Different queue contexts may be introduced later without changing the durable media domain.

---

## 22. Optional Mark-Read-on-Completion

If the product supports marking an article read after media completion, model it as core policy:

```text
mark_article_read_on_completion
```

When enabled, `playback_completed()` may atomically create the normal article-read mutation in addition to updating media state.

Native playback code must never call Miniflux directly.

---

## 23. Persistence Structure

Conceptual structure:

```text
articles
   └── enclosures
        ├── saved_media
        ├── playback_states
        ├── media_downloads
        ├── media_metadata
        │    └── media_chapters
        └── media_auto_download_suppressions
```

Reuse the existing:

```text
pending_mutations
```

infrastructure for `MediaProgressMutation`.

Do not create shared-core tables for:

- a giant `PodcastEpisode` model
- legacy-style `AudioProgressStore`
- native download queue runtime state
- CarPlay / Android Auto caches
- OS transfer task IDs

---

## 24. Sync Integration

Do not introduce a separate media sync.

Keep the existing Phase A sync order:

```text
1. send pending mutations
2. acknowledge successful mutations
3. fetch remote data
4. reconcile
5. retention / cleanup
6. update sync state / events
```

Media extends these phases.

Media-protected articles become part of the existing explicit special remote-fetch set.

---

## 25. Auto-Download Discovery Semantics

Reconciliation must distinguish live discovery from restoration/rebuild.

Conceptually:

```text
LiveDiscovery
RestoreOrRebuild
```

Only live discovery may create auto-download candidates.

Do not leak the generic `SyncReason` deeply into media domain logic when a narrower domain concept is sufficient.

---

## 26. Search Integration

Search remains remote.

When the user downloads a remote search result, atomically persist:

```text
Article
+ target Enclosure
+ Requested MediaDownload
```

If a non-persisted search result is actually played, materialize `Article + Enclosure` before creating the first durable playback state.

Never create synthetic enclosure identities for search results.

---

## 27. Required Atomic Core Operations

At minimum, keep the following operations transactionally atomic.

### Search → Download

```text
Article
+ Enclosure
+ Requested
```

### Playback checkpoint

```text
PlaybackState
+ coalesced MediaProgressMutation
```

when remote progress sync is supported.

### Playback completion

```text
Completed PlaybackState
+ MediaProgressMutation
+ optional DeleteRequested
+ optional article-read mutation
```

### Playback restart

```text
InProgress at position 0
+ MediaProgressMutation(0)
```

Remote delivery remains separate and offline-first after the local transaction succeeds.

---

## 28. Legacy FluxNews Migration

The Flutter FluxNews implementation is a behavioral/capability reference, not a technical migration template.

Do not carry forward:

- article-keyed `AudioProgressStore`
- SecureStorage for ordinary media metadata
- direct Miniflux calls from the player
- Dart `HttpClient` as the long-running download engine
- synthetic negative attachment IDs
- separate automotive metadata caches

A later one-time migration may convert legacy data into the new model.

For legacy article-keyed playback progress:

- exactly one resolvable audio enclosure → migration may map it
- multiple possible audio enclosures → do not guess

Legacy migration must adapt to the new model. It must never deform the new model.

---

## 29. Schema Migration

Continue using sequential schema migrations.

Illustrative only:

```text
v8  enclosures
v9  playback
v10 downloads
v11 metadata
```

The exact migration numbers are an implementation detail.

Every migration must be:

- deterministic
- forward-only
- independently testable
- safe for existing Phase A data

---

## 30. Required Test Coverage

### Enclosures

- single and multiple enclosures
- MIME classification
- size normalization
- remote progression mapping
- changed enclosure
- remotely removed but locally retained enclosure

### Saved media / episode library

- save and unsave
- saved without download
- downloaded without saved state
- deleting a download does not unsave
- playback completion does not unsave
- saved state protects enclosure/article retention
- feed-scoped deterministic ordering
- SavedMedia works fully with synchronization disabled
- automatic setup requires explicit approval
- automatic setup reuses an existing canonical sync feed
- manual setup discovers and verifies a user-created canonical sync feed
- setup path does not change later replication semantics
- missing configured sync feed returns to setup-required state
- bootstrap XML contains no user data and is not required after setup
- Saved Media replication does not use article starring or media progression

### Playback reconciliation

- forward progress
- backward seek
- restart to 0
- completion
- no local state → adopt remote
- unchanged remote → keep local
- pending local → local wins
- changed remote without pending → remote wins
- stale remote read after successful local PUT
- Miniflux < 2.2.0

### Download state machine

- every valid transition
- invalid transitions
- retry
- cancellation
- deletion
- missing files
- recovery combinations

### Auto-download

- new audio enclosure + enabled feed
- disabled feed
- non-audio enclosure
- initial sync / rebuild
- enabling without backfill
- suppression
- explicit manual request clears suppression
- automatic cleanup does not create suppression

### Retention

- `Requested` protects
- `Downloaded` protects
- `InProgress` protects
- `Failed` does not protect
- `DeleteRequested` does not protect
- `Completed` alone does not protect
- download retention uses `downloaded_at`

### Database migration

- fresh database → latest schema
- current Phase A database → latest schema
- existing articles/feed/category data remains intact
- foreign-key semantics

New Phase B functionality must not be differentially mirrored against the deprecated Go core. The Go core does not define this new media architecture.

---

# Phase B Implementation Roadmap

## B1 — Enclosure Domain & Persistence

Implement:

- `Enclosure` domain model
- `MediaKind`
- full Miniflux enclosure mapping
- SQLite persistence
- Article ↔ Enclosure relationship
- multiple enclosures per article
- remote-presence / remote-removal semantics

Do not implement playback or downloads yet.

**Exit condition:** Enclosures are complete durable core-domain entities.

---

## B2 — Saved Media / Episode Library

Implement:

- `SavedMedia`
- `save_media`
- `unsave_media`
- `saved_playable_media`
- feed-scoped saved-media query/read model
- retention protection for saved enclosures/articles
- episode-library read model including playback/download projections
- deterministic ordering suitable for native next/previous queue construction

Keep the local episode library independent of synchronization.

Also implement the optional, explicitly enabled Miniflux Saved Media replication adapter:

- canonical repository-hosted bootstrap `init.xml`
- capability gating for supported Miniflux versions
- automatic setup after explicit approval
- manual setup with user-created feed
- canonical `feed_url` discovery and verification
- reuse of an existing sync feed across devices
- disabled technical feed after bootstrap
- durable `sync_feed_id`
- versioned Saved Media marker identity
- save/unsave marker semantics
- failure isolation so local SavedMedia remains usable

Do not couple Saved Media to article starring or media progression, and do not introduce a Flux-hosted user-data sync service.

**Exit condition:** Flux has a durable local episode library independent of downloads, native clients can use it as the basis for episode browsing and temporary feed-scoped playback queues, and supported Miniflux accounts can optionally replicate Saved Media through a user-approved technical sync feed.

---

## B3 — Playback State & Miniflux Progress

Implement:

- `PlaybackState`
- `checkpoint_playback`
- `restart_playback`
- `playback_completed`
- `observe_media_duration`
- `MediaProgressMutation`
- per-enclosure last-value coalescing
- Miniflux progression PUT
- `MediaProgressSync` capability
- local/remote progress reconciliation

**Exit condition:** Playback progress works offline-first locally and synchronizes across devices when supported by Miniflux.

---

## B4 — Download Domain State Machine

Implement:

- `MediaDownload`
- `DownloadOrigin`
- `request_download`
- `cancel_download`
- `retry_download`
- `delete_download`
- `download_finished`
- `download_failed`
- delete confirmation
- Search → durable download materialization

Do not implement real OS transfers yet.

**Exit condition:** The complete durable download lifecycle is testable entirely inside the core.

---

## B5 — Auto-Download & Cleanup Policies

Implement:

- feed-level `auto_download_audio`
- `AutoDownloadSuppression`
- `DownloadNetworkPolicy`
- `DownloadRetention`
- `delete_after_playback`
- media-related article protection
- `evaluate_media_cleanup`

**Exit condition:** Media download/cleanup policy is centralized in the shared core.

---

## B6 — Media Metadata

Implement:

- duration
- chapters
- embedded artwork
- article timestamp chapters
- artwork priority
- complete local-file metadata analysis

Then, as an optional sub-step:

- bounded remote HTTP Range metadata probing

Remote probing is not a blocker for the rest of Phase B.

**Exit condition:** The core can determine durable podcast/media metadata independently of platform UI/player implementations.

---

## B7 — UniFFI Media API

Expose the stable core domain API required by native clients, including:

- playback preparation
- playback checkpoints
- completion / restart
- download commands
- playback/download read models
- `downloaded_playable_media`
- `continue_listening`
- required media settings/policies

Do not redesign the architecture at this stage.

**Exit condition:** Native clients have a small domain-oriented interface with low round-trip overhead.

---

## B8 — Native Playback & Transfers

### Apple

Implement:

- AVFoundation playback
- audio session
- background `URLSession`
- native transfer registry
- file coordination
- Now Playing integration

### Android

Implement:

- Media3
- MediaSession
- `MediaTransferCoordinator`
- appropriate system transfer backend(s)
- audio focus
- notifications

Both platforms must consume the same core contract even when their OS mechanisms differ.

**Exit condition:** Native playback and long-running transfers operate through the shared media core.

---

## B9 — Automotive & Legacy Migration

Implement:

- CarPlay
- Android Auto
- downloaded-media browsing
- Continue Listening
- system-media polish
- optional one-time Flutter legacy import

**Exit condition:** Native system/automotive integration uses the shared core without duplicate media caches or legacy-domain leakage.

---

# Frozen Phase B Decisions

The following topics are considered decided for Phase B and must not be routinely reopened by coding agents:

- enclosure identity and domain model
- media-kind classification
- `SavedMedia` as the durable local episode-library layer
- `SavedMedia` independent from download, playback, and article-starred state
- `SavedMedia` is local-first and fully functional without synchronization
- optional Saved Media Sync replicates through a dedicated Miniflux technical feed
- Saved Media Sync is disabled by default and requires explicit user approval
- the technical feed is identified by the canonical repository-hosted bootstrap `feed_url`
- automatic and manual setup are equivalent setup paths
- automatic setup must reuse an existing canonical sync feed before creating one
- manual setup must not silently modify the user's feed
- the technical feed is disabled after bootstrap and later replication uses imported marker entries
- the bootstrap XML contains no user data and is not a Flux-hosted user-data sync service
- Saved Media marker identity is enclosure-specific, deterministic, and versioned
- Saved Media Sync must not use article starring or media progression
- saved-media retention protection
- saved-media/feed queries as the basis for temporary native next/previous queues
- local playback persistence
- local/remote playback reconciliation
- no `max(local, remote)`
- completion semantics
- restart semantics
- checkpoint approach
- media-progress mutation and coalescing
- download state machine
- download origin
- feed-based auto-download policy
- auto-download suppression
- network policy
- download retention
- delete-after-playback
- media-related article protection
- metadata ownership and priority rules
- optional/lazy remote Range probing
- native/core playback boundary
- native/core transfer boundary
- no persistent core playback queue
- automotive as native presentation
- no automotive metadata caches
- no separate media sync
- reuse of existing Phase A mutation/sync architecture
- no legacy architecture in the new schema

A coding agent may escalate one of these decisions only when it discovers a concrete technical contradiction.

Required escalation format:

```text
Contract requires X.
Existing API/implementation guarantees Y.
X and Y conflict because Z.
```

A general re-analysis or speculative redesign of Phase B is not an acceptable implementation task.

---

# Intentionally Open Implementation Details

The following remain implementation details and are not architecture blockers:

- exact Android transfer backend by OS version and download origin
- concrete Rust crates for media metadata parsing
- exact SQLite migration numbers
- final UniFFI type names
- physical media directory layout
- exact byte/request/time limits for remote metadata probes
- details of the one-time Flutter legacy migration

These may be decided pragmatically within the relevant roadmap step while preserving this contract.

---

# Implementation Rule

Phase B architecture is considered complete.

> Do not perform another full media architecture analysis before implementation.

Implementation starts with **B1 — Enclosure Domain & Persistence** and proceeds through B9.

New architectural decisions should only be introduced when implementation reveals a concrete previously unknown platform, API, persistence, or compatibility constraint that conflicts with this contract.
