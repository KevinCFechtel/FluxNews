import BackgroundTasks
import UIKit

enum IOSRuntimeLaunchEnvironment {
    static var isUnitTestHost: Bool {
        NSClassFromString("XCTestCase") != nil
    }
}

@MainActor
final class IOSMediaTransferReconciliationHandoff {
    static let shared = IOSMediaTransferReconciliationHandoff()

    typealias Handler = () async -> Void

    private var handler: Handler?
    private var hasPendingRequest = false

    func install(_ handler: @escaping Handler) async {
        self.handler = handler
        guard hasPendingRequest else { return }
        hasPendingRequest = false
        await handler()
    }

    func uninstall() { handler = nil }

    func requestReconciliation() async {
        guard let handler else {
            hasPendingRequest = true
            return
        }
        await handler()
    }
}

enum IOSMediaCoreAccessState: Equatable {
    case detached
    case attached
    case suspendedForCoreReplacement
    case suspendedForLocalStateRebuild
}

@MainActor
final class IOSMediaRuntime {
    private(set) var core: Flux?
    private(set) var coreAccessState: IOSMediaCoreAccessState = .detached
    private(set) var lifecycleGeneration: UInt64 = 0
    private var eventSubscription: EventSubscription?

    let coreSessionExecutionCoordinator: IOSCoreSessionExecutionCoordinator
    let mediaTransferReconciliationHandoff: IOSMediaTransferReconciliationHandoff
    let playbackPresentationState = IOSMediaPlaybackPresentationState()
    let transferPresentationState = IOSMediaTransferPresentationState()

    private unowned let bootstrapper: CoreBootstrapper
    private let onSuccessfulSync: (() async -> Void)?
    private let reconcilePlaybackAfterSuccessfulSync: (() async -> Void)?

    private lazy var playbackCoreAccess = IOSMediaPlaybackCoreAccess(
        coreSessionExecutionCoordinator: coreSessionExecutionCoordinator
    )
    lazy var playbackCoordinator = IOSMediaPlaybackCoordinator(
        coreAccess: playbackCoreAccess,
        presentationState: playbackPresentationState
    )
    lazy var nowPlayingCoordinator = IOSNowPlayingCoordinator(
        playbackCoordinator: playbackCoordinator,
        presentationState: playbackPresentationState
    )
    lazy var transferCoordinator = IOSMediaTransferCoordinator(
        bootstrapper: bootstrapper,
        coreSessionExecutionCoordinator: coreSessionExecutionCoordinator,
        presentationState: transferPresentationState,
        handoff: mediaTransferReconciliationHandoff
    )

    init(
        bootstrapper: CoreBootstrapper,
        coreSessionExecutionCoordinator: IOSCoreSessionExecutionCoordinator,
        mediaTransferReconciliationHandoff: IOSMediaTransferReconciliationHandoff,
        onSuccessfulSync: (() async -> Void)? = nil,
        reconcilePlaybackAfterSuccessfulSync: (() async -> Void)? = nil
    ) {
        self.bootstrapper = bootstrapper
        self.coreSessionExecutionCoordinator = coreSessionExecutionCoordinator
        self.mediaTransferReconciliationHandoff = mediaTransferReconciliationHandoff
        self.onSuccessfulSync = onSuccessfulSync
        self.reconcilePlaybackAfterSuccessfulSync = reconcilePlaybackAfterSuccessfulSync
        transferCoordinator.setMediaInUseProvider { [weak self] enclosureID in
            self?.playbackCoordinator.blocksMediaDeletion(enclosureID: enclosureID) ?? false
        }
        playbackCoordinator.onPlaybackUseChanged = { [weak self] in
            Task { @MainActor [weak self] in await self?.transferCoordinator.reconcile() }
        }
        _ = nowPlayingCoordinator
    }

    private func endEventSubscription() {
        if let eventSubscription { try? eventSubscription.unsubscribe() }
        eventSubscription = nil
    }

    private func subscribe(to core: Flux) {
        do {
            eventSubscription = try core.subscribeEvents(
                listener: IOSMediaRuntimeEventListener(runtime: self, core: core, generation: lifecycleGeneration)
            )
        } catch {}
    }

    func attach(to core: Flux) {
        let replacingCore = self.core != nil && self.core !== core
        // Invalidate callbacks from the old subscription even when reattaching
        // the same Core after a local-state rebuild.
        lifecycleGeneration &+= 1
        endEventSubscription()
        self.core = core
        coreAccessState = .attached
        subscribe(to: core)
        if replacingCore { playbackCoordinator.replaceCore(with: core) }
        else { playbackCoordinator.attach(to: core) }
        transferCoordinator.attach(to: core, generation: lifecycleGeneration)
    }

    func prepareForCoreReplacement() async {
        guard core != nil else { return }
        lifecycleGeneration &+= 1
        coreAccessState = .suspendedForCoreReplacement
        endEventSubscription()
        await playbackCoordinator.suspendForCoreLifecycle()
        transferCoordinator.suspendForCoreLifecycle(generation: lifecycleGeneration)
    }

    func resumeAfterAbortedCoreReplacement() {
        guard core != nil else { return }
        lifecycleGeneration &+= 1
        coreAccessState = .attached
        if let core {
            subscribe(to: core)
            playbackCoordinator.resumeCoreAccess(core)
            transferCoordinator.attach(to: core, generation: lifecycleGeneration)
        }
    }

    func prepareForLocalStateRebuild() {
        guard core != nil else { return }
        lifecycleGeneration &+= 1
        coreAccessState = .suspendedForLocalStateRebuild
        endEventSubscription()
        transferCoordinator.suspendForCoreLifecycle(generation: lifecycleGeneration)
    }

    func localStateRebuildFinished(with core: Flux) { attach(to: core) }

    func detach() {
        guard core != nil || coreAccessState != .detached else { return }
        lifecycleGeneration &+= 1
        endEventSubscription()
        core = nil
        coreAccessState = .detached
        transferCoordinator.detach(generation: lifecycleGeneration, clearingAccountIdentity: true)
        playbackCoordinator.detach()
    }

    func handle(event: CoreEvent, core: Flux, generation: UInt64) {
        guard generation == lifecycleGeneration, self.core === core,
              coreAccessState == .attached else { return }
        guard case .syncDidComplete = event else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard generation == lifecycleGeneration, self.core === core,
                  coreAccessState == .attached else { return }
            if let reconcilePlaybackAfterSuccessfulSync {
                await reconcilePlaybackAfterSuccessfulSync()
            } else {
                await playbackCoordinator.reconcileAfterSuccessfulSync()
            }
            // The preceding await may have suspended across a Core replacement.
            guard generation == lifecycleGeneration, self.core === core,
                  coreAccessState == .attached else { return }
            await onSuccessfulSync?()
        }
    }

    func sceneWillResignActive() { playbackCoordinator.sceneWillResignActive() }
    func sceneDidBecomeActive() { playbackCoordinator.sceneDidBecomeActive() }
    func applicationWillTerminate() {
        playbackCoordinator.applicationWillTerminate()
        nowPlayingCoordinator.cleanup()
    }
}

private final class IOSMediaRuntimeEventListener: EventListener, @unchecked Sendable {
    weak var runtime: IOSMediaRuntime?
    weak var core: Flux?
    let generation: UInt64

    init(runtime: IOSMediaRuntime, core: Flux, generation: UInt64) {
        self.runtime = runtime
        self.core = core
        self.generation = generation
    }

    func onEvent(event: CoreEvent) {
        guard case .syncDidComplete = event else { return }
        Task { @MainActor [weak runtime, weak core] in
            guard let core else { return }
            runtime?.handle(event: event, core: core, generation: generation)
        }
    }
}

@MainActor
final class IOSAppRuntime {
    static let shared = IOSAppRuntime()

    let bootstrapper: CoreBootstrapper
    let legacyMigrationCoordinator: IOSLegacyMigrationCoordinator
    let backgroundSyncCoordinator: IOSBackgroundSyncCoordinator
    let systemNotificationManager: IOSSystemNotificationManager
    let widgetSnapshotCoordinator: IOSWidgetSnapshotCoordinator
    let mediaTransferReconciliationHandoff: IOSMediaTransferReconciliationHandoff
    let mediaRuntime: IOSMediaRuntime

    init(
        bootstrapper: CoreBootstrapper? = nil,
        scheduler: IOSBackgroundTaskScheduling = IOSSystemBackgroundTaskScheduler.shared,
        systemNotificationManager: IOSSystemNotificationManager? = nil,
        mediaTransferReconciliationHandoff: IOSMediaTransferReconciliationHandoff? = nil
    ) {
        let bootstrapper = bootstrapper ?? CoreBootstrapper()
        let legacyMigrationCoordinator = IOSLegacyMigrationCoordinator(bootstrapper: bootstrapper)
        let backgroundSyncCoordinator = IOSBackgroundSyncCoordinator(bootstrapper: bootstrapper, scheduler: scheduler)
        let systemNotificationManager = systemNotificationManager ?? IOSSystemNotificationManager.shared
        let widgetSnapshotCoordinator = IOSWidgetSnapshotCoordinator(bootstrapper: bootstrapper)
        let mediaTransferReconciliationHandoff = mediaTransferReconciliationHandoff ?? IOSMediaTransferReconciliationHandoff.shared
        let mediaRuntime = IOSMediaRuntime(
            bootstrapper: bootstrapper,
            coreSessionExecutionCoordinator: bootstrapper.coreSessionExecutionCoordinator,
            mediaTransferReconciliationHandoff: mediaTransferReconciliationHandoff,
            onSuccessfulSync: { [weak legacyMigrationCoordinator] in
                _ = await legacyMigrationCoordinator?.migratePlaybackProgressIfNeeded()
                _ = await legacyMigrationCoordinator?.migrateDownloadsIfNeeded()
                _ = await legacyMigrationCoordinator?.migrateFeedPreferencesIfNeeded()
                _ = await legacyMigrationCoordinator?.migrateSettingsFollowupIfNeeded()
            }
        )
        self.bootstrapper = bootstrapper
        self.legacyMigrationCoordinator = legacyMigrationCoordinator
        self.backgroundSyncCoordinator = backgroundSyncCoordinator
        self.systemNotificationManager = systemNotificationManager
        self.widgetSnapshotCoordinator = widgetSnapshotCoordinator
        self.mediaTransferReconciliationHandoff = mediaTransferReconciliationHandoff
        self.mediaRuntime = mediaRuntime

        bootstrapper.prepareForCoreReplacement = { [weak mediaRuntime] in await mediaRuntime?.prepareForCoreReplacement() }
        bootstrapper.onCoreReplacementAborted = { [weak mediaRuntime] in mediaRuntime?.resumeAfterAbortedCoreReplacement() }
        bootstrapper.prepareForLocalStateRebuild = { [weak mediaRuntime] in mediaRuntime?.prepareForLocalStateRebuild() }
        bootstrapper.onLocalStateRebuildFinished = { [weak mediaRuntime] core in mediaRuntime?.localStateRebuildFinished(with: core) }
        bootstrapper.onCoreChanged = { [weak mediaRuntime] core in
            if let core { mediaRuntime?.attach(to: core) }
            else { mediaRuntime?.detach() }
        }

        backgroundSyncCoordinator.onSuccessfulBackgroundSync = {
            [weak bootstrapper, weak systemNotificationManager, weak widgetSnapshotCoordinator, weak mediaTransferReconciliationHandoff]
            metadata in
            guard let bootstrapper, let core = bootstrapper.core else { return }
            await widgetSnapshotCoordinator?.refreshNow(for: core)
            if !metadata.systemNotificationCandidates.isEmpty, let systemNotificationManager {
                await systemNotificationManager.deliver(metadata.systemNotificationCandidates) { candidateID in
                    guard let result = await bootstrapper.coreSessionExecutionCoordinator.responsiveResult(
                        for: core,
                        { try core.acknowledgeSystemNotification(candidateId: candidateID) }
                    ) else { return false }
                    if case .success = result { return true }
                    return false
                }
            }
            await mediaTransferReconciliationHandoff?.requestReconciliation()
        }
    }
}

@MainActor
final class IOSAppDelegate: NSObject, UIApplicationDelegate {
    private lazy var backgroundRegistration = IOSBackgroundTaskRegistration(
        scheduler: IOSSystemBackgroundTaskScheduler.shared,
        identifier: IOSBackgroundRefreshConfiguration.taskIdentifier
    ) { context in
        Task { @MainActor in IOSAppRuntime.shared.backgroundSyncCoordinator.handle(context) }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        guard !IOSRuntimeLaunchEnvironment.isUnitTestHost else { return true }
        _ = backgroundRegistration.register()
        IOSAppRuntime.shared.systemNotificationManager.configure()
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        IOSAppRuntime.shared.mediaRuntime.applicationWillTerminate()
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        let handled = IOSAppRuntime.shared.mediaRuntime.transferCoordinator.handleBackgroundEvents(
            identifier: identifier,
            completionHandler: completionHandler
        )
        if !handled { completionHandler() }
    }
}
