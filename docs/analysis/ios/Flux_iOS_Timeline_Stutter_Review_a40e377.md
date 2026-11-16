# Flux iOS Timeline — Residual Scroll-Stutter Review

Reviewed commit: `a40e3777a1b06716647ba954a70ff11341f511fa` (`main`, 13 September 2026).
Scope: native iOS/iPadOS Timeline only. Analysis, no code changes.
Method: source reading plus effective build-setting interrogation (`xcodebuild -showBuildSettings`) and the Xcode `Swift.xcspec` defaults. No device trace, no Instruments, no simulator run.

---

## 0. Summary

The architecture is sound and the previously repaired areas hold up under re-reading. I found no regression in the Apple Core execution boundary, keyset pagination, incremental publication, targeted removal, paging ownership tokens, or Timeline identity.

What remains is **not** one large defect. It is a small number of places where a cheap-looking event fans out into whole-visible-set or whole-list work on the main thread, plus two pipelines (prepared layout metrics, article images) that are *destroyed and restarted* by that fan-out — so the next few cells to appear are guaranteed to do their expensive work synchronously, in a burst, at the worst possible moment.

That shape matches the recorded symptom better than any single hot function: irregular timing, no one-to-one correlation with a Scrollover crossing, present at high scroll velocity, and sensitive to how warm the caches are.

**Important framing on magnitude.** 2–4 frames of a 30 fps recording is 66–133 ms. A single expensive cell configuration cannot produce that. Either several tens of milliseconds of main-thread work land in one run-loop turn, or the main thread is blocked. The findings below are ranked with that budget in mind, and I flag explicitly where a finding is real but too small to be the primary cause.

**One structural obstacle first:** the Release-compatible diagnostics you built are compiled out of the build you are recording. See Finding 5 — it is the cheapest thing on this list and it converts most of the rest from "candidate" to "measured".

---

## 1. Cell layout and sizing hot path

### Is production scrolling already effectively independent of Auto Layout self-sizing?

**Yes for sizing. No for per-cell layout.**

`IOSUIKitArticleCell.preferredLayoutAttributesFitting` (`ArticleListView.swift:1831`) never calls `systemLayoutSizeFitting`. It copies the incoming attributes and overwrites `size.height` from `preparedLayoutMetrics.cellSize.height`. The constraint solver is not consulted to discover row height. The `preparedLayoutMetrics == nil` escape (`:1834`) can only be reached between `prepareForReuse` and `configure`, which is not a real production window because `configure` always assigns a non-optional value (`:1856`, `:1862`).

So U3.7.4 genuinely landed. The `systemLayoutSizeFittingCalls` counter should read 0 in production.

What still runs Auto Layout is the *inside* of an already-sized cell: `layoutSubviews` resolving ~30 constraints across `textStack`, `metadataRow` and the image slot, plus UILabel's own text layout for four labels. That is the only remaining Auto Layout cost, and U3.7.5 is about removing it.

### Finding 1.1 — Layout-variant thrash on reuse (constraint deactivate/activate per dequeue)

**Where:** `IOSUIKitArticleCell.applyLayout`, `ArticleListView.swift:1887–1920`; variant resolution in `IOSUIKitArticleGeometry.variant(hasImage:)`, `IOSUIKitArticleLayoutEngine.swift:373–377`.

**What happens:** in `.visual` mode on a phone, an article *with* an image resolves to `.visualPortrait` and an article *without* one resolves to `.visualTextOnly`. These are different constraint sets. Both are served by a **single reuse identifier** (`ArticleListView.swift:815`). So whenever a recycled cell's new article differs from its previous article in "has image", `applyLayout` runs `NSLayoutConstraint.deactivate(activeLayoutConstraints)` followed by `NSLayoutConstraint.activate(...)` — 4 constraints out and 8 in, or the reverse.

Constraint activation/deactivation is among the more expensive Auto Layout operations: it mutates the solver's tableau rather than just changing a constant. In a mixed "All news" selection where a meaningful fraction of articles have no image, this fires on a large share of dequeues, and dequeues cluster during fast scrolling.

**Why it could create the observed stall:** it is per-dequeue, and dequeues arrive in bursts. It does not by itself reach 60 ms, but it is the single largest remaining Auto Layout item in the scroll path and it stacks with Findings 2.x and 3.1 in the same run-loop turn.

**Confidence:** strong candidate for measurable cost; weak candidate as the sole cause of a 100 ms hitch.

**You can confirm this without Instruments.** The counter already exists: `layoutVariantSwitchCount` vs `configureCount` in `IOSUIKitTimelinePerformanceSnapshot`. A ratio approaching 0.5 proves the thrash; a ratio near 0 disproves it.

**Repair scope:** small. Register two reuse identifiers (text-only and portrait) — or three if you want landscape separated for iPad — so a recycled cell always receives an article of the same variant and `applyLayout` takes the early-return path at `:1901`. Roughly 20 lines in `viewDidLoad` and the data-source closure, plus a variant lookup that `renderedItem` can already answer. No product change.

**Independently worthwhile:** yes. It is strictly less work with no behavioural surface.

### Finding 1.2 — `configure()` forces a full re-layout of visible cells that did not change

**Where:** `IOSUIKitArticleTimelineController.update`, `ArticleListView.swift:958–965`; `IOSUIKitArticleCell.configure`, `:1850–1885` (note `contentView.setNeedsLayout()` at `:1884`).

**What happens:** on *every* structural change, including `.append` and `.remove`, the controller re-configures **every visible cell**:

```swift
if structuralChanged || iconVariantChanged {
    for case let cell as IOSUIKitArticleCell in collectionView.visibleCells {
        guard let id = cell.representedArticleID, let item = renderedItem(for: id) else { continue }
        configure(cell, item: item)
    }
    needsLayoutInvalidation = structuralChanged
}
```

For `.append`, the appended items are by definition *not* visible — they are at the tail. For `.remove`, the surviving visible cells' `itemsByID` entries are untouched. In both cases every visible cell is re-configured for nothing: four label `.text` assignments, `applyLayout`, `updateFeedIcon`, `updateStatus`, a prepared-metrics lookup that hashes four full strings, an `onRequestFeedIcon` callback into the store, and an explicit `contentView.setNeedsLayout()` that guarantees a complete Auto Layout pass for that cell on the next run-loop turn.

Only the `.replace` branch actually needs this loop.

**Confidence:** **confirmed avoidable work.** This is the clearest answer to question A.

**Repair scope:** trivial — scope the loop to `case .replace` and to `iconVariantChanged`. Three lines.

### Is the evidence threshold for U3.7.5 reached?

**No.** See §9 (question D) for the full argument. The short version: the dominant remaining costs in the scroll path are *not* the constraint solver inside a correctly sized cell, and manual layout would leave every one of Findings 2.1–4.2 untouched while adding a second geometry implementation to keep in sync with the engine. Finding 1.1 is the one genuine Auto Layout cost, and it has a cheaper fix than a rewrite.

---

## 2. Prepared layout metrics — the fallback path

### Finding 2.1 — The synchronous Core Text fallback result is never cached

**Where:** `IOSUIKitArticleTimelineController.configure`, `ArticleListView.swift:992–1015`.

```swift
if let prepared = preparedLayoutCoordinator.metrics(for: layoutInput, priority: .visible) {
    layoutMetrics = prepared
} else {
    let startedAt = DispatchTime.now().uptimeNanoseconds
    layoutMetrics = IOSUIKitArticleLayoutEngine.metrics(for: layoutInput)   // main thread
    performanceMetrics.recordDeterministicHeightFallback(...)
}
```

Two problems compound:

1. **The synchronously computed metrics are discarded.** They are used for this one configuration and never inserted into `IOSUIKitPreparedArticleLayoutMetricsCache`. The same row, reconfigured moments later (Finding 1.2 does exactly this), pays the full Core Text cost again — unless the asynchronous measurement happened to land in between.
2. **A miss also enqueues an asynchronous measurement of the same input** (`IOSUIKitArticleLayoutEngine.swift:239`). So every fallback costs the work twice: once on the main thread now, once on a background thread shortly after, for an identical result.

`IOSUIKitArticleLayoutEngine.metrics` (`IOSUIKitArticleLayoutEngine.swift:427`) is not cheap on the main thread: four `UIFont.preferredFont(forTextStyle:compatibleWith:)` calls each constructing a `UITraitCollection`, one `UIFont(descriptor: withSymbolicTraits(.traitBold), size:)` font-descriptor match, and two `CTTypesetterCreateWithAttributedString` line-break loops over the title and the preview.

**Why it could create the observed stall:** on its own, roughly 0.3–1 ms per cell. The problem is that Finding 3.1 makes fallbacks *cluster*: every page append cancels all in-flight measurements, so the next several cells to appear are near-guaranteed misses. Four to six clustered fallbacks is 2–6 ms of main-thread Core Text in one frame, on top of everything else that append triggers.

**Confidence:** confirmed inefficiency (the discard); strong candidate as an amplifier rather than the root trigger.

**Repair scope:** small. Give the coordinator an `insert(_:for:)` entry point (or a `metricsOrCompute(for:)` that caches the synchronous result and skips the redundant enqueue). Under 20 lines.

**Independently worthwhile:** yes, unconditionally.

**Measure it:** `deterministicHeightSynchronousFallbacks`, `...FallbackTotalNanoseconds` and `...FallbackMaxNanoseconds` are already in the snapshot. If fallbacks are near zero in a real run, this finding drops in priority immediately.

### Finding 2.2 — UIKit font APIs are called from a `.utility` QoS background thread

**Where:** measurement closure `IOSUIKitArticleLayoutEngine.swift:223–227` (`Task.detached(priority: .utility)`); `IOSUIKitArticleLayoutEngine.font(_:category:bold:)` at `:479–484`.

The "pure deterministic engine" is not entirely pure — it calls `UITraitCollection(preferredContentSizeCategory:)`, `UIFont.preferredFont(forTextStyle:compatibleWith:)` and `UIFont(descriptor:size:)`. These touch process-global UIKit/CoreText font caches that the main thread also uses for every `UILabel` layout.

Two consequences, in order of confidence:

- **Priority inversion risk (candidate, not proven).** A `.utility` thread holding a CoreText/UIKit font-cache lock while descheduled can stall the main thread, which during scrolling runs at user-interactive priority. iOS implements priority donation for several lock primitives, which mitigates but does not eliminate this. This class of problem is invisible in the Simulator (abundant cores, different scheduling) and produces exactly the profile you describe: intermittent, multi-frame, uncorrelated with any app-level event.
- **Thread-safety posture.** `UITraitCollection` construction off the main thread is not a documented-safe operation. It has evidently not misbehaved, but it is not a guarantee you want under the load the Timeline puts on it.

**Confidence:** strong candidate for the *intermittent, non-deterministic* character of the stalls specifically. Cannot be proven from source.

**Repair scope:** small and low-risk. Two independent halves:
1. Resolve the four fonts once on the MainActor per geometry identity and pass an immutable `ResolvedFonts` value into the engine. The engine then touches only Core Text, not UIKit. This also removes four `UITraitCollection` allocations per measurement.
2. Raise the measurement QoS from `.utility` to `.userInitiated`. Layout metrics for cells about to appear are not background work.

**Independently worthwhile:** yes — (1) removes real allocations and a thread-safety grey area; (2) is a one-word change.

---

## 3. Diffable Data Source and structural updates

### Finding 3.1 — The structural-update fan-out is the single largest event on the scroll path

**Where:** `IOSUIKitArticleTimelineController.update`, `ArticleListView.swift:904–972`. Triggered by `NewsreaderStore.appendTimelinePage` (`NewsreaderStore.swift:1170–1192`) via `willDisplay → onApproachingEnd → loadNextTimelinePage` (`ArticleListView.swift:1094–1095`), page size **72** (`NewsreaderStore.swift:290`).

A single page append performs, on the main thread, in one run-loop turn:

| Step | Code | Cost |
|---|---|---|
| Copy the entire current snapshot | `:917` `var snapshot = dataSource.snapshot()` | grows with total loaded IDs |
| Append 72 identifiers and re-apply | `:918–919` | framework diff over the full identifier list |
| Re-configure **every visible cell** | `:960–963` | Finding 1.2 — pure waste for `.append` |
| **Cancel every in-flight image prefetch** | `:968` `cancelAllPrefetch()` | Finding 4.1 — destructive |
| **Cancel every in-flight layout measurement** | `:969 → replaceWindow`, `IOSUIKitArticleLayoutEngine.swift:243–253` | forces Finding 2.1 to fire repeatedly |
| **Full layout invalidation** | `:971` `collectionView.collectionViewLayout.invalidateLayout()` | whole-layout invalidation of a compositional list with estimated self-sizing |

The layout is `UICollectionViewCompositionalLayout.list(using:)` (`:793–798`), which uses estimated item dimensions and resolves real heights through `preferredLayoutAttributesFitting` as cells are displayed. A blunt `invalidateLayout()` is the heaviest form of invalidation available for that layout, and it is issued *in addition to* the snapshot apply that already invalidates what it needs.

**Why it could create the observed stall:** this is the only place in the Timeline where a scroll-time event triggers whole-list work, whole-visible-set work, and the teardown of both asynchronous pipelines simultaneously. Its aftermath is also self-reinforcing: the cells that appear in the next ~200 ms have no prepared metrics (cancelled) and no prefetched image (cancelled), so they take the synchronous Core Text path and the cold image path together. "The list barely moves for a few frames, then jumps forward" is precisely what a main-thread block of this shape looks like once rendering resumes and the deceleration curve has advanced.

**Confidence:** **strong candidate, containing confirmed avoidable work.** I am not claiming Diffable's internals are O(n) — that is framework-internal and unproven here. What *is* established from this code is that Flux itself performs a full-snapshot round-trip and issues a redundant full layout invalidation, and that it cancels two pipelines that UIKit will not re-prime on its own.

**Honest caveat on frequency.** An append fires once per 72 rows. Your recorded stalls at 31.7 s and 33.0 s are ~1.3 s apart, which would require sustaining roughly 50 rows/second — a very hard flick in `.visual` mode. So appends probably do not account for *all* five occurrences. This finding is ranked first because it is the largest single event and the one with confirmed waste, not because the timing is a perfect match. The existing `structuralReconciliationCount` / `snapshotApplyCount` / `layoutInvalidationCount` counters settle this in one device run.

**Repair scope:** small and surgical, four independent edits inside `update`:
1. Restrict the visible-cell reconfigure loop to `.replace` and `iconVariantChanged`.
2. Drop `cancelAllPrefetch()` for `.append`/`.remove` (see Finding 4.1).
3. Drop the unconditional `invalidateLayout()` for `.append`/`.remove`; let `apply` do it.
4. Retain the working `NSDiffableDataSourceSnapshot` in the controller and mutate it, instead of round-tripping through `dataSource.snapshot()` on every structural change.

Items 1–3 are a handful of lines. Item 4 is ~15 lines plus keeping the retained snapshot in sync in the three branches.

**Independently worthwhile:** yes, emphatically. Even if profiling exonerates it, none of this work should be happening.

### Finding 3.2 — The incremental path silently degrades to a full O(N) rebuild

**Where:** `ArticleListView.swift:907`, `:936–950`.

```swift
let canApplyIncrementally = structuralRevision == structuralState.revision &- 1
```

The incremental append/remove branches are taken **only when exactly one structural revision elapsed** between two SwiftUI update passes. SwiftUI coalesces `@Observable` changes within a run-loop turn. If two structural mutations land in the same turn — an append plus a `removeVisibleArticles`, a sync-driven `replaceFirstTimelinePage` racing a page append — the controller receives one update with a revision gap of 2 and falls through to `else`:

```swift
orderedIDs = newIDs
itemsByID = Dictionary(uniqueKeysWithValues: items.map { ... })          // N
presentationByID = Dictionary(uniqueKeysWithValues: items.map { ... })   // N, with a bridge lookup each
scrolloverGeometryTracker.updateSnapshot(newIDs)                         // N
var snapshot = NSDiffableDataSourceSnapshot<Section, Int64>()
snapshot.appendItems(newIDs)                                             // N
dataSource.apply(snapshot, animatingDifferences: false)                  // full replace
```

With 200–400 loaded rows this is a genuine multi-frame event, and it is **indistinguishable in the counters** from a cheap incremental apply — `structuralSnapshotApplicationCount` increments identically in all three branches.

**Why it could create the observed stall:** it is non-deterministic by construction (it depends on SwiftUI coalescing), which matches "intermittent" better than the append path does. It also invalidates the Scrollover tracker's entire emitted/observed state, so a crossing can be lost at the same moment.

**Confidence:** strong candidate, currently unmeasurable.

**Repair scope:** small. Two parts: (a) add a counter for the full-replace branch so it stops hiding, and (b) make the change channel accumulate — let the store carry a list of changes since the last consumed revision, or have the controller apply a run of pending changes, rather than requiring an exact `revision − 1` match.

**Independently worthwhile:** yes. (a) alone is a few lines and materially improves your ability to diagnose everything else.

### Finding 3.3 — `applyArticlePresentation` and `applyFeedIconPresentation` are fine

`applyArticlePresentation` (`:1023`) resolves one `indexPath`, fetches one cell, and calls `updateStatus`. `updateStatus` (`:1922`) changes only `textColor` and two `alpha` values — genuinely geometry-neutral, since the star occupies a permanently reserved slot (`:1749–1752`). No structural work, no reconfigure. This path is correct.

`applyFeedIconPresentation` (`:1036`) allocates an array from `visibleCells` and scans it per delta. With a burst of icon deltas that is N_icons × N_visible, but both are small. Not a stall source.

---

## 4. Image pipeline

### Are images truly decoded before assignment?

**Yes, for article images.** `ArticleImagePipeline.downsample` (`ArticleImagePipeline.swift:408–422`) uses `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceShouldCacheImmediately: true`, on a detached task (`:321–324`). The bitmap is materialized off the main thread. This is correct and should not be described as missing.

**No, for feed icons.** See Finding 4.3 — that is a separate path and it is not decoded off the main thread at all.

### Finding 4.1 — `cancelAllPrefetch()` throws away prefetch work that UIKit will not re-request

**Where:** `ArticleListView.swift:968` and `:1317–1320`.

`prefetchTasks` is Flux's own bookkeeping. `UICollectionViewDataSourcePrefetching` drives `prefetchItemsAt` / `cancelPrefetchingForItemsAt` from UIKit's side. When `update` cancels all of Flux's prefetch tasks, UIKit still believes those index paths are prefetched and will **not** call `prefetchItemsAt` for them again. Cancelling the Swift task propagates into `ArticleImagePipeline.cancel` (`:292–310`), which tears down the shared job if it has no other waiter — so the in-flight download is aborted too.

The result: after every page append, the rows about to scroll into view have no prefetched image. `configureArticleImage` (`:1986`) then starts a fresh `.visible` request, the URL is re-fetched (or re-read from `URLCache`), re-downsampled, and lands late — several at once, because three operations run concurrently and complete around the same time.

**Confidence:** **confirmed behavioural defect**, not merely a perf smell. It also wastes network.

**Repair scope:** trivial. Cancel prefetch only when the requests genuinely become invalid — which is exactly what `cancelIncompatibleImagePrefetch()` (`:1322–1330`) already does correctly for geometry changes. Structural appends and removals do not invalidate any surviving row's image request.

### Finding 4.2 — `.utility` QoS decode, un-normalized CGImage, and a cache budget of ~18 cards

**Where:** `ArticleImagePipeline.swift:142–144`, `:321–324`, `:352`; `ArticleListView.swift:2004–2022`.

Three separate issues on the same path:

**(a) Decode QoS.** `Task.detached(priority: .utility)` runs the download *and* the downsample. During an active scroll the main thread is user-interactive; a `.utility` decode is scheduled against it and will be preempted. Images therefore land later and more clustered than necessary. `.userInitiated` for `.visible` demand (keeping `.utility` for `.prefetch`) matches what the work actually is.

**(b) The CGImage is handed to Core Animation without normalization.** `CGImageSourceCreateThumbnailAtIndex` returns an image in the *source's* pixel format and colour space. `UIImage(cgImage:)` is then assigned directly to the image view (`:2005`, `:2021`). If the format does not match what the compositor wants, Core Animation performs the conversion **on the main thread during the CATransaction commit** — the classic "we decoded in the background but it still costs main-thread time" trap. A deliberate redraw into a device-RGB `CGContext` inside the background task removes the residual conversion and guarantees the backing store is commit-ready.

**(c) Cache budget versus per-image cost.** On an iPhone 15 the portrait slot is 361 × 203 pt; `ArticleImageRequest.init` (`:9–14`) buckets to `maxPixelDimension = 1088`. A typical 16:9 source yields 1088 × 612 × 4 bytes ≈ **2.66 MB per decoded image**. Against `memoryCacheCostLimit = 48 MB` that is roughly **18 images**. With a visible window of 2–3 cards plus prefetch, the cache evicts images that are still nearby; scrolling back up is a full re-download and re-decode. The existing `memoryCacheEvictions` / `visibleMemoryCacheHitRate` counters will show this immediately.

**Why these could create the observed stall:** (b) is the only one that puts work directly on the main thread, and it scales with image area. Three images committing in one frame is a plausible 10–20 ms. (a) and (c) govern how *bursty* completions are — several continuations resuming into MainActor tasks in the same run-loop turn (`:2012–2033`).

**Confidence:** (b) strong candidate; (a) and (c) strong candidates for burstiness and for the cold/warm difference you have noticed; none proven.

**Repair scope:** (a) one line. (b) ~15 lines in `downsample`. (c) a constant, ideally derived from `ProcessInfo.processInfo.physicalMemory` rather than fixed.

**Independently worthwhile:** yes for all three.

### Finding 4.3 — Feed icons are decoded on the MainActor, at full resolution, and never downsampled

**Where:** `NewsreaderStore.requestFeedIcon`, `NewsreaderStore.swift:501–520`.

```swift
Task { [weak self] in
    let result = await AppleCoreExecution.shared.blockingResult { try loader(feedID, variant) }
    ...
    guard let image = UIImage(data: data) else { ... }     // MainActor
    state.setAvailable(image)
    timelinePresentationBridge.publishFeedIcon(...)
}
```

This `Task` is created inside a `@MainActor` method, so it inherits MainActor isolation. After the `await`, everything runs on the main thread:

- `UIImage(data:)` parses the container but **defers pixel decoding to first draw** — which happens on the main thread inside the next CATransaction commit, when the icon is assigned to a visible cell.
- The image is **never downsampled**. It is displayed in a 22 × 22 pt slot (`ArticleListView.swift:1685–1687`) but retained at source resolution for the lifetime of the session. A 512 × 512 PNG decodes to 1 MB; a 1024 × 1024 apple-touch-icon to 4 MB. Feed icons are frequently large.
- `feedIconImageView` uses `.scaleAspectFit` inside a container with `cornerRadius = 11` and `clipsToBounds = true` and two subviews (`:1681–1706`), so the oversized image is rescaled by the GPU through an offscreen pass on every frame it is visible.

Unlike article images, this path has **no** downsampling, **no** decode-ahead, and **no** bounded memory.

**Why it could create the observed stall:** it fires on **first encounter with each feed**. Scrolling a diverse "All news" selection meets new feeds at irregular intervals, and several can complete in the same run-loop turn (the blocking lane runs 2 concurrent operations). A burst of large PNG decodes inside one commit is a very good fit for a 60–130 ms hitch that correlates with *position in the list* rather than with any Timeline event. It also explains the cold/warm asymmetry directly: once a feed's icon is decoded it stays in `feedIconPresentationStates` for the session, so a second pass over the same region is free.

**Confidence:** **strong candidate** — arguably the best single fit for the irregular timing and the warm-up effect, and the only place in the reviewed code where genuinely unbounded image work reaches the main thread.

**Repair scope:** small and well-contained. Decode and downsample the icon data to `22 × displayScale` inside the background work — the exact operation `ArticleImagePipeline.downsample` already implements — and hand a finished, correctly sized `UIImage` to the MainActor. About 15 lines, no product change. The 22 pt slot size is already a shared constant (`IOSUIKitArticleGeometry.feedIconSize`).

**Independently worthwhile:** yes, regardless of profiling. It also cuts per-session icon memory by one to three orders of magnitude.

### Other image questions, answered

- **Can the same image be decoded repeatedly?** Yes, via Finding 4.2(c) eviction and Finding 4.1 prefetch destruction. Not via a logic defect — `ArticleImageRequest` bucketing (`:12`) and the job/generation model are correct.
- **Can visible requests duplicate prefetched requests?** No. `attach` coalesces onto a non-retiring generation and promotes prefetch→visible (`:241–247`). This is sound.
- **Can many completions land on the MainActor in one burst?** Yes — `complete` (`:347`) resumes all waiters for a job, and up to 3 operations complete independently. Each waiter is a MainActor task. This is the intended design; the mitigation is making each landing cheaper (4.2b) rather than serializing them.
- **Does assigning an image change row geometry?** No. The image slot is fixed by constraints (`:1795–1800`, `:1809–1828`) and `preferredLayoutAttributesFitting` ignores pixels entirely. U3.6.5 holds.
- **Are feed icons and article images separate enough?** They are separate pipelines, but only one of them is hardened. That asymmetry is Finding 4.3.

---

## 5. Instrumentation and build configuration

### Finding 5.1 — `FLUX_PERFORMANCE_DIAGNOSTICS` is not defined in any Release configuration

**Where:** `apple/ios/FluxNews.xcodeproj/project.pbxproj` — `SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG` appears once, in the Debug configuration only (line 404). The Release configuration (lines 409–436) defines no compilation conditions. Verified with `xcodebuild -showBuildSettings -configuration Release`, which reports no `SWIFT_ACTIVE_COMPILATION_CONDITIONS` at all.

Everything behind `#if DEBUG || FLUX_PERFORMANCE_DIAGNOSTICS` is therefore **absent from the build you install on the phone**: the whole `IOSUIKitTimelinePerformanceDiagnostics` enum, the Developer Diagnostics section that exposes it (`DeveloperDiagnosticsView.swift:22–31`), the OSSignposter events, and the Scrollover diagnostic logger. `archive.sh` builds `-configuration Release` and the TestFlight export path uses that archive.

The commit `41ba3b9 "Enable Release-compatible iOS performance diagnostics"` added the conditional guards; the build setting that activates them was never added.

**Confidence:** **confirmed.** This is why the device evidence problem feels unsolvable: you already built the instrument, and it is being compiled out of the only build you can run.

**Repair scope:** one line — `SWIFT_ACTIVE_COMPILATION_CONDITIONS = FLUX_PERFORMANCE_DIAGNOSTICS;` in the Release configuration (or a dedicated `Release-Diagnostics` configuration if you would rather keep shipping builds clean).

**Second, related step:** `printSnapshot()` uses `print()` (`ArticleListView.swift:1435`), which writes to stdout. On a device you cannot attach Xcode to, that is unreliable to retrieve. Either route it through the `Logger` that is already imported under the same flag — os_log is readable in Console.app from a trusted Mac without any developer profile — or render the snapshot directly in `DeveloperDiagnosticsView` as selectable text. Rendering it on screen is the most robust option for a company device: reset, scroll, read the numbers, screenshot.

**This is the highest-value item on the list per unit of effort**, because it converts Findings 1.1, 2.1, 3.1, 3.2 and 4.2c from reasoned candidates into measured facts, using counters that already exist.

### Finding 5.2 — Release compiles at `-O` but in single-file mode

Verified against the Xcode Swift build spec: `SWIFT_OPTIMIZATION_LEVEL` defaults to `-O` (so optimization **is** on — I checked this specifically because an unset value would have been a far larger finding, and it is not), but `SWIFT_COMPILATION_MODE` defaults to `singlefile`. Neither is set in this project, so Release builds are optimized per-file without whole-module optimization.

The Timeline hot path spans file boundaries constantly: `IOSUIKitArticleGeometry` and `ArticlePresentationLayout` live in `BrowserPresentation.swift`, the engine in `IOSUIKitArticleLayoutEngine.swift`, the cell and controller in `ArticleListView.swift`. Cross-file inlining of the many tiny geometry accessors, and generic specialization of the dictionary and set operations on the scroll path, are unavailable in single-file mode.

**Confidence:** weak candidate for the specific symptom — this is a broad few-percent effect, not a 100 ms hitch. Listed because the fix is one line and carries no risk.

**Repair scope:** `SWIFT_COMPILATION_MODE = wholemodule;` in the Release configuration.

---

## 6. Scrollover and read/starred follow-up work

Re-read end to end. **The current path does not structurally remove articles.** `flushScrollover` (`NewsreaderStore.swift:739`) only enqueues; `drainScrolloverMutations` (`:774`) runs only at a batch of 64 or when the phase goes idle (`:760–768`); the success path publishes read presentation and Undo state, never `removeVisibleArticles`. During a forward scroll with Scrollover enabled, **no Core write, no presentation publication, and no structural change occur at all**. Presentation is deliberately deferred to a direction reversal or idle (`:755–758`, `:840–854`).

That is a good design and it exonerates Scrollover as a primary suspect. It also explains why the recording no longer shows a deterministic crossing→hitch relationship.

Answering the specific questions:

- **Can crossing one article trigger meaningful synchronous UI work?** No. `flushScrollover` does set insertion and array append only.
- **Can a batch completion produce a burst of removals?** Not from Scrollover. Structural removal only reaches the Timeline through explicit `setRead` with "remove when marked read" enabled (`:709–711`, `:1079–1085`).
- **Can navigation/count refresh coincide with the active scroll?** `reloadScrolloverCountsIfReady` (`:856`) gates on `phase == .idle`, so not from Scrollover. But `setRead`/`setStarred` (`:712`, `:731`) call `reloadCounts()` unconditionally, and `reloadCounts` → `publishNavigationProjection` → `catalog`/`feedCounts`/`categoryCounts` assignment → SwiftUI invalidation → `updateUIViewController`. A swipe-to-read during scrolling therefore does schedule a nav refresh whose completion can land mid-scroll. Worth knowing; not implicated in pure scrolling.
- **Can Undo state creation be unexpectedly expensive?** No. `recordSuccessfulScrolloverUndo` (`:865`) does bounded array work, and while scrolling it is deferred entirely (`:821–825`).
- **Can geometry rebaselining trigger layout work?** No. `invalidateGeometry` only clears tracker dictionaries.
- **Can a targeted removal cause scroll-position compensation?** Yes, but via Finding 3.1's `invalidateLayout()` at `:971`, not via the removal itself.

### Finding 6.1 — Per-frame allocation churn in the geometry sampler (minor)

`sampleScrolloverGeometry` (`ArticleListView.swift:1175`) runs on every `scrollViewDidScroll`. Per callback, `IOSUIKitScrolloverGeometryTracker.receive` (`:382`) performs: `hasMaterialLayoutChange` over up to 96 retained frames, a `visibleIDs` `compactMap` building a fresh `Set`, `retainedFrames.merge` over up to 96 entries, and `Set(retainedFrames.keys).union(visibleIDs)` at `:433` — two more freshly allocated sets of ~96 elements, every frame.

Separately, `IOSUIKitResolvedScrolloverFrameStore.record` (`:305`) sorts and rebuilds its entire 96-entry dictionary whenever a *new* article ID is inserted at capacity — roughly once per newly displayed cell, not once per frame.

Order of magnitude: tens of microseconds per frame plus four collection allocations per frame. Against an 8.3 ms budget at 120 Hz that is under one percent.

**Confidence:** **unlikely** to be a stall cause. You asked me not to overfocus on theoretical microallocations, and this qualifies as "real but too small". Worth cleaning only when touching this file for another reason: `:433` can reuse a retained scratch set, and the eviction in `record` can be an amortized bulk trim rather than a sort-per-insert.

---

## 7. Prefetch and reuse lifecycle

`prefetchItemsAt` (`ArticleListView.swift:1277`) is correctly structured: it prepares layout metrics for the incoming index paths, deduplicates against an existing task for the same request (`:1288`), and stores a `(request, task)` pair. `cancelPrefetchingForItemsAt` (`:1302`) cleans up by identifier. The `defer` block at `:1291–1295` correctly clears only its own generation. `prefetchTasks` cannot grow unbounded — entries are removed on cancel, on completion, and on structural removal (`:928`).

The one defect on this path is Finding 4.1: `cancelAllPrefetch()` breaks the contract with UIKit's prefetch bookkeeping.

One further note: `willDisplay` calls `prepareVisibleLayoutMetrics()` (`:1093`, `:1403`) for **every** cell that begins displaying. Each call sorts `indexPathsForVisibleItems`, maps them through `renderedItem` and `preparedLayoutInput`, and constructs an `IOSUIKitArticleLayoutKey` per row — which hashes the full `title`, `feedTitle`, `publishedDate` and `preview` strings. For ~8 visible cells that is ~8 full-string-set hashes per appearing cell. It is not a stall by itself, but it is quadratic in the visible-window size for no benefit: the prefetch callback and the prepared window already cover these rows. Reducing it to the newly displayed cell only would be a small, safe win. Consider it a secondary item within Finding 2.x.

---

## 8. First-scroll-after-idle behaviour

Code-driven mechanisms that genuinely explain a warm-up effect, in descending order of confidence:

1. **Feed icon coldness (Finding 4.3).** Decoded icons live in `feedIconPresentationStates` for the session. First pass over a region pays full-resolution main-thread PNG decodes; second pass pays nothing. This is the strongest code-established explanation for the cold/warm asymmetry.
2. **`NSCache` purging.** `ArticleImagePipeline` uses `NSCache` (`ArticleImagePipeline.swift:40`), which the system empties automatically on memory pressure and on backgrounding. So does the `URLCache`'s 8 MB memory portion (`:392–396`). After the app has been idle or backgrounded, article images are cold and must be re-fetched and re-decoded — at `.utility` QoS (Finding 4.2a).
3. **Prepared layout metrics survive, but in-flight measurements do not.** `IOSUIKitPreparedArticleLayoutMetricsCache` is a plain dictionary (capacity 512) that is never cleared, so it is warm across idle. Good. But the *first* scroll after idle triggers `schedulePreparedLayoutWindow`, and the first font-descriptor match after a long idle (`IOSUIKitArticleLayoutEngine.swift:483`) may have to repopulate CoreText caches that the system reclaimed — a millisecond-class cost that only occurs once.
4. **First layout pass and first reuse of a cell variant.** The first cell of each variant pays initial constraint installation. One-time, small.

Not establishable from source, and I will not claim it: **DVFS.** After idle the CPU sits at a low P-state and the scheduler ramps over tens of milliseconds. A burst of work at the start of the first scroll therefore executes at reduced clock. This is real hardware behaviour, it perfectly matches "worse after idle, better once warmed up", and no amount of source review can separate it from items 1–4. The only way to distinguish them is to compare a cold-start scroll against a warm scroll over *the same rows* with the diagnostics counters — which brings you back to Finding 5.1.

---

## 9. Architectural questions

### A. Is there still an obvious avoidable main-thread/MainActor operation that should be removed regardless of profiling?

**Yes — four, in order of how clearly avoidable they are:**

1. **Feed icon `UIImage(data:)` on the MainActor without downsampling** (`NewsreaderStore.swift:509`). Full-resolution PNG decode deferred into a CATransaction commit, for a 22 pt slot, unbounded in memory. There is no argument for keeping this.
2. **Re-configuring every visible cell on `.append` and `.remove`** (`ArticleListView.swift:960–963`). The appended rows are not visible; the surviving rows did not change. Pure waste, including a forced `setNeedsLayout` per cell.
3. **`cancelAllPrefetch()` on structural change** (`:968`). Destroys in-flight image work that UIKit will not re-request, and forces a cold visible load moments later.
4. **Discarding the synchronously computed layout metrics** (`:1000–1002`). Paying Core Text on the main thread and then throwing the result away, while separately enqueuing the identical computation on a background thread.

Add to that the unconditional `collectionViewLayout.invalidateLayout()` at `:971`, which is redundant alongside the snapshot apply for append and remove.

None of these needs a trace to justify removing.

### B. Is the current Image Pipeline robust enough for smooth scrolling on real iPhone hardware?

**The article-image pipeline is architecturally sound but under-hardened. The feed-icon path is not a pipeline at all and needs the most work.**

`ArticleImagePipeline` gets the hard parts right: request canonicalization with upward bucketing, in-flight coalescing with generation safety, visible-over-prefetch prioritization with promotion, bounded concurrency and bounded queues, and off-main downsampling with `kCGImageSourceShouldCacheImmediately`. I found no race or leak in it.

Further hardening **is** justified from source alone, on three counts: `.utility` QoS for visible decodes; handing Core Animation a CGImage in the source's pixel format so the final conversion lands on the main thread at commit; and a 48 MB budget against ~2.7 MB per decoded card, which is about 18 images. None of these is a design flaw — they are the three tuning decisions that separate "correct" from "smooth on device".

The feed-icon path needs the same treatment it never received: bounded, downsampled, decoded off the main actor.

### C. Is Diffable itself the likely problem, or are the update patterns around it?

**The update patterns, clearly.**

I will not assert that `NSDiffableDataSourceSnapshot`'s internal diff is O(n) — the code does not establish it and the framework does not document it in a way I can rely on. What the code *does* establish is that Flux surrounds every structural update with avoidable work of its own: a full `dataSource.snapshot()` round-trip on the hot path, a redundant full layout invalidation, a whole-visible-set reconfigure, and the teardown of two asynchronous pipelines. Separately, Finding 3.2 means the controller can silently fall back to a full O(N) rebuild whenever SwiftUI coalesces two structural revisions — and nothing in the counters distinguishes that from a cheap append.

Fix the surroundings first. If a device run then still attributes time to `apply` itself, that is a different and much harder conversation, and it will be backed by evidence rather than assumption.

### D. Has the evidence threshold for U3.7.5 (manual cell layout) now been reached?

**No. Defer again — but with one concrete change to the reasoning.**

The gate in the U3.6.5→U3.7 plan is: *do this only if instrumentation still attributes meaningful main-thread cost to Auto Layout/StackView layout inside already-sized cells.* That gate has still not been met, and now it cannot be met, because the instrumentation that would answer it is compiled out of Release (Finding 5.1).

Three substantive reasons to defer:

1. **The sizing path is already Auto-Layout-free.** `preferredLayoutAttributesFitting` returns the engine's height without ever invoking the solver. The premise that motivated U3.7.5 — solver cost discovered during sizing — is gone.
2. **Manual layout would not touch a single one of the findings above.** Not the feed icon decode, not the prefetch cancellation, not the snapshot round-trip, not the layout invalidation, not the synchronous Core Text fallback, not the CA image conversion. It would also not remove UILabel's own text rendering, which is the larger half of per-cell text cost — only a switch to pre-typeset `CTFrame` drawing would, and that is a much bigger commitment than "assign frames in `layoutSubviews`".
3. **It would create a second geometry implementation.** `IOSUIKitArticleLayoutEngine` already computes every subview frame (`titleFrame`, `metadataFrame`, `unreadFrame`, `feedIconFrame`, `feedTitleFrame`, `commentsFrame`, `starFrame`, `dateFrame`, `previewFrame`). Manual layout means the cell consumes those instead of constraints — which is elegant, but it puts RTL, Dynamic Type, accessibility sizes and the metadata row's independent semantic direction under a second set of rules that must be proven equivalent on every device class. That is a real regression surface to accept without evidence.

**The one genuine pro-U3.7.5 data point is Finding 1.1** — constraint deactivate/activate on every variant flip during reuse. That is a real, recurring Auto Layout cost in the scroll path. But it has a much cheaper fix (separate reuse identifiers per variant), and `layoutVariantSwitchCount / configureCount` already measures it exactly.

**Concrete gate for reopening U3.7.5:** with Findings 1.1, 1.2, 2.1, 3.1, 4.1 and 4.3 repaired and diagnostics enabled in Release, if a device run still shows meaningful main-thread time inside `layoutSubviews` for cells whose variant did not change — then the evidence exists. Not before.

### E. One targeted repair, independent hardening of three areas, or no change until Instruments data exists?

**None of the three as stated. Do this instead, in two steps.**

**Step 0 — restore your ability to measure (hours, not days).** Enable `FLUX_PERFORMANCE_DIAGNOSTICS` in Release and surface `printSnapshot()` on screen in `DeveloperDiagnosticsView`. This is one build-setting line plus a small view change. It does not require Instruments, Xcode attachment, or a developer profile on the company phone: reset the counters, reproduce the stutter, read the numbers, screenshot. Then one device pass immediately tells you:

| Question | Counter |
|---|---|
| Is Finding 1.1 real? | `layoutVariantSwitchCount` ÷ `configureCount` |
| Is Finding 2.1 real? | `deterministicHeightSynchronousFallbacks`, `...FallbackMaxNanoseconds` |
| Is Finding 3.1 firing often enough to matter? | `structuralReconciliationCount`, `snapshotApplyCount`, `layoutInvalidationCount` |
| Is Finding 4.2c real? | `memoryCacheEvictions`, `visibleImageMemoryCacheHitRate` |
| Is any solver work left at all? | `systemLayoutSizeFittingCalls` (expected: 0) |

Finding 3.2 needs one new counter added alongside — a few lines.

**Step 1 — ship the repairs that need no evidence, as one coherent change.** Findings 1.2, 3.1 (items 1–3), 4.1 and 2.1 are all inside two functions, are all removals of work rather than new mechanisms, and are all justified on their own terms. Finding 4.3 is a separate, self-contained ~15-line change. Together this is a day of work, not a redesign, and it attacks the composite event directly.

**The tradeoff, stated plainly.** A single targeted repair is the wrong shape here because the mechanism is a *composite*: one event triggering six kinds of work and tearing down two pipelines. Fixing one component leaves the others firing in the same frame. Conversely, "independent hardening of Image + Diffable + Cell Layout" is too broad — it pulls in U3.7.5, which I have argued against, and a Diffable redesign, which the evidence does not support. And "no change until Instruments data exists" concedes a constraint you do not actually have: you built a Release-capable instrument already and it is one build setting away from working.

The asymmetry that decides it: everything in Step 1 is *less* code doing *less* work on the main thread. If profiling later exonerates all of it, you have lost nothing and the Timeline is simpler. U3.7.5, by contrast, adds a second geometry implementation with a real regression surface — that one must stay behind evidence.

---

## 10. Final ranking

**1. Structural-update fan-out in `IOSUIKitArticleTimelineController.update` (`ArticleListView.swift:904–972`).**
Largest single event on the scroll path; bundles a full snapshot round-trip, a redundant full layout invalidation, a whole-visible-set reconfigure, and the destruction of both the image-prefetch and layout-measurement pipelines. Contains confirmed avoidable work. Ranked first for magnitude and certainty of waste; its firing rate is bounded by page appends, which the counters will settle. Includes the silent full-rebuild fallback of Finding 3.2.

**2. Feed-icon decode on the MainActor at full resolution (`NewsreaderStore.swift:501–520`).**
Best fit for the *irregular timing* and the *cold-versus-warm* asymmetry specifically. The only unbounded image work reaching the main thread anywhere in the reviewed code. Fires on first encounter with each feed, several can land in one commit, and it is invisible to every existing counter.

**3. Prepared-layout-metrics misses → synchronous Core Text on the main thread (`ArticleListView.swift:996–1003`), amplified by #1 and possibly by `.utility` QoS lock contention (`IOSUIKitArticleLayoutEngine.swift:223–227, 479–484`).**
Modest on its own; systematically clustered by #1. The discard-without-caching is a confirmed defect. The priority-inversion component is the most plausible explanation for stalls that are intermittent and device-only, but it cannot be proven from source.

**4. Article-image pipeline tuning: `.utility` decode QoS, un-normalized CGImage handed to Core Animation, ~18-image cache budget, prefetch destroyed by #1 (`ArticleImagePipeline.swift:142–144, 321–324, 408–422`).**
Governs how late and how bursty image completions are. The CA conversion is the only part that lands directly on the main thread.

**5. Build configuration: diagnostics compiled out of Release; single-file compilation mode (`project.pbxproj:409–436`).**
Not a cause of the stutter, but the reason it cannot currently be measured. Highest value per unit of effort on the entire list.

**6. Layout-variant thrash on reuse (`ArticleListView.swift:1887–1920`).**
Real recurring Auto Layout cost, cheaply fixed with separate reuse identifiers. The only genuine argument for U3.7.5, and it has a cheaper answer.

**Unlikely / already sufficiently mitigated:**

- **Scrollover.** Performs no Core write, no presentation publication and no structural change during forward scrolling. The repaired design holds. Its per-frame geometry sampling costs tens of microseconds — real, but two orders of magnitude below the observed symptom.
- **Diffable Data Source itself.** The surrounding update patterns are the problem; there is no evidence against the framework.
- **Production Auto Layout self-sizing.** Removed. `preferredLayoutAttributesFitting` never solves.
- **Cell height invalidation from images or status.** Genuinely geometry-neutral; U3.6.5 holds.
- **Rounded-corner offscreen passes** on `articleImageView` and `feedIconContainer` (`:1681–1706`, `:1765–1778`). Both layers have contents *and* sublayers *and* `masksToBounds`, so each forces an offscreen render pass — roughly two per visible cell. This is steady GPU cost that would depress the frame rate uniformly, not produce 100 ms holds. Worth revisiting only after the main-thread items are resolved, and Finding 4.3 removes half the pressure for free by shrinking the icon.
- **Prefetch/reuse bookkeeping.** Correct apart from Finding 4.1.
- **Allocation churn in the scroll sampler.** Measurable in principle, irrelevant in practice at this magnitude.
