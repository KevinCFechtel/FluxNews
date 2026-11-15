import Combine
import Foundation

@MainActor
final class CoreBootstrapper: ObservableObject {
    private enum DefaultsKey {
        static let mutationDeliveryDefaultApplied =
            "FluxNews.iOS.mutationDeliveryDefaultApplied.v1"
        static let accountInfoServerBase =
            "FluxNews.iOS.accountInfo.serverBase.v1"
        static let accountInfoServerVersion =
            "FluxNews.iOS.accountInfo.serverVersion.v1"
    }

    enum SettingsAccessError: Error {
        case coreUnavailable
        case sessionUnavailable
    }

    enum ConfigurationBackupRestoreError: Error {
        case busy
        case noConfiguredAccount
        case sessionUnavailable
        case activationFailed
        case rollbackFailed
    }

    enum LocalStateRebuildState: Equatable {
        case idle
        case rebuilding
        case succeeded
        case failed
    }

    enum State: Equatable {
        case starting
        case accountRequired
        case ready(String)
        case recoverableError(String)

        var title: String {
            switch self {
            case .starting: String(localized: "Starting")
            case .accountRequired: String(localized: "Account required")
            case .ready: String(localized: "Ready")
            case .recoverableError: String(localized: "Recoverable startup error")
            }
        }
    }

    @Published private(set) var state: State = .starting
    @Published private(set) var credentials: IOSMinifluxCredentials?
    @Published private(set) var validationMessage: String?
    @Published private(set) var validationDiagnostic: AccountValidationDiagnostic?
    @Published private(set) var serverVersion: String?
    @Published private(set) var isConfiguring = false
    @Published private(set) var localStateRebuildState: LocalStateRebuildState = .idle
    @Published private(set) var core: Flux?
    @Published private(set) var coreRevision: UInt64 = 0
    let credentialStore: IOSCredentialStoreProtocol
    let coreSessionExecutionCoordinator: IOSCoreSessionExecutionCoordinator
    var onCoreChanged: ((Flux?) -> Void)?
    var prepareForCoreReplacement: (() async -> Void)?
    var onCoreReplacementAborted: (() -> Void)?
    var prepareForLocalStateRebuild: (() -> Void)?
    var onLocalStateRebuildFinished: ((Flux) -> Void)?

    private let coreFactory: @Sendable (IOSMinifluxCredentials) throws -> Flux
    private let accountValidator: @Sendable (IOSMinifluxCredentials) throws -> AccountValidationAttempt
    private let localStateRebuilder: @Sendable (Flux) throws -> SyncCompleted
    private let defaults: UserDefaults
    private let logger = IOSAppLogger(category: "core")
    private var bootstrapGeneration: UInt64 = 0
    private var startupTask: Task<Void, Never>?
    private var startupTaskGeneration: UInt64?
    private nonisolated static let defaultCoreFactory: @Sendable (IOSMinifluxCredentials) throws -> Flux = { try makeCore($0) }
    private nonisolated static let defaultAccountValidator: @Sendable (IOSMinifluxCredentials) throws -> AccountValidationAttempt = { validateAccount($0) }
    private nonisolated static let defaultLocalStateRebuilder: @Sendable (Flux) throws -> SyncCompleted = { try $0.rebuildLocalState() }

    init(
        credentialStore: IOSCredentialStoreProtocol = IOSKeychainCredentialStore(),
        coreSessionExecutionCoordinator: IOSCoreSessionExecutionCoordinator? = nil,
        coreFactory: @escaping @Sendable (IOSMinifluxCredentials) throws -> Flux = CoreBootstrapper.defaultCoreFactory,
        accountValidator: @escaping @Sendable (IOSMinifluxCredentials) throws -> AccountValidationAttempt = CoreBootstrapper.defaultAccountValidator,
        localStateRebuilder: @escaping @Sendable (Flux) throws -> SyncCompleted = CoreBootstrapper.defaultLocalStateRebuilder,
        defaults: UserDefaults = .standard
    ) {
        self.credentialStore = credentialStore
        self.coreSessionExecutionCoordinator =
            coreSessionExecutionCoordinator ?? IOSCoreSessionExecutionCoordinator()
        self.coreFactory = coreFactory
        self.accountValidator = accountValidator
        self.localStateRebuilder = localStateRebuilder
        self.defaults = defaults
    }

    func start() async {
        if let startupTask {
            await startupTask.value
            return
        }
        guard case .starting = state else { return }

        let generation = nextBootstrapGeneration()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performStartup(generation: generation)
        }
        startupTask = task
        startupTaskGeneration = generation
        await task.value

        if startupTaskGeneration == generation {
            startupTask = nil
            startupTaskGeneration = nil
        }
    }

    /// Idempotent readiness entry point for both normal app startup and later
    /// headless/background launch paths. Concurrent callers await the same
    /// in-flight bootstrap instead of constructing a second Core.
    @discardableResult
    func ensureStarted() async -> Flux? {
        if let core { return core }
        await start()
        return core
    }

    private func performStartup(generation: UInt64) async {
        do {
            guard let stored = try credentialStore.load() else {
                guard generation == bootstrapGeneration else { return }
                state = .accountRequired
                return
            }
            credentials = stored
            serverVersion = persistedServerVersion(for: stored)
            _ = try await activate(stored, persist: false, generation: generation)
        } catch IOSCredentialStoreError.temporarilyUnavailable {
            // Before the first unlock after reboot, Keychain access can be
            // unavailable to a background launch. Keep startup retryable rather
            // than presenting a broken-account error. A later app-active or
            // background readiness request will retry the same bootstrap path.
            guard generation == bootstrapGeneration else { return }
            state = .starting
            logger.info("Core startup deferred until protected credentials become available.")
        } catch {
            guard generation == bootstrapGeneration else { return }
            state = .recoverableError(Self.safeMessage(for: error))
            logger.error("Core startup failed: \(String(reflecting: error))")
        }
    }

    func retry() async {
        _ = nextBootstrapGeneration()
        state = .starting
        await start()
    }

    func mutationDeliveryPreference() async -> Result<Bool, Error> {
        guard let activeCore = core else {
            return .failure(SettingsAccessError.coreUnavailable)
        }
        guard let result = await coreSessionExecutionCoordinator.responsiveResult(
            for: activeCore,
            { try activeCore.coreSettings().deliveryMode == .live }
        ) else {
            return .failure(SettingsAccessError.sessionUnavailable)
        }
        return result
    }

    func setMutationDeliveryPreference(_ live: Bool) async -> Result<Void, Error> {
        guard let activeCore = core else {
            return .failure(SettingsAccessError.coreUnavailable)
        }
        guard let result = await coreSessionExecutionCoordinator.responsiveResult(
            for: activeCore,
            { try activeCore.setDeliveryMode(mode: live ? .live : .deferred) }
        ) else {
            return .failure(SettingsAccessError.sessionUnavailable)
        }
        return result
    }

    func readArticleRetentionPreference() async -> Result<ReadArticleRetention, Error> {
        guard let activeCore = core else {
            return .failure(SettingsAccessError.coreUnavailable)
        }
        guard let result = await coreSessionExecutionCoordinator.responsiveResult(
            for: activeCore,
            { try activeCore.coreSettings().retention }
        ) else {
            return .failure(SettingsAccessError.sessionUnavailable)
        }
        return result
    }

    func setReadArticleRetentionPreference(
        _ retention: ReadArticleRetention
    ) async -> Result<Void, Error> {
        guard let activeCore = core else {
            return .failure(SettingsAccessError.coreUnavailable)
        }
        guard let result = await coreSessionExecutionCoordinator.responsiveResult(
            for: activeCore,
            { try activeCore.setRetention(retention: retention) }
        ) else {
            return .failure(SettingsAccessError.sessionUnavailable)
        }
        return result
    }

    func detailCharacterLimitPreference() async -> Result<UInt32, Error> {
        guard let activeCore = core else {
            return .failure(SettingsAccessError.coreUnavailable)
        }
        guard let result = await coreSessionExecutionCoordinator.responsiveResult(
            for: activeCore,
            { try activeCore.coreSettings().detailCharacterLimit }
        ) else {
            return .failure(SettingsAccessError.sessionUnavailable)
        }
        return result
    }

    func setDetailCharacterLimitPreference(
        _ limit: UInt32
    ) async -> Result<Void, Error> {
        guard let activeCore = core else {
            return .failure(SettingsAccessError.coreUnavailable)
        }
        guard let result = await coreSessionExecutionCoordinator.responsiveResult(
            for: activeCore,
            { try activeCore.setDetailCharacterLimit(limit: limit) }
        ) else {
            return .failure(SettingsAccessError.sessionUnavailable)
        }
        return result
    }

    func mediaSettings() async -> Result<CoreSettings, Error> {
        guard let activeCore = core else {
            return .failure(SettingsAccessError.coreUnavailable)
        }
        guard let result = await coreSessionExecutionCoordinator.responsiveResult(
            for: activeCore,
            { try activeCore.coreSettings() }
        ) else {
            return .failure(SettingsAccessError.sessionUnavailable)
        }
        return result
    }

    func downloadedMediaSummary() async -> Result<DownloadedMediaSummary, Error> {
        guard let activeCore = core else {
            return .failure(SettingsAccessError.coreUnavailable)
        }
        guard let result = await coreSessionExecutionCoordinator.responsiveResult(
            for: activeCore,
            { try activeCore.downloadedMediaSummary() }
        ) else {
            return .failure(SettingsAccessError.sessionUnavailable)
        }
        return result
    }

    func requestAllDownloadDeletions() async -> Result<UInt64, Error> {
        guard let activeCore = core else {
            return .failure(SettingsAccessError.coreUnavailable)
        }
        guard let result = await coreSessionExecutionCoordinator.responsiveResult(
            for: activeCore,
            { try activeCore.requestAllDownloadDeletions() }
        ) else {
            return .failure(SettingsAccessError.sessionUnavailable)
        }
        return result
    }

    func importLegacyPlayback(
        _ records: [LegacyPlaybackImport]
    ) async -> Result<LegacyPlaybackImportResult, Error> {
        guard let activeCore = core else {
            return .failure(SettingsAccessError.coreUnavailable)
        }
        guard let result = await coreSessionExecutionCoordinator.responsiveResult(
            for: activeCore,
            { try activeCore.importLegacyPlayback(records: records) }
        ) else {
            return .failure(SettingsAccessError.sessionUnavailable)
        }
        return result
    }

    func importLegacyMediaSettings(
        _ settings: IOSLegacyMediaSettingsImport
    ) async -> Result<Void, Error> {
        guard let activeCore = core else { return .failure(SettingsAccessError.coreUnavailable) }
        guard let result = await coreSessionExecutionCoordinator.responsiveResult(
            for: activeCore,
            {
                try activeCore.importLegacyMediaSettings(
                    unmeteredOnly: settings.unmeteredOnly,
                    retention: settings.retentionDays.map { .days(days: $0) },
                    deleteAfterPlayback: settings.deleteAfterPlayback
                )
            }
        ) else { return .failure(SettingsAccessError.sessionUnavailable) }
        return result
    }

    func importLegacyPolicySettings(
        backgroundSyncEnabled: Bool?,
        autoDownloadListeningList: Bool?
    ) async -> Result<Void, Error> {
        guard let activeCore = core else { return .failure(SettingsAccessError.coreUnavailable) }
        guard let result = await coreSessionExecutionCoordinator.responsiveResult(
            for: activeCore,
            { try activeCore.importLegacyPolicySettings(backgroundSyncEnabled: backgroundSyncEnabled, autoDownloadListeningList: autoDownloadListeningList) }
        ) else { return .failure(SettingsAccessError.sessionUnavailable) }
        return result
    }

    func restoreLegacyMediaArticle(articleID: Int64, enclosureID: Int64) async -> Result<Bool, Error> {
        guard let activeCore = core else { return .failure(SettingsAccessError.coreUnavailable) }
        guard let result = await coreSessionExecutionCoordinator.blockingResult(
            for: activeCore,
            { try activeCore.restoreLegacyMediaArticle(articleId: articleID, enclosureId: enclosureID) }
        ) else { return .failure(SettingsAccessError.sessionUnavailable) }
        return result
    }

    func restoreLegacyPlaybackArticle(articleID: Int64) async -> Result<Bool, Error> {
        guard let activeCore = core else { return .failure(SettingsAccessError.coreUnavailable) }
        guard let result = await coreSessionExecutionCoordinator.blockingResult(
            for: activeCore,
            { try activeCore.restoreLegacyPlaybackArticle(articleId: articleID) }
        ) else { return .failure(SettingsAccessError.sessionUnavailable) }
        return result
    }

    func restoreLegacyLocalPlaybackArticle(
        _ snapshot: LegacyPlaybackArticleImport
    ) async -> Result<Bool, Error> {
        guard let activeCore = core else { return .failure(SettingsAccessError.coreUnavailable) }
        let legacy = LegacyLocalPlaybackArticle(
            articleId: snapshot.articleID,
            feedId: snapshot.feedID,
            title: snapshot.title,
            url: snapshot.url,
            commentsUrl: snapshot.commentsURL,
            publishedAt: snapshot.publishedAt,
            isRead: snapshot.isRead,
            isStarred: snapshot.isStarred,
            rawHtmlContent: snapshot.rawHTMLContent,
            readingTimeMinutes: snapshot.readingTimeMinutes,
            preview: snapshot.preview,
            imageUrl: snapshot.imageURL,
            enclosureId: snapshot.enclosureID,
            enclosureUrl: snapshot.enclosureURL,
            enclosureMimeType: snapshot.enclosureMimeType
        )
        guard let result = await coreSessionExecutionCoordinator.responsiveResult(
            for: activeCore,
            { try activeCore.restoreLegacyLocalPlaybackArticle(snapshot: legacy) }
        ) else { return .failure(SettingsAccessError.sessionUnavailable) }
        return result
    }

    func repairLegacyDownloadMetadata() async -> Result<LegacyMediaRepairResult, Error> {
        guard let activeCore = core else { return .failure(SettingsAccessError.coreUnavailable) }
        guard let result = await coreSessionExecutionCoordinator.blockingResult(
            for: activeCore,
            { try activeCore.repairLegacyDownloadMetadata() }
        ) else { return .failure(SettingsAccessError.sessionUnavailable) }
        return result
    }

    func importLegacyDownload(
        enclosureID: Int64,
        localFile: String,
        fileSizeBytes: UInt64
    ) async -> Result<LegacyDownloadImportOutcome, Error> {
        guard let activeCore = core else { return .failure(SettingsAccessError.coreUnavailable) }
        guard let result = await coreSessionExecutionCoordinator.responsiveResult(
            for: activeCore,
            { try activeCore.importLegacyDownload(enclosureId: enclosureID, localFile: localFile, fileSizeBytes: fileSizeBytes) }
        ) else { return .failure(SettingsAccessError.sessionUnavailable) }
        return result
    }

    func importLegacyFeedOpenInMiniflux(
        feedID: Int64
    ) async -> Result<LegacyFeedOpenInMinifluxImportOutcome, Error> {
        guard let activeCore = core else { return .failure(SettingsAccessError.coreUnavailable) }
        guard let result = await coreSessionExecutionCoordinator.responsiveResult(
            for: activeCore,
            { try activeCore.importLegacyFeedOpenInMiniflux(feedId: feedID) }
        ) else { return .failure(SettingsAccessError.sessionUnavailable) }
        return result
    }

    func setDownloadNetworkPolicyPreference(
        _ policy: DownloadNetworkPolicy
    ) async -> Result<Void, Error> {
        await updateMediaSetting {
            try $0.setDownloadNetworkPolicy(policy: policy)
        }
    }

    func setDownloadRetentionPreference(
        _ retention: DownloadRetention
    ) async -> Result<Void, Error> {
        await updateMediaSetting {
            try $0.setDownloadRetention(retention: retention)
        }
    }

    func setDeleteAfterPlaybackPreference(
        _ enabled: Bool
    ) async -> Result<Void, Error> {
        await updateMediaSetting {
            try $0.setDeleteAfterPlayback(enabled: enabled)
        }
    }

    func setAutoDownloadListeningListPreference(
        _ enabled: Bool
    ) async -> Result<Void, Error> {
        await updateMediaSetting {
            try $0.setAutoDownloadListeningList(enabled: enabled)
        }
    }

    func setRemoveCompletedListeningListPreference(
        _ enabled: Bool
    ) async -> Result<Void, Error> {
        await updateMediaSetting {
            try $0.setRemoveCompletedListeningList(enabled: enabled)
        }
    }

    private func updateMediaSetting(
        _ change: @escaping @Sendable (Flux) throws -> Void
    ) async -> Result<Void, Error> {
        guard let activeCore = core else {
            return .failure(SettingsAccessError.coreUnavailable)
        }
        guard let result = await coreSessionExecutionCoordinator.responsiveResult(
            for: activeCore,
            { try change(activeCore) }
        ) else {
            return .failure(SettingsAccessError.sessionUnavailable)
        }
        return result
    }

    func configurationSnapshotForBackup() async throws -> ConfigurationSnapshot {
        guard let activeCore = core else {
            throw ConfigurationBackupRestoreError.noConfiguredAccount
        }
        guard let result = await coreSessionExecutionCoordinator.responsiveResult(
            for: activeCore,
            { try activeCore.configurationSnapshot() }
        ) else {
            throw ConfigurationBackupRestoreError.sessionUnavailable
        }
        return try result.get()
    }

    /// Applies a Core-parsed iOS configuration backup without contacting
    /// Miniflux. Existing-session replacement is transactional through the
    /// authoritative Core replace operation plus credential rollback. A fresh
    /// install can also adopt a backup without first configuring an account.
    func restoreConfigurationBackup(
        _ restored: ConfigBackupRestoreModel,
        customHeaders: [IOSCustomHTTPHeader]
    ) async throws {
        guard !isConfiguring, localStateRebuildState != .rebuilding else {
            throw ConfigurationBackupRestoreError.busy
        }

        let replacementCredentials = IOSMinifluxCredentials(
            server: restored.account.installationBase,
            apiKey: restored.account.apiKey,
            customHeaders: customHeaders
        )
        let generation = nextBootstrapGeneration()
        isConfiguring = true
        defer { isConfiguring = false }
        validationMessage = nil
        validationDiagnostic = nil

        guard let activeCore = core else {
            try await restoreConfigurationBackupIntoFreshSession(
                restored,
                credentials: replacementCredentials,
                generation: generation
            )
            return
        }

        let previousCredentials = try credentialStore.load()
        guard let previousCredentials else {
            throw ConfigurationBackupRestoreError.noConfiguredAccount
        }

        guard let snapshotResult = await coreSessionExecutionCoordinator.responsiveResult(
            for: activeCore,
            { try activeCore.configurationSnapshot() }
        ) else {
            throw ConfigurationBackupRestoreError.sessionUnavailable
        }
        let previousSnapshot = try snapshotResult.get()

        await prepareForCoreReplacement?()
        await coreSessionExecutionCoordinator.quiesce()
        guard generation == bootstrapGeneration else {
            coreSessionExecutionCoordinator.resume(activeCore)
            onCoreReplacementAborted?()
            throw ConfigurationBackupRestoreError.busy
        }

        guard let replaceResult = await coreSessionExecutionCoordinator.exclusiveBlockingResult(
            for: activeCore,
            {
                try activeCore.replaceConfiguration(
                    installationBase: restored.account.installationBase,
                    coreSettings: restored.coreSettings,
                    feedPreferences: restored.feedPreferences
                )
            }
        ) else {
            coreSessionExecutionCoordinator.resume(activeCore)
            onCoreReplacementAborted?()
            throw ConfigurationBackupRestoreError.sessionUnavailable
        }

        do {
            try replaceResult.get()
            try credentialStore.save(replacementCredentials)

            let factory = coreFactory
            let created = await AppleCoreExecution.shared.responsiveResult {
                try factory(replacementCredentials)
            }
            guard generation == bootstrapGeneration else {
                throw ConfigurationBackupRestoreError.busy
            }
            let configuredCore = try created.get()

            defaults.set(true, forKey: DefaultsKey.mutationDeliveryDefaultApplied)
            clearPersistedServerVersion()
            IOSAppDiagnostics.shared.setSensitiveValues(
                [replacementCredentials.apiKey]
                    + replacementCredentials.customHeaders.map(\.value)
            )

            coreSessionExecutionCoordinator.deactivate()
            coreSessionExecutionCoordinator.activate(configuredCore)
            core = configuredCore
            credentials = replacementCredentials
            serverVersion = nil
            localStateRebuildState = .idle
            coreRevision &+= 1
            state = .ready(String(localized: "Initialized"))
            onCoreChanged?(configuredCore)
        } catch {
            let rolledBack = await rollbackConfigurationBackupRestore(
                activeCore: activeCore,
                snapshot: previousSnapshot,
                credentials: previousCredentials
            )
            guard rolledBack else {
                coreSessionExecutionCoordinator.deactivate()
                core = nil
                credentials = nil
                serverVersion = nil
                coreRevision &+= 1
                state = .recoverableError(
                    String(localized: "Configuration restore rollback failed.")
                )
                onCoreChanged?(nil)
                throw ConfigurationBackupRestoreError.rollbackFailed
            }
            throw error
        }
    }

    func syncAfterConfigurationRestore() async -> Bool {
        guard let activeCore = core else { return false }
        guard let result = await coreSessionExecutionCoordinator.blockingResult(
            for: activeCore,
            { try activeCore.sync(reason: .manual) }
        ) else {
            return false
        }
        if case .success = result { return true }
        return false
    }

    private func restoreConfigurationBackupIntoFreshSession(
        _ restored: ConfigBackupRestoreModel,
        credentials replacementCredentials: IOSMinifluxCredentials,
        generation: UInt64
    ) async throws {
        let factory = coreFactory
        let created = await AppleCoreExecution.shared.responsiveResult {
            try factory(replacementCredentials)
        }
        guard generation == bootstrapGeneration else {
            throw ConfigurationBackupRestoreError.busy
        }
        let configuredCore = try created.get()

        let replacement = await AppleCoreExecution.shared.blockingResult {
            try configuredCore.replaceConfiguration(
                installationBase: restored.account.installationBase,
                coreSettings: restored.coreSettings,
                feedPreferences: restored.feedPreferences
            )
        }
        do {
            try replacement.get()
            try credentialStore.save(replacementCredentials)
        } catch {
            _ = try? await AppleCoreExecution.shared.blocking {
                try configuredCore.resetCoreState()
            }
            throw error
        }

        defaults.set(true, forKey: DefaultsKey.mutationDeliveryDefaultApplied)
        clearPersistedServerVersion()
        IOSAppDiagnostics.shared.setSensitiveValues(
            [replacementCredentials.apiKey]
                + replacementCredentials.customHeaders.map(\.value)
        )
        coreSessionExecutionCoordinator.activate(configuredCore)
        core = configuredCore
        credentials = replacementCredentials
        serverVersion = nil
        localStateRebuildState = .idle
        coreRevision &+= 1
        state = .ready(String(localized: "Initialized"))
        onCoreChanged?(configuredCore)
    }

    private func rollbackConfigurationBackupRestore(
        activeCore: Flux,
        snapshot: ConfigurationSnapshot,
        credentials previousCredentials: IOSMinifluxCredentials
    ) async -> Bool {
        guard let rollback = await coreSessionExecutionCoordinator.exclusiveBlockingResult(
            for: activeCore,
            {
                try activeCore.replaceConfiguration(
                    installationBase: snapshot.installationBase,
                    coreSettings: snapshot.coreSettings,
                    feedPreferences: snapshot.feedPreferences
                )
            }
        ), case .success = rollback else {
            return false
        }

        do {
            try credentialStore.save(previousCredentials)
        } catch {
            return false
        }

        IOSAppDiagnostics.shared.setSensitiveValues(
            [previousCredentials.apiKey] + previousCredentials.customHeaders.map(\.value)
        )
        coreSessionExecutionCoordinator.resume(activeCore)
        onCoreReplacementAborted?()
        return true
    }

    func configure(server: String, apiKey: String, headers: [IOSCustomHTTPHeader]) async {
        guard !isConfiguring, localStateRebuildState != .rebuilding else { return }
        localStateRebuildState = .idle
        let generation = nextBootstrapGeneration()
        isConfiguring = true
        defer { isConfiguring = false }
        validationMessage = nil
        validationDiagnostic = nil
        let proposed = IOSMinifluxCredentials(server: server.trimmingCharacters(in: .whitespacesAndNewlines), apiKey: apiKey, customHeaders: headers)
        guard !proposed.server.isEmpty, !proposed.apiKey.isEmpty else {
            validationMessage = String(localized: "Enter both a Miniflux server URL and API key.")
            return
        }
        let validator = accountValidator
        let validation = await AppleCoreExecution.shared.blockingResult {
            try validator(proposed)
        }
        guard generation == bootstrapGeneration else { return }
        switch validation {
        case let .failure(error): validationMessage = IOSAccountValidationPresentation.message(for: IOSAccountValidationPresentation.failure(for: error))
        case let .success(attempt):
            validationDiagnostic = attempt.diagnostic
            if let error = attempt.error {
                validationMessage = IOSAccountValidationPresentation.message(for: IOSAccountValidationPresentation.failure(for: error))
                return
            }
            guard let result = attempt.result else {
                validationMessage = String(localized: "The Miniflux server returned an unexpected response.")
                validationDiagnostic = nil
                return
            }
            let normalized = IOSMinifluxCredentials(server: result.installationBase, apiKey: proposed.apiKey, customHeaders: proposed.customHeaders)
            do {
                let previous = credentials
                try credentialStore.save(normalized)
                do {
                    guard try await activate(normalized, persist: false, generation: generation) else { return }
                    persistServerVersion(result.version, for: normalized)
                } catch {
                    if let previous { try? credentialStore.save(previous) } else { try? credentialStore.remove() }
                    throw error
                }
            } catch { validationMessage = String(localized: "The account could not be activated. Your previous account is still active.") }
        }
    }

    func rebuildLocalState() async {
        guard localStateRebuildState != .rebuilding else { return }
        guard let activeCore = core else {
            localStateRebuildState = .failed
            return
        }

        let generation = nextBootstrapGeneration()
        localStateRebuildState = .rebuilding
        validationMessage = nil

        // Manual Sync owns presentation work outside the app-wide Core gate.
        // Quiesce that lifecycle first, then close admission for every other
        // foreground/background Core caller before invalidating projections.
        await prepareForCoreReplacement?()
        await coreSessionExecutionCoordinator.quiesce()
        guard generation == bootstrapGeneration else {
            localStateRebuildState = .idle
            return
        }

        prepareForLocalStateRebuild?()

        let rebuilder = localStateRebuilder
        guard let result = await coreSessionExecutionCoordinator.exclusiveBlockingResult(
            for: activeCore,
            { try rebuilder(activeCore) }
        ) else {
            guard generation == bootstrapGeneration else {
                localStateRebuildState = .idle
                return
            }
            coreSessionExecutionCoordinator.resume(activeCore)
            onLocalStateRebuildFinished?(activeCore)
            localStateRebuildState = .failed
            return
        }

        guard generation == bootstrapGeneration else {
            // A newer account/session lifecycle operation now owns the quiesced
            // Core. Do not reopen admission or reattach stale presentation.
            localStateRebuildState = .idle
            return
        }

        coreSessionExecutionCoordinator.resume(activeCore)
        onLocalStateRebuildFinished?(activeCore)

        switch result {
        case .success:
            localStateRebuildState = .succeeded
        case let .failure(error):
            localStateRebuildState = .failed
            logger.error(
                "Local state rebuild failed after destructive reset: \(String(reflecting: error))"
            )
        }
    }

    func removeAccount() async {
        guard localStateRebuildState != .rebuilding else { return }
        let generation = nextBootstrapGeneration()
        guard let activeCore = core else {
            try? credentialStore.remove()
            clearPersistedServerVersion()
            credentials = nil
            serverVersion = nil
            state = .accountRequired
            return
        }

        await prepareForCoreReplacement?()
        await coreSessionExecutionCoordinator.quiesce()
        guard generation == bootstrapGeneration else {
            coreSessionExecutionCoordinator.resume(activeCore)
            return
        }

        do {
            try await AppleCoreExecution.shared.responsive {
                try activeCore.removeAccountState()
            }
            guard generation == bootstrapGeneration else {
                coreSessionExecutionCoordinator.resume(activeCore)
                return
            }
            try credentialStore.remove()
            clearPersistedServerVersion()
            deactivateAfterCoreQuiescence()
            localStateRebuildState = .idle
            state = .accountRequired
        } catch {
            guard generation == bootstrapGeneration else { return }
            coreSessionExecutionCoordinator.resume(activeCore)
            onCoreReplacementAborted?()
            validationMessage = String(localized: "The account could not be removed.")
        }
    }

    var pathsDescription: String {
        guard let paths = try? CorePaths(createDirectories: false) else { return String(localized: "Unavailable") }
        return "Application Support: \(paths.persistentData.path)\nCaches: \(paths.cache.path)\nMedia: \(paths.media.path)"
    }

    private func activate(_ account: IOSMinifluxCredentials, persist: Bool, generation: UInt64) async throws -> Bool {
        if persist { try credentialStore.save(account) }

        let previousCore = core
        let replacingExistingCore = previousCore != nil
        if let previousCore {
            await prepareForCoreReplacement?()
            await coreSessionExecutionCoordinator.quiesce()
            guard generation == bootstrapGeneration else {
                coreSessionExecutionCoordinator.resume(previousCore)
                return false
            }
        }

        IOSAppDiagnostics.shared.setSensitiveValues(
            [account.apiKey] + account.customHeaders.map(\.value)
        )

        let factory = coreFactory
        let result = await AppleCoreExecution.shared.responsiveResult {
            try factory(account)
        }
        guard generation == bootstrapGeneration else { return false }

        let configuredCore: Flux
        do {
            configuredCore = try result.get()
        } catch {
            if let previousCore {
                coreSessionExecutionCoordinator.resume(previousCore)
                onCoreReplacementAborted?()
            }
            throw error
        }

        if !defaults.bool(forKey: DefaultsKey.mutationDeliveryDefaultApplied) {
            let defaultResult = await AppleCoreExecution.shared.responsiveResult {
                try configuredCore.setDeliveryMode(mode: .live)
            }
            guard generation == bootstrapGeneration else { return false }
            do {
                try defaultResult.get()
                defaults.set(true, forKey: DefaultsKey.mutationDeliveryDefaultApplied)
            } catch {
                if let previousCore {
                    coreSessionExecutionCoordinator.resume(previousCore)
                    onCoreReplacementAborted?()
                }
                throw error
            }
        }

        if replacingExistingCore {
            coreSessionExecutionCoordinator.deactivate()
        }
        coreSessionExecutionCoordinator.activate(configuredCore)
        core = configuredCore
        credentials = account
        localStateRebuildState = .idle
        coreRevision &+= 1
        state = .ready(String(localized: "Initialized"))
        onCoreChanged?(configuredCore)
        return true
    }

    func deactivate() async {
        let generation = nextBootstrapGeneration()
        if let activeCore = core {
            await prepareForCoreReplacement?()
            await coreSessionExecutionCoordinator.quiesce()
            guard generation == bootstrapGeneration else {
                coreSessionExecutionCoordinator.resume(activeCore)
                return
            }
        }
        deactivateAfterCoreQuiescence()
    }

    private func deactivateAfterCoreQuiescence() {
        if core != nil {
            coreSessionExecutionCoordinator.deactivate()
        }
        core = nil
        coreRevision &+= 1
        credentials = nil
        serverVersion = nil
        onCoreChanged?(nil)
    }

    private func persistedServerVersion(
        for account: IOSMinifluxCredentials
    ) -> String? {
        guard defaults.string(forKey: DefaultsKey.accountInfoServerBase) == account.server else {
            return nil
        }
        return IOSAccountInformationPresentation.normalizedServerVersion(
            defaults.string(forKey: DefaultsKey.accountInfoServerVersion)
        )
    }

    private func persistServerVersion(
        _ version: String,
        for account: IOSMinifluxCredentials
    ) {
        defaults.set(account.server, forKey: DefaultsKey.accountInfoServerBase)
        if let normalized =
            IOSAccountInformationPresentation.normalizedServerVersion(version) {
            defaults.set(normalized, forKey: DefaultsKey.accountInfoServerVersion)
            serverVersion = normalized
        } else {
            defaults.removeObject(forKey: DefaultsKey.accountInfoServerVersion)
            serverVersion = nil
        }
    }

    private func clearPersistedServerVersion() {
        defaults.removeObject(forKey: DefaultsKey.accountInfoServerBase)
        defaults.removeObject(forKey: DefaultsKey.accountInfoServerVersion)
    }

    private func nextBootstrapGeneration() -> UInt64 {
        bootstrapGeneration &+= 1
        // The underlying stale task may still be unwinding on AppleCoreExecution,
        // but generation guards make its publication inert. Clearing only this
        // reference allows an explicit retry/reconfiguration to start a new
        // bootstrap without waiting for stale synchronous work.
        startupTask = nil
        startupTaskGeneration = nil
        return bootstrapGeneration
    }

    private nonisolated static func makeCore(_ account: IOSMinifluxCredentials) throws -> Flux {
        let paths = try CorePaths()
        return try Flux.initializeWithDiagnostics(
            config: InitializationConfig(
                persistentData: paths.persistentData.path,
                cache: paths.cache.path,
                media: paths.media.path,
                baseUrl: account.server,
                apiKey: account.apiKey,
                customHeaders: account.customHeaders.map {
                    HttpHeader(name: $0.name, value: $0.value)
                }
            ),
            listener: IOSCoreDiagnosticListener.shared
        )
    }

    private nonisolated static func validateAccount(_ account: IOSMinifluxCredentials) -> AccountValidationAttempt {
        validateMinifluxAccountWithDiagnostic(
            serverUrl: account.server,
            apiKey: account.apiKey,
            customHeaders: account.customHeaders.map { HttpHeader(name: $0.name, value: $0.value) }
        )
    }

    private static func safeMessage(for error: Error) -> String {
        IOSErrorPresentation.message(for: error, context: .startup)
    }
}

private struct CorePaths {
    let persistentData: URL
    let cache: URL
    let media: URL

    init(createDirectories: Bool = true) throws {
        let fileManager = FileManager.default
        guard let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { throw CocoaError(.fileNoSuchFile) }
        let namespace = (Bundle.main.object(forInfoDictionaryKey: "FluxStorageNamespace") as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "FluxNewsNativeDev"
        persistentData = applicationSupport.appendingPathComponent("\(namespace)/Core", isDirectory: true)
        cache = caches.appendingPathComponent("\(namespace)/CoreCache", isDirectory: true)
        media = applicationSupport.appendingPathComponent("\(namespace)/Media", isDirectory: true)
        if createDirectories {
            for directory in [persistentData, cache, media] { try fileManager.createDirectory(at: directory, withIntermediateDirectories: true) }
        }
    }
}
