import SwiftUI
import UIKit

private struct IOSBrowserURL: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct IOSReaderArticle: Identifiable {
    let article: ArticleSummary
    var id: Int64 { article.id }
}

private struct IOSSharePayload: Identifiable {
    let items: [Any]
    let id = UUID()
}

private struct IOSArticleMediaPlayerPresentation: Identifiable {
    let article: ArticleSummary
    let enclosureID: Int64
    let source: IOSArticleMediaSource
    var id: String { "\(source):\(article.id):\(enclosureID)" }
}

private enum IOSArticleMediaSource {
    case news
    case search
}

private struct IOSArticleMediaDownloadChoice: Identifiable {
    let article: ArticleSummary
    let enclosures: [Enclosure]
    let source: IOSArticleMediaSource
    var id: String { "\(source)-\(article.id)" }
}

private enum IOSMarkReadWorkflow: Equatable {
    case read
    case readAndNext
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ObservedObject var bootstrapper: CoreBootstrapper
    var newsreaderStore: NewsreaderStore
    @StateObject private var searchStore = IOSSearchStore()
    @StateObject private var listeningListStore = IOSListeningListStore()
    @ObservedObject private var playbackState =
        IOSAppRuntime.shared.mediaRuntime.playbackPresentationState
    @State private var navigationPresented = false
    @State private var searchPresented = false
    @State private var listeningListPresented = false
    /// Set while the navigation sheet is closing so that the requested fly-over
    /// opens only after the navigation sheet is fully gone.
    @State private var searchPendingAfterNavigationSheet = false
    @State private var listeningListPendingAfterNavigationSheet = false
    @State private var diagnosticsPresented = false
    @State private var settingsPresented = false
    @State private var splitColumnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var browser: IOSBrowserURL?
    @State private var articleOpenError: String?
    @State private var articleOpenGeneration = 0
    @State private var readerArticle: IOSReaderArticle?
    @State private var readerDocument: ReaderDocument?
    @State private var readerIsLoading = false
    @State private var readerErrorMessage: String?
    @State private var readerGeneration = 0
    @State private var sharePayload: IOSSharePayload?
    @State private var actionFeedback: IOSActionFeedbackItem?
    @State private var actionFeedbackGeneration: UInt64 = 0
    @State private var actionError: String?
    @State private var markReadConfirmationPresented = false
    @State private var markReadWorkflow: IOSMarkReadWorkflow = .read
    @State private var syncPresentation: IOSSyncButtonPresentation.State = .idle
    @State private var syncPresentationGeneration: UInt64 = 0
    @State private var saveToServiceFeedbackTrigger: UInt64 = 0
    @State private var pendingWidgetAction: WidgetAction?
    @State private var articleMediaPlayer: IOSArticleMediaPlayerPresentation?
    @State private var listeningListPlayerArticleID: Int64?
    @State private var articleMediaDownloadChoice: IOSArticleMediaDownloadChoice?
    @State private var nowPlayingPresented = false
    @ObservedObject var articleListActionPreferences: IOSArticleListActionPreferences

    /// The capsule already opens the scope chooser, so a second control for the
    /// same action would be pure redundancy.
    private var capsuleCarriesScopeAction: Bool {
        !adaptivePresentation.usesPersistentSplitNavigation
    }

    private var adaptivePresentation: AdaptivePresentation {
        AdaptivePresentationPolicy.presentation(
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass
        )
    }

    private var articleListChromeMode: IOSArticleListChromeMode {
        IOSArticleListChromePresentation.mode(
            for: adaptivePresentation,
            verticalSizeClass: verticalSizeClass,
            splitColumnVisibility: splitColumnVisibility
        )
    }

    private var miniPlayerPlacement: IOSMiniPlayerPlacement {
        IOSMiniPlayerPlacementPolicy.placement(
            for: articleListChromeMode
        )
    }

    private var adaptiveSplitColumnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { splitColumnVisibility },
            set: { requested in
                splitColumnVisibility = AdaptiveShellTransitionPolicy.constrainedSplitColumnVisibility(
                    requested: requested,
                    presentation: adaptivePresentation
                )
            }
        )
    }

    var body: some View {
        Group {
            if case .ready = bootstrapper.state, newsreaderStore.core != nil {
                newsreader
            } else {
                StartupView(
                    bootstrapper: bootstrapper,
                    store: newsreaderStore,
                    articleListActionPreferences: articleListActionPreferences
                )
            }
        }
        .overlay(alignment: .bottom) {
            actionFeedbackOverlay(
                active: !searchPresented && !listeningListPresented,
                hasBottomActionBar: articleListChromeMode == .compactPortrait,
                hasMiniPlayer: miniPlayerPlacement == .portraitBottomDock
                    && miniPlayerIsVisible
            )
        }
        .animation(.easeInOut(duration: 0.2), value: actionFeedback?.id)
        .sheet(isPresented: $diagnosticsPresented) { DeveloperDiagnosticsView(bootstrapper: bootstrapper) }
        .sheet(isPresented: $nowPlayingPresented) {
            nowPlayingPlayerView
        }
        // A sheet rather than a pushed destination: the timeline is the detail
        // column of a split view that collapses on a phone, and a destination
        // registered there did not activate. A sheet behaves identically in both
        // size classes and needs no sequencing against the navigation sheet.
        .sheet(isPresented: $searchPresented) {
            NavigationStack {
                searchView
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { searchPresented = false }
                        }
                    }
            }
            .overlay(alignment: .bottom) {
                actionFeedbackOverlay(
                    active: true,
                    hasBottomActionBar: false,
                    hasMiniPlayer: false
                )
            }
            .animation(.easeInOut(duration: 0.2), value: actionFeedback?.id)
            // Only one sheet can be presented per view, so what the results open
            // has to hang off the search sheet while it is up.
            .sheet(item: gatedBrowser(active: true)) { item in IOSInAppBrowser(url: item.url) }
            .sheet(item: gatedReaderSheet(active: true)) { item in
                NavigationStack { readerView(for: item.article) }
            }
            .sheet(item: gatedShare(active: true)) { payload in IOSShareSheet(items: payload.items) }
            .sheet(
                item: gatedArticleMediaPlayer(active: true),
                onDismiss: { listeningListStore.clearShowNotes() }
            ) { presentation in
                articleMediaPlayerView(presentation)
            }
            .confirmationDialog(
                "Download Audio",
                isPresented: gatedArticleMediaDownloadPresented(active: true),
                titleVisibility: .visible
            ) {
                articleMediaDownloadButtons
            }
        }
        .sheet(isPresented: $listeningListPresented) {
            NavigationStack {
                listeningListView
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") {
                                listeningListPresented = false
                            }
                        }
                    }
            }
            .sheet(
                isPresented: Binding(
                    get: { listeningListPlayerArticleID != nil },
                    set: { presented in
                        if !presented {
                            listeningListPlayerArticleID = nil
                        }
                    }
                ),
                onDismiss: {
                    listeningListStore.clearShowNotes()
                }
            ) {
                listeningListPlayerView
            }
        }
        .sheet(
            item: gatedBrowser(
                active: !searchPresented && !listeningListPresented
            )
        ) { item in
            IOSInAppBrowser(url: item.url)
        }
        .sheet(item: gatedReaderSheet(active: !searchPresented && !listeningListPresented)) { item in
            NavigationStack { readerView(for: item.article) }
        }
        .sheet(item: gatedShare(active: !searchPresented && !listeningListPresented)) { payload in IOSShareSheet(items: payload.items) }
        .sheet(
            item: gatedArticleMediaPlayer(active: !searchPresented && !listeningListPresented),
            onDismiss: { listeningListStore.clearShowNotes() }
        ) { presentation in
            articleMediaPlayerView(presentation)
        }
        .confirmationDialog(
            "Download Audio",
            isPresented: gatedArticleMediaDownloadPresented(
                active: !searchPresented && !listeningListPresented
            ),
            titleVisibility: .visible
        ) {
            articleMediaDownloadButtons
        }
        .alert("Unable to Open Article", isPresented: Binding(get: { articleOpenError != nil }, set: { if !$0 { articleOpenError = nil } })) {
            Button("OK", role: .cancel) { articleOpenError = nil }
        } message: { Text(articleOpenError ?? "") }
        .alert("Action Failed", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
        .sensoryFeedback(.success, trigger: saveToServiceFeedbackTrigger)
        .confirmationDialog(markReadDialogTitle, isPresented: $markReadConfirmationPresented, titleVisibility: .visible) {
            Button(markReadDialogTitle, role: .destructive) { performMarkReadWorkflow() }
        } message: { Text("Marks all unread articles in this scope as read.") }
        .onChange(of: adaptivePresentation) { _, presentation in
            normalizeAdaptiveShell(for: presentation)
        }
        .onChange(of: searchPresented) { _, presented in
            if !presented { searchStore.invalidate() }
        }
        .onAppear {
            if newsreaderStore.scope == .listeningList {
                newsreaderStore.select(.all)
            }
            normalizeAdaptiveShell(for: adaptivePresentation)
        }
        .onOpenURL { url in
            handleWidgetURL(url)
        }
        .task(id: bootstrapper.coreRevision) {
            if let core = bootstrapper.core {
                searchStore.attach(
                    to: core,
                    coreSessionExecutionCoordinator: bootstrapper.coreSessionExecutionCoordinator
                )
                listeningListStore.attach(
                    to: core,
                    coreSessionExecutionCoordinator: bootstrapper.coreSessionExecutionCoordinator
                )
                listeningListStore.onTransferReconciliationRequested = {
                    await IOSAppRuntime.shared.mediaTransferReconciliationHandoff
                        .requestReconciliation()
                }
                IOSAppRuntime.shared.mediaRuntime.transferCoordinator.onWorkChanged = {
                    listeningListStore.reload()
                }
                newsreaderStore.onMediaTransferReconciliationRequested = {
                    await IOSAppRuntime.shared.mediaTransferReconciliationHandoff
                        .requestReconciliation()
                }
                newsreaderStore.onMediaArtworkProbeChanged = {
                    listeningListStore.reload()
                }
                searchStore.onMediaTransferReconciliationRequested = {
                    await IOSAppRuntime.shared.mediaTransferReconciliationHandoff
                        .requestReconciliation()
                }
                searchStore.onMediaArtworkProbeChanged = {
                    listeningListStore.reload()
                }
                searchStore.onLocalFirstMutation = { newsreaderStore.loadNavigationAndCounts() }
            } else {
                searchStore.onMediaTransferReconciliationRequested = nil
                searchStore.onMediaArtworkProbeChanged = nil
                searchStore.detach()
                listeningListStore.onTransferReconciliationRequested = nil
                IOSAppRuntime.shared.mediaRuntime.transferCoordinator.onWorkChanged = nil
                newsreaderStore.onMediaTransferReconciliationRequested = nil
                newsreaderStore.onMediaArtworkProbeChanged = nil
                listeningListStore.detach()
            }
            consumePendingWidgetActionIfReady()
        }
    }

    private func gatedArticleMediaPlayer(
        active: Bool
    ) -> Binding<IOSArticleMediaPlayerPresentation?> {
        Binding(
            get: { active ? articleMediaPlayer : nil },
            set: { if active { articleMediaPlayer = $0 } }
        )
    }

    private func gatedArticleMediaDownloadPresented(
        active: Bool
    ) -> Binding<Bool> {
        Binding(
            get: { active && articleMediaDownloadChoice != nil },
            set: {
                if active && !$0 {
                    articleMediaDownloadChoice = nil
                }
            }
        )
    }

    @ViewBuilder
    private var listeningListPlayerView: some View {
        let item = listeningListPlayerArticleID.flatMap { articleID in
            listeningListStore.items.first { $0.articleId == articleID }
        }

        mediaPlayerView(item: item) {
            listeningListPlayerArticleID = nil
        }
    }

    @ViewBuilder
    private func mediaPlayerView(
        item: ListeningListItem?,
        onDismiss: @escaping () -> Void
    ) -> some View {
        IOSMediaPlayerView(
            playbackState: playbackState,
            transferState: IOSAppRuntime.shared.mediaRuntime.transferPresentationState,
            sleepTimer: IOSAppRuntime.shared.mediaRuntime.playbackCoordinator.sleepTimer,
            playbackCoordinator: IOSAppRuntime.shared.mediaRuntime.playbackCoordinator,
            item: item,
            downloadEnclosures: item?.audioEnclosures.map {
                IOSMediaPlayerDownloadEnclosure(
                    enclosure: $0.enclosure,
                    download: $0.download
                )
            } ?? [],
            onDownloadAction: { enclosureID, action in
                handleListeningListPlayerDownloadAction(
                    enclosureID: enclosureID,
                    action: action
                )
            },
            feedIconFeedID: item?.feedId,
            feedIconTitle: item?.feedTitle ?? "",
            feedIconState: { feedID, variant in
                newsreaderStore.feedIconPresentationState(
                    for: feedID,
                    variant: variant
                )
            },
            onRequestFeedIcon: { feedID, variant in
                newsreaderStore.requestFeedIcon(
                    feedID,
                    variant: variant
                )
            },
            showNotesDocument: listeningListStore.showNotesDocument,
            showNotesIsLoading: listeningListStore.showNotesIsLoading,
            showNotesErrorMessage: listeningListStore.showNotesErrorMessage,
            onSelectEnclosure: { enclosureID in
                if let articleID = item?.articleId {
                    playListeningListEnclosure(
                        articleID: articleID,
                        enclosureID: enclosureID
                    )
                }
            },
            onShowNotes: {
                if let articleID = item?.articleId {
                    listeningListStore.loadShowNotes(articleID: articleID)
                }
            },
            onDismiss: onDismiss
        )
    }

    @ViewBuilder
    private var nowPlayingPlayerView: some View {
        let item = IOSListeningListPlayerPresentation.item(
            for: playbackState.loadedEnclosure,
            in: listeningListStore.items
        )
        mediaPlayerView(item: item) {
            nowPlayingPresented = false
            listeningListStore.clearShowNotes()
        }
    }

    private func handleListeningListPlayerDownloadAction(
        enclosureID: Int64,
        action: IOSListeningListPresentation.DownloadAction
    ) {
        Task {
            switch action {
            case .download:
                await listeningListStore.requestDownload(
                    enclosureID: enclosureID
                )
            case .pending, .downloading:
                await listeningListStore.cancelDownload(
                    enclosureID: enclosureID
                )
            case .retry:
                await listeningListStore.retryDownload(
                    enclosureID: enclosureID
                )
            case .delete:
                await listeningListStore.deleteDownload(
                    enclosureID: enclosureID
                )
            case .cancelling, .pendingDeletion:
                break
            }
        }
    }

    private func openListeningListPlayer(articleID: Int64) {
        // Opening a Listening List item is presentation-only. It must never
        // prepare or replace the currently loaded enclosure; playback switches
        // only when the user explicitly presses Play or chooses an enclosure.
        listeningListPlayerArticleID = articleID
    }

    private func playListeningListEnclosure(
        articleID: Int64,
        enclosureID: Int64
    ) {
        Task {
            do {
                try await IOSAppRuntime.shared.mediaRuntime
                    .playbackCoordinator.play(enclosureID: enclosureID)
                listeningListStore.reload()
            } catch {
                let coordinator = IOSAppRuntime.shared.mediaRuntime
                    .playbackCoordinator
                playbackState
                    .setErrorMessage(
                        coordinator.lastStartFailureDescription
                            ?? error.localizedDescription
                    )
            }
        }
    }

    @ViewBuilder
    private func articleMediaPlayerView(
        _ presentation: IOSArticleMediaPlayerPresentation
    ) -> some View {
        let audioState = switch presentation.source {
        case .news:
            newsreaderStore.articleAudioActionStates[presentation.article.id]
        case .search:
            searchStore.articleAudioActionStates[presentation.article.id]
        }

        IOSMediaPlayerView(
            playbackState: playbackState,
            transferState: IOSAppRuntime.shared.mediaRuntime.transferPresentationState,
            sleepTimer: IOSAppRuntime.shared.mediaRuntime.playbackCoordinator.sleepTimer,
            playbackCoordinator: IOSAppRuntime.shared.mediaRuntime.playbackCoordinator,
            item: nil,
            downloadEnclosures: audioState?.audioEnclosures.map {
                IOSMediaPlayerDownloadEnclosure(
                    enclosure: $0,
                    download: audioState?.downloads[$0.id]
                )
            } ?? [],
            onDownloadAction: { enclosureID, action in
                handleArticlePlayerDownloadAction(
                    presentation: presentation,
                    enclosureID: enclosureID,
                    action: action
                )
            },
            feedIconFeedID: presentation.article.feedId,
            feedIconTitle: presentation.article.feedTitle,
            feedIconState: { feedID, variant in
                newsreaderStore.feedIconPresentationState(
                    for: feedID,
                    variant: variant
                )
            },
            onRequestFeedIcon: { feedID, variant in
                newsreaderStore.requestFeedIcon(
                    feedID,
                    variant: variant
                )
            },
            showNotesDocument: listeningListStore.showNotesDocument,
            showNotesIsLoading: listeningListStore.showNotesIsLoading,
            showNotesErrorMessage: listeningListStore.showNotesErrorMessage,
            onSelectEnclosure: { _ in },
            onShowNotes: {
                listeningListStore.loadShowNotes(
                    articleID: presentation.article.id
                )
            },
            onDismiss: {
                articleMediaPlayer = nil
            }
        )
    }

    private func handleArticlePlayerDownloadAction(
        presentation: IOSArticleMediaPlayerPresentation,
        enclosureID: Int64,
        action: IOSListeningListPresentation.DownloadAction
    ) {
        Task {
            let result: Result<Void, Error>
            switch (presentation.source, action) {
            case (.news, .download):
                result = await newsreaderStore.requestArticleDownload(
                    articleID: presentation.article.id,
                    enclosureID: enclosureID
                )
            case (.news, .pending), (.news, .downloading):
                result = await newsreaderStore.cancelArticleDownload(
                    articleID: presentation.article.id,
                    enclosureID: enclosureID
                )
            case (.news, .retry):
                result = await newsreaderStore.retryArticleDownload(
                    articleID: presentation.article.id,
                    enclosureID: enclosureID
                )
            case (.news, .delete):
                result = await newsreaderStore.deleteArticleDownload(
                    articleID: presentation.article.id,
                    enclosureID: enclosureID
                )
            case (.search, .download):
                result = await searchStore.requestArticleDownload(
                    articleID: presentation.article.id,
                    enclosureID: enclosureID
                )
            case (.search, .pending), (.search, .downloading):
                result = await searchStore.cancelArticleDownload(
                    articleID: presentation.article.id,
                    enclosureID: enclosureID
                )
            case (.search, .retry):
                result = await searchStore.retryArticleDownload(
                    articleID: presentation.article.id,
                    enclosureID: enclosureID
                )
            case (.search, .delete):
                result = await searchStore.deleteArticleDownload(
                    articleID: presentation.article.id,
                    enclosureID: enclosureID
                )
            case (_, .cancelling), (_, .pendingDeletion):
                return
            }

            switch result {
            case .success:
                break
            case let .failure(error):
                actionError = IOSErrorPresentation.message(
                    for: error,
                    context: .articleAction
                )
            }
        }
    }

    @ViewBuilder
    private var articleMediaDownloadButtons: some View {
        if let choice = articleMediaDownloadChoice {
            ForEach(
                Array(choice.enclosures.enumerated()),
                id: \.element.id
            ) { index, enclosure in
                Button(
                    IOSArticleAudioPresentation.enclosureLabel(
                        enclosure,
                        index: index
                    )
                ) {
                    performArticleDownload(
                        article: choice.article,
                        enclosure: enclosure,
                        source: choice.source
                    )
                    articleMediaDownloadChoice = nil
                }
            }
        }
        Button("Cancel", role: .cancel) {
            articleMediaDownloadChoice = nil
        }
    }

    @ViewBuilder
    private var newsreader: some View {
        NavigationSplitView(columnVisibility: adaptiveSplitColumnVisibility) {
            NewsNavigationView(
                store: newsreaderStore,
                sheetPresented: $navigationPresented,
                presentation: .sidebar,
                onListeningList: openListeningList,
                onSearch: openSearch
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                sidebarMiniPlayer
            }
        } detail: {
            adaptiveDetail
        }
        // These presentations outlive an article-navigation reset.
        .sheet(isPresented: $navigationPresented, onDismiss: {
            if listeningListPendingAfterNavigationSheet {
                listeningListPendingAfterNavigationSheet = false
                listeningListStore.reload()
                listeningListPresented = true
                return
            }
            if searchPendingAfterNavigationSheet {
                searchPendingAfterNavigationSheet = false
                searchPresented = true
            }
        }) {
            NavigationStack {
                NewsNavigationView(
                    store: newsreaderStore,
                    sheetPresented: $navigationPresented,
                    presentation: .sheet,
                    onListeningList: openListeningList,
                    onSearch: openSearch
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { navigationPresented = false }
                    }
                }
            }
        }
        .sheet(isPresented: $settingsPresented) {
            SettingsView(
                store: newsreaderStore,
                bootstrapper: bootstrapper,
                articleListActionPreferences: articleListActionPreferences,
                onDiagnostics: { diagnosticsPresented = true }
            )
        }
    }

    @ViewBuilder
    private var adaptiveDetail: some View {
        Group {
            if usesReaderInspector, let article = readerArticle?.article {
                articleList
                    .inspector(isPresented: readerInspectorBinding) {
                        NavigationStack { readerView(for: article) }
                    }
            } else {
                // Do not install an inactive Inspector presentation hierarchy.
                // On regular-width layouts (including iPhone Duo's inner display)
                // the reader uses an Inspector only while a reader article is
                // actually open. Keeping a dormant Inspector attached to the
                // NavigationSplitView detail needlessly participates in every
                // startup/layout pass.
                articleList
            }
        }
        .toolbar {
            if !adaptivePresentation.usesPersistentSplitNavigation,
               !capsuleCarriesScopeAction {
                ToolbarItem(placement: .topBarLeading) {
                    Button { navigationPresented = true } label: {
                        Image(IOSNavigationButtonPresentation.imageName)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(
                                width: IOSNavigationButtonPresentation.glyphSize,
                                height: IOSNavigationButtonPresentation.glyphSize
                            )
                    }
                    .accessibilityLabel(
                        IOSNavigationButtonPresentation.accessibilityLabel
                    )
                }
            }
        }
    }

    private var listeningListView: some View {
        IOSListeningListView(
            store: listeningListStore,
            playbackState: playbackState,
            transferState: IOSAppRuntime.shared.mediaRuntime.transferPresentationState,
            playbackCoordinator: IOSAppRuntime.shared.mediaRuntime.playbackCoordinator,
            onOpenPlayer: openListeningListPlayer,
            onPlay: playListeningListEnclosure,
            feedIconState: { feedID, variant in
                newsreaderStore.feedIconPresentationState(
                    for: feedID,
                    variant: variant
                )
            },
            onRequestFeedIcon: { feedID, variant in
                newsreaderStore.requestFeedIcon(
                    feedID,
                    variant: variant
                )
            }
        )
    }

    @ViewBuilder
    private var articleList: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            // iPad always uses the stable horizontal regular toolbar path.
            // Vertical-toolbar capability detection is reserved for layouts that
            // can actually move system chrome to a vertical edge.
            articleList(
                systemUsesAdaptiveToolbar: false,
                systemPrefersVerticalToolbar: false
            )
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
        } else {
#if FLUX_HAS_VERTICAL_TOOLBAR_API
            if #available(iOS 27.1, *) {
                IOSArticleListVerticalToolbarCapabilityEnvironment { systemUsesAdaptiveToolbar, systemPrefersVerticalToolbar in
                    articleList(
                        systemUsesAdaptiveToolbar: systemUsesAdaptiveToolbar,
                        systemPrefersVerticalToolbar: systemPrefersVerticalToolbar
                    )
                    .toolbarMinimizationBehavior(
                        systemPrefersVerticalToolbar ? .never : .automatic,
                        for: .navigationBar
                    )
                }
            } else {
                articleList(
                    systemUsesAdaptiveToolbar: false,
                    systemPrefersVerticalToolbar: false
                )
            }
#else
            articleList(
                systemUsesAdaptiveToolbar: false,
                systemPrefersVerticalToolbar: false
            )
#endif
        }
    }

    private func articleList(
        systemUsesAdaptiveToolbar: Bool,
        systemPrefersVerticalToolbar: Bool
    ) -> some View {
        let actionPlacement: IOSArticleListActionPlacement = if
            UIDevice.current.userInterfaceIdiom == .pad,
            articleListChromeMode == .persistentSplit
                || articleListChromeMode == .persistentSplitCollapsed
        {
            .topBarTrailing
        } else {
            IOSArticleListChromePresentation.actionPlacement(
                for: articleListChromeMode,
                systemPrefersVerticalToolbar: systemPrefersVerticalToolbar,
                systemUsesAdaptiveToolbar: systemUsesAdaptiveToolbar
            )
        }
        let usesNativeTopEdgeEffect = IOSArticleListChromePresentation.usesNativeTopEdgeEffect(
            for: articleListChromeMode,
            systemPrefersVerticalToolbar: systemPrefersVerticalToolbar
        )
        let directActionCapacity = IOSArticleListChromePresentation.configurableDirectActionCapacity(
            for: articleListChromeMode,
            systemPrefersVerticalToolbar: systemPrefersVerticalToolbar
        )
        let compactPortraitBottomInset = IOSCompactPortraitBottomInsetPolicy.presentation(
            chromeMode: articleListChromeMode,
            actionPlacement: actionPlacement,
            miniPlayerIsVisible: miniPlayerIsVisible
        )

        return ArticleListNavigationChrome(
            store: newsreaderStore,
            onSelectScope: presentArticleListNavigation,
            chromeMode: articleListChromeMode,
            actionPlacement: actionPlacement,
            systemUsesAdaptiveToolbar: systemUsesAdaptiveToolbar,
            systemPrefersVerticalToolbar: systemPrefersVerticalToolbar,
            topActions: {
                articleListActionButtons(directCapacity: directActionCapacity)
            },
            topAccessory: {
                if miniPlayerPlacement == .compactTopBar {
                    if articleListChromeMode == .compactLandscape {
                        compactMiniPlayer
                    } else if articleListChromeMode == .persistentSplitCollapsed {
                        if systemPrefersVerticalToolbar {
                            regularFloatingMiniPlayer
                        } else {
                            compactMiniPlayer
                        }
                    }
                }
            },
            content: { naturalTopContentInset in
                ArticleListView(
                    store: newsreaderStore,
                    naturalTopContentInset: naturalTopContentInset,
                    usesNativeTopEdgeEffect: usesNativeTopEdgeEffect,
                    onArticleTap: openArticle,
                    onArticleAction: handleArticleAction,
                    onArticleMediaAction: handleArticleMediaAction
                )
            }
        )
            .navigationBarTitleDisplayMode(IOSArticleNavigationPresentation.titleDisplayMode)
            .toolbar(
                IOSArticleListChromePresentation.navigationBarVisibility(
                    for: articleListChromeMode,
                    systemPrefersVerticalToolbar: systemPrefersVerticalToolbar,
                    systemUsesAdaptiveToolbar: systemUsesAdaptiveToolbar
                ),
                for: .navigationBar
            )
            // A collapsed split view pushes the detail and offers a back button.
            // The Timeline is the root of this app's navigation: the branded
            // button opens the scope chooser, there is nothing to go back to.
            .navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                switch compactPortraitBottomInset {
                case .standaloneMiniPlayer:
                    IOSStandalonePortraitMiniPlayerDock(
                        playbackState: playbackState,
                        playbackCoordinator: IOSAppRuntime.shared.mediaRuntime.playbackCoordinator,
                        onOpenPlayer: presentNowPlayingPlayer
                    )
                case .combinedMiniPlayerAndActions:
                    IOSArticleListBottomDock(
                        playbackState: playbackState,
                        playbackCoordinator: IOSAppRuntime.shared.mediaRuntime.playbackCoordinator,
                        onOpenPlayer: presentNowPlayingPlayer
                    ) {
                        articleListActionButtons(
                            directCapacity: directActionCapacity,
                            minimumHitTarget: 44
                        )
                    }
                case .none:
                    EmptyView()
                }
            }
            .toolbar {
                if actionPlacement == .bottomBar,
                   !miniPlayerIsVisible {
                    ToolbarItemGroup(placement: .bottomBar) {
                        articleListActionButtons(
                            directCapacity: directActionCapacity
                        )
                    }
                }
                if actionPlacement == .topBarTrailing {
                    if #available(iOS 26.0, *) {
                        // Keep all actions in one native group. The system owns
                        // horizontal/vertical placement and overflow behavior.
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            articleListActionButtons(directCapacity: directActionCapacity)
                        }
                    } else {
                        ToolbarItem(placement: .topBarTrailing) {
                            HStack(spacing: IOSArticleListActionChromeMetrics.floatingSpacing) {
                                articleListActionButtons(directCapacity: directActionCapacity)
                            }
                            .padding(.horizontal, IOSArticleListActionChromeMetrics.floatingHorizontalPadding)
                            .padding(.vertical, IOSArticleListActionChromeMetrics.floatingVerticalPadding)
                            .background(.regularMaterial, in: Capsule())
                        }
                    }
                }
            }
    }

    private var miniPlayerIsVisible: Bool {
        IOSMiniPlayerPresentation.isVisible(
            loadedEnclosureID: playbackState.loadedEnclosure?.id,
            status: playbackState.status
        )
    }

    @ViewBuilder
    private var compactMiniPlayer: some View {
        if miniPlayerIsVisible {
            IOSMiniPlayerView(
                playbackState: playbackState,
                playbackCoordinator: IOSAppRuntime.shared.mediaRuntime.playbackCoordinator,
                style: UIDevice.current.userInterfaceIdiom == .pad
                    ? .regularToolbar
                    : articleListChromeMode == .compactLandscape
                        ? .expandedLandscapeTopBar
                        : .compactTopBar,
                onOpen: presentNowPlayingPlayer
            )
        }
    }

    @ViewBuilder
    private var regularFloatingMiniPlayer: some View {
        if miniPlayerIsVisible {
            IOSMiniPlayerView(
                playbackState: playbackState,
                playbackCoordinator: IOSAppRuntime.shared.mediaRuntime.playbackCoordinator,
                style: .regularToolbar,
                onOpen: presentNowPlayingPlayer
            )
        }
    }

    @ViewBuilder
    private var sidebarMiniPlayer: some View {
        if miniPlayerPlacement == .sidebarFooter,
           miniPlayerIsVisible {
            IOSMiniPlayerView(
                playbackState: playbackState,
                playbackCoordinator: IOSAppRuntime.shared.mediaRuntime.playbackCoordinator,
                style: .sidebarFooter,
                onOpen: presentNowPlayingPlayer
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func presentNowPlayingPlayer() {
        guard miniPlayerIsVisible else { return }
        nowPlayingPresented = true
    }

    @ViewBuilder
    private func articleListActionButtons(
        directCapacity: Int,
        minimumHitTarget: CGFloat? = nil
    ) -> some View {
        Group {
            IOSSyncToolbarButton(
                state: IOSSyncButtonPresentation.resolve(
                    manualSyncState: newsreaderStore.manualSyncState,
                    transientState: syncPresentation
                ),
                action: performManualSyncControlAction
            )
            articleListConfigurableActionButtons(
                directCapacity: directCapacity,
                minimumHitTarget: minimumHitTarget
            )
        }
        // Consistent semantic action color across native toolbars and the
        // portrait mini-player dock; selected/destructive menu content keeps
        // its own explicit styling.
        .tint(.primary)
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func articleListConfigurableActionButtons(
        directCapacity: Int,
        minimumHitTarget: CGFloat? = nil
    ) -> some View {
        let resolved = IOSArticleListActionPolicy.resolvedActions(
            configuredActions: articleListActionPreferences.actions,
            directCapacity: directCapacity,
            scope: newsreaderStore.scope,
            hasNextScope: nextScope != nil,
            hasLoadedMedia: playbackState.loadedEnclosure != nil,
            playbackStatus: playbackState.status
        )

        ForEach(resolved.direct) { action in
            articleListActionButton(
                action,
                minimumHitTarget: minimumHitTarget
            )
        }
        articleListMoreMenu(
            overflowActions: resolved.overflow,
            minimumHitTarget: minimumHitTarget
        )
    }

    @ViewBuilder
    private func articleListActionButton(
        _ action: IOSBottomAction,
        minimumHitTarget: CGFloat? = nil
    ) -> some View {
        Group {
            switch action {
        case .sync:
            IOSSyncToolbarButton(
                state: IOSSyncButtonPresentation.resolve(
                    manualSyncState: newsreaderStore.manualSyncState,
                    transientState: syncPresentation
                ),
                action: performManualSyncControlAction
            )

        case .filterAndSort:
            Menu {
                filterAndSortMenuContent
            } label: {
                Label("Filter and Sort", systemImage: action.symbolName)
            }
            .accessibilityIdentifier("articleList.filterSort")

        case .toggleReadFilter:
            Button {
                newsreaderStore.setUnreadOnly(!newsreaderStore.unreadOnly)
            } label: {
                Image(systemName: action.symbolName)
                    .frame(width: 24, height: 24)
            }
            .accessibilityLabel(
                newsreaderStore.unreadOnly
                    ? String(localized: "Show All Articles")
                    : String(localized: "Show Unread Only")
            )
            .accessibilityIdentifier("articleList.toggleReadFilter")

        case .toggleSortOrder:
            Button {
                newsreaderStore.setNewestFirst(!newsreaderStore.newestFirst)
            } label: {
                Image(systemName: action.symbolName)
                    .frame(width: 24, height: 24)
            }
            .accessibilityLabel(
                newsreaderStore.newestFirst
                    ? String(localized: "Show Oldest First")
                    : String(localized: "Show Newest First")
            )
            .accessibilityIdentifier("articleList.toggleSortOrder")

        case .search:
            Button(action: openSearch) {
                Image(systemName: action.symbolName)
                    .frame(width: 24, height: 24)
            }
            .accessibilityLabel(action.settingsTitle)
            .accessibilityIdentifier("articleList.search")

        case .markAllRead:
            Button { presentMarkReadConfirmation(.read) } label: {
                Image(systemName: action.symbolName)
                    .frame(width: 24, height: 24)
            }
            .accessibilityLabel(action.settingsTitle)
            .accessibilityIdentifier("articleList.markAllRead")

        case .markAllReadAndNext:
            Button { presentMarkReadConfirmation(.readAndNext) } label: {
                Image(systemName: action.symbolName)
                    .frame(width: 24, height: 24)
            }
            .accessibilityLabel(action.settingsTitle)
            .accessibilityIdentifier("articleList.markAllReadAndNext")

        case .listeningList:
            Button(action: openListeningList) {
                Image(systemName: action.symbolName)
                    .frame(width: 24, height: 24)
            }
            .accessibilityLabel(action.settingsTitle)
            .accessibilityIdentifier("articleList.listeningList")

        case .nowPlaying:
            Button { nowPlayingPresented = true } label: {
                Image(systemName: action.symbolName)
                    .frame(width: 24, height: 24)
            }
            .accessibilityLabel("Now Playing")
            .accessibilityIdentifier("articleList.nowPlaying")

        case .settings:
            Button { settingsPresented = true } label: {
                Image(systemName: action.symbolName)
                    .frame(width: 24, height: 24)
            }
            .accessibilityLabel(action.settingsTitle)
            .accessibilityIdentifier("articleList.settings")

            case .more:
                EmptyView()
            }
        }
        .frame(
            minWidth: minimumHitTarget,
            minHeight: minimumHitTarget
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var filterAndSortMenuContent: some View {
        Section("Show") {
            Button { newsreaderStore.setUnreadOnly(true) } label: {
                filterMenuLabel(String(localized: "Unread Only"), selected: newsreaderStore.unreadOnly)
            }
            Button { newsreaderStore.setUnreadOnly(false) } label: {
                filterMenuLabel(String(localized: "All Articles"), selected: !newsreaderStore.unreadOnly)
            }
        }
        Section("Sort") {
            Button { newsreaderStore.setNewestFirst(true) } label: {
                filterMenuLabel(String(localized: "Newest First"), selected: newsreaderStore.newestFirst)
            }
            Button { newsreaderStore.setNewestFirst(false) } label: {
                filterMenuLabel(String(localized: "Oldest First"), selected: !newsreaderStore.newestFirst)
            }
        }
    }

    @ViewBuilder
    private func articleListMoreMenu(
        overflowActions: [IOSBottomAction],
        minimumHitTarget: CGFloat? = nil
    ) -> some View {
        Menu {
            ForEach(overflowActions) { action in
                overflowMenuItem(action)
            }
        } label: {
            Label("More", systemImage: IOSBottomAction.more.symbolName)
        }
        .accessibilityLabel(String(localized: "More"))
        .accessibilityIdentifier("articleList.more")
        .frame(
            minWidth: minimumHitTarget,
            minHeight: minimumHitTarget
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func overflowMenuItem(_ action: IOSBottomAction) -> some View {
        switch action {
        case .filterAndSort:
            Menu {
                filterAndSortMenuContent
            } label: {
                Label(action.settingsTitle, systemImage: action.symbolName)
            }

        case .toggleReadFilter:
            Button {
                newsreaderStore.setUnreadOnly(!newsreaderStore.unreadOnly)
            } label: {
                Label(
                    newsreaderStore.unreadOnly
                        ? String(localized: "Show All Articles")
                        : String(localized: "Show Unread Only"),
                    systemImage: action.symbolName
                )
            }

        case .toggleSortOrder:
            Button {
                newsreaderStore.setNewestFirst(!newsreaderStore.newestFirst)
            } label: {
                Label(
                    newsreaderStore.newestFirst
                        ? String(localized: "Show Oldest First")
                        : String(localized: "Show Newest First"),
                    systemImage: action.symbolName
                )
            }

        case .search:
            Button(action: openSearch) {
                Label(action.settingsTitle, systemImage: action.symbolName)
            }

        case .markAllRead:
            Button(role: .destructive) {
                presentMarkReadConfirmation(.read)
            } label: {
                Label(action.settingsTitle, systemImage: action.symbolName)
            }

        case .markAllReadAndNext:
            Button(role: .destructive) {
                presentMarkReadConfirmation(.readAndNext)
            } label: {
                Label(action.settingsTitle, systemImage: action.symbolName)
            }

        case .listeningList:
            Button(action: openListeningList) {
                Label(action.settingsTitle, systemImage: action.symbolName)
            }

        case .nowPlaying:
            Button { nowPlayingPresented = true } label: {
                Label(action.settingsTitle, systemImage: action.symbolName)
            }

        case .settings:
            Button { settingsPresented = true } label: {
                Label(action.settingsTitle, systemImage: action.symbolName)
            }

        case .sync, .more:
            EmptyView()
        }
    }

    private func presentArticleListNavigation() {
        if adaptivePresentation.usesPersistentSplitNavigation {
            splitColumnVisibility = .all
        } else {
            navigationPresented = true
        }
    }

    private func performManualSyncControlAction() {
        switch newsreaderStore.manualSyncState {
        case .running:
            syncPresentationGeneration &+= 1
            syncPresentation = .idle
            newsreaderStore.cancelManualSync()
        case .idle, .cancelling:
            Task { await performManualSync() }
        }
    }

    private func performManualSync() async {
        syncPresentationGeneration &+= 1
        let generation = syncPresentationGeneration
        syncPresentation = .idle

        await newsreaderStore.syncManually()

        guard IOSSyncButtonPresentation.canEndSuccess(
            generation: generation,
            currentGeneration: syncPresentationGeneration,
            isSyncing: newsreaderStore.isSyncing
        ) else { return }
        guard newsreaderStore.errorMessage == nil else {
            syncPresentation = .idle
            return
        }

        syncPresentation = .success
        do {
            try await Task.sleep(for: .milliseconds(1500))
        } catch {
            return
        }
        guard IOSSyncButtonPresentation.canEndSuccess(
            generation: generation,
            currentGeneration: syncPresentationGeneration,
            isSyncing: newsreaderStore.isSyncing
        ) else { return }
        syncPresentation = .idle
    }

    private var searchView: some View {
        SearchView(
            store: searchStore,
            newsreaderStore: newsreaderStore,
            onArticleTap: openSearchArticle,
            onArticleAction: handleSearchArticleAction,
            onArticleMediaAction: handleSearchArticleMediaAction,
            onSetRead: { article, read in
                searchStore.setRead(article, read: read)
            },
            onSetStarred: { article, starred in
                searchStore.setStarred(article, starred: starred)
            }
        )
    }

    @ViewBuilder
    private func actionFeedbackOverlay(
        active: Bool,
        hasBottomActionBar: Bool,
        hasMiniPlayer: Bool
    ) -> some View {
        if active, let feedback = actionFeedback {
            IOSActionFeedbackBanner(item: feedback)
                .padding(.horizontal, 16)
                .safeAreaPadding(
                    .bottom,
                    IOSActionFeedbackPresentation.bottomPadding(
                        hasBottomActionBar: hasBottomActionBar,
                        hasMiniPlayer: hasMiniPlayer
                    )
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: feedback.id) {
                    do {
                        try await Task.sleep(
                            for: IOSActionFeedbackPresentation.autoDismissDelay
                        )
                    } catch {
                        return
                    }
                    guard !Task.isCancelled,
                          IOSActionFeedbackPresentation.shouldDismiss(
                            current: actionFeedback,
                            id: feedback.id
                          ) else {
                        return
                    }
                    actionFeedback = nil
                }
        }
    }

    private func showActionFeedback(_ kind: IOSActionFeedbackKind) {
        actionFeedbackGeneration &+= 1
        actionFeedback = IOSActionFeedbackItem(
            id: actionFeedbackGeneration,
            kind: kind
        )
    }

    private func openListeningList() {
        searchPendingAfterNavigationSheet = false
        guard navigationPresented else {
            listeningListStore.reload()
            listeningListPresented = true
            return
        }
        listeningListPendingAfterNavigationSheet = true
        navigationPresented = false
    }

    private func openSearch() {
        listeningListPendingAfterNavigationSheet = false
        // Presenting while the navigation sheet is still dismissing loses the
        // presentation, so its dismissal callback performs it.
        guard navigationPresented else {
            searchPresented = true
            return
        }
        searchPendingAfterNavigationSheet = true
        navigationPresented = false
    }

    private func normalizeAdaptiveShell(for presentation: AdaptivePresentation) {
        navigationPresented = AdaptiveShellTransitionPolicy.navigationSheetPresented(
            after: presentation,
            wasPresented: navigationPresented
        )
        splitColumnVisibility = AdaptiveShellTransitionPolicy.splitColumnVisibility(after: presentation)
    }

    private func handleWidgetURL(_ url: URL) {
        guard let action = WidgetAction(url: url) else { return }
        guard newsreaderStore.core != nil else {
            pendingWidgetAction = action
            return
        }
        performWidgetAction(action)
    }

    private func performWidgetAction(_ action: WidgetAction) {
        switch action {
        case let .article(articleID):
            newsreaderStore.article(withID: articleID) { article in
                guard let article else { return }
                openArticle(article)
            }
        case let .open(selection):
            newsreaderStore.openWidgetScope(selection)
        case .sync:
            newsreaderStore.syncFromWidget()
        }
    }

    private func consumePendingWidgetActionIfReady() {
        guard newsreaderStore.core != nil, let action = pendingWidgetAction else { return }
        pendingWidgetAction = nil
        performWidgetAction(action)
    }

    private func openArticle(_ article: ArticleSummary) {
        switch ArticleOpenRouting.action(clickOnNews: newsreaderStore.clickOnNews, openInMiniflux: false) {
        case .detail:
            openReader(article)
            return
        case .original, .miniflux:
            openOriginalArticle(article)
            return
        }
    }

    private func openOriginalArticle(_ article: ArticleSummary) {
        articleOpenGeneration += 1
        let generation = articleOpenGeneration
        newsreaderStore.open(article) { original in
            guard let url = ArticleOpenRoutingPolicy.validWebURL(original) else {
                present(.invalid)
                return
            }
            UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { succeeded in
                Task { @MainActor in
                    guard generation == articleOpenGeneration else { return }
                    present(ArticleOpenRoutingPolicy.destination(originalURL: original, universalLinkSucceeded: succeeded))
                }
            }
        }
    }

    private func openSearchArticle(_ article: ArticleSummary) {
        switch ArticleOpenRouting.action(clickOnNews: newsreaderStore.clickOnNews, openInMiniflux: false) {
        case .detail: openSearchReader(article)
        case .original, .miniflux: openSearchOriginalArticle(article)
        }
    }

    private func openSearchOriginalArticle(_ article: ArticleSummary) {
        articleOpenGeneration += 1
        let generation = articleOpenGeneration
        searchStore.open(article) { original in
            guard let url = ArticleOpenRoutingPolicy.validWebURL(original) else {
                present(.invalid)
                return
            }
            UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { succeeded in
                Task { @MainActor in
                    guard generation == articleOpenGeneration else { return }
                    present(ArticleOpenRoutingPolicy.destination(originalURL: original, universalLinkSucceeded: succeeded))
                }
            }
        }
    }

    private func handleArticleAction(_ article: ArticleSummary, _ action: IOSArticleContextAction) {
        switch action {
        case .starred:
            newsreaderStore.setStarred(article, starred: !article.isStarred)
        case .read:
            newsreaderStore.setRead(article, read: !article.isRead)
        case .original:
            openOriginalArticle(article)
        case .reader:
            openReader(article)
        case .miniflux:
            newsreaderStore.minifluxEntryURL(for: article) { result in
                switch result {
                case let .success(value):
                    guard let url = ArticleOpenRoutingPolicy.validWebURL(value) else {
                         actionError = String(localized: "Flux could not resolve a valid Miniflux entry URL.")
                        return
                    }
                    browser = IOSBrowserURL(url: url)
                case let .failure(error): actionError = IOSErrorPresentation.message(for: error, context: .articleAction)
                }
            }
        case .comments:
            guard let url = IOSArticleContextMenuPolicy.commentsURL(article.commentsUrl) else { return }
            browser = IOSBrowserURL(url: url)
        case .copyLink:
            UIPasteboard.general.string = article.url
             showActionFeedback(.linkCopied)
        case .share:
            guard let url = IOSArticleContextMenuPolicy.originalURL(article.url) else {
                 actionError = String(localized: "The article does not have a valid web URL.")
                return
            }
            sharePayload = IOSSharePayload(items: [article.title, url])
        case .saveToService:
            newsreaderStore.saveToService(article) { result in
                switch result {
                case let .success(value):
                    if IOSArticleActionHapticPolicy.shouldConfirmSaveToService(value) {
                        saveToServiceFeedbackTrigger &+= 1
                    }
                    switch value {
                    case .saved:
                        showActionFeedback(.savedToService)
                    case .noIntegrationConfigured:
                        showActionFeedback(.noThirdPartyIntegration)
                    }
                case let .failure(error):
                    actionError = IOSErrorPresentation.message(for: error, context: .articleAction)
                }
            }
        }
    }

    private func handleArticleMediaAction(
        _ article: ArticleSummary,
        _ action: IOSArticleMediaAction
    ) {
        switch action {
        case let .play(enclosureID):
            articleMediaPlayer = .init(
                article: article,
                enclosureID: enclosureID,
                source: .news
            )
            Task {
                do {
                    try await IOSAppRuntime.shared.mediaRuntime
                        .playbackCoordinator.play(enclosureID: enclosureID)
                } catch {
                    let coordinator = IOSAppRuntime.shared.mediaRuntime
                        .playbackCoordinator
                    actionError = coordinator.lastStartFailureDescription
                        ?? error.localizedDescription
                    articleMediaPlayer = nil
                }
            }

        case let .setListeningList(enabled):
            Task {
                let result = await newsreaderStore
                    .setArticleListeningListMembership(
                        articleID: article.id,
                        isInListeningList: enabled
                    )
                presentArticleMediaMutationResult(
                    result,
                    success: enabled
                        ? .addedToListeningList
                        : .removedFromListeningList
                )
            }

        case let .requestDownload(enclosureID):
            Task {
                let result = await newsreaderStore.requestArticleDownload(
                    articleID: article.id,
                    enclosureID: enclosureID
                )
                presentArticleMediaMutationResult(
                    result,
                    success: .downloadRequested
                )
            }

        case let .cancelDownload(enclosureID):
            Task {
                let result = await newsreaderStore.cancelArticleDownload(
                    articleID: article.id,
                    enclosureID: enclosureID
                )
                presentArticleMediaMutationResult(
                    result,
                    success: .downloadCancelled
                )
            }

        case let .retryDownload(enclosureID):
            Task {
                let result = await newsreaderStore.retryArticleDownload(
                    articleID: article.id,
                    enclosureID: enclosureID
                )
                presentArticleMediaMutationResult(
                    result,
                    success: .downloadRequested
                )
            }

        case let .deleteDownload(enclosureID):
            Task {
                let result = await newsreaderStore.deleteArticleDownload(
                    articleID: article.id,
                    enclosureID: enclosureID
                )
                presentArticleMediaMutationResult(
                    result,
                    success: .downloadDeletionRequested
                )
            }

        case .configuredDownloadAudio:
            let enclosures = IOSArticleAudioPresentation.downloadableEnclosures(
                newsreaderStore.articleAudioActionStates[article.id]
            )
            if enclosures.count == 1, let enclosure = enclosures.first {
                performArticleDownload(
                    article: article,
                    enclosure: enclosure,
                    source: .news
                )
            } else if !enclosures.isEmpty {
                articleMediaDownloadChoice = .init(
                    article: article,
                    enclosures: enclosures,
                    source: .news
                )
            }
        }
    }

    private func performArticleDownload(
        article: ArticleSummary,
        enclosure: Enclosure,
        source: IOSArticleMediaSource
    ) {
        let state = switch source {
        case .news:
            newsreaderStore.articleAudioActionStates[article.id]
        case .search:
            searchStore.articleAudioActionStates[article.id]
        }
        let action = IOSArticleAudioPresentation.downloadAction(
            state?.downloads[enclosure.id]
        )

        Task {
            let result: Result<Void, Error>
            switch (source, action) {
            case (.news, .retry):
                result = await newsreaderStore.retryArticleDownload(
                    articleID: article.id,
                    enclosureID: enclosure.id
                )
            case (.news, .download):
                result = await newsreaderStore.requestArticleDownload(
                    articleID: article.id,
                    enclosureID: enclosure.id
                )
            case (.search, .retry):
                result = await searchStore.retryArticleDownload(
                    articleID: article.id,
                    enclosureID: enclosure.id
                )
            case (.search, .download):
                result = await searchStore.requestArticleDownload(
                    articleID: article.id,
                    enclosureID: enclosure.id
                )
            case (_, .pending), (_, .delete), (_, .pendingDeletion):
                return
            }
            presentArticleMediaMutationResult(
                result,
                success: .downloadRequested
            )
        }
    }

    private func presentArticleMediaMutationResult(
        _ result: Result<Void, Error>,
        success: IOSActionFeedbackKind
    ) {
        switch result {
        case .success:
            showActionFeedback(success)
        case let .failure(error):
            actionError = IOSErrorPresentation.message(
                for: error,
                context: .articleAction
            )
        }
    }

    private func handleSearchArticleMediaAction(
        _ article: ArticleSummary,
        _ action: IOSArticleMediaAction
    ) {
        switch action {
        case let .play(enclosureID):
            articleMediaPlayer = .init(
                article: article,
                enclosureID: enclosureID,
                source: .search
            )
            Task {
                do {
                    try await IOSAppRuntime.shared.mediaRuntime
                        .playbackCoordinator.play(enclosureID: enclosureID)
                } catch {
                    let coordinator = IOSAppRuntime.shared.mediaRuntime
                        .playbackCoordinator
                    actionError = coordinator.lastStartFailureDescription
                        ?? error.localizedDescription
                    articleMediaPlayer = nil
                }
            }

        case let .setListeningList(enabled):
            Task {
                let result = await searchStore
                    .setArticleListeningListMembership(
                        articleID: article.id,
                        isInListeningList: enabled
                    )
                presentArticleMediaMutationResult(
                    result,
                    success: enabled
                        ? .addedToListeningList
                        : .removedFromListeningList
                )
            }

        case let .requestDownload(enclosureID):
            Task {
                let result = await searchStore.requestArticleDownload(
                    articleID: article.id,
                    enclosureID: enclosureID
                )
                presentArticleMediaMutationResult(
                    result,
                    success: .downloadRequested
                )
            }

        case let .cancelDownload(enclosureID):
            Task {
                let result = await searchStore.cancelArticleDownload(
                    articleID: article.id,
                    enclosureID: enclosureID
                )
                presentArticleMediaMutationResult(
                    result,
                    success: .downloadCancelled
                )
            }

        case let .retryDownload(enclosureID):
            Task {
                let result = await searchStore.retryArticleDownload(
                    articleID: article.id,
                    enclosureID: enclosureID
                )
                presentArticleMediaMutationResult(
                    result,
                    success: .downloadRequested
                )
            }

        case let .deleteDownload(enclosureID):
            Task {
                let result = await searchStore.deleteArticleDownload(
                    articleID: article.id,
                    enclosureID: enclosureID
                )
                presentArticleMediaMutationResult(
                    result,
                    success: .downloadDeletionRequested
                )
            }

        case .configuredDownloadAudio:
            let enclosures = IOSArticleAudioPresentation.downloadableEnclosures(
                searchStore.articleAudioActionStates[article.id]
            )
            if enclosures.count == 1, let enclosure = enclosures.first {
                performArticleDownload(
                    article: article,
                    enclosure: enclosure,
                    source: .search
                )
            } else if !enclosures.isEmpty {
                articleMediaDownloadChoice = .init(
                    article: article,
                    enclosures: enclosures,
                    source: .search
                )
            }
        }
    }

    private func handleSearchArticleAction(_ article: ArticleSummary, _ action: IOSArticleContextAction) {
        switch action {
        case .starred: searchStore.setStarred(article, starred: !article.isStarred)
        case .read: searchStore.setRead(article, read: !article.isRead)
        case .original: openSearchOriginalArticle(article)
        case .reader: openSearchReader(article)
        case .miniflux: openMiniflux(article, using: searchStore)
        case .comments:
            guard let url = IOSArticleContextMenuPolicy.commentsURL(article.commentsUrl) else { return }
            browser = IOSBrowserURL(url: url)
        case .copyLink:
            UIPasteboard.general.string = article.url
             showActionFeedback(.linkCopied)
        case .share:
             guard let url = IOSArticleContextMenuPolicy.originalURL(article.url) else { actionError = String(localized: "The article does not have a valid web URL."); return }
            sharePayload = IOSSharePayload(items: [article.title, url])
        case .saveToService:
            searchStore.saveToService(article) { result in
                switch result {
                case let .success(value):
                    if IOSArticleActionHapticPolicy.shouldConfirmSaveToService(value) {
                        saveToServiceFeedbackTrigger &+= 1
                    }
                    switch value {
                    case .saved:
                        showActionFeedback(.savedToService)
                    case .noIntegrationConfigured:
                        showActionFeedback(.noThirdPartyIntegration)
                    }
                case let .failure(error):
                    actionError = IOSErrorPresentation.message(for: error, context: .articleAction)
                }
            }
        }
    }

    private func openMiniflux(_ article: ArticleSummary, using store: IOSSearchStore) {
        store.minifluxEntryURL(for: article) { result in
            switch result {
            case let .success(value):
                guard let url = ArticleOpenRoutingPolicy.validWebURL(value) else { actionError = String(localized: "Flux could not resolve a valid Miniflux entry URL."); return }
                browser = IOSBrowserURL(url: url)
            case let .failure(error): actionError = IOSErrorPresentation.message(for: error, context: .articleAction)
            }
        }
    }

    private func openReader(_ article: ArticleSummary) {
        readerGeneration += 1
        let generation = readerGeneration
        readerArticle = IOSReaderArticle(article: article)
        readerDocument = nil
        readerErrorMessage = nil
        readerIsLoading = true
        newsreaderStore.openReader(article) { result in
            guard generation == readerGeneration else { return }
            readerIsLoading = false
            switch result {
            case let .success(document): readerDocument = document
            case let .failure(error): readerErrorMessage = IOSErrorPresentation.message(for: error, context: .reader)
            }
        }
    }

    private func openSearchReader(_ article: ArticleSummary) {
        readerGeneration += 1
        let generation = readerGeneration
        readerArticle = IOSReaderArticle(article: article)
        readerDocument = nil
        readerErrorMessage = nil
        readerIsLoading = true
        searchStore.openReader(article) { result in
            guard generation == readerGeneration else { return }
            readerIsLoading = false
            switch result {
            case let .success(document): readerDocument = document
            case let .failure(error): readerErrorMessage = IOSErrorPresentation.message(for: error, context: .reader)
            }
        }
    }

    private func present(_ destination: ArticleOpenDestination) {
        switch destination {
        case .universalLink: break
        case .browser(let url): browser = IOSBrowserURL(url: url)
        case .invalid: articleOpenError = String(localized: "The article does not have a valid web URL.")
        }
    }

    @ViewBuilder
    private func filterMenuLabel(_ title: String, selected: Bool) -> some View {
        if selected { Label(title, systemImage: "checkmark") }
        else { Text(title) }
    }

    private var markReadDialogTitle: String {
        markReadWorkflow == .readAndNext ? String(localized: "Mark All as Read and Continue") : String(localized: "Mark All as Read")
    }

    private var nextScope: BrowserScope? {
        IOSScopeNavigation.nextScope(
            after: newsreaderStore.scope,
            catalog: newsreaderStore.catalog,
            hidingEmpty: newsreaderStore.hideEmptyNavigationEntries,
            counts: newsreaderStore.feedCounts
        )
    }

    private func presentMarkReadConfirmation(_ workflow: IOSMarkReadWorkflow) {
        markReadWorkflow = workflow
        markReadConfirmationPresented = true
    }

    private func performMarkReadWorkflow() {
        let target = markReadWorkflow == .readAndNext ? nextScope : nil
        newsreaderStore.markCurrentScopeAsRead { succeeded in
            guard succeeded, let target else { return }
            newsreaderStore.select(target)
        }
    }
}

extension ContentView {
    private var usesReaderInspector: Bool {
        adaptivePresentation.readerPresentationKind == .inspector
    }

    /// The browser, reader and share sheets follow whichever surface is
    /// frontmost. A view can present only one sheet, so exactly one side — the
    /// root or the search sheet — is active at a time.
    private func gatedBrowser(active: Bool) -> Binding<IOSBrowserURL?> {
        Binding(get: { active ? browser : nil }, set: { if active { browser = $0 } })
    }

    private func gatedShare(active: Bool) -> Binding<IOSSharePayload?> {
        Binding(get: { active ? sharePayload : nil }, set: { if active { sharePayload = $0 } })
    }

    private func gatedReaderSheet(active: Bool) -> Binding<IOSReaderArticle?> {
        Binding(
            get: { active && !usesReaderInspector ? readerArticle : nil },
            set: { if $0 == nil, active, !usesReaderInspector { dismissReader() } }
        )
    }

    private var readerInspectorBinding: Binding<Bool> {
        Binding(
            get: { usesReaderInspector && readerArticle != nil },
            set: { if !$0, usesReaderInspector { dismissReader() } }
        )
    }

    @ViewBuilder
    private func readerView(for article: ArticleSummary) -> some View {
        VStack(spacing: 0) {
            ReaderArticleHeader(article: article)
            Group {
                if readerIsLoading {
                    ProgressView("Loading article...")
                } else if let readerErrorMessage {
                    ContentUnavailableView("Unable to load article", systemImage: "exclamationmark.triangle", description: Text(readerErrorMessage))
                } else if let readerDocument {
                    ScrollView { ReaderDocumentContent(document: readerDocument, openOriginal: { openOriginal(article) }) }
                } else {
                    ContentUnavailableView("No article selected", systemImage: "doc.text")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.openURL, OpenURLAction { url in
            UIApplication.shared.open(url, options: [:])
            return .handled
        })
        .background(.background)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(IOSReaderDismissalPresentation.title, action: dismissReader)
            }
        }
    }

    private func dismissReader() {
        readerArticle = nil
        readerGeneration += 1
    }

    private func openOriginal(_ article: ArticleSummary) {
        guard let url = ArticleOpenRoutingPolicy.validWebURL(article.url) else {
            readerErrorMessage = String(localized: "The article does not have a valid web URL.")
            return
        }
        UIApplication.shared.open(url, options: [:])
    }
}

private struct IOSSyncToolbarButton: View {
    let state: IOSSyncButtonPresentation.State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: IOSSyncButtonPresentation.symbolName(for: state))
                .frame(width: 24, height: 24)
        }
        .accessibilityLabel(IOSSyncButtonPresentation.accessibilityLabel(for: state))
        .accessibilityValue(IOSSyncButtonPresentation.accessibilityValue(for: state))
        .accessibilityIdentifier("articleList.sync")
    }
}
