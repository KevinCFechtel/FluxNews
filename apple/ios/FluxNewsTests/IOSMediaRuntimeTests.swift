import XCTest
@testable import FluxNews

@MainActor
final class IOSMediaRuntimeTests: XCTestCase {
    func testHostATSAllowsUserSuppliedHTTPMediaWithoutChangingWidgetPolicy() throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let hostData = try Data(contentsOf: project.appendingPathComponent("FluxNews/Info.plist"))
        let host = try XCTUnwrap(PropertyListSerialization.propertyList(from: hostData, format: nil) as? [String: Any])
        let ats = try XCTUnwrap(host["NSAppTransportSecurity"] as? [String: Any])
        XCTAssertEqual(ats["NSAllowsArbitraryLoads"] as? Bool, true)
        XCTAssertNil(ats["NSAllowsArbitraryLoadsForMedia"])

        let widgetData = try Data(contentsOf: project.appendingPathComponent("FluxNewsWidgets/Info.plist"))
        let widget = try XCTUnwrap(PropertyListSerialization.propertyList(from: widgetData, format: nil) as? [String: Any])
        XCTAssertNil(widget["NSAppTransportSecurity"])
    }

    private func makeCore() throws -> Flux {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let data = root.appendingPathComponent("data")
        let cache = root.appendingPathComponent("cache")
        let media = root.appendingPathComponent("media")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        return try Flux.initialize(config: InitializationConfig(
            persistentData: data.path,
            cache: cache.path,
            media: media.path,
            baseUrl: "https://miniflux.example",
            apiKey: "key",
            customHeaders: []
        ))
    }

    private func makeRuntime(
        onSuccessfulSync: @escaping () async -> Void,
        reconcilePlaybackAfterSuccessfulSync: @escaping () async -> Void
    ) -> IOSMediaRuntime {
        let bootstrapper = CoreBootstrapper(credentialStore: IOSMemoryCredentialStore())
        return IOSMediaRuntime(
            bootstrapper: bootstrapper,
            coreSessionExecutionCoordinator: bootstrapper.coreSessionExecutionCoordinator,
            mediaTransferReconciliationHandoff: IOSMediaTransferReconciliationHandoff(),
            onSuccessfulSync: onSuccessfulSync,
            reconcilePlaybackAfterSuccessfulSync: reconcilePlaybackAfterSuccessfulSync
        )
    }

    private func syncCompletedEvent() -> CoreEvent {
        .syncDidComplete(metadata: SyncCompleted(
            reason: .manual,
            newArticles: 0,
            updatedArticles: 0,
            mutationsDelivered: 0,
            dataChanged: false,
            navigationChanged: false,
            newArticlesByFeed: [],
            systemNotificationCandidates: []
        ))
    }

    func testSyncCompletedReconcilesPlaybackThenRetriesLegacyMigrationsSequentially() async throws {
        let core = try makeCore()
        let reconciled = expectation(description: "playback reconciled")
        let migrated = expectation(description: "legacy migrations retried")
        var calls: [String] = []
        let runtime = makeRuntime(
            onSuccessfulSync: {
                calls.append("playback migration")
                calls.append("download migration")
                calls.append("feed preference migration")
                migrated.fulfill()
            },
            reconcilePlaybackAfterSuccessfulSync: {
                calls.append("reconcile")
                reconciled.fulfill()
            }
        )
        runtime.attach(to: core)

        runtime.handle(event: syncCompletedEvent(), core: core, generation: runtime.lifecycleGeneration)

        await fulfillment(of: [reconciled, migrated], timeout: 1)
        XCTAssertEqual(calls, ["reconcile", "playback migration", "download migration", "feed preference migration"])
    }

    func testNonSyncCompletedEventDoesNotRetryLegacyPlaybackMigration() async throws {
        let core = try makeCore()
        var calls = 0
        let runtime = makeRuntime(
            onSuccessfulSync: { calls += 1 },
            reconcilePlaybackAfterSuccessfulSync: { calls += 1 }
        )
        runtime.attach(to: core)

        runtime.handle(event: .articleReadStateChanged(articleId: 1, read: true), core: core, generation: runtime.lifecycleGeneration)

        XCTAssertEqual(calls, 0)
    }

    func testDetachedAndSuspendedRuntimeRejectOldSessionEvents() async throws {
        let core = try makeCore()
        var calls = 0
        let runtime = makeRuntime(
            onSuccessfulSync: { calls += 1 },
            reconcilePlaybackAfterSuccessfulSync: { calls += 1 }
        )
        runtime.attach(to: core)
        let beforeSuspend = runtime.lifecycleGeneration
        runtime.prepareForLocalStateRebuild()
        runtime.handle(event: syncCompletedEvent(), core: core, generation: beforeSuspend)
        runtime.handle(event: syncCompletedEvent(), core: core, generation: runtime.lifecycleGeneration)
        XCTAssertEqual(calls, 0)

        runtime.localStateRebuildFinished(with: core)
        let activeGeneration = runtime.lifecycleGeneration
        XCTAssertGreaterThan(activeGeneration, beforeSuspend)
        runtime.detach()
        runtime.handle(event: syncCompletedEvent(), core: core, generation: activeGeneration)
        XCTAssertEqual(calls, 0)
    }

    func testStaleCoreOrGenerationSyncCompletedEventDoesNotRunSuccessfulSyncHooks() async throws {
        let staleCore = try makeCore()
        let currentCore = try makeCore()
        var calls = 0
        let runtime = makeRuntime(
            onSuccessfulSync: { calls += 1 },
            reconcilePlaybackAfterSuccessfulSync: { calls += 1 }
        )
        runtime.attach(to: staleCore)
        let staleGeneration = runtime.lifecycleGeneration
        runtime.attach(to: currentCore)

        runtime.handle(event: syncCompletedEvent(), core: staleCore, generation: staleGeneration)
        runtime.handle(event: syncCompletedEvent(), core: currentCore, generation: staleGeneration)

        XCTAssertEqual(calls, 0)
    }
}
