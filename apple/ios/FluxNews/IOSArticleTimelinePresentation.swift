import SwiftUI
import UIKit

struct IOSUIKitArticleTimelineStructuralItem {
    let article: ArticleSummary
    let content: ArticleRowContent
}

struct IOSUIKitArticlePresentationState: Equatable {
    let isRead: Bool
    let isStarred: Bool
    let revision: UInt64
}

struct IOSUIKitArticlePresentationDelta {
    let articleID: Int64
    let state: IOSUIKitArticlePresentationState
    let rearmScrollover: Bool
}

struct IOSUIKitFeedIconPresentationDelta {
    let key: IOSFeedIconKey
    let image: UIImage?
    let revision: UInt64
}

/// Owned by the presentation layer, not SwiftUI observation. It retains current
/// mutable state so a later cell binding never needs a complete row reconstruction.
@MainActor
final class IOSUIKitArticleTimelinePresentationBridge {
    private final class WeakControllerSubscription {
        weak var controller: IOSUIKitArticleTimelineController?

        init(_ controller: IOSUIKitArticleTimelineController) {
            self.controller = controller
        }
    }

    private var articleSubscribers: [ObjectIdentifier: WeakControllerSubscription] = [:]
    private var feedIconSubscribers: [ObjectIdentifier: WeakControllerSubscription] = [:]
    private var articleStates: [Int64: IOSUIKitArticlePresentationState] = [:]
    private var feedIcons: [IOSFeedIconKey: IOSUIKitFeedIconPresentationDelta] = [:]

    func subscribeArticles(_ controller: IOSUIKitArticleTimelineController) {
        pruneSubscriptions()
        articleSubscribers[ObjectIdentifier(controller)] = .init(controller)
        controller.applyPresentationBridgeState(self)
    }

    func unsubscribeArticles(_ controller: IOSUIKitArticleTimelineController) {
        articleSubscribers.removeValue(forKey: ObjectIdentifier(controller))
    }

    func subscribeFeedIcons(_ controller: IOSUIKitArticleTimelineController) {
        pruneSubscriptions()
        feedIconSubscribers[ObjectIdentifier(controller)] = .init(controller)
    }

    func unsubscribeFeedIcons(_ controller: IOSUIKitArticleTimelineController) {
        feedIconSubscribers.removeValue(forKey: ObjectIdentifier(controller))
    }

    func replaceArticleStates(_ states: [Int64: IOSUIKitArticlePresentationState]) {
        articleStates = states
    }

    func appendArticleStates(_ states: [Int64: IOSUIKitArticlePresentationState]) {
        for (id, state) in states where articleStates[id] == nil { articleStates[id] = state }
    }

    func removeArticleStates(_ ids: some Sequence<Int64>) {
        for id in ids { articleStates[id] = nil }
    }

    func publishArticle(_ delta: IOSUIKitArticlePresentationDelta) {
        guard delta.state.revision >= articleStates[delta.articleID]?.revision ?? 0 else { return }
        articleStates[delta.articleID] = delta.state
        for subscription in articleSubscribers.values {
            subscription.controller?.applyArticlePresentation(delta)
        }
    }

    func publishFeedIcon(_ delta: IOSUIKitFeedIconPresentationDelta) {
        guard delta.revision >= feedIcons[delta.key]?.revision ?? 0 else { return }
        feedIcons[delta.key] = delta
        for subscription in feedIconSubscribers.values {
            subscription.controller?.applyFeedIconPresentation(delta)
        }
    }

    func resetFeedIcons() {
        feedIcons = [:]
        for subscription in feedIconSubscribers.values {
            subscription.controller?.clearFeedIconPresentation()
        }
    }

    func articleState(for id: Int64, fallback: ArticleSummary) -> IOSUIKitArticlePresentationState {
        articleStates[id] ?? .init(isRead: fallback.isRead, isStarred: fallback.isStarred, revision: 0)
    }

    func feedIcon(for feedID: Int64, variant: FeedIconVariant) -> UIImage? {
        feedIcons[.init(feedID: feedID, variant: variant)]?.image
    }

    private func pruneSubscriptions() {
        articleSubscribers = articleSubscribers.filter { $0.value.controller != nil }
        feedIconSubscribers = feedIconSubscribers.filter { $0.value.controller != nil }
    }
}

final class IOSUIKitArticleTimelineStructuralStorage {
    var items: [IOSUIKitArticleTimelineStructuralItem] = []
}

enum IOSUIKitArticleTimelineStructuralChange {
    case replace
    case append([IOSUIKitArticleTimelineStructuralItem])
    case remove([Int64])
}

struct IOSUIKitArticleTimelineStructuralState {
    let storage: IOSUIKitArticleTimelineStructuralStorage
    let change: IOSUIKitArticleTimelineStructuralChange
    let revision: UInt64

    init(storage: IOSUIKitArticleTimelineStructuralStorage, change: IOSUIKitArticleTimelineStructuralChange, revision: UInt64) {
        self.storage = storage
        self.change = change
        self.revision = revision
    }

    init(items: [IOSUIKitArticleTimelineStructuralItem], revision: UInt64) {
        let storage = IOSUIKitArticleTimelineStructuralStorage()
        storage.items = items
        self.init(storage: storage, change: .replace, revision: revision)
    }
}

struct IOSUIKitArticleTimelineItem {
    let article: ArticleSummary
    let content: ArticleRowContent
    let isRead: Bool
    let isStarred: Bool
    let feedIconImage: UIImage?
}

@MainActor
struct IOSUIKitArticleTimelineView: UIViewControllerRepresentable {
    let structuralState: IOSUIKitArticleTimelineStructuralState
    let presentationBridge: IOSUIKitArticleTimelinePresentationBridge
    let feedIconPresentationBridge: IOSUIKitArticleTimelinePresentationBridge
    let mode: ArticlePresentationMode
    let previewLines: ArticlePreviewLines
    let showRelativePublicationTime: Bool
    let iconVariant: FeedIconVariant
    let feedIconRequestRevision: UInt64
    let scrollResetRevision: UInt64
    let markReadOnScrolloverEnabled: Bool
    var swipeConfiguration: IOSArticleSwipeConfiguration = .defaultConfiguration
    var audioActionStates: [Int64: IOSArticleAudioActionState] = [:]
    let showsRefreshControl: Bool
    let naturalTopContentInset: CGFloat
    var usesNativeTopEdgeEffect = true
    let onArticleTap: (ArticleSummary) -> Void
    let onArticleAction: (ArticleSummary, IOSArticleContextAction) -> Void
    var onArticleMediaAction: (ArticleSummary, IOSArticleMediaAction) -> Void = { _, _ in }
    let onSetRead: (ArticleSummary, Bool) -> Void
    let onSetStarred: (ArticleSummary, Bool) -> Void
    let onRequestFeedIcon: (Int64, FeedIconVariant, CGFloat) -> Void
    let onRefresh: () async -> Void
    let onApproachingEnd: (() -> Void)?
    let onMeaningfulInteraction: () -> Void
    let onScrolloverBatch: (IOSScrolloverBatch) -> Void
    let onScrolloverDirection: (IOSArticleScrollDirection) -> Void
    let onScrolloverPhase: (IOSScrolloverPresentationPhase) -> Void

    func makeUIViewController(context: Context) -> IOSUIKitArticleTimelineController {
        let controller = IOSUIKitArticleTimelineController()
        update(controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: IOSUIKitArticleTimelineController, context: Context) {
        update(uiViewController)
    }

    static func dismantleUIViewController(_ uiViewController: IOSUIKitArticleTimelineController, coordinator: ()) {
        uiViewController.detachPresentationBridges()
    }

    private func update(_ controller: IOSUIKitArticleTimelineController) {
        controller.onArticleTap = onArticleTap
        controller.onArticleAction = onArticleAction
        controller.onArticleMediaAction = onArticleMediaAction
        controller.onSetRead = onSetRead
        controller.onSetStarred = onSetStarred
        controller.onRequestFeedIcon = onRequestFeedIcon
        controller.onRefresh = onRefresh
        controller.onApproachingEnd = onApproachingEnd
        controller.onMeaningfulInteraction = onMeaningfulInteraction
        controller.onScrolloverBatch = onScrolloverBatch
        controller.onScrolloverDirection = onScrolloverDirection
        controller.onScrolloverPhase = onScrolloverPhase
        controller.update(
            structuralState: structuralState,
            presentationBridge: presentationBridge,
            feedIconPresentationBridge: feedIconPresentationBridge,
            mode: mode,
            previewLines: previewLines,
            showRelativePublicationTime: showRelativePublicationTime,
            iconVariant: iconVariant,
            feedIconRequestRevision: feedIconRequestRevision,
            scrollResetRevision: scrollResetRevision,
            markReadOnScrolloverEnabled: markReadOnScrolloverEnabled,
            swipeConfiguration: swipeConfiguration,
            audioActionStates: audioActionStates,
            showsRefreshControl: showsRefreshControl,
            naturalTopContentInset: naturalTopContentInset,
            usesNativeTopEdgeEffect: usesNativeTopEdgeEffect
        )
    }
}
