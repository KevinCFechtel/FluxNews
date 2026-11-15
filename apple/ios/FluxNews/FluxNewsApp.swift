import SwiftUI
import UIKit

enum IOSSceneOwnershipPolicy {
    // Core/session and mutation coordination are intentionally single-window until
    // a future multi-scene coordinator can own them independently of presentation.
    static let supportsMultipleScenes = false
}

final class FluxNewsAppBundleMarker {}

@MainActor
@main
struct FluxNewsApp: App {
    @UIApplicationDelegateAdaptor(IOSAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var bootstrapper = IOSAppRuntime.shared.bootstrapper
    @State private var newsreaderStore = NewsreaderStore()
    @StateObject private var articleListActionPreferences = IOSArticleListActionPreferences()
    @State private var migrationSummary: IOSLegacyMigrationCoordinator.Summary?
    @State private var showingMigrationSummary = false
    @State private var migrationHiddenThisSession = false

    var body: some Scene {
        WindowGroup {
            ContentView(
                bootstrapper: bootstrapper,
                newsreaderStore: newsreaderStore,
                articleListActionPreferences: articleListActionPreferences
            )
                .tint(Color("FluxAccent"))
                .task {
                    guard !IOSRuntimeLaunchEnvironment.isUnitTestHost else { return }
                    IOSAppLogger(category: "app").info(
                        "FluxNews launch version=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown") build=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown") os=\(UIDevice.current.systemVersion)"
                    )
                    IOSAppRuntime.shared.systemNotificationManager.onFeedSelected = { feedID in
                        newsreaderStore.select(.feed(feedID))
                    }
                    let runtimePrepareForCoreReplacement = bootstrapper.prepareForCoreReplacement
                    let runtimeCoreReplacementAborted = bootstrapper.onCoreReplacementAborted
                    let runtimePrepareForLocalStateRebuild = bootstrapper.prepareForLocalStateRebuild
                    let runtimeLocalStateRebuildFinished = bootstrapper.onLocalStateRebuildFinished
                    let runtimeCoreChanged = bootstrapper.onCoreChanged

                    bootstrapper.prepareForCoreReplacement = {
                        await newsreaderStore.quiesceManualSyncForCoreReplacement()
                        await runtimePrepareForCoreReplacement?()
                    }
                    bootstrapper.onCoreReplacementAborted = {
                        runtimeCoreReplacementAborted?()
                        newsreaderStore.resumeManualSyncAfterAbortedCoreReplacement()
                    }
                    bootstrapper.prepareForLocalStateRebuild = {
                        runtimePrepareForLocalStateRebuild?()
                        IOSAppRuntime.shared.widgetSnapshotCoordinator.detach()
                        newsreaderStore.detach()
                    }
                    bootstrapper.onLocalStateRebuildFinished = { core in
                        runtimeLocalStateRebuildFinished?(core)
                        IOSAppRuntime.shared.widgetSnapshotCoordinator.attach(to: core)
                        newsreaderStore.attach(
                            to: core,
                            coreSessionExecutionCoordinator: bootstrapper.coreSessionExecutionCoordinator
                        )
                    }
                    bootstrapper.onCoreChanged = { core in
                        runtimeCoreChanged?(core)
                        if let core {
                            IOSAppRuntime.shared.widgetSnapshotCoordinator.attach(to: core)
                            newsreaderStore.attach(
                                to: core,
                                coreSessionExecutionCoordinator: bootstrapper.coreSessionExecutionCoordinator
                            )
                        } else {
                            IOSAppRuntime.shared.widgetSnapshotCoordinator.detach()
                            newsreaderStore.detach()
                        }
                    }
                    if let core = await bootstrapper.ensureStarted(),
                       newsreaderStore.core !== core {
                        IOSAppRuntime.shared.widgetSnapshotCoordinator.attach(to: core)
                        newsreaderStore.attach(
                            to: core,
                            coreSessionExecutionCoordinator: bootstrapper.coreSessionExecutionCoordinator
                        )
                        _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migrateMediaSettingsIfNeeded()
                        await prepareInitialMigrationSummary()
                        _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migratePlaybackProgressIfNeeded()
                        _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migrateDownloadsIfNeeded()
                    } else if bootstrapper.core != nil {
                        _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migrateMediaSettingsIfNeeded()
                        await prepareInitialMigrationSummary()
                        _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migratePlaybackProgressIfNeeded()
                        _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migrateDownloadsIfNeeded()
                    } else if bootstrapper.core == nil,
                              case .accountRequired = bootstrapper.state {
                        _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migrateAccountIfNeeded()
                        _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migrateMediaSettingsIfNeeded()
                        await prepareInitialMigrationSummary()
                        _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migratePlaybackProgressIfNeeded()
                        _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migrateDownloadsIfNeeded()
                    }
                    _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migrateGlobalPreferencesIfNeeded()
                    _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migrateSettingsFollowupIfNeeded()
                    _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migrateToolbarIfNeeded()
                    _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migrateWidgetDefaultsIfNeeded()
                    newsreaderStore.reloadLegacyMigrationSettings()
                    articleListActionPreferences.reloadFromDefaults()
                    await IOSAppRuntime.shared.backgroundSyncCoordinator.refreshScheduling()
                    IOSAppRuntime.shared.backgroundSyncCoordinator.resumeIfNeeded()
                    if !migrationHiddenThisSession,
                       let summary = IOSAppRuntime.shared.legacyMigrationCoordinator.migrationSummary(),
                       !summary.acknowledged {
                        migrationSummary = summary
                        showingMigrationSummary = true
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard !IOSRuntimeLaunchEnvironment.isUnitTestHost else { return }
                    if phase == .active {
                        IOSAppRuntime.shared.mediaRuntime.sceneDidBecomeActive()
                        Task {
                            if let core = await bootstrapper.ensureStarted(),
                               newsreaderStore.core !== core {
                                IOSAppRuntime.shared.widgetSnapshotCoordinator.attach(to: core)
                                newsreaderStore.attach(
                                    to: core,
                                    coreSessionExecutionCoordinator: bootstrapper.coreSessionExecutionCoordinator
                                )
                                _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migrateMediaSettingsIfNeeded()
                                 await prepareInitialMigrationSummary()
                        _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migratePlaybackProgressIfNeeded()
                                 _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migrateDownloadsIfNeeded()
                            } else if bootstrapper.core != nil {
                                _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migrateMediaSettingsIfNeeded()
                                 await prepareInitialMigrationSummary()
                        _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migratePlaybackProgressIfNeeded()
                                 _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migrateDownloadsIfNeeded()
                            } else if bootstrapper.core == nil,
                                      case .accountRequired = bootstrapper.state {
                                _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migrateAccountIfNeeded()
                                _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migrateMediaSettingsIfNeeded()
                                 await prepareInitialMigrationSummary()
                        _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migratePlaybackProgressIfNeeded()
                                  _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migrateDownloadsIfNeeded()
                            }
                            _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migrateGlobalPreferencesIfNeeded()
                            _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migrateSettingsFollowupIfNeeded()
                            _ = await IOSAppRuntime.shared.legacyMigrationCoordinator.migrateWidgetDefaultsIfNeeded()
                            newsreaderStore.reloadLegacyMigrationSettings()
                    articleListActionPreferences.reloadFromDefaults()
                            await IOSAppRuntime.shared.backgroundSyncCoordinator.refreshScheduling()
                            IOSAppRuntime.shared.backgroundSyncCoordinator.resumeIfNeeded()
                            if !migrationHiddenThisSession,
                               let summary = IOSAppRuntime.shared.legacyMigrationCoordinator.migrationSummary(),
                               !summary.acknowledged {
                                migrationSummary = summary
                                showingMigrationSummary = true
                            }
                        }
                    } else {
                        IOSAppRuntime.shared.mediaRuntime.sceneWillResignActive()
                        newsreaderStore.flushScrolloverPersistenceForLifecycle()
                    }
                }
                .sheet(isPresented: $showingMigrationSummary) {
                    if let summary = migrationSummary {
                        IOSLegacyMigrationSummaryView(
                            summary: summary,
                            sync: {
                                await newsreaderStore.syncManually()
                                let coordinator = IOSAppRuntime.shared.legacyMigrationCoordinator
                                _ = await coordinator.migratePlaybackProgressIfNeeded()
                                _ = await coordinator.migrateDownloadsIfNeeded()
                                migrationSummary = coordinator.migrationSummary()
                            },
                            close: {
                                if summary.completed {
                                    IOSAppRuntime.shared.legacyMigrationCoordinator.acknowledgeCompletedMigration()
                                }
                                migrationHiddenThisSession = true
                                showingMigrationSummary = false
                            },
                            finishPartial: {
                                let coordinator = IOSAppRuntime.shared.legacyMigrationCoordinator
                                if coordinator.finishMigrationWithSkippedItems() {
                                    migrationSummary = coordinator.migrationSummary()
                                    migrationHiddenThisSession = true
                                    showingMigrationSummary = false
                                }
                            }
                        )
                        .interactiveDismissDisabled()
                    }
                }
        }
    }
    /// Resolve local and catalog settings immediately on activation, without
    /// waiting for a long historical media import or a manual sync. Later
    /// successful syncs can retry catalog-dependent records.
    private func prepareInitialMigrationSummary() async {
        let coordinator = IOSAppRuntime.shared.legacyMigrationCoordinator
        _ = await coordinator.migrateGlobalPreferencesIfNeeded()
        _ = await coordinator.migrateSettingsFollowupIfNeeded()
        _ = await coordinator.migrateFeedPreferencesIfNeeded()
        _ = await coordinator.migrateToolbarIfNeeded()
        _ = await coordinator.migrateWidgetDefaultsIfNeeded()
        if !migrationHiddenThisSession,
           let summary = coordinator.migrationSummary(),
           !summary.acknowledged {
            migrationSummary = summary
            showingMigrationSummary = true
        }
    }

}