import CoreGraphics
import XCTest

final class ScrolloverExposureTrackerTests: XCTestCase {
    private let viewport = CGRect(x: 0, y: 0, width: 100, height: 100)
    private let unread: Set<Int64> = [1]

    private func frame(_ y: CGFloat) -> [Int64: CGRect] {
        [1: CGRect(x: 0, y: y, width: 100, height: 100)]
    }

    func testFirstQualifiedItemIsProcessedWhenItCrossesViewport() {
        var tracker = ScrolloverExposureTracker()
        tracker.observe(frames: frame(0), viewport: viewport, unread: unread, now: 0)
        tracker.observe(frames: frame(0), viewport: viewport, unread: unread, now: 0.7)

        XCTAssertEqual(tracker.process(frames: frame(-100), viewport: viewport, unread: unread, now: 0.8, offsetDelta: 50, userInitiated: true), [1])
    }

    func testBriefExposureIsNotProcessed() {
        var tracker = ScrolloverExposureTracker()
        tracker.observe(frames: frame(0), viewport: viewport, unread: unread, now: 0)
        tracker.observe(frames: frame(0), viewport: viewport, unread: unread, now: 0.69)

        XCTAssertEqual(tracker.process(frames: frame(-100), viewport: viewport, unread: unread, now: 0.7, offsetDelta: 50, userInitiated: true), [])
    }

    func testProgrammaticScrollDoesNotProcessButLargeForwardGeometryDoes() {
        var tracker = ScrolloverExposureTracker()
        tracker.observe(frames: frame(0), viewport: viewport, unread: unread, now: 0)
        tracker.observe(frames: frame(0), viewport: viewport, unread: unread, now: 0.7)

        XCTAssertEqual(tracker.process(frames: frame(-100), viewport: viewport, unread: unread, now: 0.8, offsetDelta: 50, userInitiated: false), [])
        tracker.rebase(frames: frame(0), unread: unread)
        tracker.observe(frames: frame(0), viewport: viewport, unread: unread, now: 1)
        tracker.observe(frames: frame(0), viewport: viewport, unread: unread, now: 1.7)
        XCTAssertEqual(tracker.process(frames: frame(-100), viewport: viewport, unread: unread, now: 1.8, offsetDelta: 86, userInitiated: true), [1])
    }

    func testQualificationSurvivesReversalAndMotionBaselineRebases() {
        var tracker = ScrolloverExposureTracker()
        tracker.observe(frames: frame(0), viewport: viewport, unread: unread, now: 0)
        tracker.observe(frames: frame(0), viewport: viewport, unread: unread, now: 0.7)

        XCTAssertEqual(tracker.process(frames: frame(30), viewport: viewport, unread: unread, now: 0.8, offsetDelta: 30, userInitiated: true), [])
        XCTAssertEqual(tracker.process(frames: frame(10), viewport: viewport, unread: unread, now: 0.9, offsetDelta: -20, userInitiated: true), [])
        XCTAssertEqual(tracker.process(frames: frame(-100), viewport: viewport, unread: unread, now: 1, offsetDelta: 20, userInitiated: true), [1])
    }

    func testReverseCrossingDoesNotProcessQualifiedItem() {
        var tracker = ScrolloverExposureTracker()
        tracker.observe(frames: frame(0), viewport: viewport, unread: unread, now: 0)
        tracker.observe(frames: frame(0), viewport: viewport, unread: unread, now: 0.7)

        XCTAssertEqual(tracker.process(frames: frame(-100), viewport: viewport, unread: unread, now: 0.8, offsetDelta: -50, userInitiated: true), [])
    }

    func testFastForwardProcessesEachQualifiedCrossingOnlyOnce() {
        let ids: Set<Int64> = [1, 2]
        var tracker = ScrolloverExposureTracker()
        tracker.observe(frames: [1: frame(0)[1]!, 2: frame(0)[1]!], viewport: viewport, unread: ids, now: 0)
        tracker.observe(frames: [1: frame(0)[1]!, 2: frame(0)[1]!], viewport: viewport, unread: ids, now: 0.7)

        XCTAssertEqual(tracker.process(frames: [1: frame(-100)[1]!, 2: frame(-200)[1]!], viewport: viewport, unread: ids, now: 0.8, offsetDelta: 300, userInitiated: true), [1, 2])
        XCTAssertEqual(tracker.process(frames: [1: frame(-140)[1]!, 2: frame(-240)[1]!], viewport: viewport, unread: ids, now: 0.9, offsetDelta: 40, userInitiated: true), [])
    }

    func testLaterQualifiedItemStillProcessesAfterRejectedScroll() {
        var tracker = ScrolloverExposureTracker()
        tracker.observe(frames: frame(0), viewport: viewport, unread: unread, now: 0)
        tracker.observe(frames: frame(0), viewport: viewport, unread: unread, now: 0.7)
        XCTAssertEqual(tracker.process(frames: frame(-100), viewport: viewport, unread: unread, now: 0.8, offsetDelta: 86, userInitiated: true), [1])

        tracker.rebase(frames: frame(0), unread: unread)
        tracker.observe(frames: frame(0), viewport: viewport, unread: unread, now: 1)
        tracker.observe(frames: frame(0), viewport: viewport, unread: unread, now: 1.7)
        XCTAssertEqual(tracker.process(frames: frame(-100), viewport: viewport, unread: unread, now: 1.8, offsetDelta: 50, userInitiated: true), [])
    }

    func testUndoBatchAccumulatesMultipleFlushesInOneScroll() {
        var batch = ScrolloverUndoBatch()
        batch.beginScroll()
        XCTAssertEqual(batch.append([1]), [1])
        XCTAssertFalse(batch.showsUndo)
        XCTAssertEqual(batch.append([2]), [1, 2])
        XCTAssertTrue(batch.showsUndo)
    }

    func testUndoBatchDeduplicatesFlushes() {
        var batch = ScrolloverUndoBatch()
        batch.beginScroll()
        XCTAssertEqual(batch.append([1, 2]), [1, 2])
        XCTAssertEqual(batch.append([2, 3]), [1, 2, 3])
        XCTAssertTrue(batch.showsUndo)
    }

    func testNewScrollReplacesUndoBatchOnlyAfterItMarksArticles() {
        var batch = ScrolloverUndoBatch()
        batch.beginScroll()
        XCTAssertEqual(batch.append([1, 2]), [1, 2])
        batch.beginScroll()
        XCTAssertEqual(batch.articleIDs, [1, 2])
        XCTAssertEqual(batch.append([3]), [3])
        XCTAssertFalse(batch.showsUndo)
    }

    func testFeedIconRequestStateCompletesEveryTerminalOutcome() {
        var requests = FeedIconRequestState()
        XCTAssertTrue(requests.begin("1-normal", cached: false))
        XCTAssertFalse(requests.begin("1-normal", cached: false))
        requests.complete("1-normal")
        XCTAssertFalse(requests.isInFlight("1-normal"))

        XCTAssertTrue(requests.begin("1-dark", cached: false))
        requests.complete("1-dark")
        XCTAssertTrue(requests.begin("1-dark", cached: false))
        XCTAssertFalse(requests.begin("1-normal", cached: true))
    }

    func testArticleThumbnailRequestStateDoesNotSuppressTerminalOutcomes() {
        var requests = ArticleThumbnailRequestState()
        XCTAssertTrue(requests.begin("1-image", cached: false))
        XCTAssertFalse(requests.begin("1-image", cached: false))
        requests.complete("1-image")
        XCTAssertFalse(requests.isInFlight("1-image"))

        XCTAssertTrue(requests.begin("1-image", cached: false))
        requests.complete("1-image")
        XCTAssertFalse(requests.begin("1-image", cached: true))
    }

    func testManualSyncAlwaysReplacesAndResetsSnapshot() {
        XCTAssertEqual(SnapshotRefreshPolicy.action(manual: true, dataChanged: false, hasMeaningfullyInteracted: true), .replace)
        XCTAssertEqual(SnapshotRefreshPolicy.action(manual: true, dataChanged: true, hasMeaningfullyInteracted: true), .replace)
    }

    func testAutomaticUntouchedSnapshotReplacesWhenDataChanges() {
        XCTAssertEqual(SnapshotRefreshPolicy.action(manual: false, dataChanged: true, hasMeaningfullyInteracted: false), .replace)
        XCTAssertEqual(SnapshotRefreshPolicy.action(manual: false, dataChanged: true, hasMeaningfullyInteracted: true), .signalNewData)
    }

    func testAutomaticInteractedSnapshotSignalsNewDataWithoutReplacement() {
        XCTAssertEqual(SnapshotRefreshPolicy.action(manual: false, dataChanged: true, hasMeaningfullyInteracted: true), .signalNewData)
    }

    func testUnchangedAutomaticSyncAndLocalMutationDoNotReplaceSnapshot() {
        XCTAssertEqual(SnapshotRefreshPolicy.action(manual: false, dataChanged: false, hasMeaningfullyInteracted: false), .preserve)
        XCTAssertNotEqual(SnapshotRefreshPolicy.Action.preserve, .replace)
    }

    func testPendingNewDataAccumulatesAcrossAutomaticSyncs() {
        var pending = PendingNewData()
        pending.accumulate([(feedID: 10, count: 3)])
        pending.accumulate([(feedID: 10, count: 2), (feedID: 20, count: 4)])

        XCTAssertEqual(pending.byFeed, [10: 5, 20: 4])
        XCTAssertTrue(pending.hasPending)
    }

    func testPendingNewDataAcknowledgesOnlyTheAdoptedScope() {
        var pending = PendingNewData()
        pending.accumulate([(feedID: 10, count: 5), (feedID: 20, count: 4), (feedID: 30, count: 2)])

        pending.adoptFeed(10)
        XCTAssertEqual(pending.byFeed, [20: 4, 30: 2])
        pending.adoptFeeds(in: [20])
        XCTAssertEqual(pending.byFeed, [30: 2])
        pending.adoptAll()
        XCTAssertFalse(pending.hasPending)
    }

    func testPendingNewDataRemovesFeedsAbsentFromNavigation() {
        var pending = PendingNewData()
        pending.accumulate([(feedID: 10, count: 1), (feedID: 20, count: 1)])
        pending.removeAbsentFeeds([20])

        XCTAssertEqual(pending.byFeed, [20: 1])
    }

    func testCategoryPendingNewDataAggregatesCurrentFeedChildren() {
        let pending: [Int64: Int] = [10: 2, 20: 5, 30: 0, 40: 4]

        XCTAssertEqual(PendingNewDataAggregation.count(feedIDs: [], pendingByFeed: pending), 0)
        XCTAssertEqual(PendingNewDataAggregation.count(feedIDs: [10], pendingByFeed: pending), 2)
        XCTAssertEqual(PendingNewDataAggregation.count(feedIDs: [10, 20, 30], pendingByFeed: pending), 7)
        XCTAssertEqual(PendingNewDataAggregation.count(feedIDs: [10, 20], pendingByFeed: [10: 0, 20: 5]), 5)
        XCTAssertEqual(PendingNewDataAggregation.count(feedIDs: [10, 20], pendingByFeed: [:]), 0)
        XCTAssertEqual(PendingNewDataAggregation.count(feedIDs: [10, 20], pendingByFeed: pending), 7)
        XCTAssertEqual(PendingNewDataAggregation.count(feedIDs: [40], pendingByFeed: pending), 4)
    }

    func testStatusItemTitleKeepsUnreadAndPendingNewDataIndependent() {
        XCTAssertEqual(StatusItemPresentation.title(unreadTotal: 127, hasPendingNewData: false), "127")
        XCTAssertEqual(StatusItemPresentation.title(unreadTotal: 127, hasPendingNewData: true), "• 127")
        XCTAssertEqual(StatusItemPresentation.title(unreadTotal: 0, hasPendingNewData: false), "")
        XCTAssertEqual(StatusItemPresentation.title(unreadTotal: 0, hasPendingNewData: true), "•")
        XCTAssertEqual(StatusItemPresentation.title(unreadTotal: 1_200, hasPendingNewData: true), "• 999+")
    }

}
