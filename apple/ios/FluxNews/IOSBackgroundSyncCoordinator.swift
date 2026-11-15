import BackgroundTasks
import Foundation

enum IOSBackgroundRefreshConfiguration {
    static let preferredInterval: TimeInterval = 30 * 60

    static var taskIdentifier: String {
        if let configured = Bundle.main.object(
            forInfoDictionaryKey: "FluxBackgroundRefreshIdentifier"
        ) as? String,
           !configured.isEmpty {
            return configured
        }

        let bundleID = Bundle.main.bundleIdentifier
            ?? "dev.kevincfechtel.fluxNews.nativeDev"
        return "\(bundleID).backgroundSync"
    }
}

struct IOSBackgroundTaskContext {
    let setExpirationHandler: (@escaping () -> Void) -> Void
    let complete: (Bool) -> Void
}

protocol IOSBackgroundTaskScheduling: AnyObject {
    @discardableResult
    func registerAppRefresh(
        identifier: String,
        launchHandler: @escaping (IOSBackgroundTaskContext) -> Void
    ) -> Bool

    func submitAppRefresh(
        identifier: String,
        earliestBeginDate: Date
    ) throws

    func cancel(identifier: String)
}

final class IOSSystemBackgroundTaskScheduler: IOSBackgroundTaskScheduling {
    static let shared = IOSSystemBackgroundTaskScheduler()

    private init() {}

    @discardableResult
    func registerAppRefresh(
        identifier: String,
        launchHandler: @escaping (IOSBackgroundTaskContext) -> Void
    ) -> Bool {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }

            launchHandler(
                IOSBackgroundTaskContext(
                    setExpirationHandler: { handler in
                        refreshTask.expirationHandler = handler
                    },
                    complete: { success in
                        refreshTask.setTaskCompleted(success: success)
                    }
                )
            )
        }
    }

    func submitAppRefresh(
        identifier: String,
        earliestBeginDate: Date
    ) throws {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliestBeginDate
        try BGTaskScheduler.shared.submit(request)
    }

    func cancel(identifier: String) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }
}

/// Owns the one-time launch registration. Apple requires registration to finish
/// before applicationDidFinishLaunching returns and forbids registering one
/// identifier twice.
final class IOSBackgroundTaskRegistration {
    private let scheduler: IOSBackgroundTaskScheduling
    private let identifier: String
    private let launchHandler: (IOSBackgroundTaskContext) -> Void
    private var registrationSucceeded = false

    init(
        scheduler: IOSBackgroundTaskScheduling,
        identifier: String,
        launchHandler: @escaping (IOSBackgroundTaskContext) -> Void
    ) {
        self.scheduler = scheduler
        self.identifier = identifier
        self.launchHandler = launchHandler
    }

    @discardableResult
    func register() -> Bool {
        if registrationSucceeded { return true }
        registrationSucceeded = scheduler.registerAppRefresh(
            identifier: identifier,
            launchHandler: launchHandler
        )
        return registrationSucceeded
    }
}

private final class IOSBackgroundTaskCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private let completion: (Bool) -> Void

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    func complete(success: Bool) {
        lock.lock()
        let shouldComplete: Bool
        if completed {
            shouldComplete = false
        } else {
            completed = true
            shouldComplete = true
        }
        lock.unlock()

        if shouldComplete {
            completion(success)
        }
    }
}

enum IOSBackgroundSyncPreferenceError: Error {
    case coreUnavailable
}

@MainActor
final class IOSBackgroundSyncCoordinator {
    private let bootstrapper: CoreBootstrapper
    private let scheduler: IOSBackgroundTaskScheduling
    private let identifier: String
    private let preferredInterval: TimeInterval
    private let now: () -> Date
    private let settingsReader: @Sendable (Flux) throws -> Bool
    private let settingsWriter: @Sendable (Flux, Bool) throws -> Void
    private let syncRunner: @Sendable (Flux, SyncCancellation) throws -> SyncOutcome
    private let resumeSyncRunner: @Sendable (Flux, SyncCancellation) throws -> SyncOutcome
    private let logger = IOSAppLogger(category: "background-sync")

    private var nextRunID: UInt64 = 0
    private var activeRunID: UInt64?
    private var activeTask: Task<Void, Never>?
    private var activeCancellation: SyncCancellation?
    private var resumeTask: Task<Void, Never>?

    var onSuccessfulBackgroundSync: ((SyncCompleted) async -> Void)?

    init(
        bootstrapper: CoreBootstrapper,
        scheduler: IOSBackgroundTaskScheduling = IOSSystemBackgroundTaskScheduler.shared,
        identifier: String = IOSBackgroundRefreshConfiguration.taskIdentifier,
        preferredInterval: TimeInterval = IOSBackgroundRefreshConfiguration.preferredInterval,
        now: @escaping () -> Date = Date.init,
        settingsReader: @escaping @Sendable (Flux) throws -> Bool = {
            try $0.coreSettings().backgroundSyncEnabled
        },
        settingsWriter: @escaping @Sendable (Flux, Bool) throws -> Void = {
            try $0.setBackgroundSyncEnabled(enabled: $1)
        },
        syncRunner: @escaping @Sendable (Flux, SyncCancellation) throws -> SyncOutcome = {
            try $0.syncCancellable(reason: .background, cancellation: $1)
        },
        resumeSyncRunner: @escaping @Sendable (Flux, SyncCancellation) throws -> SyncOutcome = {
            try $0.syncCancellable(reason: .resume, cancellation: $1)
        }
    ) {
        self.bootstrapper = bootstrapper
        self.scheduler = scheduler
        self.identifier = identifier
        self.preferredInterval = preferredInterval
        self.now = now
        self.settingsReader = settingsReader
        self.settingsWriter = settingsWriter
        self.syncRunner = syncRunner
        self.resumeSyncRunner = resumeSyncRunner
    }

    /// Reconciles the one pending BGAppRefresh request with persisted Core
    /// settings. Foreground/resume freshness is Core-owned and requested
    /// separately through resumeIfNeeded().
    func refreshScheduling() async {
        guard let core = await bootstrapper.ensureStarted() else {
            if case .accountRequired = bootstrapper.state {
                scheduler.cancel(identifier: identifier)
            }
            return
        }

        guard let settings = await bootstrapper.coreSessionExecutionCoordinator
            .responsiveResult(for: core, { [settingsReader] in
                try settingsReader(core)
            }) else {
            return
        }

        switch settings {
        case let .success(enabled):
            if enabled {
                scheduleNext()
            } else {
                scheduler.cancel(identifier: identifier)
            }
        case let .failure(error):
            logger.error(
                "Could not read Background Sync setting: \(String(reflecting: error))"
            )
        }
    }

    func backgroundSyncPreference() async -> Result<Bool, Error> {
        guard let core = await bootstrapper.ensureStarted() else {
            return .failure(IOSBackgroundSyncPreferenceError.coreUnavailable)
        }
        guard let result = await bootstrapper.coreSessionExecutionCoordinator
            .responsiveResult(for: core, { [settingsReader] in
                try settingsReader(core)
            }) else {
            return .failure(IOSBackgroundSyncPreferenceError.coreUnavailable)
        }
        return result
    }

    func setBackgroundSyncPreference(_ enabled: Bool) async -> Result<Void, Error> {
        guard let core = await bootstrapper.ensureStarted() else {
            return .failure(IOSBackgroundSyncPreferenceError.coreUnavailable)
        }
        guard let result = await bootstrapper.coreSessionExecutionCoordinator
            .responsiveResult(
                for: core,
                { [settingsWriter] in
                    try settingsWriter(core, enabled)
                }
            ) else {
            return .failure(IOSBackgroundSyncPreferenceError.coreUnavailable)
        }

        switch result {
        case .success:
            if enabled {
                scheduleNext()
                resumeIfNeeded()
            } else {
                scheduler.cancel(identifier: identifier)
            }
            return .success(())
        case let .failure(error):
            return .failure(error)
        }
    }

    /// Requests the Core-owned Resume policy. The Core itself decides whether
    /// Background Sync is enabled, whether the last successful Sync is stale,
    /// and whether this run is Delta or Full. Concurrent Manual/Background work
    /// remains serialized by the existing Core Sync gate, where freshness is
    /// re-evaluated after waiting.
    func resumeIfNeeded() {
        guard resumeTask == nil else { return }
        let runner = resumeSyncRunner
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.resumeTask = nil }

            guard let core = await bootstrapper.ensureStarted() else { return }
            let cancellation = SyncCancellation()
            guard let result = await bootstrapper.coreSessionExecutionCoordinator
                .blockingCancellableResult(
                    for: core,
                    onCancel: { cancellation.cancel() },
                    {
                        try runner(core, cancellation)
                    }
                ) else {
                return
            }

            if case let .failure(error) = result,
               !(error is CancellationError) {
                logger.error(
                    "Resume Sync failed: \(String(reflecting: error))"
                )
            }
        }
        resumeTask = task
    }

    func handle(_ context: IOSBackgroundTaskContext) {
        let completion = IOSBackgroundTaskCompletionGate(completion: context.complete)
        guard activeTask == nil else {
            completion.complete(success: false)
            return
        }

        // Follow Apple's recurring BGAppRefresh pattern: submit the successor at
        // task launch. If persisted settings later prove Background Sync is off,
        // execute() cancels that successor before returning.
        scheduleNext()

        nextRunID &+= 1
        let runID = nextRunID
        let cancellation = SyncCancellation()
        activeRunID = runID
        activeCancellation = cancellation

        let task = Task { @MainActor [weak self] in
            guard let self else {
                completion.complete(success: false)
                return
            }
            let success = await execute(
                runID: runID,
                cancellation: cancellation
            )
            completion.complete(success: success)
            finish(runID: runID)
        }
        activeTask = task

        context.setExpirationHandler { [weak self, cancellation, task] in
            cancellation.cancel()
            task.cancel()
            Task { @MainActor in
                guard let self, self.activeRunID == runID else { return }
                self.activeCancellation?.cancel()
            }
        }
    }

    private func execute(
        runID: UInt64,
        cancellation: SyncCancellation
    ) async -> Bool {
        guard activeRunID == runID, !Task.isCancelled else { return false }

        guard let core = await bootstrapper.ensureStarted() else {
            if case .accountRequired = bootstrapper.state {
                scheduler.cancel(identifier: identifier)
            }
            return false
        }
        guard activeRunID == runID, !Task.isCancelled else { return false }

        guard let settingResult = await bootstrapper.coreSessionExecutionCoordinator
            .responsiveResult(for: core, { [settingsReader] in
                try settingsReader(core)
            }) else {
            return false
        }

        switch settingResult {
        case let .success(enabled):
            guard enabled else {
                scheduler.cancel(identifier: identifier)
                return true
            }
        case let .failure(error):
            logger.error(
                "Background Sync setting read failed: \(String(reflecting: error))"
            )
            return false
        }

        guard activeRunID == runID, !Task.isCancelled else { return false }

        guard let result = await bootstrapper.coreSessionExecutionCoordinator
            .blockingCancellableResult(
                for: core,
                onCancel: { cancellation.cancel() },
                { [syncRunner] in
                    try syncRunner(core, cancellation)
                }
            ) else {
            return false
        }

        guard activeRunID == runID else { return false }

        switch result {
        case let .success(outcome):
            switch outcome {
            case let .completed(metadata):
                guard !Task.isCancelled, !cancellation.isCancelled() else {
                    return false
                }
                await onSuccessfulBackgroundSync?(metadata)
                return true
            case .cancelled:
                return false
            }
        case let .failure(error):
            if !(error is CancellationError) {
                logger.error(
                    "Background Sync failed: \(String(reflecting: error))"
                )
            }
            return false
        }
    }

    private func scheduleNext() {
        do {
            try scheduler.submitAppRefresh(
                identifier: identifier,
                earliestBeginDate: now().addingTimeInterval(preferredInterval)
            )
        } catch {
            logger.error(
                "Could not schedule Background Sync: \(String(reflecting: error))"
            )
        }
    }

    private func finish(runID: UInt64) {
        guard activeRunID == runID else { return }
        activeRunID = nil
        activeCancellation = nil
        activeTask = nil
    }
}
