import Foundation
import OSLog
import WidgetKit

enum FluxNewsWidgetKind {
    static let headlines = "FluxNewsHeadlinesWidget"
    static let compactStatus = "FluxNewsCompactStatusWidget"
    static let all = [headlines, compactStatus]
}

enum WidgetTimelineReloader {
    static func reloadAll() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

enum WidgetAction: Equatable {
    case article(Int64)
    case open(WidgetContentSelection)
    case sync

    private static var scheme: String {
        WidgetSnapshotConfiguration.widgetURLScheme()
    }
    private static let host = "widget"

    func url() -> URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        switch self {
        case let .article(id):
            components.path = "/v1/article"
            components.queryItems = [URLQueryItem(name: "id", value: String(id))]
        case let .open(selection):
            components.path = "/v1/open"
            var items = [URLQueryItem(name: "scope", value: selection.scope.rawValue)]
            if let id = selection.categoryID { items.append(URLQueryItem(name: "categoryID", value: String(id))) }
            if let id = selection.feedID { items.append(URLQueryItem(name: "feedID", value: String(id))) }
            components.queryItems = items
        case .sync:
            components.path = "/v1/sync"
        }
        return components.url!
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme, url.host == Self.host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let queryItems = components.queryItems ?? []
        guard Set(queryItems.map(\.name)).count == queryItems.count,
              queryItems.allSatisfy({ $0.value != nil }) else { return nil }
        let values = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value!) })
        switch components.path {
        case "/v1/article":
            guard values.count == 1, let rawID = values["id"], let id = Int64(rawID), id > 0 else { return nil }
            self = .article(id)
        case "/v1/sync":
            guard values.isEmpty else { return nil }
            self = .sync
        case "/v1/open":
            guard let rawScope = values["scope"], let scope = WidgetContentScope(rawValue: rawScope) else { return nil }
            let categoryID = values["categoryID"].flatMap(Int64.init)
            let feedID = values["feedID"].flatMap(Int64.init)
            guard categoryID.map({ $0 > 0 }) ?? true, feedID.map({ $0 > 0 }) ?? true else { return nil }
            switch scope {
            case .allNews, .bookmarks:
                guard values.count == 1 else { return nil }
            case .category:
                guard values.count == 2, categoryID != nil, feedID == nil else { return nil }
            case .feed:
                guard values.count == 2, feedID != nil, categoryID == nil else { return nil }
            }
            self = .open(.init(scope: scope, categoryID: categoryID, feedID: feedID))
        default:
            return nil
        }
    }
}

// This is the durable App-to-WidgetKit contract. It deliberately does not
// mirror UniFFI records, Core persistence, or account configuration.
struct WidgetSnapshotV1: Codable, Equatable {
    static let schemaVersion = 1

    enum State: String, Codable { case noAccount, awaitingSuccessfulSync, ready }

    let schemaVersion: Int
    let state: State
    let generatedAt: String
    let lastSuccessfulSyncAt: String?
    let feeds: [Feed]
    let categories: [Category]
    let articles: [Article]
    let counts: Counts
    let configuration: ConfigurationProjectionV1?

    init(
        schemaVersion: Int,
        state: State,
        generatedAt: String,
        lastSuccessfulSyncAt: String?,
        feeds: [Feed],
        categories: [Category],
        articles: [Article],
        counts: Counts,
        configuration: ConfigurationProjectionV1? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.state = state
        self.generatedAt = generatedAt
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.feeds = feeds
        self.categories = categories
        self.articles = articles
        self.counts = counts
        self.configuration = configuration
    }

    struct Feed: Codable, Equatable {
        let id: Int64
        let categoryID: Int64
        let title: String
        let normalIconFile: String?
        let darkIconFile: String?
    }

    struct Category: Codable, Equatable {
        let id: Int64
        let title: String
    }

    struct Article: Codable, Equatable {
        let id: Int64
        let feedID: Int64
        let categoryID: Int64
        let feedTitle: String
        let title: String
        let publishedAt: String
        let isRead: Bool
        let isStarred: Bool
    }

    struct Counts: Codable, Equatable {
        let allUnread: UInt64
        let bookmarks: UInt64
        let feedUnread: [ScopedCount]
        let categoryUnread: [ScopedCount]
    }

    struct ScopedCount: Codable, Equatable {
        let id: Int64
        let count: UInt64
    }

    /// Optional D9 extension. Its absence identifies an original D5 snapshot,
    /// which remains readable with Unread/Newest semantics.
    struct ConfigurationProjectionV1: Codable, Equatable {
        static let version = 1

        let version: Int
        let allArticles: UInt64
        let bookmarksUnread: UInt64
        let feedAll: [ScopedCount]
        let categoryAll: [ScopedCount]

        init(
            version: Int = Self.version,
            allArticles: UInt64,
            bookmarksUnread: UInt64,
            feedAll: [ScopedCount],
            categoryAll: [ScopedCount]
        ) {
            self.version = version
            self.allArticles = allArticles
            self.bookmarksUnread = bookmarksUnread
            self.feedAll = feedAll
            self.categoryAll = categoryAll
        }
    }
}

enum WidgetSnapshotStoreError: Error, Equatable {
    case unavailableAppGroup
    case unsupportedVersion
    case corruptSnapshot
}

enum WidgetSnapshotDiagnostics {
    static let logger = Logger(subsystem: "dev.kevincfechtel.fluxNews", category: "widget_snapshot")
}

enum WidgetSnapshotConfiguration {
    static let infoKey = "FluxWidgetAppGroupIdentifier"
    static let urlSchemeInfoKey = "FluxWidgetURLScheme"
    static let productionAppGroupIdentifier = "group.dev.kevincfechtel.fluxNews"

    static func appGroupIdentifier(bundle: Bundle = .main) -> String {
        guard let configured = bundle.object(forInfoDictionaryKey: infoKey) as? String,
              !configured.isEmpty else {
            return productionAppGroupIdentifier
        }
        return configured
    }

    static func widgetURLScheme(bundle: Bundle = .main) -> String {
        guard let configured = bundle.object(forInfoDictionaryKey: urlSchemeInfoKey) as? String,
              !configured.isEmpty else {
            return "fluxnews"
        }
        return configured
    }
}

final class WidgetSnapshotStore {
    static var appGroupIdentifier: String {
        WidgetSnapshotConfiguration.appGroupIdentifier()
    }

    private static let fileName = "widget-snapshot-v1.json"
    private let root: URL

    init(root: URL) {
        self.root = root
    }

    convenience init(
        appGroupContainer: URL? = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
    ) throws {
        guard let appGroupContainer else {
            throw WidgetSnapshotStoreError.unavailableAppGroup
        }
        self.init(root: appGroupContainer.appendingPathComponent("Widgets", isDirectory: true))
    }

    convenience init(diagnostics logger: Logger) throws {
        let identifier = Self.appGroupIdentifier
        guard let appGroupContainer = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) else {
            logger.error("Widget snapshot App Group container resolution failed identifier=\(identifier, privacy: .public)")
            throw WidgetSnapshotStoreError.unavailableAppGroup
        }
        let root = appGroupContainer.appendingPathComponent("Widgets", isDirectory: true)
        logger.notice("Widget snapshot App Group container resolved identifier=\(identifier, privacy: .public) path=\(appGroupContainer.path, privacy: .public)")
        logger.notice("Widget snapshot expected path=\(root.appendingPathComponent(Self.fileName).path, privacy: .public)")
        self.init(root: root)
    }

    func write(_ snapshot: WidgetSnapshotV1) throws {
        guard snapshot.schemaVersion == WidgetSnapshotV1.schemaVersion else {
            throw WidgetSnapshotStoreError.unsupportedVersion
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: snapshotURL, options: .atomic)
    }

    func read() throws -> WidgetSnapshotV1? {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else { return nil }
        do {
            let snapshot = try JSONDecoder().decode(
                WidgetSnapshotV1.self,
                from: Data(contentsOf: snapshotURL)
            )
            guard snapshot.schemaVersion == WidgetSnapshotV1.schemaVersion else {
                throw WidgetSnapshotStoreError.unsupportedVersion
            }
            return snapshot
        } catch let error as WidgetSnapshotStoreError {
            throw error
        } catch {
            throw WidgetSnapshotStoreError.corruptSnapshot
        }
    }

    func read(diagnostics logger: Logger) throws -> WidgetSnapshotV1? {
        let exists = FileManager.default.fileExists(atPath: snapshotURL.path)
        logger.notice("Widget snapshot file exists=\(exists, privacy: .public) path=\(self.snapshotURL.path, privacy: .public)")
        guard exists else { return nil }

        let data: Data
        do {
            data = try Data(contentsOf: snapshotURL)
            logger.notice("Widget snapshot read succeeded")
        } catch {
            log(error, operation: "read", to: logger)
            throw error
        }

        do {
            let snapshot = try JSONDecoder().decode(WidgetSnapshotV1.self, from: data)
            guard snapshot.schemaVersion == WidgetSnapshotV1.schemaVersion else {
                throw WidgetSnapshotStoreError.unsupportedVersion
            }
            logger.notice("Widget snapshot JSON decoding succeeded")
            return snapshot
        } catch {
            log(error, operation: "decode", to: logger)
            if let error = error as? WidgetSnapshotStoreError {
                throw error
            }
            throw WidgetSnapshotStoreError.corruptSnapshot
        }
    }

    func invalidate() throws {
        if FileManager.default.fileExists(atPath: snapshotURL.path) {
            try FileManager.default.removeItem(at: snapshotURL)
        }
        if FileManager.default.fileExists(atPath: iconsURL.path) {
            try FileManager.default.removeItem(at: iconsURL)
        }
    }

    func writeIcon(_ data: Data, feedID: Int64, dark: Bool) throws -> String {
        try FileManager.default.createDirectory(at: iconsURL, withIntermediateDirectories: true)
        let name = "feed-\(feedID)-\(dark ? "dark" : "normal").png"
        try data.write(to: iconsURL.appendingPathComponent(name), options: .atomic)
        return "icons/\(name)"
    }

    func readIcon(relativePath: String?) -> Data? {
        guard let relativePath,
              relativePath.hasPrefix("icons/"),
              !relativePath.contains(".."),
              URL(fileURLWithPath: relativePath).lastPathComponent
                == String(relativePath.dropFirst("icons/".count)) else {
            return nil
        }
        return try? Data(
            contentsOf: iconsURL.appendingPathComponent(
                URL(fileURLWithPath: relativePath).lastPathComponent
            )
        )
    }

    var snapshotPath: String {
        snapshotURL.path
    }

    private var snapshotURL: URL {
        root.appendingPathComponent(Self.fileName)
    }

    private var iconsURL: URL {
        root.appendingPathComponent("icons", isDirectory: true)
    }

    private func log(_ error: Error, operation: String, to logger: Logger) {
        logger.error(
            "Widget snapshot \(operation, privacy: .public) failed error_type=\(String(reflecting: type(of: error)), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
        )
    }
}
