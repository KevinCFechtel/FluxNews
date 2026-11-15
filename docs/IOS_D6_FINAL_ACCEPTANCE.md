# iOS D6 Final Acceptance

Status: **HISTORICAL D6 ACCEPTANCE RECORD — implementation stable/testvalidated; UX observation remains non-blocking**

> Current replacement status: D9 and the physical Flutter-to-native production
> upgrade were accepted on 10 October 2026. The observation/final-freeze wording
> below records the D6 state at its September acceptance point and is not a
> current replacement-release blocker. `PHASE_D_NATIVE_IOS_IPADOS.md` is the
> current Phase-D status authority.

This acceptance record closes and testvalidates the implementation portion of **D6 — Native Media & Background Downloads**. The retained real-device UX observation window is non-blocking; later D7 and D9 acceptance proceeded over the stable app-wide playback runtime.

## Current closure state

D6-0 through D6-F were implemented and testvalidated at the last accepted
canonical head.

Subsequent 25 September media-UX follow-ups reorganized the native
`IOSMediaPlayerView` presentation hierarchy and the Listening List navigation.
Stop remains the fourth permanent transport control; playback speed and Sleep
Timer remain persistently visible; Downloads and Restart moved to the More menu;
chapter/audio selection became descriptive rows. Show Notes now expand inline
inside the Player's existing scroll surface rather than opening another sheet.
Remote loading/buffering is represented by a delayed circular indicator around
Play/Pause, while resolved local-file playback suppresses that transient chrome.
The native iOS Listening List now opens as a Search-style fly-over without
replacing the selected News scope, and its Player is a child sheet of that
fly-over. A cross-device playback regression found during Android/legacy
FluxNews interoperability testing was also corrected at both layers: Core no
longer queues a lifecycle checkpoint as a new remote intent when that checkpoint
equals the last known Miniflux progression, preventing an idle iOS device from
writing an old baseline back before the next fetch. After SyncCompleted, a
loaded but idle iOS player also adopts the reconciled Core playback position,
while actively playing audio is never force-seeked by remote sync. The
associated presentation/navigation/playback tests were updated. Because these
follow-ups are newer than the last accepted 448-test run, the canonical iOS
gate must be rerun before the new head is recorded as testvalidated.

The 25 September post-closure audit corrected three narrow follow-ups: Preview
artwork now uses the canonical Core artwork-source selection without preparing
playback; the German D6 media string catalog was completed; and the canonical
iOS test script now selects an available iPhone Simulator instead of assuming a
fixed model.

The final 25 September implementation state passed the canonical gates:

- `cargo fmt --manifest-path core/Cargo.toml --all -- --check`;
- `cargo test --manifest-path core/Cargo.toml --workspace`: 226 `flux-core`
  tests + 6 `flux-uniffi` tests, 0 failures;
- `./apple/ios/Build/test.sh`: 459 tests, 0 failures, `TEST SUCCEEDED`.

The current D6 implementation is therefore **stable and testvalidated**.
D6-G remains the final closure/freeze package. It is intentionally deferred
while the current Player and Listening List spend several days in real-device
UX use. Presentation-only refinements discovered during that observation window
may be applied without blocking D7, provided they do not change app-wide
playback ownership, Core durability/sync semantics, AVAudioSession/background
execution, or the stable playback-state projection consumed by later OS
integrations.

## Automated evidence already accepted

The current automated suite covers the deterministic parts of the D6 contract:

- Core rebuild preserves protected media/playback/download/Listening List state;
- app-scoped media runtime follows Core replacement, rebuild and detach lifecycle;
- playback restores an InProgress position;
- pause, seek/lifecycle and periodic playback checkpoints use the Core path;
- natural completion reports Core completion;
- AVAudioSession interruption and route-loss orchestration are covered with deterministic fakes;
- app backgrounding checkpoints without pausing the native player;
- playback speed, sleep timer, duration observation and local artwork access are covered;
- persistent background-transfer session identity is stable and launch-event enabled;
- transfer task identity and deterministic per-account media file layout are covered;
- account execution identity is stable for the same account and rolls for another account;
- D5 media-transfer reconciliation buffering/coalescing and executor attachment are covered;
- News/Search article audio actions use batched Core projection rather than per-row Core queries;
- multiple-enclosure download selection/presentation semantics are covered;
- Listening List runtime progress, download summary and adaptive Player layout policy are covered;
- global media CoreSettings and per-feed automatic-download preference access are covered;
- the frozen UIKit Timeline, D4.5 manual-sync path and D5 background-sync suite remain inside the canonical iOS test gate.

These tests prove native orchestration and ownership. They do not substitute for OS scheduling, suspension, audio-route or physical-device presentation evidence.

## D6-G real-device / process-boundary matrix

| ID | Acceptance case | Automated evidence | Remaining physical-device evidence |
| --- | --- | --- | --- |
| G1 | Remote streaming | URL/preparation/runtime paths covered | Start an undownloaded audio enclosure and confirm sustained playback and seek |
| G2 | Downloaded-media playback | deterministic media file layout + local-source preference implemented | Download media, disable network access, play the local file successfully |
| G3 | Resume/checkpoint/restart/completion | resume/checkpoint/completion covered | Pause/leave app/reopen, verify resume; exercise Restart and natural completion |
| G4 | Chapters + Show Notes + artwork | Core/presentation paths covered | Verify real chapter seek, Reader Show Notes and artwork/fallback presentation |
| G5 | Interruption + route change | deterministic AVAudioSession fake coverage | Exercise a real interruption and a real output-route loss/change |
| G6 | Background audio | scene lifecycle test proves no intentional pause | Lock/background app and verify playback continues |
| G7 | Background download while suspended | background URLSession configuration covered | Start a sufficiently large download, suspend/background app and verify completion |
| G8 | Process termination/relaunch during transfer | task identity/account namespace/recovery design covered | Terminate/relaunch under the normal OS/process-recovery case and verify transfer state is reconciled |
| G9 | Completion with foreground UI absent | delegate/Core completion path implemented | Let a background transfer finish while app UI is absent, then reopen and verify Downloaded/local playback |
| G10 | Cancel / Retry / Delete | Core/action presentation paths covered | Exercise each against a real transfer/file and verify final durable state |
| G11 | Network-policy waiting/recovery | CoreSettings + request expensive/constrained-network policy implemented | With Unmetered Networks Only, verify transfer waits on an ineligible network and resumes when an eligible network returns |
| G12 | Account replacement/removal with outstanding transfer | Core/session/account identity lifecycle covered | Exercise account replacement/removal with an active/pending transfer and verify no old-account file/task is adopted |
| G13 | Rebuild with media state | Core rebuild regressions + iOS runtime rebuild lifecycle covered | Rebuild with Listening List/playback/download state and verify protected state remains coherent |
| G14 | Multiple audio enclosures | Core/presentation/action semantics covered | Exercise chooser, independent progress/download state and playback switching on a real multi-enclosure article |
| G15 | Compact iPhone + regular iPad | size-class layout policy covered | Accept Listening List and Player UI on physical compact iPhone and regular iPad |
| G16 | D5 background Sync -> D6 transfer executor | D5 success fanout and reconciliation handoff covered | Allow a real background Sync to create auto-download work and verify D6 executes it without foreground app interaction |
| G17 | Frozen-Timeline / D4.5 / D5 regression smoke | canonical test gate green | Smoke normal News scrolling/actions, Manual Sync and existing background/widget behavior |

## Process-termination boundary

G8 is a **normal process-recovery** acceptance check, not a promise to override explicit user force-quit behavior. The acceptance objective is that persisted Core intent, background-session tasks, deterministic task metadata and filesystem state reconcile correctly when iOS later gives the app a normal opportunity to resume/relaunch.

Do not add a second Swift durable completion queue solely to manufacture a force-quit guarantee.

## Suggested physical-device order

Run the real-device checks in this order so earlier failures isolate the smallest subsystem:

1. G1-G5 — foreground Player behavior.
2. G6 — background audio.
3. G2, G10, G14 — foreground transfer/file semantics.
4. G11 — network-policy waiting/recovery.
5. G7, G9 — suspended background transfer/completion.
6. G8 — process-recovery transfer reconciliation.
7. G12-G13 — account/rebuild destructive lifecycle.
8. G15 — compact/regular presentation acceptance.
9. G16-G17 — D5/D6 integration and final regression smoke.

## D6 observation-window and closure gate

Current state: **implementation-stable / testvalidated / not yet
architecture-frozen**. D7 is allowed to proceed over the stable playback
runtime while D6 UI/UX remains under real-device observation.

Presentation-only changes remain permitted during this window, including Player
layout, spacing, labels/icons, chapter/Show Notes presentation, buffering chrome,
time formatting and Listening List presentation. Changes to playback semantics,
runtime ownership, Core/Miniflux durability, AVAudioSession/background behavior,
or transfer ownership are not considered ordinary UX polish and require an
explicit D6 contract review.

D6 may be marked **COMPLETE / architecture-frozen** when:

- the canonical iOS test gate remains green;
- the matrix above has no unresolved D6 regression;
- physical-device evidence confirms background audio and background URLSession behavior;
- process recovery does not adopt stale/foreign account work;
- compact iPhone and regular iPad media presentation are accepted;
- D5 background-sync transfer handoff is observed end-to-end at least once.

D7 Now Playing/remote commands/CarPlay and D8 ActivityKit/Dynamic Island are intentionally outside this acceptance record.
