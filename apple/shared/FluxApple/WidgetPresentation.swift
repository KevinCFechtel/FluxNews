import Foundation
import WidgetKit

enum WidgetFamilyPolicy {
    static let headlineFamilies: [WidgetFamily] = [
        .systemMedium,
        .systemLarge,
        .systemExtraLarge,
    ]

    #if os(iOS)
    static let statusFamilies: [WidgetFamily] = [
        .systemSmall,
        .systemMedium,
        .accessoryInline,
        .accessoryCircular,
        .accessoryRectangular,
    ]

    static let lockScreenFamilies: [WidgetFamily] = [
        .accessoryInline,
        .accessoryCircular,
        .accessoryRectangular,
    ]
    #else
    static let statusFamilies: [WidgetFamily] = [
        .systemSmall,
        .systemMedium,
    ]

    static let lockScreenFamilies: [WidgetFamily] = []
    #endif
}

enum WidgetSyncTimestamp {
    static func date(from value: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: value)
    }
}

enum HeadlinesPresentation {
    static func capacity(for family: WidgetFamily) -> Int {
        switch family {
        case .systemMedium: 3
        case .systemLarge: 7
        case .systemExtraLarge: 12
        default: 1
        }
    }
}

enum WidgetContentScope: String, CaseIterable {
    case allNews
    case bookmarks
    case category
    case feed
}

enum WidgetReadFilter: String, CaseIterable {
    case unread
    case all
}

enum WidgetSortOrder: String, CaseIterable {
    case newestFirst
    case oldestFirst
}

struct WidgetContentSelection: Equatable {
    let scope: WidgetContentScope
    let categoryID: Int64?
    let feedID: Int64?
    let readFilter: WidgetReadFilter
    let sortOrder: WidgetSortOrder

    init(
        scope: WidgetContentScope,
        categoryID: Int64?,
        feedID: Int64?,
        readFilter: WidgetReadFilter? = nil,
        sortOrder: WidgetSortOrder = .newestFirst
    ) {
        self.scope = scope
        self.categoryID = categoryID
        self.feedID = feedID
        self.readFilter = readFilter ?? (scope == .bookmarks ? .all : .unread)
        self.sortOrder = sortOrder
    }
}


enum WidgetLegacyDefaultStore {
    static let applicationGroup = "group.dev.kevincfechtel.fluxNews"

    private enum Key {
        static let version = "FluxNews.Widget.legacyDefaults.version"
        static let scope = "FluxNews.Widget.legacyDefaults.scope"
        static let categoryID = "FluxNews.Widget.legacyDefaults.categoryID"
        static let feedID = "FluxNews.Widget.legacyDefaults.feedID"
        static let readFilter = "FluxNews.Widget.legacyDefaults.readFilter"
        static let sortOrder = "FluxNews.Widget.legacyDefaults.sortOrder"
    }

    static func containsConfiguration(
        in defaults: UserDefaults? = UserDefaults(suiteName: applicationGroup)
    ) -> Bool {
        defaults?.object(forKey: Key.version) != nil
    }

    static func load(
        from defaults: UserDefaults? = UserDefaults(suiteName: applicationGroup)
    ) -> WidgetContentSelection? {
        guard let defaults,
              defaults.integer(forKey: Key.version) == 1,
              let scopeRaw = defaults.string(forKey: Key.scope),
              let scope = WidgetContentScope(rawValue: scopeRaw),
              let readFilterRaw = defaults.string(forKey: Key.readFilter),
              let readFilter = WidgetReadFilter(rawValue: readFilterRaw),
              let sortOrderRaw = defaults.string(forKey: Key.sortOrder),
              let sortOrder = WidgetSortOrder(rawValue: sortOrderRaw) else {
            return nil
        }

        let categoryID = defaults.object(forKey: Key.categoryID).flatMap {
            ($0 as? NSNumber)?.int64Value
        }
        let feedID = defaults.object(forKey: Key.feedID).flatMap {
            ($0 as? NSNumber)?.int64Value
        }
        if scope == .category, categoryID == nil { return nil }
        if scope == .feed, feedID == nil { return nil }

        return .init(
            scope: scope,
            categoryID: scope == .category ? categoryID : nil,
            feedID: scope == .feed ? feedID : nil,
            readFilter: readFilter,
            sortOrder: sortOrder
        )
    }

    @discardableResult
    static func save(
        _ selection: WidgetContentSelection,
        to defaults: UserDefaults? = UserDefaults(suiteName: applicationGroup)
    ) -> Bool {
        guard let defaults else { return false }
        if selection.scope == .category, selection.categoryID == nil { return false }
        if selection.scope == .feed, selection.feedID == nil { return false }

        defaults.set(selection.scope.rawValue, forKey: Key.scope)
        defaults.set(selection.readFilter.rawValue, forKey: Key.readFilter)
        defaults.set(selection.sortOrder.rawValue, forKey: Key.sortOrder)

        if selection.scope == .category, let categoryID = selection.categoryID {
            defaults.set(categoryID, forKey: Key.categoryID)
        } else {
            defaults.removeObject(forKey: Key.categoryID)
        }
        if selection.scope == .feed, let feedID = selection.feedID {
            defaults.set(feedID, forKey: Key.feedID)
        } else {
            defaults.removeObject(forKey: Key.feedID)
        }

        defaults.set(1, forKey: Key.version)
        return true
    }
}

enum WidgetContentState: Equatable {
    case missingSnapshot
    case corruptSnapshot
    case noAccount
    case awaitingSuccessfulSync
    case unavailableSelection(String)
    case empty
    case ready
}

struct WidgetContentModel: Equatable {
    let state: WidgetContentState
    let title: String
    let count: UInt64
    let countLabel: String
    let articles: [WidgetSnapshotV1.Article]
    let lastSuccessfulSyncAt: String?

    func latestArticles(limit: Int) -> [WidgetSnapshotV1.Article] {
        Array(articles.prefix(limit))
    }

    static func make(
        snapshotResult: Result<WidgetSnapshotV1?, Error>,
        selection: WidgetContentSelection
    ) -> Self {
        guard case let .success(snapshot?) = snapshotResult else {
            return .init(
                state: snapshotResult.isSuccess ? .missingSnapshot : .corruptSnapshot,
                title: "FluxNews",
                count: 0,
                countLabel: "unread",
                articles: [],
                lastSuccessfulSyncAt: nil
            )
        }

        switch snapshot.state {
        case .noAccount:
            return .init(
                state: .noAccount,
                title: "FluxNews",
                count: 0,
                countLabel: "unread",
                articles: [],
                lastSuccessfulSyncAt: nil
            )
        case .awaitingSuccessfulSync:
            return .init(
                state: .awaitingSuccessfulSync,
                title: "FluxNews",
                count: 0,
                countLabel: "unread",
                articles: [],
                lastSuccessfulSyncAt: nil
            )
        case .ready:
            break
        }

        if selection.scope == .category,
           (selection.categoryID == nil
            || !snapshot.categories.contains(where: { $0.id == selection.categoryID })) {
            return unavailable(
                title: "Category",
                message: "Selected category unavailable",
                lastSuccessfulSyncAt: snapshot.lastSuccessfulSyncAt
            )
        }

        if selection.scope == .feed,
           (selection.feedID == nil
            || !snapshot.feeds.contains(where: { $0.id == selection.feedID })) {
            return unavailable(
                title: "Feed",
                message: "Selected feed unavailable",
                lastSuccessfulSyncAt: snapshot.lastSuccessfulSyncAt
            )
        }

        let requiresD9Projection =
            selection.sortOrder == .oldestFirst
                || (selection.scope == .bookmarks
                    ? selection.readFilter == .unread
                    : selection.readFilter == .all)
        if requiresD9Projection,
           snapshot.configuration?.version != WidgetSnapshotV1.ConfigurationProjectionV1.version {
            return unavailable(
                title: resolvedTitle(snapshot: snapshot, selection: selection),
                message: "Open FluxNews to refresh widget data",
                lastSuccessfulSyncAt: snapshot.lastSuccessfulSyncAt
            )
        }

        let resolved = resolvedCount(snapshot: snapshot, selection: selection)
        let articles = filtered(snapshot: snapshot, selection: selection)
        return .init(
            state: articles.isEmpty ? .empty : .ready,
            title: resolved.title,
            count: resolved.count,
            countLabel: resolved.label,
            articles: articles,
            lastSuccessfulSyncAt: snapshot.lastSuccessfulSyncAt
        )
    }

    private static func unavailable(
        title: String,
        message: String,
        lastSuccessfulSyncAt: String?
    ) -> Self {
        .init(
            state: .unavailableSelection(message),
            title: title,
            count: 0,
            countLabel: "unread",
            articles: [],
            lastSuccessfulSyncAt: lastSuccessfulSyncAt
        )
    }

    private static func resolvedTitle(
        snapshot: WidgetSnapshotV1,
        selection: WidgetContentSelection
    ) -> String {
        switch selection.scope {
        case .allNews:
            "All News"
        case .bookmarks:
            "Bookmarks"
        case .category:
            snapshot.categories.first(where: { $0.id == selection.categoryID })?.title
                ?? "Category"
        case .feed:
            snapshot.feeds.first(where: { $0.id == selection.feedID })?.title
                ?? "Feed"
        }
    }

    private static func resolvedCount(
        snapshot: WidgetSnapshotV1,
        selection: WidgetContentSelection
    ) -> (title: String, count: UInt64, label: String) {
        let configuration = snapshot.configuration
        switch selection.scope {
        case .allNews:
            if selection.readFilter == .all {
                return (
                    "All News",
                    configuration?.allArticles ?? snapshot.counts.allUnread,
                    "articles"
                )
            }
            return ("All News", snapshot.counts.allUnread, "unread")
        case .bookmarks:
            if selection.readFilter == .unread {
                return (
                    "Bookmarks",
                    configuration?.bookmarksUnread ?? 0,
                    "unread"
                )
            }
            return ("Bookmarks", snapshot.counts.bookmarks, "bookmarked")
        case .category:
            let id = selection.categoryID!
            let title = snapshot.categories.first(where: { $0.id == id })!.title
            if selection.readFilter == .all {
                return (
                    title,
                    configuration?.categoryAll.first(where: { $0.id == id })?.count ?? 0,
                    "articles"
                )
            }
            return (
                title,
                snapshot.counts.categoryUnread.first(where: { $0.id == id })?.count ?? 0,
                "unread"
            )
        case .feed:
            let id = selection.feedID!
            let title = snapshot.feeds.first(where: { $0.id == id })!.title
            if selection.readFilter == .all {
                return (
                    title,
                    configuration?.feedAll.first(where: { $0.id == id })?.count ?? 0,
                    "articles"
                )
            }
            return (
                title,
                snapshot.counts.feedUnread.first(where: { $0.id == id })?.count ?? 0,
                "unread"
            )
        }
    }

    private static func filtered(
        snapshot: WidgetSnapshotV1,
        selection: WidgetContentSelection
    ) -> [WidgetSnapshotV1.Article] {
        snapshot.articles.filter { article in
            let scopeMatches: Bool
            switch selection.scope {
            case .allNews:
                scopeMatches = true
            case .bookmarks:
                scopeMatches = article.isStarred
            case .category:
                scopeMatches = article.categoryID == selection.categoryID
            case .feed:
                scopeMatches = article.feedID == selection.feedID
            }
            guard scopeMatches else { return false }

            switch selection.readFilter {
            case .unread:
                return !article.isRead
            case .all:
                return true
            }
        }
        .sorted { lhs, rhs in
            let left = (lhs.publishedAt, lhs.id)
            let right = (rhs.publishedAt, rhs.id)
            switch selection.sortOrder {
            case .newestFirst:
                return left > right
            case .oldestFirst:
                return left < right
            }
        }
    }
}

private extension Result where Success == WidgetSnapshotV1?, Failure == Error {
    var isSuccess: Bool {
        if case .success = self { true } else { false }
    }
}
