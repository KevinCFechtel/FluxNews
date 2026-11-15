# iOS D9 — Flutter Replacement Completion / Legacy-Parity Closure

> **Status: COMPLETE / PHYSICAL PRODUCTION-UPGRADE ACCEPTED — 10 OCTOBER 2026**
>
> Decision date: 26 September 2026.
>
> `docs/PHASE_D_NATIVE_IOS_IPADOS.md` remains the authoritative Phase-D
> roadmap. This document records the final product decisions from the
> repository-first FluxNews-to-native gap audit. D9 is not a general Flutter
> parity project: only the explicitly retained capabilities below are required.
> Items explicitly retired or replaced here must not later be reintroduced as
> accidental "parity gaps" without a new product decision.

## 1. Purpose

D1-D7 establish the native architecture and system integrations. D8 is not
required for the replacement release. D9 closes the remaining user-visible and
upgrade/release gaps required to replace the production Flutter iOS/iPadOS app
with the native client.

D9 must preserve the frozen Rust/Core ownership, UIKit Timeline architecture,
D5 background/notification ownership, D6 media runtime, and D7 system-media /
CarPlay ownership. Additive settings or WidgetKit configuration must reuse those
boundaries rather than create parallel state owners.

## D9 implementation progress

Current repository status:

- **D9-A — Production Flutter-to-native migration:** COMPLETE / TEST-GATED
- **D9-B — Config Backup and Restore:** COMPLETE / TEST-GATED
- **D9-C — Configurable Bottom Action Bar:** COMPLETE / TEST-GATED
- **D9-D — Localization parity:** COMPLETE / TEST-GATED
- **D9-E — Downloaded Data:** COMPLETE / TEST-GATED
- **D9-F — Miniflux account information / HTTP warning:** COMPLETE / TEST-GATED
- **D9-G — Open Source and About:** COMPLETE / TEST-GATED
- **D9-H — Logging & Support Diagnostics:** COMPLETE / TEST-GATED
- **D9 Widget Configuration:** COMPLETE / TEST-GATED
- **Final physical-device Flutter-to-native production-upgrade acceptance:** COMPLETE / REAL-DEVICE ACCEPTED

The productive TestFlight upgrade completed successfully on a physical iPhone
on 10 October 2026. The final migration summary was green and explicitly
reported stale historical playback positions that were discarded because no
local download existed and Miniflux returned confirmed 404/410. Completed
implementation contracts are frozen unless a concrete regression or new
product decision requires reopening them. Later shared changes must still pass
the canonical regression suite.

## 2. D9 release-critical replacement gates

### October 2026 — historical media recovery and completion parity

The native iOS migration now mirrors the Android E9 production findings: a read-only
legacy SQLite lookup identifies the article for each downloaded enclosure, enabling
targeted Miniflux recovery of older, already-read articles through the shared Core.
Playback positions likewise trigger historical article recovery where an
unambiguous audio enclosure can be found. A confirmed 404/410 is terminal only
when the read-only legacy download scan proves that no matching local audio file
exists; that historical progress is shown as old/discarded and does not make the
migration fail. Local downloads, ambiguous identity, connectivity failures and
incomplete legacy evidence remain retryable. Imported native playback/download
states are never overwritten.

The shared Core's content-based legacy media analysis and one-time repair of
downloaded `.audio` metadata (embedded artwork, durations and chapters) are now
invoked by iOS even when the download import completed on an earlier build.
The app provides a migration summary on startup, repeat-on-sync behavior, and an
explicit confirmation for completing with skipped unresolved media. It persists
`completed` versus `completed_with_skipped_items` and the original missing-item
details. Flutter source files remain untouched. The physical production upgrade
is accepted; later changes remain subject to the canonical regression gate.

### October 2026 — missing Keychain download keys in device diagnostics

The 2026-10-10 on-device diagnostics (3.0.0 / 2026100902) show
`Legacy media repair scanned=0 recoveredArtworks=0` and repeated
`Legacy playback imported=0 missing=53`. The user-reported migration
status also says that downloaded audio files remain on disk but no
Keychain download paths match. In the Flutter legacy source,
`AudioDownloadService.getDownloadedAudios()` enumerates
`Application Support/audio_cache` by filename independently of
Keychain; the original native iOS reader required
`audio_download_path_<id>` entries and therefore missed such files.

The iOS migration source reader now merges positively identified files
(`audio_<enclosureId>_<timestamp>[.extension]`) from the legacy
audio directory with any valid Keychain paths, deduplicating by
enclosure ID and choosing the newest on-disk candidate (like Flutter).
It is read-only and will still require a matching Core enclosure
before declaring a download imported. Unit tests cover missing
Keychain paths, stale absolute paths, duplicate audio files, and
invalid names. No existing native or Flutter media is deleted.
The subsequent TestFlight upgrade confirmed the legacy downloads appear in the
Listening List and that extracted artwork is retained.

### October 2026 — production iOS download migration follow-up

A physical TestFlight upgrade exposed a false-positive Downloads stage: the iOS
legacy reader could report an empty import set and write the v1 completion
marker despite offline media not appearing in Listening List. A new versioned
verification marker forces a one-time, non-destructive recheck of those existing
installations. The new empty-source guard refuses to mark completion if legacy
audio files are still present but no secure-storage path keys matched. Already
downloaded Core entries can repair missing Listening List membership on retry.

The migration progress sheet now reports the same six logical stages as
Android: Account, Settings, Feeds & startup view, Playback progress, Downloads,
and Widgets. The local settings migration and summary are initiated on startup
before historical media restoration; catalog-dependent state can still retry
after sync. Real-device verification subsequently confirmed repaired downloads,
post-sync Listening List refresh, and successful completion of the migration.

### D9-A — Production Flutter-to-native migration

Complete the production-identity migration coordinator over the already-defined
copy/import-only migration contract.

Required retained state remains limited to semantically compatible,
non-reconstructable state such as account association/credentials, custom HTTP
headers, compatible Core/native settings, compatible feed preferences, media
policies, playback progress, and valid downloaded-media association.

Flutter's sync-triggered `autoDownloadAudioAfterSync` implementation is not
ported. Its persisted user preference is semantically migrated to Core
`autoDownloadListeningList`: native continues to download only when an article
enters Listening List.

The migration remains idempotent, restart-safe, and non-destructive to legacy
storage. Existing valid native/Core state wins.

The global Flutter secure-storage booleans `markAsReadOnScrollOver` and
`removeNewsFromListWhenRead` migrate to the corresponding native UserDefaults
keys only when those native keys are absent. Both exact Flutter strings `true`
and `false` are stored choices. Native presence, including false, wins.
`sortOrder` remains transient native article-list control state and is not
migrated. `brightnessMode` is replaced by system-native Appearance and is not
migrated.

The versioned D9-A settings follow-up additionally imports exact valid Flutter
values only when the corresponding native setting has no explicit presence:

- `multilineAppBarText` -> Show Article Count;
- `showOnlyFeedCategoriesWithNewNews` -> Hide Empty Navigation Entries;
- `tabAction=expand` -> Reader/Open Detail View. `open` and `splitted` are not
  written;
- Flutter Slidable actions map right/second-right to Leading Full/Additional
  and left/second-left to Trailing Full/Additional. Only equivalent actions are
  imported and each native slot wins independently;
- `startupCategorie` maps All, Bookmarks, Category and Feed by Miniflux ID.
  Category/Feed imports wait for the authoritative catalog rather than using a
  title or URL heuristic;
- `backgroundSyncIntervalMinutes` maps only disabled/enabled, not Flutter's
  interval policy; native D5 scheduling remains authoritative;
- `autoDownloadAudioAfterSync` maps to `autoDownloadListeningList` as above.

`syncReadStatusImmediately` is intentionally not migrated. Flutter's setting
controls only read-status timing, while native `DeliveryMode` governs several
article mutations and is not semantically equivalent.

For the Flutter `feedSettingsOverrides` secure-storage JSON object, D9 migrates
only a positive `openMinifluxEntry: 1` under its numeric Miniflux feed ID to the
existing Core `open_in_miniflux` preference. Flutter serialized zero-valued
defaults for every override field, so `0`, missing, or malformed values are not
evidence of an explicit false choice and are not migrated. The Core retains
field-level native preference presence; an existing native decision, including
explicit false, wins. A positive record for a feed not yet present after account
migration remains retryable until a later successful reconciliation.

### D9-B — Config Backup and Restore on iOS/iPadOS

Expose the existing Flux Config Backup contract through native iOS Settings:

- password-encrypted export;
- native file/share presentation;
- import/restore with validation and explicit failure presentation;
- safe account/Core replacement and widget/cache invalidation according to the
  existing architecture contract.

This is configuration backup, not article/media backup.

Implementation contract:

- iOS reuses the existing shared Core `ConfigBackupInput` /
  `parseConfigBackup` contract and `.fluxbackup` format; no second backup
  format or iOS-side cryptography implementation is introduced;
- export uses the authoritative Core `ConfigurationSnapshot` for
  `CoreSettings` and `FeedPreferences`, the native Keychain account/API key,
  and a versioned `IOSBackupSettingsV1` platform payload;
- the iOS payload contains current app-owned user configuration: startup scope,
  navigation visibility, read-on-scroll/remove-on-read behavior, article
  presentation/preview/date/count/click behavior, swipe actions, Bottom Action
  Bar priority, Debug Logging state, and custom HTTP headers;
- synchronized articles, downloaded media, Listening List/playback progress,
  pending mutations, support logs, caches, server-version presentation
  metadata, migration markers, transient list filters/sort, and per-instance
  WidgetKit AppIntent state are excluded;
- restore parses and authenticates the backup before any mutation, requires the
  iOS platform/schema, validates the complete native settings payload, and does
  not call Miniflux account validation or `/v1/version`;
- native iOS settings, Core configuration and Keychain credentials form one
  restore transaction. Failure during Core/account replacement restores the
  previous native settings, Core configuration and credentials;
- replacement quiesces the app-wide Core session and reuses the existing media,
  Newsreader and Core-replacement lifecycle hooks. Widget snapshot state is
  invalidated before replacement and rebuilt from the restored Core;
- a successfully applied restore is not rolled back if the subsequent normal
  sync fails; the UI reports that synchronization will be retried later;
- restore is reachable both from normal Settings and from the account-required
  startup surface so a fresh installation can adopt a backup without first
  creating a temporary account.

### D9-C — Configurable Bottom Action Bar

Restore the useful iOS toolbar configurability from FluxNews using semantic
native actions rather than persisted SwiftUI control identities.

**Sync** is fixed as the leading direct action and is not part of the persisted
user selection. **More** is fixed as the trailing fallback and is always
available.

The configurable priority list contains:

- Filter and Sort;
- direct All/Unread toggle;
- direct sort-order toggle;
- Search;
- Mark All as Read;
- Mark All as Read and Continue;
- Listening List;
- Now Playing;
- Settings.

The persisted order is the priority for direct presentation. Each adaptive
chrome mode exposes a bounded number of configurable direct actions; selected
actions that do not fit move into **More**. Relevant configurable actions that
the user did not select for direct presentation also remain available under
**More**. Contextually invalid actions are omitted rather than shown disabled:
Now Playing requires active loaded media, Mark All as Read is limited to article
scopes that support it, and Mark All as Read and Continue additionally requires
a following visible feed/category scope.

Action Bar Settings use an explicit Edit mode: selected actions may only be
removed or reordered while Edit is active. Adding an available action remains a
normal non-editing operation. Sync and More are shown as fixed explanatory
rows, not removable/reorderable selections.

The Flutter production migration consumes `iosToolbarActions` together with
`iosToolbarActionOrder` and maps semantic actions to the native priority list.
Existing native `articleListActionIDs` presence wins, including an explicitly
empty native selection.


The post-widget-configuration D9-A follow-up additionally imports Flutter's
global widget defaults when they have a direct semantic native equivalent:

- `widgetUnreadOnly` (with legacy `widgetNewsStatus` fallback) -> Unread / All;
- `widgetFilterType` + positive `widgetFilterId` -> All / Bookmarks /
  Category / Feed;
- `widgetSortOrder` -> Newest First / Oldest First.

These values are written only as an App-Group **legacy widget default seed**.
They initialize newly created native WidgetKit AppIntent configurations after
the production upgrade; WidgetKit remains the owner of every persisted
per-widget instance and an existing native seed wins. The legacy
`widgetOpenMiniflux`, widget item limit and widget background styling are not
migrated. Widget article taps continue to use the normal app/per-feed routing
policy.

This D9-A widget-default migration follow-up is COMPLETE / TEST-GATED.

Configuration must preserve the existing adaptive placement rules for iPhone
portrait, compact landscape, regular split presentation, and system
vertical-toolbar environments.

### D9-D — Localization parity required for replacement

The native iOS/iPadOS catalog preserves the FluxNews language set:

- English;
- German;
- Spanish;
- Galician;
- Dutch;
- Tamil;
- Turkish.

Localization remains native and Weblate-managed. This does not require carrying
forward obsolete Flutter-only strings or settings.

The binding D9-D completion scope is English and German. English is the source
language and is protected by the source-to-catalog regression contract; German
is the maintained completion translation. Spanish, Galician, Dutch, Tamil and
Turkish remain preserved additional locales. Their existing translations remain
intact, while `needs_review` values are deferred to the planned
Weblate/community localization workflow and do not block D9-D completion.

The post-D9 source-usage audit is authoritative for catalog membership and
runtime usage; see [IOS_LOCALIZATION_USAGE_AUDIT.md](IOS_LOCALIZATION_USAGE_AUDIT.md).
Xcode `extractionState` must not be used as a standalone deletion signal.


Implementation contract:

- `apple/ios/FluxNews/Localizable.xcstrings` remains the single native iOS
  String Catalog and English remains the source language;
- the production locale set is declared explicitly in the Xcode project:
  English, German, Spanish, Galician, Dutch, Tamil and Turkish;
- Xcode extraction state is not treated as a runtime-usage authority. Some
  productive SwiftUI/localized-string call sites are reported as `stale` by
  Xcode even though they remain reachable at runtime, so existing translated
  entries are preserved unless repository evidence proves they are obsolete;
- semantically identical historical Flutter translations were reused only when
  the English source match was unambiguous; native D5-D9 copy is translated as
  native copy rather than being force-mapped to obsolete Flutter wording;
- D9-D completion requires source-proven English catalog coverage and a
  translated German value for every productive key, including plural/variation
  entries and format placeholders;
- additional ES/GL/NL/TA/TR locale structures and existing translations remain
  preserved, but their `needs_review` entries are not D9-D completion gates;
- regression tests derive production usage from source rather than treating
  `extractionState: stale` as a usage signal, preserve locale structures, and
  verify translated variation paths/placeholders against the English source;
- future Weblate integration manages this same native catalog/workflow. D9 does
  not introduce a second localization store or resurrect Flutter localization
  files as runtime sources.

## 3. D9 Settings completion

### D9-E — Downloaded Data

Add a normal Settings destination for downloaded media storage.

Required information/actions:

- downloaded audio item/file count;
- total local downloaded-media storage size;
- destructive **Delete All Downloads** action with confirmation;
- refresh after transfer/deletion changes.

This is a storage-management surface over the existing D6/Core download model.
It must not create a second downloads library or duplicate Listening List state.

Implementation contract:

- Core owns the aggregate downloaded-media summary and bulk transition to
  `DeleteRequested`;
- `Downloaded` and `DeleteRequested` rows with a local file remain part of
  the storage summary until native deletion is acknowledged;
- iOS never deletes these files directly from Settings and instead reuses the
  D6 transfer/deletion reconciliation path;
- media currently protected by active playback remains deferred by the existing
  D6 deletion guard;
- Listening List membership and playback progress are not cleared by this
  action.

### D9-F — Miniflux account information and transport warning

Account/Settings must additionally expose:

- the detected Miniflux server version when available;
- a visible warning when the configured Miniflux server uses unencrypted
  `http://` rather than HTTPS.

HTTP remains supported where the existing account validation permits it; the
warning informs the user rather than changing transport ownership.

Implementation contract:

- the successfully detected Miniflux version is retained as non-sensitive,
  account-bound presentation metadata and restored for the same normalized
  server after app restart;
- failed replacement validation/activation does not overwrite the currently
  active account's retained version;
- the HTTP warning is presentation-only and is derived from the currently
  configured/edited server URL;
- failed validation technical information is exposed under **Connection
  Details**, not Developer Diagnostics.

### D9-G — Open Source and About

Settings must provide normal user-facing access to:

- the Flux project/source repository;
- app version/build information;
- About/legal information appropriate for the shipped native app;
- Miniflux/project attribution where retained by the product.

Developer Diagnostics is not a substitute for this normal user-facing
information.

Implementation contract:

- version and build are read from the shipped application bundle rather than a
  second settings-owned version constant;
- the original **FluxNews** repository is linked as the application project's
  long-term repository, because the native project is intended to move there;
- the current **Flux** repository remains linked for the existing native/shared
  Core development history;
- the BSD 3-Clause license and Miniflux project are directly reachable from the
  About surface;
- the retained project identity follows the original FluxNews values where
  still applicable: **Flux News**, Kevin Fechtel attribution, Miniflux project
  attribution and BSD 3-Clause licensing.

### D9-H — Logging & Support Diagnostics

Logging becomes a normal user/support Settings destination rather than a
Developer Diagnostics-only surface.

The existing `IOSAppDiagnostics` / `IOSAppLogger` implementation remains the
single native support-log store. D9 must not introduce a second log database or
duplicate Core/native logging path.

The Settings surface must provide:

- **Debug Logging** toggle using the existing persisted preference;
- current retained record count;
- **Log Viewer**;
- the existing diagnostics export through the native share/file flow;
- destructive **Clear Logs** with confirmation;
- concise privacy/retention explanation.

Normal Info/Warning/Error records remain available without Debug Logging.
Debug/Trace records are retained only while Debug Logging is enabled. Existing
bounded persistence, Core diagnostic bridging, unified logging mirroring, and
credential/custom-header redaction remain authoritative.

The Log Viewer must operate directly on the retained structured
`IOSAppLogEntry` records and provide at least:

- newest-first browsing;
- timestamp, level, category/module and message;
- text search across category and message;
- level filtering for Trace, Debug, Info, Warning and Error plus All;
- refresh/reload;
- copy of an individual record or its visible text.

The existing export remains the support handoff format and continues to include
retained native/Core records together with app version/build, OS version, device
class, Debug Logging state and record count. Export must remain privacy-sanitized.

A legacy **Clear Logs on Start** preference is not restored. The bounded native
support log and explicit Clear Logs action replace that Flutter-era behavior.

Implementation status:

- normal Settings now exposes **Support Diagnostics** backed directly by
  `IOSAppDiagnostics`;
- Debug Logging uses the existing persisted preference and retained record count
  is read from the same bounded store;
- the structured Log Viewer reads `IOSAppLogEntry` records directly, presents
  them newest-first, supports level filtering and Category/Message search,
  reloads on demand, and supports per-record copy;
- diagnostics export continues to use the existing privacy-sanitized support
  handoff and native Share presentation;
- **Clear Logs** requires destructive confirmation and clears only the retained
  support log;
- `DeveloperDiagnosticsView` no longer owns support logging/export controls and
  is reachable from Settings only in DEBUG/performance-diagnostics builds.

### Developer Diagnostics retirement

The current `DeveloperDiagnosticsView` is temporary development scaffolding and
must not remain a normal production Settings destination after D9.

Only the following durable support capability moves out of it:

- the complete Support Diagnostics/logging feature described in D9-H.

The remaining sections do **not** move into normal Settings:

- Rust Core status/smoke-test presentation;
- sandbox paths;
- legacy migration feasibility/probe output;
- Article Image Presentation metrics;
- Article Image Cache metrics;
- Timeline Performance counters/reset/print controls.

Those are development/performance instruments. They may remain compile-time
DEBUG/performance diagnostics where useful, but they are not production product
settings.

One related support affordance already lives outside the Developer Diagnostics
screen and should remain: failed account validation may expose technical
connection details under **Account**. Its user-facing label should be
**Connection Details** (or equivalent), not **Developer Diagnostics**.

Migration failures that require user action belong to the D9-A migration flow
with normal error/retry presentation; the legacy read-only probe itself does not
become a permanent Settings feature.

## 4. D9 Widget configuration extension

The existing D5 WidgetKit architecture remains authoritative: the extension is
credential-free, Core-free, database-free, and network-free and reads only a
versioned App Group snapshot plus bounded icon files.

D9 adds per-widget configuration for:

- **Read filter:** Unread / All;
- **Sort order:** Newest First / Oldest First.

The configured read filter applies inside the selected widget scope. For
Bookmarks, **All** means all starred articles represented by the retained widget
projection and **Unread** means unread starred articles.

The widget snapshot remains bounded. If `WidgetSnapshotV1` cannot correctly
represent both read filters and both sort directions for the supported widget
capacities, D9 must introduce a versioned backward-safe snapshot extension
rather than letting the WidgetKit extension query Core, SQLite, Miniflux, or
credentials directly.

There is intentionally **no widget-specific Open in Miniflux preference**.
Article taps already enter the main app's normal article-open path, which applies
the article/feed routing policy including the existing per-feed **Open in
Miniflux** setting. D9 must preserve that single routing authority.

Implementation contract:

- the original top-level `WidgetSnapshotV1` schema remains readable and keeps
  schema version 1; D9 adds an optional, independently versioned
  `ConfigurationProjectionV1` payload so older extensions ignore the new
  fields and newer extensions continue to decode old D5 snapshots;
- Core's widget read model remains bounded and now retains up to 12 candidates
  from both the newest and oldest end of each feed, with read-state-specific
  candidates as needed for Unread/All, plus bounded newest/oldest bookmark
  candidates;
- Core additionally supplies authoritative All counts globally and per
  feed/category plus unread-bookmark count; the existing unread/bookmark counts
  remain intact;
- the WidgetKit extension still reads only the App Group snapshot and icon files;
  it never opens Core, SQLite, Miniflux, credentials or the network;
- AppIntent configuration exposes Read Filter = Unread/All and Sort Order =
  Newest First/Oldest First per widget instance;
- legacy selections retain their prior defaults (Unread for normal scopes, All
  for Bookmarks). New AppIntent instances use explicit Unread and Newest First
  defaults;
- if a newly configured All/Oldest combination encounters an old D5 snapshot,
  the widget presents a bounded refresh-required state instead of pretending
  that the incomplete candidate set is authoritative.

## 5. Explicitly retired/replaced FluxNews behaviors

The following audited FluxNews behaviors are deliberately **not** D9 work.

### Feed-icon cache clear

No user-facing "Delete Feed Icons Only" control is required. Feed icons remain
regenerable cache and use the native/Core cache lifecycle.

### OLED / True Black

There is no Flux-specific OLED/True-Black toggle. Native iOS/iPadOS should use
system semantic colors, materials, and platform Dark Mode so OLED-capable
devices receive the best native dark appearance available without a separate
Flux setting.

This is an explicit product decision and replaces the legacy
`useBlackMode` preference.

### Legacy headline-placement toggle

The old `showHeadlineOnTop` option is not carried forward. The native article
views and frozen UIKit Timeline own the canonical content ordering/layout.

### Legacy paragraph and attachment-image preferences

The legacy per-feed `preferParagraph` and `preferAttachmentImage` settings
are not carried forward. Current Core/native article processing and image
selection remain authoritative.

### Image-cache duration

There is no user-configurable image-cache age. Native iOS manages the article
image path with bounded decoded-image caching, normal HTTP caching, memory
pressure/eviction, and implementation-owned cache policy. Cache tuning is a
native performance concern, not a product setting.

## 6. D9 acceptance contract

D9 is complete only when:

1. the production-identity Flutter-to-native migration path is validated on a
   physical device without destructive legacy conversion;
2. config backup/export and restore/import complete a tested native round trip;
3. Bottom Action Bar semantic configuration persists and remains correct across
   the existing adaptive iPhone/iPad layouts;
4. EN source coverage is protected by the source-to-catalog regression contract
   and DE has a complete production translation; preserved ES/GL/NL/TA/TR
   locales are deferred to the Weblate/community localization workflow;
5. Settings exposes downloaded-data count/size and Delete All Downloads;
6. widget instances can independently select Unread/All and
   Newest First/Oldest First while the extension remains Core/DB/network-free;
7. widget article taps continue to use the normal app/per-feed open policy with
   no widget-specific Miniflux destination setting;
8. Settings exposes Miniflux version, insecure-HTTP warning, Open Source, and
   About/version/legal information;
9. Settings exposes Debug Logging, a searchable/filterable structured Log
   Viewer, privacy-sanitized export, retained-record count and confirmed Clear
   Logs using the existing `IOSAppDiagnostics` store;
10. the production Settings hierarchy no longer depends on
    `DeveloperDiagnosticsView`; only normal Account connection details and the
    migrated logging/support surface remain user-facing;
11. no retired legacy toggle listed in this document is reintroduced;
12. the canonical Rust, native iOS and affected shared-Apple/macOS regression
    gates remain green.

After D9 acceptance, no known release-blocking Flutter replacement gap remains
unless a new concrete product or production-upgrade defect is discovered.
