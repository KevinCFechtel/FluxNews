import Foundation

enum ClickOnNews: String, CaseIterable { case openLink, openDetailView }
enum NormalOpenAction: Equatable { case original, miniflux, detail }

enum ArticleOpenRouting {
    static func action(clickOnNews: ClickOnNews, openInMiniflux: Bool) -> NormalOpenAction {
        if clickOnNews == .openDetailView { return .detail }
        return openInMiniflux ? .miniflux : .original
    }
}

enum ArticleOpenDestination: Equatable {
    case universalLink(URL)
    case browser(URL)
    case invalid
}

enum ArticleOpenRoutingPolicy {
    static func validWebURL(_ value: String) -> URL? {
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased()), url.host != nil else { return nil }
        return url
    }

    static func destination(originalURL: String, universalLinkSucceeded: Bool) -> ArticleOpenDestination {
        guard let original = validWebURL(originalURL) else { return .invalid }
        return universalLinkSucceeded ? .universalLink(original) : .browser(original)
    }
}

enum BrowserScope: Hashable { case all, starred, search, listeningList, category(Int64), feed(Int64) }

enum StartupScopePreference: String, CaseIterable { case allNews, starred, category, feed }

enum StartupScopeResolver {
    static func resolve(_ preference: StartupScopePreference, categoryID: Int64?, feedID: Int64?, categoryIDs: Set<Int64>, feedIDs: Set<Int64>) -> BrowserScope {
        switch preference {
        case .allNews: .all
        case .starred: .starred
        case .category: categoryID.map { categoryIDs.contains($0) ? .category($0) : .all } ?? .all
        case .feed: feedID.map { feedIDs.contains($0) ? .feed($0) : .all } ?? .all
        }
    }
}

struct NavigationPresentationFeed: Equatable { let id: Int64; let categoryID: Int64 }
struct NavigationPresentationCategory: Equatable { let id: Int64; let title: String }

struct NavigationPresentationGroup: Identifiable, Equatable {
    let id: Int64
    let title: String
    let categoryID: Int64?
    let feeds: [NavigationPresentationFeed]
}

enum NavigationVisibility {
    static func visibleFeeds(_ feeds: [NavigationPresentationFeed], hidingEmpty: Bool, counts: [Int64: UInt64]) -> [NavigationPresentationFeed] {
        hidingEmpty ? feeds.filter { counts[$0.id, default: 0] > 0 } : feeds
    }
    static func visibleCategoryIDs(_ categoryIDs: [Int64], feeds: [NavigationPresentationFeed]) -> [Int64] {
        let visible = Set(feeds.map(\.categoryID)); return categoryIDs.filter { visible.contains($0) }
    }

    static func groups(categories: [NavigationPresentationCategory], feeds: [NavigationPresentationFeed], hidingEmpty: Bool, counts: [Int64: UInt64]) -> [NavigationPresentationGroup] {
        let visibleFeeds = visibleFeeds(feeds, hidingEmpty: hidingEmpty, counts: counts)
        let visibleIDs = Set(visibleFeeds.map(\.id))
        let categoryIDs = Set(categories.map(\.id))
        var groups = categories.compactMap { category -> NavigationPresentationGroup? in
            let categoryFeeds = feeds.filter { $0.categoryID == category.id && visibleIDs.contains($0.id) }
            guard !hidingEmpty || !categoryFeeds.isEmpty else { return nil }
            return NavigationPresentationGroup(id: category.id, title: category.title, categoryID: category.id, feeds: categoryFeeds)
        }
        let orphanFeeds = feeds.filter { visibleIDs.contains($0.id) && !categoryIDs.contains($0.categoryID) }
        if !orphanFeeds.isEmpty {
            groups.append(NavigationPresentationGroup(id: Int64.min, title: "Other Feeds", categoryID: nil, feeds: orphanFeeds))
        }
        return groups
    }
}

enum ArticleListPresentationPolicy {
    static func removesMarkedReadArticle(removeWhenMarkedRead: Bool, unreadOnly: Bool, scope: BrowserScope) -> Bool {
        removeWhenMarkedRead && unreadOnly && scope != .search && scope != .listeningList
    }
}

enum ArticlePresentationMode: String, CaseIterable { case visual, visualCompact, compact }
extension ArticlePresentationMode {
    var showsArticleImage: Bool { self != .compact }

    /// Localisation key. Not derived from `rawValue`, which would produce
    /// "Visualcompact".
    var displayNameKey: String {
        switch self {
        case .visual: return "Visual"
        case .visualCompact: return "Visual compact"
        case .compact: return "Compact"
        }
    }
}
enum ArticlePresentationLayout {
    static let portraitImageAspectRatio: CGFloat = 16.0 / 9.0
    static let landscapeImageAspectRatio: CGFloat = 16.0 / 9.0
    static let landscapeImageAllocation: CGFloat = 0.48
    static let cardHorizontalPadding: CGFloat = 24

    static func usesLandscapeVisual(mode: ArticlePresentationMode, availableWidth: CGFloat) -> Bool {
        mode == .visual && availableWidth > 600
    }

    static func boundedArticleWidth(_ availableWidth: CGFloat) -> CGFloat {
        max(0, availableWidth)
    }

    static func articleContentWidth(_ availableWidth: CGFloat) -> CGFloat {
        max(0, boundedArticleWidth(availableWidth) - cardHorizontalPadding)
    }

    static func visualPortraitContentWidth(_ availableWidth: CGFloat) -> CGFloat {
        boundedArticleWidth(availableWidth)
    }

    static func portraitImageHeight(contentWidth: CGFloat) -> CGFloat {
        contentWidth / portraitImageAspectRatio
    }

    static func landscapeImageWidth(availableWidth: CGFloat) -> CGFloat {
        articleContentWidth(availableWidth) * landscapeImageAllocation
    }

    static func landscapeTextWidth(availableWidth: CGFloat, imageWidth: CGFloat, interColumnSpacing: CGFloat) -> CGFloat {
        max(0, articleContentWidth(availableWidth) - imageWidth - interColumnSpacing)
    }

    static func landscapeImageHeight(imageWidth: CGFloat) -> CGFloat {
        imageWidth / landscapeImageAspectRatio
    }

    static func internalUnreadIndicatorOpacity(isRead: Bool) -> CGFloat { isRead ? 0 : 1 }
}
enum ArticlePreviewLines: Int, CaseIterable { case compact = 2, standard = 3, extended = 5 }


enum ArticleTemporalPresentation {
    static func absolutePublishedDate(_ publishedAt: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: publishedAt) else { return publishedAt }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func relativePublishedAge(_ publishedAt: String, relativeTo referenceDate: Date) -> String {
        guard let date = ISO8601DateFormatter().date(from: publishedAt) else { return publishedAt }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .numeric
        return spacingLocalizedNumberUnits(
            formatter.localizedString(for: date, relativeTo: referenceDate)
        )
    }

    static func publicationValue(_ publishedAt: String, showRelative: Bool, relativeTo referenceDate: Date) -> String {
        showRelative
            ? relativePublishedAge(publishedAt, relativeTo: referenceDate)
            : absolutePublishedDate(publishedAt)
    }

    static func readingTime(_ minutes: UInt32) -> String? {
        guard minutes > 0 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: TimeInterval(minutes) * 60)
            .map(spacingLocalizedNumberUnits)
    }

    static func spacingLocalizedNumberUnits(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count + 1)
        var previous: Character?

        for character in value {
            if let previous, previous.isNumber, character.isLetter {
                result.append(" ")
            }
            result.append(character)
            previous = character
        }
        return result
    }
}
