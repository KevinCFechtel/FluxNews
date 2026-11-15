import UIKit

enum IOSArticleScrollDirection: Equatable {
    case forward
    case backward
}

struct IOSScrolloverBatch: Equatable {
    let articleIDs: [Int64]
}

struct IOSUIKitScrolloverGeometrySample: Equatable {
    let contentOffsetY: CGFloat
    let effectiveTop: CGFloat
    let effectiveBottom: CGFloat
    let contentHeight: CGFloat
    let rowFrames: [Int64: CGRect]
    let layoutGeneration: UInt64
}

struct IOSUIKitScrolloverGeometryResult: Equatable {
    let direction: IOSArticleScrollDirection?
    let batch: IOSScrolloverBatch
}

/// Resolved frames captured from real table-view cells. This is deliberately
/// smaller than the tracker's crossing window: it bridges lifecycle callback order
/// without becoming a second geometry cache for the complete collection.
struct IOSUIKitResolvedScrolloverFrameStore {
    static let capacity = 96
    private var framesByID: [Int64: CGRect] = [:]
    private var slotByID: [Int64: Int] = [:]
    private var slots = Array<Int64?>(repeating: nil, count: capacity)
    private var nextSlot = 0

    var frames: [Int64: CGRect] { framesByID }
    var count: Int { framesByID.count }

    mutating func record(articleID: Int64, frame: CGRect) {
        framesByID[articleID] = frame
        guard slotByID[articleID] == nil else { return }
        if let evictedID = slots[nextSlot] {
            framesByID[evictedID] = nil
            slotByID[evictedID] = nil
        }
        slots[nextSlot] = articleID
        slotByID[articleID] = nextSlot
        nextSlot = (nextSlot + 1) % Self.capacity
    }

    mutating func removeAll() {
        framesByID.removeAll(keepingCapacity: true)
        slotByID.removeAll(keepingCapacity: true)
        slots = Array(repeating: nil, count: Self.capacity)
        nextSlot = 0
    }
}

/// Non-observable, bounded geometry detector owned by the UIKit Timeline.
/// It only emits IDs that were actually observed in the viewport during a user-driven
/// interaction and then crossed the effective upper viewport boundary while moving forward.
final class IOSUIKitScrolloverGeometryTracker {
    private static let bottomTolerance: CGFloat = 0.5

    /// The previous scalar geometry and a private bounded frame copy. Keeping this
    /// separate from the source sample is intentional: retaining `rowFrames`
    /// directly would share the frame store's dictionary buffer and force a
    /// copy-on-write of that bounded store on its next mutation.
    private struct PreviousGeometry {
        let contentOffsetY: CGFloat
        let effectiveTop: CGFloat
        let effectiveBottom: CGFloat
        let layoutGeneration: UInt64

        init(_ sample: IOSUIKitScrolloverGeometrySample) {
            contentOffsetY = sample.contentOffsetY
            effectiveTop = sample.effectiveTop
            effectiveBottom = sample.effectiveBottom
            layoutGeneration = sample.layoutGeneration
        }
    }

    private var positions: [Int64: Int] = [:]
    private var nextPosition = 0
    private var emittedIDs = Set<Int64>()
    private var observedVisibleIDs = Set<Int64>()
    private var previousGeometry: PreviousGeometry?
    private var previousFrames: [Int64: CGRect] = [:]
    private var phase: IOSScrolloverPresentationPhase = .idle
    private var wasAtBottom = false

    var retainedPreviousFrameCount: Int { previousFrames.count }

    func updateSnapshot(_ ids: [Int64]) {
        positions = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
        nextPosition = ids.count
        emittedIDs.removeAll()
        observedVisibleIDs.removeAll()
        invalidateGeometry()
    }

    func appendSnapshot(_ ids: [Int64]) {
        guard !ids.isEmpty else { return }
        for id in ids where positions[id] == nil {
            positions[id] = nextPosition
            nextPosition &+= 1
        }
    }

    func removeSnapshot(_ ids: some Sequence<Int64>) {
        for id in ids {
            positions[id] = nil
            emittedIDs.remove(id)
            observedVisibleIDs.remove(id)
        }
        clearPreviousGeometry()
        wasAtBottom = false
    }

    func setPhase(_ newPhase: IOSScrolloverPresentationPhase) {
        phase = newPhase
        if newPhase == .idle {
            observedVisibleIDs.removeAll(keepingCapacity: true)
            invalidateGeometry()
        }
    }

    func invalidateGeometry() {
        clearPreviousGeometry()
        wasAtBottom = false
    }

    func rearm(_ ids: some Sequence<Int64>) {
        for id in ids { emittedIDs.remove(id) }
    }

    func receive(_ sample: IOSUIKitScrolloverGeometrySample, enabled: Bool) -> IOSUIKitScrolloverGeometryResult {
        guard phase.isScrolling else {
            storePrevious(sample)
            wasAtBottom = isAtBottom(sample)
            return .init(direction: nil, batch: .init(articleIDs: []))
        }

        guard let previous = previousGeometry,
              previous.layoutGeneration == sample.layoutGeneration else {
            rebaseline(with: sample, enabled: enabled)
            return .init(direction: nil, batch: .init(articleIDs: []))
        }

        guard !hasMaterialLayoutChange(from: previousFrames, to: sample) else {
            rebaseline(with: sample, enabled: enabled)
            return .init(direction: nil, batch: .init(articleIDs: []))
        }

        let delta = sample.contentOffsetY - previous.contentOffsetY
        let direction: IOSArticleScrollDirection?
        if delta > 0 { direction = .forward }
        else if delta < 0 { direction = .backward }
        else { direction = nil }

        var candidates: [Int64] = []
        if enabled, direction == .forward {
            for id in observedVisibleIDs where !emittedIDs.contains(id) {
                guard let frame = sample.rowFrames[id] ?? previousFrames[id] else { continue }
                if previous.effectiveTop < frame.maxY,
                   sample.effectiveTop >= frame.maxY {
                    candidates.append(id)
                }
            }

            let atBottom = isAtBottom(sample)
            if !wasAtBottom, atBottom {
                for (id, frame) in sample.rowFrames where observedVisibleIDs.contains(id) && isVisible(frame, in: sample) {
                    if !candidates.contains(id) { candidates.append(id) }
                }
            }
            wasAtBottom = atBottom
        } else {
            wasAtBottom = isAtBottom(sample)
        }

        if enabled {
            for (id, frame) in sample.rowFrames where isVisible(frame, in: sample) {
                observedVisibleIDs.insert(id)
            }
        } else {
            observedVisibleIDs.removeAll(keepingCapacity: true)
        }
        pruneObservedIDs(current: sample.rowFrames, previous: previousFrames)
        storePrevious(sample)

        let ids = candidates
            .filter { emittedIDs.insert($0).inserted }
            .sorted { positions[$0, default: .max] < positions[$1, default: .max] }
        return .init(direction: direction, batch: .init(articleIDs: ids))
    }

    private func rebaseline(with sample: IOSUIKitScrolloverGeometrySample, enabled: Bool) {
        observedVisibleIDs.removeAll(keepingCapacity: true)
        if enabled {
            for (id, frame) in sample.rowFrames where isVisible(frame, in: sample) {
                observedVisibleIDs.insert(id)
            }
        }
        storePrevious(sample)
        wasAtBottom = isAtBottom(sample)
    }

    private func isVisible(_ frame: CGRect, in sample: IOSUIKitScrolloverGeometrySample) -> Bool {
        frame.maxY > sample.effectiveTop && frame.minY < sample.effectiveBottom
    }

    private func isAtBottom(_ sample: IOSUIKitScrolloverGeometrySample) -> Bool {
        sample.effectiveBottom >= sample.contentHeight - Self.bottomTolerance
    }

    private func hasMaterialLayoutChange(
        from previous: [Int64: CGRect],
        to sample: IOSUIKitScrolloverGeometrySample
    ) -> Bool {
        for (id, oldFrame) in previous {
            guard let newFrame = sample.rowFrames[id], oldFrame != newFrame else { continue }
            return true
        }
        return false
    }

    private func pruneObservedIDs(current: [Int64: CGRect], previous: [Int64: CGRect]) {
        var staleIDs: [Int64]?
        for id in observedVisibleIDs where current[id] == nil && previous[id] == nil {
            if staleIDs == nil { staleIDs = [id] }
            else { staleIDs!.append(id) }
        }
        if let staleIDs {
            for id in staleIDs { observedVisibleIDs.remove(id) }
        }
    }

    private func storePrevious(_ sample: IOSUIKitScrolloverGeometrySample) {
        previousGeometry = .init(sample)
        previousFrames.removeAll(keepingCapacity: true)
        previousFrames.reserveCapacity(min(sample.rowFrames.count, IOSUIKitResolvedScrolloverFrameStore.capacity))
        for (id, frame) in sample.rowFrames.prefix(IOSUIKitResolvedScrolloverFrameStore.capacity) {
            previousFrames[id] = frame
        }
    }

    private func clearPreviousGeometry() {
        previousGeometry = nil
        previousFrames.removeAll(keepingCapacity: true)
    }
}
