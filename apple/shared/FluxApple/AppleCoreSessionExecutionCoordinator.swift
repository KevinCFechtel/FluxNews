import Foundation

/// App-wide admission gate for synchronous Core work that belongs to the
/// currently active account/Core session.
///
/// The coordinator does not own presentation and does not schedule work itself.
/// It only prevents new work from entering while a Core is being replaced,
/// tracks already-admitted work until the underlying synchronous call returns,
/// and forwards cooperative cancellation to operations that provide it.
@MainActor
final class AppleCoreSessionExecutionCoordinator {
    struct Lease: Hashable {
        fileprivate let sessionGeneration: UInt64
        fileprivate let executionID: UInt64
    }

    private struct ActiveExecution {
        let cancellation: (@Sendable () -> Void)?
    }

    private(set) var sessionGeneration: UInt64 = 0
    private(set) var isQuiescing = true
    private(set) var activeExecutionCount = 0

    private var activeCoreIdentifier: ObjectIdentifier?
    private var nextExecutionID: UInt64 = 0
    private var activeExecutions: [UInt64: ActiveExecution] = [:]
    private var quiescenceWaiters: [CheckedContinuation<Void, Never>] = []

    /// Makes `core` the only Core admitted by this coordinator.
    ///
    /// Re-activating the already-active Core is a no-op. Switching to a
    /// different Core is only legal after all work from the prior session has
    /// quiesced.
    func activate(_ core: Flux) {
        let identifier = ObjectIdentifier(core)
        if activeCoreIdentifier == identifier, !isQuiescing {
            return
        }

        precondition(
            activeExecutions.isEmpty,
            "Core session replacement requires all admitted Core work to quiesce first."
        )
        sessionGeneration &+= 1
        activeCoreIdentifier = identifier
        isQuiescing = false
    }

    /// Convenience for standalone presentation-store tests. In the app the
    /// bootstrapper activates the shared coordinator before publishing the Core.
    func ensureActive(_ core: Flux) {
        let identifier = ObjectIdentifier(core)
        if activeCoreIdentifier == identifier {
            if isQuiescing, activeExecutions.isEmpty {
                isQuiescing = false
            }
            return
        }
        activate(core)
    }

    /// Re-opens admission for the same Core when replacement failed and the old
    /// session remains authoritative.
    func resume(_ core: Flux) {
        guard activeCoreIdentifier == ObjectIdentifier(core) else { return }
        precondition(
            activeExecutions.isEmpty,
            "A quiesced Core session can resume only after all admitted work has returned."
        )
        isQuiescing = false
    }

    /// Blocks new work, requests cooperative cancellation where available, and
    /// waits until every admitted synchronous Core execution has actually
    /// returned from AppleCoreExecution.
    func quiesce() async {
        isQuiescing = true
        let cancellations = activeExecutions.values.compactMap(\.cancellation)
        cancellations.forEach { $0() }

        guard !activeExecutions.isEmpty else { return }
        await withCheckedContinuation { continuation in
            quiescenceWaiters.append(continuation)
        }
    }

    /// Clears the session after successful replacement/removal teardown.
    func deactivate() {
        precondition(
            activeExecutions.isEmpty,
            "Core session deactivation requires all admitted Core work to quiesce first."
        )
        sessionGeneration &+= 1
        activeCoreIdentifier = nil
        isQuiescing = true
    }

    /// Admits one execution against the current Core. A nil lease means the
    /// session is quiescing, detached, or the caller captured a stale Core.
    func beginExecution(
        for core: Flux,
        cancellation: (@Sendable () -> Void)? = nil
    ) -> Lease? {
        guard !isQuiescing,
              activeCoreIdentifier == ObjectIdentifier(core) else { return nil }

        nextExecutionID &+= 1
        let executionID = nextExecutionID
        activeExecutions[executionID] = ActiveExecution(cancellation: cancellation)
        activeExecutionCount = activeExecutions.count
        return Lease(
            sessionGeneration: sessionGeneration,
            executionID: executionID
        )
    }

    /// Runs a responsive/local synchronous Core operation while holding a
    /// session lease. Nil means admission was rejected because the caller
    /// captured a stale Core or replacement quiescence has begun.
    func responsiveResult<Value: Sendable>(
        for core: Flux,
        _ operation: @escaping @Sendable () throws -> Value
    ) async -> Result<Value, Error>? {
        guard let lease = beginExecution(for: core) else { return nil }
        let result = await AppleCoreExecution.shared.responsiveResult(operation)
        finish(lease)
        return result
    }

    /// Runs blocking/remote synchronous Core work while holding a session lease.
    func blockingResult<Value: Sendable>(
        for core: Flux,
        _ operation: @escaping @Sendable () throws -> Value
    ) async -> Result<Value, Error>? {
        guard let lease = beginExecution(for: core) else { return nil }
        let result = await AppleCoreExecution.shared.blockingResult(operation)
        finish(lease)
        return result
    }

    /// Cancellable blocking form used by run-scoped Core operations such as
    /// Manual Sync and, later, BGTask-owned Background Sync. The session keeps
    /// the lease until the synchronous worker really returns.
    func blockingCancellableResult<Value: Sendable>(
        for core: Flux,
        onCancel: @escaping @Sendable () -> Void,
        _ operation: @escaping @Sendable () throws -> Value
    ) async -> Result<Value, Error>? {
        guard let lease = beginExecution(for: core, cancellation: onCancel) else {
            return nil
        }
        let result = await AppleCoreExecution.shared.blockingCancellableResult(
            onCancel: onCancel,
            operation
        )
        finish(lease)
        return result
    }

    /// Runs one exclusive blocking Core operation after the session has
    /// already quiesced. Admission stays closed for the entire operation, and
    /// a concurrent quiescence request waits until this operation has returned.
    ///
    /// This is reserved for destructive session-maintenance work such as
    /// rebuilding synchronized local state. Normal Core work must use the
    /// regular responsive/blocking admission methods above.
    func exclusiveBlockingResult<Value: Sendable>(
        for core: Flux,
        _ operation: @escaping @Sendable () throws -> Value
    ) async -> Result<Value, Error>? {
        guard isQuiescing,
              activeCoreIdentifier == ObjectIdentifier(core),
              activeExecutions.isEmpty else { return nil }

        nextExecutionID &+= 1
        let executionID = nextExecutionID
        activeExecutions[executionID] = ActiveExecution(cancellation: nil)
        activeExecutionCount = activeExecutions.count
        let lease = Lease(
            sessionGeneration: sessionGeneration,
            executionID: executionID
        )

        let result = await AppleCoreExecution.shared.blockingResult(operation)
        finish(lease)
        return result
    }

    /// Must be called only after the underlying synchronous Core call has
    /// returned, not merely when its presentation owner becomes stale.
    func finish(_ lease: Lease) {
        guard lease.sessionGeneration == sessionGeneration,
              activeExecutions.removeValue(forKey: lease.executionID) != nil else { return }

        activeExecutionCount = activeExecutions.count
        guard activeExecutions.isEmpty else { return }

        let waiters = quiescenceWaiters
        quiescenceWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
