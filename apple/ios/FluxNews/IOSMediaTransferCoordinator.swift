import Combine
import CryptoKit
import Foundation

enum IOSMediaBackgroundTransferConfiguration {
    static var sessionIdentifier: String {
        let bundleID = Bundle.main.bundleIdentifier
            ?? "dev.kevincfechtel.fluxNews.nativeDev"
        return "\(bundleID).mediaTransfers.v1"
    }

    static func makeSessionConfiguration(
        identifier: String = sessionIdentifier
    ) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        return configuration
    }
}

struct IOSMediaTransferTaskIdentity: Codable, Equatable {
    static let currentVersion = 1

    let version: Int
    let executionToken: String
    let enclosureID: Int64
    let localReference: String

    init(
        executionToken: String,
        enclosureID: Int64,
        localReference: String
    ) {
        version = Self.currentVersion
        self.executionToken = executionToken
        self.enclosureID = enclosureID
        self.localReference = localReference
    }

    var taskDescription: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return data.base64EncodedString()
    }

    static func decode(_ description: String?) -> Self? {
        guard let description,
              let data = Data(base64Encoded: description),
              let identity = try? JSONDecoder().decode(Self.self, from: data),
              identity.version == currentVersion else {
            return nil
        }
        return identity
    }
}

final class IOSMediaTransferExecutionIdentityStore {
    private enum Key {
        static let fingerprint = "FluxNews.iOS.mediaTransfer.accountFingerprint.v1"
        static let token = "FluxNews.iOS.mediaTransfer.executionToken.v1"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func token(for credentials: IOSMinifluxCredentials) -> String {
        let fingerprint = Self.fingerprint(credentials)
        if defaults.string(forKey: Key.fingerprint) == fingerprint,
           let token = defaults.string(forKey: Key.token),
           !token.isEmpty {
            return token
        }

        let token = UUID().uuidString.lowercased()
        defaults.set(fingerprint, forKey: Key.fingerprint)
        defaults.set(token, forKey: Key.token)
        return token
    }

    func clear() {
        defaults.removeObject(forKey: Key.fingerprint)
        defaults.removeObject(forKey: Key.token)
    }

    private static func fingerprint(_ credentials: IOSMinifluxCredentials) -> String {
        var components = [credentials.server, credentials.apiKey]
        components.append(
            contentsOf: credentials.customHeaders
                .sorted { lhs, rhs in
                    if lhs.name == rhs.name { return lhs.value < rhs.value }
                    return lhs.name < rhs.name
                }
                .flatMap { [$0.name, $0.value] }
        )
        let data = Data(components.joined(separator: "\u{1f}").utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum IOSMediaTransferPathConfiguration {
    static var mediaRootURL: URL? {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        let namespace = (Bundle.main.object(forInfoDictionaryKey: "FluxStorageNamespace") as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "FluxNewsNativeDev"
        return applicationSupport
            .appendingPathComponent(namespace, isDirectory: true)
            .appendingPathComponent("Media", isDirectory: true)
    }
}

@MainActor
final class IOSMediaTransferCoordinator: NSObject, ObservableObject {
    private let bootstrapper: CoreBootstrapper
    private let coreSessionExecutionCoordinator: IOSCoreSessionExecutionCoordinator
    private let presentationState: IOSMediaTransferPresentationState
    private let handoff: IOSMediaTransferReconciliationHandoff
    private let sessionIdentifier: String
    private let identityStore: IOSMediaTransferExecutionIdentityStore
    private let fileManager: FileManager
    private var isMediaInUse: (Int64) -> Bool = { _ in false }
    private let logger = IOSAppLogger(category: "media-transfer")

    var onWorkChanged: (() -> Void)?
    @Published private(set) var workRevision: UInt64 = 0

    private var core: Flux?
    private var lifecycleGeneration: UInt64 = 0
    private var executionToken: String?
    private var backgroundEventsCompletionHandler: (() -> Void)?
    private var backgroundEventsFinished = false
    private var backgroundReconciliationFinished = false

    private lazy var session: URLSession = {
        URLSession(
            configuration: IOSMediaBackgroundTransferConfiguration.makeSessionConfiguration(
                identifier: sessionIdentifier
            ),
            delegate: self,
            delegateQueue: nil
        )
    }()

    init(
        bootstrapper: CoreBootstrapper,
        coreSessionExecutionCoordinator: IOSCoreSessionExecutionCoordinator,
        presentationState: IOSMediaTransferPresentationState,
        handoff: IOSMediaTransferReconciliationHandoff,
        sessionIdentifier: String = IOSMediaBackgroundTransferConfiguration.sessionIdentifier,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.bootstrapper = bootstrapper
        self.coreSessionExecutionCoordinator = coreSessionExecutionCoordinator
        self.presentationState = presentationState
        self.handoff = handoff
        self.sessionIdentifier = sessionIdentifier
        identityStore = IOSMediaTransferExecutionIdentityStore(defaults: defaults)
        self.fileManager = fileManager
        super.init()
    }

    func attach(to core: Flux, generation: UInt64) {
        self.core = core
        lifecycleGeneration = generation
        if let credentials = bootstrapper.credentials {
            executionToken = identityStore.token(for: credentials)
        }

        Task { @MainActor [weak self, weak core] in
            guard let self,
                  let core,
                  self.core === core,
                  self.lifecycleGeneration == generation else {
                return
            }

            await handoff.install { [weak self, weak core] in
                guard let self,
                      let core,
                      self.core === core,
                      self.lifecycleGeneration == generation else {
                    return
                }
                await self.reconcile()
            }

            // Process relaunch/normal app startup is itself a recovery boundary.
            // Reconcile once even when D5 has no buffered post-sync request.
            guard self.core === core,
                  self.lifecycleGeneration == generation else {
                return
            }
            await self.reconcile()
        }
    }

    func detach(generation: UInt64, clearingAccountIdentity: Bool = false) {
        lifecycleGeneration = generation
        core = nil
        handoff.uninstall()
        presentationState.reset()
        executionToken = nil
        if clearingAccountIdentity {
            identityStore.clear()
        }
    }

    func suspendForCoreLifecycle(generation: UInt64) {
        lifecycleGeneration = generation
        handoff.uninstall()
        presentationState.reset()
    }

    func setMediaInUseProvider(
        _ provider: @escaping (Int64) -> Bool
    ) {
        isMediaInUse = provider
    }

    func reconcile() async {
        guard let core,
              let executionToken,
              let mediaRoot = IOSMediaTransferPathConfiguration.mediaRootURL else {
            return
        }

        async let tasks = allBackgroundTasks()
        let coreResult = await coreSessionExecutionCoordinator.responsiveResult(
            for: core,
            {
                (
                    try core.coreSettings(),
                    try core.downloadsRequiringTransfer(),
                    try core.downloadsRequiringDeletion()
                )
            }
        )
        let existingTasks = await tasks

        guard let coreResult else { return }
        switch coreResult {
        case let .success((settings, requested, deletions)):
            await reconcile(
                requested: requested,
                deletions: deletions,
                existingTasks: existingTasks,
                settings: settings,
                executionToken: executionToken,
                mediaRoot: mediaRoot,
                core: core
            )
        case let .failure(error):
            logger.error(
                "media reconciliation Core query failed: \(String(reflecting: error))"
            )
        }
    }

    func handleBackgroundEvents(
        identifier: String,
        completionHandler: @escaping () -> Void
    ) -> Bool {
        guard identifier == sessionIdentifier else {
            return false
        }

        _ = session
        backgroundEventsCompletionHandler = completionHandler
        backgroundEventsFinished = false
        backgroundReconciliationFinished = false

        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await bootstrapper.ensureStarted()
            await reconcile()
            backgroundReconciliationFinished = true
            finishBackgroundEventsIfPossible()
        }
        return true
    }

    private func reconcile(
        requested: [MediaTransferWork],
        deletions: [MediaTransferWork],
        existingTasks: [URLSessionTask],
        settings: CoreSettings,
        executionToken: String,
        mediaRoot: URL,
        core: Flux
    ) async {
        var currentTasks = [Int64: URLSessionDownloadTask]()
        for task in existingTasks {
            guard let identity = IOSMediaTransferTaskIdentity.decode(task.taskDescription),
                  let downloadTask = task as? URLSessionDownloadTask,
                  identity.executionToken == executionToken else {
                task.cancel()
                continue
            }

            if currentTasks[identity.enclosureID] == nil {
                currentTasks[identity.enclosureID] = downloadTask
            } else {
                task.cancel()
            }
        }

        let requestedIDs = Set(requested.map(\.enclosureId))
        let staleEnclosureIDs = currentTasks.keys.filter { !requestedIDs.contains($0) }
        for enclosureID in staleEnclosureIDs {
            currentTasks[enclosureID]?.cancel()
            presentationState.remove(enclosureID: enclosureID)
            currentTasks[enclosureID] = nil
        }

        for work in requested {
            if let task = currentTasks[work.enclosureId] {
                presentationState.set(
                    MediaTransferRuntime(
                        enclosureID: work.enclosureId,
                        bytesReceived: task.countOfBytesReceived,
                        expectedBytes: task.countOfBytesExpectedToReceive > 0
                            ? task.countOfBytesExpectedToReceive
                            : nil,
                        phase: .transferring
                    )
                )
                continue
            }

            let reference = MediaTransferFileLayout.reference(
                executionNamespace: executionToken,
                enclosureID: work.enclosureId,
                url: work.url,
                mimeType: work.mimeType
            )
            guard let destination = try? MediaTransferFileLayout.destination(
                reference: reference,
                under: mediaRoot
            ) else {
                await reportFailure(
                    enclosureID: work.enclosureId,
                    kind: .storage,
                    core: core
                )
                continue
            }

            if fileManager.fileExists(atPath: destination.path) {
                if let size = fileSize(at: destination) {
                    await reportCompletion(
                        enclosureID: work.enclosureId,
                        reference: reference,
                        size: size,
                        core: core
                    )
                } else {
                    await reportFailure(
                        enclosureID: work.enclosureId,
                        kind: .storage,
                        core: core
                    )
                }
                continue
            }

            guard let url = URL(string: work.url),
                  url.scheme == "http" || url.scheme == "https" else {
                await reportFailure(
                    enclosureID: work.enclosureId,
                    kind: .invalidMedia,
                    core: core
                )
                continue
            }

            var request = URLRequest(url: url)
            request.allowsExpensiveNetworkAccess = settings.downloadNetworkPolicy == .anyNetwork
            request.allowsConstrainedNetworkAccess = settings.downloadNetworkPolicy == .anyNetwork

            let task = session.downloadTask(with: request)
            task.taskDescription = IOSMediaTransferTaskIdentity(
                executionToken: executionToken,
                enclosureID: work.enclosureId,
                localReference: reference
            ).taskDescription
            presentationState.set(
                MediaTransferRuntime(
                    enclosureID: work.enclosureId,
                    bytesReceived: 0,
                    expectedBytes: nil,
                    phase: .starting
                )
            )
            task.resume()
        }

        for work in deletions {
            guard !isMediaInUse(work.enclosureId) else {
                continue
            }
            guard let reference = work.localFile,
                  let destination = try? MediaTransferFileLayout.destination(
                    reference: reference,
                    under: mediaRoot
                  ) else {
                continue
            }
            do {
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                await reportDeletion(enclosureID: work.enclosureId, core: core)
            } catch {
                logger.error(
                    "media deletion failed enclosure=\(work.enclosureId): \(String(reflecting: error))"
                )
            }
        }

    }

    private func allBackgroundTasks() async -> [URLSessionTask] {
        await withCheckedContinuation { continuation in
            session.getAllTasks { tasks in
                continuation.resume(returning: tasks)
            }
        }
    }

    private func fileSize(at url: URL) -> UInt64? {
        guard let number = try? fileManager
            .attributesOfItem(atPath: url.path)[.size] as? NSNumber else {
            return nil
        }
        return UInt64(max(0, number.int64Value))
    }

    private func reportCompletion(
        enclosureID: Int64,
        reference: String,
        size: UInt64,
        core: Flux
    ) async {
        guard let result = await coreSessionExecutionCoordinator.responsiveResult(
            for: core,
            {
                try core.downloadFinished(
                    enclosureId: enclosureID,
                    localFile: reference,
                    fileSizeBytes: size
                )
            }
        ) else {
            return
        }
        if case let .failure(error) = result {
            logger.error(
                "media completion callback rejected enclosure=\(enclosureID): \(String(reflecting: error))"
            )
        } else {
            workRevision &+= 1
            onWorkChanged?()
        }
        presentationState.remove(enclosureID: enclosureID)
    }

    private func reportFailure(
        enclosureID: Int64,
        kind: DownloadFailureKind,
        core: Flux
    ) async {
        guard let result = await coreSessionExecutionCoordinator.responsiveResult(
            for: core,
            { try core.downloadFailed(enclosureId: enclosureID, failureKind: kind) }
        ) else {
            return
        }
        if case let .failure(error) = result {
            logger.error(
                "media failure callback rejected enclosure=\(enclosureID): \(String(reflecting: error))"
            )
        } else {
            workRevision &+= 1
            onWorkChanged?()
        }
        presentationState.remove(enclosureID: enclosureID)
    }

    private func reportDeletion(enclosureID: Int64, core: Flux) async {
        guard let result = await coreSessionExecutionCoordinator.responsiveResult(
            for: core,
            { try core.downloadDeleted(enclosureId: enclosureID) }
        ) else {
            return
        }
        if case let .failure(error) = result {
            logger.error(
                "media deletion callback rejected enclosure=\(enclosureID): \(String(reflecting: error))"
            )
        } else {
            workRevision &+= 1
            onWorkChanged?()
        }
        presentationState.remove(enclosureID: enclosureID)
    }

    private func finishBackgroundEventsIfPossible() {
        guard backgroundEventsFinished,
              backgroundReconciliationFinished,
              let completionHandler = backgroundEventsCompletionHandler else {
            return
        }
        backgroundEventsCompletionHandler = nil
        completionHandler()
    }
}

extension IOSMediaTransferCoordinator: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let identity = IOSMediaTransferTaskIdentity.decode(downloadTask.taskDescription) else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self,
                  identity.executionToken == executionToken else {
                return
            }
            presentationState.set(
                MediaTransferRuntime(
                    enclosureID: identity.enclosureID,
                    bytesReceived: totalBytesWritten,
                    expectedBytes: totalBytesExpectedToWrite > 0
                        ? totalBytesExpectedToWrite
                        : nil,
                    phase: .transferring
                )
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let identity = IOSMediaTransferTaskIdentity.decode(downloadTask.taskDescription) else {
            return
        }

        guard let response = downloadTask.response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            Task { @MainActor [weak self] in
                guard let self,
                      identity.executionToken == executionToken,
                      let core else {
                    return
                }
                await reportFailure(
                    enclosureID: identity.enclosureID,
                    kind: .network,
                    core: core
                )
            }
            return
        }

        guard let mediaRoot = IOSMediaTransferPathConfiguration.mediaRootURL,
              let destination = try? MediaTransferFileLayout.destination(
                reference: identity.localReference,
                under: mediaRoot
              ) else {
            Task { @MainActor [weak self] in
                guard let self,
                      identity.executionToken == executionToken,
                      let core else {
                    return
                }
                await reportFailure(
                    enclosureID: identity.enclosureID,
                    kind: .storage,
                    core: core
                )
            }
            return
        }

        // URLSession's temporary location is guaranteed only for this delegate
        // callback. Persist it synchronously before returning; Core acknowledgement
        // happens afterward on the app-wide session gate.
        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: location, to: destination)
            let number = try fileManager
                .attributesOfItem(atPath: destination.path)[.size] as? NSNumber
            let size = UInt64(max(0, number?.int64Value ?? 0))

            Task { @MainActor [weak self] in
                guard let self,
                      identity.executionToken == executionToken,
                      let core else {
                    return
                }
                await reportCompletion(
                    enclosureID: identity.enclosureID,
                    reference: identity.localReference,
                    size: size,
                    core: core
                )
            }
        } catch {
            Task { @MainActor [weak self] in
                guard let self,
                      identity.executionToken == executionToken,
                      let core else {
                    return
                }
                await reportFailure(
                    enclosureID: identity.enclosureID,
                    kind: .storage,
                    core: core
                )
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let identity = IOSMediaTransferTaskIdentity.decode(task.taskDescription) else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self,
                  identity.executionToken == executionToken,
                  let core else {
                return
            }
            if let error {
                let nsError = error as NSError
                if nsError.code != NSURLErrorCancelled {
                    await reportFailure(
                        enclosureID: identity.enclosureID,
                        kind: nsError.domain == NSURLErrorDomain ? .network : .unknown,
                        core: core
                    )
                }
            }
            presentationState.remove(enclosureID: identity.enclosureID)
            await reconcile()
        }
    }

    nonisolated func urlSessionDidFinishEvents(
        forBackgroundURLSession session: URLSession
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            backgroundEventsFinished = true
            finishBackgroundEventsIfPossible()
        }
    }
}
