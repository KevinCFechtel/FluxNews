import SwiftUI

struct SearchView: View {
    @ObservedObject var store: IOSSearchStore
    var newsreaderStore: NewsreaderStore
    let onArticleTap: (ArticleSummary) -> Void
    let onArticleAction: (ArticleSummary, IOSArticleContextAction) -> Void
    let onArticleMediaAction: (ArticleSummary, IOSArticleMediaAction) -> Void
    let onSetRead: (ArticleSummary, Bool) -> Void
    let onSetStarred: (ArticleSummary, Bool) -> Void
    @State private var searchInterfacePresented = true

    var body: some View {
        SearchResultsContent(
            store: store,
            newsreaderStore: newsreaderStore,
            onArticleTap: onArticleTap,
            onArticleAction: onArticleAction,
            onArticleMediaAction: onArticleMediaAction,
            onSetRead: onSetRead,
            onSetStarred: onSetStarred
        )
        .navigationTitle(store.hasSearched ? String(localized: "Search Results") : String(localized: "Search"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $store.query,
            isPresented: $searchInterfacePresented,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search Miniflux"
        )
        .onSubmit(of: .search) { store.submit() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") {
                    store.clear()
                    searchInterfacePresented = true
                }
                .disabled(!store.hasSearched && store.query.isEmpty)
            }
        }
        .onAppear {
            searchInterfacePresented = true
        }
        .sensoryFeedback(.success, trigger: store.readCompletionFeedbackRevision)
        .sensoryFeedback(.success, trigger: store.starCompletionFeedbackRevision)
    }
}

private struct SearchResultsContent: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: IOSSearchStore
    var newsreaderStore: NewsreaderStore
    let onArticleTap: (ArticleSummary) -> Void
    let onArticleAction: (ArticleSummary, IOSArticleContextAction) -> Void
    let onArticleMediaAction: (ArticleSummary, IOSArticleMediaAction) -> Void
    let onSetRead: (ArticleSummary, Bool) -> Void
    let onSetStarred: (ArticleSummary, Bool) -> Void

    var body: some View {
        let iconVariant = IOSFeedIconPresentation.variant(isDark: colorScheme == .dark)

        Group {
            if store.isSearching && store.results.isEmpty {
                ProgressView("Searching")
            } else if let errorMessage = store.errorMessage, store.results.isEmpty {
                ContentUnavailableView {
                    Label("Search Failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") { store.retry() }
                }
            } else if !store.hasSearched {
                ContentUnavailableView.search
            } else if store.results.isEmpty {
                ContentUnavailableView.search(text: store.submittedQuery)
            } else {
                IOSUIKitArticleTimelineView(
                    structuralState: store.timelineStructuralState,
                    presentationBridge: store.timelinePresentationBridge,
                    feedIconPresentationBridge: newsreaderStore.timelinePresentationBridge,
                    mode: newsreaderStore.articlePresentationMode,
                    previewLines: newsreaderStore.articlePreviewLines,
                    showRelativePublicationTime: newsreaderStore.showRelativePublicationTime,
                    iconVariant: iconVariant,
                    feedIconRequestRevision: newsreaderStore.feedIconRequestRevision,
                    scrollResetRevision: 0,
                    markReadOnScrolloverEnabled: false,
                    swipeConfiguration: newsreaderStore.articleSwipeConfiguration,
                    audioActionStates: store.articleAudioActionStates,
                    showsRefreshControl: false,
                    naturalTopContentInset: 0,
                    onArticleTap: onArticleTap,
                    onArticleAction: onArticleAction,
                    onArticleMediaAction: onArticleMediaAction,
                    onSetRead: onSetRead,
                    onSetStarred: onSetStarred,
                    onRequestFeedIcon: { feedID, variant, displayScale in
                        newsreaderStore.requestFeedIcon(feedID, variant: variant, displayScale: displayScale)
                    },
                    onRefresh: {},
                    onApproachingEnd: { store.loadMore() },
                    onMeaningfulInteraction: {},
                    onScrolloverBatch: { _ in },
                    onScrolloverDirection: { _ in },
                    onScrolloverPhase: { _ in }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

}
