# Shared Native Mobile Product Semantics

> **Scope:** Product and behavior contract shared by future native iOS/iPadOS and Android clients.
>
> This document captures mobile semantics that must not be rediscovered independently per platform. It does **not** prescribe SwiftUI/UIKit, Jetpack Compose/Android View, lifecycle, gesture-recognizer, browser, scheduler, credential-store, or media-framework implementation details. Platform-native presentation remains preferred.

## 1. Architecture boundary

The Rust Core remains authoritative for domain models, Miniflux networking, SQLite persistence, sync/reconciliation, offline mutations, article/Reader processing, search, feed preferences, notification candidates, widget projections, media/listening/download domain state, playback progress, policies, and retention.

Native mobile clients own platform presentation and navigation, gestures, visible snapshots, lifecycle integration, credential storage, browser/share presentation, background execution, notification delivery, widgets, runtime media playback/transfers, automotive UI, and other OS integrations.

Do not create a parallel Swift/Kotlin Miniflux or durable domain layer around Core functionality.

Platform-specific networking integration must preserve the platform's native trust decisions. The Apple implementation uses platform trust through the Rust TLS integration. A native Android implementation must explicitly validate equivalent Android system/user trust behavior rather than copying the Apple mechanism or introducing a second Kotlin Miniflux client.

## 2. Account and local-state lifecycle

Account credentials and custom HTTP headers are stored in the platform-native credential facility and used to configure/validate the existing Core contract.

The following actions have distinct semantics:

- **Rebuild Local State:** preserve account credentials, global preferences, and compatible account/feed preferences while rebuilding reconstructable synchronized Core state.
- **Remove Account:** remove credentials, account-bound Core state, account/feed preferences, and account media while preserving global application/display preferences.

There is no general FluxNews Factory Reset product action.

Legacy Flutter migration is copy/import-only and must not become an ongoing dependency. After migration, the native client operates solely on native/Core-owned state.

## 3. Background Sync semantics

`Background Sync` is the single user-facing preference controlling ongoing non-manual automatic synchronization on native mobile clients.

When **off**:

- no scheduled background news sync;
- no automatic foreground/resume sync;
- manual sync remains available.

When **on**:

- the platform may schedule appropriate background refresh work;
- foreground/resume may perform a fallback/complementary sync when freshness policy says it is needed;
- do not start a duplicate sync when one is already running or a sufficiently recent background sync already succeeded.

The mandatory initial/bootstrap sync after account setup is independent of this preference.

There is no separate mobile `Sync on Start` preference.

The scheduling mechanism is platform-specific: for example BGTaskScheduler on Apple platforms and an appropriate Android scheduler/lifecycle mechanism on Android.

## 4. Navigation and list state

`BrowserScope`/the equivalent Core-backed scope selection is the source of truth for the selected All News, Starred, Category, or Feed scope. Platform UI must not create a second durable selected-feed/category truth.

Expansion state, drawer/sheet visibility, and similar presentation state remain platform-local.

`Unread Only` and article sort direction are transient Article List presentation controls, not persistent global Settings.

A semantic list reset caused by scope/filter/sort or another explicitly defined reset event returns the Article List to its natural starting position. The mechanism is platform-specific. iOS keeps the owned Timeline controller and moves its collection view to the natural scroll edge so the system navigation chrome follows its normal Large Title behavior; Android must use its own native list/navigation semantics rather than copying that implementation.

Feed icons, including available normal/dark variants from Core, should be used by native clients rather than independently deriving another icon model.

Article-row accessory order is semantic and stable. Measured from the visual outer edge inward in a horizontal group, or from the top downward in a vertical rail, the order is: **Unread → Star → Comments → Audio**. Optional audio duration belongs to the Audio accessory and must not become an independent slot. Platform/layout variants may change the axis but not this semantic ordering.

Native mobile clients provide the retained article presentation modes **Compact**, **Visual**, and **Visual Compact**. Across productive variants, feed/source metadata precedes the headline and the publication row follows the headline. The publication row uses either the localized absolute publication date/time or the configured localized relative age. When Miniflux reading time is available, it is shown inline with that publication value rather than becoming a separate row. Miniflux `reading_time` is persisted and projected through Core/UniFFI; native clients must not independently estimate it.

Visual Compact must retain its article title; adding publication or reading-time metadata must never collapse the headline. Article audio availability is consumed from a batched/article-level Core projection. Productive list rows must not perform per-row enclosure/media queries merely to populate the Audio accessory.

On native iOS/iPadOS, standard Visual portrait additionally uses the accepted full-content-width 16:9 image and the publication row uses the current Apple iconography/layout described by the frozen UIKit Timeline contract. The removed reduced-width image/info-rail experiment is an iOS implementation history, not an Android requirement. Android should express the same content semantics using its native layout and image pipeline.

## 5. Article routing and Reader

Link/Reader choice and feed-specific detail-rendering preferences are shared product semantics. The native platform chooses the appropriate browser presentation.

Supported article actions should preserve current Core/native semantics where available, including open original, explicit Reader, comments, open in Miniflux, copy link, native share, and configured Miniflux third-party-service actions.

Do not copy an Apple browser implementation to Android or vice versa; preserve the routing behavior and use the native platform facility.

## 6. Mark as Read on Scrollover

Scrollover is a product behavior, not an Apple-specific gesture implementation.

The intended semantic rule is:

> An unread article that has satisfied the exposure/qualification requirement and is then genuinely moved completely past the upper Scrollover boundary by user-initiated forward scrolling is marked as read.

Required invariants:

- sufficient exposure/qualification is required; merely jumping past an unseen article must not mark it read;
- qualification survives a scroll-direction reversal;
- crossing geometry is rebased across direction reversals so stale motion does not cause missed or false crossings;
- reverse movement must not mark an article read;
- a valid forward crossing emits the read action exactly once;
- programmatic list movement, scope resets, layout changes, and structural row removal must not count as Scrollover;
- fast movement may process multiple genuinely crossed, already-qualified articles but must not qualify unseen articles merely because they were skipped;
- Undo semantics remain available where the native client exposes Scrollover.

Each platform should implement these semantics using its native scroll/geometry facilities. SwiftUI/UIKit tracker details are not part of the Android contract.

For iOS/iPadOS, the accepted details in
[Phase D](PHASE_D_NATIVE_IOS_IPADOS.md#iosipados-article-timeline--uikit) define
qualification as observed visibility, without a minimum exposure duration, and
define the narrow terminal exception: a genuine forward arrival at the content
bottom may complete observed visible trailing rows. This is not permission to
mark unseen skipped rows or arbitrary newly visible rows after leaving the
bottom. The UIKit Timeline amendment preserves these existing iOS product rules;
it does not select an Android renderer or introduce Android-specific behavior.

## 7. Swipe actions

Swipe behavior is represented as semantic article actions rather than hard-coded UI positions.

The mobile contract supports zero, one, or two configured actions per side. Visual order is inner-to-outer; the outer action is the Full Swipe action.

Interaction semantics:

- a normal/partial swipe reveals available action controls and performs no mutation by itself;
- tapping a revealed action executes it;
- a deliberate Full Swipe executes the outer action directly;
- reversing an open swipe first closes/crosses the neutral position before revealing the opposite side;
- platform implementations should use native-feeling thresholds, animation, and feedback.

Current default actions are Read/Unread and Star/Unstar on their established sides. Future configuration must preserve the semantic action model rather than storing platform widget details.

The retained configurable semantic action set is Read/Unread, Star/Unstar,
Open Original, Open in Miniflux, Open Comments, Share, Save to Third-Party
Service, Listening List, and Download Audio. A platform may expose a subset in
a particular gesture location when the remaining actions stay reachable through
native menus/overflow.

Conditional actions are omitted where their precondition is unavailable. The
Listening List action derives Add/Remove from the batched article-audio
projection and appears only for articles with audio; Download Audio appears
only when that same projection exposes at least one downloadable enclosure.
These media actions preserve the 0-2-per-side swipe contract and must never add
per-row Core media queries.

## 8. Scope-level Mark as Read

`Mark All as Read` is a mutation action and is not part of Filter/Sort presentation controls.

`Mark All as Read & Next` is an explicit workflow action, not the default behavior of Mark All as Read.

Its semantics are:

- Feed scope: mark the current Feed read, then navigate to the next Feed in visible navigation order;
- Category scope: mark the current Category read, then navigate to the next Category in visible navigation order;
- All News, Starred, Search, and Listening List do not invent a `Next` target;
- there is no wrap-around at the end;
- if no next sibling exists, the `& Next` action is unavailable;
- mutation must succeed before navigation occurs;
- plain `Mark All as Read` never changes scope.

## 9. Semantic mobile actions and overflow

Mobile UI actions should have stable semantic identities independent of where a platform presents them. Current/future examples include:

- `sync`;
- `filterAndSort`;
- `search`;
- `listeningList`;
- `markAllRead`;
- `markAllReadAndNext`;
- `settings`;
- `more`.

The default iOS/iPadOS Article List actions are Sync, Filter/Sort, and More. iPhone portrait exposes them in the Bottom Action Bar using a structurally distinct bottom-toolbar branch; its scope capsule is centered in an independent top safe-area inset and the Timeline keeps the native `.automatic` top edge effect on iOS/iPadOS 26+. Compact iPhone landscape instead returns the scope capsule to the native leading navigation toolbar and Sync/Filter/More to the native trailing toolbar, while disabling the Timeline top edge effect for that mode. When persistent split navigation is visible, the detail normally keeps the detached action capsule because the sidebar already communicates the selected scope; if the system reports a non-`nil` `toolbarVerticalEdge`, Sync/Filter/More instead become native top-toolbar items so iPhone Duo can place them in its vertical system bar. If the sidebar is hidden, the wider scope capsule with chevron remains horizontal in the detached inset row. Regular split modes keep the native automatic top edge effect regardless of whether the system bar is horizontal or vertical; the vertical preference changes only action placement. In the sidebar, category selection and category expansion are separate interactions so expanding or collapsing a selected category does not depend on List-selection behavior. This Apple layout is not an Android requirement.

Supported semantic actions may be configured into direct Article List action slots and ordered by user preference. An always-available overflow path must preserve access to applicable actions that are not shown directly. Configuration stores semantic action identities/order, never concrete SwiftUI/Compose control identities. Platform layout may limit how many configured actions are directly visible without changing the configured meaning.

Listening List functionality itself belongs to the media phase; representing its semantic action does not move media implementation into an earlier phase.

## 10. Widget product semantics

Each home-screen widget instance owns its own presentation configuration. The shared mobile configuration dimensions are:

- scope: All News, Category, Feed, or Bookmarks;
- read filter: Unread or All;
- sort: Newest First or Oldest First.

The read filter applies inside the selected scope; for Bookmarks, All means all retained starred articles and Unread means unread starred articles.

Widgets consume a bounded, versioned, credential-free projection prepared by the main app. A widget extension/provider must not initialize Core, open the production Core SQLite database, access Miniflux credentials, or perform Miniflux networking. Platform-specific storage, configuration APIs, widget families/sizes, icon files and routing mechanisms remain native concerns.

Article taps enter the normal FluxNews article-open path, including feed-specific routing. A widget does not own a separate Open in Miniflux preference.

## 11. Configuration backup and restore

Native mobile clients provide encrypted configuration export/import using the shared Core backup envelope plus a versioned platform-local settings payload.

Backup/restore is configuration handoff, not article/database/media backup. Account credentials, Core settings and compatible feed preferences follow the Core backup contract; platform presentation settings are validated by the native client before replacement.

Restore must be reachable both from normal Settings and from the account-required startup surface so a fresh installation can adopt a valid backup without creating a temporary account.

A backup is not implicitly cross-platform between iOS/iPadOS and Android. Cross-platform portability requires an explicit future contract for compatible platform payloads.

## 12. Localization baseline

The retained native-mobile production language set is English, German, Spanish, Galician, Dutch, Tamil, and Turkish.

Each native platform owns its localization resources and accessibility wording. Legacy Flutter ARB resources may be translation evidence during migration but are not runtime localization sources for a native client.

## 13. Support diagnostics

Native mobile Settings provide a user-facing Support Diagnostics destination with:

- a Debug Logging preference;
- retained-record count;
- a structured log viewer with timestamp, level, category, and message;
- newest-first display plus text search and level filtering;
- refresh and per-record copy;
- privacy-sanitized export through the platform-native share/file flow;
- confirmed Clear Logs;
- a concise privacy/retention explanation.

Normal support-level Info/Warning/Error records remain available when Debug Logging is off; Debug/Trace retention is gated by the preference. Legacy Clear Logs on Start is not part of the native product.

The exact platform log sink/view implementation remains native. Core diagnostics may be bridged into the support log, but platforms must not create a second authoritative durable application/domain log model.

## 14. Platform-native implementation rule

Shared semantics define **what the user-visible behavior means**. Platform implementations define **how that behavior is expressed natively**.

Examples that remain Apple-specific and must not become Android architecture requirements include:

- UIKit Timeline integration with native Large Title and scroll-edge behavior;
- `UINavigationController` lifecycle details;
- custom `UIPanGestureRecognizer` implementation;
- SwiftUI observation/per-row invalidation mechanics;
- Apple-specific ScrollView geometry integration.

Likewise, future Android/Compose-specific workarounds must not become requirements for the Apple client unless they reveal a genuine shared product/Core semantic.
