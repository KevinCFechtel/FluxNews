import Foundation
import SwiftUI

enum IOSLegacyAccountMigrationOutcome: Equatable {
    case nativeAccountWins
    case alreadyCompleted
    case noLegacyAccount
    case imported
    case retryableFailure
}

enum IOSLegacyMediaSettingsMigrationOutcome: Equatable {
    case notEligible
    case alreadyCompleted
    case imported
    case retryableFailure
}

enum IOSLegacyPlaybackMigrationOutcome: Equatable {
    case notEligible
    case alreadyCompleted
    case imported
    case retryableFailure
}

enum IOSLegacyDownloadMigrationOutcome: Equatable {
    case notEligible, alreadyCompleted, imported, retryableFailure
}

enum IOSLegacyFeedPreferenceMigrationOutcome: Equatable {
    case imported
    case alreadyCompleted
    case notEligible
    case retryableFailure
}

enum IOSLegacyGlobalPreferencesMigrationOutcome: Equatable {
    case notEligible
    case alreadyCompleted
    case imported
    case retryableFailure
}

enum IOSLegacySettingsFollowupMigrationOutcome: Equatable {
    case notEligible, alreadyCompleted, imported, retryableFailure
}

enum IOSLegacyToolbarMigrationOutcome: Equatable {
    case notEligible, alreadyCompleted, nativeConfigurationWins, noLegacyConfiguration, imported, retryableFailure
}

enum IOSLegacyWidgetDefaultsMigrationOutcome: Equatable {
    case notEligible, alreadyCompleted, nativeConfigurationWins, noLegacyConfiguration, imported, retryableFailure
}

struct IOSLegacyMediaSettingsImport: Equatable {
    let unmeteredOnly: Bool?
    let deleteAfterPlayback: Bool?
    let retentionDays: UInt32?

    var isEmpty: Bool {
        unmeteredOnly == nil && deleteAfterPlayback == nil && retentionDays == nil
    }

    static func parse(_ values: [String: String]) -> Self {
        func parseBool(_ key: String) -> Bool? {
            switch values[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true": return true
            case "false": return false
            default: return nil
            }
        }

        let retentionDays = values["audioDownloadRetentionDays"]
            .flatMap { UInt32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .flatMap { $0 > 0 ? $0 : nil }

        return Self(
            unmeteredOnly: parseBool("downloadAudioOnlyOnWifi"),
            deleteAfterPlayback: parseBool("deleteAudioAfterPlayback"),
            retentionDays: retentionDays
        )
    }
}

@MainActor
final class IOSLegacyMigrationCoordinator {
    private enum DefaultsKey {
        static let accountMigrationCompleted = "FluxNews.iOS.legacyMigration.account.v1.completed"
        static let migratedAccountServer = "FluxNews.iOS.legacyMigration.account.v1.server"
        static let mediaSettingsMigrationCompleted = "FluxNews.iOS.legacyMigration.mediaSettings.v1.completed"
        static let playbackMigrationCompleted = "FluxNews.iOS.legacyMigration.playback.v1.completed"
        static let downloadMigrationCompleted = "FluxNews.iOS.legacyMigration.downloads.v1.completed"
        static let downloadVerificationV2 = "FluxNews.iOS.legacyMigration.downloads.verified.v2"
        static let metadataRepairCompleted = "FluxNews.iOS.legacyMigration.downloads.metadataRepair.v1.completed"
        static let playbackPendingReason = "FluxNews.iOS.legacyMigration.playback.pendingReason"
        static let playbackRemoteRetryAfter = "FluxNews.iOS.legacyMigration.playback.remoteRetryAfter.v1"
        static let playbackDiscardedArticleIDs = "FluxNews.iOS.legacyMigration.playback.discardedArticleIDs.v1"
        static let playbackDiscardedReason = "FluxNews.iOS.legacyMigration.playback.discardedReason.v1"
        static let downloadsPendingReason = "FluxNews.iOS.legacyMigration.downloads.pendingReason"
        static let skippedPlaybackReason = "FluxNews.iOS.legacyMigration.playback.skippedReason"
        static let skippedDownloadsReason = "FluxNews.iOS.legacyMigration.downloads.skippedReason"
        static let summaryAcknowledged = "FluxNews.iOS.legacyMigration.summary.acknowledged"
        static let completionKind = "FluxNews.iOS.legacyMigration.summary.completionKind"
        static let feedPreferenceMigrationCompleted = "FluxNews.iOS.legacyMigration.feedPreferences.v1.completed"
        static let globalPreferencesMigrationCompleted = "FluxNews.iOS.legacyMigration.globalPreferences.v1.completed"
        static let settingsFollowupLocalCompleted = "FluxNews.iOS.legacyMigration.settingsFollowup.v2.local.completed"
        static let settingsFollowupCoreCompleted = "FluxNews.iOS.legacyMigration.settingsFollowup.v2.core.completed"
        static let settingsFollowupStartupCompleted = "FluxNews.iOS.legacyMigration.settingsFollowup.v2.startup.completed"
        static let toolbarMigrationCompleted = "FluxNews.iOS.legacyMigration.toolbar.v1.completed"
        static let widgetDefaultsMigrationCompleted = "FluxNews.iOS.legacyMigration.widgetDefaults.v1.completed"
        static let removeArticlesWhenMarkedRead = "FluxNews.iOS.removeArticlesWhenMarkedRead"
        static let markReadOnScrollover = "FluxNews.iOS.markReadOnScrollover"
    }

    private let bootstrapper: CoreBootstrapper
    private let defaults: UserDefaults
    private let legacyAccountReader: () -> LegacyAccountImport?
    private let legacyMediaSettingsReader: () -> IOSLegacyMediaSettingsImport?
    private let legacyPlaybackReader: () -> [LegacyPlaybackProgressImport]?
    private let legacyPlaybackArticleReader: ([Int64]) -> [LegacyPlaybackArticleImport]
    private let legacyPlaybackLocalRestorer: ((LegacyPlaybackArticleImport) async -> Result<Bool, Error>)?
    private let legacyPlaybackRemoteRestorer: ((Int64) async -> Result<Bool, Error>)?
    private let legacyPlaybackImporter: (([LegacyPlaybackImport]) async -> Result<LegacyPlaybackImportResult, Error>)?
    private let legacyDownloadReader: () -> [LegacyDownloadImport]?
    private let legacyDownloadImporter: ((Int64, String, UInt64) async -> Result<LegacyDownloadImportOutcome, Error>)?
    private let legacyFeedOpenInMinifluxReader: () -> [LegacyFeedOpenInMinifluxImport]?
    private let legacyFeedOpenInMinifluxImporter: ((Int64) async -> Result<LegacyFeedOpenInMinifluxImportOutcome, Error>)?
    private let legacyGlobalPreferencesReader: () -> LegacyGlobalPreferencesImport?
    private let legacySettingsReader: () -> LegacySettingsImport?
    private let legacyToolbarReader: () -> LegacyToolbarImport?
    private let legacyWidgetDefaultsReader: () -> LegacyWidgetDefaultsImport?
    private let legacyWidgetDefaultsStoreContainsConfiguration: () -> Bool
    private let legacyWidgetDefaultsWriter: (WidgetContentSelection) -> Bool
    private let mediaRootProvider: () -> URL?
    private let fileManager: FileManager
    private let logger = IOSAppLogger(category: "legacy_migration")
    private var inFlight = false

    init(
        bootstrapper: CoreBootstrapper,
        defaults: UserDefaults = .standard,
        legacyAccountReader: @escaping () -> LegacyAccountImport? = LegacyStateDiscovery.readAccountImport,
        legacyMediaSettingsReader: @escaping () -> IOSLegacyMediaSettingsImport? = LegacyStateDiscovery.readMediaSettingsImport,
        legacyPlaybackReader: @escaping () -> [LegacyPlaybackProgressImport]? = LegacyStateDiscovery.readPlaybackProgressImports,
        legacyPlaybackArticleReader: @escaping ([Int64]) -> [LegacyPlaybackArticleImport] = {
            LegacyStateDiscovery.readPlaybackArticleImports(articleIDs: $0)
        },
        legacyPlaybackLocalRestorer: ((LegacyPlaybackArticleImport) async -> Result<Bool, Error>)? = nil,
        legacyPlaybackRemoteRestorer: ((Int64) async -> Result<Bool, Error>)? = nil,
        legacyPlaybackImporter: (([LegacyPlaybackImport]) async -> Result<LegacyPlaybackImportResult, Error>)? = nil,
        legacyDownloadReader: @escaping () -> [LegacyDownloadImport]? = { LegacyStateDiscovery.readDownloadImports() },
        legacyDownloadImporter: ((Int64, String, UInt64) async -> Result<LegacyDownloadImportOutcome, Error>)? = nil,
        legacyFeedOpenInMinifluxReader: @escaping () -> [LegacyFeedOpenInMinifluxImport]? = { LegacyStateDiscovery.readFeedOpenInMinifluxImports() },
        legacyFeedOpenInMinifluxImporter: ((Int64) async -> Result<LegacyFeedOpenInMinifluxImportOutcome, Error>)? = nil,
        legacyGlobalPreferencesReader: @escaping () -> LegacyGlobalPreferencesImport? = LegacyStateDiscovery.readGlobalPreferencesImport,
        legacySettingsReader: @escaping () -> LegacySettingsImport? = LegacyStateDiscovery.readSettingsImport,
        legacyToolbarReader: @escaping () -> LegacyToolbarImport? = LegacyStateDiscovery.readToolbarImport,
        legacyWidgetDefaultsReader: @escaping () -> LegacyWidgetDefaultsImport? = LegacyStateDiscovery.readWidgetDefaultsImport,
        legacyWidgetDefaultsStoreContainsConfiguration: @escaping () -> Bool = {
            WidgetLegacyDefaultStore.containsConfiguration()
        },
        legacyWidgetDefaultsWriter: @escaping (WidgetContentSelection) -> Bool = {
            WidgetLegacyDefaultStore.save($0)
        },
        mediaRootProvider: @escaping () -> URL? = { IOSMediaTransferPathConfiguration.mediaRootURL },
        fileManager: FileManager = .default
    ) {
        self.bootstrapper = bootstrapper
        self.defaults = defaults
        self.legacyAccountReader = legacyAccountReader
        self.legacyMediaSettingsReader = legacyMediaSettingsReader
        self.legacyPlaybackReader = legacyPlaybackReader
        self.legacyPlaybackArticleReader = legacyPlaybackArticleReader
        self.legacyPlaybackLocalRestorer = legacyPlaybackLocalRestorer
        self.legacyPlaybackRemoteRestorer = legacyPlaybackRemoteRestorer
        self.legacyPlaybackImporter = legacyPlaybackImporter
        self.legacyDownloadReader = legacyDownloadReader
        self.legacyDownloadImporter = legacyDownloadImporter
        self.legacyFeedOpenInMinifluxReader = legacyFeedOpenInMinifluxReader
        self.legacyFeedOpenInMinifluxImporter = legacyFeedOpenInMinifluxImporter
        self.legacyGlobalPreferencesReader = legacyGlobalPreferencesReader
        self.legacySettingsReader = legacySettingsReader
        self.legacyToolbarReader = legacyToolbarReader
        self.legacyWidgetDefaultsReader = legacyWidgetDefaultsReader
        self.legacyWidgetDefaultsStoreContainsConfiguration = legacyWidgetDefaultsStoreContainsConfiguration
        self.legacyWidgetDefaultsWriter = legacyWidgetDefaultsWriter
        self.mediaRootProvider = mediaRootProvider
        self.fileManager = fileManager
    }

    /// Imports only when native credentials are absent. The completion marker is
    /// deliberately written only after a successfully activated native account,
    /// making a terminated/failed attempt safe to retry on the next launch.
    @discardableResult
    func migrateAccountIfNeeded() async -> IOSLegacyAccountMigrationOutcome {
        guard !inFlight else { return .retryableFailure }
        inFlight = true
        defer { inFlight = false }

        do {
            if try bootstrapper.credentialStore.load() != nil {
                logger.info("Legacy account migration skipped because native credentials already exist.")
                return .nativeAccountWins
            }
        } catch IOSCredentialStoreError.temporarilyUnavailable {
            logger.info("Legacy account migration deferred until native credentials become available.")
            return .retryableFailure
        } catch {
            logger.error("Legacy account migration could not inspect native credentials: \(String(reflecting: error))")
            return .retryableFailure
        }

        if defaults.bool(forKey: DefaultsKey.accountMigrationCompleted) {
            return .alreadyCompleted
        }

        guard let legacy = legacyAccountReader() else {
            // Absence is not marked complete: production Keychain access may be
            // temporarily unavailable and a later foreground launch can retry.
            return .noLegacyAccount
        }

        let headers = legacy.customHeaders.map {
            IOSCustomHTTPHeader(name: $0.name, value: $0.value)
        }
        await bootstrapper.configure(
            server: legacy.serverURL,
            apiKey: legacy.apiKey,
            headers: headers
        )

        let importedCredentials: IOSMinifluxCredentials
        do {
            guard let stored = try bootstrapper.credentialStore.load(),
                  bootstrapper.core != nil else {
                logger.warning("Legacy account validation or activation failed; migration remains retryable.")
                return .retryableFailure
            }
            importedCredentials = stored
        } catch {
            logger.error("Legacy account activation could not be verified: \(String(reflecting: error))")
            return .retryableFailure
        }

        defaults.set(normalizedServerIdentifier(importedCredentials.server), forKey: DefaultsKey.migratedAccountServer)
        defaults.set(true, forKey: DefaultsKey.accountMigrationCompleted)
        logger.info("Legacy account copied into native account storage and activated.")
        return .imported
    }

    /// Imports retained media policies only for the exact native account created
    /// by this coordinator. Native accounts without that provenance always win.
    @discardableResult
    func migrateMediaSettingsIfNeeded() async -> IOSLegacyMediaSettingsMigrationOutcome {
        guard !inFlight else { return .retryableFailure }
        inFlight = true
        defer { inFlight = false }

        do {
            guard try isCurrentMigratedAccount() else { return .notEligible }
        } catch {
            logger.error("Legacy media settings migration could not inspect native credentials: \(String(reflecting: error))")
            return .retryableFailure
        }

        guard !defaults.bool(forKey: DefaultsKey.mediaSettingsMigrationCompleted) else {
            return .alreadyCompleted
        }
        guard let legacySettings = legacyMediaSettingsReader() else {
            return .retryableFailure
        }

        if case let .failure(error) = await bootstrapper.importLegacyMediaSettings(legacySettings) {
            return mediaSettingsWriteFailed(error)
        }
        defaults.set(true, forKey: DefaultsKey.mediaSettingsMigrationCompleted)
        logger.info("Legacy media policy settings copied into Core settings.")
        return .imported
    }

    /// Imports article-keyed Flutter progress through the authoritative Core.
    /// Local Flutter SQLite identity is preferred over Miniflux re-fetches and is
    /// accepted only for an unambiguous single-audio article. `updatedAt`
    /// remains nil because Flutter retained no timestamp.
    @discardableResult
    func migratePlaybackProgressIfNeeded() async -> IOSLegacyPlaybackMigrationOutcome {
        guard !inFlight else { return .retryableFailure }
        inFlight = true
        defer { inFlight = false }

        do {
            guard try isCurrentMigratedAccount() else { return .notEligible }
        } catch {
            logger.error("Legacy playback migration could not inspect native credentials: \(String(reflecting: error))")
            return .retryableFailure
        }
        guard !defaults.bool(forKey: DefaultsKey.playbackMigrationCompleted) else {
            return .alreadyCompleted
        }
        guard let legacyRecords = legacyPlaybackReader() else {
            return .retryableFailure
        }

        var discardedArticleIDs = Set(
            defaults.stringArray(forKey: DefaultsKey.playbackDiscardedArticleIDs)?
                .compactMap(Int64.init) ?? []
        )

        // Custom importers are test seams and intentionally keep the historical
        // behavior of bypassing Core hydration unless a restore seam is supplied.
        let shouldHydrate = legacyPlaybackImporter == nil
            || legacyPlaybackLocalRestorer != nil
            || legacyPlaybackRemoteRestorer != nil
        if shouldHydrate {
            let resumable = legacyRecords.filter {
                $0.positionMs > 0 && !discardedArticleIDs.contains($0.articleID)
            }
            let localSnapshots = Dictionary(
                uniqueKeysWithValues: legacyPlaybackArticleReader(
                    resumable.map(\.articleID)
                ).map { ($0.articleID, $0) }
            )
            let legacyDownloads = legacyDownloadReader()
            let downloadScanSucceeded = legacyDownloads != nil
            let downloadedEnclosureIDs = Set(
                legacyDownloads?.map(\.enclosureID) ?? []
            )
            let downloadedArticleIDs = Set(
                legacyDownloads?.compactMap(\.articleID) ?? []
            )
            var remoteRetryAfter = defaults.dictionary(
                forKey: DefaultsKey.playbackRemoteRetryAfter
            ) as? [String: Double] ?? [:]
            let now = Date().timeIntervalSince1970
            var retryScheduleChanged = false
            var discardedSetChanged = false
            var locallyRestored = 0
            var remotelyRestored = 0
            var remoteDeferred = 0
            var newlyDiscarded = 0

            for record in resumable {
                let retryKey = String(record.articleID)
                let snapshot = localSnapshots[record.articleID]
                let hasLegacyDownload = downloadedArticleIDs.contains(record.articleID)
                    || snapshot.map { downloadedEnclosureIDs.contains($0.enclosureID) } == true

                // Flutter SQLite is trusted as identity evidence only when the
                // corresponding legacy audio file is actually present. Progress
                // alone must never fabricate a playable historical Core item.
                var restoredLocally = false
                if hasLegacyDownload, let snapshot {
                    let localResult: Result<Bool, Error>
                    if let legacyPlaybackLocalRestorer {
                        localResult = await legacyPlaybackLocalRestorer(snapshot)
                    } else {
                        localResult = await bootstrapper.restoreLegacyLocalPlaybackArticle(snapshot)
                    }
                    if case .success(true) = localResult {
                        restoredLocally = true
                        locallyRestored += 1
                        if remoteRetryAfter.removeValue(forKey: retryKey) != nil {
                            retryScheduleChanged = true
                        }
                    }
                }
                if restoredLocally {
                    continue
                }

                if let retryAt = remoteRetryAfter[retryKey], retryAt > now {
                    remoteDeferred += 1
                    continue
                }
                if remoteRetryAfter.removeValue(forKey: retryKey) != nil {
                    retryScheduleChanged = true
                }

                let remoteResult: Result<Bool, Error>
                if let legacyPlaybackRemoteRestorer {
                    remoteResult = await legacyPlaybackRemoteRestorer(record.articleID)
                } else {
                    remoteResult = await bootstrapper.restoreLegacyPlaybackArticle(
                        articleID: record.articleID
                    )
                }
                switch remoteResult {
                case .success(true):
                    remotelyRestored += 1
                case .success(false):
                    // Core returns false only for a confirmed 404/410. When the
                    // read-only Flutter download scan also proves there is no
                    // matching local audio file, this is stale progress rather
                    // than a migration failure and can be discarded terminally.
                    if downloadScanSucceeded, !hasLegacyDownload {
                        if discardedArticleIDs.insert(record.articleID).inserted {
                            discardedSetChanged = true
                            newlyDiscarded += 1
                        }
                        if remoteRetryAfter.removeValue(forKey: retryKey) != nil {
                            retryScheduleChanged = true
                        }
                    } else {
                        // A local download or incomplete local evidence keeps the
                        // record retryable. Avoid repeated server requests on
                        // every foreground activation while preserving source data.
                        remoteRetryAfter[retryKey] = now + 86_400
                        retryScheduleChanged = true
                    }
                case .failure:
                    // Connectivity/session/identity failures are not negative
                    // evidence. A later valid migration attempt may retry.
                    break
                }
            }

            if retryScheduleChanged {
                if remoteRetryAfter.isEmpty {
                    defaults.removeObject(forKey: DefaultsKey.playbackRemoteRetryAfter)
                } else {
                    defaults.set(remoteRetryAfter, forKey: DefaultsKey.playbackRemoteRetryAfter)
                }
            }
            if discardedSetChanged {
                defaults.set(
                    discardedArticleIDs.sorted().map(String.init),
                    forKey: DefaultsKey.playbackDiscardedArticleIDs
                )
            }
            if discardedArticleIDs.isEmpty {
                defaults.removeObject(forKey: DefaultsKey.playbackDiscardedReason)
            } else {
                let count = discardedArticleIDs.count
                let noun = count == 1 ? "playback position" : "playback positions"
                defaults.set(
                    "\(count) old \(noun) discarded: no local download and no longer available on the server.",
                    forKey: DefaultsKey.playbackDiscardedReason
                )
            }
            logger.info(
                "Legacy playback hydration local=\(locallyRestored) remote=\(remotelyRestored) deferred=\(remoteDeferred) discarded_old=\(newlyDiscarded)."
            )
        }

        let records = legacyRecords
            .filter { !discardedArticleIDs.contains($0.articleID) }
            .map {
                LegacyPlaybackImport(
                    articleId: $0.articleID,
                    positionMs: $0.positionMs,
                    updatedAt: nil
                )
            }

        let result: Result<LegacyPlaybackImportResult, Error>
        if let legacyPlaybackImporter {
            result = await legacyPlaybackImporter(records)
        } else {
            result = await bootstrapper.importLegacyPlayback(records)
        }
        switch result {
        case let .success(importResult):
            logger.info(
                "Legacy playback imported=\(importResult.imported) missing=\(importResult.skippedMissing) ambiguous=\(importResult.skippedAmbiguous) existing=\(importResult.alreadyPresent)."
            )
            let outcome = Self.playbackMigrationOutcome(for: importResult)
            if outcome == .imported {
                defaults.set(true, forKey: DefaultsKey.playbackMigrationCompleted)
                defaults.removeObject(forKey: DefaultsKey.playbackPendingReason)
                defaults.removeObject(forKey: DefaultsKey.playbackRemoteRetryAfter)
            } else {
                defaults.set("\(importResult.skippedMissing) missing article(s); \(importResult.skippedAmbiguous) ambiguous audio attachment(s)", forKey: DefaultsKey.playbackPendingReason)
            }
            return outcome
        case let .failure(error):
            logger.error("Legacy playback migration remains retryable: \(String(reflecting: error))")
            return .retryableFailure
        }
    }

    @discardableResult
    func migrateDownloadsIfNeeded() async -> IOSLegacyDownloadMigrationOutcome {
        guard !inFlight else { return .retryableFailure }
        inFlight = true
        defer { inFlight = false }
        do { guard try isCurrentMigratedAccount() else { return .notEligible } }
        catch { return .retryableFailure }
        // v1 could mark an empty/misread Flutter source as completed. Re-evaluate
        // that marker once after upgrade; do not discard existing native downloads.
        guard !defaults.bool(forKey: DefaultsKey.downloadVerificationV2) else {
            await repairImportedDownloadMetadataIfNeeded()
            return .alreadyCompleted
        }
        guard let records = legacyDownloadReader() else {
            defaults.set("Legacy download source could not be read", forKey: DefaultsKey.downloadsPendingReason)
            return .retryableFailure
        }
        guard !records.isEmpty else {
            // A zero-record read is only conclusive if no old audio files exist.
            // A source-key mismatch must not silently become a green check.
            if legacyDownloadImporter == nil && LegacyStateDiscovery.hasUnmigratedAudioFiles() {
                defaults.set("Legacy audio files found but no download keys matched", forKey: DefaultsKey.downloadsPendingReason)
                defaults.set(false, forKey: DefaultsKey.downloadMigrationCompleted)
                return .retryableFailure
            }
            defaults.set(true, forKey: DefaultsKey.downloadMigrationCompleted)
            defaults.set(true, forKey: DefaultsKey.downloadVerificationV2)
            defaults.removeObject(forKey: DefaultsKey.downloadsPendingReason)
            return .imported
        }
        guard let mediaRoot = mediaRootProvider() else { return .retryableFailure }
        var hasRetryableRecord = false
        var missingCount = 0
        var failedCount = 0
        var importedCount = 0
        for record in records {
            let detectedExtension = Self.legacyAudioExtension(at: record.sourceFile)
            let reference = "downloads/legacy/enclosure-\(record.enclosureID).\(detectedExtension ?? "audio")"
            guard let sourceSize = readableRegularFileSize(at: record.sourceFile) else {
                hasRetryableRecord = true
                failedCount += 1
                continue
            }
            if legacyDownloadImporter == nil, let articleID = record.articleID {
                switch await bootstrapper.restoreLegacyMediaArticle(articleID: articleID, enclosureID: record.enclosureID) {
                case .success(true): break
                case .success(false), .failure:
                    hasRetryableRecord = true
                    missingCount += 1
                    continue
                }
            }
            let destination: URL
            let createdDestination: Bool
            do {
                destination = try MediaTransferFileLayout.destination(reference: reference, under: mediaRoot)
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !fileManager.fileExists(atPath: destination.path) {
                    let stagingDestination = destination.appendingPathExtension("partial")
                    try? fileManager.removeItem(at: stagingDestination)
                    do {
                        try fileManager.copyItem(at: record.sourceFile, to: stagingDestination)
                        try fileManager.moveItem(at: stagingDestination, to: destination)
                    } catch {
                        try? fileManager.removeItem(at: stagingDestination)
                        throw error
                    }
                    createdDestination = true
                } else {
                    createdDestination = false
                }
            } catch {
                hasRetryableRecord = true
                continue
            }
            guard let destinationSize = readableRegularFileSize(at: destination),
                  destinationSize == sourceSize else {
                hasRetryableRecord = true
                continue
            }
            let result: Result<LegacyDownloadImportOutcome, Error>
            if let legacyDownloadImporter {
                result = await legacyDownloadImporter(record.enclosureID, reference, destinationSize)
            } else {
                result = await bootstrapper.importLegacyDownload(
                    enclosureID: record.enclosureID,
                    localFile: reference,
                    fileSizeBytes: destinationSize
                )
            }
            switch result {
            case .success(.imported): importedCount += 1
            case .success(.alreadyPresent):
                // Only this run can prove that it created a file Core did not adopt.
                if createdDestination { try? fileManager.removeItem(at: destination) }
            case .success(.missingEnclosure):
                // The source remains untouched, so an unadopted copy made by this
                // run can be recreated after a later authoritative sync.
                if createdDestination { try? fileManager.removeItem(at: destination) }
                hasRetryableRecord = true
                missingCount += 1
            case .failure:
                // Retain a pre-existing or just-created copy: the operation may be
                // retried safely without changing the Flutter source.
                hasRetryableRecord = true
                failedCount += 1
            }
        }
        logger.info("Legacy downloads discovered=\(records.count) imported=\(importedCount) missing=\(missingCount) failed=\(failedCount).")
        if hasRetryableRecord {
            defaults.set("\(missingCount) missing audio attachment(s); \(failedCount) file error(s)", forKey: DefaultsKey.downloadsPendingReason)
            return .retryableFailure
        }
        defaults.set(true, forKey: DefaultsKey.downloadMigrationCompleted)
        defaults.set(true, forKey: DefaultsKey.downloadVerificationV2)
        defaults.removeObject(forKey: DefaultsKey.downloadsPendingReason)
        await repairImportedDownloadMetadataIfNeeded()
        logger.info("Legacy downloads copied into Core media storage.")
        return .imported
    }

    /// A durable, privacy-safe migration summary for the native iOS dialog.
    struct Summary: Equatable {
        let acknowledged: Bool
        let completed: Bool
        let completionKind: String
        let playbackCompleted: Bool
        let downloadsCompleted: Bool
        let playbackDetails: String
        let downloadDetails: String
        let settingsCompleted: Bool
        let accountCompleted: Bool
        let localSettingsCompleted: Bool
        let feedSettingsCompleted: Bool
        let startupCompleted: Bool
        let widgetSettingsCompleted: Bool
        var canFinishWithSkippedItems: Bool {
            settingsCompleted && (!playbackCompleted || !downloadsCompleted) &&
                (playbackCompleted || !playbackDetails.isEmpty) &&
                (downloadsCompleted || !downloadDetails.isEmpty)
        }
    }

    private func kindIsManuallySkipped() -> Bool {
        defaults.string(forKey: DefaultsKey.completionKind) == "completed_with_skipped_items"
    }

    func migrationSummary() -> Summary? {
        guard defaults.bool(forKey: DefaultsKey.accountMigrationCompleted),
              (try? isCurrentMigratedAccount()) == true else { return nil }
        let settings = [
            DefaultsKey.mediaSettingsMigrationCompleted,
            DefaultsKey.globalPreferencesMigrationCompleted,
            DefaultsKey.feedPreferenceMigrationCompleted,
            DefaultsKey.settingsFollowupLocalCompleted,
            DefaultsKey.settingsFollowupCoreCompleted,
            DefaultsKey.settingsFollowupStartupCompleted,
            DefaultsKey.toolbarMigrationCompleted,
            DefaultsKey.widgetDefaultsMigrationCompleted,
        ].allSatisfy { defaults.bool(forKey: $0) }
        let playback = defaults.bool(forKey: DefaultsKey.playbackMigrationCompleted)
        let downloads = defaults.bool(forKey: DefaultsKey.downloadMigrationCompleted)
            && (defaults.bool(forKey: DefaultsKey.downloadVerificationV2) || kindIsManuallySkipped())
        let kind = defaults.string(forKey: DefaultsKey.completionKind) ?? ""
        return Summary(
            acknowledged: defaults.bool(forKey: DefaultsKey.summaryAcknowledged),
            completed: settings && playback && downloads,
            completionKind: kind,
            playbackCompleted: playback,
            downloadsCompleted: downloads,
            playbackDetails: [
                defaults.string(forKey: DefaultsKey.skippedPlaybackReason)
                    ?? defaults.string(forKey: DefaultsKey.playbackPendingReason),
                defaults.string(forKey: DefaultsKey.playbackDiscardedReason),
            ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
            downloadDetails: defaults.string(forKey: DefaultsKey.skippedDownloadsReason)
                ?? defaults.string(forKey: DefaultsKey.downloadsPendingReason) ?? "",
            settingsCompleted: settings,
            accountCompleted: true,
            localSettingsCompleted: defaults.bool(forKey: DefaultsKey.mediaSettingsMigrationCompleted)
                && defaults.bool(forKey: DefaultsKey.globalPreferencesMigrationCompleted)
                && defaults.bool(forKey: DefaultsKey.settingsFollowupLocalCompleted)
                && defaults.bool(forKey: DefaultsKey.settingsFollowupCoreCompleted)
                && defaults.bool(forKey: DefaultsKey.toolbarMigrationCompleted),
            feedSettingsCompleted: defaults.bool(forKey: DefaultsKey.feedPreferenceMigrationCompleted),
            startupCompleted: defaults.bool(forKey: DefaultsKey.settingsFollowupStartupCompleted),
            widgetSettingsCompleted: defaults.bool(forKey: DefaultsKey.widgetDefaultsMigrationCompleted)
        )
    }

    func acknowledgeCompletedMigration() {
        guard let summary = migrationSummary(), summary.completed else { return }
        if defaults.string(forKey: DefaultsKey.completionKind) == nil {
            defaults.set("completed", forKey: DefaultsKey.completionKind)
        }
        defaults.set(true, forKey: DefaultsKey.summaryAcknowledged)
    }

    @discardableResult
    func finishMigrationWithSkippedItems() -> Bool {
        guard let summary = migrationSummary(), summary.canFinishWithSkippedItems else { return false }
        if !summary.playbackCompleted {
            defaults.set(summary.playbackDetails, forKey: DefaultsKey.skippedPlaybackReason)
            defaults.set(true, forKey: DefaultsKey.playbackMigrationCompleted)
        }
        if !summary.downloadsCompleted {
            defaults.set(summary.downloadDetails, forKey: DefaultsKey.skippedDownloadsReason)
            defaults.set(true, forKey: DefaultsKey.downloadMigrationCompleted)
        }
        defaults.set("completed_with_skipped_items", forKey: DefaultsKey.completionKind)
        defaults.set(true, forKey: DefaultsKey.summaryAcknowledged)
        logger.info("Legacy migration completed with manually skipped unresolved media entries.")
        return true
    }

    private func repairImportedDownloadMetadataIfNeeded() async {
        guard !defaults.bool(forKey: DefaultsKey.metadataRepairCompleted) else { return }
        switch await bootstrapper.repairLegacyDownloadMetadata() {
        case .success(let result):
            defaults.set(true, forKey: DefaultsKey.metadataRepairCompleted)
            logger.info("Legacy media repair scanned=\(result.scanned) recoveredArtworks=\(result.recoveredArtworks).")
        case .failure:
            logger.warning("Legacy media repair remains retryable.")
        }
    }

    @discardableResult
    func migrateFeedPreferencesIfNeeded() async -> IOSLegacyFeedPreferenceMigrationOutcome {
        guard !inFlight else { return .retryableFailure }
        inFlight = true
        defer { inFlight = false }
        do { guard try isCurrentMigratedAccount() else { return .notEligible } }
        catch { return .retryableFailure }
        guard !defaults.bool(forKey: DefaultsKey.feedPreferenceMigrationCompleted) else {
            return .alreadyCompleted
        }
        guard let records = legacyFeedOpenInMinifluxReader() else { return .retryableFailure }
        var hasRetryableRecord = false
        for record in records {
            guard record.openInMiniflux else { continue }
            let result: Result<LegacyFeedOpenInMinifluxImportOutcome, Error>
            if let legacyFeedOpenInMinifluxImporter {
                result = await legacyFeedOpenInMinifluxImporter(record.feedID)
            } else {
                result = await bootstrapper.importLegacyFeedOpenInMiniflux(feedID: record.feedID)
            }
            switch result {
            case .success(.imported), .success(.alreadyPresent): break
            case .success(.missingFeed), .failure: hasRetryableRecord = true
            }
        }
        guard !hasRetryableRecord else { return .retryableFailure }
        defaults.set(true, forKey: DefaultsKey.feedPreferenceMigrationCompleted)
        logger.info("Legacy positive Open in Miniflux feed preferences copied into Core.")
        return .imported
    }

    /// Imports each retained global preference only when the corresponding
    /// native UserDefaults key has never been written. Defaults are not
    /// presence, so explicit native false remains a native winner.
    @discardableResult
    func migrateGlobalPreferencesIfNeeded() async -> IOSLegacyGlobalPreferencesMigrationOutcome {
        guard !inFlight else { return .retryableFailure }
        inFlight = true
        defer { inFlight = false }
        do { guard try isCurrentMigratedAccount() else { return .notEligible } }
        catch { return .retryableFailure }
        guard !defaults.bool(forKey: DefaultsKey.globalPreferencesMigrationCompleted) else {
            return .alreadyCompleted
        }
        guard let legacy = legacyGlobalPreferencesReader() else { return .retryableFailure }

        if defaults.object(forKey: DefaultsKey.markReadOnScrollover) == nil,
           let markReadOnScrollover = legacy.markReadOnScrollover {
            defaults.set(markReadOnScrollover, forKey: DefaultsKey.markReadOnScrollover)
        }
        if defaults.object(forKey: DefaultsKey.removeArticlesWhenMarkedRead) == nil,
           let removeArticlesWhenMarkedRead = legacy.removeArticlesWhenMarkedRead {
            defaults.set(removeArticlesWhenMarkedRead, forKey: DefaultsKey.removeArticlesWhenMarkedRead)
        }
        defaults.set(true, forKey: DefaultsKey.globalPreferencesMigrationCompleted)
        logger.info("Legacy global preferences copied where native values were absent.")
        return .imported
    }

    /// Versioned D9-A follow-up. Local, Core, and catalog-dependent Startup
    /// completion are separate so a missing catalog item cannot lose other work.
    @discardableResult
    func migrateSettingsFollowupIfNeeded() async -> IOSLegacySettingsFollowupMigrationOutcome {
        if defaults.bool(forKey: DefaultsKey.settingsFollowupLocalCompleted),
           defaults.bool(forKey: DefaultsKey.settingsFollowupCoreCompleted),
           defaults.bool(forKey: DefaultsKey.settingsFollowupStartupCompleted) {
            return .alreadyCompleted
        }
        guard !inFlight else { return .retryableFailure }
        inFlight = true
        defer { inFlight = false }
        do { guard try isCurrentMigratedAccount() else { return .notEligible } }
        catch { return .retryableFailure }
        guard let legacy = legacySettingsReader() else { return .retryableFailure }

        var retryable = false
        if !defaults.bool(forKey: DefaultsKey.settingsFollowupLocalCompleted) {
            importLocalSettings(legacy)
            defaults.set(true, forKey: DefaultsKey.settingsFollowupLocalCompleted)
        }
        if !defaults.bool(forKey: DefaultsKey.settingsFollowupCoreCompleted) {
            switch await bootstrapper.importLegacyPolicySettings(
                backgroundSyncEnabled: legacy.backgroundSyncEnabled,
                autoDownloadListeningList: legacy.autoDownloadListeningList
            ) {
            case .success: defaults.set(true, forKey: DefaultsKey.settingsFollowupCoreCompleted)
            case .failure: retryable = true
            }
        }
        if !defaults.bool(forKey: DefaultsKey.settingsFollowupStartupCompleted) {
            switch await importStartupScope(legacy) {
            case .success: defaults.set(true, forKey: DefaultsKey.settingsFollowupStartupCompleted)
            case .failure: retryable = true
            }
        }
        if retryable { return .retryableFailure }
        return .imported
    }

    /// D9-C migration of Flutter's semantic iOS toolbar selection/order.
    /// Presence of the native array is authoritative, including an explicit
    /// empty selection. Sync and More are fixed native chrome and are never
    /// imported from Flutter.
    @discardableResult
    func migrateToolbarIfNeeded() async -> IOSLegacyToolbarMigrationOutcome {
        if defaults.bool(forKey: DefaultsKey.toolbarMigrationCompleted) {
            return .alreadyCompleted
        }
        guard !inFlight else { return .retryableFailure }
        inFlight = true
        defer { inFlight = false }

        do { guard try isCurrentMigratedAccount() else { return .notEligible } }
        catch { return .retryableFailure }

        if defaults.object(forKey: IOSArticleListActionPreferences.defaultsKey) != nil {
            defaults.set(true, forKey: DefaultsKey.toolbarMigrationCompleted)
            return .nativeConfigurationWins
        }

        guard let legacy = legacyToolbarReader() else { return .retryableFailure }
        guard let selectedActions = legacy.selectedActions else {
            defaults.set(true, forKey: DefaultsKey.toolbarMigrationCompleted)
            return .noLegacyConfiguration
        }
        defaults.set(
            selectedActions.map(\.rawValue),
            forKey: IOSArticleListActionPreferences.defaultsKey
        )
        defaults.set(true, forKey: DefaultsKey.toolbarMigrationCompleted)
        logger.info("Legacy iOS toolbar configuration copied into native action preferences.")
        return .imported
    }

    /// D9-A follow-up for the old Flutter global widget settings. The values
    /// seed only the initial AppIntent state for future native widget instances;
    /// WidgetKit remains the owner of every configured per-instance intent.
    @discardableResult
    func migrateWidgetDefaultsIfNeeded() async -> IOSLegacyWidgetDefaultsMigrationOutcome {
        if defaults.bool(forKey: DefaultsKey.widgetDefaultsMigrationCompleted) {
            return .alreadyCompleted
        }
        guard !inFlight else { return .retryableFailure }
        inFlight = true
        defer { inFlight = false }

        do { guard try isCurrentMigratedAccount() else { return .notEligible } }
        catch { return .retryableFailure }

        if legacyWidgetDefaultsStoreContainsConfiguration() {
            defaults.set(true, forKey: DefaultsKey.widgetDefaultsMigrationCompleted)
            return .nativeConfigurationWins
        }

        guard let legacy = legacyWidgetDefaultsReader() else {
            defaults.set(true, forKey: DefaultsKey.widgetDefaultsMigrationCompleted)
            return .noLegacyConfiguration
        }
        guard legacyWidgetDefaultsWriter(legacy.selection) else {
            return .retryableFailure
        }

        defaults.set(true, forKey: DefaultsKey.widgetDefaultsMigrationCompleted)
        logger.info("Legacy Flutter widget defaults copied into the native WidgetKit migration seed.")
        return .imported
    }

    private func importLocalSettings(_ legacy: LegacySettingsImport) {
        func setBool(_ value: Bool?, key: String) {
            if defaults.object(forKey: key) == nil, let value { defaults.set(value, forKey: key) }
        }
        setBool(legacy.showArticleCount, key: "FluxNews.iOS.showArticleCount")
        setBool(legacy.hideEmptyNavigationEntries, key: "FluxNews.iOS.hideEmptyNavigationEntries")
        if legacy.tabActionExpands, defaults.object(forKey: "FluxNews.clickOnNews") == nil {
            defaults.set(ClickOnNews.openDetailView.rawValue, forKey: "FluxNews.clickOnNews")
        }
        importSwipeSide(
            full: legacy.leadingFull, additional: legacy.leadingAdditional,
            fullKey: "FluxNews.iOS.leadingSwipeFull", additionalKey: "FluxNews.iOS.leadingSwipeAdditional"
        )
        importSwipeSide(
            full: legacy.trailingFull, additional: legacy.trailingAdditional,
            fullKey: "FluxNews.iOS.trailingSwipeFull", additionalKey: "FluxNews.iOS.trailingSwipeAdditional"
        )
    }

    private func importSwipeSide(
        full legacyFull: IOSArticleSwipeAction??,
        additional legacyAdditional: IOSArticleSwipeAction??,
        fullKey: String,
        additionalKey: String
    ) {
        let fullIsNative = defaults.object(forKey: fullKey) != nil
        let additionalIsNative = defaults.object(forKey: additionalKey) != nil
        guard !fullIsNative || !additionalIsNative else { return }
        let currentFull = defaults.string(forKey: fullKey).flatMap(IOSArticleSwipeAction.init(rawValue:))
        let currentAdditional = defaults.string(forKey: additionalKey).flatMap(IOSArticleSwipeAction.init(rawValue:))
        let full = fullIsNative ? currentFull : legacyFull ?? currentFull
        var additional = additionalIsNative ? currentAdditional : legacyAdditional ?? currentAdditional
        if additional == full { additional = nil }
        if !fullIsNative, legacyFull != nil { defaults.set(full?.rawValue ?? "", forKey: fullKey) }
        if !additionalIsNative, legacyAdditional != nil { defaults.set(full == nil ? "" : (additional?.rawValue ?? ""), forKey: additionalKey) }
    }

    private func importStartupScope(_ legacy: LegacySettingsImport) async -> Result<Void, Error> {
        guard defaults.object(forKey: "FluxNews.iOS.startupScope") == nil else { return .success(()) }
        guard let mode = legacy.startupMode else { return .success(()) }
        switch mode {
        case 0:
            defaults.set(StartupScopePreference.allNews.rawValue, forKey: "FluxNews.iOS.startupScope")
        case 1:
            defaults.set(StartupScopePreference.starred.rawValue, forKey: "FluxNews.iOS.startupScope")
        case 2:
            guard let id = legacy.startupCategoryID, id > 0 else { return .success(()) }
            guard let core = bootstrapper.core,
                  let catalogResult = await bootstrapper.coreSessionExecutionCoordinator.responsiveResult(for: core, { try core.navigationCatalog() }) else {
                return .failure(CoreBootstrapper.SettingsAccessError.coreUnavailable)
            }
            guard case let .success(catalog) = catalogResult else { return .failure(CoreBootstrapper.SettingsAccessError.coreUnavailable) }
            guard catalog.categories.contains(where: { $0.id == id }) else { return .failure(CoreBootstrapper.SettingsAccessError.coreUnavailable) }
            defaults.set(StartupScopePreference.category.rawValue, forKey: "FluxNews.iOS.startupScope")
            defaults.set(id, forKey: "FluxNews.iOS.startupCategoryID")
        case 3:
            guard let id = legacy.startupFeedID, id > 0 else { return .success(()) }
            guard let core = bootstrapper.core,
                  let catalogResult = await bootstrapper.coreSessionExecutionCoordinator.responsiveResult(for: core, { try core.navigationCatalog() }) else {
                return .failure(CoreBootstrapper.SettingsAccessError.coreUnavailable)
            }
            guard case let .success(catalog) = catalogResult else { return .failure(CoreBootstrapper.SettingsAccessError.coreUnavailable) }
            guard catalog.feeds.contains(where: { $0.id == id }) else { return .failure(CoreBootstrapper.SettingsAccessError.coreUnavailable) }
            defaults.set(StartupScopePreference.feed.rawValue, forKey: "FluxNews.iOS.startupScope")
            defaults.set(id, forKey: "FluxNews.iOS.startupFeedID")
        default: break
        }
        return .success(())
    }

    private func mediaSettingsWriteFailed(_ error: Error) -> IOSLegacyMediaSettingsMigrationOutcome {
        logger.error("Legacy media settings migration remains retryable: \(String(reflecting: error))")
        return .retryableFailure
    }

    private static func legacyAudioExtension(at source: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: source) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 16) else { return nil }
        let bytes = [UInt8](data)
        if bytes.starts(with: [0x49, 0x44, 0x33])
            || (bytes.count >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) {
            return "mp3"
        }
        if bytes.count >= 12 && Array(bytes[4..<8]) == [0x66, 0x74, 0x79, 0x70] {
            return "m4a"
        }
        if bytes.starts(with: [0x4F, 0x67, 0x67, 0x53]) { return "ogg" }
        if bytes.starts(with: [0x66, 0x4C, 0x61, 0x43]) { return "flac" }
        return nil
    }

    private func readableRegularFileSize(at url: URL) -> UInt64? {
        guard fileManager.isReadableFile(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize,
              size > 0 else {
            return nil
        }
        return UInt64(size)
    }

    static func playbackMigrationOutcome(
        for importResult: LegacyPlaybackImportResult
    ) -> IOSLegacyPlaybackMigrationOutcome {
        // A later authoritative reconcile may make these article-keyed records resolvable.
        importResult.skippedMissing > 0 || importResult.skippedAmbiguous > 0 ? .retryableFailure : .imported
    }

    private func normalizedServerIdentifier(_ server: String) -> String {
        let trimmed = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let host = components.host else { return trimmed.lowercased() }
        components.scheme = components.scheme?.lowercased()
        components.host = host.lowercased()
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? trimmed.lowercased()
    }

    private func isCurrentMigratedAccount() throws -> Bool {
        guard let stored = try bootstrapper.credentialStore.load(),
              let migratedServer = defaults.string(forKey: DefaultsKey.migratedAccountServer) else {
            return false
        }
        return migratedServer == normalizedServerIdentifier(stored.server)
    }
}
@MainActor
struct IOSLegacyMigrationSummaryView: View {
    let summary: IOSLegacyMigrationCoordinator.Summary
    let sync: () async -> Void
    let close: () -> Void
    let finishPartial: () -> Void
    @State private var confirmingSkip = false
    @State private var syncing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(summary.completed ? "Previous data has been checked." : "Settings and media data are imported after a successful sync.")
                        .foregroundStyle(.secondary)
                    status("Account", complete: summary.accountCompleted, details: "Credentials checked")
                    status("Settings", complete: summary.localSettingsCompleted, details: "")
                    status("Feeds & startup view", complete: summary.feedSettingsCompleted && summary.startupCompleted, details: "")
                    status("Widgets", complete: summary.widgetSettingsCompleted, details: "")
                    status("Playback progress", complete: summary.playbackCompleted, details: summary.playbackDetails)
                    status("Downloads", complete: summary.downloadsCompleted, details: summary.downloadDetails)
                    if !summary.completed {
                        Text("Pending items are retried after synchronization.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button(syncing ? "Syncing…" : "Sync now") {
                            syncing = true
                            Task { await sync(); syncing = false }
                        }
                        .disabled(syncing)
                        if summary.canFinishWithSkippedItems {
                            Button("Finish with unresolved items") { confirmingSkip = true }
                                .disabled(syncing)
                        }
                    }
                    Button(summary.completed ? "Done" : "Continue in background", action: close)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle(summary.completionKind == "completed_with_skipped_items"
                ? "Completed with skipped items" : summary.completed ? "Migration complete" : "Import from FluxNews")
            .navigationBarTitleDisplayMode(.inline)
        }
        .confirmationDialog("Finish migration with skipped items?", isPresented: $confirmingSkip) {
            Button("Skip unresolved items") { finishPartial() }
            Button("Keep retrying", role: .cancel) {}
        } message: {
            Text("Successfully imported downloads and playback positions are preserved. Only unresolved items will be skipped. Original Flutter data remains untouched.")
        }
    }

    private func status(_ title: String, complete: Bool, details: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: complete ? "checkmark.circle.fill" : "circle")
                .foregroundColor(complete ? .green : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                if !details.isEmpty {
                    Text(details)
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}
