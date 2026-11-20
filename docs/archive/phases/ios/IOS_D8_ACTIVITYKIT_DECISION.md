# D8 — ActivityKit / Live Activities

> **Status: DEPRECATED FOR THE CURRENT REPLACEMENT ROADMAP / DEFERRED FOR A DISTINCT FUTURE USE CASE**
>
> Decision date: 26 September 2026.

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
