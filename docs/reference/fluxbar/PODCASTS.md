> **Status: historical product/reference evidence.** This document may describe FluxBar-specific current or legacy behavior. It is not authoritative for the shared Flux Rust-core target architecture. If it conflicts with `docs/ARCHITECTURE_DECISIONS.md`, the architecture decisions win.

# FluxBar Desktop Podcasts and Media

## Current Implementation Status

Podcast playback is a target desktop capability and is not implemented in
the current native macOS prototype. This document specifies the intended
behavior; the existing synchronized-position concept must be preserved
when the player is added.

## Product Role

Podcast audio is an intentional exception to the browser-first web
article model.

``` text
Web article → browser
Podcast     → FluxBar player
```

FluxBar can provide a better integrated experience for an RSS podcast
enclosure than handing raw audio to the browser.

## Playback Position Synchronization

The existing product already supports synchronized podcast playback
position.

Desktop must preserve this workflow:

``` text
Listen on mobile
Stop at 37:24
      ↓
Open FluxBar on Mac
      ↓
Resume at 37:24
```

Reuse shared/core playback-position behavior where available rather than
introducing an independent macOS-only state model.

## Conditional Mini Player

Do not reserve permanent popover space when no episode is loaded.

When an episode is loaded, show a compact player in the lower portion of
the popover.

Concept:

``` text
╭────────────────────────────────────────────╮
│ [Art] Podcast / Episode                    │
│       Current chapter                      │
│                                            │
│       ━━━━━━━━━●━━━━━━━━━━━━               │
│       42:18                    1:37:22      │
│                                            │
│       ↶30      ❚❚      ↷30       1.5×     │
╰────────────────────────────────────────────╯
```

The ASCII layout is conceptual. Use native macOS controls and spacing.

## Required/Important Controls

Support:

-   Play
-   Pause
-   30 seconds backward
-   30 seconds forward
-   seek/progress
-   Stop
-   Eject
-   playback speed
-   chapter selection

## Stop vs Eject

These are distinct.

### Stop

-   halt playback
-   current episode may remain loaded
-   mini player may remain present

### Eject

-   stop playback if necessary
-   remove the episode from active player state
-   reset/clear the player presentation
-   allow the mini player to disappear

Do not collapse these semantics into one action without an explicit
product decision.

## Chapters

Chapter support is important.

Show the current chapter when available and provide a native chapter
selector that allows direct navigation.

Do not bury chapter navigation in a deeply nested settings screen.

## Playback Speed

Playback speed should be quickly accessible, for example:

``` text
1.0×
1.25×
1.5×
1.75×
2.0×
```

Reuse existing supported values if the core/mobile implementation
already defines them.

## macOS Now Playing

Integrate with macOS Now Playing/system media controls.

Publish appropriate metadata:

-   podcast title
-   episode title
-   artwork
-   duration
-   playback position
-   playback state

Respond to meaningful system commands such as Play/Pause and seek/skip.

Now Playing is a complementary system control surface. It does not
replace FluxBar's own mini-player controls.

## Player Presentation

The mini-player should stay compact in normal use.

If additional UI is needed for chapter selection or less common actions,
use progressive disclosure rather than permanently expanding the player.

Stop/Eject placement can be refined during prototyping.

## Sleep Timer

Sleep Timer is useful but lower priority than the core player.

It should not block V1.

If implemented, useful choices include:

``` text
15 minutes
30 minutes
45 minutes
60 minutes
────────────
End of chapter
End of episode
```

`End of chapter` is useful beyond bedtime scenarios and fits the
importance of chapter support.

## Open Questions

-   exact mini-player height/layout
-   whether Stop is permanently visible or in overflow
-   whether Eject has a dedicated icon
-   chapter selector presentation
-   final speed choices
-   Sleep Timer implementation priority
