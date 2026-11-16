# FluxNews iOS / iPadOS Contract

> **Status: ACTIVE / AUTHORITATIVE**
>
> This document carries forward the durable iOS/iPadOS product and platform
> contracts from the completed Phase-D implementation. Historical implementation
> sequencing and acceptance evidence are preserved separately.
>
> Transfer mapping:
> - `PHASE_D_NATIVE_IOS_IPADOS.md` sections 1–9 → foundations, adaptive UI,
>   Timeline, media, manual sync and background execution below.
> - `IOS_D4_FOLLOWUP_FINDINGS.md` sections 1–7 → accepted settings/actions,
>   rebuild, diagnostics and retired behavior below.
> - `IOS_UIKIT_TIMELINE_IMPLEMENTATION.md` architecture/performance-sensitive
>   rules and frozen U3/U4/U5 boundaries → UIKit Timeline section below.
> - `IOS_D7_NOW_PLAYING_REMOTE_COMMANDS_CARPLAY.md` ownership, command and
>   CarPlay rules → system media section below.
> - `IOS_D8_ACTIVITYKIT_DECISION.md` → ActivityKit decision below.
> - `IOS_D9_FLUTTER_REPLACEMENT_COMPLETION.md` durable backup, action-bar,
>   localization, settings, widget and retired-behavior rules → replacement
>   product contract below.
>
> This transfer does not reopen D1–D9, U1–U5 or production-upgrade acceptance.
> K12 article-image/cache ownership is intentionally not resolved here; existing
> wording is carried forward without choosing a new owner.
>
> Shared mobile semantics remain authoritative in
> [`../../MOBILE_PRODUCT_SEMANTICS.md`](../../MOBILE_PRODUCT_SEMANTICS.md);
> shared media/Core semantics remain authoritative in
> [`../../current/MEDIA_CORE.md`](../../current/MEDIA_CORE.md).

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
acceptance contract is [IOS_D7_NOW_PLAYING_REMOTE_COMMANDS_CARPLAY.md](../../acceptance/ios/IOS_D7_NOW_PLAYING_REMOTE_COMMANDS_CARPLAY.md).

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
[IOS_UIKIT_TIMELINE_IMPLEMENTATION.md](../../archive/phases/ios/IOS_UIKIT_TIMELINE_IMPLEMENTATION.md).

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
[IOS_D7_NOW_PLAYING_REMOTE_COMMANDS_CARPLAY.md](../../acceptance/ios/IOS_D7_NOW_PLAYING_REMOTE_COMMANDS_CARPLAY.md).
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


---

## Accepted D4 follow-up product rules

## 1. Rebuild Local State — COMPLETE

D4.1 already requires **Rebuild Local State** and **Remove Account** as distinct
operations. Remove Account exists in native iOS; Rebuild Local State is still
missing from the native iOS orchestration and UI even though Core/UniFFI already
provide the operation.

Implementation contract:

- Add **Rebuild Local State** to native iOS Account settings with an explicit
  confirmation step.
- Preserve Miniflux account association, Keychain credentials, global
  Core/native settings, and compatible account/feed preferences.
- Destructively clear reconstructable synchronized local state, pending
  mutations, notification bookkeeping, sync metadata, and regenerable caches as
  defined by the Core contract.
- Invalidate stale widget/cache projections before the rebuild.
- Immediately perform the Core-owned fresh Miniflux rebuild/sync.
- If that fresh sync fails, do not restore the discarded old synchronized
  dataset.
- Use the existing app-wide Core-session quiescence/execution coordination so
  account/session work cannot race the destructive rebuild.
- Do not reinterpret Rebuild Local State as Remove Account or as a general
  Factory Reset.

Implementation status:

- Native iOS Account Settings now exposes the confirmed Rebuild Local State action.
- `CoreBootstrapper` coordinates the operation without replacing the active
  Core or credentials.
- The app-wide Core-session gate enters quiescence first and holds the
  destructive `rebuildLocalState()` call as an exclusive blocking operation.
- Widget and Newsreader projections are invalidated before the rebuild and
  reattached to the same Core afterward, on both success and synchronization
  failure.
- Focused AccountLifecycle tests cover credential/Core preservation, app-wide
  quiescence, and failure recovery.
- 

## 2. Native iOS mutation delivery mode — COMPLETE

The Rust Core already supports `DeliveryMode::Live` and
`DeliveryMode::Deferred`. Native iOS Read/Unread and Star/Unstar mutations,
including Scrollover bulk Read mutations, already use the Core
mutation/pending-delivery path.

Product decision:

- Native iOS defaults to **Live** mutation delivery.
- Add a native Settings switch that allows the user to disable immediate
  delivery. Disabled maps to the existing **Deferred** mode.
- The iOS default must be established at the iOS product boundary; do not change
  the global Rust Core default solely for iOS.
- The chosen value must persist across launches. A one-time iOS initialization
  must not later overwrite an explicit user choice.
- Local persistence remains authoritative and immediate; UI/count/widget
  feedback must not wait for the network.
- Live means attempting delivery of the already-persisted pending mutation to
  Miniflux immediately. It must not start a Full or Delta sync merely to deliver
  the mutation.
- Retryable remote/network failure leaves the mutation durably pending for the
  existing retry/reconciliation path.
- Scrollover keeps the accepted U4 worker contract: session-owned
  serialization, deduplication, maximum 64 IDs per Core bulk call, 500 ms
  bounded drain deadline, ordering/precedence, and failure recovery. Live mode
  must not become one Swift-side network request per crossed article.

This is a D4/U4 contract completion/configuration item, not a new sync
architecture.

Implementation status:

- Native iOS applies `DeliveryMode::Live` once as an iOS product default on the
  first native activation.
- A persisted iOS migration marker ensures later launches never overwrite an
  explicit user choice.
- Articles Settings exposes **Sync article changes immediately**.
- Enabled writes the existing Core `Live` mode; disabled writes `Deferred`.
- Reads and writes go through the existing app-wide Core-session execution gate.
- No Rust Core default was changed and no separate Swift delivery-mode state was
  introduced.
- The existing Core mutation path remains authoritative, so failed immediate
  delivery stays pending and no extra Full/Delta Sync is introduced.
- Focused tests cover first-start Live defaulting, preservation of explicit
  Deferred choice on later startup, and direct Core-backed preference reads and
  writes.
- 

## 3. UIKit Timeline swipe actions — COMPLETE

The fixed one-action-per-side implementation is incomplete relative to the
authoritative mobile interaction contract.

Implement the existing documented contract from `MOBILE_PRODUCT_SEMANTICS.md`:

- zero, one, or two configured semantic actions per side;
- inner-to-outer visual ordering;
- the outer action is the deliberate full-swipe action;
- partial swipe reveals actions without executing them;
- reversing direction crosses the neutral state before the opposite side;
- defaults retain the established Read/Unread and Star/Unstar semantics;
- action execution resolves the article by stable Article ID, never by a
  captured index path/cell.

Expose the configuration through native iOS Settings. This is interaction and
presentation configuration only and does not reopen the frozen Timeline
architecture.

Implementation status:

- Native iOS persists one semantic swipe configuration with zero, one, or two
  actions per side.
- Settings expose a **Full Swipe** slot and an optional **Additional Action**
  slot for leading and trailing sides.
- Stored order remains semantic inner-to-outer; the UIKit adapter reverses that
  order only at the native API boundary so the configured outer action is
  UIKit's first/full-swipe action.
- The established defaults remain leading Read/Unread and trailing Star/Unstar.
- Currently selectable actions are Read/Unread, Star/Unstar, Open Original,
  Open in Miniflux, Open Comments, Share, and Save to Third-Party Service.
- Open Comments is omitted for an individual row when that article has no valid
  comments URL.
- Search results consume the same persisted swipe configuration as the normal
  Article Timeline.
- The legacy **Download Audio** swipe action is intentionally not exposed yet:
  native iOS does not have the D6 media/download handler at this phase. D6 may
  add that semantic action to the existing configuration without changing the
  swipe architecture. No placeholder/no-op action is permitted.
- Focused tests cover 0-2 action normalization, duplicate suppression,
  persistence, outer/full-swipe mapping, and conditional action omission.
- 

## 4. Missing Core-backed article/settings controls — COMPLETE

Native iOS Settings must also expose the already-supported Core settings:

- **Read Article Retention**: 30 / 60 / 90 / 180 / 365 days.
- **Reader detail/truncation character limit**: 5,000 / 10,000 / 20,000
  characters, retaining the Core default of 10,000 unless the user chooses
  otherwise.

These are Settings-surface completions over existing Core capabilities; do not
duplicate the values in a second Swift domain model.

Implementation status:

- Native iOS Articles Settings now exposes Read Article Retention with the
  existing Core values 30 / 60 / 90 / 180 / 365 days.
- Native iOS Articles Settings now exposes the Reader detail/truncation limit
  with the existing Core values 5,000 / 10,000 / 20,000 characters.
- Both preferences are read directly from `coreSettings()` and written through
  the existing Core setters behind the app-wide Core-session execution gate.
- No duplicate Swift persistence/domain setting was introduced.
- The Core defaults remain authoritative when the user has not changed either
  value.
- Focused tests cover reading and writing both settings against the real Core.
- 

## 5. Configuration backup/restore — COMPLETE IN LATER PHASE-D WORK

At the time of this D4 follow-up, configuration backup/restore was deliberately
deferred until the Settings surface stabilized. That deferral is historical.

The later Phase-D/D9 implementation completed native iOS encrypted
configuration export/import using the shared versioned Core backup envelope plus
the platform-local settings payload. The production Settings surface exposes the
backup flow, and the native replacement completion gate includes a tested
backup/export + restore/import round trip.

Do not reopen this as unfinished D4 work. The current backup contract is owned by
`MOBILE_PRODUCT_SEMANTICS.md`, `ARCHITECTURE_DECISIONS.md` and the completed
D9 replacement contract.

## 6. Diagnostics, debug logging, and export — COMPLETE

Native iOS now provides the support-oriented diagnostics path required for
physical-device and TestFlight-style investigation without an attached Xcode
debug session.

Implemented contract:

- `IOSAppDiagnostics` owns a bounded app support log capped at 5,000 records
  and a rotating on-disk JSONL file under the native Application Support
  namespace; this is support infrastructure only and is not Core/domain state.
- `IOSAppLogger` mirrors retained records to Apple's unified logging while
  Info/Warning/Error remain enabled during normal operation.
- **Debug Logging** is OFF by default, persisted in UserDefaults when explicitly
  enabled, and gates Debug/Trace retention.
- Native Core startup now uses `Flux.initializeWithDiagnostics` with
  `IOSCoreDiagnosticListener`, so Rust Core Trace/Debug/Info/Warn/Error records
  feed the same support log.
- Playback, media transfers, Background Sync, system notifications, widget
  snapshot coordination, Core bootstrap and app-launch diagnostics use the
  app-owned logger.
- Developer Diagnostics exposes the Debug Logging switch, stored-record count,
  **Prepare Diagnostics Export**, Share Sheet **Export Diagnostics**, and
  **Clear Diagnostics**.
- Export combines retained native/Core records with app version/build, OS
  version and device class and remains useful across a reproducing relaunch.
- API keys and custom-header values are registered as in-memory sensitive values
  before Core initialization and are redacted before persistence/export;
  common authorization/token/password patterns are also scrubbed.
- Focused tests cover bounded retention, Debug opt-in/persistence across
  relaunch, credential redaction, and export metadata/content.

The app-owned log remains deliberately bounded and diagnostic-only; it does not
create a second persistence or domain authority.

## 7. Curated feed onboarding — RETIRED

The former Flutter curated/suggested feed onboarding is intentionally removed.

Product decision:

- Do not implement a curated repository-maintained feed list in native iOS.
- Do not add it to macOS, Android, or future Flux clients.
- Feed creation/discovery remains based on the existing Miniflux/native feed
  management flow.
- Treat the legacy Flutter curated-feed surface as retired behavior, not an open
  parity gap.


---

## Frozen UIKit Timeline architecture and performance-sensitive rules

## 2. Concrete architecture

| Responsibility | Required implementation |
|---|---|
| Timeline ownership | One UIKit view controller owning one plain `UITableView`, embedded in the SwiftUI shell through a narrow representable bridge. |
| Cell rendering | Native UIKit labels, image views, and status/accessibility presentation in reusable table cells. Preserve native table swipe actions, context menus, refresh, and reuse. |
| Structural data | Stable Article IDs in a diffable data source, with presentation content keyed by ID. Apply structural snapshots only for actual snapshot adoption/reset/membership/order changes. |
| Read/starred state | One coherent native presentation overlay over the Core snapshot, keyed by ID. Update only relevant status and actions on a matching cell. |
| Geometry | An owned UIKit coordinator samples resolved cell frames and scroll movement within one layout generation. The detector is non-observable and independent of SwiftUI view updates. |
| Persistence | One serial, account/Core-session-owned executor using existing Core bulk mutations off-main; it outlives Timeline view recreation. |
| Images/icons | Reuse prepared-image, downsampling, caching, and deduplication infrastructure; integrate bounded UIKit prefetch and safe cancellation. |
| Other app surfaces | SwiftUI continues to own the existing navigation, Settings, Reader/Search presentation, sheets, and other surfaces. |

Do not use `UIHostingConfiguration` or a `UIHostingController` per Timeline
article cell. This is a decision to control the rendering path, not a claim that
hosting is universally slow. Do not replace `List` with `LazyVStack`, install a
third-party list framework, override the internal delegate of a SwiftUI control,
or build custom scroll physics. UIKit retains system scrolling, reuse, native
swipes, context menus, and refresh integration.

Use the smallest durable set of types needed to separate controller/renderer,
geometry detection, and mutation execution. These are presentation and scheduling
objects, not a new durable Swift domain model. Reuse or extract current logic
where it already satisfies the contract; do not run two mutation queues or two
production Timeline implementations in parallel.

## 3. Rules for the performance-sensitive path

### Geometry and read detection

- Use scroll offset, effective viewport/insets, and resolved row frames in a
  common coordinate system. Observe actual user movement and deceleration.
- A normal read candidate was genuinely visible and then crossed completely
  above the effective upper boundary during forward movement. A prefetched,
  prepared, or merely skipped row is not qualified. Cell lifecycle callbacks
  may maintain bookkeeping but are never the sole read signal.
- Evaluate currently visible and just-exited rows from a consistent layout
  generation. Retain enough prior resolved geometry to handle a row that has
  already left the reuse/display set. Retire that geometry when no longer needed.
- Direction reversal must preserve qualification and associate crossings with
  the correct motion. Do not use a stale last-direction flag to discard a
  crossing before the matching geometry is considered. Small valid movements
  must accumulate; a 0.5-point tolerance per callback must not suppress an
  arbitrarily long slow gesture.
- Rebaseline for rotation, Dynamic Type, width/inset changes, snapshot resets,
  and scroll-anchor corrections. Separate baseline validity from the real scroll
  phase so detection resumes during the same gesture once geometry is valid.
- Bottom completion applies only to observed trailing rows at a genuine forward
  arrival. It is tied to that arrival/layout and ends when moving backward,
  leaving the bottom, ending the interaction, or invalidating the layout. An
  initially short list or a programmatic/reset arrival does not mark its rows.
- No per-row timers or debounce delays determine exposure/crossings. Do not
  force a full `layoutIfNeeded()` pass or query Core from `scrollViewDidScroll`.

The sensor's work is proportional to the current/recent viewport, not all 8,000
articles or all rows seen since opening the list. The pending-write collection
and structural ID/content metadata are separate from that geometry
window; do not confuse required snapshot storage with per-scroll iteration.

### Cells, layout, and images

Separate immutable content/layout inputs from mutable read/starred state.
Prepare formatting and reusable layout information outside the scroll callback.
Reuse measurements while content revision, available width, Dynamic Type,
presentation mode, preview-line setting, and other relevant sizing inputs match.
Preserve variable-height articles and accessibility; do not force every row to
a single fixed height to conceal sizing work. Image loading must use fixed slots
for each cell's selected layout and must not change cell height on completion.

For a status-only read/starred change, update the ID-keyed state first. An
offscreen article needs no cell update. A matching visible/prepared/reappearing cell obtains the
latest state during its normal configuration/display lifecycle; update only
its small status and action/accessibility surfaces. Do not reapply the full
diffable snapshot, reload all items, or reconfigure/remeasure article text and
images because one read flag changed.
An explicit manual action that removes a row under the existing Remove When
Read/Starred-scope rules performs a separate structural change. Preserve that
behavior; ordinary Scrollover must never remove rows, including after idle.

Async image results identify an Article ID, content/request identity, and a
current consumer. Never retain a cell/index path and blindly update it after
an await: it may now represent another article. Cancel obsolete prefetch
consumers without canceling a shared request still needed by a visible cell.
Keep prepared-image and auxiliary caches bounded, including after a long scroll.
Prefetch planning reacts to relevant window/size changes and remains available
when Scrollover is disabled. The compact mode must avoid image-planning work.

The SwiftUI bridge receives semantic revisions/inputs, not continuously changing
offsets or per-row positions. SwiftUI updates to navigation, badges, or overlays
must not recreate the controller or reapply an unchanged article snapshot.

### Local Timeline pagination

The local iOS Timeline reads bounded Core-owned keyset pages. The cursor is the
shared `(published_at, article_id)` ordering contract. A first page includes the
authoritative full selected-scope total and replaces the Timeline; later pages
omit the repeated total and append only new stable IDs and immutable row content.
Targeted removals likewise publish only deleted IDs, retaining unaffected row
presentation objects and content. Prepared row content, including date and link
derivation, is made off-main before the MainActor validates the page generation
and publishes the small structural delta.

Loaded pages remain retained for the lifetime of the current Timeline query.
Hard windowing/eviction is deliberately deferred until profiling demonstrates a
need. Paging requests are generation-owned, so stale work cannot block or clear
a newer query's request. Targeted read/starred/Scrollover presentation mutations
remain separate from structural pagination. Remote Search keeps its own
offset-pagination contract rather than using the local article cursor.

### Mutation execution and feedback

Adapt/extract the existing scheduler into one session-owned worker with a
controllable writer seam for tests. A synchronous UniFFI call must execute on
an appropriate background executor; placing it on an actor is not by itself
proof that the main thread or cooperative executor is safe from blocking work.

At acceptance, retain Article ID, target read value, account/Core-session
identity, origin presentation generation, and read-intent ordering/revision.
Equivalent representations are fine; the semantics are required. Capture the
origin when enqueuing, not when a delayed batch starts. Mixed-origin batches
must retain their feedback attribution. Enforce the existing 64-ID maximum at
dequeue, continue serially, and deduplicate/coalesce only when ordering and
feedback ownership remain correct.

Do not wait indefinitely for scroll idle: bound the scheduling delay for a small
buffer and additionally drain on idle and lifecycle transitions. This bound
does not imply that a blocked Core operation completes within a fixed time.
Batch timing is separate from read detection and Undo product qualification.
Record persistence parameters centrally and test their behavior; do not add
unrelated user settings or per-article timers.

Explicit Read/Unread and Undo must participate in the relevant per-article
ordering. A newer Unread must win over an older queued automatic Read. If the
older operation is already running, preserve the newer local overlay and ensure
the final persisted state follows the newer intent. Reject stale success/error
feedback by session, origin presentation, and intent revision. A changed view
discards obsolete feedback, not accepted writes. Keep starred/read field
semantics separate when resolving conflicts.
Re-arm an explicitly marked-unread/undone article for a future genuine crossing;
do not immediately read it again because of a status callback or a reset.

An account boundary must never replay old IDs into a new Core. Account removal,
rebuild, and normal session teardown have different existing semantics: handle
pending work explicitly with the original session and preserve their contracts.
Foreground-to-background handling must attempt a real local flush within the
available OS lifecycle; launching an unstructured Task is not a flush result.
Do not claim uncommitted state survives an abrupt process kill or add a Swift
database/Miniflux implementation to make such a claim.

Preserve the current iOS Undo rules: qualification after at least three
successful unread-to-read mutations in the rolling one-second window; one
rolling active group; four-second inactivity expiry and fifteen-second maximum
lifetime. Detected candidates, already-read items, failed/stale operations, and
skipped unseen IDs do not qualify a new group. Do not redefine Undo from batch
size, candidate timing, or a new exposure timer. Preserve normal Core delivery
policy and local-success semantics; remote delivery is not a prerequisite for
rendering a local read intent.

Counts/Undo are separate from the article snapshot. Filter ignored Core events
before scheduling main-thread work, and coalesce nonessential presentation
publication so it does not create scroll-frequency UI work.


## 8. Agreed U3/U4 stabilization and architecture-freeze plan

This section records the owner-approved direction after the September 2026
performance investigation. It is the default completion sequence unless new,
reproducible device evidence demonstrates a different architectural problem.
Do not restart broad renderer experiments merely because older diagnostic plans
contain alternatives that were already tried.

### 8.1 Current productive baseline

Keep the current owned `UITableView` Timeline, native UIKit cells, deterministic
layout preparation, and the normal 100%-content-width Visual portrait image.
The iPhone 15 comparison showed that the same full-width presentation that
remained visibly rough on iOS 26 is substantially smoother after updating the
same device to iOS 27. This does not prove a specific iOS 26 framework defect,
but after the completed SwiftUI/UIKit, collection/table, image-size, raster,
prefetch, scheduling, and layout experiments it is sufficient evidence not to
compromise the product UI or reopen the Timeline container by default.

Visual compact remains a normal product presentation mode, not a performance
workaround that must replace the standard full-width Visual mode.

### 8.2 U4 complete — session mutation worker

The U4 implementation contract is now represented in code and tests. The
existing queue remains owned by the `NewsreaderStore` Core/account session and
still uses 64-ID bounded FIFO batches with pending/in-flight deduplication and
one logical Scrollover writer chain per session.

A small accepted batch now receives one session-owned bounded drain deadline of
500 ms. Reaching 64 IDs, entering idle, or a lifecycle flush still requests an
immediate drain through the same serialized worker. The deadline is cancelled
when a drain starts or the session is invalidated; it never creates a parallel
writer.

Each drain captures the read-mutation writer for the current session. Production
writers capture the current `Flux` instance and continue to execute synchronous
Core/UniFFI work through `AppleCoreExecution`. A Core/account replacement drops
queued work, cancels its deadline, and invalidates completion ownership. An
already-running old writer may finish against only the Core it captured; its
completion cannot clear, publish into, or continue work for the new session.

Newer explicit Read/Unread intent removes conflicting queued/deferred automatic
presentation and Undo state, marks a conflicting in-flight automatic intent as
superseded, and waits for that older Core write before issuing the explicit write.
Automatic completion/failure effects for superseded IDs are ignored. Explicit
read-mutation tokens also keep those IDs ineligible for new automatic acceptance
until the explicit operation finishes. Undo uses the same captured writer path.

Writer failure restores only still-owned automatic presentation, clears the
running state, and continues any remaining FIFO queue; a later batch can run
normally. Presentation-only resets keep valid persistence work for the same
session.

Regression tests now use an injectable, controllably blocked read writer around
the productive drain operation rather than only array-pop helpers. They cover
the bounded deadline, 64-ID limit/FIFO continuation, trigger coalescing,
presentation reset, explicit Read/Unread precedence, blocked successors,
old-session completion, failure recovery, lifecycle flush, and real-writer Undo.

Canonical local validation passed on 2026-09-21. `./apple/ios/Build/test.sh`
executed 343 tests with 0 failures, `./apple/ios/Build/build-app.sh` succeeded,
and `git diff --check HEAD^ HEAD` was clean. U4 is therefore complete. The
subsequent U3 closure is recorded below.

### 8.3 U3 closure — COMPLETE

U3 real-device performance/correctness acceptance completed on 22 September
2026. The accepted baseline is the owned `UITableView` Timeline with native UIKit
cells, deterministic prepared layout, normal 100%-content-width Visual portrait
images, targeted status updates, and the single ImageIO -> UIImageView/Core
Animation article-image path.

On the iPhone 15 running iOS 27, sustained scrolling remained smooth with more
than 200 loaded articles and the normal full-width image geometry. The owner also
accepted the remaining presentation/device checks covering rotation-anchor
preservation, article metadata/reading-time presentation, haptics and Undo,
status-bar edge protection, compact-landscape scope capsule behavior, and the
current iPad/iPhone toolbar presentation. No unresolved performance regression
remains that justifies another renderer/container experiment.

The final post-renderer-retirement canonical XCTest run on 22 September 2026
completed `./apple/ios/Build/test.sh` with **348 tests and 0 failures**. That run
covers the productive Scrollover/mutation contracts, deterministic UIKit geometry
including RTL, EXIF-aware article-image decoding, cache/prefetch behavior, and
the retained engine-versus-cell geometry oracle. This automated result does not
replace the device evidence above; together they close U3.

Synchronous deterministic-layout fallback counters remain performance canaries.
Rotation, Dynamic Type, or a new geometry generation may legitimately exercise
exceptional preparation paths, but recurring fallback during ordinary
steady-state scrolling would be a new regression. The constraint-based cell and
`IOSUIKitArticleLayoutEngine` remain the accepted baseline; manual frame layout
is not justified without new evidence.

### 8.4 Legacy article-image renderer retirement — COMPLETE

The sole production article-image path is now:

`Data -> ImageIO display-sized aspect-fill decode -> bounded cache -> UIImageView/Core Animation aspect-fill + rounded clipping`.

The final iOS 27 device pass on the iPhone 15 remained smooth through more than
200 articles, and the former exact-slot `displayReady` CGContext path showed no
visible scrolling advantage. Earlier iOS 26 investigation likewise did not
establish a product-relevant benefit from the extra raster stage. After device
acceptance, retaining a second renderer solely for historical comparison no
longer justified its code and cache complexity.

Removed with the legacy article renderer are the runtime renderer-mode
distinction, the Developer Diagnostics switch and persisted preference,
exact-slot rounded-corner/backdrop CGContext preparation, article-image P3/
backdrop renderer cache dimensions, renderer-change notifications,
appearance-driven article-image rebinding, and renderer-specific tests. Git
history remains the archive for the experiment.

The remaining pipeline keeps display-sized ImageIO decoding, the bounded 128 MiB
LRU, in-flight deduplication, visible-over-prefetch priority, cancellation,
serialized transform work, the narrow decoded-scale test seam, and the
presentation scheduler. UIKit/Core Animation owns normal final image
presentation.

### 8.5 Status-bar and navigation edge protection

The U3 closure originally kept the native top scroll-edge effect disabled because
both `.soft` and the then-current `.automatic` presentation extended underneath
the custom scope capsule while that capsule was a `UINavigationBar` toolbar
item. Pull to Refresh was not the cause and remains enabled.

On 23 September 2026 the presentation chrome was amended without reopening the
frozen Timeline renderer/container architecture. A 24 September follow-up keeps
the successful compact-portrait result while making compact iPhone landscape
deliberately different:

- compact portrait keeps the centered detached scope capsule in a normal top
  `safeAreaInset`, with the full capsule acting as the scope-selection `Button`;
  its custom iOS 26+ glass is interactive. The measured detached-row height is
  also supplied to the Timeline as a natural-top `contentInset`, so only the
  list's initial position clears the capsule while normal scrolling can continue
  underneath it. Existing semantic resets, including scope changes and
  manual-Sync replacement, already target `-adjustedContentInset.top` and
  therefore land on the same cleared start. Sync/Filter/More remain in the
  native bottom toolbar, and the native `.automatic` Timeline top-edge effect
  remains enabled on iOS 26+;
- compact landscape returns the scope capsule to `.topBarLeading` and
  Sync/Filter/More to `.topBarTrailing`. Its Timeline top-edge effect is
  disabled because the compact landscape presentation has no visible status-bar
  glyph band to protect;
- persistent split modes normally keep the detached floating action chrome from
  the earlier amendment. On SDK/runtime combinations that expose
  `EnvironmentValues.toolbarVerticalEdge`, a non-`nil` system vertical-bar edge
  switches Sync/Filter/More back to native `.topBarTrailing` toolbar items so
  iPhone Duo can place those symbol actions on its vertical control bar. A
  collapsed split keeps the wider scope capsule horizontal in the independent
  inset row; a visible sidebar still suppresses that capsule. This adaptive
  action placement does not alter the regular-mode Timeline top-edge policy:
  `.automatic` remains enabled on iOS/iPadOS 26+.

The `toolbarVerticalEdge` symbol itself requires the iOS 27.1 SDK. To avoid
making ordinary Flux development depend on that SDK while also avoiding a
minor-version maintenance trap, the bridge is compiled behind the capability
flag `FLUX_HAS_VERTICAL_TOOLBAR_API`. The Xcode project enables that capability
for iOS/iPhone Simulator SDK 27.1 through 27.9 and for later major SDK families.
SDK 27.0 is deliberately excluded. Thus a 27.0 build keeps the established
horizontal persistent-split chrome, while 27.1+ SDK builds continue to gain the
Duo vertical-bar adaptation without adding a new flag for every future 27.x
release.

The bottom edge effect remains disabled everywhere. On iOS/iPadOS 17-25 the
bounded status-bar scrim remains the fallback where it has nonzero height. In
compact landscape its measured status-bar height is zero, so disabling the native
top-edge effect introduces no replacement backing. The compact-landscape scope
capsule relies on system toolbar Liquid Glass on iOS 26+ and uses regular
material below 26, avoiding a double glass layer.

### 8.6 iOS 26 full-width-image behavior — ACCEPTED LIMITATION

Flux continues to support iOS 17+, so iOS 26 remains a supported OS. The
full-width-image scroll-quality difference observed on iPhone 15 survived the
app-side investigation and improved materially on the same hardware under iOS 27.
The completed U3 closure found no actionable app-side regression that justifies a
second renderer or reduced-width product geometry.

The remaining iOS 26 behavior is therefore recorded as an
OS/rendering-sensitive limitation. Do not restore the temporary 80%-image/
info-rail design, reduce image width, or reopen the renderer/container solely to
hide that perceptual difference. New work requires new reproducible evidence
that identifies an actionable app-side cause.

### 8.7 U5 behavior-preserving cleanup, then freeze the Timeline architecture

U3 and U4 are complete. U5 is now limited to behavior-preserving cleanup rather
than another performance redesign:

- keep productive Scrollover geometry isolated in
  `IOSUIKitScrolloverGeometry.swift`; broader controller/cell/bridge source
  splitting is optional and is not a freeze gate;
- keep all Scrollover regression semantics on the productive
  `IOSUIKitScrolloverGeometryTracker`; the historical SwiftUI/List controller
  must not return;
- keep cell layout driven directly by prepared
  `IOSUIKitArticleLayoutMetrics`; use the cheap non-text
  `IOSUIKitArticleGeometry` only where reuse/prefetch needs geometry without
  Core Text measurement;
- keep the retired article-image renderer and diagnostic switches removed;
- preserve the existing engine-versus-cell geometry oracle, bounded-cache tests,
  snapshot/status separation tests, and accepted device behavior;
- run final `build-app.sh` and `git diff --check` validation for the cleanup
  commit set before declaring the architecture frozen.

U5 final acceptance passed on 2026-09-22: the canonical iOS test run executed
338 tests with 0 failures, `build-app.sh` succeeded, `git diff --check
main...HEAD` was clean, and the focused physical-device smoke test passed. The
current Timeline container/rendering architecture is therefore frozen. Later
feature work should extend the accepted product semantics without reopening
`UITableView`, full-width Visual portrait images, Scrollover geometry, or the
fundamental image/layout pipeline unless new device evidence demonstrates a
concrete regression that cannot be addressed inside those boundaries.


---

## System media, remote commands and CarPlay

## 4. Ownership and lifecycle decisions

### Playback authority

There remains exactly one `IOSMediaPlaybackCoordinator`, one native AVPlayer engine, one AVAudioSession coordinator, and one `IOSMediaPlaybackPresentationState` per app runtime. Lock Screen, Control Center, headset controls, and CarPlay all observe/command that same runtime.

### Now Playing ownership

Add one app-scoped iOS Now Playing/remote-command adapter as a child of `IOSMediaRuntime`. It observes `playbackPresentationState`, publishes system metadata, loads artwork through the existing playback coordinator/Core adapter, and sends semantic commands back to `playbackCoordinator`.

It must exist independently of whether `IOSMediaPlayerView`, Listening List, or any other SwiftUI surface is currently presented. D6 presentation polish therefore cannot break D7.

### Command semantics

Initial supported commands:

- Play: play/resume the currently loaded enclosure through `IOSMediaPlaybackCoordinator`.
- Pause: coordinator pause; checkpoint semantics remain D6-owned.
- Toggle: play/pause based on the shared live presentation status.
- Skip backward/forward: coordinator skip using the accepted product policy of 15 seconds backward and 30 seconds forward.
- Change playback position: validate/bound seconds and dispatch coordinator seek.

`stopCommand` stays disabled initially. D6 Stop is a meaningful in-app lifecycle operation (checkpoint + retain resumable medium + release audio session), but exposing Stop as a general remote command is not required for standard spoken-audio control and would create a different external semantic from Pause. `nextTrackCommand`/`previousTrackCommand` also stay disabled until Flux has an explicit queue/episode-advance contract; D7 must not invent one.

Restart remains an explicit Flux completion action, not a generic remote command. Natural completion continues through the existing D6 completion path.

### Publication lifecycle

When no enclosure is loaded, clear Now Playing info and use unknown playback state.
Pause retains Now Playing metadata and elapsed position so external surfaces can
resume the same item. In-app Stop checkpoints playback, releases the
AVAudioSession for deactivation, retains the prepared/loaded media state for
resume, clears system Now Playing, and hides the Article List Now Playing action.
While playing, publish the configured playback rate; while not playing,
effective rate is zero while the default/configured rate remains available.

Position ticks may update elapsed/rate without rebuilding artwork and all metadata. Metadata/artwork updates use generation/identity guards so an old artwork request cannot overwrite a newer enclosure.

### CarPlay ownership

Add a CarPlay scene delegate/coordinator that owns only CarPlay presentation objects (`CPInterfaceController`, templates, short-lived browsing projection/tasks). It references the app-scoped media runtime and a narrow Core-backed browsing adapter. It never owns AVPlayer, AVAudioSession, playback checkpoints, download state, SQLite, or a second playback presentation state.

Disconnecting CarPlay destroys CarPlay UI state only. Playback may continue through the app-scoped runtime according to existing D6 semantics.

### Article List Now Playing access

The Article List provides a configurable Action Bar access point while a player
is actively running. It presents the existing player rather than creating a
second player context, and reuses the Listening List context, including Show
Notes whenever the current `ListeningListItem` is available. Stop hides this
access point; Pause retains Now Playing presentation.

## 5. CarPlay API contract

For the current iOS 17+ deployment target, use the CarPlay framework scene/template APIs:

- `CPTemplateApplicationScene` / `CPTemplateApplicationSceneDelegate`;
- `CPInterfaceController`;
- `CPListTemplate` (and only additional audio-entitlement-compatible templates if justified by implementation);
- shared `CPNowPlayingTemplate` for current playback.

The CarPlay scene configuration must be added under `CPTemplateApplicationSceneSessionRoleApplication` in the scene manifest and must set a root template during the CarPlay connection callback. The existing phone-scene single-scene policy remains conceptually intact: CarPlay is a dedicated external presentation scene, not a second phone/Core session.

Audio-entitled CarPlay apps are restricted to the templates Apple permits for that entitlement. Do not use `CPInformationTemplate` for the audio app. Use selection handlers on modern selectable list items rather than the deprecated list-template delegate selection API.

`com.apple.developer.carplay-audio` is required. D7 implementation/acceptance must verify the development and production/upgrade-test signing profiles actually contain the entitlement. Simulator UI testing is useful but does not replace signed physical-device/head-unit acceptance.

## 6. CarPlay browsing model

The initial D7 browsing source is the Core-backed Listening List, not a scan of downloaded files and not the legacy Flutter cache. This intentionally modernizes the legacy behavior while preserving its user goal.

Minimum browse behavior:

1. root presents playable Listening List content;
2. optional feed grouping/filtering may use existing `listening_list_feeds()` when it improves navigation without duplicating state;
3. each row is projected from `ListeningListItem` / its selected playable audio enclosure;
4. selecting a playable item dispatches prepare/play to the existing `IOSMediaPlaybackCoordinator`;
5. once playback is ready/started, present the shared `CPNowPlayingTemplate`;
6. remote/CarPlay transport controls operate through the same remote-command/playback coordinator path and same Now Playing publication.

Downloaded and remote media are both valid because D6 `preparePlayback` already resolves the appropriate source. CarPlay must not require a local download unless a later explicit product policy says otherwise.

If an item has multiple audio enclosures and Core/UI semantics cannot select one unambiguously, CarPlay must expose a deterministic secondary choice or mark the row non-playable; it must not guess a different enclosure than the existing Listening List semantics.


## 11. D7 completion contract

D7 is complete when:

- iOS Now Playing and remote commands are app-scoped adapters over the D6 runtime;
- macOS/iOS share only the proven semantic projection/policy layer;
- CarPlay browses Core-backed playable content and starts the same D6 playback stack;
- no second player, durable Swift media state, SQLite/Miniflux path, or duplicate orchestration exists;
- unsupported Stop/next/previous semantics have not been invented;
- automated Rust/iOS/macOS gates are green;
- lock-screen/Control Center/background and physical CarPlay acceptance are recorded;
- D6 presentation can still evolve without changes to D7 architecture.

Those gates are satisfied for the current implementation. D7 is therefore
complete, real-device accepted, and architecture-frozen in the Phase-D contract.


---

## ActivityKit / Live Activities decision

## Decision

D8 does not introduce a custom ActivityKit Live Activity for audio playback in the current native iOS/iPadOS replacement.

D7 already integrates the single app-wide native media runtime with the system Now Playing and remote-command surfaces. On supported iPhones, the system Now Playing experience provides the appropriate audio presentation in the Dynamic Island without FluxNews owning a separate ActivityKit lifecycle or a second playback presentation state.

Therefore Dynamic Island audio playback is considered part of the D7 system-media integration rather than a missing D8 implementation.

## Architecture rationale

The existing media ownership contract remains unchanged:

- Rust/Core owns durable media and playback state.
- `IOSMediaRuntime` / `IOSMediaPlaybackCoordinator` own the single native playback runtime and AVPlayer execution.
- `IOSMediaPlaybackPresentationState` is the transient native playback projection.
- Now Playing, remote commands and CarPlay are adapters/projections over that runtime.
- D8 must not create another player, durable playback state, playback coordinator, or competing media lifecycle.

A custom ActivityKit Live Activity for the same audio session would duplicate information already exposed through the system Now Playing experience and would add a parallel ActivityKit start/update/end lifecycle without a distinct product requirement.

## Deferred scope

ActivityKit remains available for a future FluxNews feature if a distinct live-state use case emerges that is not already better represented by an existing system integration.

Potential future use cases must be evaluated independently before reopening D8. Background downloads or synchronization are not considered sufficient requirements by themselves at this time.

No ActivityKit target, `ActivityAttributes`, Live Activity lifecycle, custom Lock Screen Live Activity, or custom Dynamic Island UI is required for the current native replacement release.

## Reopening criteria

D8 should only be reopened when there is a concrete product requirement for live state that:

1. has meaningful user value beyond the existing Now Playing / notification / background-task surfaces;
2. has a clear start/update/end lifecycle appropriate for ActivityKit;
3. does not duplicate D7 audio Now Playing behavior;
4. can remain a projection over existing Core/native runtime ownership rather than becoming a new state authority.

Until such a requirement exists, D8 is intentionally outside the active
replacement roadmap rather than incomplete. D9 follows D8 as the final active
native replacement-completion block.


---

## Durable D9 replacement product rules

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
runtime usage; see [analysis/ios/IOS_LOCALIZATION_USAGE_AUDIT.md](../../analysis/ios/IOS_LOCALIZATION_USAGE_AUDIT.md).
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

