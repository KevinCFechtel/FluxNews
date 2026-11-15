import AppKit

enum ReaderDocumentSource: Equatable {
    case local
    case search

    static func forScope(_ scope: BrowserScope) -> Self {
        scope == .search ? .search : .local
    }
}

enum FeedSettingsRouting {
    static func isAvailable(feedID: Int64?) -> Bool { feedID != nil }
}

enum ReaderPreviewAction: Equatable {
    case show
    case replace
    case hide

    static func resolve(isVisible: Bool, currentArticleID: Int64?, requestedArticleID: Int64, togglesSameArticle: Bool) -> Self {
        if isVisible, currentArticleID == requestedArticleID, togglesSameArticle { return .hide }
        return isVisible ? .replace : .show
    }
}

enum ReaderPreviewGeometry {
    static let defaultSize = NSSize(width: 800, height: 700)
    static let sizeDefaultsKey = "FluxNews.ReaderPreview.Size"

    static func validSize(_ size: NSSize) -> NSSize? {
        guard size.width >= 500, size.height >= 400, size.width <= 2_000, size.height <= 1_600 else { return nil }
        return size
    }

    static func persistedSize(defaults: UserDefaults = .standard) -> NSSize {
        guard let values = defaults.array(forKey: sizeDefaultsKey), values.count == 2,
              let width = values[0] as? NSNumber,
              let height = values[1] as? NSNumber,
              let size = validSize(NSSize(width: width.doubleValue, height: height.doubleValue)) else { return defaultSize }
        return size
    }

    static func persist(size: NSSize, defaults: UserDefaults = .standard) {
        guard let size = validSize(size) else { return }
        defaults.set([size.width, size.height], forKey: sizeDefaultsKey)
    }

    static func centeredFrame(size: NSSize, visibleFrame: NSRect) -> NSRect {
        let fittedSize = NSSize(width: min(size.width, visibleFrame.width), height: min(size.height, visibleFrame.height))
        return NSRect(x: visibleFrame.midX - fittedSize.width / 2, y: visibleFrame.midY - fittedSize.height / 2, width: fittedSize.width, height: fittedSize.height)
    }
}

enum ReaderArticleState {
    static func starredState(articleID: Int64, visibleArticles: [(id: Int64, isStarred: Bool)]) -> Bool? {
        visibleArticles.first(where: { $0.id == articleID })?.isStarred
    }
}
