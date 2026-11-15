# iOS D7 — Now Playing, Remote Commands, and CarPlay

> **Status: COMPLETE / REAL-DEVICE ACCEPTED / ARCHITECTURE-FROZEN**
>
> Repository-first audit baseline: `main` at `8931fb2fff8284ef82f38b53634f8d2e699fa7d7` (25 September 2026).
> Completion state recorded against `main` at `a8a4bff4b0ff4df19cedd3bb55dad7a3b01453b7` (26 September 2026).
> Final acceptance recorded on 27 September 2026 after merge commit `e0fb13fccd11bfcc0ae2b9ba1c7477a79781f8bd`.
> `docs/PHASE_D_NATIVE_IOS_IPADOS.md` remains the authoritative Phase-D contract. D7 is implemented over the existing D6 runtime without changing the frozen Phase A/B/C, D5, or UIKit Timeline ownership boundaries.

## 1. Audit result

D7 can be implemented without a Rust/Core change and without changing the D6 playback architecture.

The current iOS ownership chain is already the required foundation:

```text
IOSAppRuntime
  -> IOSMediaRuntime                         app-scoped media owner
       -> IOSMediaPlaybackCoordinator        sole playback orchestrator
            -> IOSAVPlayerPlaybackEngine     sole native AVPlayer owner
            -> IOSMediaAudioSessionCoordinator
            -> IOSMediaPlaybackCoreAccess    narrow Core adapter
       -> IOSMediaPlaybackPresentationState  sole live playback projection
       -> IOSMediaTransferCoordinator
```

`IOSMediaPlaybackPresentationState` already projects the stable D7 inputs: loaded enclosure, feed title, media title, artwork source, chapters, status, position, duration, local/remote source, loading/buffering/error state, and playback rate. D7 must consume this state; it must not create another durable or independently mutable playback model.

The coordinator already owns prepare/play/resume, pause, stop, seek/skip, rate, completion/restart, artwork loading, checkpointing, Core lifecycle suspension/replacement, post-sync reconciliation, interruption/route behavior, and AVAudioSession activation/deactivation. D7 commands must dispatch into this coordinator rather than operate on AVPlayer directly.

The Core already exposes the read models needed for D7 browsing and playback: Listening List/feeds, `prepare_playback`, playback state, chapters, artwork, checkpoint/completion/restart and download/local-media resolution. Rust remains durable authority. No direct SQLite or Miniflux access is permitted in D7.

## 2. Proven Phase-C reuse

macOS `MediaRemoteControlCoordinator.swift` is a strong semantic reference. It already contains:

- `NowPlayingProjection` with normalized title/source title, duration, bounded elapsed time, effective/default rate, playback state, asset URL, and artwork bytes;
- fallback artwork behavior;
- `MPNowPlayingInfoCenter` publication;
- `MPRemoteCommandCenter` registration for play, pause, toggle, ±30-second skip, and absolute seek;
- explicit disabling of next/previous track and stop;
- artwork generation guards against stale async completion;
- fast elapsed-time publication separate from full metadata publication;
- cleanup of command targets and Now Playing state.

The semantic projection and command vocabulary are genuine Apple-platform reuse candidates. The concrete macOS coordinator is not copied wholesale because image types, runtime ownership/lifecycle, playback-coordinator types, and CarPlay are platform-specific.

### Shared extraction rule

D7-A should extract only platform-neutral Apple media semantics to `apple/shared/FluxApple`, for example:

- `AppleNowPlayingProjection` (or equivalent name);
- normalized duration/elapsed/rate/state rules;
- `AppleMediaRemoteCommand` semantic command enum;
- shared skip interval policy (currently 30 seconds).

Do **not** move `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`, `MPMediaItemArtwork`, AppKit/UIKit image construction, AVAudioSession, CarPlay scenes/templates, or app-runtime ownership into shared code. The shared layer remains a projection/policy layer, not a state owner.

## 3. Completion state

D7 is implemented in the native iOS target:

- the shared Apple projection/remote-command vocabulary lives in
  `apple/shared/FluxApple/MediaPresentation.swift`;
- iOS publishes the single D6 playback presentation through
  `MPNowPlayingInfoCenter`;
- `MPRemoteCommandCenter` commands route back into the existing
  `IOSMediaPlaybackCoordinator`;
- the CarPlay audio scene is declared in the native `Info.plist` and attaches
  to the process-scoped app/media runtime;
- CarPlay browsing and playback reuse Core-backed Listening List/media state and
  the same playback coordinator rather than creating a queue or second player;
- the native development signing/profile path includes the required CarPlay
  Audio capability;
- canonical iOS and macOS test/build gates are green at completion; and
- D7-A through D7-G are automated-test validated and real-device accepted,
  including CarPlay Listening List/feed filtering/navigation/Now Playing and
  system Now Playing, Dynamic Island, and Lock Screen behavior.

The audit text below remains the architectural contract that constrained the
implementation; it is no longer a list of missing productive features.

The D7 architecture is frozen. Changes require a new concrete regression or
product requirement.

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
- Skip backward/forward: coordinator skip, initially using the proven 30-second policy unless an existing product setting is discovered before implementation.
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

## 7. D7 implementation phases

### D7-0 — Contract and ownership audit — COMPLETE

This document is the output. No productive playback code changes are part of D7-0.

Acceptance:

- repository/current docs audited;
- Apple API/entitlement direction verified;
- ownership frozen before implementation;
- no Core change justified.

### D7-A — Shared Apple media projection — COMPLETE

Extract the proven semantic subset from macOS into `apple/shared/FluxApple` and migrate macOS to it without behavior change. Add focused shared tests for fallback titles, duration/elapsed bounding, rates, stopped/paused/playing projection, invalid URLs, and error behavior.

Gate: macOS tests remain green before iOS consumes the projection.

### D7-B — iOS Now Playing adapter — COMPLETE

Add the app-scoped iOS adapter under `IOSMediaRuntime`; publish title, feed/podcast, duration, elapsed time, effective/default rate, asset URL where valid, playback state, and artwork. Reuse existing artwork/Core access; no UI dependency.

Gate: unit tests with injected/fake Now Playing sink plus existing iOS suite/build.

### D7-C — iOS Remote Commands — COMPLETE

Register play/pause/toggle/skip/seek once, route only to the existing playback coordinator, remove registrations on cleanup, and explicitly disable unsupported stop/next/previous commands.

Gate: command dispatch/status tests, duplicate-registration test, no-loaded-item failures, seek bounds, and lifecycle cleanup.

### D7-D — System playback lifecycle and real-device Now Playing acceptance — COMPLETE

Validate lock screen, Control Center, headset/Bluetooth commands, background audio, interruptions, route changes, rate/elapsed publication, artwork replacement, pause/resume, Stop-from-app followed by remote Play, natural completion, and cross-device reconciliation while paused versus actively playing.

This phase is deliberately before CarPlay so the common OS media contract is stable first.

### D7-E — CarPlay scene, entitlement, and browsing — COMPLETE

Add the CarPlay scene manifest/configuration, scene delegate/coordinator, development signing strategy, Core-backed Listening List browser, feed navigation if retained, selection, loading/error/empty states, and bounded template item counts according to CarPlay APIs.

Gate: CarPlay Simulator browse/navigation tests plus source-level/unit tests for browsing projection and selection identity.

### D7-F — CarPlay playback integration — COMPLETE

Connect CarPlay selection to the existing playback coordinator, present `CPNowPlayingTemplate`, and verify transport controls/current playback are the same state as phone/lock-screen playback. No CarPlay-specific player or queue.

Gate: switching control between phone UI, lock screen/Control Center, and CarPlay never creates divergent state or duplicate playback.

### D7-G — Integration and real-device acceptance — COMPLETE

Run full Rust/native test gates and physical-device CarPlay acceptance. D7 closes only when Now Playing/remote commands and CarPlay pass the acceptance matrix below.

## 8. Automated test plan

Required focused coverage:

- shared Now Playing projection normalization and bounds;
- iOS publication with/without media, duration, artwork, errors, paused/stopped/playing states and non-1x rates;
- stale artwork completion cannot replace current artwork;
- elapsed-only update does not recreate unrelated metadata/artwork;
- remote play/pause/toggle/±skip/seek route to the one coordinator;
- unsupported commands are disabled;
- registration is idempotent and cleanup removes targets;
- media runtime attach/detach/Core replacement does not create a second adapter/player;
- CarPlay browse projection uses Core Listening List identity;
- feed filtering and multi-enclosure selection are deterministic;
- CarPlay selection calls the shared playback coordinator and never constructs a playback engine;
- CarPlay connect/disconnect owns templates only and does not stop/detach playback;
- scene-manifest and entitlement configuration have source-level regression coverage where practical.

Repository gates after each meaningful package:

- existing Rust workspace/Core tests;
- existing native iOS test script and app build;
- affected macOS tests/build when shared Apple code changes;
- `git diff --check`.

## 9. Real-device acceptance matrix

D7 requires evidence for at least:

- iPhone, app foreground: metadata/artwork/position/rate correct;
- iPhone locked/background: audio continues and lock-screen controls work;
- Control Center: play/pause/skip/seek update the in-app state correctly;
- Bluetooth/headset route: remote play/pause and route-loss behavior preserve D6 semantics;
- app Stop: audio session is released; later supported Play resumes the prepared item correctly;
- app Stop: system Now Playing and the Article List Now Playing action are
  cleared while prepared/loaded media state remains resumable; Pause retains
  Now Playing;
- natural completion and Restart remain correct after Now Playing integration;
- local downloaded media and remote streaming both publish/control correctly;
- sync reconciliation does not seek an actively playing item and can update paused/stopped progress as already specified by D6;
- CarPlay connect while idle, while paused, and while already playing;
- browse Listening List and optional feed grouping;
- select remote and downloaded items;
- CarPlay play/pause/skip and current playback presentation;
- disconnect/reconnect CarPlay without duplicate commands, duplicate AVPlayer, or playback loss;
- production/upgrade-test signed build carries the CarPlay audio entitlement;
- at least one physical CarPlay/head-unit or Apple-supported equivalent real-device path, not Simulator-only evidence.

## 10. Risks and mitigations

### CarPlay entitlement/provisioning — high external risk

Source configuration alone cannot grant CarPlay. Apple entitlement approval and the actual provisioning profile are release dependencies. Mitigation: verify signing early in D7-E, before polishing templates.

### Scene ownership — medium architectural risk

The current app intentionally disables multiple phone scenes. CarPlay adds a dedicated scene role. Mitigation: keep `IOSAppRuntime.shared`/`IOSMediaRuntime` process-scoped and make the CarPlay scene a presentation-only client. Do not instantiate Core/runtime from the CarPlay delegate.

### Duplicate remote registrations — medium runtime risk

Repeated coordinator creation can cause commands to fire multiple times. Mitigation: one adapter owned by `IOSMediaRuntime`, idempotent registration, explicit cleanup, and tests.

### Now Playing update churn — low/medium performance risk

The AVPlayer position callback is currently 0.5 s. Rebuilding artwork/metadata at that cadence is unnecessary. Mitigation: separate elapsed/rate publication from full metadata/artwork publication, following the proven macOS design.

### Artwork races — medium correctness risk

Artwork is asynchronous and the loaded enclosure may change. Mitigation: source/enclosure generation guards before publication.

### D6 UX observation overlap — low risk if boundary is respected

D7 must never observe SwiftUI geometry or button placement. Its only inputs are the app-scoped playback presentation state, playback coordinator, Core-backed browse read models, and stable runtime lifecycle. Player/Listening-List visual polish can therefore continue independently.

### Queue semantics — deliberate non-goal

D7 does not invent next/previous episode behavior, autoplay, Up Next, or a durable queue. These require a separate product/domain contract. `CPNowPlayingTemplate` is used for current playback without claiming queue semantics that Flux does not have.

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
