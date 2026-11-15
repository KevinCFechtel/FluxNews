@preconcurrency import CoreSpotlight
import Foundation
import OSLog
import UniformTypeIdentifiers

enum NavigationRoute: Hashable {
    case all
    case starred
    case category(Int64)
    case feed(Int64)

    init?(searchableIdentifier: String) {
        let parts = searchableIdentifier.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let id = Int64(parts[1]) else { return nil }
        switch parts[0] {
        case "category": self = .category(id)
        case "feed": self = .feed(id)
        default: return nil
        }
    }
}

struct RoutingCategory: Codable, Equatable {
    let id: Int64
    let title: String
}

struct RoutingFeed: Codable, Equatable {
    let id: Int64
    let categoryId: Int64
    let title: String
    let categoryTitle: String
}

struct RoutingCatalog: Codable, Equatable {
    let categories: [RoutingCategory]
    let feeds: [RoutingFeed]

    init(categories: [RoutingCategory], feeds: [RoutingFeed]) {
        self.categories = categories
        self.feeds = feeds
    }

    static let empty = RoutingCatalog(categories: [], feeds: [])

    init(_ catalog: NavigationCatalog) {
        let categories = catalog.categories.map { RoutingCategory(id: $0.id, title: $0.title) }
        let titles = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.title) })
        self.categories = categories
        feeds = catalog.feeds.map { RoutingFeed(id: $0.id, categoryId: $0.categoryId, title: $0.title, categoryTitle: titles[$0.categoryId] ?? "") }
    }
}

@MainActor
final class AppRouter {
    static let shared = AppRouter()
    private static let catalogKey = "FluxNews.navigationCatalog"
    private var openHandler: ((NavigationRoute) -> Void)?
    private var refreshHandler: (() -> Void)?
    private var widgetActionHandler: ((WidgetAction) -> Void)?
    private var pendingActions: [Action] = []
    private(set) var catalog: RoutingCatalog

    private enum Action { case open(NavigationRoute), refresh, widget(WidgetAction) }

    private init(defaults: UserDefaults = .standard) {
        catalog = defaults.data(forKey: Self.catalogKey).flatMap { try? JSONDecoder().decode(RoutingCatalog.self, from: $0) } ?? .empty
    }

    func configure(open: @escaping (NavigationRoute) -> Void, refresh: @escaping () -> Void, widgetAction: @escaping (WidgetAction) -> Void) {
        openHandler = open
        refreshHandler = refresh
        widgetActionHandler = widgetAction
        let actions = pendingActions
        pendingActions.removeAll()
        actions.forEach(perform)
    }

    func open(_ route: NavigationRoute) { perform(.open(route)) }
    func refresh() { perform(.refresh) }
    func handle(url: URL) -> Bool {
        guard let action = WidgetAction(url: url) else { return false }
        perform(.widget(action))
        return true
    }

    func updateCatalog(_ catalog: NavigationCatalog, defaults: UserDefaults = .standard) {
        let routingCatalog = RoutingCatalog(catalog)
        self.catalog = routingCatalog
        if let data = try? JSONEncoder().encode(routingCatalog) { defaults.set(data, forKey: Self.catalogKey) }
    }

    private func perform(_ action: Action) {
        switch action {
        case .open(let route):
            guard let openHandler else { pendingActions.append(action); return }
            openHandler(route)
        case .refresh:
            guard let refreshHandler else { pendingActions.append(action); return }
            refreshHandler()
        case let .widget(action):
            guard let widgetActionHandler else { pendingActions.append(.widget(action)); return }
            widgetActionHandler(action)
        }
    }
}

@MainActor
final class SpotlightIndexer {
    private static let migrationKey = "FluxNews.spotlight.namedIndexMigration.v1"
    private static let indexName = "FluxNewsNavigation"
    private let logger = Logger(subsystem: "dev.kevincfechtel.fluxNews", category: "spotlight")
    private let index = CSSearchableIndex(name: SpotlightIndexer.indexName)
    private let domainIdentifier = "dev.kevincfechtel.fluxNews.navigation"
    private var pendingItems: [CSSearchableItem]?
    private var isUpdating = false
    private var legacyMigrationInFlight = false
    private var legacyMigrationFinished = UserDefaults.standard.bool(forKey: SpotlightIndexer.migrationKey)

    func update(_ catalog: NavigationCatalog) {
        let routingCatalog = RoutingCatalog(catalog)
        pendingItems = routingCatalog.feeds.map { searchableItem(identifier: "feed:\($0.id)", title: $0.title, description: NSLocalizedString("Feed in FluxNews", comment: "Spotlight feed description"), keywords: [$0.categoryTitle]) }
            + routingCatalog.categories.map { searchableItem(identifier: "category:\($0.id)", title: $0.title, description: NSLocalizedString("Category in FluxNews", comment: "Spotlight category description"), keywords: []) }
        processNextUpdate()
    }

    static func route(from searchableIdentifier: String) -> NavigationRoute? { NavigationRoute(searchableIdentifier: searchableIdentifier) }

    private func searchableItem(identifier: String, title: String, description: String, keywords: [String]) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = title
        attributes.contentDescription = description
        attributes.keywords = ["FluxNews"] + keywords
        return CSSearchableItem(uniqueIdentifier: identifier, domainIdentifier: domainIdentifier, attributeSet: attributes)
    }

    private func processNextUpdate() {
        guard !isUpdating, let items = pendingItems else { return }
        guard legacyMigrationFinished else {
            migrateLegacyDefaultIndex()
            return
        }

        pendingItems = nil
        isUpdating = true
        index.deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.logger.error("named Spotlight index cleanup failed: \(String(describing: error), privacy: .public)")
                }
                guard !items.isEmpty else {
                    self.finishUpdate()
                    return
                }
                self.index.indexSearchableItems(items) { [weak self] error in
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        if let error {
                            self.logger.error("named Spotlight indexing failed: \(String(describing: error), privacy: .public)")
                        } else {
                            self.logger.debug("named Spotlight indexing completed item_count=\(items.count, privacy: .public)")
                        }
                        self.finishUpdate()
                    }
                }
            }
        }
    }

    private func migrateLegacyDefaultIndex() {
        guard !legacyMigrationInFlight else { return }
        legacyMigrationInFlight = true
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.legacyMigrationInFlight = false
                self.legacyMigrationFinished = true
                if let error {
                    self.logger.error("legacy default Spotlight index cleanup failed: \(String(describing: error), privacy: .public)")
                } else {
                    UserDefaults.standard.set(true, forKey: Self.migrationKey)
                    self.logger.notice("migrated Spotlight navigation content to named index")
                }
                self.processNextUpdate()
            }
        }
    }

    private func finishUpdate() {
        isUpdating = false
        processNextUpdate()
    }
}

