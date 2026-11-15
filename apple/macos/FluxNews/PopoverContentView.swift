import AppKit
import Combine
import SwiftUI

enum PopoverLayout {
    static let visualWidth: CGFloat = 390
    static let compactWidth: CGFloat = 500
    static let sidebarWidth: CGFloat = 240
    static let visualHeight: CGFloat = 760
    static let compactHeight: CGFloat = 520
    static let verticalScreenMargin: CGFloat = 32
    static let animation: TimeInterval = 0.2

    static func contentWidth(for mode: ArticlePresentationMode) -> CGFloat {
        // `visualCompact` carries a thumbnail too, so it needs the visual width.
        mode == .compact ? compactWidth : visualWidth
    }

    static func width(mode: ArticlePresentationMode, sidebarVisible: Bool) -> CGFloat {
        contentWidth(for: mode) + (sidebarVisible ? sidebarWidth : 0)
    }

    static func height(for mode: ArticlePresentationMode) -> CGFloat {
        mode == .compact ? compactHeight : visualHeight
    }
}

private enum ArticleScrollSpace { static let name = "FluxNews.ArticleScroll" }
private struct ArticleFrameKey: PreferenceKey {
    static var defaultValue: [Int64: CGRect] = [:]
    static func reduce(value: inout [Int64: CGRect], nextValue: () -> [Int64: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct PopoverContentView: View {
    @ObservedObject var store: BrowserStore
    let playbackState: MediaPlaybackPresentationState
    let playbackCoordinator: MediaPlaybackCoordinator?
    let transferState: MediaTransferPresentationState
    let layoutChanged: (Bool) -> Void
    let showSettings: () -> Void
    let dismiss: () -> Void
    @State private var sidebarVisible = false
    @State private var showingPlayer = false
    @State private var previewArticleID: Int64?

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                NavigationSidebar(store: store, onNavigate: { scope in
                    showingPlayer = false
                    store.select(scope)
                })
                    .frame(width: PopoverLayout.sidebarWidth)
                    .overlay(alignment: .trailing) { Divider() }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            ArticlePane(
                store: store,
                playbackState: playbackState,
                playbackCoordinator: playbackCoordinator,
                transferState: transferState,
                sidebarVisible: $sidebarVisible,
                showingPlayer: $showingPlayer,
                previewArticleID: $previewArticleID,
                layoutChanged: layoutChanged,
                showSettings: showSettings,
                dismiss: dismiss
            )
            .frame(width: PopoverLayout.contentWidth(for: store.articlePresentationMode))
        }
        .frame(width: PopoverLayout.width(mode: store.articlePresentationMode, sidebarVisible: sidebarVisible))
        .frame(maxHeight: .infinity)
        .sheet(item: $store.feedSettingsTarget) { target in FeedSettingsView(store: store, target: target) }
        .sheet(isPresented: $store.addFeedVisible) { AddFeedView(store: store) }
        .sheet(isPresented: $store.addCategoryVisible) { AddCategoryView(store: store) }
    }
}

private struct ArticlePane: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: BrowserStore
    let playbackState: MediaPlaybackPresentationState
    let playbackCoordinator: MediaPlaybackCoordinator?
    let transferState: MediaTransferPresentationState
    @Binding var sidebarVisible: Bool
    @Binding var showingPlayer: Bool
    @Binding var previewArticleID: Int64?
    let layoutChanged: (Bool) -> Void
    let showSettings: () -> Void
    let dismiss: () -> Void
    @State private var visibleArticleIDs = Set<Int64>()
    @State private var scrollDirection: CGFloat = 0
    @State private var reachedListBottom = false
    @State private var bottomScrolloverArmed = false
    @State private var trackerRevision: UInt64
    @State private var selectedID: Int64?
    @State private var hoveredID: Int64?
    @State private var scrollPhase = ScrollPhase.idle
    @State private var suppressUntil: TimeInterval = 0
    @State private var scrollPosition = ScrollPosition()
    @State private var pendingAudioReplacement: Enclosure?
    private let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    init(store: BrowserStore, playbackState: MediaPlaybackPresentationState, playbackCoordinator: MediaPlaybackCoordinator?, transferState: MediaTransferPresentationState, sidebarVisible: Binding<Bool>, showingPlayer: Binding<Bool>, previewArticleID: Binding<Int64?>, layoutChanged: @escaping (Bool) -> Void, showSettings: @escaping () -> Void, dismiss: @escaping () -> Void) {
        self.store = store
        self.playbackState = playbackState
        self.playbackCoordinator = playbackCoordinator
        self.transferState = transferState
        _sidebarVisible = sidebarVisible
        _showingPlayer = showingPlayer
        _previewArticleID = previewArticleID
        self.layoutChanged = layoutChanged
        self.showSettings = showSettings
        self.dismiss = dismiss
        _trackerRevision = State(initialValue: store.listPresentationRevision)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showingPlayer {
                PlayerView(
                    store: store, state: playbackState, coordinator: playbackCoordinator,
                    previewArticleID: previewArticleID, onPlayEnclosure: playAudio,
                    onDownload: { store.requestManualDownload(articleID: $0, enclosureID: $1) },
                    onDelete: { store.deleteDownload(articleID: $0, enclosureID: $1) },
                    onCancel: { store.cancelDownload(articleID: $0, enclosureID: $1) },
                    onStop: {
                        previewArticleID = nil
                        showingPlayer = false
                    }
                )
            } else {
                content
                if playbackState.loadedEnclosure != nil {
                    Divider()
                    MacCompactPlayerBar(
                        playbackState: playbackState,
                        coordinator: playbackCoordinator,
                        openPlayer: {
                            previewArticleID = nil
                            showingPlayer = true
                        }
                    )
                }
            }
        }
        .background {
            if store.articles.isEmpty {
                KeyboardCommandObserver { command in
                    if command == .refresh { store.sync() }
                    if command == .dismiss { dismiss() }
                }
            }
        }
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            if let confirmation = store.actionConfirmation {
                Text(confirmation)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 3)
                    .padding(.bottom, 12)
            } else if store.newDataAvailable {
                updateBanner.padding(.bottom, 12)
            } else if store.scrolloverUndoVisible {
                undoBanner.padding(.bottom, 12)
            }
        }
        .onChange(of: store.listPresentationRevision) { _, revision in
            visibleArticleIDs.removeAll()
            scrollDirection = 0
            trackerRevision = revision
            selectedID = nil
            suppressUntil = ProcessInfo.processInfo.systemUptime + 0.4
        }
        .onChange(of: store.scope) { _, _ in
            showingPlayer = false
            previewArticleID = nil
        }
        .onChange(of: store.articlePresentationMode) { _, _ in layoutChanged(sidebarVisible) }
        .onChange(of: selectedID) { _, articleID in
            store.selectArticleAudioActions(for: articleID)
        }
        .onChange(of: store.popoverVisible) { _, _ in
            visibleArticleIDs.removeAll()
            scrollDirection = 0
        }
        .onChange(of: store.articles.map(\.id)) { _, ids in
            if let selectedID, !ids.contains(selectedID) { self.selectedID = nil }
        }
        .alert("Replace Playing Audio?", isPresented: Binding(get: { pendingAudioReplacement != nil }, set: { if !$0 { pendingAudioReplacement = nil } })) {
            Button("Cancel", role: .cancel) { pendingAudioReplacement = nil }
            Button("Replace", role: .destructive) {
                if let enclosure = pendingAudioReplacement { pendingAudioReplacement = nil; startAudio(enclosure) }
            }
        } message: {
            Text("The currently playing audio will be replaced.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { toggleSidebar() } label: { Image(systemName: "sidebar.left") }
                .buttonStyle(.borderless)
                .help(sidebarToggleLabel)
                .accessibilityLabel(sidebarToggleLabel)
            Text(title).font(.headline).lineLimit(1)
            if store.showArticleCount {
                Text("\(store.selectionTotal)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { store.sync() } label: {
                if store.isLoading { ProgressView().controlSize(.small).frame(width: 16, height: 16) }
                else { Image(systemName: "arrow.clockwise") }
            }
            .buttonStyle(.borderless)
            .disabled(store.isLoading)
            .help("Refresh Miniflux now")
            .accessibilityLabel("Refresh")
            if showingPlayer {
                PlayerNavigationButton(playbackState: playbackState, showingPlayer: $showingPlayer)
            }
            moreMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var moreMenu: some View {
        MoreMenu(
            isListeningList: store.isListeningList,
            unreadOnly: store.unreadOnly,
            newestFirst: store.newestFirst,
            listeningListSort: store.listeningListSort,
            listeningListFeedID: store.listeningListFeedID,
            listeningListFeeds: store.listeningListFeeds,
            canMarkAllRead: store.canMarkCurrentScopeRead,
            canMarkAllReadAndNext: store.canMarkCurrentScopeRead && store.nextScopeAfterMarkRead != nil,
            markAllRead: { store.markCurrentScopeRead() },
            markAllReadAndNext: { store.markCurrentScopeRead(andNavigateNext: true) },
            setUnreadOnly: store.setUnreadOnly,
            setNewestFirst: store.setNewestFirst,
            setListeningListSort: store.setListeningListSort,
            setListeningListFeed: store.setListeningListFeed,
            showSettings: showSettings,
            quit: { NSApplication.shared.terminate(nil) }
        )
    }

    private var sidebarToggleLabel: String {
        sidebarVisible ? String(localized: "Hide navigation") : String(localized: "Show navigation")
    }

    @ViewBuilder private var content: some View {
        if store.isListeningList {
            ListeningListView(store: store, playbackState: playbackState, transferState: transferState,
                onOpenPlayer: { articleID in
                    previewArticleID = articleID
                    showingPlayer = true
                }, onPlay: playAudio, onPause: { playbackCoordinator?.pause() }, coordinator: playbackCoordinator, onDownload: { articleID, enclosureID in store.requestManualDownload(articleID: articleID, enclosureID: enclosureID) }, onDelete: { articleID, enclosureID in store.deleteDownload(articleID: articleID, enclosureID: enclosureID) }, onCancel: { articleID, enclosureID in store.cancelDownload(articleID: articleID, enclosureID: enclosureID) }, onRemove: { articleID in store.removeFromListeningList(articleID: articleID) })
        } else if store.isSearchActive {
             SearchResultsView(store: store, transferState: transferState, onPlay: playAudio, onDownload: { enclosure in store.requestManualDownload(articleID: enclosure.articleId, enclosureID: enclosure.id) }, onDelete: { enclosure in store.deleteDownload(articleID: enclosure.articleId, enclosureID: enclosure.id) }, onAdd: { articleID in store.addToListeningList(articleID: articleID) })
        } else if let error = store.errorMessage, store.articles.isEmpty {
            ContentUnavailableView("Refresh failed", systemImage: "exclamationmark.triangle", description: Text(error))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.isLoading && store.articles.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading Miniflux...").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.articles.isEmpty {
            ContentUnavailableView("No articles", systemImage: "tray", description: Text("There are no articles in this selection."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: store.articlePresentationMode == .compact ? 0 : 4) {
                            ForEach(store.articles, id: \.id) { article in
                                 ArticleItem(article: article, mode: store.articlePresentationMode, selected: selectedID == article.id, audioState: store.articleAudioActionStates[article.id], transferState: transferState, store: store, onSelect: { selectedID = article.id }, onPlayAudio: playAudio, onDownloadAudio: { enclosure in store.requestManualDownload(articleID: article.id, enclosureID: enclosure.id) }, onDeleteDownload: { enclosure in store.deleteDownload(articleID: article.id, enclosureID: enclosure.id) }, onAddToListeningList: { store.addToListeningList(articleID: article.id) }, onHoverChanged: { hovering in
                                    if hovering { hoveredID = article.id }
                                    else if hoveredID == article.id { hoveredID = nil }
                                })
                                    .id(article.id)
                                    .background {
                                        GeometryReader { row in
                                            Color.clear.preference(key: ArticleFrameKey.self, value: [article.id: row.frame(in: .named(ArticleScrollSpace.name))])
                                        }
                                    }
                                if store.articlePresentationMode == .compact {
                                    Divider().padding(.leading, 12)
                                }
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollPosition($scrollPosition)
                    .onScrollTargetVisibilityChange(idType: Int64.self) { ids in
                        visibleArticlesChanged(Set(ids))
                    }
                    .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { old, new in
                        scrollChanged(new - old)
                    }
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        geometry.contentOffset.y + geometry.containerSize.height
                            >= geometry.contentSize.height + geometry.contentInsets.bottom - 1
                    } action: { _, atBottom in
                        reachedListBottom = atBottom
                        if atBottom { finishLastScrolloverItems() }
                    }
                    .onScrollPhaseChange { previous, phase in
                        if !isUserScrollPhase(previous), isUserScrollPhase(phase) {
                            store.beginScrolloverUndoBatch()
                        }
                        if isUserScrollPhase(previous), !isUserScrollPhase(phase) {
                            if reachedListBottom { finishLastScrolloverItems() }
                            store.finishScrolloverUndoBatch()
                        }
                        scrollPhase = phase
                        if !userScrolling { scrollDirection = 0 }
                    }
                    .onChange(of: store.snapshotResetRevision) { _, revision in
                        NativeLog.snapshot.debug("snapshot reset requested revision=\(revision, privacy: .public)")
                        visibleArticleIDs.removeAll()
                        scrollDirection = 0
                        reachedListBottom = false
                        bottomScrolloverArmed = false
                        suppressUntil = ProcessInfo.processInfo.systemUptime + 0.4
                        scrollPosition.scrollTo(edge: .top)
                        NativeLog.snapshot.debug("snapshot reset completed revision=\(revision, privacy: .public)")
                    }
                    .background { KeyboardCommandObserver { command in handle(command, proxy: proxy) } }
                    .onChange(of: geometry.size) { _, _ in
                        visibleArticleIDs.removeAll()
                        scrollDirection = 0
                        reachedListBottom = false
                        bottomScrolloverArmed = false
                    }
                }
            }
        }
    }

    private var updateBanner: some View {
        HStack(spacing: 10) { Text("New articles available"); Button("Refresh") { store.applyNewData() }.buttonStyle(.borderless) }
            .font(.callout).padding(.horizontal, 12).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule()).shadow(radius: 4, y: 2)
    }

    private var undoBanner: some View {
        HStack(spacing: 10) { Text("\(store.lastScrolloverBatch.count) articles marked as read"); Button("Undo") { store.undoScrollover() }.buttonStyle(.borderless) }
            .font(.callout).padding(.horizontal, 12).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule()).shadow(radius: 4, y: 2)
    }

    private var title: String {
        switch store.scope {
        case .all: "All News"
        case .starred: "Starred"
        case .search: "Search"
        case .listeningList: "Listening List"
        case let .category(id): store.catalog.categories.first(where: { $0.id == id })?.title ?? "Category"
        case let .feed(id): store.catalog.feeds.first(where: { $0.id == id })?.title ?? "Feed"
        }
    }

    private var unreadIDs: Set<Int64> { Set(store.articles.filter { !$0.isRead }.map(\.id)) }
    private var userScrolling: Bool { scrollPhase != .idle && scrollPhase != .animating }
    private func isUserScrollPhase(_ phase: ScrollPhase) -> Bool { phase != .idle && phase != .animating }
    private func toggleSidebar() {
        if reduceMotion { sidebarVisible.toggle() }
        else { withAnimation(.easeInOut(duration: PopoverLayout.animation)) { sidebarVisible.toggle() } }
        layoutChanged(sidebarVisible)
    }
    private func scrollChanged(_ delta: CGFloat) {
        guard userScrolling else {
            scrollDirection = 0
            return
        }
        store.noteMeaningfulInteraction()
        scrollDirection = delta
        if delta > 0 { bottomScrolloverArmed = true }
        if delta < 0 { bottomScrolloverArmed = false }
        if reachedListBottom { finishLastScrolloverItems() }
    }

    private func finishLastScrolloverItems() {
        guard reachedListBottom, bottomScrolloverArmed,
              !store.isSearchActive, store.popoverVisible,
              store.markReadOnScrolloverEnabled,
              ProcessInfo.processInfo.systemUptime >= suppressUntil,
              trackerRevision == store.listPresentationRevision,
              !store.articles.isEmpty else { return }
        let remaining = MacScrolloverEndPolicy.remainingUnreadIDs(
            articles: store.articles, visibleIDs: visibleArticleIDs,
            atBottom: reachedListBottom, forwardScrollArmed: bottomScrolloverArmed
        )
        bottomScrolloverArmed = false
        if !remaining.isEmpty { store.flushScrollover(remaining) }
    }

    private func visibleArticlesChanged(_ newVisibleIDs: Set<Int64>) {
        defer { visibleArticleIDs = newVisibleIDs }

        guard userScrolling,
              scrollDirection > 0,
              !store.isSearchActive,
              store.popoverVisible,
              store.markReadOnScrolloverEnabled,
              ProcessInfo.processInfo.systemUptime >= suppressUntil,
              trackerRevision == store.listPresentationRevision,
              !visibleArticleIDs.isEmpty,
              !newVisibleIDs.isEmpty else { return }

        let order = Dictionary(uniqueKeysWithValues: store.articles.enumerated().map { ($0.element.id, $0.offset) })
        guard let firstVisibleIndex = newVisibleIDs.compactMap({ order[$0] }).min() else { return }

        let ids = visibleArticleIDs
            .subtracting(newVisibleIDs)
            .filter { id in
                guard unreadIDs.contains(id), let index = order[id] else { return false }
                return index < firstVisibleIndex
            }
            .sorted { (order[$0] ?? .max) < (order[$1] ?? .max) }

        if !ids.isEmpty { store.flushScrollover(ids) }
    }

    private func handle(_ command: ArticleKeyboardCommand, proxy: ScrollViewProxy) {
        switch command {
        case .moveUp: move(-1, proxy)
        case .moveDown: move(1, proxy)
        case .open: if let article = selected { store.open(article) }
        case .openDetail: if let article = readerTarget { store.openDetail(article, togglesPreview: true) }
        case .toggleRead: if !store.isSearchActive, let article = selected { store.setRead(article, !article.isRead) }
        case .toggleStarred: if let article = selected { store.setStarred(article, !article.isStarred) }
        case .refresh: store.sync()
        case .dismiss: dismiss()
        }
    }
    private var selected: ArticleSummary? { selectedID.flatMap { id in store.articles.first { $0.id == id } } }
    private var readerTarget: ArticleSummary? {
        let id = ArticleReaderTarget.articleID(hoveredID: hoveredID, selectedID: selectedID, availableIDs: Set(store.articles.map(\.id)))
        return id.flatMap { targetID in store.articles.first { $0.id == targetID } }
    }
    private func playAudio(_ enclosure: Enclosure) {
        guard playbackCoordinator != nil else { return }
        if ArticleAudioActions.requiresReplacement(currentID: playbackState.loadedEnclosure?.id, currentStatus: playbackState.status, selectedID: enclosure.id) {
            pendingAudioReplacement = enclosure
            return
        }
        startAudio(enclosure)
    }
    private func startAudio(_ enclosure: Enclosure) {
        previewArticleID = nil
        guard let coordinator = playbackCoordinator else { return }
        do {
            if playbackState.loadedEnclosure?.id == enclosure.id, playbackState.status == .playing {
                showingPlayer = true
                return
            }
            try coordinator.play(enclosureID: enclosure.id)
            showingPlayer = true
        } catch {
            store.errorMessage = NativeErrorPresentation.message(for: error)
        }
    }
    private func move(_ delta: Int, _ proxy: ScrollViewProxy) {
        guard !store.articles.isEmpty else { return }
        let current = selectedID.flatMap { id in store.articles.firstIndex { $0.id == id } }
        let index = min(max(0, (current ?? (delta < 0 ? store.articles.count : -1)) + delta), store.articles.count - 1)
        selectedID = store.articles[index].id
        suppressUntil = ProcessInfo.processInfo.systemUptime + 0.4
        visibleArticleIDs.removeAll()
        scrollDirection = 0
        proxy.scrollTo(store.articles[index].id, anchor: .center)
    }
}
