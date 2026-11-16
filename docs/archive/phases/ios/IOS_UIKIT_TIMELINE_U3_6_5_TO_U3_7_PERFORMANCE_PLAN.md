# UIKit Timeline Performance Plan — U3.6.5 through U3.7

> **Historical implementation plan — current U3 performance work remains open.**
>
> This file records the ordered U3.6.5–U3.7 plan that guided the September 2026
> UIKit Timeline performance work. References to the then-current
> `UICollectionView` container are historical; the productive Timeline later
> migrated to the accepted `UITableView` implementation. Several packages below have since been
> implemented, extended, or superseded by later hardening and physical-device
> experiments. Treat package descriptions and "next action" text as historical
> sequencing unless the current Phase-D contract or
> `IOS_UIKIT_TIMELINE_IMPLEMENTATION.md` explicitly carries the requirement
> forward.
>
> The UIKit Timeline amendment itself is still **IN PROGRESS**. Current physical-
> device performance investigation may still justify fundamental changes to
> renderer/layout/cell/image-presentation/preparation/scheduling structures.
> Therefore this document must not be used to infer that U3 is complete merely
> because individual packages here are complete.
>
> Baseline when this plan was written: `main` after U3.6.1–U3.6.4, including
> the merged UIKit renderer, targeted presentation bridge, resolved Scrollover
> geometry, and bounded image scheduler. U4 mutation-worker work remains a
> separate completion gate.

## 1. Objective

The goal is no longer merely to remove individually proven regressions. The production Timeline should be optimized so that scrolling through previously unseen articles does not depend on expensive full-cell measurement or unnecessary asynchronous presentation work.

The target end state is:

- no image pixel or icon arrival can alter cell geometry;
- no status-only update performs structural list work;
- article image work remains bounded and consumer-safe;
- Timeline sizing no longer depends on `systemLayoutSizeFitting` in the production scroll path;
- article geometry is derived deterministically from presentation metrics plus bounded text measurement;
- sizing and rendering consume the same layout metrics;
- layout metrics can be prepared ahead of scrolling;
- physical-device acceptance covers both cold and warm scrolling, not only repeated/cache-warm passes.

U4 remains separate and must not be folded into these packages.

## 2. Package order

| Package | Purpose | Main gate |
|---|---|---|
| **U3.6.5 — Cell Geometry Acceptance Repair** | Remove image intrinsic-size pressure from card geometry and add productive-cell geometry tests. | Placeholder, square/tall/wide decoded images, and cached image arrival all preserve the same row and image-slot geometry; no Auto Layout conflict is introduced. |
| **U3.6.6 — Presentation Delivery Repair** | Repair feed-icon/status delivery ownership and prepared-cell reconciliation. | Timeline and Search can both receive the correct icon/status stream; a prepared cell entering display resolves current icon state without structural work; transient icon failures remain retryable. |
| **U3.6.7 — Image Scheduler Race Repair** | Close cancellation-generation and admission/promotion races in `ArticleImagePipeline`. | A new consumer cannot attach to a cancelling generation; old completion cannot fail the successor; queue/concurrency bounds remain true under promotion and cancellation. |
| **U3.7.1 — Timeline Performance Instrumentation** | Add low-overhead counters/signposts around the real production hot paths. | Device runs can report measurement count/time, cache hits/misses, cell configuration, layout invalidation, image completion, and structural snapshot activity without changing product behavior. |
| **U3.7.2 — Deterministic Article Layout Engine** | Replace full-cell sizing with deterministic geometry plus bounded text measurement. | The engine returns the same geometry as the production cell across variants, widths, Dynamic Type, locale/direction, preview-line choices, and image/no-image states. |
| **U3.7.3 — Prepared Layout Metrics** | Prepare metrics before cells need them, prioritizing visible/nearby articles and optionally the remaining current selection. | New cells normally receive ready metrics; preparation remains bounded/prioritized and does not block list adoption or scrolling. |
| **U3.7.4 — Remove Production Self-Sizing** | Stop using `preferredLayoutAttributesFitting` / `systemLayoutSizeFitting` for normal Timeline item heights. | Collection layout receives explicit deterministic heights; cold scrolling does not trigger full-cell solver measurement. |
| **U3.7.5 — Optional Manual Cell Layout** | Remove Auto Layout/StackView work from the Timeline cell only if instrumentation still shows meaningful layout cost. | Cell subview frames consume the same layout metrics directly; no product/layout regression; this step is optional and evidence-gated. |
| **U3.7.6 — Physical Device Acceptance** | Validate Release scrolling on the reference iPhone under cold and warm conditions. | Previously unseen articles scroll fluidly with Scrollover enabled; warm scrolling is not materially different because of avoidable first-display work; counters show no unexpected solver/snapshot/layout bursts. |

## 3. U3.6.5 — Cell Geometry Acceptance Repair

### Problem

`IOSUIKitArticleCell` assigns required vertical hugging and compression resistance to `articleImageView` while the layout also gives the image view an explicit 16:9 slot. A decoded `UIImage` contributes an intrinsic content size. Required intrinsic-size pressure can therefore compete with the explicit image-slot constraints and cause additional layout work or unsatisfiable constraints.

The image pixels are presentation only. The slot geometry is already determined by `ArticlePresentationLayout` and the cell variant.

### Required implementation

- make the explicit image slot the sole geometry authority;
- remove or lower intrinsic-size CHCR priorities that can compete with the fixed slot;
- do not add image pixel dimensions to the sizing key;
- preserve `scaleAspectFill`, clipping and the existing 16:9 slot rules;
- placeholder -> decoded image, cache hit, and image replacement must be pixel-only updates;
- keep the permanent hierarchy introduced by U3.6.1.

### Required productive-cell tests

1. Configure and measure a visual portrait cell with placeholder/no decoded pixels.
2. Apply a square image, tall image and wide image to the same slot; row height and slot frame remain unchanged.
3. Image available before first measurement vs image arriving after first measurement yields identical geometry.
4. Visual landscape obeys the same invariant.
5. Read/Starred/feed-icon changes still do not change geometry.
6. No test should satisfy the gate only through a recreated pure helper; exercise the real cell/layout path where practical.

During device validation, use an `UIViewAlertForUnsatisfiableConstraints` symbolic breakpoint or equivalent diagnostic to verify image arrival does not create constraint conflicts.

### U3.6.5 implementation

`IOSUIKitArticleCell` no longer raises the article image view's intrinsic-content
hugging or compression-resistance priorities to required. The prepared required
portrait and landscape slot constraints remain the sole geometry authority.
Decoded pixels continue to use aspect fill, clipping, and the existing corner
radius without changing the sizing identity.

`NewsreaderPresentationTests` exercises actual configured and fitted UIKit cells.
It verifies portrait placeholder, square/tall/wide pixels, before/after-measurement
arrival, landscape pixels, Read/Starred, and feed-icon fallback/decoded-icon
transitions preserve measured height, slot frame, layout variant, and prepared
layout-variant revision. The tests call `layoutIfNeeded()` after each relevant
pixel update. Physical-device acceptance should still use an
`UIViewAlertForUnsatisfiableConstraints` symbolic breakpoint while image-rich
rows load.

## 4. U3.6.6 — Presentation Delivery Repair

### Problems

The current presentation bridge owns one weak controller receiver. Timeline and Search can both use the shared feed-icon bridge, so a later attachment can replace the earlier receiver. In addition, icon deltas are currently applied to visible cells; a prepared-but-not-yet-visible cell can miss an icon completion and later display a fallback even though the icon is already retained.

Feed icon loading also conflates successful "no icon" with transient failure, which can make a temporary failure permanent for the store lifetime.

### Required implementation

- replace single-receiver ownership with explicit subscriptions or separated article-status and feed-icon channels;
- Timeline receives its article-status and icon streams;
- Search keeps its own article-status stream while subscribing to the shared icon stream;
- unsubscribe/cleanup must be lifecycle-safe and must not retain controllers indefinitely;
- `willDisplay` (or equivalent binding point) reconciles the latest retained icon state by stable feed ID + variant without structural snapshot, full-list remap, or height measurement;
- icon state distinguishes at least idle/loading/available/successful-unavailable/retryable-failure;
- transient failures retry lazily after a cooldown or later demand; successful "no icon" must not enter a retry loop;
- concurrent requests for the same feed/variant remain deduplicated.

### Tests

- Timeline + Search attached simultaneously both receive current icon presentation.
- Search attachment cannot steal Timeline updates.
- Icon completes after cell preparation but before display -> correct icon appears on display.
- Cached icon before configure -> immediate correct presentation.
- Stale completion after reuse/variant change cannot paint the wrong icon.
- Multiple visible rows for one feed update correctly.
- Transient failure followed by later success is retryable.
- Successful no-icon result is retained without repeated requests.

### U3.6.6 implementation

`IOSUIKitArticleTimelinePresentationBridge` now has separate weak subscriber
collections for article-status and feed-icon delivery. A controller subscribes
to its own article bridge and may independently subscribe to the shared
Newsreader icon bridge. Repeated updates replace the entry by controller
identity; bridge replacement and SwiftUI dismantling explicitly unsubscribe,
while weak entries cannot retain obsolete controllers.

`willDisplay` reconciles the bound cell from retained article and feed-icon
state keyed by article ID, feed ID, and icon variant. This calls only the
cell's targeted status/icon presentation methods and does not reconfigure the
cell, measure it, or apply structural list work.

Feed-icon state is explicit: idle, loading, available, successful-unavailable,
or retryable failure. The existing Core contract's successful `nil` icon is
retained as successful-unavailable. Thrown Core failures and raw icon data that
cannot decode as a `UIImage` are retryable failures, with a 30-second
demand-based cooldown; concurrent demand remains deduplicated.

`NewsreaderPresentationTests` covers simultaneous Timeline/Search icon
subscription, article-channel isolation, repeated updates, prepared and cached
cell reconciliation, stale feed bindings, targeted multi-row delivery, retry
after transient/decode failure, and successful no-icon retention.

## 5. U3.6.7 — Image Scheduler Race Repair

### Problems

A job with its last consumer cancelled can remain in the job table until the underlying loader actually finishes. A new consumer for the same request can attach to that cancelling job and then receive its cancellation/failure. Queue promotion/admission also needs stronger invariant coverage when visible and prefetch limits interact.

### Required implementation

- give each underlying request job an explicit generation/state;
- a cancelling job cannot accept new consumers;
- a new consumer for the same request either starts/queues a successor generation or waits for the old generation to retire and then joins a successor;
- completion closes only the generation that produced it;
- a cancelled active operation continues to occupy the active-concurrency budget until it actually finishes;
- preserve maximum active operation count;
- simplify/clarify pending admission so visible demand can evict queued speculative work without violating visible/total bounds;
- promotion from prefetch to visible must preserve all queue bounds;
- visible priority must remain stronger than speculative prefetch without spawning unbounded work.

### Tests

- force cancellation-aware loader behavior: cancel final consumer, attach a new consumer before old operation completes, then verify successor succeeds and old cancellation cannot fail it;
- promotion at full queue respects all bounds;
- visible admission at full speculative capacity succeeds by evicting speculative work where policy permits;
- active count never exceeds configured concurrency under cancel/promote/successor races;
- shared consumer cancellation remains correct.

### U3.6.7 implementation

`ArticleImagePipeline` now assigns every job generation a UUID and explicit
queued, active, or retiring lifecycle. Retiring active jobs remain counted until
their token-matched completion arrives, but are excluded from coalescing; a later
request creates a successor generation. Completion removes and resolves only its
own token, so an old cancellation/failure cannot close that successor.

Pending work uses one 48-request total bound with a 32-request speculative
subset. Visible work is selected first and can evict queued speculative work when
the total pending bound is full. Promotion moves a single tokenized queue entry
between queues, so it cannot duplicate membership or increase pending metadata.
The scheduler never preempts active speculative work and therefore preserves the
three-operation active bound while visible demand waits for a real slot.

`NewsreaderPresentationTests` covers cancellation followed by a same-request
successor, including the old operation completing before the successor begins;
the existing shared-consumer, bounded-concurrency, visible-priority, and queued
prefetch tests continue to cover the surrounding scheduler contract.

## 6. U3.7.1 — Timeline Performance Instrumentation

### U3.7.1 implementation

The Timeline controller owns a resettable `IOSUIKitTimelinePerformanceMetrics`
accumulator and exposes immutable snapshots for local diagnostics. It counts cell
configuration/reuse, variant and image binding changes, fitting calls, cache hits
and misses, actual solver calls and durations, structural reconciliation,
diffable snapshot application, and layout invalidation. Solver duration uses
`DispatchTime.uptimeNanoseconds` only around `systemLayoutSizeFitting`; a fixed
64-bucket logarithmic histogram provides bounded p50/p95 approximations.

`ArticleImagePipeline.Metrics` now includes memory-cache, start/completion/
retirement, maximum-active, and visible/prefetch-start counters. Its actor-owned
counters are resettable and are available in Release-like builds without logging,
telemetry, file I/O, or per-frame work.

`NewsreaderPresentationTests` verifies first sizing is a miss/solve, repeated
sizing is a hit without a solve, width changes solve again, and snapshots reset.

### Physical-device protocol

#### Release-compatible diagnostic build

`FLUX_PERFORMANCE_DIAGNOSTICS` is an explicit Swift compilation condition for
physical Timeline profiling. It retains Release optimization while compiling the
local Timeline Performance controls, snapshots, the Scrollover diagnostic log,
and a few low-frequency Timeline signposts. It does not define `DEBUG`.

Build a signed device app with:

```sh
./apple/ios/Build/build-app.sh \
  --configuration Release \
  --performance-diagnostics \
  --destination 'generic/platform=iOS'
```

The flag is accepted only with `Release` and passes
`SWIFT_ACTIVE_COMPILATION_CONDITIONS=FLUX_PERFORMANCE_DIAGNOSTICS` to Xcode.
An ordinary `Release` build omits the condition, so the Timeline Performance
controls, diagnostics owner, Scrollover diagnostic logging, and signposts are
not compiled into the production app.

> **Note (18 September 2026):** the Frame Headroom section of Developer
> Diagnostics was removed with the rest of the temporary instrumentation. The
> procedure below is no longer executable; see
> `IOS_TIMELINE_PERFORMANCE_DIAGNOSTIC_CLEANUP.md`.

In a diagnostic build, open **Settings → Developer Diagnostics**. **Reset
Timeline Metrics** clears the Timeline, prepared-layout, and image-pipeline
counters; **Print Timeline Metrics** emits one local snapshot. Instruments can
use the `timeline-performance` signpost category to align the first drag
(`Timeline interaction began`) with the rare geometry and snapshot events. No
per-scroll callback text logging is added.

For an idle-to-first-scroll profiling run on a physical device:

1. Install and run the Release diagnostic build, then allow initial sync and rendering to settle.
2. Perform one warm scroll, leave the Timeline idle for 10–20 seconds, and reset metrics.
3. Begin one slow scroll, stop, and print the snapshot; capture signposts in the same interval.
4. Repeat about ten times and note whether a hitch aligns with prepared-layout fallback, image miss/decode, snapshot or reconciliation work, geometry invalidation, Scrollover work, or store/Core activity.

This procedure collects evidence only; it does not establish a performance conclusion.

For each run, reset Timeline and image-pipeline metrics immediately before
scrolling, record approximate traversed rows and elapsed run time, then capture
both snapshots. Run a Release build on the reference iPhone for: a cold,
previously unvisited image-rich region with Scrollover enabled; a warm repeat of
the same region/settings; and, when practical, a text-heavy control. This package
defines no acceptance threshold: the snapshots establish the U3.7 baseline.

Before replacing sizing, add instrumentation around the real production path so the architectural change can be verified rather than judged only from video.

Track at minimum:

- `preferredLayoutAttributesFitting` calls;
- `systemLayoutSizeFitting` solve count;
- solve duration total, p50/p95/max or equivalent sampled statistics;
- height/metrics cache hits and misses;
- cell configure/rebind counts;
- layout variant switches;
- structural snapshot applications;
- layout invalidations;
- article-image cache hit/miss/completion counts;
- feed-icon presentation completions;
- optional signposts around cold cell preparation and collection-view update blocks.

Instrumentation must be low-overhead and removable/disableable for normal builds. Do not add per-frame logging to stdout.

## 7. U3.7.2 — Deterministic Article Layout Engine

### Principle

The production row height is deterministically derivable. The layout should no longer ask a fully configured cell to discover its own height.

The engine computes geometry from:

- container width and outer insets;
- presentation mode/variant;
- fixed stack/inter-column spacings;
- fixed 16:9 image slot when present;
- Dynamic Type font metrics;
- exact bounded text measurement for title and preview;
- deterministic metadata-row geometry;
- locale/writing direction and any other layout-relevant typography input.

Do **not** approximate line count from character count. Use Apple's text layout/bounding APIs with the same fonts, width, paragraph/line-break behavior, and maximum line count as the renderer.

### Current deterministic geometry

The existing production cell already defines:

- compact iPhone horizontal inset: 10 pt;
- visual iPhone horizontal inset: 16 pt;
- >700 pt container horizontal inset: 28 pt;
- compact outer vertical padding: 11 pt;
- visual portrait outer vertical padding: 15 pt;
- visual landscape outer vertical padding: 13 pt;
- text stack spacing: 7 pt;
- portrait image-to-text spacing: 12 pt;
- landscape image-to-text spacing: 14 pt;
- portrait/landscape image aspect ratio: 16:9;
- landscape image allocation: 48% of article content width;
- unread dot: 6x6 pt;
- feed-icon slot: 22x22 pt;
- metadata column fallback below 370 pt available width;
- preview line choices: 2, 3 or 5.

### Proposed API

A dedicated `ArticleLayoutInput` / `ArticleLayoutKey` should contain only geometry-relevant inputs. `isRead`, `isStarred`, decoded article pixels, decoded feed-icon pixels and transient loading state must not participate.

The output should be an `ArticleLayoutMetrics` value containing at least:

- layout variant;
- exact cell height;
- title height;
- metadata height;
- preview height;
- image frame when present;
- text/title/metadata/preview frames or enough deterministic metrics to derive them without another independent geometry implementation.

Sizing and eventual manual rendering must consume this same output so there is one geometry authority.

### Geometry formulas

Text-only/compact conceptual height:

`top padding + title height + text-stack spacing + metadata height + optional (text-stack spacing + preview height) + bottom padding`

Visual portrait conceptual height:

`top padding + 16:9 image height + 12 + text block height + bottom padding`

Visual landscape conceptual height:

`top padding + max(image height, text block height) + bottom padding`

The exact implementation must account for the production title-row star reservation and current metadata layout rules.

### Tests

Compare deterministic metrics against the real UIKit cell over a matrix of:

- compact / visual text-only / visual portrait / visual landscape;
- short and multiline titles;
- empty/1/2/3/5+/very long preview text;
- image/no image;
- comments/no comments;
- widths around the 370, 600 and 700 pt transitions;
- all supported preview-line choices;
- representative Dynamic Type sizes including accessibility sizes;
- LTR/RTL;
- portrait -> landscape -> portrait.

The goal is equality within a clearly defined pixel/point rounding tolerance, not visual approximation.

## 8. U3.7.3 — Prepared Layout Metrics

Once deterministic metrics exist, move their computation ahead of active scrolling.

Priority model:

1. visible / immediately requested items;
2. near-future items within a bounded look-ahead window;
3. optionally the remainder of the current adopted selection at low priority.

Requirements:

- never synchronously prepare all loaded history on the main thread;
- preparation must be cancellable/revision-aware when width, Dynamic Type, content or selection changes;
- duplicate layout keys coalesce;
- metrics cache is bounded or revision-scoped with an explicit memory policy;
- a list of roughly 1,000 current articles may be fully warmed opportunistically if the measured cost and memory use are acceptable, but visible/nearby work always wins;
- adoption/sync may enqueue preparation but may not turn into a long blocking "recalculate every row" operation.

## 9. U3.7.4 — Remove Production Self-Sizing

After deterministic metrics are validated, the collection layout obtains explicit item heights from `ArticleLayoutMetrics`.

Required end state:

- normal Timeline scrolling does not invoke `systemLayoutSizeFitting` to discover row height;
- `preferredLayoutAttributesFitting` is removed from the normal production sizing path or becomes a non-solving compatibility fallback that is not used in accepted configurations;
- cell rendering receives the same layout metrics used for sizing;
- image/icon/status arrival cannot invalidate item height;
- width/Dynamic-Type/layout-revision changes calculate a new metrics revision and preserve the existing visible-anchor guarantees.

A temporary comparison/debug assertion against Auto Layout may remain in non-production validation code while the deterministic engine is proven.

## 10. U3.7.5 — Optional Manual Cell Layout

Do this only if post-U3.7.4 instrumentation still attributes meaningful main-thread cost to Auto Layout/StackView layout inside already-sized cells.

If needed:

- keep the permanent native subviews;
- use `ArticleLayoutMetrics` in `layoutSubviews()` to assign frames directly;
- remove Timeline-cell StackView/constraint solver dependency where practical;
- keep accessibility, Dynamic Type, RTL and all existing product presentation semantics;
- do not apply this optimization to unrelated screens without separate evidence.

This package is optional because explicit deterministic item heights may already remove the dominant first-display cost.

## 11. U3.7.6 — Device acceptance

Use the same physical iPhone class used in the performance review and a Release configuration.

Required scenarios:

### Cold path

- launch/reload a selection containing previously unvisited articles;
- scroll continuously through rows whose text/image/layout metrics have not already been consumed by a prior pass;
- Scrollover enabled;
- include an image-rich feed/selection.

### Warm path

- immediately repeat the same region without structural changes.

### Control path

- repeat with a mostly text-only selection where possible.

Capture instrumentation for each path. The final decision must distinguish actual first-display work from recording artifacts or unrelated app/system activity.

Acceptance is not "warm scrolling looks fine". The intended product property is that **previously unseen unread articles scroll fluidly**.

## 12. Explicit non-goals until this plan is complete

- U4 mutation worker/session queue redesign;
- Rust/Core API changes for Timeline layout;
- custom scroll physics;
- replacement of `UICollectionView`;
- reintroduction of SwiftUI article cells;
- product changes to Scrollover, Undo, Remove When Read, Search, article card presentation or navigation semantics.

## 13. Historical next action at the time of this plan

The original next action was to start **U3.6.5 — Cell Geometry Acceptance
Repair** on branch `u3-6-5-timeline-acceptance-repair`. That instruction has
been completed and is retained only to preserve the historical implementation
sequence.

For current work, use the authoritative Phase-D contract and
`IOS_UIKIT_TIMELINE_IMPLEMENTATION.md`. Do not restart U3.6.5 or assume the
remaining task is acceptance-only. Continue from the current production code and
current physical-device evidence; U3 remains open to deeper structural
performance changes where justified.
