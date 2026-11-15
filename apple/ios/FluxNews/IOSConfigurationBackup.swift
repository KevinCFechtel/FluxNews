import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct IOSBackupSettingsV1: Codable, Equatable, Sendable {
    static let version: UInt32 = 1

    let version: UInt32
    let startupScope: String
    let startupCategoryID: Int64?
    let startupFeedID: Int64?
    let hideEmptyNavigationEntries: Bool
    let removeArticlesWhenMarkedRead: Bool
    let markReadOnScrollover: Bool
    let articlePresentationMode: String
    let articlePreviewLines: Int
    let showArticleCount: Bool
    let showRelativePublicationTime: Bool
    let clickOnNews: String
    let leadingSwipeFull: String?
    let leadingSwipeAdditional: String?
    let trailingSwipeFull: String?
    let trailingSwipeAdditional: String?
    let articleListActionIDs: [String]
    let debugLogging: Bool
    let customHeaders: [IOSCustomHTTPHeader]

    @MainActor
    static func capture(
        store: NewsreaderStore,
        articleListActionPreferences: IOSArticleListActionPreferences,
        customHeaders: [IOSCustomHTTPHeader],
        diagnostics: IOSAppDiagnostics = .shared
    ) -> Self {
        .init(
            version: Self.version,
            startupScope: store.startupScope.rawValue,
            startupCategoryID: store.startupCategoryID,
            startupFeedID: store.startupFeedID,
            hideEmptyNavigationEntries: store.hideEmptyNavigationEntries,
            removeArticlesWhenMarkedRead: store.removeArticlesWhenMarkedRead,
            markReadOnScrollover: store.markReadOnScrolloverEnabled,
            articlePresentationMode: store.articlePresentationMode.rawValue,
            articlePreviewLines: store.articlePreviewLines.rawValue,
            showArticleCount: store.showArticleCount,
            showRelativePublicationTime: store.showRelativePublicationTime,
            clickOnNews: store.clickOnNews.rawValue,
            leadingSwipeFull: store.articleSwipeConfiguration
                .fullSwipeAction(for: .leading)?.rawValue,
            leadingSwipeAdditional: store.articleSwipeConfiguration
                .additionalAction(for: .leading)?.rawValue,
            trailingSwipeFull: store.articleSwipeConfiguration
                .fullSwipeAction(for: .trailing)?.rawValue,
            trailingSwipeAdditional: store.articleSwipeConfiguration
                .additionalAction(for: .trailing)?.rawValue,
            articleListActionIDs: articleListActionPreferences.actions.map(\.rawValue),
            debugLogging: diagnostics.isDebugLoggingEnabled,
            customHeaders: customHeaders
        )
    }

    func validated() throws -> IOSValidatedBackupSettings {
        guard version == Self.version,
              let startupScope = StartupScopePreference(rawValue: startupScope),
              let presentationMode = ArticlePresentationMode(rawValue: articlePresentationMode),
              let previewLines = ArticlePreviewLines(rawValue: articlePreviewLines),
              let clickOnNews = ClickOnNews(rawValue: clickOnNews) else {
            throw IOSConfigurationBackupError.unsupportedPlatformSettings
        }

        if startupScope == .category {
            guard let startupCategoryID, startupCategoryID > 0 else {
                throw IOSConfigurationBackupError.invalidPlatformSettings
            }
        }
        if startupScope == .feed {
            guard let startupFeedID, startupFeedID > 0 else {
                throw IOSConfigurationBackupError.invalidPlatformSettings
            }
        }

        func swipe(_ raw: String?) throws -> IOSArticleSwipeAction? {
            guard let raw else { return nil }
            guard let action = IOSArticleSwipeAction(rawValue: raw) else {
                throw IOSConfigurationBackupError.invalidPlatformSettings
            }
            return action
        }

        let leadingFull = try swipe(leadingSwipeFull)
        var leadingAdditional = try swipe(leadingSwipeAdditional)
        let trailingFull = try swipe(trailingSwipeFull)
        var trailingAdditional = try swipe(trailingSwipeAdditional)

        if leadingFull == nil, leadingAdditional != nil {
            throw IOSConfigurationBackupError.invalidPlatformSettings
        }
        if trailingFull == nil, trailingAdditional != nil {
            throw IOSConfigurationBackupError.invalidPlatformSettings
        }
        if leadingAdditional == leadingFull { leadingAdditional = nil }
        if trailingAdditional == trailingFull { trailingAdditional = nil }

        guard articleListActionIDs.count == Set(articleListActionIDs).count else {
            throw IOSConfigurationBackupError.invalidPlatformSettings
        }
        let actionBar = try articleListActionIDs.map { raw -> IOSBottomAction in
            guard let action = IOSBottomAction(rawValue: raw),
                  IOSBottomAction.configurableActions.contains(action) else {
                throw IOSConfigurationBackupError.invalidPlatformSettings
            }
            return action
        }

        var headerNames = Set<String>()
        for header in customHeaders {
            let name = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  !name.contains("\n"),
                  !name.contains("\r"),
                  header.value.utf8.count <= 8 * 1024 else {
                throw IOSConfigurationBackupError.invalidPlatformSettings
            }
            let canonical = name.lowercased()
            guard headerNames.insert(canonical).inserted else {
                throw IOSConfigurationBackupError.invalidPlatformSettings
            }
        }

        return .init(
            startupScope: startupScope,
            startupCategoryID: startupScope == .category ? startupCategoryID : nil,
            startupFeedID: startupScope == .feed ? startupFeedID : nil,
            hideEmptyNavigationEntries: hideEmptyNavigationEntries,
            removeArticlesWhenMarkedRead: removeArticlesWhenMarkedRead,
            markReadOnScrollover: markReadOnScrollover,
            articlePresentationMode: presentationMode,
            articlePreviewLines: previewLines,
            showArticleCount: showArticleCount,
            showRelativePublicationTime: showRelativePublicationTime,
            clickOnNews: clickOnNews,
            leadingFull: leadingFull,
            leadingAdditional: leadingAdditional,
            trailingFull: trailingFull,
            trailingAdditional: trailingAdditional,
            actionBar: actionBar,
            debugLogging: debugLogging,
            customHeaders: customHeaders
        )
    }
}

struct IOSValidatedBackupSettings: Equatable {
    let startupScope: StartupScopePreference
    let startupCategoryID: Int64?
    let startupFeedID: Int64?
    let hideEmptyNavigationEntries: Bool
    let removeArticlesWhenMarkedRead: Bool
    let markReadOnScrollover: Bool
    let articlePresentationMode: ArticlePresentationMode
    let articlePreviewLines: ArticlePreviewLines
    let showArticleCount: Bool
    let showRelativePublicationTime: Bool
    let clickOnNews: ClickOnNews
    let leadingFull: IOSArticleSwipeAction?
    let leadingAdditional: IOSArticleSwipeAction?
    let trailingFull: IOSArticleSwipeAction?
    let trailingAdditional: IOSArticleSwipeAction?
    let actionBar: [IOSBottomAction]
    let debugLogging: Bool
    let customHeaders: [IOSCustomHTTPHeader]

    @MainActor
    func apply(
        store: NewsreaderStore,
        articleListActionPreferences: IOSArticleListActionPreferences,
        diagnostics: IOSAppDiagnostics = .shared
    ) {
        store.setStartupScope(startupScope)
        store.setStartupCategoryID(startupCategoryID)
        store.setStartupFeedID(startupFeedID)
        store.setHideEmptyNavigationEntries(hideEmptyNavigationEntries)
        store.setRemoveArticlesWhenMarkedRead(removeArticlesWhenMarkedRead)
        store.setMarkReadOnScrolloverEnabled(markReadOnScrollover)
        store.setArticlePresentationMode(articlePresentationMode)
        store.setArticlePreviewLines(articlePreviewLines)
        store.setShowArticleCount(showArticleCount)
        store.setShowRelativePublicationTime(showRelativePublicationTime)
        store.setClickOnNews(clickOnNews)

        store.setArticleSwipeAction(
            leadingFull,
            side: .leading,
            slot: .fullSwipe
        )
        store.setArticleSwipeAction(
            leadingAdditional,
            side: .leading,
            slot: .additional
        )
        store.setArticleSwipeAction(
            trailingFull,
            side: .trailing,
            slot: .fullSwipe
        )
        store.setArticleSwipeAction(
            trailingAdditional,
            side: .trailing,
            slot: .additional
        )

        articleListActionPreferences.setActions(actionBar)
        diagnostics.setDebugLoggingEnabled(debugLogging)
    }
}

enum IOSConfigurationBackupError: LocalizedError {
    case noConfiguredAccount
    case unsupportedPlatformSettings
    case invalidPlatformSettings
    case fileAccess
    case restoreFailed

    var errorDescription: String? {
        switch self {
        case .noConfiguredAccount:
            String(localized: "Configure a Miniflux account before exporting a backup.")
        case .unsupportedPlatformSettings:
            String(localized: "This backup contains unsupported iOS settings.")
        case .invalidPlatformSettings:
            String(localized: "This backup contains invalid iOS settings.")
        case .fileAccess:
            String(localized: "The selected backup file could not be read.")
        case .restoreFailed:
            String(localized: "The configuration could not be restored.")
        }
    }

    static func message(for error: Error) -> String {
        switch error {
        case ConfigBackupError.NotFluxBackup:
            String(localized: "Not a valid FluxNews backup.")
        case ConfigBackupError.PlatformMismatch:
            String(localized: "This backup was created for another platform.")
        case ConfigBackupError.UnsupportedVersion:
            String(localized: "This backup uses a newer unsupported format.")
        case ConfigBackupError.DecryptionFailed:
            String(localized: "The backup could not be decrypted. The password may be incorrect or the file may be damaged.")
        case ConfigBackupError.InvalidCryptoMetadata,
             ConfigBackupError.MalformedPayload,
             ConfigBackupError.InvalidContents:
            String(localized: "The backup is damaged or contains invalid data.")
        case ConfigBackupError.InputTooLarge:
            String(localized: "The selected backup is too large.")
        case ConfigBackupError.EmptyPassword:
            String(localized: "Enter a backup password.")
        case let error as IOSConfigurationBackupError:
            error.localizedDescription
        case CoreBootstrapper.ConfigurationBackupRestoreError.rollbackFailed:
            String(localized: "The restore failed and the previous configuration could not be recovered. Restart FluxNews before making further changes.")
        case CoreBootstrapper.ConfigurationBackupRestoreError.busy:
            String(localized: "FluxNews is currently busy. Try the restore again.")
        default:
            String(localized: "The configuration backup operation failed.")
        }
    }
}

@MainActor
final class IOSConfigurationBackupCoordinator {
    private let bootstrapper: CoreBootstrapper
    private let fileManager: FileManager
    private let diagnostics: IOSAppDiagnostics
    private let invalidateWidgetProjection: @MainActor () -> Void
    private let restoreWidgetProjection: @MainActor (Flux) -> Void

    init(
        bootstrapper: CoreBootstrapper,
        fileManager: FileManager = .default,
        diagnostics: IOSAppDiagnostics = .shared,
        invalidateWidgetProjection: @escaping @MainActor () -> Void = {
            IOSAppRuntime.shared.widgetSnapshotCoordinator.detach()
        },
        restoreWidgetProjection: @escaping @MainActor (Flux) -> Void = {
            IOSAppRuntime.shared.widgetSnapshotCoordinator.attach(to: $0)
        }
    ) {
        self.bootstrapper = bootstrapper
        self.fileManager = fileManager
        self.diagnostics = diagnostics
        self.invalidateWidgetProjection = invalidateWidgetProjection
        self.restoreWidgetProjection = restoreWidgetProjection
    }

    func exportBackup(
        password: String,
        store: NewsreaderStore,
        articleListActionPreferences: IOSArticleListActionPreferences
    ) async throws -> URL {
        guard !password.isEmpty else { throw ConfigBackupError.EmptyPassword }
        guard let credentials = try bootstrapper.credentialStore.load() else {
            throw IOSConfigurationBackupError.noConfiguredAccount
        }

        let snapshot = try await bootstrapper.configurationSnapshotForBackup()
        let native = IOSBackupSettingsV1.capture(
            store: store,
            articleListActionPreferences: articleListActionPreferences,
            customHeaders: credentials.customHeaders,
            diagnostics: diagnostics
        )
        _ = try native.validated()
        let payload = try JSONEncoder().encode(native)
        let input = ConfigBackupInput(
            platform: .ios,
            account: BackupAccount(
                installationBase: snapshot.installationBase,
                apiKey: credentials.apiKey
            ),
            coreSettings: snapshot.coreSettings,
            feedPreferences: snapshot.feedPreferences,
            platformSettings: PlatformSettingsPayload(
                schemaVersion: IOSBackupSettingsV1.version,
                dataJson: String(decoding: payload, as: UTF8.self)
            )
        )

        let bytes = try await AppleCoreExecution.shared.blocking {
            try exportConfigBackup(input: input, password: password)
        }

        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("FluxNews-Configuration-Backup", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("FluxNews Backup.fluxbackup")
        try Data(bytes).write(to: url, options: .atomic)
        return url
    }

    func restoreBackup(
        from url: URL,
        password: String,
        store: NewsreaderStore,
        articleListActionPreferences: IOSArticleListActionPreferences
    ) async throws -> Bool {
        guard !password.isEmpty else { throw ConfigBackupError.EmptyPassword }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw IOSConfigurationBackupError.fileAccess
        }

        let restored = try await AppleCoreExecution.shared.blocking {
            try parseConfigBackup(
                bytes: data,
                password: password,
                expectedPlatform: .ios
            )
        }

        guard restored.platformSettings.schemaVersion == IOSBackupSettingsV1.version else {
            throw IOSConfigurationBackupError.unsupportedPlatformSettings
        }
        let native: IOSBackupSettingsV1
        do {
            native = try JSONDecoder().decode(
                IOSBackupSettingsV1.self,
                from: Data(restored.platformSettings.dataJson.utf8)
            )
        } catch {
            throw IOSConfigurationBackupError.invalidPlatformSettings
        }
        let validated = try native.validated()
        let previousHeaders = (try? bootstrapper.credentialStore.load())?.customHeaders ?? []
        let previousNative = try IOSBackupSettingsV1.capture(
            store: store,
            articleListActionPreferences: articleListActionPreferences,
            customHeaders: previousHeaders,
            diagnostics: diagnostics
        ).validated()

        validated.apply(
            store: store,
            articleListActionPreferences: articleListActionPreferences,
            diagnostics: diagnostics
        )
        invalidateWidgetProjection()

        do {
            try await bootstrapper.restoreConfigurationBackup(
                restored,
                customHeaders: validated.customHeaders
            )
        } catch {
            previousNative.apply(
                store: store,
                articleListActionPreferences: articleListActionPreferences,
                diagnostics: diagnostics
            )
            store.reloadLegacyMigrationSettings()
            if let activeCore = bootstrapper.core {
                restoreWidgetProjection(activeCore)
            }
            throw error
        }

        store.reloadLegacyMigrationSettings()
        await IOSAppRuntime.shared.backgroundSyncCoordinator.refreshScheduling()
        await IOSAppRuntime.shared.mediaTransferReconciliationHandoff
            .requestReconciliation()

        return await bootstrapper.syncAfterConfigurationRestore()
    }
}

struct ConfigurationBackupSettingsView: View {
    var store: NewsreaderStore
    @ObservedObject var bootstrapper: CoreBootstrapper
    @ObservedObject var articleListActionPreferences: IOSArticleListActionPreferences

    @State private var exportPassword = ""
    @State private var exportURL: URL?
    @State private var importPassword = ""
    @State private var showingImporter = false
    @State private var pendingImportURL: URL?
    @State private var showingRestoreConfirmation = false
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var coordinator: IOSConfigurationBackupCoordinator {
        IOSConfigurationBackupCoordinator(bootstrapper: bootstrapper)
    }

    var body: some View {
        List {
            if bootstrapper.credentials != nil {
                Section {
                    SecureField("Backup Password", text: $exportPassword)

                    Button {
                        prepareExport()
                    } label: {
                        Label("Prepare Backup", systemImage: "lock.doc")
                    }
                    .disabled(isWorking || exportPassword.isEmpty)

                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label(
                                "Export Configuration Backup",
                                systemImage: "square.and.arrow.up"
                            )
                        }
                    }
                } header: {
                    Text("Export")
                } footer: {
                    Text(
                        "The backup is password-encrypted and contains account credentials, Core settings, feed preferences, and iOS configuration. The password is not stored and cannot be recovered. Articles, downloads, playback state, logs, caches, and widget instances are not included."
                    )
                }
            }

            Section {
                SecureField("Backup Password", text: $importPassword)

                Button {
                    showingImporter = true
                } label: {
                    Label("Choose Backup to Restore", systemImage: "square.and.arrow.down")
                }
                .disabled(isWorking || importPassword.isEmpty)
            } header: {
                Text("Restore")
            } footer: {
                Text("Restoring replaces the configured account and configuration, clears reconstructable synchronized state, and then attempts a normal sync. Downloaded media and playback state are not restored from the backup.")
            }

            if isWorking {
                Section {
                    HStack {
                        ProgressView()
                        Text("Working…")
                    }
                }
            }
            if let statusMessage {
                Section {
                    Label(statusMessage, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                } header: {
                    Text("Restore Error")
                }
            }
        }
        .navigationTitle("Configuration Backup")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [UTType(filenameExtension: "fluxbackup") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                pendingImportURL = urls.first
                showingRestoreConfirmation = pendingImportURL != nil
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
        .alert(
            "Restore Configuration?",
            isPresented: $showingRestoreConfirmation
        ) {
            Button("Restore", role: .destructive) {
                restorePendingBackup()
            }
            Button("Cancel", role: .cancel) {
                pendingImportURL = nil
            }
        } message: {
            Text("This replaces the current account and configuration with the selected backup. Existing synchronized article state will be rebuilt.")
        }
    }

    private func prepareExport() {
        isWorking = true
        errorMessage = nil
        statusMessage = nil
        exportURL = nil
        let coordinator = coordinator
        Task {
            do {
                exportURL = try await coordinator.exportBackup(
                    password: exportPassword,
                    store: store,
                    articleListActionPreferences: articleListActionPreferences
                )
                statusMessage = String(localized: "Configuration backup prepared.")
            } catch {
                errorMessage = IOSConfigurationBackupError.message(for: error)
            }
            isWorking = false
        }
    }

    private func restorePendingBackup() {
        guard let url = pendingImportURL else { return }
        pendingImportURL = nil
        isWorking = true
        errorMessage = nil
        statusMessage = nil
        exportURL = nil
        let coordinator = coordinator
        Task {
            do {
                let synchronized = try await coordinator.restoreBackup(
                    from: url,
                    password: importPassword,
                    store: store,
                    articleListActionPreferences: articleListActionPreferences
                )
                statusMessage = synchronized
                    ? String(localized: "Configuration restored and synchronized.")
                    : String(localized: "Configuration restored. Synchronization will be retried later.")
            } catch {
                errorMessage = IOSConfigurationBackupError.message(for: error)
            }
            isWorking = false
        }
    }
}
