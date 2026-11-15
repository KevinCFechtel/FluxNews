> **Status: historical product/reference evidence.** This document may describe FluxBar-specific current or legacy behavior. It is not authoritative for the shared Flux Rust-core target architecture. If it conflicts with `docs/ARCHITECTURE_DECISIONS.md`, the architecture decisions win.

# FluxBar Desktop Product Backlog

Items here are ideas/open questions. They are **not** automatically
implemented requirements.

## UI / Navigation

-   Tune the current 620 pt row and 390 pt card article widths.
-   Tune the current 200 pt sidebar width.
-   Tune the current 240 × 168 pt row thumbnail and 366 × 206 pt card image.
-   Evaluate whether a separate hover preview still adds value once
    article rows include rich teaser information.
-   Tune article keyboard mappings and configurable global-shortcut options.
-   Extend App Shortcuts only when additional actions have clear utility.
-   Consider search within feeds/articles if it fits the lightweight
    inbox model.

## Article Interaction

-   Tune hover quick-action set.
-   Tune context-menu ordering.
-   Evaluate optional swipe mappings after mouse/context-menu UX is
    solid.
-   Refine comment presentation when comment metadata is available.
-   Add numeric comment counts if the Miniflux/data model exposes them.

## Local Data and Sync

-   Add pagination or incremental loading beyond the 200-row snapshot.
-   Add an explicit disposable-image-cache clearing affordance if useful.

## Scrollover

-   Tune visibility percentage and dwell time from real desktop usage.
-   Finalize undo presentation/duration.

## Notifications

-   Implement opt-in per-feed notification preferences and native
    delivery.
-   Detect relevant newly synchronized content independently of sync
    completion.
-   Implement native batching/grouping before adding advanced rules.
-   Category-level notification preferences.
-   Keyword notification rules.
-   Per-feed silent/normal style.
-   Configurable batching behavior.

## Podcasts

-   Implement shared playback state and synchronized playback position.
-   Implement the native macOS mini player and Now Playing integration.
-   Implement chapters, playback speed, Stop, and Eject behavior.
-   Sleep Timer.
-   End-of-chapter and end-of-episode timer modes.
-   Refine mini-player Stop/Eject placement.
-   Refine chapter-selection UI.

## Cross-Platform

-   Windows native System Tray + popup implementation using the shared
    Go core/product semantics.
-   Linux StatusNotifier/AppIndicator-style integration with
    desktop-environment fallbacks.
-   Do not choose a shared UI toolkit merely to reduce implementation
    effort; reassess native options per platform.
