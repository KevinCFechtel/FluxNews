> **Status: historical product/reference evidence.** This document may describe FluxBar-specific current or legacy behavior. It is not authoritative for the shared Flux Rust-core target architecture. If it conflicts with `docs/ARCHITECTURE_DECISIONS.md`, the architecture decisions win.

# FluxBar Desktop Notifications

## Current Implementation Status

Content notifications are not implemented in the current native macOS
prototype. This document specifies target behavior and must not be read as
describing an active notification or background-sync subsystem.

## Principle

Notifications should represent explicitly important new content, not
background synchronization activity.

Never notify merely because a sync completed.

## Default

Notifications should default to **off**.

The user explicitly opts into feeds for which new articles deserve
immediate attention.

Concept:

``` text
Notifications
├── Off by default
└── Selected feeds
    ├── Feed A   ✓
    ├── Feed B   ✓
    └── Feed C   ✕
```

Category-level preferences may be considered later if they fit the data
model cleanly.

## New Content

When background sync discovers new content:

-   only consider feeds with notifications enabled
-   avoid one notification per article when a sync discovers many items
-   group/batch multiple new articles from the same feed where
    appropriate

Single item example:

``` text
Feed Name
Article title
```

Multiple item example:

``` text
Feed Name
3 new articles

• Article A
• Article B
• Article C
```

## Navigation

Notification interaction should preserve enough context to open the
relevant article or feed.

Routing should reuse the same selection/navigation model used by
sidebar, Spotlight, and future deep links rather than implementing a
notification-specific filter state.

## Interruption Behavior

Ordinary RSS/news updates should use normal/passive notification
behavior.

Do not mark normal feed updates as critical or time-sensitive simply to
bypass Focus settings.

## Future Ideas

Potential future additions, not V1 requirements:

-   notification preferences per category
-   keyword-based notification rules
-   silent vs normal per-feed behavior
-   configurable batching windows
