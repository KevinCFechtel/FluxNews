# Flux News Developer Map

## Purpose

Flux News is a Flutter application that uses Miniflux as its remote source of truth and maintains a local SQLite representation for fast application behavior, offline/local state, widgets, and media-related features.

This document is intentionally high level. Detailed implementation constraints live in `ARCHITECTURE_DECISIONS.md` and the feature documents under `docs/features/`.

## System Map

```text
                         Miniflux
                            │
                    HTTP client / API
                            │
                ┌───────────▼───────────┐
                │ Shared Sync Pipeline  │
                └───────────┬───────────┘
                            │
                         SQLite
                            │
                 ┌──────────┴──────────┐
                 │                     │
           Flutter app state      Widget snapshots
                 │                     │
        ┌────────┼─────────┐      ┌────┴─────────┐
        │        │         │      │              │
       UI      Audio   Downloads Android       iOS
                                AppWidget    WidgetKit
```

## Core Responsibilities

### Flutter application

Flutter owns application state, Miniflux synchronization, SQLite access, user settings, snapshot generation, podcast playback coordination, and most cross-platform business logic.

### Miniflux

Miniflux owns categories, feeds, feed metadata, unread/starred server state, and remote article data. Local Flux News-specific feed preferences are stored separately and reapplied after Miniflux data is synchronized.

### SQLite

SQLite is the local operational data store. List views use lightweight metadata where possible; full article content is loaded lazily for selected/expanded articles.

### Foreground and background synchronization

Foreground and Workmanager-based background sync share the same synchronization contract and a cross-isolate file lock. Remote news, categories/feeds, and starred data are treated as one authoritative snapshot only after every required request succeeds.

### Widgets

Flutter creates compact JSON snapshots. Native Android and iOS widgets render those snapshots and do not read Miniflux credentials or SQLite directly.

### Audio

Podcast playback uses a shared Flutter audio handler with platform media integrations. Playback position is stored locally in SharedPreferences. Downloads and media-session/audio-focus behavior have additional platform-specific constraints.

## Main Data Flow: Sync

```text
Miniflux requests
    │
    ├─ news
    ├─ categories / feeds
    └─ starred news
    │
    ▼
fetchRemoteSyncSnapshot()
    │
    ├─ pages are stored in connection-local SQLite staging
    ├─ any required request fails → discard staging, no reconciliation
    ▼
reconcileRemoteSyncSnapshot()
    │
    ├─ reconcile categories / feeds
    └─ atomically reconcile news / status / starred state
    │
    ▼
SQLite
    │
    ├─ rebuild/reload foreground list
    ├─ update counts/state
    └─ generate widget snapshot
```

Foreground and background execution reuse this contract.

## Main Data Flow: Configuration

```text
Secure Storage
    │
    ▼
readConfigValues()
    │
    ├─ successful empty read → valid empty configuration
    └─ failure / timeout → preserve previous values and abort initialization path
```

A failed credential/configuration read must never be interpreted as the user clearing configuration.

## Main Data Flow: Widgets

```text
Flutter state + SQLite
       │
       ▼
widget_service.dart
       │
       ▼
JSON snapshot
       │
   ┌───┴────┐
   ▼        ▼
Android    iOS
widget     WidgetKit
```

Widget actions open the Flutter application. The first implementation intentionally does not perform authenticated Miniflux synchronization directly inside native widget extensions/workers.

## Main UI Architecture

The application keeps platform-specific presentation while sharing business behavior:

- iOS uses the Liquid Glass-oriented application shell and adaptive iPhone/iPad layouts.
- Android uses Material layouts, including the optional/default floating chrome and tablet two-pane shell.
- Shared commands and business policies should remain shared even when presentation differs.

## Key Code Areas

- `lib/functions/sync_pipeline.dart` — authoritative remote snapshot fetch and local reconciliation.
- `lib/functions/background_sync_service.dart` — headless background-sync entry point.
- `lib/functions/sync_lock.dart` — foreground/background cross-isolate exclusion.
- `lib/functions/widget_service.dart` — widget snapshot generation.
- `lib/database/database_schema.dart` — SQLite schema and migrations/indexes.
- `lib/miniflux/miniflux_http_client.dart` — Miniflux HTTP client creation and lifetime.
- `lib/functions/audio_progress_store.dart` — podcast playback progress.
- `lib/functions/flux_news_audio_handler.dart` — media playback/session behavior.
- `lib/ui/adaptive_layout.dart` — shared compact/two-pane layout policy.
- `lib/ui/flux_news_body.dart` — major application shell/state integration.

## Areas Requiring Extra Care

Changes deserve especially careful review when they affect sync completeness, destructive cleanup, configuration loading, database migration, cross-isolate concurrency, lifecycle/reentrancy, widget action delivery, native bridges, media-session/audio-focus ownership, or release/signing reproducibility.

## Where to Read Next

- Sync/data/configuration: `docs/features/SYNC_AND_DATA.md`
- Widgets: `docs/features/WIDGETS.md`
- iOS UI: `docs/features/IOS_UI.md`
- Android UI: `docs/features/ANDROID_UI.md`
- Audio/media: `docs/features/MEDIA.md`
- Backup: `docs/features/BACKUP.md`
- Release/signing/F-Droid: `docs/RELEASE_AND_DISTRIBUTION.md`
- Future features: `docs/PRODUCT_BACKLOG.md`
