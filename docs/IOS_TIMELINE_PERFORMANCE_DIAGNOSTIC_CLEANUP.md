# iOS Timeline Performance Diagnostics — Experiment Record and Cleanup Contract

Status: **cleanup complete — 18 September 2026.** Every temporary diagnostic listed
below has been removed. This file remains as the historical experiment record and
as the audit that closed it.

Branch during investigation: `perf/ios-frame-headroom`

This document records the temporary diagnostics used while investigating intermittent scrolling unevenness in the native iOS UIKit article timeline. It exists so that experimental behavior cannot accidentally become shipping architecture.

The experiment history is useful evidence and should remain documented. The diagnostic code paths themselves are not automatically production features. Before this work is merged or released, every diagnostic listed below must be audited and either removed or explicitly promoted to a documented production mechanism.

## Measurement caveat

An early screen-recording analysis treated pixel-identical repeated ReplayKit frames as dropped display frames. The original Flux recording produced a value around 5.6%, but an Apple Calendar control produced roughly 13% with the same method. Therefore the repeated-frame percentage and the earlier `<1%` target are **not valid application-performance KPIs** and must not be used as release gates.

Physical-device subjective comparison and Instruments traces were subsequently used only as diagnostic evidence. Simulator Time Profiler data is useful for locating CPU work, but it is not proof of physical-device frame pacing.

## Baseline hardening that is not diagnostic by itself

The investigation also produced changes intended as genuine hardening rather than temporary A/B switches. These must be reviewed normally, not blindly reverted with the diagnostics. Relevant work included whole-module optimization for archives, BGRA raster preparation, bounded image/cache work, Scrollover copy-on-write reduction, removal of unused hot-path inputs, a larger article-image cache, and related regression tests.

In particular, do **not** interpret this cleanup contract as an instruction to revert every commit made during the performance investigation.

## Temporary experiments

### 1. Standard geometry with article images disabled

Commit: `14747e850e3c4be3387a8c75161804e03c0b2b99` — `Add standard-layout no-image performance diagnostic`

Purpose: keep Standard row/layout/image-slot geometry while suppressing article-image request/cache/prefetch/decode/presentation work.

Physical-device result: Standard became approximately as smooth as Compact.

Conclusion: article-image work is strongly implicated; general Standard geometry became a weaker primary hypothesis.

Cleanup requirement: the source-level no-image performance switch and its diagnostic-only branches/tests must not ship unless deliberately retained as an internal diagnostic facility.

### 2. Deferred article-image presentation while scrolling

Commit: `2dba8d243f81ebabb9ad850dfaade95f6fd17fe0` — `Defer article image presentation while scrolling`

Purpose: defer asynchronous image completions during dragging/deceleration and flush visible images when scrolling became idle. Cache-hit presentation remained immediate in this first version.

Physical-device result: scrolling improved, but placeholders remained visible too long and the behavior was not acceptable product UX.

Cleanup requirement: remove diagnostic scroll-state presentation deferral unless a later production design explicitly reintroduces it with its own contract.

### 3. A′ — suppress all new article-image assignments while scrolling

Commit: `3bc70a9097e047910bfcabb11346c36722191f65` — `Suppress article image assignment while scrolling`

Purpose: close the cache-hit hole from the previous experiment. While scrolling, suppress both cache-hit and asynchronous new raster assignments; retain recycled image content diagnostically and correct cells when idle.

Physical-device result: clearly smoother, with only occasional very small residual unevenness.

Interpretation: new real-image presentation during scrolling is a major contributor. This was deliberately ugly diagnostic behavior, not an acceptable product implementation.

Cleanup requirement: remove stale/wrong-image retention, scroll-state assignment suppression, idle correction logic, and diagnostic tests unless a later production mechanism explicitly supersedes them.

### 4. Diagnostic C — shared opaque article raster

Commit: `0226d54720d5b0bdfe38233883e3a1883a656c7b` — `Use shared opaque article raster for diagnosis`

Purpose: restore normal assignment timing while replacing all real article images with the same shared full-size opaque neutral raster. Standard geometry and image-layer assignment remained present; real article-image network/decode/cache/prefetch work was bypassed.

Physical-device result: nearly smooth, comparable to the best diagnostic variants, with at most very rare inconspicuous unevenness.

Interpretation: `UIImageView.image = ...` by itself was not sufficient to reproduce the issue. Distinct real image content/surfaces remained implicated.

Cleanup requirement: remove the shared-raster switch, synthetic raster cache/generator, pipeline bypass, and diagnostic-specific tests.

### 5. Real decoded raster without exact-slot prerasterization

Commit: `2c3ecd8a606dec07730c3bcb4d0627b4f308bcd5` — `Use decoded article raster for diagnosis`

Diagnostic switch used during this experiment:

`IOSUIKitTimelineArticleImageDecodedRasterPerformanceDiagnostic.useDecodedRasterWithoutExactSlotRenderingForPerformanceDiagnosis`

Purpose: restore real requests/cache/loading/prefetch/immediate assignment while changing the native pipeline from:

`Data -> ImageIO thumbnail -> renderDisplayReady exact-slot BGRA raster -> cache -> UIImageView`

to:

`Data -> ImageIO thumbnail -> cache -> UIImageView.scaleAspectFill`

Native-resolution intent remained approximately 3x. Representative iPhone 15 Standard geometry used a `1083x609` exact slot in the old path and an ImageIO maximum around `1088` pixels in the diagnostic path. Runtime corner clipping was temporarily reintroduced because corners were no longer baked into the exact-slot raster.

Physical-device result: **not meaningfully better** than the normal real-image path and subjectively more uneven than Diagnostic C.

Conclusion: the second exact-slot `renderDisplayReady` rasterization was downgraded as the primary explanation. The experiment does not justify replacing the production raster architecture by itself.

Cleanup requirement: remove the decoded-raster representation switch, diagnostic cache-identity mode, runtime-corner diagnostic branch, and diagnostic-only tests unless later work explicitly adopts this architecture for independent reasons.

### 6. 2x exact-slot raster-size diagnostic

A later diagnostic was planned to restore the normal exact-slot pipeline and change only effective article-image raster scale from physical-display scale (typically 3x on iPhone 15) to exactly 2x. Representative dimensions were intended to change from about `1083x609` (~2.52 MiB BGRA) to `722x406` (~1.12 MiB BGRA), while preserving logical slot geometry, real images, normal assignment, cache, prefetch, crop, and baked corners.

Purpose: isolate whether scrolling unevenness scales materially with the pixel/byte volume of distinct image rasters.

**Resolved.** The experiment ran on the physical iPhone 15: 2x was not meaningfully
smoother than 3x. Article-raster pixel volume is therefore not the driver of the
residual unevenness, and the production architecture keeps the physical display
scale.

`IOSUIKitTimelineArticleImageRasterScalePerformanceDiagnostic` and
`useTwoXArticleImageRasterForPerformanceDiagnosis` were removed on 18 September
2026. The tests that used the switch only to inject a non-native scale were kept
and renamed: they assert pipeline properties — exact-slot BGRA output, and that
rasters of different scales cannot alias in the memory cache — which still hold.
The cell keeps a documented `articleImageRasterScale` test seam for that purpose.

## Evidence that should remain after cleanup

The following conclusions are historical diagnostic evidence, not guaranteed explanations of the final root cause:

- Compact was subjectively very smooth on the physical iPhone 15.
- Standard geometry with article images disabled was approximately Compact-smooth.
- Warm-cache Standard still showed unevenness, weakening network/decode as a sufficient explanation.
- Suppressing new real-image assignments while scrolling improved behavior substantially.
- Normal assignment of one shared opaque raster was nearly smooth.
- Removing exact-slot prerasterization while retaining real approximately-3x images did not materially improve scrolling.
- No experiment above proves a specific Core Animation, Render Server, IOSurface, texture-upload, memory-bandwidth, or GPU mechanism.
- U3.7.5/manual cell layout was not justified by these experiments and remained deferred during this investigation.

## Mandatory pre-merge cleanup audit

Before merging the performance branch or declaring the timeline implementation production-ready, search the iOS source and tests for at least the following terms and for semantically equivalent code introduced later:

- `PerformanceDiagnostic`
- `PerformanceDiagnosis`
- `Diagnosis`
- `useDecodedRasterWithoutExactSlotRenderingForPerformanceDiagnosis`
- `useTwoXArticleImageRasterForPerformanceDiagnosis`
- no-image article-image suppression
- scroll-state image-presentation deferral
- cache-hit/async assignment suppression
- stale image retention during reuse
- shared/synthetic opaque article raster generation
- forced diagnostic raster scale
- diagnostic-only cache representation keys

For each match classify it as one of:

1. **Remove** — temporary experiment only.
2. **Promote** — intentionally becomes production behavior; remove diagnostic naming and document/test the production contract.
3. **Retain as tooling** — only if there is a deliberate long-term diagnostics strategy and the code cannot affect normal Release behavior.

The final cleanup must also remove or rewrite tests whose only purpose is to lock temporary diagnostic behavior. Tests for production invariants discovered during the experiments should be preserved.

## Final-state verification checklist

After cleanup:

- no temporary experiment is enabled by a source-level `true` constant;
- normal Release/TestFlight behavior cannot select a diagnostic branch accidentally;
- article-image request, cache, prefetch, presentation, reuse, and raster-scale behavior match the final documented production design;
- Compact behavior remains intentional;
- Phase-D documentation describes the final architecture separately from this historical experiment record;
- repository-standard Core/iOS tests, app build, archive, and `git diff --check` pass.

This file should remain as the historical experiment/cleanup record even after diagnostic code is removed, updated with the final cleanup commit and final production decision.

## Final cleanup audit — 18 September 2026

The search terms above were run against the iOS sources and tests. Experiments 1
through 6 produce no matches. `MUST NOT SHIP` appears nowhere in the Swift
sources.

Removed in this pass:

- `IOSUIKitTimelineFrameHeadroomRecorder` and the whole
  `IOSTimelineFrameHeadroomDiagnostic.swift` file, its project entry, its ~20
  call sites, its Developer Diagnostics section, and its test;
- `IOSUIKitTimelineInstrumentedTableView`, a `UITableView` subclass that existed
  only to time `layoutSubviews`;
- the six runtime A/B arms (scroll edge effect, Scrollover undo pill, title
  presentation, capsule material, status bar scrim, article image size) and
  their Settings pickers;
- `IOSUIKitTimelineArticleImageRasterScalePerformanceDiagnostic`;
- a dead `if phase == .idle { } else if wasIdle { }` left behind by the recorder
  removal, which no compiler warning would have surfaced.

Deliberately retained, classified per the three categories above:

| Symbol | Class | Reason |
|---|---|---|
| `IOSUIKitTimelineTopScrimView` | Promote | Retained as the iOS/iPadOS 17-25 status-bar fallback. iOS/iPadOS 26+ normally uses the native `.automatic` top edge effect; compact iPhone landscape disables that effect and the status-bar scrim has zero height because the system status bar is absent there. The bottom edge effect remains disabled. |
| `IOSUIKitTimelinePerformanceMetrics` | Promote | The oracle tests assert `systemLayoutSizeFittingCalls == 0` and `preferredLayoutAttributesFittingCalls == 0` through it. That is the proof that the cell never self-sizes — the core invariant of the UITableView migration. Removing the counters would delete the proof. |
| `IOSUIKitTimelinePerformanceDiagnostics` | Retain as tooling | Console readout for the above. Its UI is behind `#if DEBUG \|\| FLUX_PERFORMANCE_DIAGNOSTICS` and cannot be reached in Release; the static controller reference is `weak`. The counter increments themselves do run in Release. |
| `articleImageRasterScale` on the cell | Retain as tooling | Narrow decoded-scale test seam only; there is no production renderer or raster-scale switch. |

## Final production decision

The investigation ended with a presentation decision rather than a performance
fix, and the evidence for that is recorded in the measurement caveat above.

A later iOS 27 acceptance pass closed the remaining renderer question: scrolling
through more than 200 articles was smooth, and the extra exact-slot CGContext
article renderer showed no visible advantage over display-sized ImageIO decode
plus UIImageView/Core Animation. On 22 September 2026 that legacy article-image
renderer, its diagnostic switch, and its renderer-specific cache state were
removed. The post-retirement canonical XCTest run completed
`./apple/ios/Build/test.sh` with **348 tests and 0 failures**, including the
single-renderer image/EXIF coverage and deterministic UIKit RTL geometry.
Historical experiment descriptions above remain intentionally as the
investigation record and no longer describe shipping code.

Fixed chrome, no longer switchable: ordinary compact portrait and horizontal
regular split modes use the native `.automatic` top scroll-edge effect on
iOS/iPadOS 26+, while compact iPhone landscape disables it and returns scope plus
Sync/Filter/More to native top navigation toolbar items. A non-`nil`
`toolbarVerticalEdge` changes persistent-split Sync/Filter/More from detached
floating controls to native top-toolbar items so the system may place them
vertically; it does not change the regular-mode `.automatic` Timeline top-edge
policy. The bounded status-bar gradient remains the 17-25 fallback
and measures to zero where the status bar is absent; the bottom edge effect
remains disabled. Detached scope/action capsules remain the horizontal-mode
presentation where applicable. The Scrollover undo pill remains in
`.regularMaterial`.

New presentation mode **Visual compact** (`ArticlePresentationMode.visualCompact`):
a 4:3 thumbnail beside the title, metadata bar full width above, preview below —
and on containers wider than 600 pt the preview joins the column beside the
image. It is a normal user setting alongside Visual and Compact, not a
diagnostic.

The reason it exists is perceptual, not computational. A full-width image edge
travelling vertically is the strongest judder cue available; breaking that edge
makes the same dropped frames stop being visible. Screen-recording comparisons
of the two layouts differed by 0.04 percentage points — and per the measurement
caveat at the top of this document, that metric is not a valid KPI in either
direction.


## U5 source-cleanup follow-up — 22 September 2026

The final behavior-preserving U5 source cleanup removes the historical
SwiftUI/List `IOSScrolloverGeometryController` and its row-region/scroll-geometry
helper types. Still-relevant crossing, resize/rebaseline, terminal-bottom and
Undo-rearm regression semantics now target the productive
`IOSUIKitScrolloverGeometryTracker` directly.

Productive UIKit Scrollover sampling/tracking has been extracted from the large
Timeline source into `IOSUIKitScrolloverGeometry.swift`. This is a source
ownership cleanup only; the detector semantics are unchanged.

The redundant `IOSUIKitArticleCell.Metrics` wrapper has also been removed.
Configured cells now consume the already-prepared
`IOSUIKitArticleLayoutMetrics` for variant, insets, accessory geometry and image
slot size. The cheap non-text `IOSUIKitArticleGeometry` remains intentionally
available to the controller for reuse-identifier selection and image-prefetch
target sizing without invoking Core Text measurement.

The retained performance metrics/diagnostics and `articleImageRasterScale` test
seam keep their classifications from the final cleanup audit above. They are not
legacy renderer switches.

Final U5 acceptance passed on 22 September 2026. The canonical
`./apple/ios/Build/test.sh` run executed **338 tests with 0 failures**,
`./apple/ios/Build/build-app.sh` succeeded, `git diff --check main...HEAD`
was clean, and the focused physical-device smoke test passed. The reduction from
the earlier 348-test renderer-retirement baseline is intentional: redundant
tests tied to the removed historical Scrollover controller were deleted while
the still-relevant semantics were migrated to the productive
`IOSUIKitScrolloverGeometryTracker`.

With those gates complete, U5 is closed and the current UIKit Timeline
container/rendering architecture is frozen. Future feature work must extend this
baseline rather than reopening the container, Scrollover detector, or
fundamental image/layout pipeline without new reproducible device evidence of a
concrete regression.
