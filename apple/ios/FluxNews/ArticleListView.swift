import SwiftUI

struct ArticleListView: View {
    @Environment(\.colorScheme) private var colorScheme
    var store: NewsreaderStore
    var naturalTopContentInset: CGFloat = 0
    var usesNativeTopEdgeEffect = true
    let onArticleTap: (ArticleSummary) -> Void
    let onArticleAction: (ArticleSummary, IOSArticleContextAction) -> Void
    let onArticleMediaAction: (ArticleSummary, IOSArticleMediaAction) -> Void

    var body: some View {
        let emptyState = IOSArticleListEmptyState.resolve(
            isSyncing: store.isSyncing,
            isLoading: store.isLoading,
            errorMessage: store.errorMessage,
            hasArticles: store.hasLoadedArticles
        )
        let iconVariant = IOSFeedIconPresentation.variant(isDark: colorScheme == .dark)

        Group {
            if case let .error(message) = emptyState {
                ContentUnavailableView("Unable to Load Articles", systemImage: "exclamationmark.triangle", description: Text(message))
            } else if case .syncing = emptyState {
                ProgressView("News syncing…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if case .loading = emptyState {
                ProgressView("Loading articles")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if case .noNews = emptyState {
                ContentUnavailableView("No News", systemImage: "newspaper")
            } else {
                IOSUIKitArticleTimelineView(
                    structuralState: store.timelineStructuralState,
                    presentationBridge: store.timelinePresentationBridge,
                    feedIconPresentationBridge: store.timelinePresentationBridge,
                    mode: store.articlePresentationMode,
                    previewLines: store.articlePreviewLines,
                    showRelativePublicationTime: store.showRelativePublicationTime,
                    iconVariant: iconVariant,
                    feedIconRequestRevision: store.feedIconRequestRevision,
                    scrollResetRevision: store.scrollResetRevision,
                    markReadOnScrolloverEnabled: store.markReadOnScrolloverEnabled,
                    swipeConfiguration: store.articleSwipeConfiguration,
                    audioActionStates: store.articleAudioActionStates,
                    showsRefreshControl: true,
                    naturalTopContentInset: naturalTopContentInset,
                    usesNativeTopEdgeEffect: usesNativeTopEdgeEffect,
                    onArticleTap: onArticleTap,
                    onArticleAction: onArticleAction,
                    onArticleMediaAction: onArticleMediaAction,
                    onSetRead: { article, read in store.setRead(article, read: read) },
                    onSetStarred: { article, starred in store.setStarred(article, starred: starred) },
                    onRequestFeedIcon: { feedID, variant, displayScale in store.requestFeedIcon(feedID, variant: variant, displayScale: displayScale) },
                    onRefresh: { await store.syncManually() },
                    onApproachingEnd: { store.loadNextTimelinePage() },
                    onMeaningfulInteraction: { store.markMeaningfulInteraction() },
                    onScrolloverBatch: { store.flushScrollover($0) },
                    onScrolloverDirection: { store.receiveScrolloverDirection($0) },
                    onScrolloverPhase: { store.setScrolloverPresentationPhase($0) }
                )
                .ignoresSafeArea(.container, edges: [.top, .bottom])
            }
        }
        .background(.background)
        .overlay(alignment: .bottom) {
            ArticleListBottomOverlay(store: store)
        }
        // Mark-as-read is a completed action/event. Scrollover publishes this
        // revision only once after the motion has settled and its successful
        // mutations are drained, so fast scrolling never becomes a haptic stream.
        .sensoryFeedback(.success, trigger: store.readCompletionFeedbackRevision)
        .sensoryFeedback(.success, trigger: store.starCompletionFeedbackRevision)
        // Undo is intentionally distinct and lighter: it communicates the
        // reversal of the read-state change without reusing the completion pulse.
        .sensoryFeedback(.selection, trigger: store.undoCompletionFeedbackRevision)
    }

}

private struct ArticleListBottomOverlay: View {
    var store: NewsreaderStore

    var body: some View {
        Group {
            if store.scrolloverUndoVisible {
                ScrolloverUndoPresentation(store: store)
            } else if store.hasPendingNewDataForCurrentScope {
                Button("New articles available") { store.adoptVisibleSnapshot() }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 12)
            }
        }
    }
}

private struct ScrolloverUndoPresentation: View {
    var store: NewsreaderStore
    var body: some View {
        HStack(spacing: 10) {
            Text(scrolloverUndoCountLabel)
            Button("Undo") { store.undoScrollover() }
                .buttonStyle(.borderless)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, 12)
    }

    private var scrolloverUndoCountLabel: String {
        let count = store.scrolloverUndoIDs.count
        return String(localized: "\(count) article marked as read")
    }
}
