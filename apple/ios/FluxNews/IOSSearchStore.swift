import Combine
import Foundation

enum IOSSearchPaginationPolicy {
    static let pageSize: UInt32 = 50

    static func nextOffset(resultCount: Int, total: Int64) -> Int64? {
        guard Int64(resultCount) < total else { return nil }
        return Int64(resultCount)
    }

    static func canLoadMore(resultCount: Int, total: Int64, hasSearched: Bool, isSearching: Bool, isLoadingMore: Bool, hasError: Bool) -> Bool {
        hasSearched && !isSearching && !isLoadingMore && !hasError && nextOffset(resultCount: resultCount, total: total) != nil
    }

    static func deduplicated(_ articles: [ArticleSummary]) -> [ArticleSummary] {
        var seen = Set<Int64>()
        return articles.filter { seen.insert($0.id).inserted }
    }
}

struct IOSSearchRequestState {
    private(set) var generation: UInt64 = 0

    mutating func begin() -> UInt64 {
        generation &+= 1
        return generation
    }

    mutating func invalidate() { generation &+= 1 }

    func isCurrent(_ request: UInt64) -> Bool { request == generation }
}

@MainActor
final class IOSSearchStore: ObservableObject {
    @Published var query = ""
    @Published private(set) var submittedQuery = ""
    @Published private(set) var results: [ArticleSummary] = []
    private(set) var timelineStructuralState = IOSUIKitArticleTimelineStructuralState(items: [], revision: 0)
    let timelinePresentationBridge = IOSUIKitArticleTimelinePresentationBridge()
    @Published private(set) var total: Int64 = 0
    @Published private(set) var hasSearched = false
    @Published private(set) var isSearching = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var readCompletionFeedbackRevision: UInt64 = 0
    @Published private(set) var starCompletionFeedbackRevision: UInt64 = 0
    @Published private(set) var articleAudioActionStates: [Int64: IOSArticleAudioActionState] = [:]

    private enum MutationFeedback {
        case read
        case starred
    }

    private(set) var core: Flux?
    private var coreSessionExecutionCoordinator = IOSCoreSessionExecutionCoordinator()
    private var requestState = IOSSearchRequestState()
    private var paginationExhausted = false
    private var searchReferenceDate = Date.now
    private let pageSize = IOSSearchPaginationPolicy.pageSize
    var onLocalFirstMutation: () -> Void = {}
    var onMediaTransferReconciliationRequested: (() async -> Void)?
    var onMediaArtworkProbeChanged: (() -> Void)?
    private var articleAudioActionGeneration: UInt64 = 0

    func attach(
        to core: Flux,
        coreSessionExecutionCoordinator: IOSCoreSessionExecutionCoordinator? = nil
    ) {
        invalidate()
        if let coreSessionExecutionCoordinator {
            self.coreSessionExecutionCoordinator = coreSessionExecutionCoordinator
        }
        self.coreSessionExecutionCoordinator.ensureActive(core)
        self.core = core
    }
    func detach() { invalidate(); core = nil; clear() }

    func submit() {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let core else { return }
        let requestGeneration = requestState.begin()
        let pageSize = pageSize
        searchReferenceDate = .now
        submittedQuery = value
        replaceResults([])
        total = 0
        hasSearched = true
        isSearching = true
        isLoadingMore = false
        paginationExhausted = false
        errorMessage = nil

        let sessionCoordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, sessionCoordinator] in
            guard let result = await sessionCoordinator.blockingResult(
                for: core,
                {
                    try core.searchArticles(
                        request: SearchArticlesRequest(query: value, offset: 0, limit: pageSize)
                    )
                }
            ) else { return }
            guard let self, self.requestState.isCurrent(requestGeneration) else { return }
            self.isSearching = false
            switch result {
            case let .success(page):
                self.total = page.total
                self.paginationExhausted = page.articles.isEmpty || Int64(page.articles.count) >= page.total
                self.replaceResults(IOSSearchPaginationPolicy.deduplicated(page.articles))
            case let .failure(error): self.errorMessage = IOSErrorPresentation.message(for: error, context: .search)
            }
        }
    }

    func clear() {
        requestState.invalidate()
        query = ""
        submittedQuery = ""
        replaceResults([])
        total = 0
        hasSearched = false
        isSearching = false
        isLoadingMore = false
        paginationExhausted = false
        errorMessage = nil
    }

    func invalidate() {
        requestState.invalidate()
        isSearching = false
        isLoadingMore = false
    }

    func loadMore() {
        guard let core, hasSearched, !isSearching, !isLoadingMore, errorMessage == nil,
              !paginationExhausted,
              IOSSearchPaginationPolicy.canLoadMore(resultCount: results.count, total: total, hasSearched: hasSearched, isSearching: isSearching, isLoadingMore: isLoadingMore, hasError: errorMessage != nil) else { return }
        let requestGeneration = requestState.generation
        let offset = Int64(results.count)
        let value = submittedQuery
        isLoadingMore = true

        let sessionCoordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, sessionCoordinator] in
            guard let result = await sessionCoordinator.blockingResult(
                for: core,
                {
                    try core.searchArticles(
                        request: SearchArticlesRequest(
                            query: value,
                            offset: offset,
                            limit: IOSSearchPaginationPolicy.pageSize
                        )
                    )
                }
            ) else { return }
            guard let self, self.requestState.isCurrent(requestGeneration) else { return }
            self.isLoadingMore = false
            switch result {
            case let .success(page):
                self.total = page.total
                let updated = IOSSearchPaginationPolicy.deduplicated(self.results + page.articles)
                self.paginationExhausted = page.articles.isEmpty || updated.count == self.results.count || Int64(updated.count) >= page.total
                self.replaceResults(updated)
            case let .failure(error): self.errorMessage = IOSErrorPresentation.message(for: error, context: .search)
            }
        }
    }

    func retry() {
        query = submittedQuery
        submit()
    }

    func setRead(_ article: ArticleSummary, read: Bool, providesFeedback: Bool = true) {
        mutate(
            articleID: article.id,
            read: read,
            feedback: providesFeedback && read ? .read : nil
        )
    }

    func setStarred(_ article: ArticleSummary, starred: Bool) {
        mutate(articleID: article.id, starred: starred, feedback: .starred)
    }

    func open(_ article: ArticleSummary, completion: @escaping (String) -> Void) {
        setRead(article, read: true, providesFeedback: false)
        completion(article.url)
    }

    func openReader(_ article: ArticleSummary, completion: @escaping (Result<ReaderDocument, Error>) -> Void) {
        setRead(article, read: true, providesFeedback: false)
        guard let core else {
            completion(.failure(IOSCoreError.notConfigured))
            return
        }
        let requestGeneration = requestState.generation
        let sessionCoordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, sessionCoordinator] in
            guard let result = await sessionCoordinator.blockingResult(
                for: core,
                { try core.readerDocumentForSearch(articleId: article.id) }
            ) else { return }
            guard let self, self.requestState.isCurrent(requestGeneration) else { return }
            completion(result)
        }
    }

    func minifluxEntryURL(for article: ArticleSummary, completion: @escaping (Result<String, Error>) -> Void) {
        guard let core else {
            completion(.failure(IOSCoreError.notConfigured))
            return
        }
        completion(.success(core.minifluxEntryUrl(articleId: article.id)))
    }

    func saveToService(_ article: ArticleSummary, completion: @escaping (Result<SaveToServiceResult, Error>) -> Void) {
        guard let core else {
            completion(.failure(IOSCoreError.notConfigured))
            return
        }
        let sessionCoordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, sessionCoordinator] in
            guard let result = await sessionCoordinator.blockingResult(
                for: core,
                { try core.saveToService(articleId: article.id) }
            ) else { return }
            guard self != nil else { return }
            completion(result)
        }
    }

    func setArticleListeningListMembership(
        articleID: Int64,
        isInListeningList: Bool
    ) async -> Result<Void, Error> {
        let result = await mutateArticleMedia(
            articleID: articleID,
            operation: { core in
                if isInListeningList {
                    try core.addToListeningList(articleId: articleID)
                } else {
                    try core.removeFromListeningList(articleId: articleID)
                }
            },
            reconcileTransfers: true
        )
        if isInListeningList, case .success = result {
            requestMediaArtworkProbe(articleID: articleID)
        }
        return result
    }

    func requestArticleDownload(
        articleID: Int64,
        enclosureID: Int64
    ) async -> Result<Void, Error> {
        await mutateArticleMedia(
            articleID: articleID,
            operation: { core in
                try core.requestDownload(
                    enclosureId: enclosureID,
                    origin: .manual
                )
            },
            reconcileTransfers: true
        )
    }

    func cancelArticleDownload(
        articleID: Int64,
        enclosureID: Int64
    ) async -> Result<Void, Error> {
        await mutateArticleMedia(
            articleID: articleID,
            operation: { core in
                try core.cancelDownload(enclosureId: enclosureID)
            },
            reconcileTransfers: true
        )
    }

    func retryArticleDownload(
        articleID: Int64,
        enclosureID: Int64
    ) async -> Result<Void, Error> {
        await mutateArticleMedia(
            articleID: articleID,
            operation: { core in
                try core.retryDownload(enclosureId: enclosureID)
            },
            reconcileTransfers: true
        )
    }

    func deleteArticleDownload(
        articleID: Int64,
        enclosureID: Int64
    ) async -> Result<Void, Error> {
        await mutateArticleMedia(
            articleID: articleID,
            operation: { core in
                try core.requestDownloadDeletion(enclosureId: enclosureID)
            },
            reconcileTransfers: true
        )
    }

    private func loadArticleAudioActionStates(
        for articleIDs: [Int64]
    ) {
        articleAudioActionGeneration &+= 1
        let generation = articleAudioActionGeneration
        let ids = Array(Set(articleIDs))
        guard !ids.isEmpty else {
            articleAudioActionStates = [:]
            return
        }
        guard let core else {
            articleAudioActionStates = [:]
            return
        }

        let sessionCoordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, sessionCoordinator] in
            guard let result = await sessionCoordinator.responsiveResult(
                for: core,
                { try core.articleAudioActionStates(articleIds: ids) }
            ) else { return }
            guard let self,
                  self.articleAudioActionGeneration == generation else {
                return
            }

            switch result {
            case let .success(values):
                self.articleAudioActionStates = Dictionary(
                    uniqueKeysWithValues: values.map { value in
                        (
                            value.articleId,
                            IOSArticleAudioActionState(
                                articleID: value.articleId,
                                enclosures: value.enclosures,
                                isInListeningList: value.isInListeningList,
                                downloads: Dictionary(
                                    uniqueKeysWithValues: value.downloads.map {
                                        ($0.enclosureId, $0)
                                    }
                                )
                            )
                        )
                    }
                )
            case .failure:
                self.articleAudioActionStates = [:]
            }
        }
    }

    private func requestMediaArtworkProbe(articleID: Int64) {
        guard let core else { return }
        let sessionCoordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, sessionCoordinator] in
            guard let result = await sessionCoordinator.blockingResult(
                for: core,
                {
                    var changed = false
                    for enclosure in try core.articleEnclosures(articleId: articleID)
                    where enclosure.mediaKind == .audio {
                        if (try? core.probeMediaArtwork(enclosureId: enclosure.id)) == true {
                            changed = true
                        }
                    }
                    return changed
                }
            ) else { return }

            guard let self, self.core === core else { return }
            if case .success(true) = result {
                self.loadArticleAudioActionStates(for: [articleID])
                self.onMediaArtworkProbeChanged?()
            }
        }
    }

    private func mutateArticleMedia(
        articleID: Int64,
        operation: @escaping @Sendable (Flux) throws -> Void,
        reconcileTransfers: Bool
    ) async -> Result<Void, Error> {
        guard let core else {
            return .failure(IOSCoreError.notConfigured)
        }
        let sessionCoordinator = coreSessionExecutionCoordinator
        guard let result = await sessionCoordinator.responsiveResult(
            for: core,
            { try operation(core) }
        ) else {
            return .failure(IOSCoreError.notConfigured)
        }

        if case .success = result {
            loadArticleAudioActionStates(for: results.map(\.id))
            if reconcileTransfers {
                await onMediaTransferReconciliationRequested?()
            }
        }
        return result
    }

    private func mutate(
        articleID: Int64,
        read: Bool? = nil,
        starred: Bool? = nil,
        feedback: MutationFeedback? = nil
    ) {
        guard let core else { return }
        let sessionCoordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, sessionCoordinator] in
            guard let result = await sessionCoordinator.blockingResult(
                for: core,
                {
                    if let read {
                        return try core.searchSetReadState(articleId: articleID, read: read)
                    }
                    return try core.searchSetStarredState(
                        articleId: articleID,
                        starred: starred ?? false
                    )
                }
            ) else { return }
            guard let self else { return }
            switch result {
            case let .success(disposition):
                guard let article = self.results.first(where: { $0.id == articleID }) else { return }
                let current = self.timelinePresentationBridge.articleState(for: articleID, fallback: article)
                let readChanged = read.map { $0 != current.isRead } ?? false
                let starChanged = starred.map { $0 != current.isStarred } ?? false
                self.timelinePresentationBridge.publishArticle(.init(
                    articleID: articleID,
                    state: .init(isRead: read ?? current.isRead, isStarred: starred ?? current.isStarred, revision: current.revision &+ 1),
                    rearmScrollover: false
                ))
                switch feedback {
                case .read where readChanged:
                    self.readCompletionFeedbackRevision &+= 1
                case .starred where starChanged:
                    self.starCompletionFeedbackRevision &+= 1
                case .read, .starred, nil:
                    break
                }
                if disposition == .localFirst { self.onLocalFirstMutation() }
            case let .failure(error): self.errorMessage = IOSErrorPresentation.message(for: error, context: .articleAction)
            }
        }
    }

    // Narrow deterministic seams for temporal/pagination presentation tests.
    func replaceResultsForTesting(_ value: [ArticleSummary], referenceDate: Date) {
        searchReferenceDate = referenceDate
        replaceResults(value)
    }

    func appendResultsForTesting(_ value: [ArticleSummary]) {
        replaceResults(IOSSearchPaginationPolicy.deduplicated(results + value))
    }

    var searchReferenceDateForTesting: Date { searchReferenceDate }

    private func replaceResults(_ value: [ArticleSummary]) {
        results = value
        let states = Dictionary(uniqueKeysWithValues: value.map { article in
            let existing = timelinePresentationBridge.articleState(for: article.id, fallback: article)
            return (article.id, existing.revision == 0 ? IOSUIKitArticlePresentationState(isRead: article.isRead, isStarred: article.isStarred, revision: 0) : existing)
        })
        timelinePresentationBridge.replaceArticleStates(states)
        timelineStructuralState = .init(
            items: value.map { .init(article: $0, content: ArticleRowContent(article: $0, referenceDate: searchReferenceDate)) },
            revision: timelineStructuralState.revision &+ 1
        )
        loadArticleAudioActionStates(for: value.map(\.id))
    }

}
