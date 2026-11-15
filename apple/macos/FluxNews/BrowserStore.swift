import AppKit
import Combine
import Foundation
import Security


private struct MacOSBackupSettingsV1: Codable {
    static let version: UInt32 = 1
    let version: UInt32
    let markReadOnScrollover: Bool
    let syncOnStart: Bool
    let articlePresentationMode: String
    let previewLines: Int
    let showArticleCount: Bool?
    let showRelativePublicationTime: Bool?
    let clickOnNews: String
    let globalShortcut: String
    let launchAtLogin: Bool
    let startupScope: String?
    let startupCategoryID: Int64?
    let startupFeedID: Int64?
    let hideEmptyNavigationEntries: Bool?
    let removeArticlesWhenMarkedRead: Bool?
    let customHeaders: [CustomHTTPHeader]?
}

private enum ConfigurationBackupPresentationError: LocalizedError {
    case noConfiguredAccount
    case unsupportedPlatformSettings
    case coreInitialization

    var errorDescription: String? {
        switch self {
        case .noConfiguredAccount: "Configure a Miniflux account before exporting a backup."
        case .unsupportedPlatformSettings: "This backup contains unsupported macOS settings."
        case .coreInitialization: "The restored account could not be activated locally."
        }
    }
}

@MainActor
final class BrowserStore: ObservableObject {
    nonisolated static var mediaRootURL: URL { MediaPlaybackPaths.mediaRootURL }
    var onCoreConfigured: ((Flux) -> Void)?
    @Published var articles: [ArticleSummary] = []
    @Published var catalog = NavigationCatalog(categories: [], feeds: [])
    @Published var unreadTotal: UInt64 = 0
    @Published var starredTotal: UInt64 = 0
    @Published var selectionTotal: UInt64 = 0
    @Published var categorySidebarCounts: [Int64: UInt64] = [:]
    @Published var feedSidebarCounts: [Int64: UInt64] = [:]
    @Published private(set) var feedIcons: [String: NSImage] = [:]
    @Published private(set) var articleThumbnails: [String: NSImage] = [:]
    @Published private(set) var unavailableArticleThumbnails = Set<String>()
    @Published var isLoading = false
    @Published private(set) var isMarkingScopeRead = false
    @Published var errorMessage: String?
    @Published var actionConfirmation: String?
    @Published var scope: BrowserScope = .all
    @Published private(set) var listeningListItems: [ListeningListItem] = []
    @Published private(set) var artworkProbeRevisions: [Int64: UInt64] = [:]
    @Published private(set) var listeningListFeeds: [ListeningListFeed] = []
    @Published var listeningListSort: ListeningListSort = .recentlyAdded
    @Published var listeningListFeedID: Int64?
    @Published var searchQuery = ""
    @Published private(set) var searchTotal: Int64 = 0
    @Published private(set) var hasSearched = false
    @Published private(set) var isSearching = false
    @Published var unreadOnly = true
    @Published var newestFirst = false
    @Published var popoverVisible = false
    @Published var settingsVisible = false
    @Published var addFeedVisible = false
    @Published var addCategoryVisible = false
    @Published var newDataAvailable = false
    @Published var lastScrolloverBatch: [Int64] = []
    @Published var scrolloverUndoVisible = false
    @Published var markReadOnScrolloverEnabled = true
    @Published var startupScope: StartupScopePreference
    @Published var startupCategoryID: Int64?
    @Published var startupFeedID: Int64?
    @Published var hideEmptyNavigationEntries: Bool
    @Published var removeArticlesWhenMarkedRead: Bool
    @Published private(set) var syncOnStartEnabled: Bool
    @Published var articlePresentationMode: ArticlePresentationMode
    @Published var articlePreviewLines: ArticlePreviewLines
    @Published var showArticleCount: Bool
    @Published var showRelativePublicationTime: Bool
    @Published var clickOnNews: ClickOnNews
    @Published var globalShortcut: GlobalShortcutChoice
    @Published var globalShortcutRegistrationError: String?
    @Published private(set) var coreSettings: CoreSettings?
    @Published private(set) var pendingNewByFeed: [Int64: Int] = [:]
    @Published private(set) var hasPendingNewData = false
    @Published private(set) var systemNotificationSettings: [FeedSystemNotificationSetting] = []
    @Published private(set) var systemNotificationSettingsError: String?
    @Published private(set) var updatingSystemNotificationFeedIDs = Set<Int64>()
    @Published private(set) var listPresentationRevision: UInt64 = 0
    @Published private(set) var snapshotResetRevision: UInt64 = 0
    @Published private(set) var configuredServer: String?
    @Published private(set) var minifluxVersion: String?
    @Published private(set) var accountValidationError: String?
    @Published private(set) var isSavingAccount = false
    @Published var feedSettingsTarget: FeedSettingsTarget?
    @Published private(set) var articleAudioActionState: ArticleAudioActionState?
    @Published private(set) var articleAudioActionStates: [Int64: ArticleAudioActionState] = [:]

    private var scopeReadActionGeneration: UInt64 = 0
    private var core: Flux?
    private let coreSessionExecutionCoordinator = AppleCoreSessionExecutionCoordinator()
    private var eventSubscription: EventSubscription?
    private var eventSessionGeneration: UInt64 = 0

    private func endEventSubscription() {
        eventSessionGeneration &+= 1
        if let eventSubscription { try? eventSubscription.unsubscribe() }
        eventSubscription = nil
    }
    private var lastSyncAttempt: Date?
    private var networkAvailability: Bool?
    private var networkRecoveryState = NetworkRecoveryState()
    private var periodicSyncTimer: Timer?
    private var hasMeaningfullyInteracted = false
    private var sharingPicker: NSSharingServicePicker?
    private var undoExpiry: Task<Void, Never>?
    private var actionConfirmationExpiry: Task<Void, Never>?
    private var feedIconRequests = FeedIconRequestState()
    private var scrolloverUndoBatch = ScrolloverUndoBatch()
    private var articleThumbnailRequests = ArticleThumbnailRequestState()
    private var scrolloverCountsPending = false
    private var searchGeneration: UInt64 = 0
    private var pendingNewData = PendingNewData()
    private var readerDocumentRequest: UInt64 = 0
    private let searchPageSize: UInt32 = 50
    private var pendingWidgetActions: [WidgetAction] = []
    private var startupRouteState = StartupRouteState()
    private var hasAppliedStartupScope = false
    private var scrolloverRemovedArticles: [Int64: ArticleSummary] = [:]
    private var scrolloverOriginalOrder: [Int64: Int] = [:]
    private var articleAudioRequestGeneration: UInt64 = 0
    private var artworkProbeRequestedIDs = Set<Int64>()
    private var artworkProbeQueue: [Int64] = []
    private var artworkProbeInFlight = false
    var onMediaTransferRequested: (() -> Void)?
    var onCancelMediaTransferRequested: ((Int64) -> Void)?
    var onReleaseMediaForDownloadDeletion: ((Int64) -> Void)?

    init() {
        markReadOnScrolloverEnabled = UserDefaults.standard.object(forKey: "FluxNews.markReadOnScrollover") as? Bool ?? true
        startupScope = UserDefaults.standard.string(forKey: "FluxNews.startupScope").flatMap(StartupScopePreference.init(rawValue:)) ?? .allNews
        startupCategoryID = UserDefaults.standard.object(forKey: "FluxNews.startupCategoryID") as? Int64
        startupFeedID = UserDefaults.standard.object(forKey: "FluxNews.startupFeedID") as? Int64
        hideEmptyNavigationEntries = UserDefaults.standard.object(forKey: "FluxNews.hideEmptyNavigationEntries") as? Bool ?? false
        removeArticlesWhenMarkedRead = UserDefaults.standard.object(forKey: "FluxNews.removeArticlesWhenMarkedRead") as? Bool ?? false
        syncOnStartEnabled = UserDefaults.standard.object(forKey: "FluxNews.syncOnStart") as? Bool ?? true
        articlePresentationMode = UserDefaults.standard.string(forKey: "FluxNews.articlePresentationMode").flatMap(ArticlePresentationMode.init(rawValue:)) ?? .visual
        articlePreviewLines = ArticlePreviewLines(rawValue: UserDefaults.standard.integer(forKey: "FluxNews.articlePreviewLines")) ?? .standard
        showArticleCount = UserDefaults.standard.object(forKey: "FluxNews.showArticleCount") as? Bool ?? true
        showRelativePublicationTime = UserDefaults.standard.object(forKey: "FluxNews.showRelativePublicationTime") as? Bool ?? false
        clickOnNews = UserDefaults.standard.string(forKey: "FluxNews.clickOnNews").flatMap(ClickOnNews.init(rawValue:)) ?? .openLink
        globalShortcut = GlobalShortcutChoice.stored()
    }

    func start() {
        do {
            guard let credentials = try CredentialStore.load() else { settingsVisible = true; return }
            NativeLog.keychain.notice("stored Miniflux credentials loaded")
            Task { [weak self] in
                guard let self else { return }
                _ = await self.configure(
                    server: credentials.server,
                    apiKey: credentials.apiKey,
                    customHeaders: credentials.resolvedCustomHeaders
                )
            }
        } catch {
            NativeLog.keychain.error("credential lookup failed: \(error.localizedDescription, privacy: .private)")
            errorMessage = NativeErrorPresentation.message(for: error)
            settingsVisible = true
        }
    }

    @discardableResult
    func configure(
        server: String,
        apiKey: String,
        customHeaders: [CustomHTTPHeader] = [],
        refreshVersion: Bool = true,
        startSync: Bool = true
    ) async -> Bool {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FluxNews", isDirectory: true)
        let cache = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FluxNews", isDirectory: true)
        let media = Self.mediaRootURL
        let previousCore = core

        if previousCore != nil {
            await coreSessionExecutionCoordinator.quiesce()
        }

        MacSupportDiagnostics.shared.registerSecrets([server, apiKey] + customHeaders.flatMap { [$0.name, $0.value] })
        let headers = customHeaders.map { HttpHeader(name: $0.name, value: $0.value) }
        let creation = await AppleCoreExecution.shared.responsiveResult {
            try Flux.initializeWithDiagnostics(
                config: InitializationConfig(
                    persistentData: support.path,
                    cache: cache.path,
                    media: media.path,
                    baseUrl: server,
                    apiKey: apiKey,
                    customHeaders: headers
                ),
                listener: CoreDiagnosticLogger()
            )
        }

        let configuredCore: Flux
        switch creation {
        case let .success(value):
            configuredCore = value
        case let .failure(error):
            if let previousCore { coreSessionExecutionCoordinator.resume(previousCore) }
            NativeLog.app.error("core configuration failed: \(error.localizedDescription, privacy: .private)")
            errorMessage = NativeErrorPresentation.message(for: error)
            return false
        }

        if previousCore != nil { coreSessionExecutionCoordinator.deactivate() }
        coreSessionExecutionCoordinator.activate(configuredCore)

        let listener = BrowserEventListener(store: self)
        guard let setup = await coreSessionExecutionCoordinator.responsiveResult(
            for: configuredCore,
            {
                let settings = try configuredCore.coreSettings()
                let subscription = try configuredCore.subscribeEvents(listener: listener)
                return (settings, subscription)
            }
        ) else {
            coreSessionExecutionCoordinator.deactivate()
            if let previousCore { coreSessionExecutionCoordinator.activate(previousCore) }
            return false
        }

        switch setup {
        case let .success((settings, subscription)):
            endEventSubscription()
            listener.generation = eventSessionGeneration
            core = configuredCore
            // Account-scoped probe bookkeeping must never survive Core replacement.
            artworkProbeRequestedIDs.removeAll()
            artworkProbeQueue.removeAll()
            artworkProbeInFlight = false
            artworkProbeRevisions = [:]
            onCoreConfigured?(configuredCore)
            configuredServer = server
            coreSettings = settings
            lastSyncAttempt = nil
            eventSubscription = subscription
            NativeLog.app.notice("core configured")
            NativeLog.support("app", "core configured")
            if previousCore != nil {
                invalidateLocalPresentation()
            } else {
                resetPresentation()
            }
            reloadNavigationAndCounts()
            refreshWidgetSnapshot()
            consumePendingWidgetActions()
            applyStartupScopeIfNeeded()
            reloadVisibleArticles()
            if startSync && syncOnStartEnabled { sync(reason: .appStart) }
            if settings.backgroundSyncEnabled { activatePeriodicSyncScheduling() }
            else { deactivatePeriodicSyncScheduling() }
            if refreshVersion {
                refreshMinifluxVersion(
                    server: server,
                    apiKey: apiKey,
                    customHeaders: customHeaders,
                    for: configuredCore
                )
            }
            return true
        case let .failure(error):
            coreSessionExecutionCoordinator.deactivate()
            if let previousCore { coreSessionExecutionCoordinator.activate(previousCore) }
            NativeLog.app.error("core setup failed: \(error.localizedDescription, privacy: .private)")
            errorMessage = NativeErrorPresentation.message(for: error)
            return false
        }
    }

    func saveAccount(
        server: String,
        apiKey: String,
        customHeaders: [CustomHTTPHeader],
        launchAtLogin: Bool,
        scrollover: Bool,
        syncOnStart: Bool,
        globalShortcut: GlobalShortcutChoice
    ) {
        guard !isSavingAccount else { return }
        isSavingAccount = true
        accountValidationError = nil
        Task { [weak self] in
            let validation = await AppleCoreExecution.shared.blockingResult {
                try validateMinifluxAccount(
                    serverUrl: server,
                    apiKey: apiKey,
                    customHeaders: customHeaders.map { HttpHeader(name: $0.name, value: $0.value) }
                )
            }
            guard let self else { return }
            self.isSavingAccount = false
            switch validation {
            case let .success(result):
                await self.commitValidatedAccount(
                    result,
                    apiKey: apiKey,
                    customHeaders: customHeaders,
                    launchAtLogin: launchAtLogin,
                    scrollover: scrollover,
                    syncOnStart: syncOnStart,
                    globalShortcut: globalShortcut
                )
            case let .failure(error):
                self.accountValidationError = AccountValidationPresentation.message(
                    for: self.accountValidationFailure(for: error)
                )
            }
        }
    }

    private func commitValidatedAccount(
        _ validation: AccountValidationResult,
        apiKey: String,
        customHeaders: [CustomHTTPHeader],
        launchAtLogin: Bool,
        scrollover: Bool,
        syncOnStart: Bool,
        globalShortcut: GlobalShortcutChoice
    ) async {
        do {
            let previousCredentials = try CredentialStore.load()
            invalidateWidgetSnapshot()
            try CredentialStore.save(
                MinifluxCredentials(
                    server: validation.installationBase,
                    apiKey: apiKey,
                    customHeaders: customHeaders
                )
            )
            guard await configure(
                server: validation.installationBase,
                apiKey: apiKey,
                customHeaders: customHeaders,
                refreshVersion: false
            ) else {
                do { try restoreCredentials(previousCredentials) }
                catch {
                    accountValidationError = String(localized: "The account could not be saved.")
                    return
                }
                accountValidationError = String(
                    localized: "The validated account could not be configured. Your previous account is still active."
                )
                return
            }
            try CredentialStore.setLaunchAtLogin(launchAtLogin)
            setScrolloverEnabled(scrollover)
            setSyncOnStartEnabled(syncOnStart)
            setGlobalShortcut(globalShortcut)
            configuredServer = validation.installationBase
            minifluxVersion = validation.version
            accountValidationError = nil
        } catch {
            accountValidationError = String(localized: "The account could not be saved.")
        }
    }

    private func restoreCredentials(_ credentials: MinifluxCredentials?) throws {
        if let credentials { try CredentialStore.save(credentials) }
        else { try CredentialStore.remove() }
    }

    private func accountValidationFailure(for error: Error) -> AccountValidationFailure {
        switch error {
        case AccountValidationError.InvalidUrl, AccountValidationError.UnsupportedUrlScheme:
            .invalidURL
        case AccountValidationError.Network, AccountValidationError.ServerUnavailable:
            .network
        case AccountValidationError.Unauthorized:
            .unauthorized
        case AccountValidationError.IncompatibleServer:
            .incompatibleServer
        case AccountValidationError.InvalidResponse:
            .invalidResponse
        case AccountValidationError.InvalidCustomHeader:
            .invalidCustomHeader
        default:
            .invalidResponse
        }
    }

    private func refreshMinifluxVersion(server: String, apiKey: String, customHeaders: [CustomHTTPHeader], for configuredCore: Flux) {
        Task { [weak self] in
            let result = await AppleCoreExecution.shared.blockingResult {
                try validateMinifluxAccount(
                    serverUrl: server,
                    apiKey: apiKey,
                    customHeaders: customHeaders.map { HttpHeader(name: $0.name, value: $0.value) }
                )
            }
            guard let self, self.core === configuredCore else { return }
            if case let .success(validation) = result {
                self.minifluxVersion = validation.version
            }
        }
    }

    var isListeningList: Bool { scope == .listeningList }
    func feedID(forArticleID articleID: Int64) -> Int64? {
        articles.first(where: { $0.id == articleID })?.feedId
            ?? listeningListItems.first(where: { $0.articleId == articleID })?.feedId
    }
    func query(scope: BrowserScope? = nil) -> ArticleQuery? {
        let requestedScope = scope ?? self.scope
        let coreScope: ArticleScope
        switch requestedScope {
        case .all, .starred:
            coreScope = .all
        case let .category(id):
            coreScope = .category(id: id)
        case let .feed(id):
            coreScope = .feed(id: id)
        case .search, .listeningList:
            return nil
        }
        return ArticleQuery(
            scope: coreScope,
            readFilter: requestedScope == .starred ? .all : (unreadOnly ? .unread : .all),
            starredFilter: requestedScope == .starred ? .starred : .all,
            sort: newestFirst ? .newestFirst : .oldestFirst,
            limit: 0,
            cursor: nil
        )
    }
    var canMarkCurrentScopeRead: Bool {
        core != nil && !isMarkingScopeRead && ScopeReadActionPolicy.supportsMarkAll(scope)
    }

    var nextScopeAfterMarkRead: BrowserScope? {
        ScopeReadActionPolicy.nextVisibleScope(
            after: scope,
            categoryIDs: catalog.categories.map(\.id),
            feeds: catalog.feeds.map { NavigationPresentationFeed(id: $0.id, categoryID: $0.categoryId) },
            hidingEmpty: hideEmptyNavigationEntries,
            counts: feedSidebarCounts
        )
    }

    func markCurrentScopeRead(andNavigateNext: Bool = false) {
        guard canMarkCurrentScopeRead, let core, let currentQuery = query() else { return }
        let originalScope = scope
        let nextScope = andNavigateNext ? nextScopeAfterMarkRead : nil
        if andNavigateNext && nextScope == nil { return }
        let unreadQuery = ScopeReadActionPolicy.unreadQuery(from: currentQuery)
        scopeReadActionGeneration &+= 1
        let generation = scopeReadActionGeneration
        isMarkingScopeRead = true
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.responsiveResult(for: core, {
                let ids = try core.queryArticles(query: unreadQuery).map(\.id)
                if !ids.isEmpty {
                    _ = try core.setReadStateBulk(articleIds: ids, read: true)
                }
                return ids.count
            }) else {
                if let self, self.core === core, self.scopeReadActionGeneration == generation {
                    self.isMarkingScopeRead = false
                }
                return
            }
            guard let self, self.core === core, self.scopeReadActionGeneration == generation else { return }
            self.isMarkingScopeRead = false
            switch result {
            case let .success(count):
                self.showActionConfirmation(String(localized: "Marked \(count) articles as read"))
                self.reloadCounts()
                if self.scope == originalScope {
                    if let nextScope {
                        self.select(nextScope)
                    } else {
                        self.reloadVisibleArticles()
                    }
                }
                self.refreshWidgetSnapshot()
            case let .failure(error):
                self.errorMessage = NativeErrorPresentation.message(for: error)
            }
        }
    }

    func reloadVisibleArticles(resetPosition: Bool = false, acknowledgingPendingNewData: Bool = false) {
        guard !isListeningList, scope != .search, let core, let articleQuery = query() else { return }
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.responsiveResult(
                for: core,
                {
                    let articles = try core.queryArticles(query: articleQuery)
                    let selectionTotal = try core.countArticles(query: articleQuery)
                    return (articles, selectionTotal)
                }
            ) else { return }
            guard let self, self.core === core else { return }
            switch result {
            case let .success((articles, selectionTotal)):
                self.articles = articles
                self.loadArticleAudioActions(for: articles.map(\.id))
                self.selectionTotal = selectionTotal
                self.errorMessage = nil
                if acknowledgingPendingNewData { self.acknowledgePendingNewDataForCurrentScope() }
                if resetPosition {
                    self.resetPresentation()
                    self.snapshotResetRevision &+= 1
                }
            case let .failure(error):
                NativeLog.app.error("article reload failed: \(String(describing: error), privacy: .private)")
                self.errorMessage = NativeErrorPresentation.message(for: error)
            }
        }
    }

    func reloadSelectionTotal() {
        guard let core, let articleQuery = query() else { return }
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.responsiveResult(
                for: core,
                { try core.countArticles(query: articleQuery) }
            ) else { return }
            guard let self, self.core === core else { return }
            switch result {
            case let .success(total):
                self.selectionTotal = total
                self.errorMessage = nil
            case let .failure(error):
                NativeLog.app.error("selection count reload failed: \(String(describing: error), privacy: .private)")
                self.errorMessage = NativeErrorPresentation.message(for: error)
            }
        }
    }

    func reloadNavigation() { reloadNavigationAndCounts() }
    func reloadCounts() { reloadNavigationAndCounts() }

    func reloadNavigationAndCounts() {
        guard let core else { return }
        let countMode: NavigationCountMode = unreadOnly ? .unread : .all
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.responsiveResult(
                for: core,
                { try core.navigationProjection(countMode: countMode) }
            ) else { return }
            guard let self, self.core === core else { return }
            switch result {
            case let .success(projection):
                self.catalog = projection.catalog
                self.unreadTotal = projection.unreadTotal
                self.starredTotal = projection.starredTotal
                self.categorySidebarCounts = Dictionary(uniqueKeysWithValues: projection.categoryCounts.map { ($0.id, $0.count) })
                self.feedSidebarCounts = Dictionary(uniqueKeysWithValues: projection.feedCounts.map { ($0.id, $0.count) })
                self.pendingNewData.removeAbsentFeeds(Set(projection.catalog.feeds.map(\.id)))
                self.publishPendingNewData()
                self.errorMessage = nil
            case let .failure(error):
                NativeLog.app.error("navigation projection reload failed: \(String(describing: error), privacy: .private)")
                self.errorMessage = NativeErrorPresentation.message(for: error)
            }
        }
    }

    func requestFeedIcon(_ feedID: Int64, darkAppearance: Bool, displayScale: CGFloat = 2) {
        let key = "\(feedID)-\(darkAppearance ? "dark" : "normal")"
        guard feedIconRequests.begin(key, cached: feedIcons[key] != nil), let core else { return }
        let variant: FeedIconVariant = darkAppearance ? .dark : .normal
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            defer { self?.feedIconRequests.complete(key) }
            guard let result = await coordinator.blockingResult(
                for: core,
                { try core.feedIcon(feedId: feedID, variant: variant) }
            ) else { return }
            guard let self, self.core === core else { return }
            switch result {
            case let .success(icon):
                let prepared = await Task.detached(priority: .userInitiated) {
                    icon.flatMap {
                        MacOSFeedIconImagePreparation.prepare(
                            data: Data($0.pngData),
                            displayScale: displayScale
                        )
                    }
                }.value
                guard self.core === core else { return }
                if let prepared {
                    self.feedIcons[key] = NSImage(
                        cgImage: prepared.image,
                        size: NSSize(
                            width: MacOSFeedIconImagePreparation.displaySidePoints,
                            height: MacOSFeedIconImagePreparation.displaySidePoints
                        )
                    )
                }
            case .failure:
                break
            }
        }
    }

    func articleThumbnailKey(_ article: ArticleSummary) -> String { "\(article.id)-\(article.imageUrl ?? "")" }

    func requestArticleThumbnail(_ article: ArticleSummary) {
        guard let imageURL = article.imageUrl else { return }
        let key = articleThumbnailKey(article)
        guard !unavailableArticleThumbnails.contains(key),
              articleThumbnailRequests.begin(key, cached: articleThumbnails[key] != nil),
              let core else { return }
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            defer { self?.articleThumbnailRequests.complete(key) }
            guard let result = await coordinator.blockingResult(
                for: core,
                { try core.articleThumbnail(articleId: article.id, imageUrl: imageURL) }
            ) else { return }
            guard let self, self.core === core else { return }
            switch result {
            case let .success(thumbnailResult):
                switch thumbnailResult {
                case let .available(pngData):
                    let image = await Task.detached(priority: .userInitiated) {
                        NSImage(data: Data(pngData))
                    }.value
                    guard self.core === core else { return }
                    if let image { self.articleThumbnails[key] = image }
                case .unavailable:
                    self.unavailableArticleThumbnails.insert(key)
                }
            case .failure:
                self.unavailableArticleThumbnails.insert(key)
            }
        }
    }

    func retryUnavailableArticleThumbnail(_ article: ArticleSummary) {
        let key = articleThumbnailKey(article)
        guard unavailableArticleThumbnails.contains(key) else { return }
        unavailableArticleThumbnails.remove(key)
    }

    var isSearchActive: Bool { scope == .search }
    var canLoadMoreSearchResults: Bool { Int64(articles.count) < searchTotal }
    func select(_ scope: BrowserScope) {
        if scope == .search { selectSearch(); return }
        self.scope = scope
        resetPresentation()
        if scope == .listeningList { reloadListeningList() }
        else { reloadVisibleArticles(acknowledgingPendingNewData: true) }
    }
    func setListeningListSort(_ sort: ListeningListSort) {
        guard listeningListSort != sort else { return }
        listeningListSort = sort
        reloadListeningList()
    }
    func setListeningListFeed(_ feedID: Int64?) {
        listeningListFeedID = feedID
        reloadListeningList()
    }
    func reloadListeningList() {
        guard let core else { return }
        let feedID = listeningListFeedID
        let sort = listeningListSort
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.responsiveResult(
                for: core,
                {
                    let feeds = try core.listeningListFeeds()
                    let validatedFeedID = ListeningListPresentation.validatedFeedID(feedID, feeds: feeds)
                    let items = try core.listeningList(feedId: validatedFeedID, sort: sort)
                    return (feeds, validatedFeedID, items)
                }
            ) else { return }
            guard let self, self.core === core else { return }
            switch result {
            case let .success((feeds, validatedFeedID, items)):
                self.listeningListFeeds = feeds
                self.listeningListFeedID = validatedFeedID
                self.listeningListItems = items
                self.selectionTotal = UInt64(items.count)
                self.errorMessage = nil
            case let .failure(error):
                self.errorMessage = NativeErrorPresentation.message(for: error)
            }
        }
    }

    func refreshListeningListIfVisible() {
        guard isListeningList else { return }
        reloadListeningList()
    }
    func selectSearch() {
        guard scope != .search else { return }
        scope = .search
        articles = []
        selectionTotal = 0
        searchQuery = ""
        searchTotal = 0
        hasSearched = false
        isSearching = false
        errorMessage = nil
        searchGeneration &+= 1
        resetPresentation()
    }
    func submitSearch() {
        let searchText = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        searchGeneration &+= 1
        let generation = searchGeneration
        guard !searchText.isEmpty else { clearSearch(); return }
        guard let core else { return }
        let pageSize = searchPageSize
        articles = []
        selectionTotal = 0
        searchTotal = 0
        hasSearched = true
        isSearching = true
        errorMessage = nil
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.blockingResult(
                for: core,
                { try core.searchArticles(request: SearchArticlesRequest(query: searchText, offset: 0, limit: pageSize)) }
            ) else { return }
            guard let self, self.core === core, self.scope == .search, self.searchGeneration == generation else { return }
            self.isSearching = false
            switch result {
            case let .success(page):
                self.articles = page.articles
                self.searchTotal = page.total
                self.loadArticleAudioActions(for: page.articles.map(\.id))
            case let .failure(error):
                self.errorMessage = NativeErrorPresentation.message(for: error)
            }
        }
    }

    func clearSearch() {
        searchGeneration &+= 1
        searchQuery = ""
        articles = []
        selectionTotal = 0
        searchTotal = 0
        hasSearched = false
        isSearching = false
        errorMessage = nil
    }
    func loadMoreSearchResults() {
        guard scope == .search, hasSearched, !isSearching, canLoadMoreSearchResults, let core else { return }
        let generation = searchGeneration
        let searchText = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let offset = Int64(articles.count)
        let pageSize = searchPageSize
        isSearching = true
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.blockingResult(
                for: core,
                { try core.searchArticles(request: SearchArticlesRequest(query: searchText, offset: offset, limit: pageSize)) }
            ) else { return }
            guard let self, self.core === core, self.scope == .search, self.searchGeneration == generation else { return }
            self.isSearching = false
            switch result {
            case let .success(page):
                let existing = Set(self.articles.map(\.id))
                let appended = page.articles.filter { !existing.contains($0.id) }
                self.articles.append(contentsOf: appended)
                self.searchTotal = page.total
                self.loadArticleAudioActions(for: appended.map(\.id))
            case let .failure(error):
                self.errorMessage = NativeErrorPresentation.message(for: error)
            }
        }
    }

    func route(to route: NavigationRoute) {
        startupRouteState.markExplicitRoute()
        switch route {
        case .all: select(.all)
        case .starred: select(.starred)
        case .category(let id): select(.category(id))
        case .feed(let id): select(.feed(id))
        }
    }
    func handleWidgetAction(_ action: WidgetAction) {
        guard core != nil else { pendingWidgetActions.append(action); return }
        startupRouteState.markExplicitRoute()
        switch action {
        case let .article(id):
            openArticle(id)
        case let .open(selection):
            openWidgetScope(selection)
        case .sync:
            sync(reason: .widget)
        }
    }
    func setUnreadOnly(_ enabled: Bool) { unreadOnly = enabled; resetPresentation(); reloadCounts(); reloadVisibleArticles(acknowledgingPendingNewData: true) }
    func setNewestFirst(_ enabled: Bool) { newestFirst = enabled; resetPresentation(); reloadVisibleArticles(acknowledgingPendingNewData: true) }
    func noteMeaningfulInteraction() { hasMeaningfullyInteracted = true }
    func resetPresentation() { hasMeaningfullyInteracted = false; newDataAvailable = false; listPresentationRevision &+= 1 }
    func setArticlePresentationMode(_ mode: ArticlePresentationMode) { guard mode != articlePresentationMode else { return }; articlePresentationMode = mode; UserDefaults.standard.set(mode.rawValue, forKey: "FluxNews.articlePresentationMode"); resetPresentation() }
    func applyNewData() { reloadVisibleArticles(resetPosition: true, acknowledgingPendingNewData: true) }
    func requestMediaTransferReconciliation() { onMediaTransferRequested?() }
    func sync(reason: SyncReason = .manual) {
        // Background, periodic and resume triggers must honor the persisted
        // preference even when called directly by a lifecycle observer.
        if reason == .periodic || reason == .resume || reason == .background {
            guard BackgroundRecoveryPolicy.shouldAttempt(
                configured: core != nil,
                backgroundEnabled: coreSettings?.backgroundSyncEnabled == true,
                networkAvailable: networkAvailability,
                syncInFlight: isLoading,
                lastAttempt: lastSyncAttempt,
                now: .now
            ) else {
                NativeLog.sync.debug("automatic sync suppressed (offline, disabled, active or throttled)")
                return
            }
        }
        guard let core, !isLoading else { return }
        isLoading = true
        lastSyncAttempt = .now
        if reason == .periodic { NativeLog.sync.notice("periodic sync triggered") }
        let coordinator = coreSessionExecutionCoordinator
        let cancellation = SyncCancellation()
        Task { [weak self, core, coordinator, cancellation] in
            guard let result = await coordinator.blockingCancellableResult(
                for: core,
                onCancel: { cancellation.cancel() },
                { try core.syncCancellable(reason: reason, cancellation: cancellation) }
            ) else {
                if let self, self.core === core { self.isLoading = false }
                return
            }
            guard let self, self.core === core else { return }
            self.isLoading = false
            switch result {
            case let .success(outcome):
                switch outcome {
                case let .completed(metadata):
                    NativeLog.sync.debug("sync completed; reconciling native media work")
            NativeLog.support("sync", "sync completed", level: .debug)
                    self.requestMediaTransferReconciliation()
                    await SystemNotificationManager.shared.deliver(metadata.systemNotificationCandidates, core: core, coordinator: coordinator)
                case .cancelled:
                    NativeLog.sync.debug("sync cancelled reason=\(String(describing: reason), privacy: .public)")
                }
            case let .failure(error):
                if cancellation.isCancelled() || error is CancellationError { return }
                NativeLog.sync.error("sync failed reason=\(String(describing: reason), privacy: .public) error=\(String(describing: error), privacy: .private)")
                self.errorMessage = NativeErrorPresentation.message(for: error)
            }
        }
    }

    func syncIfStale(reason: SyncReason = .periodic) {
        sync(reason: reason)
    }

    /// Called on the main actor by NWPathMonitor. The first callback only
    /// establishes connectivity state; a subsequent offline -> online change
    /// requests a throttled recovery sync.
    func networkAvailabilityChanged(isAvailable: Bool) {
        networkAvailability = isAvailable
        if networkRecoveryState.observe(isAvailable: isAvailable) {
            syncIfStale(reason: .resume)
        }
    }

    /// An explicit wake notification complements foreground resume; both
    /// converge on the same guarded single-flight path.
    func systemDidWake() {
        syncIfStale(reason: .resume)
    }
    func activatePeriodicSyncScheduling() {
        guard core != nil, coreSettings?.backgroundSyncEnabled == true, periodicSyncTimer == nil else { return }
        periodicSyncTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runPeriodicSync() }
        }
        NativeLog.sync.notice("periodic sync scheduled cadence_seconds=900")
    }
    func deactivatePeriodicSyncScheduling() {
        periodicSyncTimer?.invalidate()
        periodicSyncTimer = nil
    }
    func resume() {
        if coreSettings?.backgroundSyncEnabled == true { activatePeriodicSyncScheduling() }
        syncIfStale(reason: .resume)
    }
    private func runPeriodicSync() { syncIfStale(reason: .periodic) }
    func setDownloadNetworkPolicy(_ policy: DownloadNetworkPolicy) {
        updateCoreSettings({ try $0.setDownloadNetworkPolicy(policy: policy) }, afterSuccess: { [weak self] in
            self?.requestMediaTransferReconciliation()
        })
    }
    func setDownloadRetention(_ retention: DownloadRetention) {
        updateCoreSettings({ try $0.setDownloadRetention(retention: retention) }, afterSuccess: { [weak self] in
            self?.requestMediaTransferReconciliation()
        })
    }
    func setRetention(_ retention: ReadArticleRetention) { updateCoreSettings { try $0.setRetention(retention: retention) } }
    func setDeliveryMode(_ mode: DeliveryMode) { updateCoreSettings { try $0.setDeliveryMode(mode: mode) } }
    func setBackgroundSyncEnabled(_ enabled: Bool) {
        updateCoreSettings(
            { try $0.setBackgroundSyncEnabled(enabled: enabled) },
            afterSuccess: { [weak self] in
                if enabled { self?.activatePeriodicSyncScheduling() }
                else { self?.deactivatePeriodicSyncScheduling() }
            }
        )
    }
    func setDetailCharacterLimit(_ limit: UInt32) { updateCoreSettings { try $0.setDetailCharacterLimit(limit: limit) } }
    func setDeleteAfterPlayback(_ enabled: Bool) { updateCoreSettings { try $0.setDeleteAfterPlayback(enabled: enabled) } }
    func setAutoDownloadListeningList(_ enabled: Bool) { updateCoreSettings { try $0.setAutoDownloadListeningList(enabled: enabled) } }
    func setRemoveCompletedListeningList(_ enabled: Bool) { updateCoreSettings { try $0.setRemoveCompletedListeningList(enabled: enabled) } }
    func reloadSystemNotificationSettings() {
        guard let core else { return }
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.responsiveResult(
                for: core,
                { try core.feedSystemNotificationSettings() }
            ) else { return }
            guard let self, self.core === core else { return }
            switch result {
            case let .success(settings):
                self.systemNotificationSettings = settings
                self.systemNotificationSettingsError = nil
            case let .failure(error):
                self.systemNotificationSettingsError = NativeErrorPresentation.message(for: error)
            }
        }
    }

    func setSystemNotificationsEnabled(
        feedID: Int64,
        enabled: Bool,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard let core, !updatingSystemNotificationFeedIDs.contains(feedID) else { return }
        updatingSystemNotificationFeedIDs.insert(feedID)
        systemNotificationSettingsError = nil
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let self else { return }
            do {
                if enabled { try await SystemNotificationManager.shared.ensureAuthorization() }
                guard let result = await coordinator.responsiveResult(
                    for: core,
                    {
                        try core.setFeedSystemNotificationsEnabled(feedId: feedID, enabled: enabled)
                        return try core.feedSystemNotificationSettings()
                    }
                ) else {
                    self.updatingSystemNotificationFeedIDs.remove(feedID)
                    return
                }
                guard self.core === core else { return }
                switch result {
                case let .success(settings):
                    self.updatingSystemNotificationFeedIDs.remove(feedID)
                    self.systemNotificationSettings = settings
                    completion?(.success(()))
                case let .failure(error):
                    self.updatingSystemNotificationFeedIDs.remove(feedID)
                    self.systemNotificationSettingsError = NativeErrorPresentation.message(for: error)
                    completion?(.failure(error))
                }
            } catch {
                self.updatingSystemNotificationFeedIDs.remove(feedID)
                self.systemNotificationSettingsError = NativeErrorPresentation.message(for: error)
                completion?(.failure(error))
            }
        }
    }

    func selectNotificationFeed(_ feedID: Int64) {
        startupRouteState.markExplicitRoute()
        select(.feed(feedID))
    }
    private func updateCoreSettings(
        _ update: @escaping @Sendable (Flux) throws -> Void,
        afterSuccess: @escaping () -> Void = {}
    ) {
        guard let core else { return }
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.responsiveResult(
                for: core,
                {
                    try update(core)
                    return try core.coreSettings()
                }
            ) else { return }
            guard let self, self.core === core else { return }
            switch result {
            case let .success(settings):
                self.coreSettings = settings
                afterSuccess()
            case let .failure(error):
                self.errorMessage = NativeErrorPresentation.message(for: error)
            }
        }
    }

    func handle(event: CoreEvent, generation: UInt64) {
        guard generation == eventSessionGeneration, core != nil else { return }
        switch event {
        case .articleReadStateChanged, .articleStarredStateChanged:
            refreshWidgetSnapshot()
            return
        case let .syncDidComplete(metadata):
            refreshWidgetSnapshot()
            handleSyncCompleted(metadata)
        default:
            return
        }
    }
    private func handleSyncCompleted(_ metadata: SyncCompleted) {
        refreshListeningListIfVisible()
        if metadata.reason == .background || metadata.reason == .periodic {
            pendingNewData.accumulate(metadata.newArticlesByFeed.map { (feedID: $0.feedId, count: $0.count) })
            publishPendingNewData()
        }
        if metadata.navigationChanged { reloadNavigationAndCounts() }
        else if metadata.reason == .manual { reloadCounts() }
        else if metadata.dataChanged { reloadCounts() }
        if metadata.reason == .periodic { NativeLog.sync.notice("periodic sync completed") }
        let action: SnapshotRefreshPolicy.Action = if metadata.reason == .background || metadata.reason == .periodic {
            metadata.dataChanged ? .signalNewData : .preserve
        } else {
            SnapshotRefreshPolicy.action(manual: metadata.reason == .manual, dataChanged: metadata.dataChanged, hasMeaningfullyInteracted: hasMeaningfullyInteracted)
        }
        switch action {
        case .replace:
            reloadVisibleArticles(resetPosition: true, acknowledgingPendingNewData: metadata.reason == .manual)
        case .signalNewData:
            newDataAvailable = true
        case .preserve:
            break
        }
    }
    private func acknowledgePendingNewDataForCurrentScope() {
        switch scope {
        case .all:
            pendingNewData.adoptAll()
        case let .category(categoryID):
            pendingNewData.adoptFeeds(in: Set(catalog.feeds.filter { $0.categoryId == categoryID }.map(\.id)))
        case let .feed(feedID):
            pendingNewData.adoptFeed(feedID)
        case .starred, .search, .listeningList:
            return
        }
        publishPendingNewData()
    }
    private func publishPendingNewData() {
        pendingNewByFeed = pendingNewData.byFeed
        hasPendingNewData = pendingNewData.hasPending
    }
    func setRead(_ article: ArticleSummary, _ read: Bool) {
        guard let core else { return }
        let coordinator = coreSessionExecutionCoordinator
        if scope == .search {
            Task { [weak self, core, coordinator] in
                guard let result = await coordinator.blockingResult(
                    for: core,
                    { try core.searchSetReadState(articleId: article.id, read: read) }
                ) else { return }
                guard let self, self.core === core else { return }
                switch result {
                case let .success(disposition):
                    self.updateVisibleRead([article.id], read: read)
                    if case .localFirst = disposition { self.reloadCounts() }
                case let .failure(error):
                    self.errorMessage = NativeErrorPresentation.message(for: error)
                }
            }
            return
        }
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.responsiveResult(
                for: core,
                { try core.setReadState(articleId: article.id, read: read) }
            ) else { return }
            guard let self, self.core === core else { return }
            switch result {
            case .success:
                self.updateVisibleRead([article.id], read: read)
                self.reloadSelectionTotal()
                self.reloadCounts()
            case let .failure(error):
                self.errorMessage = NativeErrorPresentation.message(for: error)
            }
        }
    }

    func setStarred(_ article: ArticleSummary, _ starred: Bool, completion: ((Bool) -> Void)? = nil) {
        guard let core else { completion?(false); return }
        let coordinator = coreSessionExecutionCoordinator
        if scope == .search {
            Task { [weak self, core, coordinator] in
                guard let result = await coordinator.blockingResult(
                    for: core,
                    { try core.searchSetStarredState(articleId: article.id, starred: starred) }
                ) else { completion?(false); return }
                guard let self, self.core === core else { completion?(false); return }
                switch result {
                case let .success(disposition):
                    self.updateVisible([article.id]) { $0.isStarred = starred }
                    if case .localFirst = disposition { self.reloadCounts() }
                    completion?(true)
                case let .failure(error):
                    self.errorMessage = NativeErrorPresentation.message(for: error)
                    completion?(false)
                }
            }
            return
        }
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.responsiveResult(
                for: core,
                { try core.setStarredState(articleId: article.id, starred: starred) }
            ) else { completion?(false); return }
            guard let self, self.core === core else { completion?(false); return }
            switch result {
            case .success:
                self.updateVisible([article.id]) { $0.isStarred = starred }
                self.reloadSelectionTotal()
                self.reloadCounts()
                completion?(true)
            case let .failure(error):
                self.errorMessage = NativeErrorPresentation.message(for: error)
                completion?(false)
            }
        }
    }

    func loadPlayerArtworkSource(enclosureID: Int64, completion: @escaping (MediaArtworkSource?) -> Void) {
        guard let core else { completion(nil); return }
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            let result = await coordinator.responsiveResult(
                for: core, { try core.mediaArtworkSource(enclosureId: enclosureID) }
            )
            guard let self, self.core === core else { completion(nil); return }
            let source = result.flatMap { try? $0.get() } ?? nil
            completion(source)
            // Older Listening List items were added before macOS supported
            // Range probing. Probe on demand, once per enclosure/session, only
            // when neither embedded nor remote artwork is currently known.
            if source == nil { self.enqueueMediaArtworkProbes([enclosureID]) }
        }
    }

    private func enqueueMediaArtworkProbes(_ enclosureIDs: [Int64]) {
        guard core != nil else { return }
        for id in enclosureIDs where id > 0 {
            if artworkProbeRequestedIDs.insert(id).inserted {
                artworkProbeQueue.append(id)
            }
        }
        startNextMediaArtworkProbe()
    }

    private func startNextMediaArtworkProbe() {
        guard !artworkProbeInFlight, !artworkProbeQueue.isEmpty, let core else { return }
        let enclosureID = artworkProbeQueue.removeFirst()
        artworkProbeInFlight = true
        let coordinator = coreSessionExecutionCoordinator
        // Range probing includes network IO: never execute this on MainActor,
        // and admit at most one probe at a time to protect UI/Core responsiveness.
        Task { [weak self, core, coordinator] in
            let result = await coordinator.blockingResult(
                for: core, { try core.probeMediaArtwork(enclosureId: enclosureID) }
            )
            guard let self, self.core === core else { return }
            self.artworkProbeInFlight = false
            if case .success(true) = result {
                self.artworkProbeRevisions[enclosureID, default: 0] &+= 1
            }
            self.startNextMediaArtworkProbe()
        }
    }

    private func requestMediaArtworkProbe(articleID: Int64) {
        guard let core else { return }
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.responsiveResult(
                for: core,
                { try core.articleEnclosures(articleId: articleID)
                    .filter { $0.mediaKind == .audio }
                    .map(\.id) }
            ) else { return }
            guard let self, self.core === core else { return }
            if case let .success(ids) = result {
                self.enqueueMediaArtworkProbes(ids)
            }
        }
    }

    /// Preview chapter metadata without preparing or playing an audio item.
    func loadPlayerPreviewChapters(enclosureID: Int64, completion: @escaping ([MediaChapter]) -> Void) {
        guard let core else { completion([]); return }
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            let result = await coordinator.responsiveResult(
                for: core, { try core.mediaChapters(enclosureId: enclosureID) }
            )
            guard let self, self.core === core else { completion([]); return }
            completion((try? result?.get()) ?? [])
        }
    }

    /// Resolve Listening List articles independently of the currently visible
    /// timeline (which can be filtered to a different feed or scope).
    func openOriginalArticle(articleID: Int64) {
        if let article = articles.first(where: { $0.id == articleID }) {
            openOriginal(article)
            return
        }
        guard let core else { return }
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.responsiveResult(
                for: core, { try core.articleSummary(articleId: articleID) }
            ) else { return }
            guard let self, self.core === core else { return }
            switch result {
            case let .success(article):
                if let article { self.openOriginal(article) }
                else { self.errorMessage = String(localized: "Article unavailable") }
            case let .failure(error):
                self.errorMessage = NativeErrorPresentation.message(for: error)
            }
        }
    }

    /// Player show notes must not use the global Reader request generation:
    /// opening a separate Reader must never silently discard this callback.
    func loadPlayerShowNotes(articleID: Int64, completion: @escaping (Result<ReaderDocument, Error>) -> Void) {
        guard let core else {
            completion(.failure(NSError(domain: "FluxNews", code: 1,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Flux is not configured")])))
            return
        }
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            let result = await coordinator.responsiveResult(
                for: core, { try core.readerDocument(articleId: articleID) }
            )
            guard let self, self.core === core else {
                completion(.failure(NSError(domain: "FluxNews", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "Session no longer available")])))
                return
            }
            if let result {
                completion(result)
            } else {
                completion(.failure(NSError(domain: "FluxNews", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "Show Notes unavailable")])))
            }
        }
    }

    func loadReaderDocument(_ article: ArticleSummary, completion: @escaping (Result<ReaderDocument, Error>) -> Void) {
        loadReaderDocument(articleID: article.id, forSearch: ReaderDocumentSource.forScope(scope) == .search, completion: completion)
    }
    func loadReaderDocument(articleID: Int64, completion: @escaping (Result<ReaderDocument, Error>) -> Void) {
        loadReaderDocument(articleID: articleID, forSearch: false, completion: completion)
    }
    private func loadReaderDocument(articleID: Int64, forSearch: Bool, completion: @escaping (Result<ReaderDocument, Error>) -> Void) {
        guard let core else {
            completion(.failure(NSError(domain: "FluxNews", code: 1, userInfo: [NSLocalizedDescriptionKey: "Flux is not configured"])))
            return
        }
        readerDocumentRequest &+= 1
        let request = readerDocumentRequest
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.blockingResult(
                for: core,
                {
                    if forSearch { return try core.readerDocumentForSearch(articleId: articleID) }
                    return try core.readerDocument(articleId: articleID)
                }
            ) else { return }
            guard let self, self.core === core, self.readerDocumentRequest == request else { return }
            completion(result)
        }
    }

    func loadArticleAudioActions(for articleID: Int64) {
        loadArticleAudioActions(for: [articleID], selectedArticleID: articleID)
    }

    func loadArticleAudioActions(for articleIDs: [Int64], selectedArticleID: Int64? = nil) {
        articleAudioRequestGeneration &+= 1
        let generation = articleAudioRequestGeneration
        articleAudioActionState = nil
        guard let core else { return }
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.responsiveResult(
                for: core,
                {
                    try core.articleAudioActionStates(articleIds: articleIDs).reduce(into: [Int64: ArticleAudioActionState]()) { result, state in
                        result[state.articleId] = ArticleAudioActionState(
                            articleID: state.articleId,
                            enclosures: ArticleAudioActions.audioEnclosures(state.enclosures),
                            isInListeningList: state.isInListeningList,
                            downloads: Dictionary(uniqueKeysWithValues: state.downloads.map { ($0.enclosureId, $0) })
                        )
                    }
                }
            ) else { return }
            guard let self, self.core === core, self.articleAudioRequestGeneration == generation else { return }
            switch result {
            case let .success(states):
                self.articleAudioActionStates.merge(states) { _, new in new }
                if let selectedArticleID { self.articleAudioActionState = states[selectedArticleID] }
            case let .failure(error):
                self.errorMessage = NativeErrorPresentation.message(for: error)
            }
        }
    }

    func refreshArticleAudioActions() {
        guard let articleID = articleAudioActionState?.articleID else { return }
        loadArticleAudioActions(for: articleID)
    }

    func selectArticleAudioActions(for articleID: Int64?) {
        articleAudioActionState = articleID.flatMap { articleAudioActionStates[$0] }
    }

    private func runResponsiveMutation(
        _ operation: @escaping @Sendable (Flux) throws -> Void,
        onSuccess: @escaping () -> Void
    ) {
        guard let core else { return }
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.responsiveResult(
                for: core,
                { try operation(core) }
            ) else { return }
            guard let self, self.core === core else { return }
            switch result {
            case .success: onSuccess()
            case let .failure(error): self.errorMessage = NativeErrorPresentation.message(for: error)
            }
        }
    }

    func addToListeningList(articleID: Int64) {
        let generation = articleAudioRequestGeneration
        runResponsiveMutation(
            { try $0.addToListeningList(articleId: articleID) },
            onSuccess: { [weak self] in
                guard let self else { return }
                self.showActionConfirmation(String(localized: "Added to Listening List"))
                self.onMediaTransferRequested?()
                self.refreshListeningListIfVisible()
                self.requestMediaArtworkProbe(articleID: articleID)
                guard self.articleAudioRequestGeneration == generation else { return }
                self.loadArticleAudioActions(for: articleID)
            }
        )
    }

    func loadDownloadedMediaSummary(completion: @escaping (Result<DownloadedMediaSummary, Error>) -> Void) {
        guard let core else {
            completion(.failure(NSError(domain: "FluxNews", code: 1, userInfo: [NSLocalizedDescriptionKey: "Flux is not configured"])))
            return
        }
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.responsiveResult(
                for: core,
                { try core.downloadedMediaSummary() }
            ) else { return }
            guard let self, self.core === core else { return }
            completion(result)
        }
    }

    func requestAllDownloadDeletions(completion: @escaping (Result<UInt64, Error>) -> Void) {
        guard let core else {
            completion(.failure(NSError(domain: "FluxNews", code: 1, userInfo: [NSLocalizedDescriptionKey: "Flux is not configured"])))
            return
        }
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.responsiveResult(
                for: core,
                { try core.requestAllDownloadDeletions() }
            ) else { return }
            guard let self, self.core === core else { return }
            if case .success = result {
                self.onMediaTransferRequested?()
                self.refreshListeningListIfVisible()
                self.refreshArticleAudioActions()
            }
            completion(result)
        }
    }

    func cancelDownload(articleID: Int64, enclosureID: Int64) {
        let refreshArticleActions = articleAudioActionState?.articleID == articleID
        runResponsiveMutation(
            { try $0.cancelDownload(enclosureId: enclosureID) },
            onSuccess: { [weak self] in
                guard let self else { return }
                self.onCancelMediaTransferRequested?(enclosureID)
                self.onMediaTransferRequested?()
                self.refreshListeningListIfVisible()
                if refreshArticleActions { self.refreshArticleAudioActions() }
                self.showActionConfirmation(String(localized: "Download cancelled"))
            }
        )
    }

    func requestManualDownload(articleID: Int64, enclosureID: Int64) {
        let refreshArticleActions = articleAudioActionState?.articleID == articleID
        let generation = articleAudioRequestGeneration
        runResponsiveMutation(
            { try $0.requestDownload(enclosureId: enclosureID, origin: .manual) },
            onSuccess: { [weak self] in
                guard let self else { return }
                self.showActionConfirmation(String(localized: "Download requested"))
                self.onMediaTransferRequested?()
                self.refreshListeningListIfVisible()
                if refreshArticleActions, self.articleAudioRequestGeneration == generation {
                    self.loadArticleAudioActions(for: articleID)
                }
            }
        )
    }

    func removeFromListeningList(articleID: Int64) {
        let refreshArticleActions = articleAudioActionState?.articleID == articleID
        runResponsiveMutation(
            { try $0.removeFromListeningList(articleId: articleID) },
            onSuccess: { [weak self] in
                guard let self else { return }
                self.showActionConfirmation(String(localized: "Removed from Listening List"))
                self.onMediaTransferRequested?()
                self.refreshListeningListIfVisible()
                if refreshArticleActions { self.refreshArticleAudioActions() }
            }
        )
    }

    func deleteDownload(articleID: Int64, enclosureID: Int64) {
        let refreshArticleActions = articleAudioActionState?.articleID == articleID
        runResponsiveMutation(
            { try $0.requestDownloadDeletion(enclosureId: enclosureID) },
            onSuccess: { [weak self] in
                guard let self else { return }
                // A paused/stopped AVPlayer can still hold the file descriptor.
                // Release the explicitly deleted media before attempting removal.
                self.onReleaseMediaForDownloadDeletion?(enclosureID)
                self.showActionConfirmation(String(localized: "Download deletion requested"))
                self.onMediaTransferRequested?()
                self.refreshListeningListIfVisible()
                if refreshArticleActions { self.refreshArticleAudioActions() }
            }
        )
    }

    func saveToService(_ article: ArticleSummary) {
        guard let core else { return }
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.blockingResult(
                for: core,
                { try core.saveToService(articleId: article.id) }
            ) else { return }
            guard let self, self.core === core else { return }
            switch result {
            case let .success(value):
                switch value {
                case .saved:
                    self.showActionConfirmation(String(localized: "Saved to third-party service"))
                case .noIntegrationConfigured:
                    self.showActionConfirmation(String(localized: "No third-party integration is configured in Miniflux"))
                }
            case let .failure(error):
                self.errorMessage = NativeErrorPresentation.message(for: error)
            }
        }
    }

    func discoverSubscriptions(_ request: DiscoverSubscriptionsRequest, completion: @escaping (Result<[DiscoveredSubscription], Error>) -> Void) {
        guard let core else {
            completion(.failure(NSError(domain: "FluxNews", code: 1, userInfo: [NSLocalizedDescriptionKey: "Flux is not configured"])))
            return
        }
        let coordinator = coreSessionExecutionCoordinator
        Task { [core, coordinator] in
            guard let result = await coordinator.blockingResult(
                for: core,
                { try core.discoverSubscriptions(request: request) }
            ) else { return }
            completion(result)
        }
    }

    func createFeed(_ request: CreateFeedRequest, completion: @escaping (Result<CreateFeedResult, Error>) -> Void) {
        guard let core else {
            completion(.failure(NSError(domain: "FluxNews", code: 1, userInfo: [NSLocalizedDescriptionKey: "Flux is not configured"])))
            return
        }
        let coordinator = coreSessionExecutionCoordinator
        Task { [core, coordinator] in
            guard let result = await coordinator.blockingResult(
                for: core,
                { try core.createFeed(request: request) }
            ) else { return }
            completion(result)
        }
    }

    func createCategory(_ title: String, completion: @escaping (Result<CreateCategoryResult, Error>) -> Void) {
        guard let core else {
            completion(.failure(NSError(domain: "FluxNews", code: 1, userInfo: [NSLocalizedDescriptionKey: "Flux is not configured"])))
            return
        }
        let coordinator = coreSessionExecutionCoordinator
        Task { [core, coordinator] in
            guard let result = await coordinator.blockingResult(
                for: core,
                { try core.createCategory(title: title) }
            ) else { return }
            completion(result)
        }
    }

    func beginScrolloverUndoBatch() {
        scrolloverUndoBatch.beginScroll()
        scrolloverRemovedArticles = [:]
        scrolloverOriginalOrder = Dictionary(uniqueKeysWithValues: articles.enumerated().map { ($0.element.id, $0.offset) })
    }
    func finishScrolloverUndoBatch() {
        guard scrolloverCountsPending else { return }
        scrolloverCountsPending = false
        reloadScrolloverCounts()
    }
    func flushScrollover(_ ids: [Int64]) {
        guard let core, !ids.isEmpty else { return }
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            let started = ContinuousClock.now
            guard let result = await coordinator.responsiveResult(
                for: core,
                { try core.setReadStateBulk(articleIds: ids, read: true) }
            ) else { return }
            guard let self, self.core === core else { return }
            switch result {
            case .success:
                let elapsed = started.duration(to: .now)
                if elapsed >= .milliseconds(8) {
                    let components = elapsed.components
                    let milliseconds = components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000
                    NativeLog.scrollover.debug("scrollover mutation elapsed_ms=\(milliseconds, privacy: .public) ids=\(ids.count, privacy: .public)")
                }
                self.lastScrolloverBatch = self.scrolloverUndoBatch.append(ids)
                self.updateVisibleRead(ids, read: true, retainingForScrolloverUndo: true)
                self.scrolloverCountsPending = true
                self.showScrolloverUndo()
            case let .failure(error):
                self.errorMessage = NativeErrorPresentation.message(for: error)
            }
        }
    }

    func undoScrollover() {
        guard let core, !lastScrolloverBatch.isEmpty else { return }
        let ids = lastScrolloverBatch
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.responsiveResult(
                for: core,
                { try core.setReadStateBulk(articleIds: ids, read: false) }
            ) else { return }
            guard let self, self.core === core else { return }
            switch result {
            case .success:
                self.updateVisibleRead(ids, read: false)
                self.restoreScrolloverRemovedArticles()
                self.scrolloverUndoBatch.clear()
                self.lastScrolloverBatch = []
                self.scrolloverUndoVisible = false
                self.undoExpiry?.cancel()
                self.reloadSelectionTotal()
                self.reloadCounts()
            case let .failure(error):
                self.errorMessage = NativeErrorPresentation.message(for: error)
            }
        }
    }

    func setScrolloverEnabled(_ enabled: Bool) { markReadOnScrolloverEnabled = enabled; UserDefaults.standard.set(enabled, forKey: "FluxNews.markReadOnScrollover") }
    func setStartupScope(_ preference: StartupScopePreference) {
        startupScope = preference
        if preference == .category, startupCategoryID == nil { startupCategoryID = catalog.categories.first?.id }
        if preference == .feed, startupFeedID == nil { startupFeedID = catalog.feeds.first?.id }
        UserDefaults.standard.set(preference.rawValue, forKey: "FluxNews.startupScope")
        persistStartupTargets()
    }
    func setStartupCategoryID(_ id: Int64?) { startupCategoryID = id; persistStartupTargets() }
    func setStartupFeedID(_ id: Int64?) { startupFeedID = id; persistStartupTargets() }
    func setHideEmptyNavigationEntries(_ enabled: Bool) { hideEmptyNavigationEntries = enabled; UserDefaults.standard.set(enabled, forKey: "FluxNews.hideEmptyNavigationEntries") }
    func setRemoveArticlesWhenMarkedRead(_ enabled: Bool) { removeArticlesWhenMarkedRead = enabled; UserDefaults.standard.set(enabled, forKey: "FluxNews.removeArticlesWhenMarkedRead") }
    func setSyncOnStartEnabled(_ enabled: Bool) { syncOnStartEnabled = enabled; UserDefaults.standard.set(enabled, forKey: "FluxNews.syncOnStart") }
    func setArticlePreviewLines(_ lines: ArticlePreviewLines) { articlePreviewLines = lines; UserDefaults.standard.set(lines.rawValue, forKey: "FluxNews.articlePreviewLines") }
    func setShowArticleCount(_ enabled: Bool) { showArticleCount = enabled; UserDefaults.standard.set(enabled, forKey: "FluxNews.showArticleCount") }
    func setShowRelativePublicationTime(_ enabled: Bool) { showRelativePublicationTime = enabled; UserDefaults.standard.set(enabled, forKey: "FluxNews.showRelativePublicationTime") }
    func setClickOnNews(_ preference: ClickOnNews) { clickOnNews = preference; UserDefaults.standard.set(preference.rawValue, forKey: "FluxNews.clickOnNews") }
    func setGlobalShortcut(_ shortcut: GlobalShortcutChoice) { guard shortcut != globalShortcut else { return }; globalShortcut = shortcut; shortcut.store() }
    func exportConfigurationBackup(password: String) async throws -> Data {
        guard let core else { throw ConfigurationBackupPresentationError.noConfiguredAccount }
        guard let credentials = try CredentialStore.load() else {
            throw ConfigurationBackupPresentationError.noConfiguredAccount
        }
        let coordinator = coreSessionExecutionCoordinator
        guard let snapshotResult = await coordinator.responsiveResult(
            for: core,
            { try core.configurationSnapshot() }
        ) else {
            throw CancellationError()
        }
        let snapshot: ConfigurationSnapshot
        switch snapshotResult {
        case let .success(value):
            snapshot = value
        case let .failure(error):
            throw error
        }

        let payload = try JSONEncoder().encode(
            nativeBackupSettings(customHeaders: credentials.resolvedCustomHeaders)
        )
        let input = ConfigBackupInput(
            platform: .macos,
            account: BackupAccount(
                installationBase: snapshot.installationBase,
                apiKey: credentials.apiKey
            ),
            coreSettings: snapshot.coreSettings,
            feedPreferences: snapshot.feedPreferences,
            platformSettings: PlatformSettingsPayload(
                schemaVersion: MacOSBackupSettingsV1.version,
                dataJson: String(decoding: payload, as: UTF8.self)
            )
        )
        return try Data(
            await AppleCoreExecution.shared.blocking {
                try exportConfigBackup(input: input, password: password)
            }
        )
    }

    func importConfigurationBackup(bytes: Data, password: String) async throws -> BackupImportOutcome {
        let restored = try await AppleCoreExecution.shared.blocking {
            try parseConfigBackup(bytes: bytes, password: password, expectedPlatform: .macos)
        }
        guard restored.platformSettings.schemaVersion == MacOSBackupSettingsV1.version else {
            throw ConfigurationBackupPresentationError.unsupportedPlatformSettings
        }
        let native = try JSONDecoder().decode(
            MacOSBackupSettingsV1.self,
            from: Data(restored.platformSettings.dataJson.utf8)
        )
        guard native.version == MacOSBackupSettingsV1.version else {
            throw ConfigurationBackupPresentationError.unsupportedPlatformSettings
        }
        guard let core else { throw ConfigurationBackupPresentationError.noConfiguredAccount }

        let coordinator = coreSessionExecutionCoordinator
        guard let previousSnapshotResult = await coordinator.responsiveResult(
            for: core,
            { try core.configurationSnapshot() }
        ) else {
            throw CancellationError()
        }
        let previousSnapshot: ConfigurationSnapshot
        switch previousSnapshotResult {
        case let .success(value):
            previousSnapshot = value
        case let .failure(error):
            throw error
        }

        let previousCredentials = try CredentialStore.load()
        let previousNative = nativeBackupSettings(
            customHeaders: previousCredentials?.resolvedCustomHeaders ?? []
        )

        await coordinator.quiesce()
        guard let replaceResult = await coordinator.exclusiveBlockingResult(
            for: core,
            {
                try core.replaceConfiguration(
                    installationBase: restored.account.installationBase,
                    coreSettings: restored.coreSettings,
                    feedPreferences: restored.feedPreferences
                )
            }
        ) else {
            coordinator.resume(core)
            throw CancellationError()
        }

        if case let .failure(error) = replaceResult {
            coordinator.resume(core)
            throw error
        }

        do {
            invalidateWidgetSnapshot()
            let customHeaders = native.customHeaders ?? []
            try CredentialStore.save(
                MinifluxCredentials(
                    server: restored.account.installationBase,
                    apiKey: restored.account.apiKey,
                    customHeaders: customHeaders
                )
            )
            try applyNativeBackupSettings(native)
            guard await configure(
                server: restored.account.installationBase,
                apiKey: restored.account.apiKey,
                customHeaders: customHeaders,
                refreshVersion: false,
                startSync: false
            ) else {
                throw ConfigurationBackupPresentationError.coreInitialization
            }
        } catch {
            // If configure activated a replacement Core, return admission to the
            // original Core before restoring its previous durable configuration.
            if self.core !== core {
                await coordinator.quiesce()
                coordinator.deactivate()
                coordinator.activate(core)
            }
            if !coordinator.isQuiescing {
                await coordinator.quiesce()
            }
            _ = await coordinator.exclusiveBlockingResult(
                for: core,
                {
                    try core.replaceConfiguration(
                        installationBase: previousSnapshot.installationBase,
                        coreSettings: previousSnapshot.coreSettings,
                        feedPreferences: previousSnapshot.feedPreferences
                    )
                }
            )
            coordinator.resume(core)
            self.core = core
            try? restoreCredentials(previousCredentials)
            try? applyNativeBackupSettings(previousNative)
            throw error
        }

        invalidateLocalPresentation()
        return await syncAfterImport()
    }

    func rebuildLocalState() {
        guard let core, !isLoading else { return }
        invalidateWidgetSnapshot()
        isLoading = true
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            await coordinator.quiesce()
            guard let result = await coordinator.exclusiveBlockingResult(
                for: core,
                { try core.rebuildLocalState() }
            ) else {
                coordinator.resume(core)
                if let self, self.core === core { self.isLoading = false }
                return
            }
            coordinator.resume(core)
            guard let self, self.core === core else { return }
            self.invalidateLocalPresentation()
            self.isLoading = false
            switch result {
            case .success:
                self.showActionConfirmation(String(localized: "Local state rebuilt"))
            case .failure:
                self.errorMessage = String(
                    localized: "Local state was cleared, but synchronization could not be completed."
                )
            }
        }
    }

    func resetFluxNews() {
        guard let core else { return }
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            await coordinator.quiesce()
            guard let result = await coordinator.exclusiveBlockingResult(
                for: core,
                { try core.resetCoreState() }
            ) else {
                coordinator.resume(core)
                return
            }
            guard let self else { return }
            switch result {
            case .success:
                coordinator.deactivate()
                do {
                    try CredentialStore.remove()
                    try CredentialStore.setLaunchAtLogin(false)
                    self.resetNativeSettings()
                    self.endEventSubscription()
                    self.core = nil
                    self.configuredServer = nil
                    self.minifluxVersion = nil
                    self.coreSettings = nil
                    self.isLoading = false
                    self.lastSyncAttempt = nil
                    self.deactivatePeriodicSyncScheduling()
                    self.invalidateWidgetSnapshot()
                    self.invalidateLocalPresentation()
                    self.showActionConfirmation(String(localized: "FluxNews was reset"))
                    self.settingsVisible = true
                } catch {
                    self.errorMessage = String(localized: "FluxNews could not be fully reset.")
                }
            case .failure:
                coordinator.resume(core)
                self.errorMessage = String(localized: "FluxNews could not be fully reset.")
            }
        }
    }

    var onInvalidateContent: (() -> Void)?

    private func syncAfterImport() async -> BackupImportOutcome {
        guard let core else { return .synchronizationFailed }
        isLoading = true
        let coordinator = coreSessionExecutionCoordinator
        guard let result = await coordinator.blockingResult(
            for: core,
            { try core.sync(reason: .manual) }
        ) else {
            isLoading = false
            return .synchronizationFailed
        }
        isLoading = false
        switch result {
        case .success:
            return .synchronized
        case .failure:
            return .synchronizationFailed
        }
    }

    private func invalidateLocalPresentation() {
        scopeReadActionGeneration &+= 1
        isMarkingScopeRead = false
        articles = []
        catalog = NavigationCatalog(categories: [], feeds: [])
        unreadTotal = 0
        starredTotal = 0
        selectionTotal = 0
        categorySidebarCounts = [:]
        feedSidebarCounts = [:]
        feedIcons = [:]
        feedIconRequests = FeedIconRequestState()
        articleThumbnails = [:]
        articleThumbnailRequests = ArticleThumbnailRequestState()
        unavailableArticleThumbnails = []
        pendingNewData = PendingNewData()
        publishPendingNewData()
        clearSearch()
        onInvalidateContent?()
        resetPresentation()
        snapshotResetRevision &+= 1
    }
    private func refreshWidgetSnapshot() {
        guard let core else {
            WidgetSnapshotDiagnostics.logger.error("Widget snapshot refresh skipped because Flux core is unavailable")
            return
        }
        let coordinator = coreSessionExecutionCoordinator
        Task { [core, coordinator] in
            let store: WidgetSnapshotStore
            do {
                store = try WidgetSnapshotStore(diagnostics: WidgetSnapshotDiagnostics.logger)
            } catch {
                WidgetSnapshotDiagnostics.logger.error("Widget snapshot refresh could not resolve App Group container error=\(error.localizedDescription, privacy: .private)")
                return
            }
            guard let result = await coordinator.responsiveResult(
                for: core,
                { try WidgetSnapshotWriter.refresh(core: core, store: store) }
            ) else { return }
            switch result {
            case .success:
                WidgetSnapshotDiagnostics.logger.notice("Widget snapshot refresh succeeded path=\(store.snapshotPath, privacy: .private)")
                WidgetTimelineReloader.reloadAll()
            case let .failure(error):
                WidgetSnapshotDiagnostics.logger.error("Widget snapshot refresh failed error=\(error.localizedDescription, privacy: .private)")
            }
        }
    }
    private func invalidateWidgetSnapshot() {
        do {
            let store = try WidgetSnapshotStore(diagnostics: WidgetSnapshotDiagnostics.logger)
            try store.invalidate()
            WidgetSnapshotDiagnostics.logger.notice("Widget snapshot invalidated path=\(store.snapshotPath, privacy: .private)")
            WidgetTimelineReloader.reloadAll()
        } catch {
            WidgetSnapshotDiagnostics.logger.error("Widget snapshot invalidation failed error=\(error.localizedDescription, privacy: .private)")
        }
    }
    private func nativeBackupSettings(customHeaders: [CustomHTTPHeader] = []) -> MacOSBackupSettingsV1 {
        MacOSBackupSettingsV1(
            version: MacOSBackupSettingsV1.version,
            markReadOnScrollover: markReadOnScrolloverEnabled,
            syncOnStart: syncOnStartEnabled,
            articlePresentationMode: articlePresentationMode.rawValue,
            previewLines: articlePreviewLines.rawValue,
            showArticleCount: showArticleCount,
            showRelativePublicationTime: showRelativePublicationTime,
            clickOnNews: clickOnNews.rawValue,
            globalShortcut: globalShortcut.rawValue,
            launchAtLogin: CredentialStore.launchAtLoginEnabled,
            startupScope: startupScope.rawValue,
            startupCategoryID: startupCategoryID,
            startupFeedID: startupFeedID,
            hideEmptyNavigationEntries: hideEmptyNavigationEntries,
            removeArticlesWhenMarkedRead: removeArticlesWhenMarkedRead,
            customHeaders: customHeaders
        )
    }
    private func applyNativeBackupSettings(_ settings: MacOSBackupSettingsV1) throws {
        try CredentialStore.setLaunchAtLogin(settings.launchAtLogin)
        setScrolloverEnabled(settings.markReadOnScrollover)
        setSyncOnStartEnabled(settings.syncOnStart)
        setArticlePresentationMode(ArticlePresentationMode(rawValue: settings.articlePresentationMode) ?? .visual)
        setArticlePreviewLines(ArticlePreviewLines(rawValue: settings.previewLines) ?? .standard)
        setShowArticleCount(settings.showArticleCount ?? true)
        setShowRelativePublicationTime(settings.showRelativePublicationTime ?? false)
        setClickOnNews(ClickOnNews(rawValue: settings.clickOnNews) ?? .openLink)
        setGlobalShortcut(GlobalShortcutChoice(rawValue: settings.globalShortcut) ?? .optionCommandF)
        setStartupScope(StartupScopePreference(rawValue: settings.startupScope ?? "") ?? .allNews)
        setStartupCategoryID(settings.startupCategoryID)
        setStartupFeedID(settings.startupFeedID)
        setHideEmptyNavigationEntries(settings.hideEmptyNavigationEntries ?? false)
        setRemoveArticlesWhenMarkedRead(settings.removeArticlesWhenMarkedRead ?? false)
    }
    private func resetNativeSettings() {
        try? CredentialStore.setLaunchAtLogin(false)
        setScrolloverEnabled(true)
        setSyncOnStartEnabled(true)
        setArticlePresentationMode(.visual)
        setArticlePreviewLines(.standard)
        setShowArticleCount(true)
        setShowRelativePublicationTime(false)
        setClickOnNews(.openLink)
        setGlobalShortcut(.optionCommandF)
        setStartupScope(.allNews)
        setStartupCategoryID(nil)
        setStartupFeedID(nil)
        setHideEmptyNavigationEntries(false)
        setRemoveArticlesWhenMarkedRead(false)
    }
    func open(_ article: ArticleSummary) {
        setRead(article, true)
        guard let core else {
            routeOpen(article, prefersMiniflux: false)
            return
        }
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.responsiveResult(
                for: core,
                { try core.feedPreferences(feedId: article.feedId).openInMiniflux }
            ) else { return }
            guard let self, self.core === core else { return }
            switch result {
            case let .success(prefersMiniflux):
                self.routeOpen(article, prefersMiniflux: prefersMiniflux)
            case .failure:
                self.routeOpen(article, prefersMiniflux: false)
            }
        }
    }

    private func routeOpen(_ article: ArticleSummary, prefersMiniflux: Bool) {
        switch ArticleOpenRouting.action(clickOnNews: clickOnNews, openInMiniflux: prefersMiniflux) {
        case .detail: openDetail(article)
        case .original: openOriginal(article)
        case .miniflux: openInMiniflux(article)
        }
    }

    private func openArticle(_ articleID: Int64) {
        guard let core else { return }
        let query = ArticleQuery(
            scope: .all,
            readFilter: .all,
            starredFilter: .all,
            sort: .newestFirst,
            limit: 0,
            cursor: nil
        )
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.responsiveResult(
                for: core,
                { try core.queryArticles(query: query).first(where: { $0.id == articleID }) }
            ) else { return }
            guard let self, self.core === core else { return }
            switch result {
            case let .success(article?):
                self.open(article)
            case .success(nil):
                return
            case let .failure(error):
                self.errorMessage = NativeErrorPresentation.message(for: error)
            }
        }
    }

    private func openWidgetScope(_ selection: WidgetContentSelection) {
        switch selection.scope {
        case .allNews:
            unreadOnly = true
            select(.all)
        case .bookmarks:
            select(.starred)
        case .category:
            guard let id = selection.categoryID, catalog.categories.contains(where: { $0.id == id }) else { return }
            unreadOnly = true
            select(.category(id))
        case .feed:
            guard let id = selection.feedID, catalog.feeds.contains(where: { $0.id == id }) else { return }
            unreadOnly = true
            select(.feed(id))
        }
    }
    private func consumePendingWidgetActions() {
        let actions = pendingWidgetActions
        pendingWidgetActions.removeAll()
        actions.forEach(handleWidgetAction)
    }
    var onOpenDetail: ((ArticleSummary, Bool) -> Void)?
    func openDetail(_ article: ArticleSummary, togglesPreview: Bool = false) { onOpenDetail?(article, togglesPreview) }
    func openOriginal(_ article: ArticleSummary) { if let url = URL(string: article.url) { NSWorkspace.shared.open(url) } }
    func openComments(_ article: ArticleSummary) { if let url = URL(string: article.commentsUrl), !article.commentsUrl.isEmpty { NSWorkspace.shared.open(url) } }
    func openInMiniflux(_ article: ArticleSummary) {
        guard let core else { return }
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.responsiveResult(
                for: core,
                { MinifluxEntryURL.resolve(articleID: article.id, using: core.minifluxEntryUrl) }
            ) else { return }
            guard let self, self.core === core else { return }
            switch result {
            case let .success(url?):
                NSWorkspace.shared.open(url)
            case .success(nil):
                self.errorMessage = String(localized: "Flux could not resolve the Miniflux entry URL.")
            case let .failure(error):
                self.errorMessage = NativeErrorPresentation.message(for: error)
            }
        }
    }
    func copyLink(_ article: ArticleSummary) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(article.url, forType: .string) }
    func loadFeedPreferences(
        feedID: Int64,
        completion: @escaping (Result<FeedPreferences, Error>) -> Void
    ) {
        guard let core else {
            completion(.failure(NSError(domain: "FluxNews", code: 1)))
            return
        }
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.responsiveResult(
                for: core,
                { try core.feedPreferences(feedId: feedID) }
            ) else { return }
            guard let self, self.core === core else { return }
            completion(result)
        }
    }


    func loadBulkFeedPreferences(
        feedIDs: [Int64],
        completion: @escaping (Result<[FeedPreferences], Error>) -> Void
    ) {
        guard let core else {
            completion(.failure(NSError(domain: "FluxNews", code: 1)))
            return
        }
        guard !feedIDs.isEmpty else {
            completion(.success([]))
            return
        }
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.responsiveResult(
                for: core,
                { try core.feedPreferencesBulk(feedIds: feedIDs) }
            ) else { return }
            guard let self, self.core === core else { return }
            completion(result)
        }
    }

    func patchBulkFeedPreferences(
        feedIDs: [Int64],
        patch: FeedPreferencesPatch,
        completion: @escaping (Result<[FeedPreferences], Error>) -> Void
    ) {
        guard let core, !feedIDs.isEmpty else {
            completion(.failure(NSError(domain: "FluxNews", code: 1)))
            return
        }
        let available = Set(catalog.feeds.map(\.id))
        guard Set(feedIDs).isSubset(of: available) else {
            completion(.failure(NSError(
                domain: "FluxNews", code: 2,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "The selected feeds have changed. Refresh and try again.")]
            )))
            return
        }
        let ids = Array(Set(feedIDs)).sorted()
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            do {
                if patch.systemNotificationsEnabled == true {
                    try await SystemNotificationManager.shared.ensureAuthorization()
                }
                guard self?.core === core else { return }
                guard let result = await coordinator.responsiveResult(
                    for: core,
                    {
                        try core.patchFeedPreferencesBulk(feedIds: ids, patch: patch)
                        return try core.feedPreferencesBulk(feedIds: ids)
                    }
                ) else { return }
                guard let self, self.core === core else { return }
                if case .success = result, patch.systemNotificationsEnabled != nil {
                    self.reloadSystemNotificationSettings()
                }
                completion(result)
            } catch {
                guard let self, self.core === core else { return }
                completion(.failure(error))
            }
        }
    }

    private func updateFeedPreferences(
        feedID: Int64,
        change: @escaping @Sendable (Flux) throws -> Void,
        completion: @escaping (Result<FeedPreferences, Error>) -> Void
    ) {
        guard let core else {
            completion(.failure(NSError(domain: "FluxNews", code: 1)))
            return
        }
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.responsiveResult(
                for: core,
                {
                    try change(core)
                    return try core.feedPreferences(feedId: feedID)
                }
            ) else { return }
            guard let self, self.core === core else { return }
            completion(result)
        }
    }

    func feedTitle(feedID: Int64) -> String {
        catalog.feeds.first(where: { $0.id == feedID })?.title ?? ""
    }

    func setFeedDetailRendering(
        feedID: Int64,
        mode: DetailRenderingMode,
        completion: @escaping (Result<FeedPreferences, Error>) -> Void
    ) {
        updateFeedPreferences(
            feedID: feedID,
            change: { try $0.setFeedDetailRendering(feedId: feedID, mode: mode) },
            completion: completion
        )
    }

    func setFeedTruncateDetail(
        feedID: Int64,
        enabled: Bool,
        completion: @escaping (Result<FeedPreferences, Error>) -> Void
    ) {
        updateFeedPreferences(
            feedID: feedID,
            change: { try $0.setFeedTruncateDetail(feedId: feedID, enabled: enabled) },
            completion: completion
        )
    }

    func setFeedOpenInMiniflux(
        feedID: Int64,
        enabled: Bool,
        completion: @escaping (Result<FeedPreferences, Error>) -> Void
    ) {
        updateFeedPreferences(
            feedID: feedID,
            change: { try $0.setFeedOpenInMiniflux(feedId: feedID, enabled: enabled) },
            completion: completion
        )
    }

    func setFeedAutoDownloadAudio(
        feedID: Int64,
        enabled: Bool,
        completion: @escaping (Result<FeedPreferences, Error>) -> Void
    ) {
        updateFeedPreferences(
            feedID: feedID,
            change: { try $0.setFeedAutoDownloadAudio(feedId: feedID, enabled: enabled) },
            completion: completion
        )
    }
    func share(_ article: ArticleSummary) { guard let url = URL(string: article.url) else { return }; DispatchQueue.main.async { [weak self] in guard let self, let view = NSApplication.shared.keyWindow?.contentView else { return }; let picker = NSSharingServicePicker(items: [article.title, url]); self.sharingPicker = picker; let point = view.convert(view.window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil); picker.show(relativeTo: NSRect(origin: point, size: NSSize(width: 1, height: 1)), of: view, preferredEdge: .minY) } }
    func showActionConfirmation(_ message: String) {
        actionConfirmation = message
        actionConfirmationExpiry?.cancel()
        actionConfirmationExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, self?.actionConfirmation == message else { return }
            self?.actionConfirmation = nil
        }
    }
    private func applyStartupScopeIfNeeded() {
        guard !hasAppliedStartupScope else { return }
        hasAppliedStartupScope = true
        guard startupRouteState.shouldApplyStartupScope else { return }
        let resolved = StartupScopeResolver.resolve(startupScope, categoryID: startupCategoryID, feedID: startupFeedID, categoryIDs: Set(catalog.categories.map(\.id)), feedIDs: Set(catalog.feeds.map(\.id)))
        if resolved == .all && (startupScope == .category || startupScope == .feed) {
            if startupScope == .category { startupCategoryID = nil }
            if startupScope == .feed { startupFeedID = nil }
            startupScope = .allNews
            UserDefaults.standard.set(StartupScopePreference.allNews.rawValue, forKey: "FluxNews.startupScope")
            persistStartupTargets()
        }
        scope = resolved
    }
    private func persistStartupTargets() {
        if let startupCategoryID { UserDefaults.standard.set(startupCategoryID, forKey: "FluxNews.startupCategoryID") }
        else { UserDefaults.standard.removeObject(forKey: "FluxNews.startupCategoryID") }
        if let startupFeedID { UserDefaults.standard.set(startupFeedID, forKey: "FluxNews.startupFeedID") }
        else { UserDefaults.standard.removeObject(forKey: "FluxNews.startupFeedID") }
    }
    private func updateVisibleRead(_ ids: [Int64], read: Bool, retainingForScrolloverUndo: Bool = false) {
        let ids = Set(ids)
        if read && ArticleListPresentationPolicy.removesMarkedReadArticle(removeWhenMarkedRead: removeArticlesWhenMarkedRead, unreadOnly: unreadOnly, scope: scope) {
            if retainingForScrolloverUndo {
                for article in articles where ids.contains(article.id) { scrolloverRemovedArticles[article.id] = article }
            }
            articles.removeAll { ids.contains($0.id) }
        } else {
            updateVisible(Array(ids)) { $0.isRead = read }
        }
    }
    private func restoreScrolloverRemovedArticles() {
        guard !scrolloverRemovedArticles.isEmpty else { return }
        let visibleIDs = Set(articles.map(\.id))
        articles.append(contentsOf: scrolloverRemovedArticles.values.filter { !visibleIDs.contains($0.id) })
        articles.sort { scrolloverOriginalOrder[$0.id, default: .max] < scrolloverOriginalOrder[$1.id, default: .max] }
        scrolloverRemovedArticles = [:]
        scrolloverOriginalOrder = [:]
    }
    private func updateVisible(_ ids: [Int64], _ change: (inout ArticleSummary) -> Void) { let ids = Set(ids); for index in articles.indices where ids.contains(articles[index].id) { change(&articles[index]) } }
    private func reloadScrolloverCounts() {
        guard let core, let selectionQuery = query() else { return }
        let countMode: NavigationCountMode = unreadOnly ? .unread : .all
        let coordinator = coreSessionExecutionCoordinator
        Task { [weak self, core, coordinator] in
            guard let result = await coordinator.responsiveResult(
                for: core,
                {
                    let selectionTotal = try core.countArticles(query: selectionQuery)
                    let projection = try core.navigationProjection(countMode: countMode)
                    return (selectionTotal, projection)
                }
            ) else { return }
            guard let self, self.core === core else { return }
            switch result {
            case let .success((selectionTotal, projection)):
                self.selectionTotal = selectionTotal
                self.catalog = projection.catalog
                self.unreadTotal = projection.unreadTotal
                self.starredTotal = projection.starredTotal
                self.categorySidebarCounts = Dictionary(uniqueKeysWithValues: projection.categoryCounts.map { ($0.id, $0.count) })
                self.feedSidebarCounts = Dictionary(uniqueKeysWithValues: projection.feedCounts.map { ($0.id, $0.count) })
            case let .failure(error):
                self.errorMessage = NativeErrorPresentation.message(for: error)
            }
        }
    }

    private func showScrolloverUndo() {
        guard scrolloverUndoBatch.showsUndo else {
            scrolloverUndoVisible = false
            undoExpiry?.cancel()
            return
        }
        scrolloverUndoVisible = true
        undoExpiry?.cancel()
        undoExpiry = Task { [weak self] in try? await Task.sleep(for: .seconds(8)); guard !Task.isCancelled else { return }; self?.scrolloverUndoVisible = false }
    }
}


private final class WeakBrowserStore: @unchecked Sendable { weak var value: BrowserStore?; init(_ value: BrowserStore) { self.value = value } }
private final class BrowserEventListener: EventListener, @unchecked Sendable {
    weak var store: BrowserStore?
    // Assigned when a successfully configured subscription becomes active.
    // Core calls may arrive before then, so the generation must be captured per callback.
    private let lock = NSLock()
    private var storedGeneration: UInt64 = 0
    var generation: UInt64 {
        get { lock.lock(); defer { lock.unlock() }; return storedGeneration }
        set { lock.lock(); defer { lock.unlock() }; storedGeneration = newValue }
    }
    init(store: BrowserStore) { self.store = store }
    func onEvent(event: CoreEvent) {
        let generation = generation
        Task { @MainActor [weak store] in store?.handle(event: event, generation: generation) }
    }
}
