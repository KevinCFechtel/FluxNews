import Foundation

enum IOSArticleImagePrefetchPolicy {
    static func candidateIDs(
        orderedIDs: [Int64],
        visibleIDs: [Int64],
        imageIDs: Set<Int64>,
        direction: IOSArticleScrollDirection,
        excludedIDs: Set<Int64> = [],
        limit: Int = 2,
        searchHorizon: Int = 12
    ) -> [Int64] {
        IOSArticleImagePrefetchMetadata(orderedIDs: orderedIDs, imageIDs: imageIDs)
            .candidateIDs(visibleIDs: visibleIDs, direction: direction, excludedIDs: excludedIDs, limit: limit, searchHorizon: searchHorizon)
    }
}

enum IOSUIKitTimelineSnapshotPolicy {
    static func requiresStructuralUpdate(previousIDs: [Int64], newIDs: [Int64]) -> Bool {
        previousIDs != newIDs
    }
}

/// Derived only with a structural article snapshot, never from a visibility update.
struct IOSArticleImagePrefetchMetadata {
    private(set) var orderedIDs: [Int64] = []
    private var positions: [Int64: Int] = [:]
    private var imageIDs = Set<Int64>()
    private var imageURLs: [Int64: URL] = [:]

    init() {}

    init(orderedIDs: [Int64], imageIDs: Set<Int64>) {
        self.orderedIDs = orderedIDs
        positions = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { ($0.element, $0.offset) })
        self.imageIDs = imageIDs
    }

    mutating func update(articles: [ArticleSummary]) -> Bool {
        let ids = articles.map(\.id)
        guard ids != orderedIDs else { return false }
        orderedIDs = ids
        positions = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
        imageURLs = Dictionary(uniqueKeysWithValues: articles.compactMap { article in
            article.imageUrl.flatMap(URL.init(string:)).map { (article.id, $0) }
        })
        imageIDs = Set(imageURLs.keys)
        return true
    }

    func imageURL(for id: Int64) -> URL? { imageURLs[id] }

    func candidateIDs(
        visibleIDs: [Int64],
        direction: IOSArticleScrollDirection,
        excludedIDs: Set<Int64> = [],
        limit: Int = 2,
        searchHorizon: Int = 12
    ) -> [Int64] {
        guard limit > 0, searchHorizon > 0 else { return [] }
        var anchor: Int?
        for id in visibleIDs {
            guard let position = positions[id] else { continue }
            if let current = anchor {
                anchor = direction == .forward ? max(current, position) : min(current, position)
            } else {
                anchor = position
            }
        }
        guard let anchor else { return [] }

        var result: [Int64] = []
        for offset in 1...searchHorizon {
            let position = direction == .forward ? anchor + offset : anchor - offset
            guard orderedIDs.indices.contains(position) else { break }
            let id = orderedIDs[position]
            if imageIDs.contains(id) && !excludedIDs.contains(id) {
                result.append(id)
                if result.count == limit { break }
            }
        }
        return result
    }
}

/// Retains requests already handed to the pipeline without invalidating the list.
final class IOSArticleImagePrefetchCoordinator {
    private var submittedRequests = Set<ArticleImageRequest>()

    func accept(_ requests: [ArticleImageRequest]) -> [ArticleImageRequest] {
        requests.filter { submittedRequests.insert($0).inserted }
    }

    func reset() {
        submittedRequests.removeAll(keepingCapacity: true)
    }
}

enum IOSArticleContextAction: Equatable {
    case starred
    case read
    case original
    case reader
    case miniflux
    case comments
    case copyLink
    case share
    case saveToService
}

enum IOSArticleMediaAction: Equatable {
    case play(enclosureID: Int64)
    case setListeningList(Bool)
    case requestDownload(enclosureID: Int64)
    case cancelDownload(enclosureID: Int64)
    case retryDownload(enclosureID: Int64)
    case deleteDownload(enclosureID: Int64)
    case configuredDownloadAudio
}

enum IOSArticleAudioPresentation {
    static func hasAudio(_ state: IOSArticleAudioActionState?) -> Bool {
        guard let state else { return false }
        return !state.audioEnclosures.isEmpty
    }

    enum DownloadAction: Equatable {
        case download
        case pending
        case delete
        case retry
        case pendingDeletion
    }

    static func downloadAction(_ download: MediaDownload?) -> DownloadAction {
        switch download?.state {
        case .downloaded:
            .delete
        case .requested:
            .pending
        case .deleteRequested:
            .pendingDeletion
        case .failed:
            .retry
        case .notDownloaded, nil:
            .download
        }
    }

    static func downloadableEnclosures(
        _ state: IOSArticleAudioActionState?
    ) -> [Enclosure] {
        guard let state else { return [] }
        return state.audioEnclosures.filter { enclosure in
            switch downloadAction(state.downloads[enclosure.id]) {
            case .download, .retry:
                true
            case .pending, .delete, .pendingDeletion:
                false
            }
        }
    }

    static func enclosureLabel(_ enclosure: Enclosure, index: Int) -> String {
        IOSListeningListPresentation.enclosureLabel(enclosure, index: index)
    }
}

enum IOSArticleSwipeSide: Hashable {
    case leading
    case trailing
}

enum IOSArticleSwipeSlot: Hashable {
    case fullSwipe
    case additional
}

enum IOSArticleSwipeAction: String, CaseIterable, Hashable {
    case readUnread
    case starUnstar
    case openOriginal
    case openMiniflux
    case comments
    case share
    case saveToService
    case listeningList
    case downloadAudio

    var title: String {
        switch self {
        case .readUnread: String(localized: "Read / Unread")
        case .starUnstar: String(localized: "Star / Unstar")
        case .openOriginal: String(localized: "Open Original")
        case .openMiniflux: String(localized: "Open in Miniflux")
        case .comments: String(localized: "Open Comments")
        case .share: String(localized: "Share")
        case .saveToService: String(localized: "Save to Third-Party Service")
        case .listeningList: String(localized: "Listening List")
        case .downloadAudio: String(localized: "Download Audio")
        }
    }

    var contextAction: IOSArticleContextAction? {
        switch self {
        case .readUnread, .starUnstar:
            nil
        case .openOriginal:
            .original
        case .openMiniflux:
            .miniflux
        case .comments:
            .comments
        case .share:
            .share
        case .saveToService:
            .saveToService
        case .listeningList, .downloadAudio:
            nil
        }
    }
}

struct IOSArticleSwipeConfiguration: Equatable {
    /// Stored in visual inner-to-outer order. The last element is therefore
    /// the deliberate Full Swipe action.
    let leading: [IOSArticleSwipeAction]
    let trailing: [IOSArticleSwipeAction]

    static let defaultConfiguration = IOSArticleSwipeConfiguration(
        leading: [.readUnread],
        trailing: [.starUnstar]
    )

    init(
        leading: [IOSArticleSwipeAction],
        trailing: [IOSArticleSwipeAction]
    ) {
        self.leading = Self.normalized(leading)
        self.trailing = Self.normalized(trailing)
    }

    func actions(for side: IOSArticleSwipeSide) -> [IOSArticleSwipeAction] {
        switch side {
        case .leading: leading
        case .trailing: trailing
        }
    }

    func fullSwipeAction(for side: IOSArticleSwipeSide) -> IOSArticleSwipeAction? {
        actions(for: side).last
    }

    func additionalAction(for side: IOSArticleSwipeSide) -> IOSArticleSwipeAction? {
        let actions = actions(for: side)
        return actions.count == 2 ? actions.first : nil
    }

    func setting(
        _ action: IOSArticleSwipeAction?,
        side: IOSArticleSwipeSide,
        slot: IOSArticleSwipeSlot
    ) -> IOSArticleSwipeConfiguration {
        let current = actions(for: side)
        let fullSwipe = current.last
        let additional = current.count == 2 ? current.first : nil
        let updated: [IOSArticleSwipeAction]

        switch slot {
        case .fullSwipe:
            guard let action else {
                updated = []
                break
            }
            if let additional, additional != action {
                updated = [additional, action]
            } else {
                updated = [action]
            }

        case .additional:
            guard let fullSwipe else {
                updated = []
                break
            }
            if let action, action != fullSwipe {
                updated = [action, fullSwipe]
            } else {
                updated = [fullSwipe]
            }
        }

        switch side {
        case .leading:
            return .init(leading: updated, trailing: trailing)
        case .trailing:
            return .init(leading: leading, trailing: updated)
        }
    }

    private static func normalized(
        _ actions: [IOSArticleSwipeAction]
    ) -> [IOSArticleSwipeAction] {
        var seen = Set<IOSArticleSwipeAction>()
        let unique = actions.filter { seen.insert($0).inserted }
        return Array(unique.suffix(2))
    }
}

enum IOSArticleContextMenuPolicy {
    static func commentsURL(_ value: String) -> URL? {
        ArticleOpenRoutingPolicy.validWebURL(value)
    }

    static func originalURL(_ value: String) -> URL? {
        ArticleOpenRoutingPolicy.validWebURL(value)
    }
}

enum IOSArticleListEmptyState: Equatable {
    case syncing
    case loading
    case noNews
    case error(String)

    static func resolve(isSyncing: Bool, isLoading: Bool, errorMessage: String?, hasArticles: Bool) -> Self? {
        guard !hasArticles else { return nil }
        if let errorMessage { return .error(errorMessage) }
        if isSyncing { return .syncing }
        if isLoading { return .loading }
        return .noNews
    }
}
