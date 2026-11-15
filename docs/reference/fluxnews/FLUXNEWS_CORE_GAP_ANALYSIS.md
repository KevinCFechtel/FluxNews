> **Status: historical feature-inventory evidence.** Phase A — Newsreader Completion is complete and architecture-frozen; this document is not an open Flutter parity checklist or implementation roadmap. Use it only as behavioral reference evidence, especially for future Podcast/Media work. If it conflicts with `docs/ARCHITECTURE_DECISIONS.md`, the architecture decisions win.

# FluxNews to Rust Core GAP Analysis

## Scope and source revisions

This document is a read-only source analysis. It does not implement a FluxNews
feature, change either database, design a final Flutter-to-native migration, or
select a binding technology.

Sources inspected:

- FluxBar commit `3d81812` (`Implement Rust Release`), including
  `rust-core/src/**`, Rust tests, build/binding scripts, and the core
  compatibility/migration documents.
- FluxNews commit `8f8161787d99b6bedb3d17404bb370b53c869aae`
  (`Update localization and dependencies`), cloned from
  <https://github.com/KevinCFechtel/FluxNews>.

References beginning with `rust-core/` or `docs/` are in FluxBar. References
beginning with `FluxNews/` are paths in the inspected FluxNews revision.

The classifications used below are:

- Ownership: `RUST_CORE`, `NATIVE_IOS`, `NATIVE_ANDROID`, `NATIVE_BOTH`,
  `SHARED_BUT_NOT_CORE`, `UI_ONLY`, or `UNCLEAR`.
- Rust coverage: `FULL`, `PARTIAL`, `MISSING`, or `NOT_APPLICABLE`.
- Native readiness: `READY`, `CORE_EXTENSION_REQUIRED`,
  `NATIVE_IMPLEMENTATION_REQUIRED`, or `BOTH_REQUIRED`.

## Executive summary

The current Rust core is a strong reusable foundation for Miniflux transport,
account-scoped local state, optimistic mutations, complete-selection
reconciliation, and deterministic article/icon processing. It is not yet a
FluxNews core.

FluxNews is a materially broader mobile product than FluxBar. Its source
implements a local full-article repository, configurable synchronization and
retention, server-side search, curated subscription onboarding, per-feed
presentation overrides, home-screen widgets, background synchronization,
settings backup/restore, podcast downloads/playback/chapters, playback-position
synchronization, Android Auto, and CarPlay. Those are demonstrated in code; new
article notifications and general feed/category management are not.

The principal blocker is the data contract. FluxNews uses a single-account,
version-12 SQLite database containing full HTML and enclosures. The Rust core
uses an unversioned, account-scoped FluxBar schema containing preview rows,
selection totals, pending mutations, and Undo metadata. FluxBar's 200-entry
presentation snapshot is not equivalent to FluxNews' offline article
repository. FluxBar's Go/Rust SQLite interoperability does not solve this
independent migration problem.

No end-to-end FluxNews responsibility is a strict `FULL` match. The narrow
read/unread desired-state persistence algorithm is a strong reusable basis: it
supports multiple local desired-state changes, immediate local visibility,
durable retry, revision-safe acknowledgement, and automatic-read Undo. It is
currently coupled to the FluxBar schema and flush scheduling, remote delivery
is per row, and mobile schema/query/API integration does not exist. Most
apparent matches are partial
because the data retained,
pagination/sync scope, endpoint contract, cache policy, or presentation
semantics differ.

A viable native FluxNews client therefore needs these foundations before UI
parity work:

1. mobile build/runtime validation using the existing ABI before choosing a
   future typed adapter;
2. a deliberate FluxNews-capable data model;
3. characterized import/preservation of existing FluxNews data;
4. a mobile offline sync/query profile rather than the FluxBar popover profile;
5. native ownership of credentials, scheduling, audio sessions, widgets, and
   platform lifecycle.

## FluxNews architecture audit

### Application composition

FluxNews is a Flutter application for Android and iOS. `main()` initializes
logging, WorkManager, audio services, CarPlay, and iOS visual integration before
installing three `ChangeNotifierProvider`s and the route graph
(`FluxNews/lib/main.dart:41-123`, `FluxNews/lib/main.dart:236-257`,
`FluxNews/lib/main.dart:402-438`).

`FluxNewsState` is the central mutable application object. It owns credentials,
preferences, current selection/sort/filter state, SQLite initialization,
Miniflux configuration, feed-icon storage, background-sync settings, and audio
download settings (`FluxNews/lib/state_management/flux_news_state.dart:31-38`,
`FluxNews/lib/state_management/flux_news_state.dart:408-585`). Domain, storage,
network, platform, and presentation concerns are
therefore coupled rather than separated into strict layers.

Startup reads secure configuration with retries, migrates Keychain
accessibility, opens SQLite, applies settings, optionally synchronizes, or loads
the cached database, and then processes pending widget actions
(`FluxNews/lib/ui/flux_news_body.dart:208-484`).

### Persistence

The current database is `news_database.db`, schema version 12
(`FluxNews/lib/database/database_schema.dart:3-28`). It is stored under the iOS
Library directory or Android database directory
(`FluxNews/lib/state_management/flux_news_state.dart:587-610`). It is not
account-scoped.

The four durable tables are created at
`FluxNews/lib/state_management/flux_news_state.dart:613-668`:

| Table | Durable responsibility |
| --- | --- |
| `news` | Entry identity, full HTML, URLs, hash, timestamps, derived preview/image, read/star state, reading time, feed title, and `syncStatus`. |
| `categories` | Category identity and title. |
| `feeds` | Feed metadata plus local-only presentation overrides. |
| `attachments` | Enclosure identity, article relationship, URL, MIME type, and media progression. |

> **Current Flux status (2026-09-20):** the Rust Core now consumes Miniflux `reading_time`, persists it as `articles.reading_time_minutes` (schema v18), includes it in `ArticleSummary`, and exports it through UniFFI. The original gap for reading-time metadata is therefore closed; platform clients should consume the projected value rather than estimate it independently.

The migration implementation branches on exact `oldVersion` values with
`else if`, rather than visibly applying every intervening migration
(`FluxNews/lib/state_management/flux_news_state.dart:672-1699`). Whether every
historical installed schema safely reaches version 12 is an unresolved
characterization requirement, not an assumption this analysis makes.

### Domain and article model

`News` combines Miniflux entry fields, cached article content, effective state,
feed presentation settings, and enclosures
(`FluxNews/lib/models/news_model.dart:22-188`). It stores full HTML and derives a
cached preview of up to 2,000 characters. Preview extraction can prefer a
qualifying paragraph, while image selection can prefer either HTML images or
image enclosures per feed (`FluxNews/lib/models/news_model.dart:250-331`,
`FluxNews/lib/models/news_model.dart:507-620`). Expanded article content is converted to Markdown in Flutter UI
code (`FluxNews/lib/models/news_model.dart:337-428`).

`Attachment` is an actual persisted enclosure model and includes
`mediaProgression` (`FluxNews/lib/models/news_model.dart:1280-1325`). Audio
enclosures are discovered from this model (`FluxNews/lib/models/news_model.dart:465-491`).

### Miniflux and synchronization

Production synchronization is staged:

```text
manual/background trigger
        |
        v
cross-isolate file lease
        |
        v
push deferred locally-read rows
        |
        v
stage main entry pages
        |
        v
fetch categories/feeds/icons
        |
        v
stage starred entry pages
        |
        v
reconcile categories/feeds
        |
        v
transactional entry/star reconciliation
        |
        v
retention, audio progression, widgets
```

Evidence: `FluxNews/lib/functions/sync_news.dart:17-347`,
`FluxNews/lib/functions/sync_pipeline.dart:67-178`, and
`FluxNews/lib/functions/sync_pipeline.dart:243-284`.

Entry fetches use `order=published_at`, configurable direction, 1,000-entry
offset pages, optional unread/all/date-window scope, and an optional total cap
(`FluxNews/lib/miniflux/miniflux_backend.dart:48-155`). A capped result is marked
incomplete and does not authorize absence cleanup. The main and starred sets are
fetched separately.

The temporary staging table deduplicates entry IDs and holds main/starred JSON
payloads (`FluxNews/lib/database/database_backend.dart:20-70`). Category/feed
reconciliation occurs before the transaction that reconciles entries and star
state (`FluxNews/lib/functions/sync_pipeline.dart:249-263`).

### Mutations and offline behavior

Read/unread actions update SQLite and visible state first, then optionally issue
an unawaited immediate Miniflux request
(`FluxNews/lib/functions/news_widget_functions.dart:481-623`). Opening an
article follows the same local-read-first path before native URL launch
(`FluxNews/lib/functions/news_widget_functions.dart:626-707`).

Deferred synchronization only sends rows where `status=read` and
`syncStatus=notSynced`, in chunks of 500
(`FluxNews/lib/miniflux/miniflux_backend.dart:630-702`). The ordinary local
status update does not itself update `syncStatus`, and there is no symmetric
durable unread queue. This is current FluxNews behavior, not a desired future
contract.

Bookmark actions optimistically flip the in-memory value, call
`PUT entries/{id}/bookmark`, and also update SQLite, but have no durable outbox
(`FluxNews/lib/functions/news_widget_functions.dart:293-367`,
`FluxNews/lib/miniflux/miniflux_backend.dart:811-864`).

### Platform and UI responsibilities

Actual platform responsibilities include:

- WorkManager/BGTask registration and foreground/background exclusion
  (`FluxNews/lib/functions/background_sync_service.dart:64-181`,
  `FluxNews/lib/functions/background_sync_service.dart:184-349`).
- Android Custom Tabs/intents and iOS URL launching
  (`FluxNews/android/app/src/main/kotlin/de/circle_dev/flux_news/MainActivity.kt:45-175`,
  `FluxNews/lib/functions/news_widget_functions.dart:690-705`).
- Android RemoteViews and iOS WidgetKit/App Intents
  (`FluxNews/android/app/src/main/kotlin/de/circle_dev/flux_news/FluxNewsWidgetProvider.kt`,
  `FluxNews/ios/FluxNewsWidgets/FluxNewsWidgets.swift`).
- Native audio session, media notification/Now Playing, Android Auto, and
  CarPlay integration (`FluxNews/lib/functions/flux_news_audio_handler.dart`,
  `FluxNews/lib/functions/flux_news_carplay_service.dart`).
- Native secure storage and Keychain accessibility
  (`FluxNews/lib/state_management/flux_news_state.dart:23-38`,
  `FluxNews/lib/state_management/flux_news_state.dart:1722-1962`).

No source implementation was found for new-article push/local notifications.
Android notification permissions and iOS `remote-notification` declarations do
not establish such a feature. ActivityKit/Dynamic Island source exists, but it
is not demonstrated as a complete packaged feature: the widget source is not in
the widget target and its controls do not route back to Dart.

## Current Rust capability map

| Capability | Public operation/API | Persistent state | Remote state | Platform assumptions | Reuse assessment |
| --- | --- | --- | --- | --- | --- |
| C ABI and JSON transport | `FluxCoreRequest`, `FluxCoreFree`; 11 operation names | None | None | Synchronous C strings; caller frees responses | ABI can remain for FluxBar, but the flat FluxBar envelope is too narrow for FluxNews. `rust-core/src/ffi.rs:27-131`; `rust-core/src/transport/request.rs:162-396`. |
| Configuration/runtime | `configure` | Account row and process runtime registry | No request during configure | Production DB path is macOS-specific; credentials are process memory | Validation is reusable. Credential-derived account identity needs a key-rotation/product decision; DB path and localization/config-generation behavior are FluxBar host policy. `rust-core/src/runtime.rs:62-152`, `rust-core/src/runtime.rs:391-439`. |
| Domain selections | `all`, `unread`, `starred`, `category`, `feed`; `unreadOnly` | Selection totals | Miniflux selection filters | None | Predicate vocabulary is reusable, but FluxNews queries are not limited presentation snapshots. `rust-core/src/domain/selection.rs:6-80`. |
| Account identity | Internal SHA-256 server/API-key derivation | Account-scoped primary keys | Identifies Miniflux credential pair | None | Implementation is reusable only if mobile identity deliberately accepts API-key rotation creating a new account ID. `rust-core/src/domain/account.rs:1-16`. |
| SQLite store | Via configure/snapshot/sync/mutations | Accounts, categories, feeds, selection totals, preview entries, pending mutations, Undo | Stores observed remote baselines | Bundled SQLite; production path macOS-only | Transactions, account scoping, and pending revision mechanics are reusable; schema is not a FluxNews schema. `rust-core/src/persistence/schema.rs:7-79`. |
| Local snapshot | `local_snapshot` | Reads all core tables | None | Synchronous DB; 5-second deadline | Local-first behavior is reusable. Snapshot v1, retained IDs, and 200-entry cap are FluxBar-specific. `rust-core/src/persistence/store.rs:635-873`. |
| Miniflux client | Internal `MinifluxClient` | None | Entries, entry, categories, feeds, counters, feed icon, read status, star toggle | Blocking `ureq`, native TLS, fixed headers | HTTP/error/DTO pieces are reusable. Custom headers, mobile TLS validation, search, capability discovery, feed creation, save, and progression are absent. `rust-core/src/remote/miniflux.rs:115-363`. |
| Refresh/reconciliation | `refresh` | Applies one complete selected set and totals | Strict ascending-ID cursor pagination | Per-account serial gate; synchronous calls | Complete-set verification and pending-state preservation are reusable. Sync scope and retained data are FluxBar-specific. `rust-core/src/sync.rs:241-247`, `rust-core/src/sync.rs:521-583`. |
| Read mutation | `set_read`, `flush_pending`, `undo_read`, `discard_undo` | Effective/remote status, desired revision, Undo batch | Pending rows are delivered individually | Delayed worker thread for automatic reads | Desired-state persistence/revision semantics are reusable; FluxNews bulk delivery and mobile API/schema integration are not implemented. `rust-core/src/sync.rs:283-370`, `rust-core/src/sync.rs:398-433`. |
| Star mutation | `set_starred`, `flush_pending` | Effective/remote star, desired revision | Reads entry then toggles `/star` | Same sync gate | Desired-state/revision logic is reusable, but FluxNews uses `/bookmark`; endpoint equivalence must be characterized. `rust-core/src/remote/miniflux.rs:355-361`. |
| Article processing | Internal mapping; no public article operation | Stores 600-code-point preview/image URL | Miniflux content/enclosures | HTML/image work is synchronous | Parsing/URL primitives are reusable. Output rules differ from FluxNews and full HTML is discarded. `rust-core/src/article.rs:13-273`; `rust-core/src/remote/mod.rs:27-73`. |
| Feed icons | `feed_icon` | Process-memory cache only | `/v1/feeds/{feedID}/icon` | Raster/SVG processing; 15-second deadline | Decode/raster/single-flight primitives are reusable. FluxNews uses icon IDs, MIME/raw bytes, files, widgets, and per-feed policies. `rust-core/src/icons.rs:17-609`. |
| Localization | `localize`, `localize_plural` | Embedded FluxBar English/German catalog | None | Caller supplies locale list | FluxBar compatibility only. Native FluxNews UI should use native catalogs and typed core errors. `rust-core/src/localization.rs:15-87`. |
| Concurrency | Internal service registry, shared store, sync gate, icon single-flight | Shared SQLite connection | Serializes refresh/flush only | Threads, mutexes, condvars; no async runtime | State-scoped locking is reusable. OS scheduling and cross-process coordination remain native/mobile integration work. `rust-core/src/sync.rs:24-202`; `rust-core/src/runtime.rs:109-150`. |

Current known Rust limitations relevant to reuse include macOS-only production
path discovery, synchronous SQLite/image calls that cannot be interrupted
mid-call, no cross-process differential concurrency harness, English/German
primary-subtag localization only, memory-only icon cache, and no explicit
secondary ordering for equal publication timestamps. See
`docs/RUST_CORE_TESTING.md:232-256` and
`docs/CORE_COMPATIBILITY_CONTRACT.md:1053-1096`.

## FluxNews responsibility inventory

| Responsibility | Evidence and current location | Persistent state | Remote dependency | Platform dependency | User-visible behavior |
| --- | --- | --- | --- | --- | --- |
| Single Miniflux configuration, credentials, custom headers, version | `FluxNews/lib/state_management/flux_news_state.dart:79-195`, `FluxNews/lib/state_management/flux_news_state.dart:1722-1962`; `FluxNews/lib/miniflux/miniflux_backend.dart:1516-1615` | Secure storage | `/me`, `/version` | Keychain/Android secure storage | Login, validation, custom proxy/auth headers |
| Local full-article repository | `FluxNews/lib/models/news_model.dart:22-188`; `FluxNews/lib/database/database_backend.dart:1181-1453` | Full HTML and metadata in `news` | Rebuildable only while Miniflux retains entries | SQLite/filesystem | Cached lists and inline offline content |
| Categories, feeds, counts, local feed settings | `FluxNews/lib/models/news_model.dart:853-1278`; `FluxNews/lib/database/database_backend.dart:2098-2469` | `categories`, `feeds`, secure feed overrides | Categories/feeds/counters/icons | SQLite/filesystem | Navigation and per-feed display behavior |
| Main/starred staged synchronization | `FluxNews/lib/functions/sync_pipeline.dart:67-178`, `FluxNews/lib/functions/sync_pipeline.dart:243-284`; `FluxNews/lib/database/database_backend.dart:20-319` | Temporary staging plus all durable tables | Entries/categories/feeds/icons | SQLite and sync lease | Refresh without applying incomplete snapshots |
| Configurable sync scope/cap/date window | `FluxNews/lib/miniflux/miniflux_backend.dart:69-155`; `FluxNews/lib/ui/settings/sync_settings.dart:53-317` | Secure preferences | Entries pagination | None beyond host network | Unread-only or read history, capped/all sync |
| Read/unread actions | `FluxNews/lib/functions/news_widget_functions.dart:481-623`; `FluxNews/lib/miniflux/miniflux_backend.dart:630-809` | Status and `syncStatus` | Bulk entry status PUT | Gesture/list/widget triggers | Immediate local state and optional remote push |
| Mark all/current scope read | `FluxNews/lib/database/database_backend.dart:1849-1924`; `FluxNews/lib/functions/news_widget_functions.dart:753-808` | Many local statuses | Optional bulk status PUT | UI confirmation/action | Clears all/bookmarks/category/feed scope |
| Mark read on scroll | `FluxNews/lib/ui/news_list.dart:245-447`; `FluxNews/lib/ui/read_on_scroll_controller.dart:16-143` | Read state | Optional status PUT | Flutter visibility/scroll events | Marks crossed rows after scroll ends |
| Bookmark/unbookmark | `FluxNews/lib/functions/news_widget_functions.dart:293-367`; `FluxNews/lib/miniflux/miniflux_backend.dart:811-864` | Starred flag; no outbox | `/entries/{id}/bookmark` | UI actions | Optimistic bookmark state |
| Remote search | `FluxNews/lib/ui/search.dart:165-196`; `FluxNews/lib/miniflux/miniflux_backend.dart:435-628` | Result limit; results transient | Entries `search` query | Search UI | Server-side article results |
| Curated subscription onboarding | `FluxNews/lib/ui/feed_onboarding.dart:245-331`; `FluxNews/lib/miniflux/miniflux_backend.dart:1202-1513` | Result later cached | Category/feed create, title update, refresh | Onboarding UI/assets | Creates selected suggested subscriptions |
| Third-party save action | `FluxNews/lib/functions/news_widget_functions.dart:369-397`; `FluxNews/lib/miniflux/miniflux_backend.dart:866-931` | None | `/entries/{id}/save` | Snackbar/action UI | Sends article to configured Miniflux integration |
| Article preview/image derivation | `FluxNews/lib/models/news_model.dart:250-331`, `FluxNews/lib/models/news_model.dart:507-620`; `FluxNews/lib/database/database_backend.dart:360-413` | Preview/image cache | Article image URLs | HTML parser, image cache | Preview text and row image |
| Network article-image cache | `FluxNews/lib/ui/news_row.dart:709-717`; `FluxNews/lib/ui/flux_news_body.dart:433-439`; `FluxNews/lib/state_management/flux_news_state.dart:174-177` | Configurable-age disposable image files | Article image hosts | Native/application cache filesystem and image loader | Reuses downloaded row images across launches |
| Inline full-text/Markdown rendering | `FluxNews/lib/models/news_model.dart:337-428` | Full HTML and feed limits | Link/image destinations | Flutter Markdown and native URL launch | Expanded article content in list |
| Feed-icon cache/contrast | `FluxNews/lib/miniflux/miniflux_backend.dart:1064-1200`; `FluxNews/lib/state_management/flux_news_state.dart:3051-3104` | Icon files, feed settings | Miniflux icon endpoint | Filesystem/SVG/raster widgets | Feed logos in app and widgets |
| Retention/cache cleanup | `FluxNews/lib/database/database_backend.dart:647-728`, `FluxNews/lib/database/database_backend.dart:1988-2096` | Limits and downloaded-audio protection | Miniflux can rebuild some rows | SQLite/filesystem | Controls saved read/starred history |
| Audio enclosures and progression | `FluxNews/lib/models/news_model.dart:465-491`, `FluxNews/lib/models/news_model.dart:1280-1325`; `FluxNews/lib/functions/sync_news.dart:350-445` | Attachments, progression, local progress keys | Entry/enclosure progression endpoints | Shared preferences/secure migration | Resume across devices |
| Streaming and downloaded playback | `FluxNews/lib/functions/flux_news_audio_handler.dart:34-66`, `FluxNews/lib/functions/flux_news_audio_handler.dart:487-521`, `FluxNews/lib/functions/flux_news_audio_handler.dart:559-807`; `FluxNews/lib/ui/audioplayer.dart:202-940` | Current/last progress and downloads | Audio hosts | Native audio session/media controls | Play/pause/seek/speed/sleep timer |
| Audio download management/chapters/artwork | `FluxNews/lib/functions/audio_download_service.dart:130-274`, `FluxNews/lib/functions/audio_download_service.dart:977-1396`, `FluxNews/lib/functions/audio_download_service.dart:1546-1670` | Files, path/title/feed/timestamp/skip metadata | Audio/artwork hosts | Filesystem/connectivity/ID3 parser | Offline episodes, chapter navigation, cleanup |
| Android Auto and CarPlay | `FluxNews/lib/functions/flux_news_audio_handler.dart:809-1055`; `FluxNews/lib/functions/flux_news_carplay_service.dart:23-304` | Download metadata/progress | Optional progression sync | Native automotive/media APIs | Browse and play downloaded episodes |
| Background sync | `FluxNews/lib/functions/background_sync_service.dart:64-349`; `FluxNews/lib/functions/sync_lock.dart:7-148` | Settings, timestamps, lock file | Same sync operations | WorkManager/BGTaskScheduler | Opportunistic headless refresh |
| Home-screen widgets | `FluxNews/lib/functions/widget_service.dart:20-395`; `FluxNews/ios/FluxNewsWidgets/FluxNewsWidgets.swift`; `FluxNews/android/app/src/main/kotlin/de/circle_dev/flux_news/FluxNewsWidgetProvider.kt` | Widget settings and generated snapshots | Sync action only | WidgetKit/App Intents/RemoteViews | Counts, headlines, open/sync actions |
| Settings backup/restore | `FluxNews/lib/functions/settings_backup_service.dart:252-426`, `FluxNews/lib/functions/settings_backup_service.dart:428-581` | ZIP/JSON, optional Argon2id/AES-GCM, secure values | User export/Android backup service | File picker/share/Android backup | Export and restore credentials/settings |
| Destructive local-data reset | `FluxNews/lib/database/database_backend.dart:2519-2588`; `FluxNews/lib/ui/settings.dart:1092-1108` | Deletes/recreates repository, downloads, and icon cache | None | Stops audio, deletes files, clears in-memory UI projections | User-requested local reset without deleting Miniflux data |
| Theme, gestures, layout, navigation | `FluxNews/lib/main.dart:259-438`; `FluxNews/lib/ui/settings.dart:1-1175`; `FluxNews/lib/state_management/flux_news_state.dart:408-585` | Many secure UI preferences | None | Flutter/native platform styling | Adaptive Android/iOS UI |
| Localization | `FluxNews/lib/l10n/flux_news_localizations.dart:92-108`; `FluxNews/lib/main.dart:428-438`; `FluxNews/lib/functions/widget_service.dart:187-193` | Generated catalogs | None | Flutter and native widget strings | Seven implemented UI languages |
| Logging/diagnostics | `FluxNews/lib/functions/logging.dart:30-138`; `FluxNews/lib/ui/log_viewer.dart:105-267`; `FluxNews/lib/ui/settings.dart:566-636` | Log files and debug settings | User-controlled share | Filesystem/share sheet | Search, export, and clear logs |

No source evidence supports adding new-article notifications, multi-account
switching, OPML import/export, arbitrary feed/category administration, a
dedicated full-screen native reader, or desktop/web clients to this inventory.

## Ownership, coverage, and native readiness

| Responsibility | Future owner | Rust coverage | iOS readiness | Android readiness | Reason |
| --- | --- | --- | --- | --- | --- |
| Account identity and account-scoped data | `RUST_CORE` | `PARTIAL` | `CORE_EXTENSION_REQUIRED` | `CORE_EXTENSION_REQUIRED` | Rust scopes by a server/API-key hash, but FluxNews data is unscoped and API-key rotation changes the Rust identity. Product semantics require characterization. |
| Credentials and secret storage | `NATIVE_BOTH` | `NOT_APPLICABLE` | `NATIVE_IMPLEMENTATION_REQUIRED` | `NATIVE_IMPLEMENTATION_REQUIRED` | Keychain/Keystore and locked-device policy are OS responsibilities. |
| Basic per-entry/batch read and unread behavior | `RUST_CORE` | `PARTIAL` | `CORE_EXTENSION_REQUIRED` | `CORE_EXTENSION_REQUIRED` | Desired-state persistence is reusable, but FluxNews bulk remote delivery and mobile schema/API exposure are absent. |
| Star/bookmark desired state | `RUST_CORE` | `PARTIAL` | `CORE_EXTENSION_REQUIRED` | `CORE_EXTENSION_REQUIRED` | Revision logic is stronger, but `/star` versus `/bookmark` is uncharacterized. |
| Full article/enclosure persistence | `RUST_CORE` | `MISSING` | `CORE_EXTENSION_REQUIRED` | `CORE_EXTENSION_REQUIRED` | Rust discards full HTML/enclosures after deriving preview/image. |
| Main/starred mobile sync and retention | `RUST_CORE` | `PARTIAL` | `CORE_EXTENSION_REQUIRED` | `CORE_EXTENSION_REQUIRED` | Complete-selection primitives exist; scope, schema, and retention differ. |
| Local queries, scopes, counts, sorting | `RUST_CORE` | `PARTIAL` | `CORE_EXTENSION_REQUIRED` | `CORE_EXTENSION_REQUIRED` | Predicates overlap, but FluxBar snapshot v1 is capped and presentation-oriented. |
| Remote search | `RUST_CORE` | `MISSING` | `CORE_EXTENSION_REQUIRED` | `CORE_EXTENSION_REQUIRED` | No search filter or operation. |
| Subscription onboarding and third-party save | `RUST_CORE` | `MISSING` | `CORE_EXTENSION_REQUIRED` | `CORE_EXTENSION_REQUIRED` | Required Miniflux commands are absent. |
| FluxNews preview/image policy | `SHARED_BUT_NOT_CORE` | `PARTIAL` | `BOTH_REQUIRED` | `BOTH_REQUIRED` | Parser primitives overlap; policy/output differ and rendering remains UI. |
| Full-text/Markdown presentation | `UI_ONLY` | `NOT_APPLICABLE` | `NATIVE_IMPLEMENTATION_REQUIRED` | `NATIVE_IMPLEMENTATION_REQUIRED` | Rust should provide content, not platform text/layout/link behavior. |
| Network article-image cache | `NATIVE_BOTH` | `NOT_APPLICABLE` | `NATIVE_IMPLEMENTATION_REQUIRED` | `NATIVE_IMPLEMENTATION_REQUIRED` | Cache directory, age cleanup, image loading, and migration are platform/application storage concerns. |
| Feed-icon decoding | `SHARED_BUT_NOT_CORE` | `PARTIAL` | `BOTH_REQUIRED` | `BOTH_REQUIRED` | Decode primitives exist; mobile raw/cache/widget policy does not. |
| Enclosure progression reconciliation | `RUST_CORE` | `MISSING` | `BOTH_REQUIRED` | `BOTH_REQUIRED` | Portable conflict/delivery state plus native player timing are required. |
| Playback/audio session | `NATIVE_BOTH` | `NOT_APPLICABLE` | `NATIVE_IMPLEMENTATION_REQUIRED` | `NATIVE_IMPLEMENTATION_REQUIRED` | Audio session, focus, decoders, Now Playing, and routes are platform work. |
| Download queue/files | `NATIVE_BOTH` | `NOT_APPLICABLE` | `NATIVE_IMPLEMENTATION_REQUIRED` | `NATIVE_IMPLEMENTATION_REQUIRED` | Filesystem/background/network policy is platform work; core supplies metadata. |
| Core repository reset | `RUST_CORE` | `MISSING` | `CORE_EXTENSION_REQUIRED` | `CORE_EXTENSION_REQUIRED` | Rust must expose transactional deletion/reinitialization of core-owned durable state. |
| Local-reset orchestration | `NATIVE_BOTH` | `NOT_APPLICABLE` | `NATIVE_IMPLEMENTATION_REQUIRED` | `NATIVE_IMPLEMENTATION_REQUIRED` | Native hosts coordinate confirmation, playback stop, file/cache deletion, projections, and partial-failure UX around the core reset. |
| ID3 chapter/artwork parsing | `SHARED_BUT_NOT_CORE` | `MISSING` | `BOTH_REQUIRED` | `BOTH_REQUIRED` | Portable parser is shareable but not inbox/sync domain state. |
| Work scheduling | `NATIVE_BOTH` | `NOT_APPLICABLE` | `NATIVE_IMPLEMENTATION_REQUIRED` | `NATIVE_IMPLEMENTATION_REQUIRED` | Native code chooses when/how; Rust exposes the operation to execute. |
| Headless/cross-process core execution | `RUST_CORE` | `MISSING` | `BOTH_REQUIRED` | `BOTH_REQUIRED` | In-process gates are reusable primitives, but mobile process/path/DB coordination and headless initialization do not exist. |
| Widget query data | `RUST_CORE` | `MISSING` | `BOTH_REQUIRED` | `BOTH_REQUIRED` | The core has only a capped FluxBar snapshot, not FluxNews widget filters, limits, or DTOs. |
| Widget implementation | `NATIVE_BOTH` | `NOT_APPLICABLE` | `NATIVE_IMPLEMENTATION_REQUIRED` | `NATIVE_IMPLEMENTATION_REQUIRED` | WidgetKit and RemoteViews are OS contracts. |
| CarPlay/Android Auto | `NATIVE_BOTH` | `NOT_APPLICABLE` | `NATIVE_IMPLEMENTATION_REQUIRED` | `NATIVE_IMPLEMENTATION_REQUIRED` | Core supplies downloads/progress; native code supplies automotive browse/control. |
| Semantic settings/feed overrides | `SHARED_BUT_NOT_CORE` | `MISSING` | `BOTH_REQUIRED` | `BOTH_REQUIRED` | Stable DTO/rules can be shared; storage and UI stay native. |
| Backup format, crypto, validation, and restore mapping | `SHARED_BUT_NOT_CORE` | `MISSING` | `BOTH_REQUIRED` | `BOTH_REQUIRED` | FluxNews has portable ZIP/JSON, Argon2id, AES-GCM, version parsing, and restore semantics that require an explicit preservation or replacement decision. |
| Backup UI, secret access, files, and OS backup | `NATIVE_BOTH` | `NOT_APPLICABLE` | `NATIVE_IMPLEMENTATION_REQUIRED` | `NATIVE_IMPLEMENTATION_REQUIRED` | File access, secret retrieval, user prompts, and Android backup are platform/security policy. |
| UI localization | `UI_ONLY` | `NOT_APPLICABLE` | `NATIVE_IMPLEMENTATION_REQUIRED` | `NATIVE_IMPLEMENTATION_REQUIRED` | Native String Catalogs/resources should replace Flutter ARB UI use. |
| Typed domain errors | `RUST_CORE` | `PARTIAL` | `CORE_EXTENSION_REQUIRED` | `CORE_EXTENSION_REQUIRED` | Current errors are FluxBar-localized strings rather than native-localizable codes. |

## Core GAP matrix

| ID | FluxNews responsibility and evidence | Future owner | Current coverage | Gap description | Priority | Complexity | Dependencies | Suggested model |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `CORE-GAP-001` | Typed mobile host boundary; current Rust has a portable C/JSON ABI but only FluxBar operations (`rust-core/src/ffi.rs:27-131`, `rust-core/src/transport/request.rs:162-396`) | `RUST_CORE` | `PARTIAL` | Define mobile-safe typed operation categories, cancellation/error behavior, host-supplied paths/config, and Swift/Kotlin ownership without destabilizing FluxBar ABI. This is not a prerequisite for internal model work and does not preselect UniFFI. | P1 | `LARGE` | None | GPT-5.6 Sol |
| `CORE-GAP-002` | Mobile Rust artifacts/TLS/runtime validation; FluxNews supports iOS/Android, current production path is macOS-only (`rust-core/src/runtime.rs:391-439`) | `RUST_CORE` | `MISSING` | Produce and test iOS/Android library targets using the current ABI first, plus host path injection, TLS trust behavior, panic/thread behavior, and package integration. | P0 | `LARGE` | None | GPT-5.6 Terra |
| `CORE-GAP-003` | FluxNews full article/feed/enclosure state (`FluxNews/lib/state_management/flux_news_state.dart:613-668`) | `RUST_CORE` | `MISSING` | Add a deliberate mobile-capable domain/persistence model for full content, richer feed fields, enclosures, progression, retention metadata, and account scope. Do not silently mutate the FluxBar compatibility schema. | P0 | `VERY_LARGE` | None | GPT-5.6 Sol |
| `CORE-GAP-004` | Existing version-12 data and migrations (`FluxNews/lib/state_management/flux_news_state.dart:672-1699`) | `SHARED_BUT_NOT_CORE` | `MISSING` | Characterize every deployed schema, map must-preserve state, and choose import/replacement boundaries. FluxBar Go/Rust DB compatibility is irrelevant to this database. | P0 | `VERY_LARGE` | 003 | GPT-5.6 Sol |
| `CORE-GAP-005` | Staged main/starred sync with configurable scope/cap (`FluxNews/lib/miniflux/miniflux_backend.dart:48-155`; `FluxNews/lib/functions/sync_pipeline.dart:110-178`) | `RUST_CORE` | `PARTIAL` | Add a mobile offline sync profile, complete/incomplete set semantics, all/read-window modes, remote field refresh, attachment updates, feed/category deletion, and retention. Reuse strict completeness and pending-baseline protection. | P0 | `VERY_LARGE` | 003, 009 | GPT-5.6 Sol |
| `CORE-GAP-006` | Unbounded local lists, category/feed/bookmark scopes, counts, sort, mark-all (`FluxNews/lib/database/database_backend.dart:1181-1391`, `FluxNews/lib/database/database_backend.dart:1849-1924`) | `RUST_CORE` | `PARTIAL` | Add paginated/cursor local queries and scope mutations. Do not expose a 200-row FluxBar presentation snapshot as the mobile repository API. Define deterministic tie ordering. | P0 | `LARGE` | 003 | GPT-5.6 Terra |
| `CORE-GAP-007` | Read/unread/bookmark offline semantics (`FluxNews/lib/functions/news_widget_functions.dart:293-367`, `FluxNews/lib/functions/news_widget_functions.dart:481-623`) | `RUST_CORE` | `PARTIAL` | Integrate the existing read desired-state engine with the mobile schema/query API; characterize `/star` vs `/bookmark`; expose scope/batch receipts and bulk delivery; preserve durable unread and star retry semantics even though current FluxNews is weaker. | P0 | `LARGE` | 003, 005, 006 | GPT-5.6 Sol |
| `CORE-GAP-008` | Headless background operation and foreground exclusion (`FluxNews/lib/functions/background_sync_service.dart:184-349`; `FluxNews/lib/functions/sync_lock.dart:7-148`) | `RUST_CORE` | `MISSING` | Make core operations safe for host-scheduled headless launches and define cross-process SQLite/operation coordination. OS scheduling itself remains native. | P0 | `LARGE` | 002, 003, 005 | GPT-5.6 Sol |
| `CORE-GAP-009` | Custom headers, remote credential check, version/capabilities (`FluxNews/lib/miniflux/miniflux_backend.dart:62-68`, `FluxNews/lib/miniflux/miniflux_backend.dart:1516-1743`) | `RUST_CORE` | `MISSING` | Add general client configuration, `/me` and version discovery, capability gating, and custom-header policy. Required custom headers block reconnection for some existing accounts. Keep FluxBar's network-free `configure` contract unchanged. | P0 | `MEDIUM` | None | Kimi K2.7 Code |
| `CORE-GAP-010` | Server-side search (`FluxNews/lib/miniflux/miniflux_backend.dart:435-628`) | `RUST_CORE` | `MISSING` | Add encoded search query, pagination/cap/sort, transient result DTOs, and action-compatible entry identities. | P1 | `MEDIUM` | 009 | Kimi K2.7 Code |
| `CORE-GAP-011` | Curated onboarding, category/feed create/title update/refresh, third-party save (`FluxNews/lib/miniflux/miniflux_backend.dart:1202-1513`, `FluxNews/lib/miniflux/miniflux_backend.dart:866-931`) | `RUST_CORE` | `MISSING` | Add optional typed Miniflux commands and special outcomes. Do not add general feed administration that FluxNews source does not implement. | P1 | `LARGE` | 009 | Kimi K2.7 Code |
| `CORE-GAP-012` | FluxNews article preview/image/full-content policy (`FluxNews/lib/models/news_model.dart:250-428`, `FluxNews/lib/models/news_model.dart:507-620`) | `SHARED_BUT_NOT_CORE` | `PARTIAL` | Preserve reusable parser/URL primitives but add separate policy for 2,000-character preview, paragraph preference, attachment/image preference, and content output. Markdown rendering remains native. | P1 | `LARGE` | 003 | Kimi K2.7 Code |
| `CORE-GAP-013` | Icon ID/MIME/raw bytes, persistent cache, contrast overrides, widgets (`FluxNews/lib/functions/widget_service.dart:377-393`) | `SHARED_BUT_NOT_CORE` | `PARTIAL` | Separate decode/raster utilities from FluxBar's memory-only feed-ID 32x32 variants; define raw/icon-ID data and host cache contract. | P2 | `MEDIUM` | 003, 009 | Kimi K2.7 Code |
| `CORE-GAP-014` | Enclosure progression and downloaded-episode reconciliation (`FluxNews/lib/functions/sync_news.dart:350-445`; `FluxNews/lib/miniflux/miniflux_backend.dart:1618-1743`) | `RUST_CORE` | `MISSING` | Persist remote/local progression, explicit zero completion, conflict policy, capability gating, and retry/acknowledgement. Native players own save cadence and playback. Existing local progression is must-preserve migration state. | P0 | `VERY_LARGE` | 003, 007, 009 | GPT-5.6 Sol |
| `CORE-GAP-015` | Download catalog, retention, user-skipped intent, and article-deletion protection (`FluxNews/lib/functions/audio_download_service.dart:130-274`, `FluxNews/lib/functions/audio_download_service.dart:1546-1670`; `FluxNews/lib/database/database_backend.dart:647-728`, `FluxNews/lib/database/database_backend.dart:1988-2096`) | `SHARED_BUT_NOT_CORE` | `MISSING` | Define portable download metadata/state and its contract with core retention. Native services own files, network constraints, and queues. Existing user-skipped flags are must-preserve migration state. | P0 | `LARGE` | 003, 014 | GPT-5.6 Terra |
| `CORE-GAP-016` | ID3 chapters/artwork/range parsing (`FluxNews/lib/functions/audio_download_service.dart:977-1396`) | `SHARED_BUT_NOT_CORE` | `MISSING` | Add a portable media parser only if both native clients will share it; keep it outside inbox/sync domain. | P2 | `LARGE` | 015 | Kimi K2.7 Code |
| `CORE-GAP-017` | Widget headline/count/filter projection (`FluxNews/lib/functions/widget_service.dart:84-123`, `FluxNews/lib/functions/widget_service.dart:377-393`) | `RUST_CORE` | `MISSING` | Expose deterministic query DTOs suitable for native widget snapshot generation. App-group/preferences transport and rendering remain native. | P1 | `MEDIUM` | 003, 006 | GPT-5.6 Terra |
| `CORE-GAP-018` | Semantic sync/retention/feed/widget/media settings and feed overrides (`FluxNews/lib/state_management/flux_news_state.dart:79-195`) | `SHARED_BUT_NOT_CORE` | `MISSING` | Define stable semantic DTOs/defaults/validation while leaving Keychain/Keystore, UI, theme, gestures, and platform backup native. Existing local-only settings are must-preserve migration state. | P0 | `LARGE` | 003 | GPT-5.6 Terra |
| `CORE-GAP-019` | Native-localizable errors versus FluxBar core strings (`rust-core/src/localization.rs:15-87`; FluxNews seven-language catalogs) | `RUST_CORE` | `PARTIAL` | Expose typed error codes/data and let Swift/Kotlin localize UI. Retain FluxBar catalog operations for compatibility rather than extending them into FluxNews UI localization. | P2 | `MEDIUM` | 001 | GPT-5.6 Luna |
| `CORE-GAP-020` | Versioned backup ZIP/JSON, Argon2id/AES-GCM, validation, and restore mapping (`FluxNews/lib/functions/settings_backup_service.dart:252-420`, `FluxNews/lib/functions/settings_backup_service.dart:844-942`) | `SHARED_BUT_NOT_CORE` | `MISSING` | Decide whether to preserve the portable format/crypto contract or deliberately replace it. Keep file pickers, secret access, password UI, and Android OS backup native. | P2 | `LARGE` | 018 | GPT-5.6 Terra |
| `CORE-GAP-021` | One-time migration of deployed SQLite, secure storage, progression, downloads, and local settings (`FluxNews/lib/state_management/flux_news_state.dart:672-1699`; migration inventory below) | `SHARED_BUT_NOT_CORE` | `MISSING` | After characterization, implement an idempotent, resumable import with verification, rollback/failure policy, account association, and per-state mappings. Add handlers as their target models stabilize; do not cut over existing users until all must-preserve handlers are complete. | P0 | `VERY_LARGE` | 003, 004, 007, 009, 014, 015, 018 | GPT-5.6 Sol |
| `CORE-GAP-022` | User-requested deletion of repository, downloads, icons, player state, and projections (`FluxNews/lib/database/database_backend.dart:2519-2588`; `FluxNews/lib/ui/settings.dart:1092-1108`) | `RUST_CORE` | `MISSING` | Define a transactional core repository-reset operation and its native coordination contract for audio stop, file/cache deletion, widget refresh, and partial-failure recovery. | P1 | `MEDIUM` | 003, 015 | GPT-5.6 Terra |

## FULL coverage

None at the end-to-end FluxNews responsibility level.

### Strong reusable basis: read/unread desired-state persistence

Rust already has strong core semantics for immediate effective local state,
read and unread desired values, durable retry, successful-prefix
acknowledgement, newer-revision protection, and batch automatic-read Undo
(`rust-core/src/sync.rs:283-370`, `rust-core/src/sync.rs:398-433`;
`rust-core/src/persistence/store.rs:407-474`,
`rust-core/src/persistence/store.rs:508-633`).

FluxNews exposes individual, bulk, open-to-read, and scrollover read triggers
(`FluxNews/lib/functions/news_widget_functions.dart:481-707`,
`FluxNews/lib/ui/news_list.dart:245-447`). `CORE-GAP-007` must extract or adapt
the algorithm from its FluxBar schema and flush-timer coupling, expose it against
the mobile schema/query contract, and implement FluxNews bulk delivery. The
revision/acknowledgement algorithm is reusable, but is not yet a directly
callable mobile engine.

## PARTIAL coverage

| Area | Existing Rust overlap | Exact semantic gap |
| --- | --- | --- |
| Persistence | SQLite, account scope, categories/feeds/entries, transactions | No full HTML, hash/created/reading/share fields, feed settings, attachments, progression, versioned FluxNews migration, or retention metadata. |
| Sync | Complete-set checks, pending baseline protection, local-first fallback, serialization | One selected FluxBar set, ID cursor, 200-row presentation; FluxNews uses separate main/starred staged repositories, published-time/order/offset pages, configurable caps/windows, full content and retention. |
| Queries | All/unread/starred/category/feed predicates and sort direction | No mobile pagination, arbitrary list size, full fields, mark-scope operation, widget projection, or deterministic equal-time tie-break. |
| Stars/bookmarks | Desired-state pending revisions and current-state read-before-toggle | Rust calls `/star`; FluxNews calls `/bookmark`. Equivalence and Miniflux-version behavior are not characterized. |
| Categories/feeds | DTOs, hierarchy, titles, unread counters | FluxNews keeps site URL, icon ID/MIME, crawler and local presentation overrides, and supports creation/update/refresh commands. |
| Article processing | HTML parsing, normalization, image/enclosure selection, URL safety | FluxNews uses 2,000 characters, paragraph preference, per-feed attachment-image priority, stores HTML, and renders Markdown. |
| Icons | Data URL decode, raster/SVG processing, contrast variant, single-flight | FluxNews uses icon IDs, MIME/raw bytes, filesystem cache, widgets, and per-feed contrast settings. |
| Background execution | Per-account operation gate and durable pending work | No mobile path injection, OS headless lifecycle, or cross-process lease. OS scheduling must remain native. |
| Localization | Core lookup/pluralization and localized validation strings | Only FluxBar English/German catalog; FluxNews has seven UI languages and future native clients should localize UI and typed errors natively. |

## MISSING coverage

The current Rust core has no sufficient implementation for:

- full article and enclosure persistence;
- FluxNews v12 import/preservation;
- configurable mobile offline sync/retention;
- paginated local repository queries and mark-scope commands;
- custom Miniflux headers, `/me`, version/capability discovery;
- remote search;
- curated feed/category creation, feed title update/refresh, and third-party save;
- enclosure progression state and delivery;
- download catalog/retention coordination;
- ID3 chapter/artwork parsing;
- mobile/headless artifacts and tested iOS/Android TLS/runtime behavior;
- widget-specific local query projections;
- shared semantic settings DTOs;
- typed native-localizable error categories;
- versioned backup-format/crypto compatibility or a deliberate replacement;
- one-time migration implementation and cutover verification;
- coordinated destructive local-data reset.

## Native responsibilities

### Swift/iOS

- Keychain storage/accessibility and background credential availability.
- BGTaskScheduler registration and lifecycle.
- SwiftUI navigation, list/card/reader presentation, gestures, and share/link UI.
- WidgetKit, App Intents, app-group transport, and widget timelines.
- AVAudioSession, Now Playing, remote commands, CarPlay, route changes, and
  interruption handling.
- ActivityKit/Dynamic Island if retained; the current FluxNews implementation
  is not proven complete.
- Native String Catalog UI localization.
- File import/export and backup security UI.

### Kotlin/Android

- Keystore-backed secret storage and background availability.
- WorkManager registration, constraints, process lifecycle, and retries.
- Compose/native navigation, list/card/reader presentation, gestures, share,
  intents, and Custom Tabs.
- AppWidget/RemoteViews or Glance, deep links, and widget data transport.
- Media3/audio focus, notification/media session, Android Auto, route changes,
  and interruptions.
- Android resources localization.
- Storage Access Framework and Android backup integration.

### Both native clients

- Decide when to call Rust sync/query/mutation operations.
- Convert OS lifecycle/connectivity/background events into typed core calls.
- Persist secrets and UI/platform preferences.
- Own image/audio files and disposable caches.
- Render full article content and platform link/share behavior.
- Publish widget/audio/automotive surfaces from core data.

## Persistence comparison

| Concern | FluxNews | Current Rust core | Classification |
| --- | --- | --- | --- |
| Account scope | One global DB, integer IDs only | Account ID on every durable core row | Rust concept reusable; FluxNews migration/association required |
| Schema version | Sqflite version 12 with historical upgrade code | No `user_version`; idempotent Go-compatible schema | Requires separate schema/migration decision |
| Article body | Full HTML persisted | Discarded after preview/image extraction | Requires Rust schema/domain extension |
| Entry metadata | Hash, created time, reading time, share code, comments, feed title | Subset only | Requires extension |
| Feed metadata | Site URL, icon ID/MIME, crawler and presentation settings | ID/category/title/unread count | Requires extension; UI settings may remain native storage |
| Enclosures | Dedicated table and progression | DTO used only transiently for image fallback | Requires extension |
| Remote/effective state | `status`, `starred`, weak `syncStatus` | Explicit remote/effective baselines plus desired revisions | Rust mechanism is preferable and reusable |
| Undo | None | Durable automatic-read batches/items | Reusable optional capability |
| Selection totals | Derived/query state | Explicit remote totals by selection | Reusable where mobile queries need remote totals |
| Sync staging | Temporary main/starred JSON staging table | In-memory complete selection plus temporary ID table for reconciliation | Requires mobile-scale design/characterization |
| Retention | Configurable read/star limits, protects downloaded audio | No durable cache retention policy | Requires extension plus native download contract |
| Icons/images | Filesystem/disposable caches | Memory-only icons; image URL only | Keep caches platform-owned/rebuildable |

Structural categories:

- Directly reusable concept: account scoping, remote/effective/desired state,
  revisions, transactions, selection predicates, complete-set reconciliation.
- Requires Rust schema extension: full article fields, feed metadata,
  enclosures/progression, retention/download protection, mobile query indexes.
- Requires adapter/migration: every existing FluxNews database and
  local-only/unsynchronized row.
- Should remain platform storage: credentials, UI/theme/gesture settings,
  background scheduling metadata, file paths, widget transport.
- Rebuildable cache: feed icons, article images, previews when full HTML exists,
  widget snapshots, logs, temporary staging.

## Settings and secrets

Actual FluxNews secure storage includes URL/API key/version, custom headers,
sync/search/retention limits, read behavior, per-feed overrides, UI/theme/
gesture settings, widget settings, background interval, download policy, and
download metadata (`FluxNews/lib/state_management/flux_news_state.dart:79-195`).

Recommended split:

| Category | Future ownership |
| --- | --- |
| API key and sensitive custom headers | Native secure storage |
| Server URL and account selection | Native configuration, passed to Rust as typed session config |
| Sync scope, caps, date window, retention semantics | Shared semantic DTO/rules; persisted by native host or deliberate core settings store |
| Per-feed article/icon behavior | Shared semantic DTO keyed by account/feed; native UI edits it |
| Theme, layout, gestures, toolbar, scroll position | Native preference storage/UI only |
| Background interval and OS constraints | Native preference and scheduler |
| Widget presentation/settings | Native preference; core can answer deterministic query projections |
| Download paths, connectivity policy, media-session preferences | Native storage/services |
| Core-generated errors | Typed Rust codes/data; native localization |

Do not move Keychain/Keystore APIs into Rust. Also do not assume FluxNews backup
format is only harmless preferences: `createBackupData()` includes nearly all
secure-storage values, including credentials/custom headers
(`FluxNews/lib/functions/settings_backup_service.dart:252-331`).

## Sync and mutation comparison

| Behavior | FluxNews source behavior | Rust behavior | Assessment |
| --- | --- | --- | --- |
| Initial sync | Stages main, categories/feeds, then starred; applies after complete fetch | Fetches counters, optional starred total, selected entries, categories, feeds | `PARTIAL`; ordering/scope/data differ |
| Incremental sync | Repeats scoped snapshot; optional read-history window and cap | Repeats selected complete snapshot | `PARTIAL` |
| Pagination | Published order, direction, offset, page 1,000, stable total and unique-count check | Ascending ID cursor, page 200, strict monotonic IDs/total | `PARTIAL`; neither contract can be substituted silently |
| Local cache size | All unread plus configured retained read/starred rows | At most 200 presented rows per snapshot; DB stores fetched selected rows | `PARTIAL` |
| Read | Local update, optional immediate fire-and-forget, deferred queue only for selected read rows | Durable desired read or unread revision and per-row retry | `PARTIAL`; desired-state persistence is reusable, bulk delivery/mobile integration are absent |
| Unread | Local update and optional immediate push; no symmetric deferred queue | Durable desired unread revision and retry | Rust is stronger; preserve stronger behavior |
| Star | Optimistic local state, `/bookmark`, no durable retry | Durable desired state, reads current server state, `/star` toggle | `PARTIAL`; endpoint equivalence unknown |
| Reconciliation | Complete main absence can mark local unread rows read; complete starred absence clears stars | Complete unread/starred selection updates remote baseline while pending desired state wins | Strong reusable concept; row sets differ |
| Retry | No general HTTP backoff; WorkManager may rerun; partial read chunks acknowledge | Durable queue, ordered successful prefix, first-failure stop, scheduler retry opportunity | Rust stronger |
| Undo | No mutation Undo | Durable automatic-read batch/compensation | Optional Rust capability useful to native UI |
| Automatic read | Marks crossed indexes after scroll ends; no dwell/percentage | Core accepts automatic source, creates Undo, delays flush 10 seconds | UI detection remains native; core delivery is reusable |
| Deletion/retention | Read/star limits and downloaded-audio protection; feed/category absence cleanup | Scoped negative status/star reconciliation; no cache retention/feed deletion policy | `PARTIAL` |
| Triggers | Startup/manual/background/widget/open/gesture/scroll | Host calls operations; internal delayed pending flush | Native host must reproduce trigger policy |

Characterization tests should compare both codebases' semantics before choosing
which behavior to preserve. Existing FluxNews weaknesses, such as no durable
unread/star queue, should not force regressions in the stronger Rust engine.

## Background execution

Core responsibility:

- expose idempotent typed operations for refresh, pending flush, retention,
  progression reconciliation, and widget-query generation;
- preserve durable pending state across process death;
- serialize/coordinate access to the selected account database;
- return typed partial/failure outcomes suitable for OS retry decisions.

Native responsibility:

- register BGTaskScheduler/WorkManager jobs;
- choose timing, network/power constraints, retry policy, and expiration;
- obtain secrets under locked/background conditions;
- start/load the Rust library and provide database/cache paths;
- terminate/cancel work when the OS requires it;
- refresh widgets and enqueue platform downloads after core completion.

FluxNews' current 30-minute interval is normalized and scheduled in
`FluxNews/lib/functions/background_sync_service.dart:71-157`; it is an OS
request, not a cadence guarantee.

## Localization

FluxNews uses generated Flutter catalogs for English, German, Spanish,
Galician, Dutch, Tamil, and Turkish
(`FluxNews/lib/l10n/flux_news_localizations.dart:92-108` and
`FluxNews/lib/main.dart:428-438`). Widget snapshot labels are localized in
Flutter before crossing to native widgets
(`FluxNews/lib/functions/widget_service.dart:84-123`,
`FluxNews/lib/functions/widget_service.dart:187-193`).

The Rust core's embedded English/German catalog exists to preserve FluxBar's Go
wire behavior. It is not an appropriate source of truth for future SwiftUI and
Android UI. Recommended ownership:

- SwiftUI/App Intents/WidgetKit UI strings: Apple String Catalogs.
- Android/Glance/automotive UI strings: Android resources.
- Rust failures: typed error code plus structured context.
- Domain-generated non-UI text, if any remains: explicitly shared and tested;
  do not silently reuse FluxBar keys.

## Media, article, and icons

### Articles

FluxNews actually persists full HTML and supports inline Markdown/full-text
expansion. Rust only stores preview/image metadata. A future native client needs
the full content record from Rust, while rendering and link handling stay
native.

FluxNews and Rust extraction algorithms are not equivalent. FluxNews can prefer
paragraphs and attachment images and truncates cached preview at 2,000
characters. Rust reproduces FluxBar's 600-code-point extraction, lazy/srcset
rules, tiny-image filtering, relative URL resolution, and enclosure fallback.
Use separate policy functions rather than changing proven FluxBar output.

### Icons

FluxNews persists raw icon files by Miniflux icon ID, retains MIME type, exposes
bytes to widgets, and applies per-feed contrast choices. Rust fetches by feed ID
and returns normalized regular/dark PNG variants from an in-memory cache. Decode,
SVG/raster, and single-flight utilities are reusable; identity, output, and
cache ownership need separation.

### Audio and podcasts

Podcast functionality is demonstrably implemented in FluxNews. It includes
streaming/local playback, download queues, Wi-Fi policy, progress persistence,
Miniflux enclosure progression, sleep timer, playback speed, chapters/artwork,
Android media browsing/Auto, and CarPlay.

Recommended split:

- Rust core: enclosure/article identity, server/local progression baseline,
  conflict/retry semantics, and queryable podcast metadata.
- Shared utility outside inbox core: optional ID3 chapter/artwork parser.
- Native: audio engine/session, Now Playing/media notification, files/download
  queue, connectivity policy, route/interruption handling, automotive UI.

No new-article notification feature was found, so no notification core gap is
recorded.

## Binding and API gaps

The current C/JSON API is sufficient for FluxBar compatibility but is too
FluxBar-specific as the only FluxNews interface:

| API category | Current status | FluxNews requirement |
| --- | --- | --- |
| Configuration | Server/API key/sort/locales in `configure` | Host paths, custom headers, account/session, version/capabilities; secrets remain native |
| Snapshot/query | One snapshot v1 with max 200 and retained IDs | Paginated full-entry/list projections, counts, full-content lookup, widget/download queries |
| Sync | Refresh one selection | Mobile offline sync profile, progress/cancellation, complete/incomplete outcomes, retention |
| Mutations | Read/star, Undo, discard, explicit flush | Scope/batch commands, typed receipts, progression desired state, feed/save commands |
| Search | None | Remote search query/results/cap/sort |
| Settings semantics | Sort only | Sync/retention/feed/media semantic DTOs; UI/platform settings stay native |
| Media | None | Enclosure/progression/download metadata, not an audio engine |
| Errors | Localized strings | Stable typed codes and structured data for native localization/retry |
| Concurrency/lifecycle | Synchronous global runtime | Host cancellation, background process startup, explicit close/account lifecycle |

Do not extend the flat compatibility envelope with every FluxNews field by
default. Preserve FluxBar's ABI and place future typed adapters around reusable
domain services.

## Data migration inventory

| Classification | Existing FluxNews data | Evidence/reason |
| --- | --- | --- |
| `MUST_PRESERVE` | Miniflux URL/API key and required custom headers | Required to reconnect; secure keys at `FluxNews/lib/state_management/flux_news_state.dart:79-81`, `FluxNews/lib/state_management/flux_news_state.dart:151-154` |
| `MUST_PRESERVE` | Playback progress, including explicit zero completion | Can be ahead of server and zero prevents stale resume; explicit reset writes at `FluxNews/lib/functions/flux_news_audio_handler.dart:372-391` and `FluxNews/lib/ui/audioplayer.dart:637-643` |
| `MUST_PRESERVE` | Local-only per-feed overrides and semantic preferences | Not recoverable from Miniflux; feed override key at `FluxNews/lib/state_management/flux_news_state.dart:120-121` |
| `MUST_PRESERVE` | Per-attachment user-skipped download flags | Explicit user intent prevents automatic redownload after cancellation/deletion and is not recoverable remotely; `FluxNews/lib/functions/audio_download_service.dart:222-270` |
| `SHOULD_PRESERVE` | Downloaded audio and its article/enclosure/title/feed metadata | Needed for offline playback and automotive browsing; source may disappear |
| `SHOULD_PRESERVE` | Full cached article HTML and attachments | Supports offline reading; remote retention/caps may prevent complete rebuild |
| `SHOULD_PRESERVE` | User settings backup artifacts and compatibility with their passwords | May be the user's only portable copy; format/encryption parsing at `FluxNews/lib/functions/settings_backup_service.dart:252-398` |
| `CAN_REBUILD` | Categories/feeds except local overrides | Miniflux source of truth |
| `CAN_REBUILD` | Fully synchronized article metadata still available remotely | Subject to server retention and configured query limits |
| `CAN_REBUILD` | Derived preview text/image URL | Recompute from preserved/refetched HTML and enclosures |
| `CAN_REBUILD` | Feed icons, article images, podcast artwork | Disposable remote/derived caches |
| `CAN_REBUILD` | Widget snapshots and page indexes | Deterministically generated from data/settings |
| `CAN_DROP` | Temporary sync staging, file lock, foreground/background heartbeat | Coordination only |
| `CAN_DROP` | Transient search results and in-memory UI lists | Requery/refetch |
| `CAN_DROP` | Logs and temporary exported log ZIPs | Diagnostics only unless user explicitly preserves them |
| `UNCLEAR` | Historical databases from every version 1-11 | Migration branches require fixture characterization |
| `UNCLEAR` | Locally changed read/unread state represented by `status`/`syncStatus` | The stored values and sync-marker lifecycle do not reliably distinguish unresolved user intent from a stale remote snapshot without fixtures and execution characterization |
| `UNCLEAR` | Bookmark state after failed remote toggle | Current code has no durable intent marker, so a local value alone cannot prove unresolved intent |
| `UNCLEAR` | Download path metadata restored to another device | Paths can be device/install-specific and backups do not contain audio files |
| `UNCLEAR` | Unencrypted backup handling | Backups can contain credentials; product/security policy must decide preservation flow |

## Reusable Rust components

Likely reusable internal components, subject to the stated integration and
semantic caveats:

| Module/component | Capability | Reuse evidence | FluxNews caveat |
| --- | --- | --- | --- |
| `domain/account.rs` | Deterministic credential-derived account ID | Pure tested SHA-256 helper | API-key rotation changes identity; existing rows need an explicit association/import policy |
| `domain/selection.rs` | Selection normalization/predicates | Pure all/unread/starred/category/feed logic | Mobile query API cannot inherit 200-row snapshot |
| Pending revision/ack logic in `persistence/store.rs` | Desired state supersession and acknowledgement | Tested against Go and concurrent mutation cases | Must operate on chosen mobile schema |
| Sync gate/service ownership in `sync.rs` | Per-account refresh/flush ordering without blocking icon work | Phase 10.1 concurrency tests | Cross-process/mobile lifecycle remains unresolved |
| Remote error taxonomy and request deadline plumbing | Typed transport/auth/status errors | Deterministic fake-server tests | Add custom headers, capabilities, mobile TLS tests |
| Miniflux entry/category/feed DTO basics | Shared protocol field subset | Existing remote adapter tests | Existing DTOs are insufficient unchanged; they must retain full FluxNews fields/enclosures |
| Strict complete-selection pagination algorithm | Detects unstable/duplicate/truncated ID pages | Differential tests | FluxNews sync policy must decide cursor/order/scope explicitly |
| Article parser URL/enclosure primitives | HTML recovery, HTTP(S) URL resolution, MIME fallback | Differential article fixtures | Do not change FluxBar output policy in place |
| Icon raster/SVG/single-flight primitives | Safe decode/normalize/concurrent fetch | Differential/unit icon tests | Mobile raw/MIME/file policy differs |
| FFI panic/memory boundary | Safe interim adapter behavior | 2,073-response ABI differential | Not an ergonomic typed mobile API |

## FluxBar-specific components

These should remain FluxBar compatibility behavior or be separated before
FluxNews reuse:

- Snapshot v1 and the 200-entry presentation limit
  (`rust-core/src/persistence/store.rs:635-873`).
- `retainEntryIDs`, which preserves rows across popover presentation changes.
- The 11-operation flat JSON request/response envelope.
- Network-free `configure`, configuration generation, and embedded localized
  validation strings.
- The exact unversioned Go-compatible SQLite schema.
- FluxBar's selected-scope refresh rather than a mobile offline repository sync.
- FluxBar's 600-code-point article preview and exact image precedence.
- Feed-ID memory-only normalized regular/dark icon response.
- FluxBar English/German catalog and plural fallback contract.
- The automatic-read 10-second flush timer and native 8-second Undo-window
  assumption; the durable receipt mechanism is reusable, timing is host policy.

## Prioritized gap list

| Order | GAP ID | Priority | Complexity | Dependencies | Recommended implementation sequence |
| --- | --- | --- | --- | --- | --- |
| 1 | `CORE-GAP-002` | P0 | `LARGE` | None | Prove the current ABI on iOS/Android, including paths, TLS, threads, and lifecycle. |
| 2 | `CORE-GAP-003` | P0 | `VERY_LARGE` | None | Define mobile domain/schema beside FluxBar compatibility storage. |
| 3 | `CORE-GAP-004` | P0 | `VERY_LARGE` | 003 | Characterize real FluxNews schemas/data before migration decisions. |
| 4 | `CORE-GAP-006` | P0 | `LARGE` | 003 | Add mobile local query/content interfaces so a prototype can render offline. |
| 5 | `CORE-GAP-009` | P0 | `MEDIUM` | None | Support required headers and account validation before sync prototypes exclude affected users. |
| 6 | `CORE-GAP-005` | P0 | `VERY_LARGE` | 003, 009 | Implement and characterize mobile sync/reconciliation/retention. |
| 7 | `CORE-GAP-007` | P0 | `LARGE` | 003, 005, 006 | Integrate mutations and characterize bookmark endpoint behavior. |
| 8 | `CORE-GAP-008` | P0 | `LARGE` | 002, 003, 005 | Make host-triggered headless work safe; native schedulers follow. |
| 9 | `CORE-GAP-001` | P1 | `LARGE` | None | Design a typed mobile adapter from validated ABI, lifecycle, and domain requirements. |
| 10 | `CORE-GAP-014` | P0 | `VERY_LARGE` | 003, 007, 009 | Add enclosure progression state before migration and native podcast parity. |
| 11 | `CORE-GAP-010` | P1 | `MEDIUM` | 009 | Add remote search. |
| 12 | `CORE-GAP-011` | P1 | `LARGE` | 009 | Add source-demonstrated onboarding/save commands only. |
| 13 | `CORE-GAP-012` | P1 | `LARGE` | 003 | Add separate FluxNews article policy; keep rendering native. |
| 14 | `CORE-GAP-018` | P0 | `LARGE` | 003 | Stabilize must-preserve semantic settings/feed override DTOs. |
| 15 | `CORE-GAP-015` | P0 | `LARGE` | 003, 014 | Define native download/core retention and user-skipped-state contract. |
| 16 | `CORE-GAP-017` | P1 | `MEDIUM` | 003, 006 | Add widget query projection before native widget parity. |
| 17 | `CORE-GAP-021` | P0 | `VERY_LARGE` | 003, 004, 007, 009, 014, 015, 018 | Complete and verify every required migration handler before existing-user cutover. |
| 18 | `CORE-GAP-022` | P1 | `MEDIUM` | 003, 015 | Coordinate destructive local reset across core repository and native files/services. |
| 19 | `CORE-GAP-013` | P2 | `MEDIUM` | 003, 009 | Separate mobile icon asset/cache semantics. |
| 20 | `CORE-GAP-019` | P2 | `MEDIUM` | 001 | Move new mobile callers to typed errors/native localization. |
| 21 | `CORE-GAP-020` | P2 | `LARGE` | 018 | Preserve or deliberately replace the versioned backup/crypto contract. |
| 22 | `CORE-GAP-016` | P2 | `LARGE` | 015 | Share ID3 parsing only after native media architecture is chosen. |

Priority meaning:

- P0 blocks a viable native client or safe use of existing user data.
- P1 is required for demonstrated FluxNews functional parity.
- P2 is important but can follow an initial native prototype.
- No source-backed Rust-core P3 item was needed in this analysis.

## Dependency graph

```text
001 -> 019
002 -> 008
003 -> 004, 005, 006, 007, 008, 012, 013, 014, 015, 017, 018, 021, 022
004 -> 021
005 -> 007, 008
006 -> 007, 017
007 -> 014, 021
009 -> 005, 010, 011, 013, 014, 021
014 -> 015, 021
015 -> 016, 021, 022
018 -> 020, 021
```

Root gaps with no prerequisites are `001`, `002`, `003`, and `009`. The arrows
mean “must precede,” and exactly mirror the matrix/list dependencies.

## Suggested model assignment

Use GPT-5.6 Sol only for changes where incorrect semantic decisions can cause
data loss, synchronization divergence, ABI instability, or cross-process
corruption:

- GPT-5.6 Sol: `CORE-GAP-001`, `003`, `004`, `005`, `007`, `008`, `014`, `021`.
- GPT-5.6 Terra: `CORE-GAP-002`, `006`, `015`, `017`, `018`, `020`, `022` and native
  background/media/widget architecture.
- Kimi K2.7 Code: `CORE-GAP-009`, `010`, `011`, `012`, `013`, `016` after
  contracts and fixtures are defined.
- GPT-5.6 Luna: `CORE-GAP-019`, native localization/catalog migration, and
  native UI surfaces after data APIs stabilize.

## Recommended next steps

### Rust-core expansion

1. Freeze the current FluxBar compatibility modules and identify reusable
   service boundaries without changing behavior.
2. Characterize a mobile domain/schema and full-content/enclosure requirements.
3. Build FluxNews-vs-new-core fixtures for sync scope, complete/incomplete
   pagination, retention, remote field changes, mutations, and progression.
4. Add mobile query/sync/mutation capabilities in dependency order.
5. Add media progression and retention integration only after the article/
   enclosure model is stable.

### Binding/API work

1. Build/test the existing C ABI as iOS and Android artifacts, including TLS,
   paths, threads, ownership, and lifecycle behavior.
2. Define typed API categories, cancellation, and errors from the characterized
   mobile domain and validated host constraints.
3. Keep `FluxCoreRequest`/`FluxCoreFree` unchanged for FluxBar.
4. Evaluate UniFFI or another adapter only against those requirements.

### Native iOS work

1. Prototype Keychain-backed configuration plus a Rust local-query screen.
2. Add native sync triggers and BGTaskScheduler integration after headless core
   operations are safe.
3. Add SwiftUI article/navigation/actions around typed queries and mutations.
4. Add AVFoundation/Now Playing/downloads, then widgets and CarPlay.
5. Treat Dynamic Island as separate native work; do not infer parity from the
   incomplete Flutter-era source.

### Flutter-data migration

1. Collect or generate historical schema fixtures for every supported version.
2. Characterize secure-storage, shared-preference progression, database, and
   downloaded-file relationships.
3. Decide preserve/import/rebuild/drop policy per the inventory above.
4. Only then design the one-time migrator and rollback/verification strategy.
5. Implement idempotent import handlers alongside their target models, exercise
   them against historical fixtures, and block existing-user cutover until all
   must-preserve state verifies successfully.

### Native Android work

1. Start after the mobile ABI/runtime and schema are stable enough to avoid
   duplicating API churn; a final typed adapter need not block initial work.
2. Implement Keystore configuration, local query/action UI, and WorkManager.
3. Add Media3/downloads/Android Auto and widget support using the same core
   article/progression contracts.
4. Add migration from Android secure storage, SharedPreferences, SQLite, and
   audio files using characterized fixtures.

## Confidence and unknowns

### High-confidence traced areas

- FluxNews schema creation, principal tables, model mapping, staged sync order,
  read/bookmark actions, query scopes, background scheduling, widget snapshot
  generation, backup contents, audio progression, and platform entry points.
- Rust public operations, schema, snapshot limit, remote endpoints, pending
  mutations, Undo, article processing, icons, localization, and concurrency
  ownership.

### Weakly tested or ambiguous areas

- Which FluxNews historical schema versions exist in real installations and
  whether exact-version migration branches safely reach version 12.
- Whether Miniflux `/star` and `/bookmark` are equivalent for every supported
  server version. This analysis does not assume they are.
- Stability guarantees of FluxNews offset pagination while remote data changes.
- Exact OS retry/execution behavior for WorkManager and BGTaskScheduler.
- Background secure-storage access on locked physical devices.
- Native widget/deep-link, CarPlay/Android Auto, and audio interruption behavior;
  no native XCTest/instrumentation suites were found.
- ActivityKit source packaging/control wiring; treat it as incomplete until a
  native build/test proves otherwise.
- Whether all cached historical articles/enclosures can be rebuilt from a
  user's current Miniflux retention and sync settings.
- Intended security policy for unencrypted backups containing credentials.
- Whether custom headers are intentionally allowed to override auth/content
  headers; current FluxNews merge order permits it.

### Required future characterization tests

- Every FluxNews schema version to the chosen native schema.
- Existing account/server switch behavior and overlapping integer IDs.
- Full/partial/capped main and starred snapshots with concurrent remote changes.
- Read/unread/star failures, process death, retry, and cross-device conflicts.
- Enclosure progression including explicit zero, completion, and stale server
  positions.
- Equal publication timestamps and mixed ISO-8601 offsets.
- iOS/Android Rust TLS, lifecycle, thread, cancellation, and headless database
  access.
- Widget, background, media-session, automotive, secure-storage, and migration
  tests on physical devices.

## Final assessment

The Rust core is close to being a reusable Miniflux synchronization foundation,
but not close to drop-in FluxNews parity. Reuse should begin with its transport,
pending-state, transaction, complete-set, article-parser, icon, and in-process
concurrency primitives. Credential-derived account identity needs an explicit
rotation/import policy. The mobile data model, migration contract, offline sync
profile, query API, media progression, and native host boundary must be added
deliberately rather than by expanding FluxBar's presentation contract.
