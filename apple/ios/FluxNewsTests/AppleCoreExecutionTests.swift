import Foundation
import XCTest
@testable import FluxNews

final class AppleCoreExecutionTests: XCTestCase {
    @MainActor
    func testResponsiveWorkRunsOffMainActorThread() async throws {
        let execution = AppleCoreExecution(responsiveConcurrency: 1, blockingConcurrency: 1)

        XCTAssertTrue(Thread.isMainThread)
        let operationWasOnMainThread = try await execution.responsive { Thread.isMainThread }

        XCTAssertFalse(operationWasOnMainThread)
    }

    func testResponsiveWorkIsBounded() async throws {
        let execution = AppleCoreExecution(responsiveConcurrency: 2, blockingConcurrency: 1)
        let gate = ExecutionGate()
        let tasks = (0 ..< 4).map { _ in
            Task { try await execution.responsive { gate.enter(); return 1 } }
        }

        try await gate.waitForStarts(2)
        XCTAssertEqual(gate.startCount, 2)
        gate.release(2)
        try await gate.waitForStarts(4)
        XCTAssertEqual(gate.maximumConcurrentOperations, 2)
        gate.release(2)
        for task in tasks { _ = try await task.value }
    }

    func testBlockingWorkIsBounded() async throws {
        let execution = AppleCoreExecution(responsiveConcurrency: 1, blockingConcurrency: 2)
        let gate = ExecutionGate()
        let tasks = (0 ..< 4).map { _ in
            Task { try await execution.blocking { gate.enter(); return 1 } }
        }

        try await gate.waitForStarts(2)
        XCTAssertEqual(gate.startCount, 2)
        gate.release(2)
        try await gate.waitForStarts(4)
        XCTAssertEqual(gate.maximumConcurrentOperations, 2)
        gate.release(2)
        for task in tasks { _ = try await task.value }
    }

    func testBlockingWorkDoesNotBlockResponsiveWork() async throws {
        let execution = AppleCoreExecution(responsiveConcurrency: 1, blockingConcurrency: 1)
        let blockingGate = ExecutionGate()
        let responsiveStarted = LockedFlag()
        let blockingTask = Task { try await execution.blocking { blockingGate.enter(); return 1 } }

        try await blockingGate.waitForStarts(1)
        let responsiveTask = Task {
            try await execution.responsive {
                responsiveStarted.set()
                return 2
            }
        }

        try await waitUntil(timeout: 2) { responsiveStarted.value }
        blockingGate.release(1)
        let blockingValue = try await blockingTask.value
        let responsiveValue = try await responsiveTask.value
        XCTAssertEqual(blockingValue, 1)
        XCTAssertEqual(responsiveValue, 2)
    }

    func testValuesAndErrorsPropagateUnchanged() async throws {
        let execution = AppleCoreExecution(responsiveConcurrency: 1, blockingConcurrency: 1)

        let value = try await execution.responsive { 42 }
        XCTAssertEqual(value, 42)
        do {
            _ = try await execution.blocking { throw ExpectedError.expected }
            XCTFail("Expected Core error")
        } catch let error as ExpectedError {
            XCTAssertEqual(error, .expected)
        }
    }

    func testCancelledQueuedWorkDoesNotRunAndDoesNotLeakCapacity() async throws {
        let execution = AppleCoreExecution(responsiveConcurrency: 1, blockingConcurrency: 1)
        let gate = ExecutionGate()
        let first = Task { try await execution.blocking { gate.enter(); return 1 } }
        try await gate.waitForStarts(1)

        let ranCancelledOperation = LockedFlag()
        let cancelled = Task {
            try await execution.blocking {
                ranCancelledOperation.set()
                return 2
            }
        }
        cancelled.cancel()
        gate.release(1)

        let firstValue = try await first.value
        XCTAssertEqual(firstValue, 1)
        do {
            _ = try await cancelled.value
            XCTFail("Expected queued work cancellation")
        } catch is CancellationError {
            // Expected: cancellation prevented the queued Core closure from starting.
        }
        XCTAssertFalse(ranCancelledOperation.value)
        let followUp = try await execution.blocking { 3 }
        XCTAssertEqual(followUp, 3)
    }

    func testRunningCooperativeCancellationSignalsAndKeepsWorkerOccupied() async throws {
        let execution = AppleCoreExecution(responsiveConcurrency: 1, blockingConcurrency: 1)
        let gate = ExecutionGate()
        let cancellationSignalled = LockedFlag()
        let operationFinished = LockedFlag()
        let followUpStarted = LockedFlag()

        let running = Task {
            let value = try await execution.blockingCancellable(
                onCancel: { cancellationSignalled.set() }
            ) {
                gate.enter()
                return 7
            }
            operationFinished.set()
            return value
        }

        try await gate.waitForStarts(1)
        running.cancel()
        try await waitUntil(timeout: 2) { cancellationSignalled.value }

        let followUp = Task {
            try await execution.blocking {
                followUpStarted.set()
                return 8
            }
        }

        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(operationFinished.value)
        XCTAssertFalse(followUpStarted.value)

        gate.release(1)
        let runningValue = try await running.value
        let followUpValue = try await followUp.value
        XCTAssertEqual(runningValue, 7)
        XCTAssertEqual(followUpValue, 8)
        XCTAssertTrue(operationFinished.value)
        XCTAssertTrue(followUpStarted.value)
    }

    func testQueuedCooperativeCancellationDoesNotSignalRunningHook() async throws {
        let execution = AppleCoreExecution(responsiveConcurrency: 1, blockingConcurrency: 1)
        let gate = ExecutionGate()
        let first = Task { try await execution.blocking { gate.enter(); return 1 } }
        try await gate.waitForStarts(1)

        let cancellationSignalled = LockedFlag()
        let ranCancelledOperation = LockedFlag()
        let cancelled = Task {
            try await execution.blockingCancellable(
                onCancel: { cancellationSignalled.set() }
            ) {
                ranCancelledOperation.set()
                return 2
            }
        }
        cancelled.cancel()
        gate.release(1)

        let firstValue = try await first.value
        XCTAssertEqual(firstValue, 1)
        do {
            _ = try await cancelled.value
            XCTFail("Expected queued work cancellation")
        } catch is CancellationError {
            // Expected: queued work never became a running Core operation.
        }
        XCTAssertFalse(cancellationSignalled.value)
        XCTAssertFalse(ranCancelledOperation.value)
    }

    func testFailuresAndCancellationsLeaveBothLanesUsable() async throws {
        let execution = AppleCoreExecution(responsiveConcurrency: 1, blockingConcurrency: 1)

        for _ in 0 ..< 3 {
            do {
                _ = try await execution.responsive { throw ExpectedError.expected }
                XCTFail("Expected Core error")
            } catch let error as ExpectedError {
                XCTAssertEqual(error, .expected)
            }
        }

        let gate = ExecutionGate()
        let first = Task { try await execution.blocking { gate.enter(); return 1 } }
        try await gate.waitForStarts(1)
        let cancelled = Task { try await execution.blocking { 2 } }
        cancelled.cancel()
        gate.release(1)
        _ = try await first.value
        _ = try? await cancelled.value

        let responsiveValue = try await execution.responsive { 4 }
        let blockingValue = try await execution.blocking { 5 }
        XCTAssertEqual(responsiveValue, 4)
        XCTAssertEqual(blockingValue, 5)
    }

    func testSynchronousIOSCoreCallSitesUseTheCentralExecutionBoundary() throws {
        let iosDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sharedDirectory = iosDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("shared/FluxApple")
        let sources = try [
            iosDirectory.appendingPathComponent("FluxNews/NewsreaderStore.swift"),
            iosDirectory.appendingPathComponent("FluxNews/IOSSearchStore.swift"),
            iosDirectory.appendingPathComponent("FluxNews/CoreBootstrapper.swift"),
            sharedDirectory.appendingPathComponent("AppleCoreSessionExecutionCoordinator.swift")
        ].map { try String(contentsOf: $0, encoding: .utf8) }

        XCTAssertTrue(sources[0].contains("Task.detached(priority: .userInitiated)")) // CPU-only feed-icon ImageIO preparation.
        XCTAssertFalse(sources[1].contains("Task.detached"))
        XCTAssertFalse(sources[2].contains("Task.detached"))
        XCTAssertFalse(sources[3].contains("Task.detached"))

        XCTAssertTrue(sources[0].contains("sessionCoordinator.responsiveResult("))
        XCTAssertTrue(sources[0].contains("sessionCoordinator.blockingResult("))
        XCTAssertTrue(sources[0].contains("beginExecution("))
        XCTAssertTrue(sources[0].contains("blockingCancellableResult("))
        XCTAssertTrue(sources[0].contains("core.syncCancellable(reason: .manual, cancellation: cancellation)"))

        XCTAssertTrue(sources[1].contains("sessionCoordinator.blockingResult("))
        XCTAssertFalse(sources[1].contains("AppleCoreExecution.shared"))

        XCTAssertTrue(sources[2].contains("coreSessionExecutionCoordinator.quiesce()"))
        XCTAssertTrue(sources[2].contains("AppleCoreExecution.shared.blockingResult"))
        XCTAssertTrue(sources[2].contains("AppleCoreExecution.shared.responsive"))

        XCTAssertTrue(sources[3].contains("AppleCoreExecution.shared.responsiveResult"))
        XCTAssertTrue(sources[3].contains("AppleCoreExecution.shared.blockingResult"))
        XCTAssertTrue(sources[3].contains("AppleCoreExecution.shared.blockingCancellableResult"))
    }
}

private enum ExpectedError: Error, Equatable, Sendable {
    case expected
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    func set() {
        lock.lock()
        storage = true
        lock.unlock()
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class ExecutionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var activeOperations = 0
    private var starts = 0
    private var releasedOperations = 0
    private var maximumActiveOperations = 0

    func enter() {
        lock.lock()
        starts += 1
        activeOperations += 1
        maximumActiveOperations = max(maximumActiveOperations, activeOperations)
        lock.unlock()

        while true {
            lock.lock()
            if releasedOperations > 0 {
                releasedOperations -= 1
                activeOperations -= 1
                lock.unlock()
                return
            }
            lock.unlock()
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    func waitForStarts(_ count: Int, timeout: TimeInterval = 10) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while startCount < count {
            guard ContinuousClock.now < deadline else {
                XCTFail("ExecutionGate timeout: observed \(startCount) starts; expected \(count) within \(timeout)s")
                throw GateError.timedOut
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func release(_ count: Int) {
        lock.lock()
        releasedOperations += count
        lock.unlock()
    }

    var startCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return starts
    }

    var maximumConcurrentOperations: Int {
        lock.lock()
        defer { lock.unlock() }
        return maximumActiveOperations
    }
}

private func waitUntil(
    timeout: TimeInterval,
    condition: @escaping @Sendable () -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
    while !condition() {
        guard ContinuousClock.now < deadline else { throw GateError.timedOut }
        try await Task.sleep(for: .milliseconds(1))
    }
}

private enum GateError: Error {
    case timedOut
}
