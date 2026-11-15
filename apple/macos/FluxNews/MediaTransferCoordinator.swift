import Foundation
import OSLog

struct NativeTransferResult {
    let temporaryURL: URL
}

@MainActor
final class MediaTransferPresentationState: ObservableObject {
    @Published private(set) var transfers: [Int64: MediaTransferRuntime] = [:]

    func runtime(for enclosureID: Int64) -> MediaTransferRuntime? { transfers[enclosureID] }

    fileprivate func set(_ runtime: MediaTransferRuntime) { transfers[runtime.enclosureID] = runtime }
    fileprivate func remove(enclosureID: Int64) { transfers[enclosureID] = nil }
}

protocol MediaTransferEngine: Sendable {
    func download(from url: URL, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws -> NativeTransferResult
}

@MainActor
protocol MediaTransferCore: AnyObject {
    func coreSettings() throws -> CoreSettings
    func downloadsRequiringTransfer() throws -> [MediaTransferWork]
    func downloadsRequiringDeletion() throws -> [MediaTransferWork]
    func downloadFinished(enclosureId: Int64, localFile: String, fileSizeBytes: UInt64) throws
    func downloadFailed(enclosureId: Int64, failureKind: DownloadFailureKind) throws
    func downloadDeleted(enclosureId: Int64) throws
}

enum MediaTransferNetworkConfiguration {
    static func configuration(for policy: DownloadNetworkPolicy) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.allowsExpensiveNetworkAccess = policy == .anyNetwork
        configuration.allowsConstrainedNetworkAccess = policy == .anyNetwork
        return configuration
    }
}

struct URLSessionMediaTransferEngine: MediaTransferEngine {
    let networkPolicy: DownloadNetworkPolicy

    init(networkPolicy: DownloadNetworkPolicy = .anyNetwork) {
        self.networkPolicy = networkPolicy
    }

    func download(from url: URL, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws -> NativeTransferResult {
        let handle = URLSessionDownloadHandle()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let delegate = FluxURLSessionDownloadDelegate(progress: progress, continuation: continuation, handle: handle)
                let session = URLSession(configuration: MediaTransferNetworkConfiguration.configuration(for: networkPolicy), delegate: delegate, delegateQueue: nil)
                delegate.session = session
                handle.set(delegate: delegate)
                session.downloadTask(with: url).resume()
            }
        } onCancel: {
            handle.cancel()
        }
    }
}

private final class URLSessionDownloadHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var delegate: FluxURLSessionDownloadDelegate?
    private var cancelled = false

    func set(delegate: FluxURLSessionDownloadDelegate) {
        lock.lock(); defer { lock.unlock() }
        self.delegate = delegate
        if cancelled { delegate.cancel() }
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        delegate?.cancel()
    }
}

private final class FluxURLSessionDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Int64, Int64?) -> Void
    private var continuation: CheckedContinuation<NativeTransferResult, Error>?
    private let handle: URLSessionDownloadHandle
    private var temporaryURL: URL?
    private var finished = false
    var session: URLSession?

    init(progress: @escaping @Sendable (Int64, Int64?) -> Void, continuation: CheckedContinuation<NativeTransferResult, Error>, handle: URLSessionDownloadHandle) {
        self.progress = progress
        self.continuation = continuation
        self.handle = handle
    }

    func cancel() { session?.invalidateAndCancel() }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten, totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let response = downloadTask.response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            complete(.failure(MediaTransferError.network))
            return
        }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("flux-download-").appendingPathExtension(UUID().uuidString)
        do {
            try FileManager.default.copyItem(at: location, to: destination)
            temporaryURL = destination
        } catch {
            complete(.failure(MediaTransferError.storage))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            if (error as NSError).code == NSURLErrorCancelled { complete(.failure(CancellationError())) }
            else { complete(.failure(error)) }
        } else if let temporaryURL {
            complete(.success(NativeTransferResult(temporaryURL: temporaryURL)))
        } else {
            complete(.failure(MediaTransferError.network))
        }
    }

    private func complete(_ result: Result<NativeTransferResult, Error>) {
        guard !finished else { return }
        finished = true
        session?.finishTasksAndInvalidate()
        continuation?.resume(with: result)
        continuation = nil
    }
}

@MainActor
final class MediaTransferCoordinator {
    private let core: MediaTransferCore
    private let mediaRoot: URL
    private var engine: MediaTransferEngine
    private var networkPolicy: DownloadNetworkPolicy
    private let isMediaInUse: (Int64) -> Bool
    let presentationState: MediaTransferPresentationState
    var onWorkChanged: (() -> Void)?
    private var activeTasks = [Int64: Task<Void, Never>]()
    private var activeTaskTokens = [Int64: UUID]()

    init(core: MediaTransferCore, mediaRoot: URL = MediaPlaybackPaths.mediaRootURL, networkPolicy: DownloadNetworkPolicy = .anyNetwork, engine: MediaTransferEngine? = nil, isMediaInUse: @escaping (Int64) -> Bool = { _ in false }, presentationState: MediaTransferPresentationState? = nil) {
        self.core = core
        self.mediaRoot = mediaRoot
        self.networkPolicy = networkPolicy
        self.engine = engine ?? URLSessionMediaTransferEngine(networkPolicy: networkPolicy)
        self.isMediaInUse = isMediaInUse
        self.presentationState = presentationState ?? MediaTransferPresentationState()
    }

    func reconcile() {
        do {
            let currentPolicy = try core.coreSettings().downloadNetworkPolicy
            if currentPolicy != networkPolicy {
                networkPolicy = currentPolicy
                engine = URLSessionMediaTransferEngine(networkPolicy: currentPolicy)
            }
            let requested = try core.downloadsRequiringTransfer()
            let requestedIDs = Set(requested.map(\.enclosureId))
            for work in requested where activeTasks[work.enclosureId] == nil { start(work) }
            for id in Array(activeTasks.keys) where !requestedIDs.contains(id) {
                activeTasks[id]?.cancel()
                activeTasks[id] = nil
                activeTaskTokens[id] = nil
                presentationState.remove(enclosureID: id)
            }
            executeDeletions(try core.downloadsRequiringDeletion())
        } catch {
            Logger(subsystem: "dev.kevincfechtel.fluxNews", category: "media").error("media transfer reconciliation failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    func cancel(enclosureID: Int64) {
        if activeTasks[enclosureID] != nil {
            presentationState.set(MediaTransferRuntime(enclosureID: enclosureID, bytesReceived: 0, expectedBytes: nil, phase: .cancelling))
        }
        activeTasks[enclosureID]?.cancel()
        activeTasks[enclosureID] = nil
        activeTaskTokens[enclosureID] = nil
        presentationState.remove(enclosureID: enclosureID)
    }

    func shutdown() {
        for id in activeTasks.keys {
            activeTaskTokens[id] = nil
            activeTasks[id]?.cancel()
            presentationState.remove(enclosureID: id)
        }
        activeTasks.removeAll()
        activeTaskTokens.removeAll()
    }

    private func start(_ work: MediaTransferWork) {
        guard let url = URL(string: work.url), url.scheme == "http" || url.scheme == "https" else {
            reportFailure(enclosureID: work.enclosureId, kind: .invalidMedia)
            return
        }
        let token = UUID()
        presentationState.set(MediaTransferRuntime(enclosureID: work.enclosureId, bytesReceived: 0, expectedBytes: nil, phase: .starting))
        let task = Task { [weak self] in
            guard let self else { return }
            Logger(subsystem: "dev.kevincfechtel.fluxNews", category: "media").info("media transfer started enclosure=\(work.enclosureId, privacy: .public)")
            let result: NativeTransferResult
            do {
                result = try await engine.download(from: url) { [weak self] bytesReceived, expectedBytes in
                    Task { @MainActor [weak self] in
                        guard let self, self.activeTaskTokens[work.enclosureId] == token else { return }
                        self.presentationState.set(MediaTransferRuntime(enclosureID: work.enclosureId, bytesReceived: bytesReceived, expectedBytes: expectedBytes, phase: .transferring))
                    }
                }
            } catch is CancellationError {
                finish(enclosureID: work.enclosureId, token: token)
                return
            } catch {
                finish(enclosureID: work.enclosureId, token: token)
                reportFailure(enclosureID: work.enclosureId, kind: Self.failureKind(for: error))
                return
            }

            guard activeTaskTokens[work.enclosureId] == token else {
                try? FileManager.default.removeItem(at: result.temporaryURL)
                return
            }
            let reference = MediaTransferFileLayout.reference(enclosureID: work.enclosureId, url: work.url, mimeType: work.mimeType)
            let destination: URL
            do {
                destination = try safeDestination(reference)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                try FileManager.default.moveItem(at: result.temporaryURL, to: destination)
            } catch {
                finish(enclosureID: work.enclosureId, token: token)
                reportFailure(enclosureID: work.enclosureId, kind: .storage)
                return
            }

            let size: UInt64
            do {
                let value = try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber
                size = UInt64(value?.int64Value ?? 0)
            } catch {
                finish(enclosureID: work.enclosureId, token: token)
                reportFailure(enclosureID: work.enclosureId, kind: .storage)
                return
            }

            do {
                finish(enclosureID: work.enclosureId, token: token)
                presentationState.remove(enclosureID: work.enclosureId)
                try core.downloadFinished(enclosureId: work.enclosureId, localFile: reference, fileSizeBytes: size)
                Logger(subsystem: "dev.kevincfechtel.fluxNews", category: "media").info("media transfer completed enclosure=\(work.enclosureId, privacy: .public) reference=<private> path=<private> readable=\(FileManager.default.isReadableFile(atPath: destination.path), privacy: .public)")
                onWorkChanged?()
            } catch {
                // Core owns stale-callback handling; a callback rejection is not a transfer failure.
                Logger(subsystem: "dev.kevincfechtel.fluxNews", category: "media").error("media completion callback rejected enclosure=\(work.enclosureId, privacy: .public): \(error.localizedDescription, privacy: .private)")
            }
            finish(enclosureID: work.enclosureId, token: token)
        }
        activeTaskTokens[work.enclosureId] = token
        activeTasks[work.enclosureId] = task
    }

    private func finish(enclosureID: Int64, token: UUID) {
        guard activeTaskTokens[enclosureID] == token else { return }
        activeTaskTokens[enclosureID] = nil
        activeTasks[enclosureID] = nil
        presentationState.remove(enclosureID: enclosureID)
    }

    private func executeDeletions(_ workItems: [MediaTransferWork]) {
        for work in workItems {
            guard !isMediaInUse(work.enclosureId) else { continue }
            guard let reference = work.localFile, let path = try? safeDestination(reference) else { continue }
            do {
                if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
                try core.downloadDeleted(enclosureId: work.enclosureId)
                Logger(subsystem: "dev.kevincfechtel.fluxNews", category: "media").info("media deletion completed enclosure=\(work.enclosureId, privacy: .public)")
                onWorkChanged?()
            } catch {
                Logger(subsystem: "dev.kevincfechtel.fluxNews", category: "media").error("media deletion failed enclosure=\(work.enclosureId, privacy: .public): \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    private func safeDestination(_ reference: String) throws -> URL {
        try MediaTransferFileLayout.destination(reference: reference, under: mediaRoot)
    }

    private func reportFailure(enclosureID: Int64, kind: DownloadFailureKind) {
        do {
            try core.downloadFailed(enclosureId: enclosureID, failureKind: kind)
            onWorkChanged?()
        } catch {
            Logger(subsystem: "dev.kevincfechtel.fluxNews", category: "media").error("media failure callback failed enclosure=\(enclosureID, privacy: .public): \(error.localizedDescription, privacy: .private)")
        }
    }

    static func failureKind(for error: Error) -> DownloadFailureKind {
        if let transferError = error as? MediaTransferError {
            return transferError == .network ? .network : .storage
        }
        if (error as NSError).domain == NSURLErrorDomain { return .network }
        return .unknown
    }
}

extension Flux: MediaTransferCore {}
