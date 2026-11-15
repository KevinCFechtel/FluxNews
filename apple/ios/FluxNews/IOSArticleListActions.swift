import SwiftUI

enum IOSBottomAction: String, CaseIterable, Equatable, Hashable, Identifiable {
    case sync
    case filterAndSort
    case toggleReadFilter
    case toggleSortOrder
    case search
    case markAllRead
    case markAllReadAndNext
    case listeningList
    case nowPlaying
    case settings
    case more

    static let fixedLeadingAction: Self = .sync
    static let fixedTrailingAction: Self = .more
    static let defaultConfiguredActions: [Self] = [.filterAndSort]

    static let configurableActions: [Self] = [
        .filterAndSort,
        .toggleReadFilter,
        .toggleSortOrder,
        .search,
        .markAllRead,
        .markAllReadAndNext,
        .listeningList,
        .settings,
    ]

    var id: String { rawValue }

    var settingsTitle: LocalizedStringKey {
        switch self {
        case .sync: "Sync"
        case .filterAndSort: "Filter and Sort"
        case .toggleReadFilter: "All / Unread"
        case .toggleSortOrder: "Sort Order"
        case .search: "Search"
        case .markAllRead: "Mark All as Read"
        case .markAllReadAndNext: "Mark All as Read and Continue"
        case .listeningList: "Listening List"
        case .nowPlaying: "Now Playing"
        case .settings: "Settings"
        case .more: "More"
        }
    }

    var symbolName: String {
        switch self {
        case .sync: "arrow.triangle.2.circlepath"
        case .filterAndSort: "line.3.horizontal.decrease.circle"
        case .toggleReadFilter: "line.3.horizontal.decrease"
        case .toggleSortOrder: "arrow.up.arrow.down.circle"
        case .search: "magnifyingglass"
        case .markAllRead: "checkmark.circle"
        case .markAllReadAndNext: "forward.end.circle"
        case .listeningList: "headphones"
        case .nowPlaying: "play.circle"
        case .settings: "gearshape"
        case .more: "ellipsis.circle"
        }
    }
}

struct IOSArticleListResolvedActions: Equatable {
    let direct: [IOSBottomAction]
    let overflow: [IOSBottomAction]
}

enum IOSArticleListActionPolicy {
    static func normalizedConfiguredActions(from persistedIDs: [String]?) -> [IOSBottomAction] {
        guard let persistedIDs else {
            return IOSBottomAction.defaultConfiguredActions
        }

        var seen = Set<IOSBottomAction>()
        return persistedIDs.compactMap { id in
            guard let action = IOSBottomAction(rawValue: id),
                  IOSBottomAction.configurableActions.contains(action),
                  seen.insert(action).inserted
            else { return nil }
            return action
        }
    }

    static func isAvailable(
        _ action: IOSBottomAction,
        scope: BrowserScope,
        hasNextScope: Bool,
        hasLoadedMedia: Bool,
        playbackStatus: MediaPlaybackPresentationStatus
    ) -> Bool {
        switch action {
        case .filterAndSort, .toggleReadFilter, .toggleSortOrder, .search,
             .listeningList, .settings:
            true
        case .markAllRead:
            switch scope {
            case .all, .category, .feed: true
            case .starred, .search, .listeningList: false
            }
        case .markAllReadAndNext:
            hasNextScope && {
                switch scope {
                case .category, .feed: true
                case .all, .starred, .search, .listeningList: false
                }
            }()
        case .nowPlaying:
            hasLoadedMedia && playbackStatus != .stopped
        case .sync, .more:
            false
        }
    }

    static func resolvedActions(
        configuredActions: [IOSBottomAction],
        directCapacity: Int,
        scope: BrowserScope,
        hasNextScope: Bool,
        hasLoadedMedia: Bool,
        playbackStatus: MediaPlaybackPresentationStatus
    ) -> IOSArticleListResolvedActions {
        let configured = normalizedConfiguredActions(
            from: configuredActions.map(\.rawValue)
        )
        let availableConfigured = configured.filter {
            isAvailable(
                $0,
                scope: scope,
                hasNextScope: hasNextScope,
                hasLoadedMedia: hasLoadedMedia,
                playbackStatus: playbackStatus
            )
        }
        let direct = Array(availableConfigured.prefix(max(0, directCapacity)))
        let directSet = Set(direct)
        let configuredSet = Set(configured)

        let overflowSelected = availableConfigured.filter {
            !directSet.contains($0)
        }
        let overflowUnselected = IOSBottomAction.configurableActions.filter {
            !configuredSet.contains($0)
                && isAvailable(
                    $0,
                    scope: scope,
                    hasNextScope: hasNextScope,
                    hasLoadedMedia: hasLoadedMedia,
                    playbackStatus: playbackStatus
                )
        }

        return .init(
            direct: direct,
            overflow: overflowSelected + overflowUnselected
        )
    }
}

enum IOSListeningListPlayerPresentation {
    static func item(
        for loadedEnclosure: Enclosure?,
        in items: [ListeningListItem]
    ) -> ListeningListItem? {
        guard let loadedEnclosure else { return nil }
        return items.first { item in
            item.articleId == loadedEnclosure.articleId
                && item.audioEnclosures.contains {
                    $0.enclosure.id == loadedEnclosure.id
                }
        }
    }
}

@MainActor
final class IOSArticleListActionPreferences: ObservableObject {
    static let defaultsKey = "articleListActionIDs"

    @Published private(set) var actions: [IOSBottomAction]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        actions = IOSArticleListActionPolicy.normalizedConfiguredActions(
            from: defaults.stringArray(forKey: Self.defaultsKey)
        )
    }

    func setActions(_ actions: [IOSBottomAction]) {
        let normalized = IOSArticleListActionPolicy.normalizedConfiguredActions(
            from: actions.map(\.rawValue)
        )
        self.actions = normalized
        defaults.set(normalized.map(\.rawValue), forKey: Self.defaultsKey)
    }

    func reloadFromDefaults() {
        actions = IOSArticleListActionPolicy.normalizedConfiguredActions(
            from: defaults.stringArray(forKey: Self.defaultsKey)
        )
    }

    func resetToDefault() {
        setActions(IOSBottomAction.defaultConfiguredActions)
    }
}
