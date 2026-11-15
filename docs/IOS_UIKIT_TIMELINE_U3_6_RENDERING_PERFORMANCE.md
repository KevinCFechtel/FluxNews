# U3.6 — UIKit Timeline Rendering Performance Repair

> **Status: HISTORICAL PERFORMANCE PACKAGE — U3.6.1, U3.6.2, U3.6.3, AND U3.6.4 COMPLETE**
>
> Container references in this document describe the implementation at the time
> this package was executed. The productive Timeline later migrated from the
> `UICollectionView` baseline to the current `UITableView` architecture.
> Current container/UI contracts are authoritative in
> `PHASE_D_NATIVE_IOS_IPADOS.md` and `IOS_UIKIT_TIMELINE_IMPLEMENTATION.md`.
>
> Baseline: `main` at `2dbec0d3fc0368b15d04ff679fd79dc5e6bcdfc7`.
>
> This package follows U3/U3.5 and precedes U4. It does not reopen the UIKit
> architecture decision. The purpose of U3.6 is to finish the performance
> separation that the owned `UICollectionView` Timeline was intended to provide.
> U4 remains a separate session-mutation-worker package.

## 1. Why U3.6 exists

The physical-device review in
[`Flux_iPhone15_Scrolling_Review_2dbec0d.md`](Flux_iPhone15_Scrolling_Review_2dbec0d.md)
confirmed visible movement holds in an iPhone 15 screen recording and identified
remaining synchronous work in the current UIKit Timeline. The review does not
prove the millisecond cost of each individual code path, but the relevant work
is visible in the production implementation and contradicts the intended
performance contract in several places.

The UIKit migration itself remains correct. U3.6 is therefore a repair of the
current native renderer and bridge, not another List-versus-UIKit experiment.
No SwiftUI Timeline fallback, third-party scrolling framework, custom scroll
physics, or framework benchmark is required before this work.

U3.6 is deliberately placed before U4. The visible rendering/scroll path should
be made cheap and deterministic before mutation scheduling is changed further,
so the two classes of work remain independently reviewable.

## 2. Scope

U3.6 contains four ordered implementation packages:

| Package | Scope | Gate |
|---|---|---|
| **U3.6.1 — Stable native cell renderer and sizing** | Stop rebuilding the cell hierarchy and image constraints during ordinary configuration. Make status changes geometrically neutral. Reuse measured heights for matching layout/content revisions. | Reconfiguring the same layout variant does not remove/reinsert arranged subviews or recreate structural constraints; matching measurements hit a bounded cache; Read/Starred/image-pixel changes preserve row height. |
| **U3.6.2 — Structural bridge plus targeted presentation deltas** | Remove full-list presentation work from status/icon events. Separate structural article revisions from read/starred/icon presentation changes. | A single status/icon change is O(changed IDs + relevant bound cells), not O(all loaded articles), and does not rebuild `itemsByID` or a full Timeline item array. |
| **U3.6.3 — Resolved visible-frame Scrollover sampling** | Stop querying a three-viewport layout region from every active scroll callback. Drive the detector from already-resolved visible/recent cell geometry and scroll offsets. | `scrollViewDidScroll` performs no broad layout-attributes query or forced layout; existing crossing/bottom/reversal semantics stay intact. |
| **U3.6.4 — Image request scheduling and consumer safety** | Bound decode/request execution, prefer visible demand over speculative prefetch, and make async completions consumer-generation safe. | Obsolete consumers cannot update a rebound cell; visible requests are not starved by prefetch; shared work is not cancelled while still consumed; concurrency remains bounded. |

The packages are sequential because U3.6.2 and U3.6.3 should operate on the
stable renderer established by U3.6.1. Do not silently fold U4 queue semantics
into these packages.

## 3. U3.6.1 — Stable native cell renderer and sizing

### 3.1 Permanent cell hierarchy

`IOSUIKitArticleCell.configure` currently removes arranged subviews from
`rootStack`, removes those views from the hierarchy, deactivates image-size
constraints, recreates constraints, and re-adds the views. This must stop for
ordinary reuse/configuration.

The cell owns permanent native UIKit subviews and permanent structural
constraints. Compact, visual portrait, and visual landscape are explicit layout
variants. Switching variants may activate/deactivate a prepared constraint set
or use variant-specific reuse identifiers/classes, but configuring another
article in the same variant must update values rather than rebuild structure.

Required behavior:

- no `removeFromSuperview` / arranged-subview teardown in the ordinary
  configuration path;
- no recreation of image width/height constraints for another article in the
  same layout variant;
- texts, image request identity, feed icon, preview-line count, accessibility,
  and presentation values remain configurable;
- portrait and landscape image geometry remains exactly aligned with the shared
  `ArticlePresentationLayout` policy;
- rotation/split-view/Dynamic-Type changes switch layout revision coherently and
  must not leave stale constraint sets active.

A fully manual text-layout engine is not required. U3.6 should first make the
existing UIKit/Auto Layout renderer controlled and reusable.

### 3.2 Geometrically neutral status presentation

Read, Starred, Undo feedback and loaded image pixels are presentation changes,
not structural sizing inputs.

The current star presentation uses `starImageView.isHidden` while the star is an
arranged subview next to the multiline title. That changes available title width
and can change row height. U3.6.1 must reserve stable star geometry or overlay the
star so toggling it has no effect on text width or row height.

The existing unread indicator keeps its geometry slot and changes visual opacity;
retain that behavior.

For an unchanged article content/layout revision:

- Read <-> Unread: same measured row height;
- Starred <-> Unstarred: same measured row height;
- placeholder <-> decoded image pixels: same measured row height;
- feed-icon fallback <-> decoded icon: same measured row height.

### 3.3 Bounded measurement reuse

`preferredLayoutAttributesFitting` must not invoke a new full
`systemLayoutSizeFitting` solve when an equivalent measurement is already known.
Introduce a bounded height cache owned by the Timeline renderer or a dedicated
presentation helper.

The measurement key must represent every input that can legitimately change
height. Equivalent designs are acceptable, but the key must cover at least:

- article/content revision or an immutable sizing-content identity;
- actual available content/text width;
- presentation mode and portrait/landscape layout variant;
- preview-line choice;
- Dynamic Type/content-size category and any typography revision that changes
  metrics;
- relevant locale/writing-direction inputs if they affect measured layout;
- whether the selected presentation variant includes an article image slot.

Read, Starred, feed-icon pixels, image pixels, and transient loading state are
**not** height-key inputs.

Cache rules:

- bounded memory use after a long 8,000-row scroll;
- cache hit returns the measured height without another Auto Layout solve;
- no synchronous measurement of the entire loaded history;
- width/Dynamic-Type/layout revision changes create a new coherent sizing
  revision or invalidate only incompatible entries;
- final cell layout and the measurement path must use the same sizing rules;
- preserve the visible article anchor across legitimate layout revisions where
  the existing controller already promises that behavior.

### 3.4 U3.6.1 tests

Add productive-path tests/spies where feasible. Do not satisfy these requirements
only with a recreated pure array helper.

Required coverage:

1. Reconfiguring two articles under the same layout variant does not rebuild the
   permanent cell hierarchy or recreate structural image constraints.
2. Measuring the same sizing key twice performs one solver measurement and one
   cache hit.
3. Different content/width/preview-lines/Dynamic-Type/layout variants do not
   incorrectly share a cached height.
4. Read and Starred transitions keep the same sizing key and measured height.
5. Placeholder-to-image and feed-icon fallback-to-image transitions keep the
   same sizing key and measured height.
6. Rotation portrait -> landscape -> portrait selects the correct variant and
   returns to the correct portrait sizing rules without stale constraints.
7. The measurement cache stays bounded after enough unique articles to exceed
   its configured capacity.

## 4. U3.6.2 — Structural bridge plus targeted deltas

The current SwiftUI `ArticleListView.timelineItems` maps every loaded article and
reads row presentation/icon state before the UIKit controller can decide that a
change is status-only. The controller then reconstructs `newIDs`, scans the full
item list, and rebuilds `itemsByID`. Snapshot suppression therefore occurs too
late to make a single status event cheap.

U3.6.2 must separate two channels:

1. **Structural/content channel** — stable ordered IDs plus immutable/sizing
   content, changing only when membership/order/content/layout-relevant data
   changes.
2. **Presentation-delta channel** — read/starred/feed-icon changes identified by
   stable Article ID (and feed ID/variant where appropriate).

Required properties:

- ordinary Read/Starred changes do not rebuild all Timeline items;
- one newly available feed icon updates matching bound/prepared presentation
  state without scanning every loaded article on the main-thread bridge;
- structural snapshot application remains restricted to membership/order/reset;
- content changes that actually affect text/image URL/sizing still invalidate the
  affected content/measurement correctly;
- a prepared/offscreen cell always resolves the newest presentation revision
  before display, without a full-cell reconfigure in `willDisplay`;
- Search continues to use the same native article collection infrastructure and
  observes the same status/icon correctness rules;
- no duplicate Swift durable/domain truth is introduced. Rust/Core and existing
  store semantics remain authoritative.

### U3.6.2 implementation

U3.6.2 is complete. `NewsreaderStore` constructs
`IOSUIKitArticleTimelineStructuralState` only when `replaceArticles` adopts a
new Core snapshot. The state contains ordered immutable article/content records
and a monotonic structural revision; it is the sole input that lets the UIKit
controller rebuild its ID map or apply a diffable snapshot. Presentation-mode
and preview-line changes remain explicit layout inputs, not status snapshots.

`IOSUIKitArticleTimelinePresentationBridge` is a MainActor-owned, retained
overlay between the stores and the controller. Article deltas carry an article
ID, read/starred values, and the row mutation revision. The bridge stores the
newest state by ID and rejects lower revisions before forwarding it. The
controller applies the state only to the matching bound cell; later
configuration resolves its retained latest state, which covers offscreen and
reused cells without height invalidation. Explicit unread deltas additionally
carry a targeted Scrollover rearm flag, eliminating the former whole-item scan.

Feed-icon completions publish a feed-ID/variant/image/revision delta through the
same bridge. The controller updates only bound cells whose prepared structural
feed ID matches and resolves the retained icon when a cell later binds. Search
owns its result structural state and status bridge, while it attaches the shared
Newsreader feed-icon bridge, so it continues to use the same UIKit renderer
without Timeline Scrollover behavior.

Production controller counters are covered by XCTest to assert that targeted
read, starred, unread-rearm, and icon deltas do not cause structural
reconciliation or a diffable snapshot. These are bridge-work contract tests,
not a device performance measurement.

## 5. U3.6.3 — Resolved visible-frame Scrollover sampling

The current sensor asks the collection-view layout for attributes in a region of
roughly three viewport heights on each active scroll callback. It is bounded, but
it still couples `scrollViewDidScroll` to collection layout and estimated nearby
geometry.

U3.6.3 changes the sampling source, not the product semantics.

Required implementation properties:

- keep resolved frames for actually visible cells and the minimal recently-exited
  geometry needed to prove upper-boundary crossings;
- update resolved frames when UIKit has completed/committed the relevant layout,
  without `layoutIfNeeded()` from `scrollViewDidScroll`;
- the scroll callback evaluates offset/direction plus already available bounded
  geometry only;
- prepared/prefetched but never-visible cells remain unqualified;
- layout generation/baseline changes continue to protect rotation, Dynamic Type,
  width/inset changes and structural resets;
- movement after a rebaseline in the same gesture remains detectable;
- preserve bottom completion, reversal behavior, small movement accumulation,
  rearm, terminal disarming and no-false-read guarantees already accepted in U3.

Do not replace the crossing model with exposure timing, debounce, `willDisplay`
semantics or a skipped-index heuristic.

### U3.6.3 implementation

U3.6.3 is complete. The controller records `IOSUIKitArticleCell.frame` values
from `willDisplay`, `didEndDisplaying`, and the already-resolved bounded
`collectionView.visibleCells` set. Cell frames, offsets, adjusted viewport
bounds, and content height all remain in collection-view content coordinates.
`scrollViewDidScroll` refreshes only that visible cell set and passes the
resolved source to the existing tracker; it does not ask the collection layout
for attributes or force layout.

`IOSUIKitResolvedScrolloverFrameStore` holds at most 96 source frames, retaining
the frames nearest the effective upper boundary. The tracker retains its existing
96-frame crossing window, for an explicit maximum of 192 retained frame records
across source and tracker. Both are explicitly bounded independently of loaded
article count. Recording `didEndDisplaying` preserves a just-exited resolved
frame, while refreshing `visibleCells` covers the converse callback order; the
tracker consequently evaluates either ordering against the same retained frame.

Width, Dynamic Type, insets, structural snapshots, and presentation layout input
continue to advance the controller layout generation and clear both resolved
source and tracker baseline. The next valid sample rebaselines during the current
interaction. Terminal completion remains in the tracker and still requires an
observed visible row plus a forward transition into bottom.

Regression tests cover the resolved source's callback-order retention and bound;
the established production tracker tests continue to cover forward/backward and
reversal behavior, sub-point movement, rearming, generation transitions, bottom
completion, initial-bottom safety, disabled state, and long-feed boundedness.

## 6. U3.6.4 — Image scheduling and consumer safety

The existing ImageIO downsampling, decoded-image cache, request deduplication and
fixed image slots remain valuable and must be reused.

U3.6.4 is limited to execution policy and consumer correctness:

- actor/request state must not serialize CPU-heavy decode work unnecessarily;
- use a bounded decode/request executor rather than unbounded task fan-out;
- visible requests outrank speculative prefetch without breaking request
  deduplication;
- cancellation is consumer-aware: cancelling one prefetch/cell consumer does not
  cancel shared work still required elsewhere;
- a cell binding receives a unique consumer generation/token in addition to
  request identity;
- success and error completion both require the same current binding and respect
  cancellation;
- an old consumer for request A cannot replace the image or placeholder of a new
  consumer that happens to request the same A;
- cache and request bookkeeping remain bounded.

Do not change image completion into a row-height/layout event.

### U3.6.4 implementation

`ArticleImagePipeline` now retains one job per normalized request with individual
consumer continuations. It starts at most three loader/downsampling operations,
drains visible requests before queued prefetch, and promotes a queued prefetch
when a visible consumer joins it. A cancelled consumer is removed independently;
only an operation with no remaining consumers is cancelled. The decoded cache and
request key remain unchanged. Pending metadata is capped at 48 visible requests
and 32 speculative requests; visible admission evicts speculative work first.

`IOSUIKitArticleCell` advances a local image-binding generation for every image
configuration and reuse. Both success and failure verify that generation, article
ID, request identity, and task cancellation before changing the image view. The
collection prefetch callbacks use the pipeline's explicit prefetch demand.

Tests cover the three-operation bound, visible-before-prefetch dispatch, shared
consumer cancellation, duplicate request coalescing, cache behavior, and ImageIO
downsampling.

## 7. Explicitly outside U3.6

Do not implement these as part of U3.6:

- U4 queue/session-worker redesign, bounded mutation drain, intent ordering or
  lifecycle writer semantics;
- Core/UniFFI API changes or a Scrollover-specific Core API;
- a new persistent Swift data/domain layer;
- Timeline framework replacement;
- custom scroll physics;
- product changes to Scrollover, Remove When Read, Undo qualification, swipe
  actions, navigation, search semantics or article layout design;
- broad macOS refactors.

A small compatibility edit required for the U3.6 renderer/bridge is allowed only
when it preserves the existing product contract.

## 8. Acceptance gate for U3.6 as a whole

U3.6 is complete only when all four packages are implemented and the following
remain true:

- Timeline and Search use the shared native UIKit article renderer;
- repeated configuration of stable variants does not rebuild cell structure;
- matching row measurements reuse a bounded cached result;
- status/icon/image-pixel updates are geometrically neutral;
- a status/icon event does not cause O(N) Timeline item reconstruction;
- `scrollViewDidScroll` does not query a broad layout-attributes region or force
  layout;
- existing U3 Scrollover regression behavior remains intact;
- image work is bounded, visible-first, request-deduplicated and consumer-safe;
- no structural diffable snapshot is applied for status-only changes;
- rotation and Dynamic Type remain correct;
- no Auto Layout warnings are introduced;
- no U4 mutation semantics are silently changed.

Run the repository-native iOS checks for each package, including
`./apple/ios/Build/test.sh`, `./apple/ios/Build/build-app.sh`, and
`git diff --check` where available. Final acceptance also includes a Release build
on the same physical iPhone class used for the review, with Scrollover enabled,
fast and slow scrolling, immediate reversal, cold/warm image cache and rotation.
Use Instruments/Hitches/Time Profiler at final acceptance to verify the completed
implementation rather than to reopen the already selected UIKit architecture.

## 9. Relationship to U4 and U5

After U3.6 is accepted, continue with U4 as already contracted: one account/Core-
session-owned serial mutation worker with origin attribution, bounded drain,
explicit Read/Unread/Undo ordering, lifecycle handling and failure semantics.

U5 remains cleanup and final acceptance. Superseded renderer/test helpers and
outdated documentation should be removed or corrected only once their productive
replacement no longer depends on them.
