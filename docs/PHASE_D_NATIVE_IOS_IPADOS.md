# Phase D — Native iOS/iPadOS

> **Status: D1-D5 COMPLETE / D6 IMPLEMENTATION STABLE & TESTVALIDATED — UX OBSERVATION WINDOW NON-BLOCKING / D7 COMPLETE & ARCHITECTURE-FROZEN / D8 DEFERRED — NOT REQUIRED FOR REPLACEMENT / D9 IMPLEMENTATION COMPLETE & PHYSICAL FLUTTER→NATIVE UPGRADE ACCEPTED / UIKIT TIMELINE U1-U5 COMPLETE / TIMELINE ARCHITECTURE FROZEN / AUTHORITATIVE PHASE-D CONTRACT**
>
> Phase A, Phase B, and Phase C are complete and architecture-frozen. Phase D
> replaces the existing Flutter iOS/iPadOS client with a native Swift client:
> a SwiftUI shell and a UIKit Article Timeline over the existing Rust Core and
> UniFFI boundary. The current native macOS implementation is the primary native
> reference. Flutter is only a
> behavioral reference for mobile-only capabilities and the legacy migration
> source; it is not a parity checklist and intentionally removed behavior must
> not be reintroduced without a product decision.
>
> Final replacement acceptance: the physical production upgrade completed
> successfully on 10 October 2026 and the canonical Apple regression workflow
> is green on main (Apple #123, attempt 2). No known Phase-D replacement blocker
> remains.
>
> Post-completion structural cleanup was merged on 11 October 2026. The former
> large `ArticleListView.swift`, `NewsreaderStore.swift`, and `ContentView.swift`
> implementation surfaces were split into focused iOS source files without
> changing Timeline behavior, state ownership, Core/UniFFI semantics, migration
> behavior, or the frozen UIKit architecture. PR #28 passed Apple CI before merge.
>
> Release/distribution scripting is tracked separately in
> [RELEASE_DISTRIBUTION.md](RELEASE_DISTRIBUTION.md). iOS already has archive and
> export building blocks, but they should be normalized into the shared release
> interface and continue to prepare App Store Connect artifacts for Transporter
> rather than making CI publication the primary distribution path.
>
> On 2026-09-11, the owner approved replacing the Article Timeline with an owned
> UIKit Timeline and native UIKit cells. The implementation initially used a
> `UICollectionView` baseline and later evolved to the current `UITableView`
> implementation during performance work. The current table-based Timeline is
> the accepted productive UI/UX baseline. U3 performance/correctness and U4
> mutation-worker semantics are complete and accepted. U5 behavior-preserving
> cleanup and final acceptance are also complete. The current UIKit Timeline
> container/rendering architecture is frozen. Fundamental container, layout,
> image-pipeline, Scrollover, or scheduling redesign now requires new reproducible
> device evidence of a concrete regression rather than speculative performance
> work. See [implementation handoff](IOS_UIKIT_TIMELINE_IMPLEMENTATION.md).

## 1. Goal and non-goals

Native FluxNews iOS/iPadOS minimum deployment target: 17.0.

Phase D delivers a first-class native iPhone/iPadOS FluxNews client without
creating a second domain layer in Swift.

The Rust Core remains authoritative for domain models, Miniflux networking,
SQLite persistence, sync/reconciliation, offline mutations, article/Reader
processing, search, notification candidates, widget projection, media domain,
playback progress, download intent/state, policies and retention.

The native Apple client owns SwiftUI/UIKit presentation, navigation, gestures,
visible snapshots, platform settings, Keychain access, browser/share behavior,
BGTaskScheduler execution, URLSession transfers, WidgetKit presentation,
UNUserNotificationCenter delivery, AVPlayer/AVAudioSession execution, Now
Playing/remote commands, CarPlay and ActivityKit.

Phase D does not rewrite existing Core functionality in Swift and does not make
Flutter storage or schemas permanent compatibility APIs.

## 2. Apple repository and sharing strategy

Target layout:

```text
core/
apple/
  shared/
    FluxApple/
  macos/
  ios/
docs/
```

Moving the current `macos/` tree under `apple/macos/` is a mechanical setup
step. macOS behavior must remain unchanged.

`apple/shared/FluxApple/` contains only genuinely reusable Apple integration and
presentation semantics. It must not become a second business/domain layer or a
durable state owner. Shared code is extracted on first real reuse rather than
through a speculative up-front refactor.

Strong reuse candidates already proven by the macOS implementation include
Browser presentation policies, Scrollover state/snapshot policy, Reader routing
semantics, widget snapshot/routing models, playback presentation/orchestration,
Now Playing/remote-command semantics and transfer reconciliation. Platform UI,
window geometry, lifecycle owners, AVAudioSession behavior and concrete transfer
executors remain platform-specific where appropriate.

## 3. Development, migration and release identities

Phase D uses two iOS identities during development:

- **Native Development:** a separate development Bundle ID and separate sandbox,
  allowing the native app and existing Flutter production app to be installed
  side by side on the same device.
- **Production/Upgrade Test:** the existing FluxNews production Bundle ID and
  entitlements, used to exercise the real Flutter-to-native update path.

The production Bundle ID and existing App Store product identity are retained
for the final native replacement. The exact development Bundle ID is an
implementation/configuration choice and must not leak into production data.

Upgrade feasibility is verified in D1 before deep product implementation:
existing production identity, App Group, Keychain access and required legacy
storage must be reachable by a native production-identity test build.

## 4. Legacy migration safety contract

Migration is **copy/import-only**.

The native app may read legacy Flutter data required for migration, but it must
not convert legacy storage in place, use the Flutter database as its operational
Core database, or aggressively delete legacy data. Imported state is written to
new native/Core-owned storage.

Migration must be idempotent and restart-safe. Existing valid native/Core state
wins over legacy state. A migration marker may record completed import work, but
must not make an interrupted migration unrecoverable.

Migrate when semantically compatible and not reconstructable from Miniflux:

- account association and credentials;
- custom HTTP headers;
- compatible native/Core settings;
- compatible feed preferences;
- podcast/download settings that still exist;
- playback progress;
- existing downloaded media with correct enclosure association.

The Flutter `autoDownloadAudioAfterSync` implementation is not ported: native
Core retains its Listening List-triggered policy. Its stored user intent is,
however, migrated to `autoDownloadListeningList` during D9-A because both mean
that audio intended for listening should be downloaded automatically.

Do not migrate the Flutter article/feed/category cache, widget cache/snapshots,
temporary UI/runtime state, the old explicit Light/Dark choice, or obsolete
Flutter-only preferences. Synchronized read/unread/starred state is rebuilt via
Miniflux/Core rather than copied from Flutter SQLite.

The current Core `FeedPreferences` model is authoritative. Legacy Flutter fields
without a current semantic equivalent do not justify a compatibility layer.

## 5. Adaptive iOS/iPadOS product architecture

Flux is one adaptive iOS/iPadOS application, not separate iPhone and iPad
applications. Available presentation environment and platform capability are
authoritative for layout; device name is not.

### Compact presentation

In compact presentation, the app starts directly in the Article List.
Navigation is transient and opens as a native sheet containing All News,
Starred, Categories and Feeds plus auxiliary Search and Listening List actions.
Selecting a News scope closes the sheet and updates the Article List. Search and
Listening List instead open their own native fly-over sheets without changing
the selected News scope.

### Regular presentation

In regular presentation, navigation and the Article List may coexist in a
two-column `NavigationSplitView`:

```text
Navigation | Article List
```

There is no permanent third article/detail column. The existing article-first
behavior remains: a normal article tap tries the configured installed-app deep
link and falls back to the in-app browser. The internal Reader is an explicitly
configured exception and is temporary presentation: an inspector in regular
presentation and a sheet/full-screen presentation in compact presentation.

Presentation may change at runtime as available environment changes. This does
not create a second app hierarchy or replace BrowserScope, article snapshots,
filters, Core session, read/starred state, or Search domain state. iPhone,
iPhone Duo, iPad, and future form factors fall out of this compact/regular model
without dedicated UI implementations.

The adaptive app shell keeps one persistent split/detail hierarchy across these
transitions. Its detail Timeline remains in place while only column visibility
and transient navigation presentation normalize. Entering regular presentation
dismisses transient navigation; Search and Reader retain their request state and
move to the appropriate native presentation without another Core request.

### Scene ownership

The first native iOS/iPadOS release intentionally supports one app scene. The
app-level `CoreBootstrapper` and `NewsreaderStore` own the account/Core session,
Core event subscription, Sync state, and serialized Scrollover mutation worker.
The scene owns its presentation state and Search request state; Timeline
controllers remain view-local. Article-image caching and HTTP loading are
process-global native presentation infrastructure.

Multi-scene support is deferred. It requires an app/account service that owns
the shared Core session, subscriptions, synchronization, mutation coordination,
and future media playback independently of per-scene presentation stores. Do not
enable additional scenes until that boundary exists; a second scene must not
create another Core against the same storage paths or share another scene's
presentation state.

### D7 CarPlay scene amendment — 25 September 2026

D7 does not enable a second independent phone/application scene. CarPlay adds a
dedicated `CPTemplateApplicationScene` presentation role whose delegate attaches
to the existing process-scoped `IOSAppRuntime.shared` / `IOSMediaRuntime`. It
must not create another Core, `IOSMediaRuntime`, AVPlayer, AVAudioSession owner,
or durable playback state. Disconnecting the CarPlay scene destroys CarPlay
presentation state only; the app-scoped media runtime remains authoritative.

The detailed D7 ownership, API, entitlement, implementation, test and real-device
acceptance contract is [IOS_D7_NOW_PLAYING_REMOTE_COMMANDS_CARPLAY.md](IOS_D7_NOW_PLAYING_REMOTE_COMMANDS_CARPLAY.md).

### iOS/iPadOS Article Timeline — UIKit

The target Article Timeline is an owned UIKit view controller containing a
plain `UITableView`, embedded through a narrow bridge in the SwiftUI app shell.
Use stable Article IDs, a diffable table data source, deterministic prepared row
heights, and native reusable UIKit article cells. Compact and visual modes, portrait/landscape image slots,
preview-line choices, Dynamic Type, VoiceOver, and adaptive compact/regular
presentation remain supported. Cell structure and content sizing are reused
when their layout inputs have not changed.

The Timeline must not use SwiftUI `List`, `ScrollView`/`LazyVStack`, or hosted
SwiftUI article cells as its production renderer. Navigation, Settings, Reader,
Search, sheets, and other surfaces may continue using SwiftUI. Use public UIKit
APIs; do not take over the internal delegate of a SwiftUI control through
introspection. Retire the old Timeline path after the replacement is integrated.

Available table-container geometry is the Timeline layout authority; device
identity, screen dimensions, and orientation names are not inputs. A canonical
pixel geometry generation includes the effective table width and the
environment values that affect deterministic item layout. Geometry changes make
visible cells correct immediately and establish a fresh Scrollover baseline, but
coalesce only speculative prepared-layout work for the latest generation. Older
generation results cannot be consumed as current layout. Relayout alone is never
user scrolling and must not mark an article read. Image prefetch retains its
existing canonical target-size bucket across a resize when possible, without
changing visible-first or bounded scheduling behavior.

Timeline actions use system-native swipe actions under the shared mobile interaction contract: each side supports zero, one, or two configured semantic actions in inner-to-outer order, and the outer action is the deliberate full-swipe action. The established defaults remain Read/Unread and Star/Unstar. These actions invoke the existing optimistic mutations and identify articles by stable ID. Preserve context menus, pull-to-refresh,
article routing, the accepted native scope-capsule navigation chrome, semantic
scope resets, and persistent split navigation. Actions identify articles by stable ID, never a captured
index path or a cell reference that may have been reused.

Mark-as-Read-on-Scrollover uses actual UIKit scroll movement and resolved cell
frames in one coordinate system, including effective viewport insets and
occlusion. A non-observable detector consumes a coherent layout/movement sample
from the controller. It emits an ID only when an observed visible unread row
becomes completely above the effective upper boundary during a user-originated
forward interaction or deceleration. Preparation/prefetch, `willDisplay`, or
`didEndDisplaying` alone does not prove a valid crossing. Unseen rows skipped by
a fast movement must not be manufactured as read candidates.

Candidate processing is bounded by currently/recently visible rows, not the
complete snapshot or accumulated history. Preserve enough prior resolved
geometry to recognize a just-exited row after reuse. Direction reversals must
not lose qualified crossings through stale callback order; small movements
must accumulate rather than disappear under a per-sample tolerance. No exposure
timers, fixed delays, or SwiftUI row/scroll callback ordering may determine a
read crossing.

Snapshot, layout, size, inset, and reset changes establish a fresh geometric
baseline without emitting reads. Keep actual interaction/deceleration state
separate from baseline validity so a layout change cannot silently disable the
rest of an ongoing gesture. Programmatic movement and scroll-anchor correction
do not qualify reads. A genuine forward arrival at the content bottom may
complete observed visible trailing rows that cannot cross the upper boundary.
This completion belongs only to that arrival and valid layout; leaving the
bottom, reversing direction, ending the interaction, or changing the baseline
disarms it. Initial short lists and initial/reset/backward arrivals do not
complete rows. The layout and viewport used to decide bottom arrival must be
consistent with those used to identify the trailing visible rows.

Remove When Read applies to explicit/manual read actions, including swipe and
context-menu actions. It does not apply to Mark-as-Read-on-Scrollover:
Scrollover updates read state without changing visible article list membership,
including after scrolling becomes idle. The unread/read visual transition keeps
the unread-indicator layout slot present and changes only its visual opacity, so
it does not alter article-card geometry.

iOS Scrollover keeps sensing, detection, cell status, Core scheduling, and Undo
separate. Accept an ID into a deduplicated native intent buffer with a local
status overlay; rendering must not wait for Core. A fully exited row requires
no visible update. A visible/reappearing cell obtains the latest status by ID
and updates only its status, accessibility, and interaction state. Status-only
read/starred changes must not apply a full diffable snapshot, reload the Timeline,
reconfigure all cell content, invalidate text/image layout, or change row height.
An explicit manual action that removes an article under the existing rules is
a separate structural update; it must not turn ordinary Scrollover into removal.

One serialized mutation worker belongs to the account/Core session rather than
the Timeline view or its presentation snapshot. Reuse the current Core bulk
operation, with an actual maximum of 64 IDs per call, deduplication, ordered
continuation, and a bounded maximum wait before attempting to drain a small
buffer. Idle and lifecycle transitions request additional flushes; continuous
scrolling alone must not defer local persistence indefinitely. Batching time
controls persistence scheduling, never exposure qualification. Blocking UniFFI
calls execute off-main without synchronously waiting on the UI thread.

Capture origin presentation generation and per-article read-intent ordering at
enqueue time, and preserve them when splitting/coalescing batches. A scope,
filter, snapshot, or view change preserves accepted writes but invalidates old
presentation feedback. Newer explicit Read/Unread/Undo actions must win over
older automatic writes and completions. An account/session boundary must never
send old IDs to a new Core; session shutdown and foreground-to-background
handling must explicitly account for pending local persistence. Starting a Task
is not proof of a durable flush, and an uncommitted write cannot be guaranteed
after abrupt process termination. Rust remains the only durable state owner.
Explicit Unread/Undo re-arms the affected article for a new genuine qualified
crossing; a status callback or rebaseline alone must not immediately read it again.

Counts and Undo publish independently of structural list snapshots and avoid
scroll-frequency work. Ignored Core events must be filtered before creating
main-thread tasks. Feed icons and article images arrive as prepared images;
decoding, network access, and synchronous Core queries are not cell/scroll work.
All detected Scrollover candidates are still marked read, independently of Undo.
Search results use the same UIKit Article Timeline renderer and presentation
settings as the normal Article List, with Search-specific pagination and
Scrollover disabled.
Normal continuous scrolling and small forward jumps do not present Undo. Undo is
an exceptional recovery mechanism: it activates only after at least 3 successful
unread-to-read Scrollover mutations in a rolling one-second window. Visibility
candidates, already-read rows, rejected candidates, failed mutations, and the
former skipped-index qualification do not count. When the third success arrives,
the qualifying burst is retained together for Undo; later successes follow the
existing rolling group. A success extends its 4-second inactivity window without
extending the 15-second maximum group lifetime. Backward movement, initial baseline
establishment, and structural rebaselining emit neither reads nor Undo. macOS
retains its existing platform-specific frame integration.

Visual article images are native iOS presentation infrastructure, not Core or
sync state. They use display-sized ImageIO downsampling, normal HTTP response
caching, and bounded in-memory caching of decoded images. Loading, failure, and
success presentation remain inside the existing fixed portrait or landscape
image slots and must not change article-card geometry. Recreating an article
image view reuses an already-decoded memory-cache image synchronously so
snapshot refreshes do not regress to a placeholder frame.
Reuse this pipeline from UIKit with ID/request-safe completion and bounded,
cancellable prefetching. Planning must respond to changes in the relevant
visible/prefetch window or target size, not rescan visited rows on every pixel
of movement. A prefetch cancellation must not cancel an image still required by
a visible cell or another consumer.

This renderer decision is accepted without requiring a preliminary
SwiftUI-versus-UIKit benchmark or optimization of the old renderer. Focused
device profiling is acceptance of the new implementation. The implementation
sequence and regression matrix are in
[IOS_UIKIT_TIMELINE_IMPLEMENTATION.md](IOS_UIKIT_TIMELINE_IMPLEMENTATION.md).

#### Current UIKit Timeline amendment status — 22 September 2026

U1-U4 are complete. U3 is real-device accepted on iOS 27 with the normal
full-width Visual presentation, stable rotation/chrome/status-bar behavior, and
the single ImageIO -> UIImageView/Core Animation article-image path. The legacy
exact-slot renderer and its diagnostic switches are removed. The canonical
post-retirement XCTest run executed 348 tests with 0 failures.

U4 session-owned mutation-worker semantics remain complete: one active
Core/account-session writer, 64-ID FIFO batches, a 500 ms bounded drain deadline,
explicit-intent precedence, lifecycle coalescing, session-isolated completion,
and deterministic failure recovery.

U5 behavior-preserving cleanup and final acceptance are complete. The
historical SwiftUI/List Scrollover controller and its helper geometry have been
removed; still-relevant regression cases exercise the productive
`IOSUIKitScrolloverGeometryTracker`; productive Scrollover geometry is isolated
in its focused source file; and the UIKit cell consumes prepared
`IOSUIKitArticleLayoutMetrics` directly rather than a redundant cell metrics
wrapper. Focused native full-swipe and article-cell accessibility oracles are
present. Final validation on 22 September 2026 executed 338 iOS tests with
0 failures, `build-app.sh` succeeded, `git diff --check main...HEAD` was clean,
and U5 was accepted as a behavior-preserving cleanup. The UIKit Timeline
architecture is now frozen.

#### Article-image renderer decision — 20 September 2026

A new physical-device A/B comparison was run after the presentation scheduler,
offscreen-image-prefetch removal, obsolete-work cancellation, and serialized
image-transform changes. On the iPhone 15, both paths still showed very rare
residual hitches, but the ImageIO -> UIImageView/Core Animation path was
subjectively somewhat smoother than the additional exact-slot CGContext
renderer. The exact-slot renderer was therefore retired after U3 acceptance.

## 6. Native media and platform integration

Phase D media uses the shared Rust media domain and the existing app-scoped
native playback/transfer runtime. Swift owns native execution; Rust/Core owns
durable media state and policy.

D6 establishes one app-wide `IOSMediaRuntime` below `IOSAppRuntime`. It owns the
single `IOSMediaPlaybackCoordinator`, the single `IOSMediaPlaybackPresentationState`,
the native AVPlayer engine, AVAudioSession lifecycle and background transfer
coordinator. Downloaded and remote media use this same playback stack.

`IOSMediaPlaybackPresentationState` is the stable live projection for platform
integrations. It contains the loaded enclosure, feed/media title, artwork source,
chapters, status, position, duration, playback source, loading/buffering/error
state and playback rate. D7/D8 integrations consume this projection rather than
SwiftUI player geometry or controls.

AVAudioSession integration covers background audio, interruptions, route
changes, Bluetooth/AirPlay and appropriate resume behavior. Core checkpoints,
completion/restart and Miniflux `media_progression` reconciliation remain D6
semantics and are not reimplemented by D7.

`MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` use the same playback state
as the in-app player. CarPlay is another native presentation over this same
playback stack, not a second player or legacy download cache. Required CarPlay
scope includes browsing playable/listening items, selecting an episode,
starting playback, play/pause, skip and current playback presentation.

D7-A through D7-G are complete, automated-test validated, and real-device
accepted. This covers the shared Apple Now Playing projection, iOS Now Playing
adapter, remote commands, system playback acceptance, CarPlay scene/browsing,
CarPlay playback integration, and final physical-device CarPlay acceptance.
The detailed contract is
[IOS_D7_NOW_PLAYING_REMOTE_COMMANDS_CARPLAY.md](IOS_D7_NOW_PLAYING_REMOTE_COMMANDS_CARPLAY.md).
The D7 architecture is frozen; changes require a new concrete regression or
product requirement.

D7 must not expose Stop, next/previous episode, autoplay, or queue semantics
without an explicit product/domain contract. Stop remains an in-app D6 lifecycle
operation; remote Play/Pause/Toggle/skip/seek operate through the existing
playback coordinator. CarPlay browsing is Core-backed Listening List content,
not a filesystem/download-cache scan.

D8 ActivityKit/Dynamic Island remains outside D7, but may consume the same stable
playback projection later.

## 7. D4/D4.5 manual sync contract

Manual foreground Sync must become explicitly cancellable by the user. This is
a Newsreader interaction and therefore remains in D4 rather than being deferred
to D5 background scheduling.

The product contract is:

- when idle, the Sync control starts a manual Sync;
- while manual Sync is running, that control changes into a clear Cancel/Stop
  action rather than becoming disabled;
- the scope capsule continues to present `Syncing…` while the Sync is active;
- cancellation returns the capsule to the current count and does not present the
  normal successful-Sync confirmation;
- user cancellation is a normal outcome, not a Sync/network failure, and must
  not surface an error alert;
- accessibility label/value/action state must track Start Sync versus Cancel Sync;
- already committed durable work remains valid; cancellation must not roll back
  successfully delivered mutations or otherwise corrupt local/Core state;
- completion from a cancelled or superseded Sync must not publish stale success,
  counts, snapshot replacement, notifications, or other presentation into a newer
  Sync generation;
- background Sync remains separately governed by D5 and is not made
  user-cancellable merely by implementing this foreground control.

A real cancellation requires a cooperative Rust/Core boundary. Cancelling only
the Swift task is insufficient because the current Apple execution contract can
prevent queued Core work from starting but cannot interrupt synchronous Rust
network I/O once it is running. The Core Sync path therefore needs a
session/run-scoped cancellation signal checked at safe phase and bounded-work
boundaries. Network operations that cannot be interrupted mid-call may finish
their current bounded request, but no further cancellable Sync work should begin
after cancellation is observed.

Tests must cover cancellation before Core work starts, cancellation during each
safe Sync phase, a late completion racing a cancelled generation, immediate
restart after cancellation, failure-versus-cancellation presentation, and
preservation of already durable mutations/state. Real-device acceptance must
verify that cancelling and immediately restarting Sync leaves the Timeline,
scope count, capsule, and Sync control coherent.

D4.5 implementation began only after the UIKit Timeline/presentation change
set was accepted on device and U5 was closed. D4.5-A, D4.5-B, and D4.5-C are
complete.

**D4.5-C — UniFFI + AppleCoreExecution is COMPLETE.** The UniFFI layer exports
a run-scoped `SyncCancellation` object, explicit
`SyncOutcome::Completed/Cancelled`, and an additive cancellable Sync entry
point while preserving the existing `sync(reason)` API. `AppleCoreExecution`
adds a blocking cancellable lane operation: cancellation before execution still
prevents queued Core work from starting; cancellation after execution begins
invokes the supplied cooperative cancellation callback exactly once and does not
release the OperationQueue worker until the synchronous Core closure actually
returns. Focused tests cover both queued and running cancellation semantics.

D4.5-C validation on 23 September 2026 completed with `cargo fmt --check`
clean and `cargo test --workspace` green: 216 `flux-core` tests and 6
`flux-uniffi` tests passed with 0 failures, plus all workspace doc-tests.
The native iOS gate then executed 340 tests with 0 failures and the native app
build succeeded.

## 8. D5 background execution

D5 is complete and architecture-frozen. Native iOS owns BGTaskScheduler,
WidgetKit and UNUserNotificationCenter execution over Core projections and
candidates. Background Sync never creates a second Core/session or media runtime.

The D5 `IOSMediaTransferReconciliationHandoff` remains the authoritative bridge
from successful background Sync into the D6 transfer runtime. D6 installs the
native transfer executor and backs `BrowserScope.listeningList` with the Core
Listening List read model.

D5 widget and notification ownership remains unchanged by D7. D9 may add
per-instance widget read-filter/sort configuration and, if necessary, a
versioned bounded snapshot extension, without moving Core/database/network or
credential access into the WidgetKit extension.

## 9. D6 native media status

D6 is implementation-stable and testvalidated. Its remaining observation window
is UX/presentation-focused and does not block D7. Playback/runtime ownership is
stable enough to be consumed by D7.

D6 presentation polish may continue in `IOSMediaPlayerView`, Listening List,
chapter/show-notes/download presentation and related SwiftUI surfaces. D7 must
not depend on those views' geometry, action placement, buffering-ring design, or
presentation hierarchy.

The accepted in-app mini-player presentation is adaptive and remains a native
iOS presentation concern over the single D6 playback runtime: compact iPhone
portrait integrates Now Playing into the Article List bottom dock, compact
landscape presents a reduced Now Playing control in the top navigation chrome,
persistent iPad split navigation presents it as a sidebar footer, and a
collapsed persistent split uses the compact top control. The mini player is
visible for loaded paused/playing media, disappears for stopped playback, opens
the existing full player, and replaces the former configurable Article List
`Now Playing` action. iOS 26+ may use system glass presentation while older
supported releases retain a material fallback; this does not introduce a
TabView/UITabBarController dependency.

D6 runtime semantics remain authoritative: Play/resume, Pause checkpointing,
Stop checkpoint/retain/release-audio-session, seek/skip, natural completion,
restart, local/remote source resolution, playback rate, sleep timer, chapters,
artwork, background audio, cross-device progression reconciliation and download
protection all remain owned by the existing D6 stack.

## 10. Phase sequence

### D1 — Foundation & Migration Spike

Complete.

### D2 — Adaptive Shell & Settings

Complete.

### D3 — Native Timeline / Article Presentation

Complete; UIKit Timeline U1-U5 is architecture-frozen.

### D4 / D4.5 — Actions, Sync, Cancellation

Complete.

### D5 — Background Sync, Notifications & Widgets

Complete and architecture-frozen.

### D6 — Native Media & Background Downloads

Implementation-stable/testvalidated. UX observation window remains active; it
does not block D7.

### D7 — Now Playing, Remote Commands & CarPlay

Complete and architecture-frozen. The native app uses the single D6 playback
runtime for Now Playing, remote commands and CarPlay. D7-A through D7-G are
automated-test validated and real-device accepted, including CarPlay Listening
List/feed filtering/navigation/Now Playing and system Now Playing, Dynamic
Island, and Lock Screen behavior. See
[IOS_D7_NOW_PLAYING_REMOTE_COMMANDS_CARPLAY.md](IOS_D7_NOW_PLAYING_REMOTE_COMMANDS_CARPLAY.md).

### D8 — Live Activities & Dynamic Island

Deferred and removed from the current native replacement completion path. The
system Now Playing experience already supplies the appropriate audio presentation
on supported Dynamic Island devices. A custom ActivityKit lifecycle may only be
reopened for a distinct future live-state product requirement. See
[IOS_D8_ACTIVITYKIT_DECISION.md](IOS_D8_ACTIVITYKIT_DECISION.md).

### D9 — Flutter Replacement Completion / Legacy-Parity Closure

Implementation and physical production-upgrade acceptance are complete. All
planned D9 blocks are complete and test-gated: production migration, config
backup/restore, configurable Bottom Action Bar, retained localization set,
downloaded-data management, widget Unread/All plus Newest/Oldest
configuration, final Settings account/about information, and production
logging/support diagnostics with a native log viewer and export.

On 10 October 2026 the production-identity TestFlight upgrade path completed
successfully on a physical iPhone. Legacy downloads were recovered from the
Flutter audio cache, including artwork extraction, and the migration completed
green while explicitly reporting stale historical playback positions that had
no local download and returned confirmed 404/410 from Miniflux. Such stale
positions are intentionally discarded rather than creating ghost Listening List
items. Existing native playback/download state and Flutter source data remain
untouched.

D9 therefore has no remaining iOS feature or physical-upgrade blocker. The
canonical Apple/Rust regression gate remains mandatory whenever later shared
changes touch the iOS path. D9 also records the intentionally retired/replaced
behaviors so they are not reintroduced later as accidental parity work. See
[IOS_D9_FLUTTER_REPLACEMENT_COMPLETION.md](IOS_D9_FLUTTER_REPLACEMENT_COMPLETION.md).

## 11. Release/acceptance invariants

1. Rust/Core remains the durable authority for domain, playback progress,
   downloads and policy.
2. There is exactly one app-scoped native iOS media/playback runtime and one
   AVPlayer execution stack.
3. Now Playing, remote commands, CarPlay and later ActivityKit are projections
   or command adapters over that runtime; none owns durable playback state.
4. The UIKit Timeline architecture remains frozen and is not touched by D7.
5. D6 UI polish remains independent of D7 integration.
6. CarPlay is release-blocking and requires signed entitlement plus physical
   acceptance; Simulator-only evidence is insufficient.
7. Shared Apple code contains only genuinely common semantics/policies, never a
   second domain or lifecycle owner.
8. Potentially blocking Rust Core work must not execute on `MainActor` or a
   Swift cooperative executor. `MainActor` owns native presentation inputs,
   request lifecycle, and state publication; a bounded Apple worker policy owns
   synchronous Core/UniFFI closure execution. Separate responsive/local and
   blocking/remote lanes prevent network work from head-of-line blocking local
   reads and mutations. Existing request/session generations still decide whether
   results publish. Swift cancellation may prevent queued work from starting, but
   does not cancel already-running synchronous Rust network I/O. CPU-only
   detached image/layout work is outside this policy; Timeline bounded-query and
   pagination work remains separate.