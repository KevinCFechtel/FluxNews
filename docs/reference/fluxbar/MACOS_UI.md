> **Status: historical product/reference evidence.** This document may describe FluxBar-specific current or legacy behavior. It is not authoritative for the shared Flux Rust-core target architecture. If it conflicts with `docs/ARCHITECTURE_DECISIONS.md`, the architecture decisions win.

# FluxBar Desktop macOS UI

## Product Role

The macOS interface is a native Menu Bar news inbox.

The common workflow is:

``` text
Menu Bar
   ↓
Open popover
   ↓
Scan / triage articles
   ↓
Click interesting article
   ↓
Original page in browser
```

The interface should feel like a focused macOS utility rather than a
mobile application enlarged for desktop.

## Popover

Use a native popover/custom SwiftUI/AppKit surface rather than a
conventional `NSMenu`.

The popover is larger than a simple status menu because it contains a
real scrollable inbox. The row layout uses a 620 pt article column, while
the card layout uses 390 pt. Rows target a 620 pt height and cards may grow
to 760 pt. Both heights are capped to the visible frame of the monitor
containing the Menu Bar item with a 32 pt safety margin. These are current
tuning values, not compatibility requirements.

Use native system components/materials so macOS appearance changes,
including current/future system material and Liquid Glass behavior, can
be adopted naturally.

Avoid hand-building an imitation of Apple glass/card styling when system
behavior is available.

## Header

The header should remain compact and may contain:

-   sidebar toggle
-   current context/title
-   refresh/sync
-   settings entry

Do not turn the header into a large permanent toolbar. The compact header
uses native SwiftUI controls inside the popover content because the same view
is hosted by both an `NSPopover` and a fallback `NSPanel`; a window toolbar
would not provide consistent placement across those AppKit containers.

While the popover is visible, its refresh control is the only trigger for
an inbox sync. Scheduled background sync runs only while the popover is
hidden; navigation inside the popover reads the local SQLite snapshot.

Settings include a persisted Mark as Read on Scrollover toggle. The feature
is enabled by default.

## Menu Bar Item

The native status item uses the system variable-length width so short unread
counts do not reserve unnecessary Menu Bar space. When the popover or fallback
panel opens, the current width is frozen; unread-count changes may continue
visually while the menu is open, but the status-item anchor does not move.
After the menu closes, variable-length sizing is restored and the item adapts
once to the current count. It uses a template icon and shows the global unread
count according to the rules in `Counts` below.

## Collapsible Feed Sidebar

The preferred navigation is a sidebar hidden by default.

Collapsed:

``` text
╭──────────────────────────────────────────╮
│ ☰  FluxBar                        ↻  ⚙  │
├──────────────────────────────────────────┤
│                                          │
│              Article list                │
│                                          │
╰──────────────────────────────────────────╯
```

Expanded:

``` text
╭───────────────────┬──────────────────────────────────────────╮
│ Feeds             │ ☰  FluxBar                        ↻  ⚙ │
│                   │                                          │
│ ● All News        │              Article list                │
│ ★ Starred         │                                          │
│                   │                                          │
│ ▾ Technology      │                                          │
│    Heise          │                                          │
│    Ars Technica   │                                          │
│                   │                                          │
│ ▸ Development     │                                          │
╰───────────────────┴──────────────────────────────────────────╯
```

### Sidebar content

Provide:

-   All News
-   Starred
-   expandable Miniflux categories
-   feeds nested below categories

Selecting a category shows articles from all feeds in that category.

Selecting a feed shows that feed.

All News, each category, and each feed have an independently persisted
Unread/All filter. Unread is the default. Starred always includes both
read and unread starred articles, so the native sidebar does not expose a
separate Unread destination.

### Popover resizing

When the sidebar opens, expand the overall popover horizontally.

Do not significantly compress the article column.

Prototype concept:

``` text
row closed:
[ 620 pt content ]

row open:
[ 240 pt sidebar ][ 620 pt content ]

card closed:
[ 390 pt content ]
```

The sidebar is hidden by default. Opening it expands the popover by its
width and preserves the article-column width.

The native popover resize and the SwiftUI sidebar transition run as one
200 ms ease-in-out animation. `AppDelegate` changes the shown
`NSPopover` size inside an `NSAnimationContext`, while
`PopoverContentView` inserts or removes the sidebar with the same duration.
The utility-panel fallback animates to the same target size while retaining
its horizontal center and top edge. The app targets macOS 15 and uses SwiftUI
scroll geometry and phase callbacks to distinguish user scrolling from layout
changes during the resize. Reduce Motion disables both the SwiftUI sidebar
transition and the AppKit popover/panel resize animation.

The sidebar divider is an overlay on the sidebar's trailing edge. It must
not contribute additional layout width; otherwise the fixed popover width
and the SwiftUI content width disagree during resizing and cause visible
layout stutter.

The sidebar uses a native SwiftUI `List` with sidebar styling, sections,
hierarchical disclosure, selection, and badges. The outer composition remains
an explicit two-column `HStack`: `NavigationSplitView` negotiates its columns
inside the available width and cannot guarantee the exact 240 pt expansion
required by the AppKit popover without temporarily compressing the article
column. Keeping the article `ScrollView` in a stable detail view also protects
scrollover geometry during sidebar transitions.

## Article Row

macOS retains desktop-native hover, context-menu, keyboard, and popover behavior,
but article content semantics are aligned with the native mobile clients.

Three persisted presentation modes are available:

-   **Visual** — large 16:9 lead image above the article content.
-   **Visual Compact** — full-width feed/status metadata followed by a 4:3
    thumbnail beside the headline/publication row; preview text remains below.
-   **Compact** — text-focused layout without an article image.

Across all three productive variants the semantic order is:

1.  feed icon + feed/source metadata
2.  stable status accessories: Unread → Star → Comments → Audio
3.  article title
4.  publication row
5.  preview/teaser
6.  desktop-specific progressive audio/actions where applicable

The publication row shows either the localized absolute date/time or the
configured relative age. When Miniflux reading time is available it appears
inline with the publication value. Relative time uses the
`clock.arrow.circlepath` symbol; reading time uses `doc.text`, or
`headphones` for audio articles.

Feed icons use the Core-provided normal/dark variants. macOS prepares and caches
a display-ready circular image off the main UI path. Article rows use a 22 pt
icon; sidebar, Listening List, and player surfaces use 16 pt. If Core has no
icon, the native fallback is a circular accent-colored tile containing the
feed's first letter.

### Visual styling

Avoid permanently elevated mobile-style cards. Prefer clean spacing, neutral
normal state, subtle hover/selection feedback, native system colors/materials,
and minimal permanent chrome.

The Visual lead image remains approximately 366 × 206 pt in the current 390 pt
article column. Visual Compact uses a small 4:3 side thumbnail. These are
presentation tuning values rather than compatibility requirements.

### Interaction separation

Permanent row accessories communicate article state/availability. Mutation and
navigation controls remain desktop-native progressive actions: read/unread,
star/unstar, overflow, context menu, and keyboard shortcuts can appear on hover
without changing the semantic article content order.


## Article Interaction

### Main click

Clicking the main row opens the original article URL in the user's
configured/default browser.

### Hover quick actions

The native prototype reserves a stable action column so text does not
shift when frequently used actions appear on hover:

-   mark read/unread
-   star/unstar
-   overflow (`…`)

Do not permanently show a full action toolbar on every row.

Read articles are visually de-emphasized. The permanent star indicator
remains visible, while `circle.fill` represents the action to mark an
article unread.

### Context menu

Right-click and/or the overflow button should expose appropriate
actions:

-   Open in Browser
-   Mark Read / Unread
-   Star / Unstar
-   Share...
-   Open Comments when available
-   Copy Link
-   Open/Filter by Feed

Use the existing capability/data model. Do not invent unavailable
comment behavior.

These actions are implemented. Share uses the native
`NSSharingServicePicker`; article and comment links use the configured
default browser.

### Comments

The current model exposes a comments URL but no comment count. The native
row therefore shows a compact comments-availability icon and can open the
URL. A numeric count may be added when the data model provides one.

For example, a future count could appear as:

``` text
Feed · 18 min · 💬 12
```

The comment indicator may be clickable.

### Swipe

Swipe is optional convenience, particularly for trackpad users.

Possible mapping:

``` text
Swipe left  → read/unread
Swipe right → star/unstar
```

No action may be swipe-only.

Swipe actions are not currently implemented.

## Counts

-   The Menu Bar item shows the total unread count, is blank at zero, and
    displays `999+` above 999.
-   All News, category, and feed sidebar badges are unread counts.
-   The Starred badge includes read and unread starred articles.
-   The popover title shows the selection's matching total. With the Unread
    filter active it updates immediately for local read mutations, and retained
    scrollover rows do not keep this count elevated. With the All filter, it
    includes read and unread matches rather than only the currently loaded rows.
-   A browse snapshot returns at most 200 article rows even when its
    matching total is larger; pagination is not yet implemented.

## Sorting

Articles are sorted by Miniflux publication time. Oldest first is the
default; newest first can be selected from the header options menu. The
choice is persisted with the Keychain-backed native configuration.

## Preview

The product originally considered a separate hover preview.

Once article rows contain thumbnail, title, metadata, and teaser, the
need for a separate larger hover preview should be evaluated in the
prototype.

If retained, it should help answer "Is this worth opening?" and must not
become a full article reader.

This remains an open UI question.

## Keyboard

The article list supports native keyboard triage while preserving pointer
interaction:

``` text
↑ / ↓       move article selection
Return      open selected article in the browser
M           mark selected article read/unread
S           star/unstar selected article
Command-R   refresh
Escape      dismiss FluxBar
```

Keyboard-driven scrolling resets exposure tracking and is briefly
suppressed from Mark as Read on Scrollover. Mouse, trackpad, context-menu,
and hover actions remain unchanged and keyboard use is optional.

## Global Shortcut

A persisted global shortcut opens FluxBar idempotently. The default is
Option-Command-F; Control-Option-F and Disabled are available in Settings.
It uses the native Carbon hot-key API and does not require Accessibility or
Input Monitoring permission. If the status-item button has no usable screen
anchor, FluxBar presents the same SwiftUI content and `BrowserStore` in a
native floating utility panel rather than attempting custom popover
positioning.

FluxBar requests exclusive Carbon registration so a shortcut owned by
another process fails visibly instead of appearing registered while never
delivering events. Changing the preference replaces the active registration
only after the new combination succeeds. The event handler validates the
FluxBar hot-key identifier before opening the app.

## Spotlight and App Intents

Feeds and categories are accessible through Spotlight and App Intents.

Example:

``` text
⌘ Space
"Heise"
Enter
   ↓
FluxBar opens directly filtered to Heise
```

Implemented entities/actions:

-   FluxBar → open normal inbox
-   feed → open that feed
-   category → open that category
-   Show Starred
-   Refresh FluxBar

Feeds are good candidates for App Entities.

Feeds and categories are App Entities backed by a small persisted projection
of the local navigation catalog. Classic Core Spotlight items expose only
feed/category names and IDs. Individual articles are not indexed. All actions
and Spotlight results enter `NavigationRoute` and then the same
`BrowserStore.route(to:)` path used by the sidebar.

## Native UI Implementation Status

Implemented in the current prototype:

-   Menu Bar item
-   native popover
-   compact native-control header shared by popover and fallback panel
-   collapsed-by-default sidebar
-   animated horizontal sidebar expansion
-   All News/Starred with per-destination Unread/All filtering
-   native sidebar list with expandable categories/feeds
-   stable-width article content column
-   persisted Visual / Visual Compact / Compact article-list layouts
-   shared native article information hierarchy and publication/reading-time row
-   prepared circular feed icons with first-letter fallback
-   hover state
-   read/star/overflow actions
-   right-click context menu
-   browser opening
-   native sharing and link copying
-   unread navigation/status counts
-   persisted sorting and per-destination filters
-   SQLite-first local rendering with background refresh
-   desktop-safe Mark as Read on Scrollover
-   compact localized automatic-read Undo overlay
-   shared sidebar/Spotlight/App Intent routing
-   feed/category Spotlight indexing and App Entities
-   configurable global shortcut with native fallback panel
-   article keyboard selection and triage actions

The conditional podcast player is specified separately in `PODCASTS.md`.
It is not yet implemented.

## Open UI Questions

-   tune the current 620 pt row and 390 pt card widths
-   tune the current 240 pt sidebar width
-   tune the 240 × 168 pt row thumbnail and 366 × 206 pt card image
-   exact typography and spacing
-   whether separate hover preview remains useful
-   exact hover button set
-   exact context-menu ordering
