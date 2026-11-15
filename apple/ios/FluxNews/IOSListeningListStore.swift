import Combine
import Foundation

@MainActor
final class IOSListeningListStore: ObservableObject {
    @Published private(set) var items: [ListeningListItem] = []
    @Published private(set) var feeds: [ListeningListFeed] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var sort: ListeningListSort = .recentlyAdded
    @Published var feedID: Int64?
    @Published private(set) var showNotesDocument: ReaderDocument?
    @Published private(set) var showNotesIsLoading = false
    @Published private(set) var showNotesErrorMessage: String?

    var onTransferReconciliationRequested: (() async -> Void)?

    private var core: Flux?
    private var coreSessionExecutionCoordinator = IOSCoreSessionExecutionCoordinator()
    private var generation: UInt64 = 0
    private var showNotesGeneration: UInt64 = 0

    var count: UInt64 { UInt64(items.count) }

    func attach(
        to core: Flux,
        coreSessionExecutionCoordinator: IOSCoreSessionExecutionCoordinator
    ) {
        generation &+= 1
        self.core = core
        self.coreSessionExecutionCoordinator = coreSessionExecutionCoordinator
        reload()
    }

    func detach() {
        generation &+= 1
        showNotesGeneration &+= 1
        core = nil
        items = []
        feeds = []
        feedID = nil
        isLoading = false
        errorMessage = nil
        showNotesDocument = nil
        showNotesIsLoading = false
        showNotesErrorMessage = nil
    }

    func reload() {
        guard let core else { return }
        generation &+= 1
        let request = generation
        let requestedFeedID = feedID
        let requestedSort = sort
        let coordinator = coreSessionExecutionCoordinator
        isLoading = true
        errorMessage = nil

        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.responsiveResult(
                for: core,
                {
                    let feeds = try core.listeningListFeeds()
                    let validatedFeedID = requestedFeedID.flatMap { id in
                        feeds.contains(where: { $0.feedId == id }) ? id : nil
                    }
                    let items = try core.listeningList(
                        feedId: validatedFeedID,
                        sort: requestedSort
                    )
                    return (feeds, validatedFeedID, items)
                }
            ) else { return }

            guard let self, self.generation == request else { return }
            self.isLoading = false
            switch result {
            case let .success((feeds, validatedFeedID, items)):
                self.feeds = feeds
                self.feedID = validatedFeedID
                self.items = items
                self.errorMessage = nil
            case let .failure(error):
                self.errorMessage = IOSErrorPresentation.message(
                    for: error,
                    context: .contentLoad
                )
            }
        }
    }

    func setSort(_ sort: ListeningListSort) {
        guard self.sort != sort else { return }
        self.sort = sort
        reload()
    }

    func setFeedID(_ feedID: Int64?) {
        guard self.feedID != feedID else { return }
        self.feedID = feedID
        reload()
    }

    func removeFromListeningList(articleID: Int64) async {
        await mutate(
            { core in try core.removeFromListeningList(articleId: articleID) },
            reconcileTransfers: true
        )
    }

    func requestDownload(enclosureID: Int64) async {
        await mutate(
            { core in
                try core.requestDownload(
                    enclosureId: enclosureID,
                    origin: .manual
                )
            },
            reconcileTransfers: true
        )
    }

    func cancelDownload(enclosureID: Int64) async {
        await mutate(
            { core in try core.cancelDownload(enclosureId: enclosureID) },
            reconcileTransfers: true
        )
    }

    func retryDownload(enclosureID: Int64) async {
        await mutate(
            { core in try core.retryDownload(enclosureId: enclosureID) },
            reconcileTransfers: true
        )
    }

    func deleteDownload(enclosureID: Int64) async {
        await mutate(
            {
                core in try core.requestDownloadDeletion(
                    enclosureId: enclosureID
                )
            },
            reconcileTransfers: true
        )
    }

    func loadShowNotes(articleID: Int64) {
        guard let core else { return }
        showNotesGeneration &+= 1
        let request = showNotesGeneration
        let coordinator = coreSessionExecutionCoordinator
        showNotesDocument = nil
        showNotesErrorMessage = nil
        showNotesIsLoading = true

        Task { [weak self, core, coordinator] in
            let result = await coordinator.responsiveResult(
                for: core,
                { try core.readerDocument(articleId: articleID) }
            )
            guard let self, self.showNotesGeneration == request else { return }
            self.showNotesIsLoading = false
            guard let result else { return }
            switch result {
            case let .success(document):
                self.showNotesDocument = document
            case let .failure(error):
                self.showNotesErrorMessage = IOSErrorPresentation.message(
                    for: error,
                    context: .reader
                )
            }
        }
    }

    func clearShowNotes() {
        showNotesGeneration &+= 1
        showNotesDocument = nil
        showNotesIsLoading = false
        showNotesErrorMessage = nil
    }

    private func mutate(
        _ operation: @escaping @Sendable (Flux) throws -> Void,
        reconcileTransfers: Bool
    ) async {
        guard let core else { return }
        let coordinator = coreSessionExecutionCoordinator
        guard let result = await coordinator.responsiveResult(
            for: core,
            { try operation(core) }
        ) else {
            return
        }

        switch result {
        case .success:
            if reconcileTransfers {
                await onTransferReconciliationRequested?()
            }
            reload()
        case let .failure(error):
            errorMessage = IOSErrorPresentation.message(
                for: error,
                context: .contentLoad
            )
        }
    }
}

enum IOSListeningListPresentation {
    enum PlaybackAction: Equatable {
        case play
        case pause
    }

    enum DownloadAction: Equatable {
        case download
        case pending
        case downloading
        case cancelling
        case delete
        case pendingDeletion
        case retry
    }

    struct TransferProgress: Equatable {
        let fraction: Double?
        let label: String
    }

    struct Progress: Equatable {
        let positionMs: UInt64
        let durationMs: UInt64?
        let status: PlaybackStatus

        var fraction: Double? {
            guard let durationMs, durationMs > 0 else { return nil }
            return min(
                max(Double(positionMs) / Double(durationMs), 0),
                1
            )
        }
    }

    static func playbackAction(
        enclosureID: Int64,
        loadedEnclosureID: Int64?,
        status: MediaPlaybackPresentationStatus
    ) -> PlaybackAction {
        loadedEnclosureID == enclosureID && status == .playing
            ? .pause
            : .play
    }

    static func textOrFallback(_ value: String, fallback: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallback
            : value
    }

    static func selectedEnclosure(
        _ item: ListeningListItem
    ) -> ListeningListEnclosure? {
        if let activeID = item.activeEnclosureId,
           let active = item.audioEnclosures.first(
            where: { $0.enclosure.id == activeID }
           ) {
            return active
        }
        return item.audioEnclosures.count == 1
            ? item.audioEnclosures[0]
            : nil
    }

    @MainActor
    static func isUnplayed(
        _ item: ListeningListItem,
        runtime: IOSMediaPlaybackPresentationState
    ) -> Bool {
        guard !item.audioEnclosures.isEmpty,
              item.audioEnclosures.allSatisfy({ audio in
                  guard audio.enclosure.remoteMediaProgressionSeconds == 0 else {
                      return false
                  }
                  guard let playback = audio.playbackState else { return true }
                  return playback.status == .notStarted && playback.positionMs == 0
              }) else {
            return false
        }
        if let loadedID = runtime.loadedEnclosure?.id,
           item.audioEnclosures.contains(where: { $0.enclosure.id == loadedID }) {
            return runtime.status != .playing && runtime.positionMs == 0
        }
        return true
    }

    @MainActor
    static func progress(
        _ item: ListeningListItem,
        runtime: IOSMediaPlaybackPresentationState
    ) -> Progress? {
        guard let selected = selectedEnclosure(item) else { return nil }
        let isRuntimeItem = runtime.loadedEnclosure?.id == selected.enclosure.id
        let playback = selected.playbackState

        let status: PlaybackStatus = if isRuntimeItem {
            switch runtime.status {
            case .playing:
                .inProgress
            case .paused, .stopped:
                playback?.status ?? .notStarted
            }
        } else {
            playback?.status ?? .notStarted
        }

        let rawPosition = isRuntimeItem
            ? runtime.positionMs
            : playback?.positionMs ?? 0
        let rawDuration = isRuntimeItem
            ? runtime.durationMs ?? selected.durationMs ?? playback?.durationMs
            : selected.durationMs ?? playback?.durationMs
        let duration = rawDuration.flatMap { $0 > 0 ? $0 : nil }
        let position = duration.map { min(rawPosition, $0) } ?? rawPosition

        guard status != .notStarted || position > 0 else { return nil }
        return .init(
            positionMs: position,
            durationMs: duration,
            status: status
        )
    }

    static func enclosureLabel(
        _ enclosure: Enclosure,
        index: Int
    ) -> String {
        let filename: String?
        if let url = URL(string: enclosure.url),
           let decoded = url.lastPathComponent.removingPercentEncoding {
            let trimmed = decoded.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            filename = trimmed.isEmpty || trimmed == "/" ? nil : trimmed
        } else {
            filename = nil
        }

        let name = filename ?? String(localized: "Audio \(index + 1)")
        let format = enclosure.mimeType
            .split(separator: ";", maxSplits: 1)
            .first
            .map(String.init) ?? ""
        let size = enclosure.sizeBytes.map {
            ByteCountFormatter.string(
                fromByteCount: Int64(min($0, UInt64(Int64.max))),
                countStyle: .file
            )
        }
        let details = [format, size]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return details.isEmpty
            ? name
            : "\(name) (\(details.joined(separator: ", ")))"
    }

    static func downloadAction(
        _ enclosure: ListeningListEnclosure,
        runtime: MediaTransferRuntime?
    ) -> DownloadAction {
        downloadAction(
            download: enclosure.download,
            runtime: runtime
        )
    }

    static func downloadAction(
        download: MediaDownload?,
        runtime: MediaTransferRuntime?
    ) -> DownloadAction {
        switch download?.state {
        case .downloaded:
            return .delete
        case .requested:
            switch runtime?.phase {
            case .transferring:
                return .downloading
            case .cancelling:
                return .cancelling
            case .starting, nil:
                return .pending
            }
        case .deleteRequested:
            return .pendingDeletion
        case .failed:
            return .retry
        case .notDownloaded, nil:
            return .download
        }
    }

    static func downloadSummary(
        _ item: ListeningListItem,
        transfers: [Int64: MediaTransferRuntime] = [:]
    ) -> (downloaded: Int, total: Int, pending: Int) {
        let actions = item.audioEnclosures.map {
            downloadAction(
                $0,
                runtime: transfers[$0.enclosure.id]
            )
        }
        return (
            actions.filter { $0 == .delete }.count,
            item.audioEnclosures.count,
            actions.filter {
                switch $0 {
                case .pending, .downloading, .cancelling, .pendingDeletion:
                    true
                case .download, .delete, .retry:
                    false
                }
            }.count
        )
    }

    static func transferProgress(
        _ item: ListeningListItem,
        transfers: [Int64: MediaTransferRuntime]
    ) -> TransferProgress? {
        let active = item.audioEnclosures.compactMap { enclosure -> MediaTransferRuntime? in
            transfers[enclosure.enclosure.id]
        }
        guard !active.isEmpty else { return nil }

        if let runtime = active.first(where: { $0.phase == .transferring }) {
            let label: String
            if let fraction = runtime.fraction {
                label = String(
                    localized: "\(Int((fraction * 100).rounded()))% downloaded"
                )
            } else {
                label = String(localized: "Downloading")
            }
            return .init(
                fraction: runtime.fraction,
                label: label
            )
        }

        if active.contains(where: { $0.phase == .cancelling }) {
            return .init(
                fraction: nil,
                label: String(localized: "Cancelling Download")
            )
        }

        return .init(
            fraction: nil,
            label: String(localized: "Preparing Download")
        )
    }
}
