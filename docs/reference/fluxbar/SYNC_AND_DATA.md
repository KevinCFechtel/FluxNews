> **Status: historical product/reference evidence.** This document may describe FluxBar-specific current or legacy behavior. It is not authoritative for the shared Flux Rust-core target architecture. If it conflicts with `docs/ARCHITECTURE_DECISIONS.md`, the architecture decisions win.

# FluxBar Desktop Sync, Data, Cache, and Scrollover

## Current Implementation Status

The native application persists account-scoped inbox snapshots and
desired read/star mutations in SQLite. It renders the selected local
snapshot before starting Miniflux synchronization. Sync runs at startup,
after explicit refresh operations, when a stale popover closes, and
every 15 minutes while the app remains active and the popover is hidden.

Automatic mark-as-read-on-scrollover and its transient Undo affordance
are implemented and can be disabled in persisted settings. Undo is
offered only when one scroll event marks at least three articles. Remote
selections are fully paginated in 200-entry pages before negative
reconciliation. The local popover snapshot remains capped at 200 rows
for responsive presentation.

Rust is the normal FluxBar development core and reproduces local snapshots,
Miniflux remote behavior, refresh/reconciliation, effective versus remote state,
durable pending read/star mutations, successful-prefix flush, Undo/discard, the
10-second automatic-read delay, article preview/image extraction, localization,
and feed-icon processing/cache. Go is deprecated for future development but
remains the compatibility/reference implementation and explicit fallback.
Differential tests compare JSON, database state, pending/Undo rows, fake
remote requests, and processed article fields. Automated Rust tests use
temporary databases and fake credentials and never open the user's production
database or contact a real account.

The persisted state machine keeps effective `status`/`starred` separate from
`remote_status`/`remote_starred`. A pending row is the durable desired value
and prevents stale refresh data from replacing effective presentation state.
Only a fully paginated stable remote result can negatively reconcile absence.
Flush processes pending rows by update time, acknowledges each success, and
stops at the first failure, leaving the failed and unattempted suffix queued.

Automatic read batches record prior read values in durable Undo rows. Undo
restores those values and replaces or creates pending desired state; discard
only removes Undo metadata. The Swift affordance remains visible for eight
seconds while the core delay remains ten seconds. One resettable scheduler is
owned by each configured account service, so delayed work cannot cross to a
replacement account.

## Local-First Desktop Behavior

FluxBar Desktop should keep a local SQLite representation of news/state.

This is valuable even though full web articles open in the browser.

Primary reasons:

-   immediate popover rendering
-   responsive filtering/navigation
-   resilience to temporary connectivity loss
-   local state mutation without network latency
-   efficient background synchronization

Preferred flow:

``` text
Open popover
    ↓
Read SQLite immediately
    ↓
Render current inbox
```

Do not make opening the popover wait for Miniflux. While the popover is
visible, only the explicit refresh button starts an inbox sync.
Navigation continues to render local snapshots immediately. A successful
explicit refresh resets the presentation and scrolls the new snapshot to
its first row. Scheduled and stale-close refreshes preserve the current
position and continue to start only while the popover is hidden.

## Local State Changes

### Current behavior

Read/unread and starred actions commit effective state and a coalesced
desired mutation in one SQLite transaction. The local snapshot updates
immediately and remains authoritative for presentation while Miniflux is
unavailable. Read updates are retry-safe desired-state operations;
toggle-only starred updates re-read remote state before deciding whether
to toggle.

Rows marked read locally remain visible in the current unread-only list
until the user explicitly refreshes it. Pending flushes, scheduled
background sync, and subsequent scrollover batches retain those rows.
This prevents list geometry from collapsing during scrollover. Changing
the navigation/filter context starts a new presentation and clears that
retention.

### Synchronization contract

Read/unread and starred actions should update local state immediately.

If the server cannot be reached, changes should remain pending/persisted
and synchronize later through the established sync mechanism.

Concept:

``` text
User action
    ↓
Local SQLite/state
    ↓
Pending/current sync state
    ↓
Miniflux
```

Avoid duplicating sync semantics in the SwiftUI layer.

## Offline Scope

The locally persisted inbox can remain useful offline:

-   titles
-   feed/category metadata
-   publication time
-   URLs
-   read/unread
-   starred
-   teaser/snippet
-   cached thumbnails

This does **not** imply that FluxBar Desktop should become a complete
offline full-article reader.

Opening the publisher page in the browser normally requires
connectivity.

## Image Cache

Article images are lazy loaded and cached separately from durable state.

Treat image cache as separate from durable article/state data.

Implemented article-thumbnail behavior:

-   the first usable image in article HTML is preferred; when none
    exists, the first valid Miniflux enclosure/attachment with an
    `image/*` MIME type is used
-   relative HTML and attachment URLs are resolved against the article
    URL; only HTTP(S) image URLs are accepted
-   URL cache with 32 MiB memory and 256 MiB disk capacity
-   separate 64 MiB decoded-image memory cache
-   concurrent requests for the same URL are deduplicated
-   ImageIO downsamples images to at most 520 pixels before display
-   a 12-second request timeout and 10 MiB response limit
-   MIME validation and a placeholder for unavailable images
-   disposable
-   safe to clear without losing application state

Feed icons use a separate in-memory core cache, including regular and dark
variants, and deduplicate concurrent loads. Both implementations retry failed
or malformed loads rather than caching failure. Feed-icon bytes are not
included in browse snapshots and are not persisted to disk. The caches remain
unbounded process-local behavior inherited from Go.

An explicit cache-clear UI and an application-controlled age/LRU policy
remain open; the system `URLCache` and `NSCache` currently manage
eviction.

## Background Sync

Background sync is useful on desktop because it lets the Menu Bar inbox
remain current without requiring the user to open a full application.

Sync completion itself should not create a notification.

Notification behavior is defined in `NOTIFICATIONS.md`.

The native implementation performs a startup sync after applying local
state, refreshes after a stale popover closes, and schedules a 15-minute
sync while the Menu Bar process remains active. These automatic inbox
syncs only start while the popover is hidden; a visible popover requires
the explicit refresh button. Pending automatic-read changes use a short
delayed flush so Undo normally precedes remote delivery; manual
mutations request reconciliation immediately.

Miniflux selection sync uses stable ascending entry-ID cursor
pagination. Only an exact, fully loaded remote ID set is applied as
complete absence information. A failed, duplicated, reordered, or
count-inconsistent page leaves the last local snapshot intact. Miniflux
does not expose a lightweight ID/status projection for this endpoint, so
complete pages include normal entry payloads; SQLite still returns only
the first 200 locally sorted rows to SwiftUI.

## Mark as Read on Scrollover

The mobile-style "Mark as Read on Scrollover" workflow is valuable on
desktop but needs stronger safeguards because trackpad/mouse momentum
can move through many rows accidentally.

### Goal

As a user intentionally works downward through the inbox, articles they
genuinely saw and then passed can automatically become read.

### Visibility qualification

Do not mark read based only on a row leaving the viewport.

An article should first qualify as meaningfully seen.

Centralized current thresholds:

-   at least 60% of the row visible
-   visible for at least 0.7 seconds
-   subsequently leaves the viewport upward through normal scrolling
-   a single offset change above 85% of the viewport height is treated
    as a jump and resets qualification

Exposure timing runs only while the popover is visible and restarts each
time it opens. The current row geometry is retained across closing and
reopening so the initially visible row can begin qualifying before the
first scroll event.

These values should be centralized/configurable and tuned through
testing.

Conceptual state:

``` text
unseen
  ↓
visible
  ↓
qualifiedAsSeen
  ↓
scrolledPastUpward
  ↓
markReadLocally
```

### Do not mass-mark skipped content

The following should not be interpreted as reading progression:

-   dragging/jumping the scrollbar
-   programmatic scrolling
-   changing feed/category/filter
-   Spotlight/App Intent/deep-link navigation
-   restoring a previous scroll position
-   rows that pass too quickly to qualify as seen

Route changes suspend exposure tracking until the matching local SQLite
snapshot is installed. Keyboard scrolling uses the same centralized
reset and short programmatic-scroll suppression rather than adding
integration- specific read exceptions.

Scroll offset and user-scroll phase come from the macOS 15 SwiftUI
scroll APIs. Article geometry remains separate from the exposure state
machine. Geometry changes while the scroll phase is idle or
programmatically animated rebase article frames without discarding
already qualified visibility. This makes horizontal layout transitions,
including opening or closing the sidebar, ordinary layout changes rather
than AppKit observer pause/resume sequences and prevents layout movement
from being interpreted as user scrolling.

### Synchronization

Automatic read changes should use the same local-first/delayed
synchronization model as other read-state changes.

Do not force immediate Miniflux sync unless an explicit existing user
preference requests it.

### Undo

Provide a lightweight transient undo affordance after automatic read
mutations, for example:

``` text
5 articles marked as read · Undo
```

Undo should restore local state correctly and cooperate with pending
synchronization.

The Undo affordance appears when a single scroll event marks at least
three articles and remains visible for eight seconds. Smaller batches
are still marked read without presenting Undo. Undo either replaces an
undelivered desired mutation or enqueues the compensating unread state
if delivery already occurred.

Avoid building a large custom notification/banner framework solely for
this feature.

## Implementation Caution

Scroll visibility logic can affect many items quickly. Keep it testable
and separated from row rendering where practical.

Tests should cover:

-   item becomes sufficiently visible
-   item remains visible long enough
-   upward exit marks it read
-   fast pass does not
-   programmatic/jump navigation does not
-   filter/feed changes do not
-   undo restores expected local state
