import Foundation
import Observation
import UIKit
#if DEBUG || FLUX_PERFORMANCE_DIAGNOSTICS
import OSLog
#endif

enum IOSArticleActionHapticPolicy {
    static func shouldConfirmStar(previous: Bool?, requested: Bool) -> Bool {
        guard let previous else { return false }
        return previous != requested
    }

    static func shouldConfirmSaveToService(_ result: SaveToServiceResult) -> Bool {
        switch result {
        case .saved: true
        case .noIntegrationConfigured: false
        }
    }
}

private struct TimelinePagePreparation {
    let page: ArticlePage
    let contents: [ArticleRowContent]
    let referenceDate: Date
}

private struct IOSPendingScrolloverUndoPresentation {
    let ids: [Int64]
    let generation: UInt64
    let completedAt: TimeInterval
}

@MainActor
@Observable final class NewsreaderStore {
#if DEBUG || FLUX_PERFORMANCE_DIAGNOSTICS
    private static let scrolloverDiagnosticLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.kevincfechtel.fluxNews", category: "scrollover-diagnostic")
#endif
    private enum Key {
        static let startupScope = "FluxNews.iOS.startupScope"
        static let startupCategoryID = "FluxNews.iOS.startupCategoryID"
        static let startupFeedID = "FluxNews.iOS.startupFeedID"
        static let hideEmpty = "FluxNews.iOS.hideEmptyNavigationEntries"
        static let removeWhenRead = "FluxNews.iOS.removeArticlesWhenMarkedRead"
        static let scrollover = "FluxNews.iOS.markReadOnScrollover"
        static let presentationMode = "FluxNews.iOS.articlePresentationMode"
        static let previewLines = "FluxNews.iOS.articlePreviewLines"
        static let showArticleCount = "FluxNews.iOS.showArticleCount"
        static let showRelativePublicationTime = "FluxNews.iOS.showRelativePublicationTime"
        static let clickOnNews = "FluxNews.clickOnNews"
        static let leadingSwipeFull = "FluxNews.iOS.leadingSwipeFull"
        static let leadingSwipeAdditional = "FluxNews.iOS.leadingSwipeAdditional"
        static let trailingSwipeFull = "FluxNews.iOS.trailingSwipeFull"
        static let trailingSwipeAdditional = "FluxNews.iOS.trailingSwipeAdditional"
    }

    var articles: [ArticleSummary] { timelineStructuralStorage.items.map(\.article) }
    private(set) var hasLoadedArticles = false
    private let timelineStructuralStorage = IOSUIKitArticleTimelineStructuralStorage()
    private(set) var timelineStructuralState: IOSUIKitArticleTimelineStructuralState
    let timelinePresentationBridge = IOSUIKitArticleTimelinePresentationBridge()
    @ObservationIgnored private var rowPresentationStates: [Int64: ArticleRowPresentationState] = [:]
    @ObservationIgnored private var loadedArticlesByID: [Int64: ArticleSummary] = [:]
    private var nextTimelineCursor: ArticleCursor?
    private var hasMoreTimelinePages = false
    private var nextTimelinePageRequest: IOSNewsreaderTimelinePageRequest?
    private var timelineReferenceDate = Date.now
    private static let timelinePageSize: UInt32 = 72
    private(set) var catalog = NavigationCatalog(categories: [], feeds: [])
    private(set) var unreadTotal: UInt64 = 0
    private(set) var starredTotal: UInt64 = 0
    private(set) var selectionTotal: UInt64 = 0
    private(set) var categoryCounts: [Int64: UInt64] = [:]
    private(set) var feedCounts: [Int64: UInt64] = [:]
    private(set) var articleAudioActionStates: [Int64: IOSArticleAudioActionState] = [:]
    var onMediaTransferReconciliationRequested: (() async -> Void)?
    var onMediaArtworkProbeChanged: (() -> Void)?
    @ObservationIgnored private var feedIconPresentationStates: [IOSFeedIconKey: IOSFeedIconPresentationState] = [:]
    private(set) var isLoading = false
    private(set) var manualSyncState: IOSManualSyncState = .idle
    var isSyncing: Bool { manualSyncState.isActive }
    private(set) var errorMessage: String?
    private(set) var pendingNewByFeed: [Int64: Int] = [:]
    private(set) var hasPendingNewData = false
    private(set) var hasUnscopedNewDataSignal = false

    var hasPendingNewDataForCurrentScope: Bool {
        if hasUnscopedNewDataSignal { return true }

        switch scope {
        case .all, .starred:
            return hasPendingNewData
        case let .category(id):
            let feedIDs = catalog.feeds
                .filter { $0.categoryId == id }
                .map(\.id)
            return PendingNewDataAggregation.count(
                feedIDs: feedIDs,
                pendingByFeed: pendingNewByFeed
            ) > 0
        case let .feed(id):
            return (pendingNewByFeed[id] ?? 0) > 0
        case .search, .listeningList:
            return false
        }
    }
    private(set) var snapshotRevision: UInt64 = 0
    private(set) var scrollResetRevision: UInt64 = 0
    var scope: BrowserScope = .all
    var unreadOnly = true
    var newestFirst = false
    var startupScope: StartupScopePreference
    var startupCategoryID: Int64?
    var startupFeedID: Int64?
    var hideEmptyNavigationEntries: Bool
    var removeArticlesWhenMarkedRead: Bool
    var markReadOnScrolloverEnabled: Bool
    var articlePresentationMode: ArticlePresentationMode
    var articlePreviewLines: ArticlePreviewLines
    var showArticleCount: Bool
    var showRelativePublicationTime: Bool
    var clickOnNews: ClickOnNews
    var articleSwipeConfiguration: IOSArticleSwipeConfiguration
    private(set) var scrolloverUndoIDs: [Int64] = []
    // The tracker only needs to re-arm when an existing Undo group is cleared.
    private(set) var scrolloverRearmRevision: UInt64 = 0
    var scrolloverUndoVisible: Bool { scrolloverUndoIDs.count >= 2 }

    private(set) var core: Flux?
    @ObservationIgnored private var coreSessionExecutionCoordinator = IOSCoreSessionExecutionCoordinator()
    private var eventSubscription: EventSubscription?
    private let defaults: UserDefaults
    private var pending = PendingNewData()
    private var requestedFeedIcons = Set<IOSFeedIconRequestOwnership>()
    // A request belongs to the active Core session and navigation/feed state.
    // Completion may mutate presentation only while this generation still owns it.
    private var feedIconOwnershipGeneration: UInt64 = 0
    private var articleAudioActionGeneration: UInt64 = 0
    // Causes existing timeline controllers to request icons again after a
    // successful navigation refresh invalidates negative results.
    private(set) var feedIconRequestRevision: UInt64 = 0
    /// Semantic UI feedback events. The view decides how the system represents
    /// them; persistence code only publishes successful user-visible outcomes.
    private(set) var readCompletionFeedbackRevision: UInt64 = 0
    private(set) var starCompletionFeedbackRevision: UInt64 = 0
    private(set) var undoCompletionFeedbackRevision: UInt64 = 0
    private var feedIconLoader: (@Sendable (Int64, FeedIconVariant) throws -> Data?)?
    private static let feedIconRetryCooldown: TimeInterval = 30
    private var scrolloverUndoTask: Task<Void, Never>?
    private var scrolloverUndoOpenedAt: TimeInterval?
    private var scrolloverUndoLastSuccessAt: TimeInterval?
    private var recentSuccessfulScrolloverReads: [(id: Int64, time: TimeInterval)] = []
    private var scrolloverCountsPending = false
    private var pendingScrolloverIDs: [Int64] = []
    private var pendingScrolloverIDSet = Set<Int64>()
    // These revisions protect only rows whose deferred read presentation was
    // actually published before a failed Core mutation.
    @ObservationIgnored private var publishedScrolloverPresentationRevisions: [Int64: UInt64] = [:]
    private var pendingScrolloverReadPresentationIDs = Set<Int64>()
    // A forward-qualified group is published once when its motion reverses or idles.
    private var hasForwardPendingScrolloverPresentation = false
    private typealias ReadMutationWriter = @MainActor ([Int64], Bool) async -> Result<Void, Error>

    private var scrolloverMutationRunning = false
    private var runningScrolloverIDs = Set<Int64>()
    private var supersededRunningScrolloverIDs = Set<Int64>()
    private var scrolloverMutationTask: Task<Void, Never>?
    private var scrolloverMutationDeadlineTask: Task<Void, Never>?
    @ObservationIgnored private var readMutationWriterOverride: ReadMutationWriter?
    @ObservationIgnored private var scrolloverMutationMaximumWaitOverride: Duration?
    private var explicitReadMutationTokens: [Int64: UInt64] = [:]
    private var nextExplicitReadMutationToken: UInt64 = 0
#if DEBUG
    @ObservationIgnored private var explicitReadMutationWaiters: [CheckedContinuation<Void, Never>] = []
#endif
    // Presentation resets rebaseline UI feedback only. Accepted persistence work
    // remains owned by this Core session until a real detach invalidates it.
    private var scrolloverPresentationGeneration: UInt64 = 0
    private var scrolloverSessionGeneration: UInt64 = 0
    private var scrolloverPresentationPhase: IOSScrolloverPresentationPhase = .idle
    // Successful mutations are still coalesced for the existing Undo behavior.
    private var pendingSuccessfulScrolloverUndoPresentation: [IOSPendingScrolloverUndoPresentation] = []
    private var hasMeaningfullyInteracted = false
    private var readerRequests = ReaderRequestState()
    private var readLifecycle = IOSNewsreaderReadLifecycle()
    private var manualSyncLifecycle = IOSManualSyncLifecycle()
    @ObservationIgnored private var manualSyncRequest: IOSManualSyncRequest?
    @ObservationIgnored private var manualSyncCancellation: SyncCancellation?
    @ObservationIgnored private var manualSyncTask: Task<Void, Never>?
    @ObservationIgnored private var manualSyncPresentationCancellationRequest: IOSManualSyncRequest?
    @ObservationIgnored private var manualSyncExecutions: [IOSManualSyncRequest: (cancellation: SyncCancellation, task: Task<Void, Never>)] = [:]
    @ObservationIgnored private var manualSyncQuiescenceRequested = false

    init(
        defaults: UserDefaults = .standard,
        coreSessionExecutionCoordinator: IOSCoreSessionExecutionCoordinator? = nil
    ) {
        timelineStructuralState = .init(storage: timelineStructuralStorage, change: .replace, revision: 0)
        self.defaults = defaults
        if let coreSessionExecutionCoordinator {
            self.coreSessionExecutionCoordinator = coreSessionExecutionCoordinator
        }
        startupScope = defaults.string(forKey: Key.startupScope).flatMap(StartupScopePreference.init(rawValue:)) ?? .allNews
        startupCategoryID = defaults.object(forKey: Key.startupCategoryID) as? Int64
        startupFeedID = defaults.object(forKey: Key.startupFeedID) as? Int64
        hideEmptyNavigationEntries = defaults.object(forKey: Key.hideEmpty) as? Bool ?? false
        removeArticlesWhenMarkedRead = defaults.object(forKey: Key.removeWhenRead) as? Bool ?? false
        markReadOnScrolloverEnabled = defaults.object(forKey: Key.scrollover) as? Bool ?? true
        articlePresentationMode = defaults.string(forKey: Key.presentationMode).flatMap(ArticlePresentationMode.init(rawValue:)) ?? .visual
        articlePreviewLines = ArticlePreviewLines(rawValue: defaults.object(forKey: Key.previewLines) as? Int ?? 3) ?? .standard
        showArticleCount = defaults.object(forKey: Key.showArticleCount) as? Bool ?? true
        showRelativePublicationTime = defaults.object(forKey: Key.showRelativePublicationTime) as? Bool ?? false
        clickOnNews = defaults.string(forKey: Key.clickOnNews).flatMap(ClickOnNews.init(rawValue:)) ?? .openLink
        articleSwipeConfiguration = Self.loadArticleSwipeConfiguration(defaults: defaults)
    }

    func attach(
        to configuredCore: Flux,
        coreSessionExecutionCoordinator: IOSCoreSessionExecutionCoordinator? = nil
    ) {
        detach()
        if let coreSessionExecutionCoordinator {
            self.coreSessionExecutionCoordinator = coreSessionExecutionCoordinator
        }
        self.coreSessionExecutionCoordinator.ensureActive(configuredCore)
        core = configuredCore
        manualSyncQuiescenceRequested = false
        do {
            eventSubscription = try configuredCore.subscribeEvents(
                listener: IOSNewsreaderEventListener(store: self, session: readLifecycle.session)
            )
        } catch {
            errorMessage = IOSErrorPresentation.message(for: error, context: .contentLoad)
        }
        let session = readLifecycle.session
        loadNavigationAndCounts { [weak self] in
            guard let self, self.readLifecycle.session == session else { return }
            let categoryIDs = Set(self.catalog.categories.map(\.id))
            let feedIDs = Set(self.catalog.feeds.map(\.id))
            self.scope = StartupScopeResolver.resolve(self.startupScope, categoryID: self.startupCategoryID, feedID: self.startupFeedID, categoryIDs: categoryIDs, feedIDs: feedIDs)
            self.normalizeStartupScope(categoryIDs: categoryIDs, feedIDs: feedIDs)
            self.loadVisibleArticles()
        }
    }

    func detach() {
        flushScrolloverPersistenceForLifecycle()
        invalidateScrolloverSession()
        invalidateManualSyncSession()
        readLifecycle.invalidateSession()
        if let eventSubscription { try? eventSubscription.unsubscribe() }
        eventSubscription = nil
        core = nil
        replaceArticles([])
        catalog = NavigationCatalog(categories: [], feeds: [])
        unreadTotal = 0
        starredTotal = 0
        selectionTotal = 0
        categoryCounts = [:]
        feedCounts = [:]
        articleAudioActionGeneration &+= 1
        articleAudioActionStates = [:]
        invalidateFeedIconSession()
        isLoading = false
        resetPresentationState()
    }

    func query(scope requestedScope: BrowserScope? = nil) -> ArticleQuery {
        let selected = requestedScope ?? scope
        let coreScope: ArticleScope = switch selected {
        case .all, .starred: .all
        case let .category(id): .category(id: id)
        case let .feed(id): .feed(id: id)
        case .search, .listeningList: .all
        }
        return ArticleQuery(scope: coreScope, readFilter: selected == .starred ? .all : (unreadOnly ? .unread : .all), starredFilter: selected == .starred ? .starred : .all, sort: newestFirst ? .newestFirst : .oldestFirst, limit: Self.timelinePageSize, cursor: nil)
    }

    func loadNavigationAndCounts(afterCompletion: (() -> Void)? = nil) {
        guard let core else { return }
        let request = readLifecycle.beginNavigation()
        let countMode: NavigationCountMode = unreadOnly ? .unread : .all
        let sessionCoordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, sessionCoordinator] in
            guard let result = await sessionCoordinator.responsiveResult(
                for: core,
                { try core.navigationProjection(countMode: countMode) }
            ) else { return }
            guard let self, self.readLifecycle.isCurrentNavigation(request) else { return }
            switch result {
            case let .success(value):
                publishNavigationProjection(value)
                if readLifecycle.ownsError(request) { errorMessage = nil }
            case let .failure(error):
                if readLifecycle.ownsError(request) { errorMessage = IOSErrorPresentation.message(for: error, context: .contentLoad) }
            }
            afterCompletion?()
        }
    }

    func loadVisibleArticles(acknowledgePending: Bool = false, resetSnapshot: Bool = false, completion: (() -> Void)? = nil) {
        guard let core else { return }
        let request = readLifecycle.beginArticle()
        let articleQuery = query()
        let referenceDate = Date.now
        nextTimelinePageRequest = nil
        nextTimelineCursor = nil
        hasMoreTimelinePages = false
        isLoading = true
        errorMessage = nil
        let sessionCoordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, sessionCoordinator] in
            guard let result = await sessionCoordinator.responsiveResult(
                for: core,
                {
                    let page = try core.articlePage(query: articleQuery, includeTotal: true)
                    return TimelinePagePreparation(
                        page: page,
                        contents: page.articles.map { ArticleRowContent(article: $0, referenceDate: referenceDate) },
                        referenceDate: referenceDate
                    )
                }
            ) else { return }
            guard let self, self.readLifecycle.isCurrentArticle(request), self.readLifecycle.isCurrentSelectionCount(request) else { return }
            switch result {
            case let .success(value):
                replaceFirstTimelinePage(value)
                selectionTotal = value.page.total ?? selectionTotal
                if acknowledgePending { acknowledgePendingForCurrentScope() }
                if resetSnapshot { snapshotRevision &+= 1 }
                if readLifecycle.ownsError(request) { errorMessage = nil }
            case let .failure(error):
                if readLifecycle.ownsError(request) { errorMessage = IOSErrorPresentation.message(for: error, context: .contentLoad) }
            }
            isLoading = false
            if case .success = result { completion?() }
        }
    }

    func refreshArticleAudioActionState(articleID: Int64) {
        loadArticleAudioActionStates(for: [articleID], replacing: false)
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
        for articleIDs: [Int64],
        replacing: Bool
    ) {
        guard let core else { return }
        let ids = Array(Set(articleIDs))
        guard !ids.isEmpty else {
            if replacing {
                articleAudioActionGeneration &+= 1
                articleAudioActionStates = [:]
            }
            return
        }

        if replacing {
            articleAudioActionGeneration &+= 1
            articleAudioActionStates = [:]
        }
        let generation = articleAudioActionGeneration
        let coordinator = coreSessionExecutionCoordinator

        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.responsiveResult(
                for: core,
                { try core.articleAudioActionStates(articleIds: ids) }
            ) else { return }
            guard let self,
                  self.articleAudioActionGeneration == generation else {
                return
            }

            switch result {
            case let .success(values):
                let projected = Dictionary(
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
                if replacing {
                    self.articleAudioActionStates = projected
                } else {
                    for (id, state) in projected {
                        self.articleAudioActionStates[id] = state
                    }
                }
            case .failure:
                if replacing {
                    self.articleAudioActionStates = [:]
                }
            }
        }
    }

    private func requestMediaArtworkProbe(articleID: Int64) {
        guard let core else { return }
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.blockingResult(
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
                self.refreshArticleAudioActionState(articleID: articleID)
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
            return .failure(
                NSError(
                    domain: "FluxNews",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Flux is not configured"
                    ]
                )
            )
        }
        let coordinator = coreSessionExecutionCoordinator
        guard let result = await coordinator.responsiveResult(
            for: core,
            { try operation(core) }
        ) else {
            return .failure(
                NSError(
                    domain: "FluxNews",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Core session is unavailable"
                    ]
                )
            )
        }

        if case .success = result {
            refreshArticleAudioActionState(articleID: articleID)
            if reconcileTransfers {
                await onMediaTransferReconciliationRequested?()
            }
        }
        return result
    }

    func feedIconPresentationState(for feedID: Int64, variant: FeedIconVariant) -> IOSFeedIconPresentationState {
        let key = IOSFeedIconKey(feedID: feedID, variant: variant)
        if let state = feedIconPresentationStates[key] { return state }
        let state = IOSFeedIconPresentationState()
        feedIconPresentationStates[key] = state
        return state
    }

    func requestFeedIcon(_ feedID: Int64, variant: FeedIconVariant, displayScale: CGFloat = 1, now: TimeInterval = Date.timeIntervalSinceReferenceDate) {
        let key = IOSFeedIconKey(feedID: feedID, variant: variant)
        let state = feedIconPresentationState(for: feedID, variant: variant)
        guard state.canRequest(at: now) else { return }
        let loader: @Sendable (Int64, FeedIconVariant) throws -> Data?
        let productionCore: Flux?
        if let feedIconLoader {
            loader = feedIconLoader
            productionCore = nil
        } else if let core {
            loader = { feedID, variant in try core.feedIcon(feedId: feedID, variant: variant)?.pngData }
            productionCore = core
        } else {
            return
        }
        let ownership = IOSFeedIconRequestOwnership(key: key, generation: feedIconOwnershipGeneration)
        guard requestedFeedIcons.insert(ownership).inserted else { return }
        state.beginLoading()
        let sessionCoordinator = coreSessionExecutionCoordinator
        Task { [weak self, productionCore, sessionCoordinator] in
            // The synchronous Core fetch remains on the bounded blocking lane.
            // ImageIO raster work is CPU-only and deliberately leaves that lane;
            // it must not run on the MainActor that owns presentation state.
            let loaded: Result<Data?, Error>
            if let productionCore {
                guard let admitted = await sessionCoordinator.blockingResult(
                    for: productionCore,
                    { try loader(feedID, variant) }
                ) else {
                    guard let self,
                          ownership.generation == feedIconOwnershipGeneration else { return }
                    requestedFeedIcons.remove(ownership)
                    feedIconPresentationStates[key]?.invalidateLoading()
                    return
                }
                loaded = admitted
            } else {
                loaded = await AppleCoreExecution.shared.blockingResult {
                    try loader(feedID, variant)
                }
            }
            let result: Result<IOSPreparedFeedIcon?, Error> = switch loaded {
            case let .success(data?):
                await Task.detached(priority: .userInitiated) {
                    Result { try IOSFeedIconImagePreparation.prepare(data: data, displayScale: displayScale) }
                }.value
            case .success(nil):
                .success(nil)
            case let .failure(error):
                .failure(error)
            }
            guard let self else { return }
            guard ownership.generation == feedIconOwnershipGeneration else { return }
            requestedFeedIcons.remove(ownership)
            guard let state = feedIconPresentationStates[key] else { return }
            switch result {
            case let .success(prepared?):
                state.setAvailable(prepared.image)
                timelinePresentationBridge.publishFeedIcon(.init(key: key, image: prepared.image, revision: state.revision))
            case .success(nil):
                state.setUnavailable()
            case .failure:
                state.setRetryableFailure(retryAfter: now + Self.feedIconRetryCooldown)
            }
        }
    }

#if DEBUG
    func setFeedIconLoaderForTesting(_ loader: @escaping @Sendable (Int64, FeedIconVariant) throws -> Data?) {
        feedIconLoader = loader
    }

    func invalidateFeedIconAvailabilityForTesting() {
        invalidateFeedIconAvailabilityAfterNavigationRefresh()
    }
#endif

    func syncManually() async {
        guard !manualSyncQuiescenceRequested,
              let core,
              let request = manualSyncLifecycle.begin() else { return }
        let cancellation = SyncCancellation()
        guard let sessionLease = coreSessionExecutionCoordinator.beginExecution(
            for: core,
            cancellation: { cancellation.cancel() }
        ) else { return }

        manualSyncRequest = request
        manualSyncCancellation = cancellation
        manualSyncPresentationCancellationRequest = nil
        manualSyncState = .running
        errorMessage = nil

        let sessionCoordinator = coreSessionExecutionCoordinator
        let task = Task { [weak self, core, cancellation, sessionLease, sessionCoordinator] in
            let result = await AppleCoreExecution.shared.blockingCancellableResult(
                onCancel: { cancellation.cancel() }
            ) {
                try core.syncCancellable(reason: .manual, cancellation: cancellation)
            }
            sessionCoordinator.finish(sessionLease)
            guard let self else { return }
            completeManualSync(request, cancellation: cancellation, result: result)
        }
        manualSyncTask = task
        manualSyncExecutions[request] = (cancellation, task)
        await task.value
    }

    func syncFromWidget() {
        guard let core else { return }
        let cancellation = SyncCancellation()
        let sessionCoordinator = coreSessionExecutionCoordinator
        Task { [core, cancellation, sessionCoordinator] in
            _ = await sessionCoordinator.blockingCancellableResult(
                for: core,
                onCancel: { cancellation.cancel() },
                {
                    try core.syncCancellable(
                        reason: .widget,
                        cancellation: cancellation
                    )
                }
            )
        }
    }

    func article(
        withID articleID: Int64,
        completion: @escaping (ArticleSummary?) -> Void
    ) {
        guard let core else {
            completion(nil)
            return
        }
        let sessionCoordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, sessionCoordinator] in
            guard let result = await sessionCoordinator.responsiveResult(
                for: core,
                {
                    let query = ArticleQuery(
                        scope: .all,
                        readFilter: .all,
                        starredFilter: .all,
                        sort: .newestFirst,
                        limit: 0,
                        cursor: nil
                    )
                    return try core.queryArticles(query: query)
                        .first(where: { $0.id == articleID })
                }
            ) else {
                return
            }
            guard self?.core === core else { return }
            switch result {
            case let .success(article):
                completion(article)
            case .failure:
                completion(nil)
            }
        }
    }

    func openWidgetScope(_ selection: WidgetContentSelection) {
        switch selection.scope {
        case .allNews:
            unreadOnly = true
            select(.all)
        case .bookmarks:
            select(.starred)
        case .category:
            guard let id = selection.categoryID,
                  catalog.categories.contains(where: { $0.id == id }) else {
                return
            }
            unreadOnly = true
            select(.category(id))
        case .feed:
            guard let id = selection.feedID,
                  catalog.feeds.contains(where: { $0.id == id }) else {
                return
            }
            unreadOnly = true
            select(.feed(id))
        }
    }

    func cancelManualSync() {
        guard let request = manualSyncRequest,
              manualSyncLifecycle.requestCancellation(request) else { return }
        manualSyncState = .cancelling
        manualSyncCancellation?.cancel()
        manualSyncTask?.cancel()

        // Presentation ownership ends immediately. The cancelled Core call may
        // still be winding down on its worker, but its request generation is now
        // stale and a fresh manual run may start without accepting old results.
        _ = manualSyncLifecycle.supersedeCancelled(request)
        manualSyncPresentationCancellationRequest = request
        manualSyncRequest = nil
        manualSyncCancellation = nil
        manualSyncTask = nil
    }

    /// Account/Core replacement is stronger than presentation cancellation:
    /// prevent a new manual run, cancel every still-winding execution, and wait
    /// until each synchronous Rust call has actually returned from its worker.
    func quiesceManualSyncForCoreReplacement() async {
        manualSyncQuiescenceRequested = true
        cancelManualSync()

        for execution in manualSyncExecutions.values {
            execution.cancellation.cancel()
            execution.task.cancel()
        }

        while !manualSyncExecutions.isEmpty {
            let tasks = manualSyncExecutions.values.map { $0.task }
            for task in tasks {
                await task.value
            }
        }
    }

    /// Used only when account/Core replacement failed and the existing Core
    /// remains authoritative. Successful replacement releases the gate in attach.
    func resumeManualSyncAfterAbortedCoreReplacement() {
        manualSyncQuiescenceRequested = false
    }

    func select(_ newScope: BrowserScope) {
        markMeaningfulInteraction()
        scope = newScope
        if newScope == .listeningList {
            readLifecycle.invalidateArticle()
            replaceArticles([])
            selectionTotal = 0
            resetPresentationState()
        } else {
            loadVisibleArticles(
                acknowledgePending: true,
                resetSnapshot: true
            )
        }
        requestScrollReset()
    }

    func setUnreadOnly(_ value: Bool) {
        guard unreadOnly != value else { return }
        unreadOnly = value
        readLifecycle.invalidateNavigation()
        resetPresentationState()
        loadVisibleArticles(resetSnapshot: true)
        requestScrollReset()
    }
    func setNewestFirst(_ value: Bool) {
        guard newestFirst != value else { return }
        newestFirst = value
        resetPresentationState()
        loadVisibleArticles(resetSnapshot: true)
        requestScrollReset()
    }
    func setStartupScope(_ value: StartupScopePreference) { startupScope = value; defaults.set(value.rawValue, forKey: Key.startupScope) }
    func setStartupCategoryID(_ value: Int64?) { startupCategoryID = value; defaults.set(value, forKey: Key.startupCategoryID) }
    func setStartupFeedID(_ value: Int64?) { startupFeedID = value; defaults.set(value, forKey: Key.startupFeedID) }
    func setHideEmptyNavigationEntries(_ value: Bool) { hideEmptyNavigationEntries = value; defaults.set(value, forKey: Key.hideEmpty) }
    func setRemoveArticlesWhenMarkedRead(_ value: Bool) { removeArticlesWhenMarkedRead = value; defaults.set(value, forKey: Key.removeWhenRead) }
    func setMarkReadOnScrolloverEnabled(_ value: Bool) { markReadOnScrolloverEnabled = value; defaults.set(value, forKey: Key.scrollover) }

    /// Applies a just-completed legacy import to this already initialized store.
    func reloadGlobalPreferenceSettings() {
        removeArticlesWhenMarkedRead = defaults.object(forKey: Key.removeWhenRead) as? Bool ?? false
        markReadOnScrolloverEnabled = defaults.object(forKey: Key.scrollover) as? Bool ?? true
    }
    /// Applies local D9-A imports to an already initialized presentation store.
    func reloadLegacyMigrationSettings() {
        reloadGlobalPreferenceSettings()
        startupScope = defaults.string(forKey: Key.startupScope).flatMap(StartupScopePreference.init(rawValue:)) ?? .allNews
        startupCategoryID = defaults.object(forKey: Key.startupCategoryID) as? Int64
        startupFeedID = defaults.object(forKey: Key.startupFeedID) as? Int64
        hideEmptyNavigationEntries = defaults.object(forKey: Key.hideEmpty) as? Bool ?? false
        showArticleCount = defaults.object(forKey: Key.showArticleCount) as? Bool ?? true
        clickOnNews = defaults.string(forKey: Key.clickOnNews).flatMap(ClickOnNews.init(rawValue:)) ?? .openLink
        articleSwipeConfiguration = Self.loadArticleSwipeConfiguration(defaults: defaults)
        let categoryIDs = Set(catalog.categories.map(\.id))
        let feedIDs = Set(catalog.feeds.map(\.id))
        let resolved = StartupScopeResolver.resolve(startupScope, categoryID: startupCategoryID, feedID: startupFeedID, categoryIDs: categoryIDs, feedIDs: feedIDs)
        if scope != resolved {
            scope = resolved
            loadVisibleArticles(resetSnapshot: true)
        }
    }
    func setArticlePresentationMode(_ value: ArticlePresentationMode) { articlePresentationMode = value; defaults.set(value.rawValue, forKey: Key.presentationMode); resetPresentationState() }
    func setArticlePreviewLines(_ value: ArticlePreviewLines) { articlePreviewLines = value; defaults.set(value.rawValue, forKey: Key.previewLines); resetPresentationState() }
    func setShowArticleCount(_ value: Bool) { showArticleCount = value; defaults.set(value, forKey: Key.showArticleCount) }
    func setShowRelativePublicationTime(_ value: Bool) {
        guard showRelativePublicationTime != value else { return }
        showRelativePublicationTime = value
        defaults.set(value, forKey: Key.showRelativePublicationTime)
    }
    func setClickOnNews(_ value: ClickOnNews) { clickOnNews = value; defaults.set(value.rawValue, forKey: Key.clickOnNews) }

    func setArticleSwipeAction(
        _ action: IOSArticleSwipeAction?,
        side: IOSArticleSwipeSide,
        slot: IOSArticleSwipeSlot
    ) {
        articleSwipeConfiguration = articleSwipeConfiguration.setting(
            action,
            side: side,
            slot: slot
        )
        persistArticleSwipeConfiguration()
    }

    private static func loadArticleSwipeConfiguration(
        defaults: UserDefaults
    ) -> IOSArticleSwipeConfiguration {
        let leadingFull = defaults.string(forKey: Key.leadingSwipeFull)
            .flatMap(IOSArticleSwipeAction.init(rawValue:))
        let leadingAdditional = defaults.string(forKey: Key.leadingSwipeAdditional)
            .flatMap(IOSArticleSwipeAction.init(rawValue:))
        let trailingFull = defaults.string(forKey: Key.trailingSwipeFull)
            .flatMap(IOSArticleSwipeAction.init(rawValue:))
        let trailingAdditional = defaults.string(forKey: Key.trailingSwipeAdditional)
            .flatMap(IOSArticleSwipeAction.init(rawValue:))

        let hasStoredConfiguration = [
            Key.leadingSwipeFull,
            Key.leadingSwipeAdditional,
            Key.trailingSwipeFull,
            Key.trailingSwipeAdditional,
        ].contains { defaults.object(forKey: $0) != nil }

        guard hasStoredConfiguration else {
            return .defaultConfiguration
        }

        func side(
            full: IOSArticleSwipeAction?,
            additional: IOSArticleSwipeAction?
        ) -> [IOSArticleSwipeAction] {
            guard let full else { return [] }
            if let additional, additional != full {
                return [additional, full]
            }
            return [full]
        }

        return .init(
            leading: side(full: leadingFull, additional: leadingAdditional),
            trailing: side(full: trailingFull, additional: trailingAdditional)
        )
    }

    private func persistArticleSwipeConfiguration() {
        func persist(
            _ side: IOSArticleSwipeSide,
            fullKey: String,
            additionalKey: String
        ) {
            if let full = articleSwipeConfiguration.fullSwipeAction(for: side) {
                defaults.set(full.rawValue, forKey: fullKey)
            } else {
                defaults.set("", forKey: fullKey)
            }

            if let additional = articleSwipeConfiguration.additionalAction(for: side) {
                defaults.set(additional.rawValue, forKey: additionalKey)
            } else {
                defaults.set("", forKey: additionalKey)
            }
        }

        persist(
            .leading,
            fullKey: Key.leadingSwipeFull,
            additionalKey: Key.leadingSwipeAdditional
        )
        persist(
            .trailing,
            fullKey: Key.trailingSwipeFull,
            additionalKey: Key.trailingSwipeAdditional
        )
    }

    func setRead(_ article: ArticleSummary, read: Bool, providesFeedback: Bool = true) {
        setRead(articleIDs: [article.id], read: read, providesFeedback: providesFeedback)
    }
    func setStarred(_ article: ArticleSummary, starred: Bool) { setStarred(articleIDs: [article.id], starred: starred) }

    func markCurrentScopeAsRead(completion: @escaping (Bool) -> Void = { _ in }) {
        guard case .all = scope else {
            guard case .category = scope else {
                guard case .feed = scope else { return }
                markCurrentScopeArticlesRead(completion: completion)
                return
            }
            markCurrentScopeArticlesRead(completion: completion)
            return
        }
        markCurrentScopeArticlesRead(completion: completion)
    }

    // Read-on-open stays on the existing Core mutation path; only the original URL is returned.
    func open(_ article: ArticleSummary, completion: @escaping (String) -> Void) {
        // Opening already has its own strong visual transition. Avoid stacking a
        // second tactile confirmation merely because read-on-open shares the
        // same Core mutation.
        setRead(article, read: true, providesFeedback: false)
        completion(article.url)
    }

    func openReader(_ article: ArticleSummary, completion: @escaping (Result<ReaderDocument, Error>) -> Void) {
        setRead(article, read: true)
        loadReaderDocument(articleID: article.id, completion: completion)
    }

    func loadReaderDocument(articleID: Int64, completion: @escaping (Result<ReaderDocument, Error>) -> Void) {
        let request = readerRequests.begin()
        guard let core else {
            completion(.failure(IOSCoreError.notConfigured))
            return
        }
        let sessionCoordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, sessionCoordinator] in
            guard let result = await sessionCoordinator.responsiveResult(
                for: core,
                { try core.readerDocument(articleId: articleID) }
            ) else { return }
            guard let self, self.readerRequests.isCurrent(request) else { return }
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

    func discoverSubscriptions(_ request: DiscoverSubscriptionsRequest, completion: @escaping (Result<[DiscoveredSubscription], Error>) -> Void) {
        guard let core else { completion(.failure(unconfiguredError)); return }
        let sessionCoordinator = coreSessionExecutionCoordinator
        Task { [core, sessionCoordinator] in
            guard let result = await sessionCoordinator.blockingResult(
                for: core,
                { try core.discoverSubscriptions(request: request) }
            ) else { return }
            completion(result)
        }
    }

    func createFeed(_ request: CreateFeedRequest, completion: @escaping (Result<CreateFeedResult, Error>) -> Void) {
        guard let core else { completion(.failure(unconfiguredError)); return }
        let sessionCoordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, sessionCoordinator] in
            guard let result = await sessionCoordinator.blockingResult(
                for: core,
                { try core.createFeed(request: request) }
            ) else { return }
            if case .success = result { self?.loadNavigationAndCounts() }
            completion(result)
        }
    }

    func createCategory(_ title: String, completion: @escaping (Result<CreateCategoryResult, Error>) -> Void) {
        guard let core else { completion(.failure(unconfiguredError)); return }
        let sessionCoordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, sessionCoordinator] in
            guard let result = await sessionCoordinator.blockingResult(
                for: core,
                { try core.createCategory(title: title) }
            ) else { return }
            if case .success = result { self?.loadNavigationAndCounts() }
            completion(result)
        }
    }

    func loadFeedPreferences(feedID: Int64, completion: @escaping (Result<FeedPreferences, Error>) -> Void) {
        guard let core else { completion(.failure(unconfiguredError)); return }
        let sessionCoordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, sessionCoordinator] in
            guard let result = await sessionCoordinator.responsiveResult(
                for: core,
                { try core.feedPreferences(feedId: feedID) }
            ) else { return }
            guard self?.core === core else { return }
            completion(result)
        }
    }

    func setFeedDetailRendering(feedID: Int64, mode: DetailRenderingMode, completion: @escaping (Result<Void, Error>) -> Void) {
        updateFeedPreferences(feedID: feedID, change: { try $0.setFeedDetailRendering(feedId: feedID, mode: mode) }, completion: completion)
    }

    func setFeedTruncateDetail(feedID: Int64, enabled: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        updateFeedPreferences(feedID: feedID, change: { try $0.setFeedTruncateDetail(feedId: feedID, enabled: enabled) }, completion: completion)
    }

    func setFeedOpenInMiniflux(feedID: Int64, enabled: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        updateFeedPreferences(feedID: feedID, change: { try $0.setFeedOpenInMiniflux(feedId: feedID, enabled: enabled) }, completion: completion)
    }

    func setFeedAutoDownloadAudio(
        feedID: Int64,
        enabled: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        updateFeedPreferences(
            feedID: feedID,
            change: {
                try $0.setFeedAutoDownloadAudio(
                    feedId: feedID,
                    enabled: enabled
                )
            }
        ) { [weak self] result in
            if case .success = result {
                Task {
                    await self?.onMediaTransferReconciliationRequested?()
                }
            }
            completion(result)
        }
    }

    func setFeedSystemNotificationsEnabled(feedID: Int64, enabled: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        updateFeedPreferences(
            feedID: feedID,
            change: { try $0.setFeedSystemNotificationsEnabled(feedId: feedID, enabled: enabled) },
            completion: completion
        )
    }

    private func updateFeedPreferences(feedID: Int64, change: @escaping @Sendable (Flux) throws -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let core else { completion(.failure(unconfiguredError)); return }
        let sessionCoordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, sessionCoordinator] in
            guard let result = await sessionCoordinator.responsiveResult(
                for: core,
                { try change(core) }
            ) else { return }
            guard self?.core === core else { return }
            completion(result)
        }
    }

    private func makeReadMutationWriter() -> ReadMutationWriter? {
        if let readMutationWriterOverride { return readMutationWriterOverride }
        guard let core else { return nil }
        let sessionCoordinator = coreSessionExecutionCoordinator
        return { articleIDs, read in
            guard let result = await sessionCoordinator.responsiveResult(
                for: core,
                {
                    _ = try core.setReadStateBulk(articleIds: articleIDs, read: read)
                }
            ) else {
                return .failure(CancellationError())
            }
            return result
        }
    }

    private func beginExplicitReadMutation(_ articleIDs: [Int64]) -> UInt64 {
        nextExplicitReadMutationToken &+= 1
        let token = nextExplicitReadMutationToken
        for id in articleIDs { explicitReadMutationTokens[id] = token }
        return token
    }

    private func finishExplicitReadMutation(_ articleIDs: [Int64], token: UInt64) {
        for id in articleIDs where explicitReadMutationTokens[id] == token {
            explicitReadMutationTokens[id] = nil
        }
    }

    private func notifyExplicitReadMutationWaitersIfIdle() {
#if DEBUG
        guard explicitReadMutationTokens.isEmpty, !explicitReadMutationWaiters.isEmpty else { return }
        let waiters = explicitReadMutationWaiters
        explicitReadMutationWaiters = []
        for waiter in waiters { waiter.resume() }
#endif
    }

    func setRead(
        articleIDs: [Int64],
        read: Bool,
        providesFeedback: Bool = true
    ) {
        guard !articleIDs.isEmpty, let writer = makeReadMutationWriter() else { return }
        let shouldPublishReadFeedback = providesFeedback
            && read
            && articleIDs.contains { rowPresentationStates[$0]?.isRead == false }
        let conflictingScrolloverMutation = !runningScrolloverIDs.isDisjoint(with: articleIDs) ? scrolloverMutationTask : nil
        let explicitToken = beginExplicitReadMutation(articleIDs)
        let sessionGeneration = scrolloverSessionGeneration
        flushConflictingScrolloverIDs(articleIDs)
        let revisions = optimisticallySetRead(articleIDs, read: read)
        let snapshotRevision = snapshotRevision
        Task { [weak self, writer] in
            if let conflictingScrolloverMutation {
                await conflictingScrolloverMutation.value
            }
            let result = await writer(articleIDs, read)
            guard let self, sessionGeneration == self.scrolloverSessionGeneration else { return }
            self.finishExplicitReadMutation(articleIDs, token: explicitToken)
            switch result {
            case .success:
                markMeaningfulInteraction()
                if snapshotRevision == self.snapshotRevision && read && ArticleListPresentationPolicy.removesMarkedReadArticle(removeWhenMarkedRead: removeArticlesWhenMarkedRead, unreadOnly: unreadOnly, scope: scope) {
                    removeVisibleArticles(articleIDs)
                }
                if shouldPublishReadFeedback {
                    readCompletionFeedbackRevision &+= 1
                }
                reloadCounts()
            case let .failure(error):
                restoreReadPresentation(articleIDs, revisions: revisions, snapshotRevision: snapshotRevision)
                errorMessage = IOSErrorPresentation.message(for: error, context: .articleAction)
            }
            notifyExplicitReadMutationWaitersIfIdle()
        }
    }

    func setStarred(articleIDs: [Int64], starred: Bool) {
        guard let core, !articleIDs.isEmpty else { return }
        let shouldPublishStarFeedback = articleIDs.contains {
            IOSArticleActionHapticPolicy.shouldConfirmStar(
                previous: rowPresentationStates[$0]?.isStarred,
                requested: starred
            )
        }
        let revisions = optimisticallySetStarred(articleIDs, starred: starred)
        let snapshotRevision = snapshotRevision
        let sessionCoordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, sessionCoordinator] in
            guard let result = await sessionCoordinator.responsiveResult(
                for: core,
                { try core.setStarredStateBulk(articleIds: articleIDs, starred: starred) }
            ) else { return }
            guard let self else { return }
            switch result {
            case .success:
                markMeaningfulInteraction()
                if snapshotRevision == self.snapshotRevision && !starred && scope == .starred { removeVisibleArticles(articleIDs) }
                if shouldPublishStarFeedback {
                    starCompletionFeedbackRevision &+= 1
                }
                reloadCounts()
            case let .failure(error):
                restoreStarredPresentation(articleIDs, revisions: revisions, snapshotRevision: snapshotRevision)
                errorMessage = IOSErrorPresentation.message(for: error, context: .articleAction)
            }
        }
    }

    func flushScrollover(_ batch: IOSScrolloverBatch) {
        guard core != nil else { return }
        let ids = acceptScrolloverIDs(batch.articleIDs)
        guard !ids.isEmpty else { return }
        scrolloverDiagnostic("detected count=\(ids.count)")
    }

    @discardableResult
    private func acceptScrolloverIDs(_ candidateIDs: [Int64]) -> [Int64] {
        let ids = eligibleScrolloverIDs(candidateIDs)
        guard !ids.isEmpty else { return [] }
        for id in ids {
            pendingScrolloverReadPresentationIDs.insert(id)
            pendingScrolloverIDSet.insert(id)
            pendingScrolloverIDs.append(id)
        }
        hasForwardPendingScrolloverPresentation = true
        scheduleScrolloverMutationDeadlineIfNeeded()
        if pendingScrolloverIDs.count >= Self.maximumScrolloverMutationBatchSize {
            drainScrolloverMutations()
        }
        return ids
    }

    func receiveScrolloverDirection(_ direction: IOSArticleScrollDirection) {
        guard direction == .backward, hasForwardPendingScrolloverPresentation else { return }
        publishPendingScrolloverReadPresentation()
    }

    func setScrolloverPresentationPhase(_ phase: IOSScrolloverPresentationPhase) {
        scrolloverPresentationPhase = phase
        if phase == .idle {
            publishPendingScrolloverReadPresentation()
            drainScrolloverMutations()
            flushPendingSuccessfulScrolloverUndoPresentation()
            reloadScrolloverCountsIfReady()
        }
    }

    func flushScrolloverPersistenceForLifecycle() {
        drainScrolloverMutations()
    }

    private func scheduleScrolloverMutationDeadlineIfNeeded() {
        guard !pendingScrolloverIDs.isEmpty,
              !scrolloverMutationRunning,
              scrolloverMutationDeadlineTask == nil else { return }
        let sessionGeneration = scrolloverSessionGeneration
        let delay = scrolloverMutationMaximumWaitOverride ?? Self.defaultScrolloverMutationMaximumWait
        scrolloverMutationDeadlineTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled,
                  let self,
                  sessionGeneration == self.scrolloverSessionGeneration else { return }
            self.scrolloverMutationDeadlineTask = nil
            self.drainScrolloverMutations()
        }
    }

    private func cancelScrolloverMutationDeadline() {
        scrolloverMutationDeadlineTask?.cancel()
        scrolloverMutationDeadlineTask = nil
    }

    private func drainScrolloverMutations() {
        guard !scrolloverMutationRunning,
              !pendingScrolloverIDs.isEmpty,
              let writer = makeReadMutationWriter() else { return }
        cancelScrolloverMutationDeadline()
        let ids = Array(pendingScrolloverIDs.prefix(Self.maximumScrolloverMutationBatchSize))
        pendingScrolloverIDs.removeFirst(ids.count)
        scrolloverMutationRunning = true
        runningScrolloverIDs = Set(ids)
        supersededRunningScrolloverIDs.subtract(ids)
        let presentationGeneration = scrolloverPresentationGeneration
        let sessionGeneration = scrolloverSessionGeneration
        scrolloverDiagnostic("persistence flush count=\(ids.count)")
        let task = Task { [weak self, writer] in
            let result = await writer(ids, true)
            guard let self else { return }
            // A prior Core operation must never complete into, clear state for, or
            // continue work for a newly attached Core session.
            guard sessionGeneration == self.scrolloverSessionGeneration else { return }
            let ownedIDs = ids.filter { !self.supersededRunningScrolloverIDs.contains($0) }
            switch result {
            case .success:
                if !ownedIDs.isEmpty {
                    completeSuccessfulScrolloverMutation(ownedIDs, presentationGeneration: presentationGeneration)
                }
                scrolloverDiagnostic("persistence success count=\(ids.count)")
            case let .failure(error):
                if !ownedIDs.isEmpty {
                    restoreScrolloverPresentation(ownedIDs, presentationGeneration: presentationGeneration)
                    if presentationGeneration == scrolloverPresentationGeneration {
                        errorMessage = IOSErrorPresentation.message(for: error, context: .articleAction)
                    }
                }
                scrolloverDiagnosticError(ids: ids, error: error)
            }
            pendingScrolloverIDSet.subtract(ids)
            supersededRunningScrolloverIDs.subtract(ids)
            for id in ids { publishedScrolloverPresentationRevisions[id] = nil }
            scrolloverMutationRunning = false
            runningScrolloverIDs = []
            scrolloverMutationTask = nil
            reloadScrolloverCountsIfReady()
            drainScrolloverMutations()
        }
        scrolloverMutationTask = task
    }

    private func completeSuccessfulScrolloverMutation(
        _ ids: [Int64],
        presentationGeneration: UInt64,
        completedAt: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        // A new structural snapshot owns its presentation state; stale Core
        // completions remain persisted but cannot publish into that snapshot.
        guard presentationGeneration == scrolloverPresentationGeneration else { return }
        scrolloverCountsPending = true
        let result = IOSPendingScrolloverUndoPresentation(ids: ids, generation: presentationGeneration, completedAt: completedAt)
        if scrolloverPresentationPhase.isScrolling {
            pendingSuccessfulScrolloverUndoPresentation.append(result)
        } else {
            publishSuccessfulScrolloverMutation(result)
        }
    }

    private func flushPendingSuccessfulScrolloverUndoPresentation() {
        let pending = pendingSuccessfulScrolloverUndoPresentation
        pendingSuccessfulScrolloverUndoPresentation = []
        for result in pending where result.generation == scrolloverPresentationGeneration {
            publishSuccessfulScrolloverMutation(result)
        }
    }

    private func publishSuccessfulScrolloverMutation(_ result: IOSPendingScrolloverUndoPresentation) {
        recordSuccessfulScrolloverUndo(result.ids, now: result.completedAt)
    }

    private func publishPendingScrolloverReadPresentation() {
        hasForwardPendingScrolloverPresentation = false
        guard !pendingScrolloverReadPresentationIDs.isEmpty else { return }
        publishScrolloverReadPresentation(Array(pendingScrolloverReadPresentationIDs))
    }

    private func publishScrolloverReadPresentation(_ ids: [Int64]) {
        pendingScrolloverReadPresentationIDs.subtract(ids)
        for id in ids {
            guard let state = rowPresentationStates[id], !state.isRead else { continue }
            state.setRead(true)
            publishedScrolloverPresentationRevisions[id] = state.mutationRevision
            publishArticlePresentation(id)
        }
    }

    private func reloadScrolloverCountsIfReady() {
        guard scrolloverPresentationPhase == .idle,
              !scrolloverMutationRunning,
              pendingScrolloverIDs.isEmpty,
              scrolloverCountsPending else { return }
        scrolloverCountsPending = false
        readCompletionFeedbackRevision &+= 1
        reloadCounts()
    }

    private func recordSuccessfulScrolloverUndo(_ ids: [Int64], now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard !ids.isEmpty else { return }
        if scrolloverUndoOpenedAt != nil {
            appendSuccessfulScrolloverUndo(ids, now: now)
            return
        }
        recentSuccessfulScrolloverReads.append(contentsOf: ids.map { (id: $0, time: now) })
        recentSuccessfulScrolloverReads.removeAll { now - $0.time > Self.scrolloverUndoQualificationWindow }
        guard recentSuccessfulScrolloverReads.count >= Self.minimumSuccessfulScrolloverReadsForUndo else { return }
        let burstIDs = recentSuccessfulScrolloverReads.map(\.id)
        recentSuccessfulScrolloverReads.removeAll()
        scrolloverUndoOpenedAt = now
        appendSuccessfulScrolloverUndo(burstIDs, now: now)
    }

    private func appendSuccessfulScrolloverUndo(_ ids: [Int64], now: TimeInterval) {
        let groupExpired: Bool
        if let openedAt = scrolloverUndoOpenedAt, let lastSuccessAt = scrolloverUndoLastSuccessAt {
            groupExpired = now - lastSuccessAt >= Self.scrolloverUndoInactivityTimeout || now - openedAt >= Self.scrolloverUndoMaximumLifetime
        } else {
            groupExpired = scrolloverUndoOpenedAt != nil || scrolloverUndoLastSuccessAt != nil
        }
        if scrolloverUndoOpenedAt == nil || groupExpired {
            // A replacement group never presented an empty array to the tracker.
            clearScrolloverUndoGroup(rearmTracker: false, clearQualification: false)
            scrolloverUndoOpenedAt = now
        }
        var seen = Set(scrolloverUndoIDs)
        let unique = ids.filter { seen.insert($0).inserted }
        guard !unique.isEmpty else { return }
        markMeaningfulInteraction()
        scrolloverUndoIDs.append(contentsOf: unique)
        scrolloverCountsPending = true
        scrolloverUndoLastSuccessAt = now
        scheduleScrolloverUndoExpiry()
    }

    private static let scrolloverUndoInactivityTimeout: TimeInterval = 4
    private static let scrolloverUndoMaximumLifetime: TimeInterval = 15
    private static let scrolloverUndoQualificationWindow: TimeInterval = 1
    private static let minimumSuccessfulScrolloverReadsForUndo = 3

    private func scheduleScrolloverUndoExpiry(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard let openedAt = scrolloverUndoOpenedAt, let lastSuccessAt = scrolloverUndoLastSuccessAt else { return }
        scrolloverUndoTask?.cancel()
        scrolloverUndoTask = Task { [weak self] in
            let delay = min(
                Self.scrolloverUndoInactivityTimeout - (now - lastSuccessAt),
                Self.scrolloverUndoMaximumLifetime - (now - openedAt)
            )
            try? await Task.sleep(for: .seconds(max(0, delay)))
            guard !Task.isCancelled else { return }
            self?.expireScrolloverUndoGroup()
        }
    }

    private func expireScrolloverUndoGroup(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard let openedAt = scrolloverUndoOpenedAt, let lastSuccessAt = scrolloverUndoLastSuccessAt else { return }
        if now - openedAt >= Self.scrolloverUndoMaximumLifetime || now - lastSuccessAt >= Self.scrolloverUndoInactivityTimeout {
            clearScrolloverUndoGroup()
        } else {
            scheduleScrolloverUndoExpiry(now: now)
        }
    }

    private func clearScrolloverUndoGroup(rearmTracker: Bool = true, clearQualification: Bool = true) {
        if rearmTracker && !scrolloverUndoIDs.isEmpty { scrolloverRearmRevision &+= 1 }
        scrolloverUndoTask?.cancel()
        scrolloverUndoTask = nil
        scrolloverUndoIDs = []
        scrolloverUndoOpenedAt = nil
        scrolloverUndoLastSuccessAt = nil
        if clearQualification { recentSuccessfulScrolloverReads.removeAll() }
    }

    func undoScrollover() {
        guard !scrolloverUndoIDs.isEmpty, let writer = makeReadMutationWriter() else { return }
        let ids = scrolloverUndoIDs
        let explicitToken = beginExplicitReadMutation(ids)
        let sessionGeneration = scrolloverSessionGeneration
        Task { [weak self, writer] in
            let result = await writer(ids, false)
            guard let self, sessionGeneration == self.scrolloverSessionGeneration else { return }
            self.finishExplicitReadMutation(ids, token: explicitToken)
            switch result {
            case .success:
                updateVisibleRead(ids, read: false)
                clearScrolloverUndoGroup()
                undoCompletionFeedbackRevision &+= 1
                reloadCounts()
            case let .failure(error): errorMessage = IOSErrorPresentation.message(for: error, context: .articleAction)
            }
            notifyExplicitReadMutationWaitersIfIdle()
        }
    }

    func accumulateNewData(_ additions: [(feedID: Int64, count: UInt32)]) { pending.accumulate(additions); publishPending() }
    func adoptVisibleSnapshot() { acknowledgePendingForCurrentScope(); hasUnscopedNewDataSignal = false; resetPresentationState(); replaceSnapshot(shouldResetScroll: true) }
    func resetVisibleSnapshot() { replaceArticles([]); selectionTotal = 0; resetPresentationState() }

    private func acknowledgePendingForCurrentScope() {
        switch scope {
        case .all, .starred: pending.adoptAll()
        case let .category(id): pending.adoptFeeds(in: Set(catalog.feeds.filter { $0.categoryId == id }.map(\.id)))
        case let .feed(id): pending.adoptFeed(id)
        case .search, .listeningList: break
        }
        publishPending()
    }
    private func publishPending() { pendingNewByFeed = pending.byFeed; hasPendingNewData = pending.hasPending }

    private func normalizeStartupScope(categoryIDs: Set<Int64>, feedIDs: Set<Int64>) {
        if startupScope == .category && (startupCategoryID == nil || !categoryIDs.contains(startupCategoryID!)) {
            setStartupCategoryID(nil)
            setStartupScope(.allNews)
        } else if startupScope == .feed && (startupFeedID == nil || !feedIDs.contains(startupFeedID!)) {
            setStartupFeedID(nil)
            setStartupScope(.allNews)
        }
    }

    private func invalidateFeedIconSession() {
        feedIconOwnershipGeneration &+= 1
        requestedFeedIcons = []
        feedIconPresentationStates = [:]
        feedIconRequestRevision &+= 1
        timelinePresentationBridge.resetFeedIcons()
    }

    // Navigation is the Core-owned feed-state refresh. A nil response remains
    // cached until then, while decoded icons stay valid. Requests already in
    // flight belong to the prior feed state and cannot complete into this one.
    private func invalidateFeedIconAvailabilityAfterNavigationRefresh() {
        feedIconOwnershipGeneration &+= 1
        requestedFeedIcons = []
        for state in feedIconPresentationStates.values {
            state.invalidateLoading()
        }
        feedIconPresentationStates = feedIconPresentationStates.filter { $0.value.loadState != .unavailable }
        feedIconRequestRevision &+= 1
    }

    func markMeaningfulInteraction() { hasMeaningfullyInteracted = true }

    private func resetPresentationState(preserveLoading: Bool = false) {
        // Request persistence before rebaselining, but retain queued work when
        // another batch already owns the worker.
        drainScrolloverMutations()
        readLifecycle.invalidateArticle()
        // Presentation-only resets invalidate page publication too. Release the
        // old token now; its synchronous Core work may finish later, but cannot
        // clear or publish into this generation.
        nextTimelinePageRequest = nil
        if !preserveLoading { isLoading = false }
        hasMeaningfullyInteracted = false
        snapshotRevision &+= 1
        // The structural snapshot change independently clears tracker emissions.
        clearScrolloverUndoGroup(rearmTracker: false)
        scrolloverCountsPending = false
        publishedScrolloverPresentationRevisions = [:]
        pendingScrolloverReadPresentationIDs = []
        hasForwardPendingScrolloverPresentation = false
        pendingSuccessfulScrolloverUndoPresentation = []
        for article in loadedArticlesByID.values { rowPresentationStates[article.id]?.reconcile(with: article) }
        scrolloverPresentationPhase = .idle
        scrolloverPresentationGeneration &+= 1
    }

    private func invalidateScrolloverSession() {
        scrolloverSessionGeneration &+= 1
        cancelScrolloverMutationDeadline()
        pendingScrolloverIDs = []
        pendingScrolloverIDSet = []
        runningScrolloverIDs = []
        supersededRunningScrolloverIDs = []
        explicitReadMutationTokens = [:]
        notifyExplicitReadMutationWaitersIfIdle()
        scrolloverMutationRunning = false
        // An in-flight writer is deliberately not synchronously awaited or rebound.
        // It owns the Core/writer captured for the old session and its completion is
        // rejected by the generation guard above.
        scrolloverMutationTask = nil
    }

    private func completeManualSync(
        _ request: IOSManualSyncRequest,
        cancellation: SyncCancellation,
        result: Result<SyncOutcome, Error>
    ) {
        manualSyncExecutions[request] = nil
        if manualSyncPresentationCancellationRequest == request {
            manualSyncPresentationCancellationRequest = nil
            if manualSyncRequest == nil && manualSyncState == .cancelling {
                manualSyncState = .idle
            }
        }
        guard manualSyncLifecycle.isCurrent(request) else { return }

        let cancellationWonPresentation = manualSyncState == .cancelling
            || cancellation.isCancelled()

        switch result {
        case let .success(outcome):
            switch outcome {
            case let .completed(metadata):
                guard !cancellationWonPresentation,
                      manualSyncLifecycle.canPublishCompletion(request) else {
                    finishManualSync(request)
                    return
                }
                finishManualSync(request)
                handleSyncCompleted(metadata)
            case .cancelled:
                finishManualSync(request)
            }
        case let .failure(error):
            if cancellationWonPresentation || error is CancellationError {
                finishManualSync(request)
                return
            }
            finishManualSync(request)
            errorMessage = IOSErrorPresentation.message(for: error, context: .sync)
        }
    }

    private func finishManualSync(_ request: IOSManualSyncRequest) {
        guard manualSyncLifecycle.finish(request) else { return }
        manualSyncState = .idle
        manualSyncRequest = nil
        manualSyncCancellation = nil
        manualSyncTask = nil
        manualSyncPresentationCancellationRequest = nil
    }

    private func invalidateManualSyncSession() {
        if let request = manualSyncRequest {
            _ = manualSyncLifecycle.requestCancellation(request)
        }
        manualSyncCancellation?.cancel()
        manualSyncTask?.cancel()
        for execution in manualSyncExecutions.values {
            execution.cancellation.cancel()
            execution.task.cancel()
        }
        manualSyncLifecycle.invalidateSession()
        manualSyncState = .idle
        manualSyncRequest = nil
        manualSyncCancellation = nil
        manualSyncTask = nil
        manualSyncPresentationCancellationRequest = nil
    }

    fileprivate func ownsCoreEventSession(_ session: UInt64) -> Bool {
        readLifecycle.session == session
    }

    fileprivate func handleSyncCompleted(_ metadata: SyncCompleted) {
        if metadata.reason == .background || metadata.reason == .periodic || metadata.reason == .resume {
            pending.accumulate(metadata.newArticlesByFeed.map { (feedID: $0.feedId, count: $0.count) })
            publishPending()
            if metadata.dataChanged && metadata.newArticlesByFeed.isEmpty { hasUnscopedNewDataSignal = true }
        }
        let action = SnapshotRefreshPolicy.action(manual: metadata.reason == .manual, dataChanged: metadata.dataChanged, hasMeaningfullyInteracted: hasMeaningfullyInteracted)
        if action == .replace { isLoading = true }
        switch IOSSyncCountRefreshPolicy.resolve(dataChanged: metadata.dataChanged, navigationChanged: metadata.navigationChanged) {
        case .navigationAndAllCounts:
            loadNavigationAndCounts { [weak self] in self?.applySyncSnapshotRefresh(metadata, action: action) }
            return
        case .allCounts where action == .replace:
            applySyncSnapshotRefresh(metadata, action: action) { [weak self] in self?.reloadCounts() }
        case .allCounts:
            reloadCounts()
            applySyncSnapshotRefresh(metadata, action: action)
        case .none:
            applySyncSnapshotRefresh(metadata, action: action)
        }
    }

    private func applySyncSnapshotRefresh(_ metadata: SyncCompleted, action: SnapshotRefreshPolicy.Action, afterSnapshot: (() -> Void)? = nil) {
        switch action {
        case .replace:
            hasUnscopedNewDataSignal = false
            if metadata.reason == .manual {
                pending.adoptAll()
                publishPending()
            }
            replaceSnapshot(shouldResetScroll: metadata.reason == .manual, afterLoad: afterSnapshot)
        case .signalNewData:
            if metadata.newArticlesByFeed.isEmpty { hasUnscopedNewDataSignal = true }
            afterSnapshot?()
        case .preserve:
            afterSnapshot?()
        }
    }

    private func replaceSnapshot(shouldResetScroll: Bool = false, afterLoad: (() -> Void)? = nil) {
        resetPresentationState(preserveLoading: true)
        loadVisibleArticles(resetSnapshot: true, completion: afterLoad)
        if shouldResetScroll { requestScrollReset() }
    }

    private func updateVisibleRead(_ ids: [Int64], read: Bool, removeFromVisibleList: Bool = true) {
        let removesReadArticles = ArticleListPresentationPolicy.removesMarkedReadArticle(removeWhenMarkedRead: removeArticlesWhenMarkedRead, unreadOnly: unreadOnly, scope: scope)
        if read && removeFromVisibleList && removesReadArticles {
            _ = optimisticallySetRead(ids, read: true)
            removeVisibleArticles(ids)
        } else { _ = optimisticallySetRead(ids, read: read) }
    }

    private func eligibleScrolloverIDs(_ ids: [Int64]) -> [Int64] {
        ids.filter { id in
            !pendingScrolloverIDSet.contains(id)
                && explicitReadMutationTokens[id] == nil
                && rowPresentationStates[id]?.isRead == false
        }
    }

    private static let maximumScrolloverMutationBatchSize = 64
    private static let defaultScrolloverMutationMaximumWait: Duration = .milliseconds(500)

    private func flushConflictingScrolloverIDs(_ ids: [Int64]) {
        let conflicts = Set(ids)
        let runningConflicts = conflicts.intersection(runningScrolloverIDs)
        pendingScrolloverIDs.removeAll { conflicts.contains($0) }
        pendingScrolloverIDSet.subtract(conflicts.subtracting(runningConflicts))
        pendingScrolloverReadPresentationIDs.subtract(conflicts)
        supersededRunningScrolloverIDs.formUnion(runningConflicts)
        for id in conflicts { publishedScrolloverPresentationRevisions[id] = nil }

        pendingSuccessfulScrolloverUndoPresentation = pendingSuccessfulScrolloverUndoPresentation.compactMap { result in
            let remaining = result.ids.filter { !conflicts.contains($0) }
            guard !remaining.isEmpty else { return nil }
            return IOSPendingScrolloverUndoPresentation(
                ids: remaining,
                generation: result.generation,
                completedAt: result.completedAt
            )
        }
        recentSuccessfulScrolloverReads.removeAll { conflicts.contains($0.id) }

        let hadUndoIDs = !scrolloverUndoIDs.isEmpty
        scrolloverUndoIDs.removeAll { conflicts.contains($0) }
        if hadUndoIDs && scrolloverUndoIDs.isEmpty {
            scrolloverUndoTask?.cancel()
            scrolloverUndoTask = nil
            scrolloverUndoOpenedAt = nil
            scrolloverUndoLastSuccessAt = nil
        }

        if pendingScrolloverIDs.isEmpty {
            cancelScrolloverMutationDeadline()
        }
    }

    private func replaceArticles(_ value: [ArticleSummary]) {
        let referenceDate = Date.now
        replaceFirstTimelinePage(.init(
            page: ArticlePage(articles: value, total: UInt64(value.count), nextCursor: nil),
            contents: value.map { ArticleRowContent(article: $0, referenceDate: referenceDate) },
            referenceDate: referenceDate
        ))
    }

    private func replaceFirstTimelinePage(_ value: TimelinePagePreparation) {
        timelineReferenceDate = value.referenceDate
        let articles = value.page.articles
        loadedArticlesByID = Dictionary(uniqueKeysWithValues: articles.map { ($0.id, $0) })
        let loadedIDs = Set(loadedArticlesByID.keys)
        hasLoadedArticles = !loadedIDs.isEmpty
        rowPresentationStates = rowPresentationStates.filter { loadedIDs.contains($0.key) }
        pendingScrolloverReadPresentationIDs.formIntersection(loadedIDs)
        for (article, content) in zip(articles, value.contents) {
            if let state = rowPresentationStates[article.id] {
                state.reconcile(with: article, content: content)
            } else {
                rowPresentationStates[article.id] = ArticleRowPresentationState(article: article, content: content)
            }
        }
        let states = Dictionary(uniqueKeysWithValues: articles.compactMap { article in
            rowPresentationStates[article.id].map { (article.id, IOSUIKitArticlePresentationState(isRead: $0.isRead, isStarred: $0.isStarred, revision: $0.mutationRevision)) }
        })
        timelinePresentationBridge.replaceArticleStates(states)
        timelineStructuralStorage.items = articles.compactMap { article in
                rowPresentationStates[article.id].map { .init(article: article, content: $0.content) }
        }
        timelineStructuralState = .init(storage: timelineStructuralStorage, change: .replace, revision: timelineStructuralState.revision &+ 1)
        loadArticleAudioActionStates(
            for: articles.map(\.id),
            replacing: true
        )
        nextTimelineCursor = value.page.nextCursor
        hasMoreTimelinePages = value.page.nextCursor != nil
        nextTimelinePageRequest = nil
    }

    func loadNextTimelinePage() {
        guard let core, let cursor = nextTimelineCursor, hasMoreTimelinePages, nextTimelinePageRequest == nil else { return }
        let request = readLifecycle.beginNextArticlePage()
        let currentQuery = query()
        let referenceDate = timelineReferenceDate
        let pageQuery = ArticleQuery(
            scope: currentQuery.scope,
            readFilter: currentQuery.readFilter,
            starredFilter: currentQuery.starredFilter,
            sort: currentQuery.sort,
            limit: Self.timelinePageSize,
            cursor: cursor
        )
        nextTimelinePageRequest = request
        let sessionCoordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, sessionCoordinator] in
            guard let result = await sessionCoordinator.responsiveResult(
                for: core,
                {
                    let page = try core.articlePage(query: pageQuery, includeTotal: false)
                    return TimelinePagePreparation(
                        page: page,
                        contents: page.articles.map { ArticleRowContent(article: $0, referenceDate: referenceDate) },
                        referenceDate: referenceDate
                    )
                }
            ) else { return }
            guard let self, self.completeNextTimelinePageRequest(request) else { return }
            switch result {
            case let .success(value):
                self.appendTimelinePage(value)
            case let .failure(error):
                self.errorMessage = IOSErrorPresentation.message(for: error, context: .contentLoad)
            }
        }
    }

    private func completeNextTimelinePageRequest(_ request: IOSNewsreaderTimelinePageRequest) -> Bool {
        guard readLifecycle.ownsTimelinePage(request), nextTimelinePageRequest == request else { return false }
        nextTimelinePageRequest = nil
        return true
    }

    private func appendTimelinePage(_ value: TimelinePagePreparation) {
        var appended: [IOSUIKitArticleTimelineStructuralItem] = []
        for (article, content) in zip(value.page.articles, value.contents) {
            if loadedArticlesByID[article.id] != nil {
                loadedArticlesByID[article.id] = article
                rowPresentationStates[article.id]?.reconcileContent(with: article, content: content)
                continue
            }
            loadedArticlesByID[article.id] = article
            hasLoadedArticles = true
            let state = ArticleRowPresentationState(article: article, content: content)
            rowPresentationStates[article.id] = state
            appended.append(.init(article: article, content: content))
        }
        let states = Dictionary(uniqueKeysWithValues: appended.compactMap { item in
            rowPresentationStates[item.article.id].map { (item.article.id, IOSUIKitArticlePresentationState(isRead: $0.isRead, isStarred: $0.isStarred, revision: $0.mutationRevision)) }
        })
        timelinePresentationBridge.appendArticleStates(states)
        timelineStructuralStorage.items.append(contentsOf: appended)
        timelineStructuralState = .init(storage: timelineStructuralStorage, change: .append(appended), revision: timelineStructuralState.revision &+ 1)
        if !appended.isEmpty {
            loadArticleAudioActionStates(
                for: appended.map { $0.article.id },
                replacing: false
            )
        }
        nextTimelineCursor = value.page.nextCursor
        hasMoreTimelinePages = value.page.nextCursor != nil
    }

    func rowPresentationState(for article: ArticleSummary) -> ArticleRowPresentationState {
        if let state = rowPresentationStates[article.id] { return state }
        let state = ArticleRowPresentationState(
            article: article,
            content: ArticleRowContent(article: article, referenceDate: timelineReferenceDate)
        )
        rowPresentationStates[article.id] = state
        return state
    }

    private func publishArticlePresentation(_ id: Int64, rearmScrollover: Bool = false) {
        guard let state = rowPresentationStates[id] else { return }
        timelinePresentationBridge.publishArticle(.init(
            articleID: id,
            state: .init(isRead: state.isRead, isStarred: state.isStarred, revision: state.mutationRevision),
            rearmScrollover: rearmScrollover
        ))
    }

    private func optimisticallySetRead(_ ids: [Int64], read: Bool) -> [Int64: UInt64] {
        var revisions: [Int64: UInt64] = [:]
        for id in ids where rowPresentationStates[id] != nil {
            let previous = rowPresentationStates[id]?.isRead
            rowPresentationStates[id]?.setRead(read)
            revisions[id] = rowPresentationStates[id]?.mutationRevision
            if previous != read { publishArticlePresentation(id, rearmScrollover: !read) }
        }
        return revisions
    }

    private func optimisticallySetStarred(_ ids: [Int64], starred: Bool) -> [Int64: UInt64] {
        var revisions: [Int64: UInt64] = [:]
        for id in ids where rowPresentationStates[id] != nil {
            let previous = rowPresentationStates[id]?.isStarred
            rowPresentationStates[id]?.setStarred(starred)
            revisions[id] = rowPresentationStates[id]?.mutationRevision
            if previous != starred { publishArticlePresentation(id) }
        }
        return revisions
    }

    private func restoreReadPresentation(_ ids: [Int64], revisions: [Int64: UInt64], snapshotRevision: UInt64) {
        guard self.snapshotRevision == snapshotRevision else { return }
        for id in ids where rowPresentationStates[id]?.mutationRevision == revisions[id] {
            if let article = loadedArticlesByID[id] {
                rowPresentationStates[id]?.setRead(article.isRead)
                publishArticlePresentation(id, rearmScrollover: !article.isRead)
            }
        }
    }

    private func restoreStarredPresentation(_ ids: [Int64], revisions: [Int64: UInt64], snapshotRevision: UInt64) {
        guard self.snapshotRevision == snapshotRevision else { return }
        for id in ids where rowPresentationStates[id]?.mutationRevision == revisions[id] {
            if let article = loadedArticlesByID[id] {
                rowPresentationStates[id]?.setStarred(article.isStarred)
                publishArticlePresentation(id)
            }
        }
    }

    private func restoreScrolloverPresentation(_ ids: [Int64], presentationGeneration: UInt64) {
        guard presentationGeneration == scrolloverPresentationGeneration else { return }
        pendingScrolloverReadPresentationIDs.subtract(ids)
        for id in ids where rowPresentationStates[id]?.mutationRevision == publishedScrolloverPresentationRevisions[id] {
            if let article = loadedArticlesByID[id] {
                rowPresentationStates[id]?.setRead(article.isRead)
                publishArticlePresentation(id, rearmScrollover: !article.isRead)
            }
        }
    }

    private func removeVisibleArticles(_ ids: [Int64]) {
        let removalSet = Set(ids)
        let removedIDs = ids.filter { loadedArticlesByID.removeValue(forKey: $0) != nil }
        guard !removedIDs.isEmpty else { return }
        hasLoadedArticles = !loadedArticlesByID.isEmpty
        for id in removedIDs {
            rowPresentationStates[id] = nil
            articleAudioActionStates[id] = nil
        }
        timelinePresentationBridge.removeArticleStates(removedIDs)
        pendingScrolloverReadPresentationIDs.subtract(removedIDs)
        timelineStructuralStorage.items.removeAll(where: { removalSet.contains($0.article.id) })
        timelineStructuralState = .init(storage: timelineStructuralStorage, change: .remove(removedIDs), revision: timelineStructuralState.revision &+ 1)
        snapshotRevision &+= 1
    }

    private var unconfiguredError: IOSCoreError { .notConfigured }

    private func markCurrentScopeArticlesRead(completion: @escaping (Bool) -> Void) {
        guard let core else { completion(false); return }
        let scope = scope
        let query = ArticleQuery(scope: query(scope: scope).scope, readFilter: .unread, starredFilter: .all, sort: .newestFirst, limit: 0, cursor: nil)
        let sessionCoordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, sessionCoordinator] in
            guard let result = await sessionCoordinator.responsiveResult(
                for: core,
                { try core.queryArticles(query: query).map(\.id) }
            ) else { return }
            guard let self else { return }
            switch result {
            case let .success(ids):
                guard !ids.isEmpty else { completion(true); return }
                guard let mutation = await sessionCoordinator.responsiveResult(
                    for: core,
                    { try core.setReadStateBulk(articleIds: ids, read: true) }
                ) else { return }
                switch mutation {
                case .success:
                    self.markMeaningfulInteraction()
                    self.loadNavigationAndCounts { [weak self] in
                        self?.loadVisibleArticles(resetSnapshot: true)
                        self?.requestScrollReset()
                    }
                    completion(true)
                case let .failure(error): self.errorMessage = IOSErrorPresentation.message(for: error, context: .articleAction)
                    completion(false)
                }
            case let .failure(error):
                self.errorMessage = IOSErrorPresentation.message(for: error, context: .contentLoad)
                completion(false)
            }
        }
    }

    private func scrolloverDiagnostic(_ message: String) {
#if DEBUG || FLUX_PERFORMANCE_DIAGNOSTICS
        Self.scrolloverDiagnosticLog.debug("\(message, privacy: .public)")
#endif
    }

    private func scrolloverDiagnosticError(ids: [Int64], error: Error) {
#if DEBUG || FLUX_PERFORMANCE_DIAGNOSTICS
        Self.scrolloverDiagnosticLog.debug("mutation failure ids=\(ids) error=\(String(reflecting: error), privacy: .private)")
#endif
    }

    // Narrow seam for deterministic iOS mutation-state tests without a live Core.
    @MainActor
    func setArticlesForTesting(_ value: [ArticleSummary]) { replaceArticles(value) }
    @MainActor
    func appendArticlesForTesting(_ value: [ArticleSummary]) {
        appendTimelinePage(
            .init(
                page: .init(articles: value, total: nil, nextCursor: nil),
                contents: value.map {
                    ArticleRowContent(article: $0, referenceDate: timelineReferenceDate)
                },
                referenceDate: timelineReferenceDate
            )
        )
    }
    @MainActor
    var timelineReferenceDateForTesting: Date { timelineReferenceDate }
    @MainActor
    var timelineStructuralItemCountForTesting: Int { timelineStructuralStorage.items.count }
    @MainActor
    var timelineStructuralChangeForTesting: IOSUIKitArticleTimelineStructuralChange { timelineStructuralState.change }
    @MainActor
    func removeVisibleArticlesForTesting(_ ids: [Int64]) { removeVisibleArticles(ids) }
    @MainActor
    func setTimelinePagingForTesting(cursor: ArticleCursor?, hasMore: Bool) {
        nextTimelineCursor = cursor
        hasMoreTimelinePages = hasMore
    }
    @MainActor
    var timelinePagingStateForTesting: (cursor: ArticleCursor?, hasMore: Bool, inFlight: Bool) {
        (nextTimelineCursor, hasMoreTimelinePages, nextTimelinePageRequest != nil)
    }
    @MainActor
    func beginTimelinePageRequestForTesting() -> IOSNewsreaderTimelinePageRequest {
        let request = readLifecycle.beginNextArticlePage()
        nextTimelinePageRequest = request
        return request
    }
    @MainActor
    func completeTimelinePageRequestForTesting(_ request: IOSNewsreaderTimelinePageRequest) -> Bool {
        completeNextTimelinePageRequest(request)
    }
    @MainActor
    func resetTimelinePagingGenerationForTesting() { resetPresentationState() }
    @MainActor
    func applyReadMutationForTesting(_ ids: [Int64], read: Bool) { markMeaningfulInteraction(); updateVisibleRead(ids, read: read) }
    @MainActor
    func applyScrolloverMutationForTesting(_ ids: [Int64], now: TimeInterval = 0) {
        let eligible = eligibleScrolloverIDs(ids)
        _ = optimisticallySetRead(eligible, read: true)
        completeSuccessfulScrolloverMutation(eligible, presentationGeneration: scrolloverPresentationGeneration, completedAt: now)
    }
    @MainActor
    func setScrolloverPresentationPhaseForTesting(_ phase: IOSScrolloverPresentationPhase) { setScrolloverPresentationPhase(phase) }
    @MainActor
    func receiveScrolloverDirectionForTesting(_ direction: IOSArticleScrollDirection) { receiveScrolloverDirection(direction) }
    @MainActor
    func completeSuccessfulScrolloverMutationForTesting(_ ids: [Int64], generation: UInt64? = nil, now: TimeInterval = 0) {
        completeSuccessfulScrolloverMutation(ids, presentationGeneration: generation ?? scrolloverPresentationGeneration, completedAt: now)
    }
    @MainActor
    var pendingScrolloverPresentationIDsForTesting: [Int64] { pendingScrolloverReadPresentationIDs.sorted() }
    @MainActor
    func rebaselineScrolloverPresentationForTesting() { resetPresentationState() }
    @MainActor
    var scrolloverQueueGenerationForTesting: UInt64 { scrolloverPresentationGeneration }
    @MainActor
    func applyScrolloverUndoForTesting() { updateVisibleRead(scrolloverUndoIDs, read: false); clearScrolloverUndoGroup() }
    @MainActor
    var scrolloverUndoIDsForTesting: [Int64] { scrolloverUndoIDs }
    @MainActor
    func eligibleScrolloverIDsForTesting(_ ids: [Int64]) -> [Int64] { eligibleScrolloverIDs(ids) }
    @MainActor
    func enqueueScrolloverForTesting(_ ids: [Int64]) -> [Int64] {
        acceptScrolloverForTesting(ids)
    }
    @MainActor
    func acceptScrolloverForTesting(_ ids: [Int64]) -> [Int64] {
        acceptScrolloverIDs(ids)
    }
    @MainActor
    func beginScrolloverMutationForTesting() -> [Int64] {
        let ids = Array(pendingScrolloverIDs.prefix(Self.maximumScrolloverMutationBatchSize))
        pendingScrolloverIDs.removeFirst(ids.count)
        return ids
    }
    @MainActor
    func flushScrolloverPersistenceForTesting() -> [Int64] {
        let ids = Array(pendingScrolloverIDs.prefix(Self.maximumScrolloverMutationBatchSize))
        pendingScrolloverIDs.removeFirst(ids.count)
        return ids
    }
    @MainActor
    func discardPendingScrolloverForTesting(_ ids: [Int64]) { flushConflictingScrolloverIDs(ids) }
    @MainActor
    func failScrolloverMutationForTesting(_ ids: [Int64], generation: UInt64? = nil) {
        restoreScrolloverPresentation(ids, presentationGeneration: generation ?? scrolloverPresentationGeneration)
        for id in ids {
            pendingScrolloverIDSet.remove(id)
            publishedScrolloverPresentationRevisions[id] = nil
        }
    }
    @MainActor
    func expireScrolloverUndoGroupForTesting(now: TimeInterval) { expireScrolloverUndoGroup(now: now) }
    @MainActor
    func applyStarredMutationForTesting(_ ids: [Int64], starred: Bool) {
        markMeaningfulInteraction()
        _ = optimisticallySetStarred(ids, starred: starred)
        if !starred && scope == .starred { removeVisibleArticles(ids) }
    }
    @MainActor
    func completeSyncForTesting(_ metadata: SyncCompleted) { handleSyncCompleted(metadata) }
    @MainActor
    func setManualSyncStateForTesting(_ value: IOSManualSyncState) { manualSyncState = value }
    @MainActor
    var meaningfullyInteractedForTesting: Bool { hasMeaningfullyInteracted }
    @MainActor
    var pendingByFeedForTesting: [Int64: Int] { pendingNewByFeed }
    @MainActor
    func normalizeStartupScopeForTesting(categoryIDs: Set<Int64>, feedIDs: Set<Int64>) { normalizeStartupScope(categoryIDs: categoryIDs, feedIDs: feedIDs) }
    @MainActor
    func setCatalogForTesting(_ value: NavigationCatalog) { catalog = value }
    @MainActor
    func setSelectionTotalForTesting(_ value: UInt64) { selectionTotal = value }
    @MainActor
    func rowPresentationStateForTesting(_ id: Int64) -> ArticleRowPresentationState? { rowPresentationStates[id] }
    @MainActor
    func isArticleReadForTesting(_ id: Int64) -> Bool? { rowPresentationStates[id]?.isRead }
    @MainActor
    func isArticleStarredForTesting(_ id: Int64) -> Bool? { rowPresentationStates[id]?.isStarred }
    @MainActor
    static var maximumScrolloverMutationBatchSizeForTesting: Int { maximumScrolloverMutationBatchSize }
    @MainActor
    var pendingScrolloverIDsForTesting: [Int64] { pendingScrolloverIDs }
    @MainActor
    func invalidateScrolloverSessionForTesting() { invalidateScrolloverSession() }
    @MainActor
    var scrolloverSessionGenerationForTesting: UInt64 { scrolloverSessionGeneration }
    @MainActor
    func setReadMutationWriterForTesting(
        _ writer: @escaping @MainActor ([Int64], Bool) async -> Result<Void, Error>
    ) {
        readMutationWriterOverride = writer
    }
    @MainActor
    func setScrolloverMutationMaximumWaitForTesting(_ value: Duration) {
        scrolloverMutationMaximumWaitOverride = value
    }
    @MainActor
    var scrolloverMutationRunningForTesting: Bool { scrolloverMutationRunning }
    @MainActor
    var runningScrolloverIDsForTesting: [Int64] { runningScrolloverIDs.sorted() }
#if DEBUG
    @MainActor
    func waitForExplicitReadMutationsForTesting() async {
        guard !explicitReadMutationTokens.isEmpty else { return }
        await withCheckedContinuation { continuation in
            explicitReadMutationWaiters.append(continuation)
        }
    }
#endif

    private func reloadCounts() {
        guard let core else { return }
        let navigationRequest = readLifecycle.beginNavigation()
        let request = readLifecycle.beginSelectionCount()
        let selectionQuery = query()
        let countMode: NavigationCountMode = unreadOnly ? .unread : .all
        let sessionCoordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, sessionCoordinator] in
            guard let result = await sessionCoordinator.responsiveResult(
                for: core,
                {
                    let selection = try core.countArticles(query: selectionQuery)
                    let navigation = try core.navigationProjection(countMode: countMode)
                    return (selection, navigation)
                }
            ) else { return }
            guard let self else { return }
            switch result {
            case let .success(counts):
                if readLifecycle.isCurrentSelectionCount(request) { selectionTotal = counts.0 }
                if readLifecycle.isCurrentNavigation(navigationRequest) {
                    publishNavigationProjection(counts.1)
                }
                if readLifecycle.ownsError(request) { errorMessage = nil }
            case let .failure(error):
                if readLifecycle.ownsError(request) { errorMessage = IOSErrorPresentation.message(for: error, context: .contentLoad) }
            }
        }
    }

    private func publishNavigationProjection(_ projection: NavigationProjection) {
        catalog = projection.catalog
        unreadTotal = projection.unreadTotal
        starredTotal = projection.starredTotal
        categoryCounts = Dictionary(uniqueKeysWithValues: projection.categoryCounts.map { ($0.id, $0.count) })
        feedCounts = Dictionary(uniqueKeysWithValues: projection.feedCounts.map { ($0.id, $0.count) })
        invalidateFeedIconAvailabilityAfterNavigationRefresh()
        pending.removeAbsentFeeds(Set(projection.catalog.feeds.map(\.id)))
        publishPending()
    }

    private func requestScrollReset() { scrollResetRevision &+= 1 }
}

private final class IOSNewsreaderEventListener: EventListener, @unchecked Sendable {
    weak var store: NewsreaderStore?
    let session: UInt64

    init(store: NewsreaderStore, session: UInt64) {
        self.store = store
        self.session = session
    }

    func onEvent(event: CoreEvent) {
        guard case let .syncDidComplete(metadata) = event,
              IOSNewsreaderEventRoutingPolicy.shouldDispatchSyncCompleted(reason: metadata.reason) else { return }
        let session = session
        Task { @MainActor [weak store] in
            guard let store, store.ownsCoreEventSession(session) else { return }
            store.handleSyncCompleted(metadata)
        }
    }
}
