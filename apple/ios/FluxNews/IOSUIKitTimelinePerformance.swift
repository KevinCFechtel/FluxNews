import UIKit

#if DEBUG || FLUX_PERFORMANCE_DIAGNOSTICS
@MainActor
enum IOSUIKitTimelinePerformanceDiagnostics {
    weak static var currentController: IOSUIKitArticleTimelineController?

    static func resetAndPrint() async {
        guard let controller = currentController else {
            print("[Timeline Performance] No active Timeline controller")
            return
        }
        controller.resetPerformanceMetrics()
        await ArticleImagePipeline.shared.resetMetrics()
        print("[Timeline Performance] Metrics reset")
    }

    static func printSnapshot() async {
        guard let controller = currentController else {
            print("[Timeline Performance] No active Timeline controller")
            return
        }
        let timeline = controller.performanceSnapshot()
        let image = await ArticleImagePipeline.shared.metrics()
        let cacheHitRate = timeline.heightCacheHits + timeline.heightCacheMisses > 0 ? Double(timeline.heightCacheHits) / Double(timeline.heightCacheHits + timeline.heightCacheMisses) : nil
        let solverRate = timeline.preferredLayoutAttributesFittingCalls > 0 ? Double(timeline.systemLayoutSizeFittingCalls) / Double(timeline.preferredLayoutAttributesFittingCalls) : nil
        let averageSolveTime = timeline.systemLayoutSizeFittingCalls > 0 ? Double(timeline.systemLayoutSizeFittingTotalNanoseconds) / Double(timeline.systemLayoutSizeFittingCalls) : nil
        let imageHitRate = image.visibleMemoryCacheHits + image.visibleMemoryCacheMisses > 0 ? Double(image.visibleMemoryCacheHits) / Double(image.visibleMemoryCacheHits + image.visibleMemoryCacheMisses) : nil
        print("""
        [Timeline Performance]
        timeline preferredLayoutAttributesFittingCalls=\(timeline.preferredLayoutAttributesFittingCalls) systemLayoutSizeFittingCalls=\(timeline.systemLayoutSizeFittingCalls) configureCount=\(timeline.configureCount) reuseCount=\(timeline.reuseCount) layoutVariantSwitchCount=\(timeline.layoutVariantSwitchCount) imageBindingCount=\(timeline.imageBindingCount) structuralReconciliationCount=\(timeline.structuralReconciliationCount) snapshotApplyCount=\(timeline.snapshotApplyCount) layoutInvalidationCount=\(timeline.layoutInvalidationCount)
        geometry identityChanges=\(timeline.geometryIdentityChanges) layoutInvalidations=\(timeline.geometryLayoutInvalidationCount) preparedWindowReplacements=\(timeline.preparedWindowReplacementCount) preparedWindowGenerationsSuperseded=\(timeline.preparedWindowGenerationsSuperseded)
        deterministicHeight requests=\(timeline.deterministicHeightRequests) preparedHits=\(timeline.deterministicHeightPreparedHits) synchronousFallbacks=\(timeline.deterministicHeightSynchronousFallbacks) synchronousFallbackTotalNanoseconds=\(timeline.deterministicHeightSynchronousFallbackTotalNanoseconds) synchronousFallbackMaxNanoseconds=\(timeline.deterministicHeightSynchronousFallbackMaxNanoseconds)
        preparedLayout requests=\(timeline.preparedLayoutRequests) cacheHits=\(timeline.preparedLayoutCacheHits) cacheMisses=\(timeline.preparedLayoutCacheMisses) measurementsStarted=\(timeline.preparedLayoutMeasurementsStarted) measurementsCompleted=\(timeline.preparedLayoutMeasurementsCompleted) discardedResults=\(timeline.preparedLayoutDiscardedResults) cancellations=\(timeline.preparedLayoutCancellations) maximumConcurrency=\(timeline.preparedLayoutMaximumConcurrency) visibleRequests=\(timeline.visibleLayoutMetricRequests) visibleCacheHits=\(timeline.visibleLayoutMetricCacheHits) visibleCacheMisses=\(timeline.visibleLayoutMetricCacheMisses) prefetchRequests=\(timeline.prefetchLayoutMetricRequests) prefetchCacheHits=\(timeline.prefetchLayoutMetricCacheHits) prefetchCacheMisses=\(timeline.prefetchLayoutMetricCacheMisses)
        image memoryCacheHits=\(image.memoryCacheHits) memoryCacheMisses=\(image.memoryCacheMisses) visibleMemoryCacheHits=\(image.visibleMemoryCacheHits) visibleMemoryCacheMisses=\(image.visibleMemoryCacheMisses) prefetchMemoryCacheHits=\(image.prefetchMemoryCacheHits) prefetchMemoryCacheMisses=\(image.prefetchMemoryCacheMisses) memoryCacheInsertions=\(image.memoryCacheInsertions) memoryCacheEvictions=\(image.memoryCacheEvictions) memoryCacheCostLimit=\(image.memoryCacheCostLimit) inFlightDedupHits=\(image.inFlightDedupHits) startedOperations=\(image.startedOperations) completedOperations=\(image.completedOperations) retiredOperations=\(image.retiredOperations) maximumActiveOperations=\(image.maximumActiveOperations) visibleStarts=\(image.visibleStarts) prefetchStarts=\(image.prefetchStarts) activeOperations=\(image.activeOperations) queuedVisibleRequests=\(image.queuedVisibleRequests) queuedPrefetchRequests=\(image.queuedPrefetchRequests)
        derived heightCacheHitRate=\(cacheHitRate.map { String(format: "%.3f", $0) } ?? "n/a") solverRate=\(solverRate.map { String(format: "%.3f", $0) } ?? "n/a") averageSolveTime=\(averageSolveTime.map { String(format: "%.0f", $0) } ?? "n/a") visibleImageMemoryCacheHitRate=\(imageHitRate.map { String(format: "%.3f", $0) } ?? "n/a")
        """)
    }
}
#endif

enum IOSUIKitArticleCellLayoutVariant: Hashable {
    case compact
    case visualTextOnly
    case visualPortrait
    case visualLandscape
    /// `Visual compact`: metadata spans the row above; title and publication
    /// row share the content row with the trailing image; preview follows below.
    case visualSideTitle
    /// The same arrangement on a wide container, except the preview also joins
    /// the text column beside the image instead of running underneath it.
    case visualSideTitleWide
    /// `Visual compact` for an article without an image: same order, full width.
    case visualSideTitleTextOnly

    /// Whether the cell shows its image view at all. Derived rather than listed
    /// at each call site, so a new variant cannot silently default to "shown".
    var showsImageSlot: Bool {
        switch self {
        case .compact, .visualTextOnly, .visualSideTitleTextOnly: return false
        case .visualPortrait, .visualLandscape, .visualSideTitle, .visualSideTitleWide: return true
        }
    }
}

struct IOSUIKitTimelinePerformanceSnapshot: Equatable {
    let preferredLayoutAttributesFittingCalls: UInt64
    let heightCacheHits: UInt64
    let heightCacheMisses: UInt64
    let systemLayoutSizeFittingCalls: UInt64
    let systemLayoutSizeFittingTotalNanoseconds: UInt64
    let systemLayoutSizeFittingMaxNanoseconds: UInt64
    let systemLayoutSizeFittingP50ApproxNanoseconds: UInt64
    let systemLayoutSizeFittingP95ApproxNanoseconds: UInt64
    let configureCount: UInt64
    let reuseCount: UInt64
    let layoutVariantSwitchCount: UInt64
    let imageBindingCount: UInt64
    let structuralReconciliationCount: UInt64
    let snapshotApplyCount: UInt64
    let layoutInvalidationCount: UInt64
    let geometryIdentityChanges: UInt64
    let geometryLayoutInvalidationCount: UInt64
    let preparedWindowReplacementCount: UInt64
    let preparedWindowGenerationsSuperseded: UInt64
    let preparedLayoutRequests: UInt64
    let preparedLayoutCacheHits: UInt64
    let preparedLayoutCacheMisses: UInt64
    let preparedLayoutMeasurementsStarted: UInt64
    let preparedLayoutMeasurementsCompleted: UInt64
    let preparedLayoutDiscardedResults: UInt64
    let preparedLayoutCancellations: UInt64
    let preparedLayoutMaximumConcurrency: UInt64
    let visibleLayoutMetricRequests: UInt64
    let visibleLayoutMetricCacheHits: UInt64
    let visibleLayoutMetricCacheMisses: UInt64
    let prefetchLayoutMetricRequests: UInt64
    let prefetchLayoutMetricCacheHits: UInt64
    let prefetchLayoutMetricCacheMisses: UInt64
    let deterministicHeightRequests: UInt64
    let deterministicHeightPreparedHits: UInt64
    let deterministicHeightSynchronousFallbacks: UInt64
    let deterministicHeightSynchronousFallbackTotalNanoseconds: UInt64
    let deterministicHeightSynchronousFallbackMaxNanoseconds: UInt64
}

@MainActor
final class IOSUIKitTimelinePerformanceMetrics {
    // Logarithmic nanosecond buckets provide bounded percentile estimates.
    private static let durationBucketCount = 64
    private var durationBuckets = Array(repeating: UInt64(0), count: durationBucketCount)
    private var preferredLayoutAttributesFittingCalls: UInt64 = 0
    private var heightCacheHits: UInt64 = 0
    private var heightCacheMisses: UInt64 = 0
    private var systemLayoutSizeFittingCalls: UInt64 = 0
    private var systemLayoutSizeFittingTotalNanoseconds: UInt64 = 0
    private var systemLayoutSizeFittingMaxNanoseconds: UInt64 = 0
    private var configureCount: UInt64 = 0
    private var reuseCount: UInt64 = 0
    private var layoutVariantSwitchCount: UInt64 = 0
    private var imageBindingCount: UInt64 = 0
    private var structuralReconciliationCount: UInt64 = 0
    private var snapshotApplyCount: UInt64 = 0
    private var layoutInvalidationCount: UInt64 = 0
    private var geometryIdentityChanges: UInt64 = 0
    private var geometryLayoutInvalidationCount: UInt64 = 0
    private var preparedWindowReplacementCount: UInt64 = 0
    private var preparedWindowGenerationsSuperseded: UInt64 = 0
    private var deterministicHeightRequests: UInt64 = 0
    private var deterministicHeightPreparedHits: UInt64 = 0
    private var deterministicHeightSynchronousFallbacks: UInt64 = 0
    private var deterministicHeightSynchronousFallbackTotalNanoseconds: UInt64 = 0
    private var deterministicHeightSynchronousFallbackMaxNanoseconds: UInt64 = 0

    func reset() {
        durationBuckets = Array(repeating: 0, count: Self.durationBucketCount)
        preferredLayoutAttributesFittingCalls = 0; heightCacheHits = 0; heightCacheMisses = 0
        systemLayoutSizeFittingCalls = 0; systemLayoutSizeFittingTotalNanoseconds = 0; systemLayoutSizeFittingMaxNanoseconds = 0
        configureCount = 0; reuseCount = 0; layoutVariantSwitchCount = 0; imageBindingCount = 0
        structuralReconciliationCount = 0; snapshotApplyCount = 0; layoutInvalidationCount = 0
        geometryIdentityChanges = 0; geometryLayoutInvalidationCount = 0
        preparedWindowReplacementCount = 0; preparedWindowGenerationsSuperseded = 0
        deterministicHeightRequests = 0; deterministicHeightPreparedHits = 0; deterministicHeightSynchronousFallbacks = 0
        deterministicHeightSynchronousFallbackTotalNanoseconds = 0; deterministicHeightSynchronousFallbackMaxNanoseconds = 0
    }
    func recordFittingCall() { preferredLayoutAttributesFittingCalls &+= 1 }
    func recordCacheHit() { heightCacheHits &+= 1 }
    func recordCacheMiss() { heightCacheMisses &+= 1 }
    func recordConfigure() { configureCount &+= 1 }
    func recordReuse() { reuseCount &+= 1 }
    func recordVariantSwitch() { layoutVariantSwitchCount &+= 1 }
    func recordImageBinding() { imageBindingCount &+= 1 }
    func recordStructuralReconciliation() { structuralReconciliationCount &+= 1 }
    func recordSnapshotApply() { snapshotApplyCount &+= 1 }
    func recordLayoutInvalidation() { layoutInvalidationCount &+= 1 }
    func recordGeometryChange() {
        geometryIdentityChanges &+= 1
        geometryLayoutInvalidationCount &+= 1
        layoutInvalidationCount &+= 1
    }
    func recordPreparedWindowReplacement() { preparedWindowReplacementCount &+= 1 }
    func recordPreparedWindowGenerationSuperseded() { preparedWindowGenerationsSuperseded &+= 1 }
    func recordDeterministicHeightRequest(prepared: Bool) {
        deterministicHeightRequests &+= 1
        if prepared { deterministicHeightPreparedHits &+= 1 }
    }
    func recordDeterministicHeightFallback(durationNanoseconds: UInt64) {
        deterministicHeightRequests &+= 1
        deterministicHeightSynchronousFallbacks &+= 1
        deterministicHeightSynchronousFallbackTotalNanoseconds &+= durationNanoseconds
        deterministicHeightSynchronousFallbackMaxNanoseconds = max(deterministicHeightSynchronousFallbackMaxNanoseconds, durationNanoseconds)
    }
    func recordSolve(durationNanoseconds: UInt64) {
        systemLayoutSizeFittingCalls &+= 1
        systemLayoutSizeFittingTotalNanoseconds &+= durationNanoseconds
        systemLayoutSizeFittingMaxNanoseconds = max(systemLayoutSizeFittingMaxNanoseconds, durationNanoseconds)
        durationBuckets[min(durationNanoseconds == 0 ? 0 : 63 - durationNanoseconds.leadingZeroBitCount, Self.durationBucketCount - 1)] &+= 1
    }
    func snapshot(preparation: IOSUIKitArticleLayoutPreparationSnapshot = .init(requests: 0, cacheHits: 0, cacheMisses: 0, measurementsStarted: 0, measurementsCompleted: 0, discardedResults: 0, cancellations: 0, maximumConcurrentMeasurements: 0, visibleRequests: 0, visibleCacheHits: 0, visibleCacheMisses: 0, prefetchRequests: 0, prefetchCacheHits: 0, prefetchCacheMisses: 0)) -> IOSUIKitTimelinePerformanceSnapshot {
        .init(preferredLayoutAttributesFittingCalls: preferredLayoutAttributesFittingCalls, heightCacheHits: heightCacheHits, heightCacheMisses: heightCacheMisses, systemLayoutSizeFittingCalls: systemLayoutSizeFittingCalls, systemLayoutSizeFittingTotalNanoseconds: systemLayoutSizeFittingTotalNanoseconds, systemLayoutSizeFittingMaxNanoseconds: systemLayoutSizeFittingMaxNanoseconds, systemLayoutSizeFittingP50ApproxNanoseconds: percentile(0.5), systemLayoutSizeFittingP95ApproxNanoseconds: percentile(0.95), configureCount: configureCount, reuseCount: reuseCount, layoutVariantSwitchCount: layoutVariantSwitchCount, imageBindingCount: imageBindingCount, structuralReconciliationCount: structuralReconciliationCount, snapshotApplyCount: snapshotApplyCount, layoutInvalidationCount: layoutInvalidationCount, geometryIdentityChanges: geometryIdentityChanges, geometryLayoutInvalidationCount: geometryLayoutInvalidationCount, preparedWindowReplacementCount: preparedWindowReplacementCount, preparedWindowGenerationsSuperseded: preparedWindowGenerationsSuperseded, preparedLayoutRequests: preparation.requests, preparedLayoutCacheHits: preparation.cacheHits, preparedLayoutCacheMisses: preparation.cacheMisses, preparedLayoutMeasurementsStarted: preparation.measurementsStarted, preparedLayoutMeasurementsCompleted: preparation.measurementsCompleted, preparedLayoutDiscardedResults: preparation.discardedResults, preparedLayoutCancellations: preparation.cancellations, preparedLayoutMaximumConcurrency: preparation.maximumConcurrentMeasurements, visibleLayoutMetricRequests: preparation.visibleRequests, visibleLayoutMetricCacheHits: preparation.visibleCacheHits, visibleLayoutMetricCacheMisses: preparation.visibleCacheMisses, prefetchLayoutMetricRequests: preparation.prefetchRequests, prefetchLayoutMetricCacheHits: preparation.prefetchCacheHits, prefetchLayoutMetricCacheMisses: preparation.prefetchCacheMisses, deterministicHeightRequests: deterministicHeightRequests, deterministicHeightPreparedHits: deterministicHeightPreparedHits, deterministicHeightSynchronousFallbacks: deterministicHeightSynchronousFallbacks, deterministicHeightSynchronousFallbackTotalNanoseconds: deterministicHeightSynchronousFallbackTotalNanoseconds, deterministicHeightSynchronousFallbackMaxNanoseconds: deterministicHeightSynchronousFallbackMaxNanoseconds)
    }
    private func percentile(_ percentile: Double) -> UInt64 {
        let target = UInt64((Double(systemLayoutSizeFittingCalls) * percentile).rounded(.up))
        guard target > 0 else { return 0 }
        var seen: UInt64 = 0
        for (index, count) in durationBuckets.enumerated() {
            seen &+= count
            if seen >= target { return UInt64(1) << index }
        }
        return systemLayoutSizeFittingMaxNanoseconds
    }
}

@MainActor
final class IOSArticleImagePresentationScheduler {
    struct Metrics: Equatable {
        let queued: Int
        let maximumQueued: Int
        let presented: Int
        let discarded: Int
        let averageDelayMilliseconds: Double
        let maximumDelayMilliseconds: Double
    }

    static let shared = IOSArticleImagePresentationScheduler()

    private struct PendingPresentation {
        let enqueuedAt: CFTimeInterval
        let isStillValid: () -> Bool
        let present: () -> Void
    }

    @MainActor
    private final class DisplayLinkTarget: NSObject {
        weak var owner: IOSArticleImagePresentationScheduler?

        @objc func tick(_ displayLink: CADisplayLink) {
            owner?.displayLinkDidFire()
        }
    }

    private var queue: [PendingPresentation] = []
    private var isScrolling = false
    private var displayLink: CADisplayLink?
    private let displayLinkTarget = DisplayLinkTarget()
    private var maximumQueued = 0
    private var presented = 0
    private var discarded = 0
    private var totalDelay: CFTimeInterval = 0
    private var maximumDelay: CFTimeInterval = 0

    private init() {
        displayLinkTarget.owner = self
    }

    func setScrolling(_ scrolling: Bool) {
        guard isScrolling != scrolling else { return }
        isScrolling = scrolling
        if scrolling {
            startDisplayLinkIfNeeded()
        } else {
            stopDisplayLink()
            drainImmediately()
        }
    }

    func enqueue(
        isStillValid: @escaping () -> Bool,
        present: @escaping () -> Void
    ) {
        guard isScrolling else {
            guard isStillValid() else {
                discarded += 1
                return
            }
            present()
            presented += 1
            return
        }

        queue.append(.init(
            enqueuedAt: CACurrentMediaTime(),
            isStillValid: isStillValid,
            present: present
        ))
        maximumQueued = max(maximumQueued, queue.count)
        startDisplayLinkIfNeeded()
    }

    func metrics() -> Metrics {
        .init(
            queued: queue.count,
            maximumQueued: maximumQueued,
            presented: presented,
            discarded: discarded,
            averageDelayMilliseconds: presented > 0 ? (totalDelay / Double(presented)) * 1_000 : 0,
            maximumDelayMilliseconds: maximumDelay * 1_000
        )
    }

    func resetMetrics() {
        maximumQueued = queue.count
        presented = 0
        discarded = 0
        totalDelay = 0
        maximumDelay = 0
    }

    private func displayLinkDidFire() {
        guard isScrolling else { return }
        presentNextValid()
        if queue.isEmpty {
            stopDisplayLink()
        }
    }

    private func presentNextValid() {
        while !queue.isEmpty {
            let pending = queue.removeFirst()
            guard pending.isStillValid() else {
                discarded += 1
                continue
            }
            let delay = CACurrentMediaTime() - pending.enqueuedAt
            pending.present()
            presented += 1
            totalDelay += delay
            maximumDelay = max(maximumDelay, delay)
            return
        }
    }

    private func drainImmediately() {
        while !queue.isEmpty {
            let pending = queue.removeFirst()
            guard pending.isStillValid() else {
                discarded += 1
                continue
            }
            let delay = CACurrentMediaTime() - pending.enqueuedAt
            pending.present()
            presented += 1
            totalDelay += delay
            maximumDelay = max(maximumDelay, delay)
        }
    }

    private func startDisplayLinkIfNeeded() {
        guard isScrolling, !queue.isEmpty, displayLink == nil else { return }
        let link = CADisplayLink(target: displayLinkTarget, selector: #selector(DisplayLinkTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
}
