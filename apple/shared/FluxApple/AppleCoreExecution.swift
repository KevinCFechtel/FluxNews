import Foundation

/// Bounded Apple worker lanes for synchronous UniFFI/Core operations. Swift
/// Concurrency owns operation lifetime; an OperationQueue owns the synchronous
/// call so it never occupies a cooperative executor thread.
final class AppleCoreExecution: @unchecked Sendable {
    static let responsiveConcurrencyLimit = 2
    static let blockingConcurrencyLimit = 2
    static let shared = AppleCoreExecution()

    private let responsiveQueue: OperationQueue
    private let blockingQueue: OperationQueue

    init(
        responsiveConcurrency: Int = AppleCoreExecution.responsiveConcurrencyLimit,
        blockingConcurrency: Int = AppleCoreExecution.blockingConcurrencyLimit
    ) {
        precondition(responsiveConcurrency > 0)
        precondition(blockingConcurrency > 0)
        responsiveQueue = Self.makeQueue(
            name: "dev.kevincfechtel.flux.core.responsive",
            concurrency: responsiveConcurrency,
            qualityOfService: .userInitiated
        )
        blockingQueue = Self.makeQueue(
            name: "dev.kevincfechtel.flux.core.blocking",
            concurrency: blockingConcurrency,
            qualityOfService: .utility
        )
    }

    func responsive<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await execute(on: responsiveQueue, operation: operation)
    }

    func blocking<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await execute(on: blockingQueue, operation: operation)
    }

    /// Runs blocking Core work with a cooperative cancellation signal for work
    /// that has already started. Queued cancellation still prevents the
    /// operation from starting. Once started, cancellation invokes onCancel
    /// but keeps the worker occupied until the synchronous operation returns.
    func blockingCancellable<Value: Sendable>(
        onCancel: @escaping @Sendable () -> Void,
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await execute(
            on: blockingQueue,
            onRunningCancel: onCancel,
            operation: operation
        )
    }

    /// Convenience for presentation code that already owns Result-based error
    /// routing. The original Core error is preserved unchanged.
    func responsiveResult<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async -> Result<Value, Error> {
        do { return .success(try await responsive(operation)) }
        catch { return .failure(error) }
    }

    /// Convenience for presentation code that already owns Result-based error
    /// routing. The original Core error is preserved unchanged.
    func blockingResult<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async -> Result<Value, Error> {
        do { return .success(try await blocking(operation)) }
        catch { return .failure(error) }
    }

    /// Result-based form of blockingCancellable. Running cancellation signals
    /// the cooperative Core handle and returns only after the synchronous
    /// operation itself has finished.
    func blockingCancellableResult<Value: Sendable>(
        onCancel: @escaping @Sendable () -> Void,
        _ operation: @escaping @Sendable () throws -> Value
    ) async -> Result<Value, Error> {
        do {
            return .success(
                try await blockingCancellable(onCancel: onCancel, operation)
            )
        } catch {
            return .failure(error)
        }
    }

    private func execute<Value: Sendable>(
        on queue: OperationQueue,
        onRunningCancel: (@Sendable () -> Void)? = nil,
        operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        let work = AppleCoreExecutionWork<Value>()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                guard work.install(continuation) else { return }
                queue.addOperation { work.run(operation) }
            }
        }, onCancel: {
            work.cancel(onRunningCancel: onRunningCancel)
        })
    }

    private static func makeQueue(
        name: String,
        concurrency: Int,
        qualityOfService: QualityOfService
    ) -> OperationQueue {
        let queue = OperationQueue()
        queue.name = name
        queue.qualityOfService = qualityOfService
        queue.maxConcurrentOperationCount = concurrency
        return queue
    }
}

private final class AppleCoreExecutionWork<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var completion: Result<Value, Error>?
    private var started = false
    private var runningCancellationSignalled = false

    /// Returns false when cancellation won the race before continuation setup.
    func install(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        lock.lock()
        if let completion {
            lock.unlock()
            continuation.resume(with: completion)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func cancel(onRunningCancel: (@Sendable () -> Void)?) {
        lock.lock()
        guard completion == nil else {
            lock.unlock()
            return
        }
        if !started {
            let result: Result<Value, Error> = .failure(CancellationError())
            let continuation = finishLocked(result)
            lock.unlock()
            continuation?.resume(with: result)
            return
        }
        guard let onRunningCancel, !runningCancellationSignalled else {
            lock.unlock()
            return
        }
        runningCancellationSignalled = true
        lock.unlock()
        onRunningCancel()
    }

    func run(_ operation: @escaping @Sendable () throws -> Value) {
        lock.lock()
        guard completion == nil else {
            lock.unlock()
            return
        }
        started = true
        lock.unlock()

        finish(Result(catching: operation))
    }

    private func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard completion == nil else {
            lock.unlock()
            return
        }
        let continuation = finishLocked(result)
        lock.unlock()
        continuation?.resume(with: result)
    }

    private func finishLocked(_ result: Result<Value, Error>) -> CheckedContinuation<Value, Error>? {
        completion = result
        guard let continuation else { return nil }
        self.continuation = nil
        return continuation
    }
}
