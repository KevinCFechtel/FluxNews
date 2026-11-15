import Foundation
import Observation

struct ArticleRowArticle: Equatable, Sendable {
    let id: Int64
    let feedId: Int64
    let categoryId: Int64
    let feedTitle: String
    let title: String
    let url: String
    let commentsUrl: String
    let publishedAt: String
    let readingTimeMinutes: UInt32
    let preview: String
    let imageUrl: String?

    init(article: ArticleSummary) {
        id = article.id
        feedId = article.feedId
        categoryId = article.categoryId
        feedTitle = article.feedTitle
        title = article.title
        url = article.url
        commentsUrl = article.commentsUrl
        publishedAt = article.publishedAt
        readingTimeMinutes = article.readingTimeMinutes
        preview = article.preview
        imageUrl = article.imageUrl
    }
}

enum IOSArticleTemporalPresentation {
    static func relativePublishedAge(_ publishedAt: String, relativeTo referenceDate: Date) -> String {
        ArticleTemporalPresentation.relativePublishedAge(
            publishedAt,
            relativeTo: referenceDate
        )
    }

    static func readingTime(_ minutes: UInt32) -> String? {
        ArticleTemporalPresentation.readingTime(minutes)
    }

    static func spacingLocalizedNumberUnits(_ value: String) -> String {
        ArticleTemporalPresentation.spacingLocalizedNumberUnits(value)
    }
}

struct ArticleRowContent: Equatable, Sendable {
    let article: ArticleRowArticle
    let publishedDate: String
    /// Frozen for the active Timeline generation. Pagination reuses the same
    /// reference date and no timer advances this string while that generation is active.
    let publishedAge: String
    let readingTime: String?
    let imageURL: URL?
    let hasComments: Bool

    init(article: ArticleSummary, referenceDate: Date = .now) {
        self.article = ArticleRowArticle(article: article)
        publishedDate = ISO8601DateFormatter().date(from: article.publishedAt)
            .map { $0.formatted(date: .abbreviated, time: .shortened) } ?? article.publishedAt
        publishedAge = IOSArticleTemporalPresentation.relativePublishedAge(
            article.publishedAt,
            relativeTo: referenceDate
        )
        readingTime = IOSArticleTemporalPresentation.readingTime(article.readingTimeMinutes)
        imageURL = article.imageUrl.flatMap { $0.isEmpty ? nil : URL(string: $0) }
        hasComments = IOSArticleContextMenuPolicy.commentsURL(article.commentsUrl) != nil
    }
}

@Observable final class ArticleRowPresentationState {
    private(set) var content: ArticleRowContent
    var isRead: Bool
    var isStarred: Bool
    private(set) var mutationRevision: UInt64 = 0

    init(article: ArticleSummary, content: ArticleRowContent? = nil) {
        self.content = content ?? ArticleRowContent(article: article)
        isRead = article.isRead
        isStarred = article.isStarred
    }

    func setRead(_ value: Bool) {
        guard isRead != value else { return }
        isRead = value
        mutationRevision &+= 1
    }

    func setStarred(_ value: Bool) {
        guard isStarred != value else { return }
        isStarred = value
        mutationRevision &+= 1
    }

    func reconcile(with article: ArticleSummary, content preparedContent: ArticleRowContent? = nil) {
        if let preparedContent {
            // A structural replacement owns a fresh frozen temporal projection
            // even when the underlying article fields are otherwise unchanged.
            content = preparedContent
        } else if content.article != ArticleRowArticle(article: article) {
            content = ArticleRowContent(article: article)
        }
        setRead(article.isRead)
        setStarred(article.isStarred)
    }

    func reconcileContent(with article: ArticleSummary, content preparedContent: ArticleRowContent) {
        if content.article != ArticleRowArticle(article: article) { content = preparedContent }
    }
}

struct IOSArticleAudioActionState {
    let articleID: Int64
    let enclosures: [Enclosure]
    let isInListeningList: Bool
    let downloads: [Int64: MediaDownload]

    var audioEnclosures: [Enclosure] {
        enclosures.filter { $0.mediaKind == .audio }
    }
}
