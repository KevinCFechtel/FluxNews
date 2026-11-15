# iOS/iPadOS D6 — Native Media & Background Downloads

Status: **IMPLEMENTATION STABLE / TESTVALIDATED — UX OBSERVATION NON-BLOCKING; historical D6 execution record**  
>
> Current Phase-D replacement acceptance is recorded in
> `PHASE_D_NATIVE_IOS_IPADOS.md`: D9 and the physical production upgrade are
> complete. Any remaining D6 observation/final-freeze wording in this document
> is historical/non-blocking rather than a replacement-release gate.
Date: 25 September 2026  
Repository baseline reviewed: `main` at `3d6b59202c61d1537784c8be9544c88e1a38c95e`

This document refines the D6 roadmap in
[`PHASE_D_NATIVE_IOS_IPADOS.md`](PHASE_D_NATIVE_IOS_IPADOS.md). The Phase-D
document remains authoritative for the overall native replacement architecture;
this file is the concrete D6 execution contract.

The review was repository-first. The current Rust Core/UniFFI implementation,
Phase-B media contract, Phase-B8 native execution contract, completed Phase-C
macOS implementation, shared Apple sources, current native iOS runtime and the
legacy Flutter client were inspected before defining this plan.

## 1. D6 boundary

D6 implements the native iOS/iPadOS media experience over the existing Core
media domain:

- Listening List;
- article/media actions;
- in-app audio playback through AVPlayer;
- playback progress and completion;
- chapters;
- show notes through the existing Reader contract;
- in-app artwork where required;
- media/download settings and policies;
- AVAudioSession lifecycle and background audio;
- true persistent background downloads through a background URLSession;
- transfer reconciliation against Core durable intent;
- recovery across foreground/background, scene lifecycle and process relaunch.

D6 does **not** implement:

- MPNowPlayingInfoCenter;
- MPRemoteCommandCenter;
- lock-screen / Control Center command integration;
- CarPlay;
- ActivityKit;
- Live Activities;
- Dynamic Island.

Now Playing, remote commands and CarPlay remain D7. ActivityKit / Dynamic
Island remain D8. D6 must expose one coherent runtime state that those later
phases can consume without introducing another player or transfer stack.

## 2. Ownership

The ownership boundary is unchanged.

### Rust Core remains authoritative for durable domain state

Core owns:

- enclosure identity and article relation;
- Listening List membership and ordering;
- playback position/status and Miniflux progression reconciliation;
- after successful Core sync, native iOS reconciles an already loaded but idle
  (paused/stopped) AVPlayer runtime to the Core playback position so a newer
  cross-device Miniflux progression is reflected before the next local
  checkpoint; actively playing audio is never force-seeked by remote sync;
- download intent and durable download state;
- download origin/failure semantics;
- media metadata, chapters and artwork references;
- download policies and retention;
- per-feed automatic download policy;
- cleanup decisions;
- Miniflux reconciliation.

Swift must not create a second durable media-domain model and must not access
SQLite or Miniflux directly.

### Native iOS owns runtime execution

Native iOS owns:

- AVPlayer execution;
- AVAudioSession;
- runtime play/pause/buffering/loading state;
- playback-rate runtime;
- sleep-timer runtime;
- background URLSession task execution;
- native transfer progress;
- native transfer task identity/registry;
- filesystem moves/deletes required by URLSession;
- application/process lifecycle integration;
- native presentation.

Native transfer task identity is execution metadata, not domain state. It may be
persisted only as the minimum opaque native execution identity required to
restore OS-owned background tasks.

## 3. Readiness findings

### 3.1 Already available in Core / UniFFI

No new D6 domain API is required by the current product contract.

The current UniFFI surface already exposes the required records and operations,
including:

- `ListeningListItem`, `ListeningListEnclosure`, `ListeningListFeed`;
- `Enclosure` and media classification;
- `PlaybackState` and `PlaybackPreparation`;
- `MediaChapter`, `MediaArtworkSource`, media metadata;
- `MediaDownload`, `MediaTransferWork`, download state/origin/failure;
- `CoreSettings` media policy fields;
- `article_enclosures`;
- batched `article_audio_action_states`;
- `listening_list`, `listening_list_feeds`,
  `is_in_listening_list`, add/remove Listening List;
- `prepare_playback`, `checkpoint_playback`,
  `playback_completed`, `restart_playback`,
  `observe_media_duration`;
- `media_chapters`, `media_artwork`;
- `media_download`, request/cancel/retry/delete download;
- `downloads_requiring_transfer` and `downloads_requiring_deletion`;
- transfer completion/failure/deletion callbacks;
- media cleanup and all current media-policy setters;
- per-feed automatic audio-download preference.

The native implementation must consume these APIs rather than reconstructing
relationships with many per-row calls.

### 3.2 Existing iOS preparation

The current iOS code already provides:

- shared `BrowserScope.listeningList`;
- title/action semantics that understand that scope;
- the prepared but deliberately hidden Listening List navigation entry;
- mobile article-action semantics that reserve media work for D6;
- the app-wide `CoreBootstrapper` and
  `IOSCoreSessionExecutionCoordinator`;
- single-scene app ownership;
- D5 `IOSMediaTransferReconciliationHandoff`;
- successful-background-sync fanout into that handoff;
- the app-specific Core media root under the configured storage namespace.

The Listening List navigation entry remains hidden until its real D6 query and
presentation exist. It must not be enabled while it still aliases the normal
article query.

## 4. Phase-C reuse

Phase C is the primary native reference, not a presentation template.

### 4.1 Good candidates for direct reuse or small extraction

Extract only when the first iOS consumer is added:

- pure media playback presentation state;
- pure transfer presentation/runtime progress state;
- sleep-timer semantics;
- deterministic/safe media transfer file-layout helpers;
- AVPlayer engine behavior that is genuinely identical across Apple platforms;
- small action/presentation helpers whose semantics are platform-independent.

Any extraction must keep the macOS behavior unchanged and must be covered by
the existing macOS media tests plus new iOS tests.

### 4.2 Components that must not be shared wholesale

Do **not** move the following macOS classes unchanged into FluxApple:

- `MediaPlaybackCoordinator`;
- `MediaTransferCoordinator`;
- the foreground `URLSessionMediaTransferEngine`;
- macOS Player/Popover UI;
- macOS remote-control / Now Playing integration;
- macOS media-root selection.

Reasons:

1. The macOS playback coordinator performs synchronous local Core calls from its
   MainActor orchestration. Phase D requires iOS Core/UniFFI work to pass
   through the existing app-wide Core-session execution boundary.
2. iOS playback additionally owns AVAudioSession interruption/route/background
   lifecycle.
3. The macOS transfer coordinator owns in-memory foreground tasks. iOS requires
   a persistent background URLSession whose tasks survive process suspension
   and may cause relaunch.
4. macOS and iOS presentation/navigation are intentionally different.

Reuse the semantics, tests and pure building blocks; keep platform execution
coordinators platform-specific unless later evidence proves a smaller common
orchestration layer is both real and behavior-preserving.

## 5. App-wide iOS media runtime

D6 introduces one app-scoped media runtime owned by `IOSAppRuntime`.

Conceptually:

```text
IOSAppRuntime
  |
  +-- CoreBootstrapper / IOSCoreSessionExecutionCoordinator
  |
  +-- IOSMediaRuntime
        |
        +-- IOSMediaPlaybackCoordinator
        |     +-- AVPlayer
        |     +-- AVAudioSession coordinator
        |     +-- transient playback presentation state
        |
        +-- IOSMediaTransferCoordinator
              +-- persistent background URLSession
              +-- transient transfer presentation state
              +-- filesystem execution
```

`NewsreaderStore`, the UIKit Timeline, Listening List views and Player views
are consumers/controllers of this runtime. None of them owns AVPlayer,
AVAudioSession or the background session.

The runtime attaches to exactly the current Core session and uses the same
`IOSCoreSessionExecutionCoordinator` as other iOS Core callers. Core/session
generation checks prevent stale results from publishing after account
replacement.

### Core lifecycle

Before account/Core replacement or removal, the media runtime must:

- stop admitting new Core work;
- checkpoint active playback where the current Core is still valid;
- detach Core-facing callbacks;
- cancel or disown native transfers belonging to the old account execution
  generation before a replacement Core can consume them;
- allow app-wide Core quiescence to finish.

A failed account replacement may reattach the still-current Core through the
existing aborted-replacement path.

A local-state rebuild keeps the same account/Core object but temporarily
detaches media Core access while the exclusive rebuild runs. Runtime playback
must not issue Core callbacks into the quiesced session.

## 6. Persistent iOS background transfer executor

### 6.1 Background session

Use one app-owned background `URLSession` for media transfers with a stable,
configuration-specific identifier. Native Dev and production/Upgrade Test must
not share a session identifier.

The session:

- uses `URLSessionConfiguration.background(withIdentifier:)`;
- enables launch events;
- applies the Core network policy through native URLSession constraints;
- uses download tasks only for D6 media transfers;
- is owned by a long-lived delegate, not by an individual Swift Task;
- is recreated with the same identifier after process relaunch.

The background session identifier belongs in build/configuration rather than
being inferred differently by views.

### 6.2 Native transfer identity

Each OS task carries a versioned native task description containing at least:

- an opaque current account-execution generation;
- Core enclosure ID.

The generation is native execution ownership, not media domain state. It must
survive process relaunch for the same active account and roll before a new
account can adopt tasks from the previous account.

Do not store OS task IDs in Core SQLite.

### 6.3 D5 handoff integration

`IOSMediaTransferReconciliationHandoff` remains the **only** post-sync
transfer handoff.

When the D6 executor is attached to a ready Core session it installs exactly one
handler into the existing handoff:

```text
D5 successful background sync
       |
       v
IOSMediaTransferReconciliationHandoff
       |
       v
IOSMediaTransferCoordinator.reconcile()
```

Pre-install requests continue to coalesce exactly as D5 already guarantees.
D6 must not add another pending flag, notification, event bus or post-sync
transfer trigger.

Detach/uninstall the handler when no valid media executor/Core session is
attached.

### 6.4 Reconciliation algorithm

Each reconciliation compares:

```text
Core desired transfer/deletion work
+ restored OS background tasks
+ native execution generation
+ actual media files
+ currently playing enclosure
```

Required behavior follows the frozen Phase-B contract:

- Requested + matching OS task -> keep task.
- Requested + no OS task + no completed file -> create task.
- Requested + already completed file -> report completion to Core.
- Downloaded + existing file -> valid.
- Requested task no longer desired -> cancel it.
- Orphan task for another execution generation/account -> cancel it.
- Orphan native file with no valid Core ownership -> remove it.
- DeleteRequested -> delete file, then confirm deletion.
- File used by active playback -> defer deletion until playback releases it.
- A stale Core callback rejection is not reclassified as a transfer failure.

The completion callback is sent only after the downloaded temporary file has
been moved to the deterministic media location and its size is known.

Because the URLSession temporary file is valid only during the delegate
callback, `didFinishDownloadingTo` must move it synchronously into the app's
media area before returning. Domain acknowledgement may happen afterward.

If Core is temporarily unavailable when an OS transfer completes, the durable
Core Requested state plus the already-moved deterministic file must allow the
next reconciliation to report completion without redownloading it. D6 must not
invent a second durable Swift completion queue merely to bridge this case.

### 6.5 Relaunch callback

`UIApplicationDelegate.application(_:handleEventsForBackgroundURLSession:
completionHandler:)` is part of D6.

The delegate hands the system completion handler to the app-owned media runtime,
ensures the normal single Core bootstrap path is used, restores the session,
reconciles native/Core ownership, and calls the system completion handler only
after the background session reports that its queued delegate events are
finished.

A background URLSession relaunch must never construct an independent second Core
against the same storage.

## 7. Playback runtime and AVAudioSession

### 7.1 Playback

The iOS playback coordinator follows the proven Phase-C behavior:

- prefer a validated readable local file from `PlaybackPreparation`;
- otherwise stream the remote enclosure URL;
- restore an `InProgress` position;
- maintain high-frequency position only in native runtime state;
- checkpoint approximately every 20 seconds while playing;
- checkpoint on pause, stop, seek/chapter seek, media switch, interruption and
  foreground-to-background lifecycle;
- use explicit Core completion and restart operations;
- report newly observed duration through Core;
- support 0.5x–3.0x playback rate;
- support the existing sleep-timer semantics;
- load chapters from Core.

Core calls are executed through the app-wide iOS Core-session execution
coordinator rather than synchronously blocking MainActor.

### 7.2 AVAudioSession

D6 owns AVAudioSession. It must:

- use an audio-session configuration suitable for spoken/background playback;
- support background audio;
- handle interruptions;
- handle route changes, including route loss;
- preserve Bluetooth and AirPlay playback;
- resume only when the interruption semantics and previous runtime state make
  resume appropriate;
- checkpoint before an interruption/route event that stops playback.

Backgrounding the app must checkpoint but must **not** pause audio merely because
the scene becomes inactive.

`Info.plist` must add the audio background mode. Background URLSession itself
does not create a second BGTaskScheduler path.

### 7.3 D7/D8 readiness

The D6 playback presentation state must expose enough transient information for
later system integrations to observe:

- active enclosure;
- article/feed title;
- artwork source/data where available;
- playing/paused state;
- position/duration;
- playback rate.

D6 must not call MediaPlayer or ActivityKit APIs.

## 8. Listening List and player presentation

### 8.1 Navigation

Restore the existing prepared Listening List navigation entry only once the real
D6 read model is wired.

- Compact iPhone: selecting Listening List closes the navigation sheet and
  replaces the article detail surface with the Listening List.
- Regular iPad: Listening List is a normal sidebar destination and replaces the
  article detail surface in the second column.
- The Listening List consumes the app shell's existing NavigationSplitView
  ownership and must not introduce a nested NavigationStack inside the detail
  column. When compact or when the sidebar is hidden, it exposes the same
  app-shell scope chooser path used by the article detail surface.
- It is not an `ArticleQuery` alias and does not reuse the UIKit Article
  Timeline data model.

The frozen UIKit Article Timeline remains untouched except for consuming the
later batched article-audio action projection.

### 8.2 Listening List presentation

The list consumes `core.listeningList(...)` and
`core.listeningListFeeds()`.

Preserve Phase-C semantics:

- one row/card per article;
- tapping a row opens the Player for that Listening List item without starting
  playback;
- row-local Play/Pause starts or controls playback without opening the Player;
- multiple audio enclosures represented within that article;
- recently added default sort;
- publication-date alternative;
- optional feed filter;
- playback progress;
- per-enclosure download/progress status derived from the Core projection plus
  the app-scoped native transfer runtime;
- active URLSession transfer byte progress updates the visible row directly;
- terminal native transfer completion/failure/deletion refreshes the Listening
  List Core projection automatically;
- aggregate enclosure status where useful.

Do not add a separate Downloads destination. Download state is represented
within the Listening List/article media experience.

Deletion deferral applies while the enclosure is actually playing. Pause/Stop
releases that deferral and triggers transfer reconciliation so a pending delete
cannot remain stuck until process relaunch.

### 8.3 Player presentation

The Player is native iOS presentation over the app-scoped runtime, not the
runtime owner.

D6 uses a temporary native Player presentation rather than introducing a
persistent mini-player. Dismissing the Player must not destroy active playback.
The app shell owns the Player sheet, analogous to Search's app-shell
presentation ownership, so the Listening List itself remains a pure detail
surface and cannot interfere with navigation-sheet dismissal.

Show Notes reuse the existing ReaderDocument/Reader presentation path. The
Player must not fetch article HTML directly.

Exact visual polish/detents can adapt by size class, but no third durable
navigation/domain model is introduced.

## 9. Article/media actions

D6 wires the existing batched `article_audio_action_states` projection into
article presentation. Do not introduce per-visible-row Core queries.

The same batched projection also drives lightweight Timeline affordances:
articles with at least one audio enclosure show a headphones indicator in the
feed metadata row, and the existing reading-time glyph switches to a listening
glyph for those rows. This remains presentation-only; no per-row media query or
new Timeline domain state is introduced.

Supported native actions follow Phase C/mobile semantics:

- Play;
- Add/remove Listening List as appropriate;
- Download / cancel / retry / delete according to Core state;
- multiple audio enclosures -> native chooser before an enclosure-specific
  action;
- configured Download Audio swipe action becomes available only after this D6
  handler exists.

Successful, non-actionable article/media feedback is presented non-modally as a
short-lived material pill (3 seconds) and a newer feedback event supersedes the
older timer. Error feedback remains modal where acknowledgement or recovery is
required. Actionable banners such as pending-new-data adoption are not converted
to auto-dismissing feedback.

Timeline geometry/image/Scrollover architecture remains frozen.

## 10. Media settings

D6 adds native settings backed only by current Core APIs:

- automatic download when added to Listening List;
- remove completed items from Listening List;
- delete download after playback;
- download network policy;
- download retention;
- per-feed automatic audio download.

Settings presentation may be iOS-specific. Values remain Core-owned.

## 11. Core/UniFFI gap result

### Core/UniFFI API contract

**No missing D6 UniFFI API was found.**

### D6-0 Core correctness follow-up

The readiness review did find one concrete pre-existing Core implementation
inconsistency that becomes user-visible once D6 exposes native media:

- the previous `clear_synchronized_state_for_rebuild()` deleted every Article;
- enclosure/media tables are FK descendants with `ON DELETE CASCADE`;
- this discarded `SavedMedia`, in-progress playback and Requested/Downloaded
  media even though the frozen Phase-B retention contract defines those states
  as local protection;
- physical media files were not removed by Rebuild, so a downloaded item could
  become an orphan file while its authoritative Core state disappeared.

D6-0 now changes the rebuild clear so it preserves only the minimal
Article -> Feed -> Category graph required by the frozen Phase-B protecting
states:

- Phase-C Listening List membership;
- `SavedMedia`;
- `MediaDownload = Requested`;
- `MediaDownload = Downloaded`;
- `PlaybackState = InProgress`;
- pending `MediaProgressMutation`.

Ordinary read/star mutation intent is still discarded and the protected Article
falls back to its last observed remote read/star state before the fresh Full
Sync. `Failed`, `DeleteRequested`, Completed-only playback,
AutoDownloadSuppression and unprotected Articles remain reconstructable and do
not gain rebuild protection. Pending media progression is preserved because it
is itself one of the frozen protecting media states.

The Core regression test
`rebuild_clear_preserves_durable_media_and_listening_state` covers the
protecting/non-protecting matrix, including a pure Listening List item, and
verifies that an existing downloaded file is not discarded as reconstructable
cache. Separate
`listening_list_membership_protects_article_from_normal_retention` and
`pending_media_progress_mutation_protects_completed_article_from_retention`
regressions cover the Phase-C Listening List invariant and the frozen Phase-B
pending-progress protection rule during normal retention cleanup.

The complete remote feed/category catalog remains authoritative. A feed absent
from a complete remote catalog continues to be removed together with its local
articles and preferences, as already defined by the earlier architecture
contract; D6 does not silently redefine feed-deletion semantics.

No Swift workaround or new UniFFI API is introduced for D6-0.

## 12. D6 work packages

### D6-0 — Rebuild/media Core correctness

**Implementation status:** **CLOSED / testvalidated.** The focused regression
tests and the full `flux-core` suite passed on 25 September 2026 after the
retention/rebuild corrections and test-isolation follow-up.

- Rebuild preserves the frozen Phase-B protecting media states plus durable
  Phase-C Listening List membership while clearing reconstructable synchronized
  state.
- Normal read-article retention now preserves Listening List membership.
- Normal read-article retention now also honors pending MediaProgressMutation
  protection even when playback is already Completed.
- Ordinary read/star pending intent is discarded; pending media progression is
  preserved with its protected playback state.
- Downloaded physical media is not invalidated by the rebuild clear.
- Restore-mode reconciliation remains responsible for preventing an
  auto-download storm.
- No new UniFFI media API was required.

### D6-A — App-scoped media runtime foundation

**Implementation status:** **CLOSED / testvalidated.**
`IOSMediaRuntime` is app-scoped under `IOSAppRuntime`, shares the
bootstrapper's `IOSCoreSessionExecutionCoordinator`, owns the existing D5
transfer-reconciliation handoff, and participates in Core replacement/rebuild
attach-suspend-resume-detach lifecycle before presentation is attached. It also
owns transient iOS playback/transfer presentation state. The first real
Phase-C reuse is deliberately small: only pure playback-status,
transfer-runtime and deterministic media-file-layout values live in
`apple/shared/FluxApple`; the macOS and iOS mutable presentation/execution
owners remain platform-local. Canonical iOS tests and the macOS app build passed
on 25 September 2026 after the shared extraction. No AVPlayer or AVAudioSession
is part of D6-A.

- add `IOSMediaRuntime` under `IOSAppRuntime`;
- define Core attach/detach/quiescence ownership;
- add transient playback/transfer presentation states;
- extract only pure Phase-C Apple helpers that now gain an actual iOS consumer;
- add lifecycle tests;
- no UI yet.

### D6-B — Persistent background transfer executor

**Implementation status:** **CLOSED / testvalidated.** The persistent executor core is now
implemented, but final D6-B validation and playback-in-use deletion deferral are
still open.

iOS owns one app-scoped `IOSMediaTransferCoordinator` with a stable
bundle-scoped background-session identifier
(`<bundle-id>.mediaTransfers.v1`), launch events enabled, Core admission
through the existing `IOSCoreSessionExecutionCoordinator`, installation into
the existing D5 `IOSMediaTransferReconciliationHandoff`, and
`UIApplicationDelegate.handleEventsForBackgroundURLSession` routing. The
system completion handler is gated on both URLSession delegate-event completion
and Core reconciliation. No parallel post-sync handoff was introduced.

The executor now also implements:

- a persisted opaque execution token derived from a SHA-256 credential
  fingerprint; the same account/process relaunch reuses the token, a different
  account rolls it, and explicit Core/account detach clears it;
- versioned URLSession task descriptions carrying execution token, enclosure ID
  and deterministic local reference;
- cancellation of malformed/foreign/duplicate tasks;
- restoration of matching OS-owned background download tasks;
- startup/Core-attach reconciliation even without a buffered D5 request;
- creation of missing download tasks from Core `Requested` work;
- Core network-policy mapping to URLRequest expensive/constrained access;
- executor-token namespaced media paths so a later account cannot adopt an old
  account's files;
- synchronous move of the URLSession temporary file into the durable Media root
  inside `didFinishDownloadingTo`;
- delayed Core `downloadFinished` acknowledgement after that durable move;
- recovery where an already-moved file plus durable Core `Requested` state is
  recognized and acknowledged after a later bootstrap/reconciliation;
- transfer failure callbacks through the app-wide Core execution gate;
- DeleteRequested file deletion followed by Core `downloadDeleted`;
- shared deterministic/safe file-layout semantics with the frozen macOS path.

The executor intentionally does **not** keep a second durable Swift completion
queue. Generic orphan-file deletion is also deliberately not performed because
the current Core API does not expose a complete global list of all
`Downloaded` rows; deleting files merely because they are absent from
`downloadsRequiringTransfer/deletion` would remove valid completed downloads.

The persistent transfer core through this point was validated by the canonical
iOS test gate and macOS app build. The final D6-B integration dependency is now
implemented together with D6-C: DeleteRequested work consults the authoritative
app-scoped playback runtime and defers physical deletion while that enclosure is
still prepared/in use. Playback-use changes request another reconciliation, so
deferred deletion is retried after the native player releases the enclosure.
This final cross-package wiring is validated by the canonical iOS test gate.

- stable background-session identifier per app identity;
- background URLSession delegate;
- native execution-generation/task-description identity;
- D5 handoff installation;
- OS-task/Core/file reconciliation;
- AppDelegate background-session relaunch callback;
- Core callbacks and filesystem recovery;
- cancellation/deletion/in-use semantics;
- focused process/lifecycle recovery tests.

### D6-C — Playback + AVAudioSession

**Implementation status:** **CLOSED / testvalidated.** iOS now has an app-scoped
`IOSMediaPlaybackCoordinator` under `IOSMediaRuntime`, an
`IOSAVPlayerPlaybackEngine`, and an iOS-specific
`IOSMediaAudioSessionCoordinator`. Core calls are asynchronous and pass only
through the existing `IOSCoreSessionExecutionCoordinator`; no Swift media
domain persistence was added.

The current slice implements:

- AVPlayer prepare/play/pause/stop/seek/skip and 0.5x-3.0x rate;
- local downloaded-file preference with remote HTTP(S) fallback;
- InProgress resume position from `PlaybackPreparation`;
- chapters and transient article/feed/artwork metadata;
- approximately 20-second checkpoints while playing;
- checkpoints on pause, stop, seek, scene deactivation, interruption, route loss
  and Core replacement;
- Core completion, restart and observed-duration callbacks;
- spoken-audio `AVAudioSession` playback configuration with AirPlay and
  Bluetooth A2DP support;
- interruption handling with conditional resume;
- old-route-device-unavailable handling;
- background audio mode in Info.plist; scene deactivation checkpoints but does
  not pause playback;
- sleep-timer semantics without unloading the prepared item;
- successful account/Core replacement explicitly unloads the previous account's
  player item before attaching the new Core; aborted replacement resumes the
  original Core without destroying playback;
- explicit detach is synchronous for player ownership and presentation reset;
  progress checkpointing remains in the ordered pre-quiescence replacement hook;
- playback ownership wired into D6-B deletion deferral;
- focused fake-engine/fake-audio-session tests for resume position, checkpoints,
  interruption, route loss, playback rate, completion, duration and sleep timer;
- canonical iOS tests and macOS build are green for this runtime slice;
- AVAudioSession activation/deactivation is serialized off the MainActor to avoid
  the simulator/runtime main-thread hang warning while keeping the iOS 17 API floor.

Now Playing/remote commands remain absent and therefore stay in D7.

- AVPlayer engine and iOS playback coordinator;
- app-wide playback state;
- Core checkpoints/completion/restart/duration;
- AVAudioSession category/activation/interruption/route handling;
- audio background mode;
- chapters, rate and sleep timer;
- local/remote source fallback;
- lifecycle/relaunch tests.

### D6-D — Listening List native presentation

**Implementation status:** **CLOSED / testvalidated.** D6-B and D6-C runtime/execution are closed and testvalidated. The
first two D6-D Listening List/Player slices passed the canonical iOS test gate
(and the shared Reader change also passed the macOS build). D6-D now owns the
user-facing iOS media presentation over those app-scoped runtimes. The Listening List remains a separate read model and
does not route through the frozen UIKit Article Timeline or its ArticleQuery
fallback.

The first D6-D slice now provides:

- app-scoped-session-aware `IOSListeningListStore` using
  `listeningListFeeds()` + `listeningList(feedId:sort:)` through the existing
  `IOSCoreSessionExecutionCoordinator`;
- Recently Added / Publication Date sorting;
- optional feed filtering with Core validation of stale feed selections;
- a native empty/loading/error/list presentation;
- News-centered rows with feed/date metadata, enclosure count, playback
  progress and download summary;
- live row progress sourced from the existing app-wide playback presentation
  state rather than a second player model;
- Listening List is exposed from native iOS navigation as a Search-style
  fly-over action rather than as the active Article List detail scope;
- opening the fly-over reloads the dedicated `IOSListeningListStore` without
  mutating the currently selected News scope, so dismissing it restores the
  exact underlying News context;
- the Listening List owns its own `NavigationStack`, while its Player is
  presented as a child sheet of that fly-over so closing Player returns to the
  Listening List and closing the Listening List returns to News;
- shared/Core `BrowserScope.listeningList` remains intact for cross-platform
  semantics and macOS; native iOS no longer selects it from the navigation UI.

The second D6-D slice now additionally provides:

- native Player sheet over the existing app-scoped playback coordinator;
- Play/Pause, ±15/30 second skip, seek slider and restart;
- 0.5x-3.0x playback-rate selection;
- chapter selection/seeking from the already-loaded Core chapters;
- multiple-enclosure selection without creating another playback owner;
- per-enclosure Download / Cancel / Retry / Delete actions backed by the
  existing Core mutation APIs;
- Listening List removal;
- all download mutations fan back into the existing D6-B reconciliation
  handoff rather than a parallel executor path;
- Show Notes loaded with `readerDocument(articleId:)` through the same
  Core-session execution gate and rendered by the existing
  `ReaderDocumentContent`;
- `ReaderDocumentContent` now permits an absent Open Original action so Player
  Show Notes can reuse the Reader renderer without fabricating an
  `ArticleSummary` or URL;
- focused presentation coverage for active-enclosure/runtime-progress selection
  and download summaries.

The final D6-D implementation slice now additionally provides:

- Player artwork from the existing `MediaArtworkSource` contract;
- preview artwork is resolved through the existing canonical Core
  `MediaArtworkSource` selection while merely previewing a Listening List
  item, preserving the normal Image Enclosure -> embedded local artwork ->
  Article Image fallback order without preparing/replacing active playback;
- player Sleep Timer presentation over the existing app-scoped
  `IOSMediaSleepTimer`, including 30–180 minute intervals and live remaining
  time;
- playback-speed presentation with quick presets plus 0.1x adjustment across
  the existing 0.5x–3.0x coordinator contract;
- Stop as a distinct playback action: it checkpoints the current position,
  preserves the prepared enclosure for later resume, and releases AVAudioSession;
- player Download / Cancel / Retry / Delete controls sourced from the existing
  Core download projection plus app-scoped transfer runtime;
- Show Notes are an inline disclosure inside the Player's existing ScrollView;
  expanding lazily requests the existing Reader document, renders it with the
  shared `ReaderDocumentContent`, keeps loaded content available when collapsed,
  and reports loading/error/retry inline without a second modal sheet;
- the resolved playback source is projected as local/remote presentation state;
  local file playback suppresses transient AVPlayer loading/buffering chrome,
  while remote loading/buffering uses a delayed 300 ms circular wait indicator
  around the Play/Pause control instead of a separate bottom status row;
- chapter presentation marks the active chapter and scrolls to it once when the
  chapter list opens, while subsequent runtime position updates never steal the
  user's manual chapter-list scroll position;
- local artwork bytes through `core.mediaArtwork(reference:)` on the existing
  iOS Core-session execution gate;
- remote HTTP(S) artwork fallback using the same Phase-C source semantics;
- UIImage validation at the presentation boundary, with a neutral waveform
  placeholder for missing/invalid artwork;
- a small size-class-driven Player layout policy: compact portrait is stacked,
  while regular iPad and compact-height landscape use a side-by-side
  artwork/controls layout;
- `ViewThatFits` fallback for the secondary Player action controls;
- focused tests for local artwork resolution and adaptive layout-policy
  selection.

No persistent mini-player, MediaPlayer API, Now Playing, remote commands or
ActivityKit work was introduced; those remain D7/D8 as contracted.

The original D6-D canonical iOS validation passed. A 25 September 2026
post-closure audit found and corrected a preview-artwork fallback gap, incomplete
German D6 localization, and a fixed-simulator assumption in the canonical iOS
test script. The corrected implementation state through
`7acb079d77a1e5812964abd382a2fd43e6067b77` was then revalidated successfully:
`cargo fmt --manifest-path core/Cargo.toml --all -- --check` passed, the Rust
workspace passed with 224 `flux-core` tests plus 6 `flux-uniffi` tests and no
failures, and `./apple/ios/Build/test.sh` passed 448 iOS tests with 0 failures.
The D6-D architecture remains closed.

- real Listening List store/read model;
- restore navigation entry;
- iPhone/iPad adaptive list;
- feed filter/sort;
- multiple enclosures;
- progress/download presentation;
- Player presentation entry points.

### D6-E — Article/media actions

**Implementation status:** **CLOSED / testvalidated.** D6-D is closed and testvalidated. D6-E now wires media
semantics into ordinary article actions without changing the frozen Timeline
geometry/image/Scrollover architecture. Audio availability comes only from the
batched Core projection; visible cells never issue per-row media queries.

The first D6-E slice now provides:

- generation-safe batched `articleAudioActionStates(articleIds:)` projection
  for the loaded News Timeline;
- the same batched projection for Search results, preserving the existing
  shared swipe-configuration semantics;
- projection cleanup on Timeline row removal, account detach, Search clear and
  new Search generations;
- native Article context-menu Audio actions for Play, Add/Remove Listening
  List and per-enclosure Download/Cancel/Retry/Delete;
- multiple audio enclosures represented as native submenus;
- semantic `Listening List` toggle and `Download Audio` added to the existing
  configurable swipe action set without changing the zero/one/two-per-side
  storage contract;
- the Listening List swipe action is derived only from the batched article audio
  projection, renders Add or Remove from current Core membership, and is omitted
  for rows without audio;
- conditional swipe rendering: Download Audio is omitted for rows without
  downloadable audio and never promotes another conditional action into Full
  Swipe;
- multiple downloadable enclosures use a native chooser before the
  enclosure-specific mutation;
- article Play opens the same app-scoped D6 Player runtime; no second player
  state is created;
- News and Search media mutations both fan into the existing D6-B transfer
  reconciliation handoff;
- Player/download chooser presentation follows the existing frontmost-surface
  rule so Search-sheet actions present above Search rather than behind it;
- focused tests for Download Audio configuration and conditional downloadable
  enclosure filtering.

- batched article audio projection;
- Play / Listening List / Download actions;
- multi-enclosure chooser;
- enable configured Download Audio swipe action;
- no structural Timeline changes.

### D6-F — Media policies/settings

**Implementation status:** **CLOSED / testvalidated.** The existing CoreSettings and FeedPreferences remain
authoritative; iOS adds no parallel persistence.

The first D6-F slice provides:

- a native Media settings destination;
- Download Network policy: Any Network / Unmetered Networks Only;
- Download Retention: Forever / 7 / 30 / 90 days;
- Delete Download After Playback;
- Automatically Download Listening List Audio;
- Remove Completed Items from Listening List;
- rollback/error presentation when a Core settings write fails;
- successful global media-policy writes request the existing D6-B transfer
  reconciliation handoff;
- per-feed "Automatically Download Audio" in the existing Feed Settings view;
- successful per-feed auto-download changes request the same transfer
  reconciliation handoff;
- Core/session access stays behind the existing
  IOSCoreSessionExecutionCoordinator;
- focused CoreSettings read/write coverage and unconfigured feed-setting
  failure coverage.

- global media settings;
- per-feed automatic-download setting;
- transfer reconciliation when policy changes where required;
- localization/accessibility.

### D6-G — D6 integration/acceptance

**Implementation status:** **OBSERVATION / FINAL-FREEZE GATE — implementation
stable and testvalidated; physical-device UX observation plus remaining
process-boundary acceptance retained.** The current implementation is explicitly
stable enough for D7 to begin. Ordinary Player/Listening-List presentation
polish may continue during the observation window, but later phases must consume
the existing app-wide playback runtime rather than depend on the mutable SwiftUI
layout. The authoritative acceptance matrix and closure evidence are recorded in
[IOS_D6_FINAL_ACCEPTANCE.md](IOS_D6_FINAL_ACCEPTANCE.md).

Validate at least:

- stream remote media;
- play downloaded media;
- resume/checkpoint/restart/completion;
- chapter seek and show notes;
- interruption and route change;
- background audio while app is inactive;
- background download while suspended;
- process kill/relaunch with active background transfer;
- transfer completion while foreground UI is absent;
- cancel/retry/delete;
- network-policy waiting/recovery;
- account replacement/removal with outstanding transfer;
- Rebuild with media state;
- multiple enclosures;
- Listening List on compact iPhone and regular iPad;
- D5 background-sync -> existing transfer handoff -> D6 executor;
- no regressions in frozen UIKit Timeline, D4.5 sync or D5 fanout.

## 13. Recommended implementation order

1. **D6-0**: fix the concrete Core Rebuild/media inconsistency under tests.
2. **D6-A**: establish app-wide iOS media ownership and lifecycle.
3. **D6-B**: build persistent transfer execution and recovery before exposing
   Download actions.
4. **D6-C**: add playback/AVAudioSession over the same app-owned runtime.
5. **D6-D**: expose the Listening List and Player presentation.
6. **D6-E**: add article/swipe media actions using batched projections.
7. **D6-F**: expose policies/settings after the executor consumes them.
8. **D6-G**: run combined real-device/process-boundary acceptance.

This order avoids exposing UI actions whose native executor is not yet present,
keeps D5's handoff authoritative, and creates the playback state that D7/D8 can
later consume without moving those phases forward.
