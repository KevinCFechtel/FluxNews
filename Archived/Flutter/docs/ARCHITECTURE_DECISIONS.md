# Flux News Architecture Decisions and Invariants

This file contains durable rules whose rationale is important enough that future changes should not accidentally undo them.

## Dependency and Build Boundaries

### iOS is SwiftPM-only

The iOS Runner uses Flutter's Swift Package Manager integration. CocoaPods has deliberately been removed. Do not run `pod install` or restore Pods files unless a future native dependency cannot be consumed through Flutter SwiftPM and that architectural decision is explicitly revisited.

Before adding or upgrading native Apple plugins, verify SwiftPM participation and complete an iOS simulator/device build.

### Production SQLite uses mobile sqflite

The production application must use normal `sqflite`. `sqflite_common_ffi` is a development/test dependency only. A global `databaseFactory = databaseFactoryFfi` caused Android startup failure because the expected native SQLite library was not packaged.

## Remote Data and Sync Integrity

### Miniflux is source of truth

Miniflux owns categories, feeds, and feed metadata. Flux News-specific per-feed preferences are stored separately and reapplied after server data is inserted.

### Incomplete remote fetches are never authoritative

Unread news, categories/feeds, and starred news form one authoritative remote snapshot. Reconciliation and destructive cleanup may begin only after all required requests succeed.

A transport/server failure must never be converted into an empty `NewsList` or empty feed result.

### Foreground and background sync share the same pipeline

`lib/functions/sync_pipeline.dart` is the common implementation. Do not create independent reconciliation behavior for foreground and background sync without an explicit redesign.

### Foreground and background sync must not overlap

Both use the file-based lock in `lib/functions/sync_lock.dart`. A second run is skipped instead of operating concurrently. Stale/orphan handling is part of the lock contract.

### Globally empty feed responses are guarded

When local feeds exist but Miniflux unexpectedly returns zero feeds, destructive feed/category cleanup is skipped. Genuine deletions are still allowed when the server response is non-empty.

### Category news ordering is global

News for a selected category are queried as one globally date-ordered result. Do not reintroduce per-feed concatenation because it groups chronology by feed.

## Configuration Integrity

### Read failure is not empty configuration

`FluxNewsState.readConfigValues()` distinguishes a successful empty Secure Storage read from a failure/timeout. Failure preserves previously loaded values and must prevent migration, initialization, scheduling changes, or Welcome navigation decisions based on defaults.

This rule exists because concurrent foreground/WorkManager reads previously timed out and were incorrectly treated as empty settings.

### Background scheduling requires valid configuration

`configureFluxNewsBackgroundSync()` must not register or cancel work until configuration has been read successfully.

## Database and Content Integrity

### Lightweight list objects must not overwrite full content

List queries intentionally return lightweight `News` objects. `insertNewsInDB()` must preserve stored full content/preview/image data when `contentLoaded == false`.

### Expensive metadata backfill must not run inside schema open/upgrade

Schema migration adds columns only. HTML parsing/backfill occurs later in batches so large databases do not block startup or cause ANRs.

### Index definitions belong in the shared schema

Keep query-path indexes in `lib/database/database_schema.dart` so installs, migrations, and tests use the same schema definition.

## Widgets

### Native widgets render snapshots only

Flutter owns synchronization, SQLite access, settings, and snapshot generation. Native widget code must not read Miniflux credentials or SQLite directly.

### Widget actions are lifecycle guarded

Pending actions are peeked for startup behavior and consumed exactly once. Reentrant `resumed` events, including those caused by closing an iOS in-app browser, must not replay the action.

## Platform UI Boundaries

### iOS Liquid Glass stays behind Flux News-owned facades

The Liquid Glass package is initialized/rendered only on the iOS application path. Android remains Material/Core Flutter and must not depend on Liquid Glass rendering.

Keep package APIs behind Flux News-owned widgets/facades to limit package churn and allow fallbacks/kill switches.

### Android and iOS may differ in presentation, not policy

Where possible, action availability and business logic should be shared while platform-specific menus/chrome provide presentation.

## Audio and Media

### Audio initialization must not claim focus

Creating the audio handler must not activate the audio session. Explicit playback requests activate audio focus/session ownership.

### iOS remains primary Now Playing owner during playback

Do not add `mixWithOthers` merely to hide interruption symptoms. The chosen iOS playback/session configuration exists to preserve CarPlay routing and Lock Screen/Dynamic Island ownership.

## Local Data and Backup

### Feed metadata is rebuilt from Miniflux

Settings backup should preserve Flux News-specific feed overrides, not restore a stale feed database as authoritative state.

### Android Auto Backup is explicitly scoped

Only the generated Flux News settings backup file participates after user opt-in. Secure Storage, SQLite, SharedPreferences, caches, and general app data are intentionally excluded.

## Known Failed Approach: mark-as-read scroll lag

With mark-as-read-on-scrollover enabled, a quick new gesture after passing an unread article can briefly lag.

Previous attempts involving batched SQLite status writes, coalesced refreshes, direct counter updates, and asynchronous optimistic persistence did not solve the problem and introduced correctness issues. Do not reapply these approaches without profiling the original implementation on a representative physical device and identifying the blocking work first.

The current implementation instead serializes scroll-observer events, processes only newly crossed indexes, uses stable article keys, rebuilds the affected article through a per-item status listenable, and serializes widget snapshot generation. It deliberately retains awaited per-item SQLite persistence rather than reintroducing the failed optimistic/batched write approach. Physical-device profiling is still required to confirm that this removes the original input interruption on all supported layouts.
