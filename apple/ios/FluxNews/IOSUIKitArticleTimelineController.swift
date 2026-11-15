import UIKit
#if DEBUG || FLUX_PERFORMANCE_DIAGNOSTICS
import OSLog
#endif

@MainActor
/// Protects the status-bar glyph band while leaving the Liquid Glass navigation
/// chrome itself unbacked over scrolling article content.
final class IOSUIKitTimelineTopScrimView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    private var gradient: CAGradientLayer { layer as! CAGradientLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        // A straight ramp has a constant slope, so the eye finds its lower edge.
        // Holding almost full strength across the glyph band and then easing out
        // makes the scrim read as shorter *and* softer than a linear one, without
        // taking protection away from where the status bar actually sits.
        gradient.locations = [0, 0.55, 0.75, 1]
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.updateColors()
        }
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Strength at the very top. The remaining stops are fractions of it, so
    /// this one number changes the whole scrim.
    static let peakAlpha: CGFloat = 0.68

    private func updateColors() {
        let base = UIColor.systemBackground.resolvedColor(with: traitCollection)
        gradient.colors = [
            base.withAlphaComponent(Self.peakAlpha).cgColor,
            base.withAlphaComponent(Self.peakAlpha * 0.95).cgColor,
            base.withAlphaComponent(Self.peakAlpha * 0.4).cgColor,
            base.withAlphaComponent(0).cgColor,
        ]
    }
}


final class IOSUIKitArticleTimelineController: UIViewController, UITableViewDelegate, UITableViewDataSourcePrefetching {
    private enum Section: Hashable { case main }

    var onArticleTap: ((ArticleSummary) -> Void)?
    var onArticleAction: ((ArticleSummary, IOSArticleContextAction) -> Void)?
    var onArticleMediaAction: ((ArticleSummary, IOSArticleMediaAction) -> Void)?
    var onSetRead: ((ArticleSummary, Bool) -> Void)?
    var onSetStarred: ((ArticleSummary, Bool) -> Void)?
    var onRequestFeedIcon: ((Int64, FeedIconVariant, CGFloat) -> Void)?
    var onRefresh: (() async -> Void)?
    var onApproachingEnd: (() -> Void)?
    var onMeaningfulInteraction: (() -> Void)?
    var onScrolloverBatch: ((IOSScrolloverBatch) -> Void)?
    var onScrolloverDirection: ((IOSArticleScrollDirection) -> Void)?
    var onScrolloverPhase: ((IOSScrolloverPresentationPhase) -> Void)?

    private var tableView: UITableView!
    private var dataSource: UITableViewDiffableDataSource<Section, Int64>!
    private var orderedIDs: [Int64] = []
    private var itemsByID: [Int64: IOSUIKitArticleTimelineStructuralItem] = [:]
    private var presentationByID: [Int64: IOSUIKitArticlePresentationState] = [:]
    private weak var presentationBridge: IOSUIKitArticleTimelinePresentationBridge?
    private weak var feedIconPresentationBridge: IOSUIKitArticleTimelinePresentationBridge?
    private var structuralRevision: UInt64?
    private var mode: ArticlePresentationMode = .visual
    private var previewLines: ArticlePreviewLines = .standard
    private var showRelativePublicationTime = false
    private var iconVariant: FeedIconVariant = .normal
    private var feedIconRequestRevision: UInt64?
    private var scrollResetRevision: UInt64?
    private var markReadOnScrolloverEnabled = false
    private var swipeConfiguration = IOSArticleSwipeConfiguration.defaultConfiguration
    private var audioActionStates: [Int64: IOSArticleAudioActionState] = [:]
    private var showsRefreshControl = true
    private var naturalTopContentInset: CGFloat = 0
    private var usesNativeTopEdgeEffect = true
    private var scrolloverPhase: IOSScrolloverPresentationPhase = .idle
    private var scrolloverLayoutGeneration: UInt64 = 0
    private var resolvedScrolloverFrames = IOSUIKitResolvedScrolloverFrameStore()
    private struct ScrollAnchor {
        let articleID: Int64
        let viewportOffset: CGFloat
    }

    private var geometryIdentity: IOSUIKitTimelineGeometryIdentity?
    private var geometryGeneration: UInt64 = 0
    /// Geometry changes may temporarily make UIKit recalculate its content
    /// offset before replacement row heights are ready. Capture the stable
    /// article identity before that transition so the asynchronous reload can
    /// restore the user's place rather than anchoring whatever UIKit happens to
    /// expose afterwards.
    private var pendingGeometryScrollAnchor: ScrollAnchor?
    private var preparedWindowTask: Task<Void, Never>?
    private var preparedWindowGeneration: UInt64 = 0
    private var scheduledPreparedWindowGeneration: UInt64?
    /// Keep image preparation narrowly ahead of the viewport. UIKit may offer
    /// a wider prefetch window, but the image pipeline receives at most the next
    /// two image-bearing articles in the inferred scroll direction.
    private static let maximumOffscreenArticleImagePrefetchCount = 2
    private var imageArticleIDs = Set<Int64>()
    private var prefetchTasks: [Int64: (request: ArticleImageRequest, task: Task<Void, Never>)] = [:]
    private let refreshControl = UIRefreshControl()
    private let statusBarScrim = IOSUIKitTimelineTopScrimView()
    private var statusBarScrimHeight: NSLayoutConstraint!
    private let scrolloverGeometryTracker = IOSUIKitScrolloverGeometryTracker()
    private let preparedLayoutCoordinator = IOSUIKitArticleLayoutPreparationCoordinator()
    /// Exact heights for every loaded row. Estimation is disabled, so a missing
    /// entry would force Core Text onto the main actor during layout.
    private let rowHeights = IOSUIKitArticleRowHeightStore()
    private var rowHeightTask: Task<Void, Never>?
    private var rowHeightGeneration: UInt64 = 0
    private var pendingStructuralApply: Task<Void, Never>?
    /// Monotonically identifies the newest structural snapshot publication.
    /// Cancellation alone is not sufficient because the detached height
    /// measurement may finish after cancellation; the generation check prevents
    /// such stale work from publishing an older diffable snapshot afterwards.
    private var structuralApplyGeneration: UInt64 = 0
    /// Held until the first layout pass resolves a geometry. Applying a snapshot
    /// before then publishes rows whose heights cannot exist yet, and the table
    /// answers by measuring every one of them synchronously while laying out.
    private var deferredSnapshot: NSDiffableDataSourceSnapshot<Section, Int64>?
    private let performanceMetrics = IOSUIKitTimelinePerformanceMetrics()
#if DEBUG || FLUX_PERFORMANCE_DIAGNOSTICS
    private static let performanceSignposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "dev.kevincfechtel.fluxNews",
        category: "timeline-performance"
    )
#endif
    private(set) var structuralReconciliationCount = 0
    private(set) var structuralSnapshotApplicationCount = 0
    private(set) var articlePresentationApplicationCount = 0
    private(set) var feedIconPresentationApplicationCount = 0
    private(set) var scrolloverRearmCount = 0
#if DEBUG
    private(set) var fullPrefetchCancellationCountForTesting = 0
    private(set) var layoutInvalidationCountForTesting = 0
    private(set) var visibleCellReconfigurationPassCountForTesting = 0
    private(set) var layoutPrefetchInputCountForTesting = 0
    var articleImagePrefetchTaskCountForTesting: Int { prefetchTasks.count }
    var tableViewForTesting: UITableView { tableView }
    var preparedRowHeightCountForTesting: Int { rowHeights.preparedCount }
    private(set) var synchronousRowHeightFallbackCountForTesting = 0
    /// Structural updates and geometry changes measure heights off the main
    /// actor before they are applied. Tests await that work instead of polling.
    func settleForTesting() async {
        while pendingStructuralApply != nil || rowHeightTask != nil {
            await pendingStructuralApply?.value
            await rowHeightTask?.value
        }
    }
#endif
#if DEBUG
    private(set) var scrollResetApplicationCountForTesting = 0
    private(set) var lastScrollResetOffsetForTesting: CGPoint?
    var contentOffsetForTesting: CGPoint { tableView.contentOffset }
    var scrolloverLayoutGenerationForTesting: UInt64 { scrolloverLayoutGeneration }
    var orderedArticleIDsForTesting: [Int64] { orderedIDs }
    var scrollAnchorForTesting: (articleID: Int64, viewportOffset: CGFloat)? {
        currentScrollAnchor().map { ($0.articleID, $0.viewportOffset) }
    }
    func captureGeometryScrollAnchorForTesting() {
        captureGeometryScrollAnchorIfNeeded()
    }
    var nativeTopEdgeEffectEnabledForTesting: Bool {
        if #available(iOS 26.0, *) {
            return !tableView.topEdgeEffect.isHidden
        }
        return false
    }
    var nativeTopEdgeEffectUsesAutomaticStyleForTesting: Bool {
        if #available(iOS 26.0, *) {
            return tableView.topEdgeEffect.style.isEqual(UIScrollEdgeEffect.Style.automatic)
        }
        return false
    }
    var statusBarScrimVisibleForTesting: Bool { !statusBarScrim.isHidden }
    var naturalTopContentInsetForTesting: CGFloat { tableView.contentInset.top }
#endif

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.isOpaque = true

        tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemBackground
        tableView.isOpaque = true
        tableView.contentInsetAdjustmentBehavior = .automatic
        // Every row height comes from the deterministic engine, so estimation is
        // switched off entirely. Estimated self-sizing rewrites `contentSize`
        // while the list scrolls, which moves the running deceleration target.
        tableView.estimatedRowHeight = 0
        tableView.estimatedSectionHeaderHeight = 0
        tableView.estimatedSectionFooterHeight = 0
        tableView.rowHeight = UITableView.automaticDimension
        tableView.separatorStyle = .none
        // A plain table reserves padding above its (absent) section header.
        tableView.sectionHeaderTopPadding = 0
        tableView.alwaysBounceVertical = true
        tableView.delegate = self
        tableView.prefetchDataSource = self
        for variant in [
            IOSUIKitArticleCellLayoutVariant.compact,
            .visualTextOnly,
            .visualPortrait,
            .visualLandscape,
            .visualSideTitle,
            .visualSideTitleWide,
            .visualSideTitleTextOnly,
        ] {
            tableView.register(IOSUIKitArticleCell.self, forCellReuseIdentifier: IOSUIKitArticleCell.reuseIdentifier(for: variant))
        }
        // Top-edge visibility is presentation-driven and may change on
        // rotation. The bottom edge effect remains disabled everywhere.
        if #available(iOS 26.0, *) {
            tableView.bottomEdgeEffect.isHidden = true
        }
        refreshControl.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitDisplayScale.self, UITraitLayoutDirection.self]) { (self: Self, _) in
            self.updateGeometryIfNeeded()
        }
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        statusBarScrim.translatesAutoresizingMaskIntoConstraints = false
        // The safe area of this view starts below the *navigation bar*, not below
        // the status bar, so anchoring to it would stretch the scrim across the
        // capsule. The status bar's own frame is the exact measure, and it is
        // zero in landscape, where there is nothing to protect.
        statusBarScrimHeight = statusBarScrim.heightAnchor.constraint(equalToConstant: 0)
        view.addSubview(statusBarScrim)
        NSLayoutConstraint.activate([
            statusBarScrim.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBarScrim.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBarScrim.topAnchor.constraint(equalTo: view.topAnchor),
            statusBarScrimHeight,
        ])
        applyTopEdgeEffectPolicy()

        dataSource = UITableViewDiffableDataSource<Section, Int64>(tableView: tableView) { [weak self] tableView, indexPath, id in
            guard let self,
                  let item = self.renderedItem(for: id)
            else { return nil }
            let geometry = IOSUIKitArticleGeometry(
                mode: self.mode,
                containerWidth: tableView.bounds.width
            )
            let variant = geometry.variant(hasImage: self.mode.showsArticleImage && item.content.imageURL != nil)
            guard let cell = tableView.dequeueReusableCell(withIdentifier: IOSUIKitArticleCell.reuseIdentifier(for: variant), for: indexPath) as? IOSUIKitArticleCell else { return nil }
            self.configure(cell, item: item)
            return cell
        }
        dataSource.defaultRowAnimation = .none
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateStatusBarScrimHeight()
        updateGeometryIfNeeded()
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        captureGeometryScrollAnchorIfNeeded()
        super.viewWillTransition(to: size, with: coordinator)
    }

    private func applyTopEdgeEffectPolicy() {
        if #available(iOS 26.0, *) {
            tableView.topEdgeEffect.style = .automatic
            tableView.topEdgeEffect.isHidden = !usesNativeTopEdgeEffect
            tableView.bottomEdgeEffect.isHidden = true
            statusBarScrim.isHidden = usesNativeTopEdgeEffect
        } else {
            statusBarScrim.isHidden = false
        }
    }

    private func updateStatusBarScrimHeight() {
        let height = view.window?.windowScene?.statusBarManager?.statusBarFrame.height ?? 0
        guard statusBarScrimHeight.constant != height else { return }
        statusBarScrimHeight.constant = height
    }

    private func updateGeometryIfNeeded() {
        guard let newIdentity = currentGeometryIdentity(), newIdentity != geometryIdentity else { return }
        if geometryIdentity != nil {
            captureGeometryScrollAnchorIfNeeded()
        }
        geometryIdentity = newIdentity
        geometryGeneration &+= 1
        performanceMetrics.recordGeometryChange()
#if DEBUG || FLUX_PERFORMANCE_DIAGNOSTICS
        Self.performanceSignposter.emitEvent("Timeline geometry changed")
#endif
        invalidateScrolloverGeometry()
        cancelIncompatibleImagePrefetch()
        reconfigureVisibleCells(needsLayout: true)
        schedulePreparedLayoutWindow(for: newIdentity)
        // The store keeps serving the superseded heights while the replacement
        // set is measured, so rotation and Dynamic Type never block a frame on a
        // full re-measurement of every loaded row.
        rowHeights.beginGeneration(newIdentity)
        if let deferred = deferredSnapshot {
            // First resolved geometry: publish the rows that were held back,
            // through the same gate that measures their heights first.
            deferredSnapshot = nil
            applySnapshotWhenHeightsReady(deferred)
        } else {
            scheduleRowHeightMeasurement(reloadWhenComplete: true)
        }
    }

    private func scheduleRowHeightMeasurement(reloadWhenComplete: Bool) {
        guard let identity = geometryIdentity else { return }
        let missing = rowHeights.missingIDs(in: orderedIDs)
        guard !missing.isEmpty else {
            if reloadWhenComplete { reloadPreservingAnchor() }
            return
        }
        rowHeightGeneration &+= 1
        let generation = rowHeightGeneration
        let inputs = rowHeightInputs(for: missing)
        rowHeightTask?.cancel()
        rowHeightTask = Task { @MainActor [weak self] in
            let measured = await IOSUIKitArticleRowHeightMeasurement.heights(for: inputs)
            guard let self, !Task.isCancelled, self.rowHeightGeneration == generation else { return }
            self.rowHeightTask = nil
            self.rowHeights.store(measured, for: identity)
            _ = self.rowHeights.retireSupersededHeights(ifComplete: self.orderedIDs)
            if reloadWhenComplete { self.reloadPreservingAnchor() }
        }
    }

    private func rowHeightInputs(for ids: [Int64]) -> [(id: Int64, input: IOSUIKitArticleLayoutInput)] {
        ids.compactMap { id in
            guard let item = renderedItem(for: id) else { return nil }
            return (id, preparedLayoutInput(for: item))
        }
    }

    /// A reload with exact heights rewrites every row position at once, so the
    /// visible article is re-anchored explicitly instead of being left wherever
    /// the new content size happens to put it.
    private func reloadPreservingAnchor() {
        let anchor = pendingGeometryScrollAnchor ?? currentScrollAnchor()
        pendingGeometryScrollAnchor = nil
        dataSource.applySnapshotUsingReloadData(dataSource.snapshot(), completion: nil)
        guard let anchor, let row = orderedIDs.firstIndex(of: anchor.articleID) else { return }
        tableView.layoutIfNeeded()
        let rect = tableView.rectForRow(at: IndexPath(row: row, section: 0))
        tableView.setContentOffset(
            CGPoint(x: tableView.contentOffset.x, y: rect.minY - anchor.viewportOffset),
            animated: false
        )
    }

    private func captureGeometryScrollAnchorIfNeeded() {
        guard pendingGeometryScrollAnchor == nil else { return }
        pendingGeometryScrollAnchor = currentScrollAnchor()
    }

    private func currentScrollAnchor() -> ScrollAnchor? {
        guard let visibleRows = tableView.indexPathsForVisibleRows,
              let indexPath = visibleRows.min(by: { lhs, rhs in
                  tableView.rectForRow(at: lhs).minY < tableView.rectForRow(at: rhs).minY
              }),
              indexPath.row < orderedIDs.count
        else { return nil }
        return ScrollAnchor(
            articleID: orderedIDs[indexPath.row],
            viewportOffset: tableView.rectForRow(at: indexPath).minY - tableView.contentOffset.y
        )
    }

    /// Rows are never published before their exact heights exist. Applying a
    /// snapshot whose heights are unknown would make the table measure text
    /// synchronously while laying out.
    /// Built from `orderedIDs`, which the controller already maintains as the
    /// authoritative order, rather than from the data source's current state.
    /// The two diverge whenever a snapshot is still held back, and reading the
    /// data source then yields an empty snapshot with no section at all.
    private func currentSnapshot() -> NSDiffableDataSourceSnapshot<Section, Int64> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Int64>()
        snapshot.appendSections([.main])
        snapshot.appendItems(orderedIDs)
        return snapshot
    }

    private func applySnapshotWhenHeightsReady(_ snapshot: NSDiffableDataSourceSnapshot<Section, Int64>) {
        // Every newer structural state supersedes every older pending
        // publication, including when the new snapshot can be applied
        // immediately. Without this, an older height-measurement task can finish
        // later and republish identifiers that have already been removed from
        // itemsByID, causing the diffable cell provider to return nil and UIKit
        // to abort.
        structuralApplyGeneration &+= 1
        let generation = structuralApplyGeneration
        pendingStructuralApply?.cancel()
        pendingStructuralApply = nil

        guard let identity = geometryIdentity else {
            deferredSnapshot = snapshot
            return
        }
        let missing = rowHeights.missingIDs(in: snapshot.itemIdentifiers)
        guard !missing.isEmpty else {
            dataSource.apply(snapshot, animatingDifferences: false)
            return
        }
        let inputs = rowHeightInputs(for: missing)
        pendingStructuralApply = Task { @MainActor [weak self] in
            let measured = await IOSUIKitArticleRowHeightMeasurement.heights(for: inputs)
            guard let self,
                  !Task.isCancelled,
                  self.structuralApplyGeneration == generation
            else { return }
            self.pendingStructuralApply = nil
            self.rowHeights.store(measured, for: identity)
            self.dataSource.apply(snapshot, animatingDifferences: false, completion: nil)
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return UITableView.automaticDimension }
        if let height = rowHeights.height(for: id) { return height }
        // Last resort: a prepared height is missing. Worth counting rather than
        // silently absorbing, because this is the one path that can put Core Text
        // on the main actor during layout.
        guard let item = renderedItem(for: id) else { return UITableView.automaticDimension }
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let metrics = preparedLayoutCoordinator.measureSynchronously(preparedLayoutInput(for: item), priority: .visible)
        performanceMetrics.recordDeterministicHeightFallback(durationNanoseconds: DispatchTime.now().uptimeNanoseconds - startedAt)
#if DEBUG
        synchronousRowHeightFallbackCountForTesting &+= 1
#endif
        if let identity = geometryIdentity { rowHeights.store([id: metrics.cellSize.height], for: identity) }
        return metrics.cellSize.height
    }

    func update(
        structuralState: IOSUIKitArticleTimelineStructuralState,
        presentationBridge newPresentationBridge: IOSUIKitArticleTimelinePresentationBridge,
        feedIconPresentationBridge newFeedIconPresentationBridge: IOSUIKitArticleTimelinePresentationBridge,
        mode newMode: ArticlePresentationMode,
        previewLines newPreviewLines: ArticlePreviewLines,
        showRelativePublicationTime newShowRelativePublicationTime: Bool = false,
        iconVariant newIconVariant: FeedIconVariant,
        feedIconRequestRevision newFeedIconRequestRevision: UInt64,
        scrollResetRevision newScrollResetRevision: UInt64,
        markReadOnScrolloverEnabled newMarkReadOnScrolloverEnabled: Bool,
        swipeConfiguration newSwipeConfiguration: IOSArticleSwipeConfiguration = .defaultConfiguration,
        audioActionStates newAudioActionStates: [Int64: IOSArticleAudioActionState] = [:],
        showsRefreshControl newShowsRefreshControl: Bool,
        naturalTopContentInset newNaturalTopContentInset: CGFloat = 0,
        usesNativeTopEdgeEffect newUsesNativeTopEdgeEffect: Bool = true
    ) {
        loadViewIfNeeded()
#if DEBUG || FLUX_PERFORMANCE_DIAGNOSTICS
        IOSUIKitTimelinePerformanceDiagnostics.currentController = self
#endif

        let structuralChanged = structuralRevision != structuralState.revision
        let layoutInputsChanged = mode != newMode
            || previewLines != newPreviewLines
            || showRelativePublicationTime != newShowRelativePublicationTime
        let iconVariantChanged = iconVariant != newIconVariant
        let feedIconRequestChanged = feedIconRequestRevision != nil && feedIconRequestRevision != newFeedIconRequestRevision
        let resetChanged = scrollResetRevision != nil && scrollResetRevision != newScrollResetRevision
        let clampedNaturalTopContentInset = max(0, newNaturalTopContentInset)
        let naturalTopInsetChanged = abs(naturalTopContentInset - clampedNaturalTopContentInset) > 0.5
        let wasAtNaturalTop = structuralRevision == nil
            || abs(tableView.contentOffset.y + tableView.adjustedContentInset.top) <= 0.5
        let topEdgePolicyChanged = usesNativeTopEdgeEffect != newUsesNativeTopEdgeEffect
        let previousAudioArticleIDs = Set(
            audioActionStates.compactMap { articleID, state in
                IOSArticleAudioPresentation.hasAudio(state) ? articleID : nil
            }
        )
        let newAudioArticleIDs = Set(
            newAudioActionStates.compactMap { articleID, state in
                IOSArticleAudioPresentation.hasAudio(state) ? articleID : nil
            }
        )
        let audioAvailabilityChangedIDs = previousAudioArticleIDs
            .symmetricDifference(newAudioArticleIDs)

        mode = newMode
        previewLines = newPreviewLines
        showRelativePublicationTime = newShowRelativePublicationTime
        iconVariant = newIconVariant
        feedIconRequestRevision = newFeedIconRequestRevision
        scrollResetRevision = newScrollResetRevision
        markReadOnScrolloverEnabled = newMarkReadOnScrolloverEnabled
        swipeConfiguration = newSwipeConfiguration
        audioActionStates = newAudioActionStates
        if !audioAvailabilityChangedIDs.isEmpty {
            for cell in materializedVisibleArticleCells() {
                guard let articleID = cell.representedArticleID,
                      audioAvailabilityChangedIDs.contains(articleID) else {
                    continue
                }
                cell.updateAudioAvailability(
                    newAudioArticleIDs.contains(articleID)
                )
            }
        }
        showsRefreshControl = newShowsRefreshControl
        naturalTopContentInset = clampedNaturalTopContentInset
        usesNativeTopEdgeEffect = newUsesNativeTopEdgeEffect
        tableView.refreshControl = showsRefreshControl ? refreshControl : nil
        if naturalTopInsetChanged {
            // The detached portrait capsule should clear the first article only at
            // the natural beginning of the list. contentInset scrolls away with
            // the content, unlike a permanent safe-area reservation.
            invalidateScrolloverGeometry()
            tableView.contentInset.top = naturalTopContentInset
            if wasAtNaturalTop {
                tableView.setContentOffset(
                    CGPoint(x: tableView.contentOffset.x, y: -tableView.adjustedContentInset.top),
                    animated: false
                )
            }
        }
        if topEdgePolicyChanged {
            applyTopEdgeEffectPolicy()
        }
        if presentationBridge !== newPresentationBridge {
            presentationBridge?.unsubscribeArticles(self)
            presentationBridge = newPresentationBridge
            newPresentationBridge.subscribeArticles(self)
        }
        if feedIconPresentationBridge !== newFeedIconPresentationBridge {
            feedIconPresentationBridge?.unsubscribeFeedIcons(self)
            feedIconPresentationBridge = newFeedIconPresentationBridge
            newFeedIconPresentationBridge.subscribeFeedIcons(self)
        }

        var structuralUpdate: IOSUIKitArticleTimelineStructuralChange?
        if structuralChanged {
            structuralReconciliationCount &+= 1
            performanceMetrics.recordStructuralReconciliation()
            let canApplyIncrementally = structuralRevision == structuralState.revision &- 1
            if canApplyIncrementally, case let .append(appendedItems) = structuralState.change {
                let appended = appendedItems.filter { itemsByID[$0.article.id] == nil }
                let appendedIDs = appended.map(\.article.id)
                orderedIDs.append(contentsOf: appendedIDs)
                for item in appended {
                    itemsByID[item.article.id] = item
                    presentationByID[item.article.id] = newPresentationBridge.articleState(for: item.article.id, fallback: item.article)
                    if item.content.imageURL != nil { imageArticleIDs.insert(item.article.id) }
                }
                scrolloverGeometryTracker.appendSnapshot(appendedIDs)
                applySnapshotWhenHeightsReady(currentSnapshot())
                structuralUpdate = .append(appended)
            } else if canApplyIncrementally, case let .remove(removedIDs) = structuralState.change {
                let removed = removedIDs.filter { itemsByID[$0] != nil }
                if !removed.isEmpty {
                    let removedSet = Set(removed)
                    orderedIDs.removeAll { removedSet.contains($0) }
                    for id in removed {
                        itemsByID[id] = nil
                        presentationByID[id] = nil
                        imageArticleIDs.remove(id)
                        prefetchTasks.removeValue(forKey: id)?.task.cancel()
                    }
                    scrolloverGeometryTracker.removeSnapshot(removed)
                    invalidateScrolloverGeometry()
                    rowHeights.remove(removed)
                    applySnapshotWhenHeightsReady(currentSnapshot())
                    structuralUpdate = .remove(removed)
                }
            } else {
                let items = structuralState.storage.items
                let newIDs = items.map(\.article.id)
                orderedIDs = newIDs
                itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.article.id, $0) })
                imageArticleIDs = Set(items.compactMap { $0.content.imageURL == nil ? nil : $0.article.id })
                presentationByID = Dictionary(uniqueKeysWithValues: items.map {
                    ($0.article.id, newPresentationBridge.articleState(for: $0.article.id, fallback: $0.article))
                })
                scrolloverGeometryTracker.updateSnapshot(newIDs)
                invalidateScrolloverGeometry()
                applySnapshotWhenHeightsReady(currentSnapshot())
                structuralUpdate = .replace
            }
            structuralRevision = structuralState.revision
            structuralSnapshotApplicationCount &+= 1
            performanceMetrics.recordSnapshotApply()
#if DEBUG || FLUX_PERFORMANCE_DIAGNOSTICS
            Self.performanceSignposter.emitEvent("Timeline snapshot applied")
#endif
        }
        // Append and removal own only their changed IDs. Reconfiguring every
        // visible cell here used to restart image bindings and duplicate layout
        // work even though neither operation changes unaffected row geometry.
        if iconVariantChanged {
            reconfigureVisibleCells(needsLayout: false)
        }

        if case .replace? = structuralUpdate {
            cancelAllPrefetch()
            schedulePreparedLayoutWindow(for: geometryIdentity)
            performanceMetrics.recordLayoutInvalidation()
#if DEBUG
            layoutInvalidationCountForTesting &+= 1
#endif
        } else if case let .append(appended)? = structuralUpdate {
            // Keep the existing visible/nearby window and prepare only the new
            // immutable inputs. UIKit prefetch will promote rows as they approach.
            preparedLayoutCoordinator.prepare(
                appended.prefix(IOSUIKitArticleLayoutPreparationCoordinator.nearbyWindowLimit)
                    .compactMap { renderedItem(for: $0.article.id) }
                    .map { preparedLayoutInput(for: $0) },
                priority: .nearby
            )
        }
        if layoutInputsChanged { updateGeometryIfNeeded() }
        if feedIconRequestChanged { requestFeedIconsForVisibleCells() }
        if resetChanged {
            // Semantic scope/filter/sort resets intentionally own the scroll
            // position. Never let a pending geometry-only anchor restore the
            // previous article after that explicit reset.
            pendingGeometryScrollAnchor = nil
            invalidateScrolloverGeometry()
            let naturalTop = CGPoint(x: 0, y: -tableView.adjustedContentInset.top)
            tableView.setContentOffset(naturalTop, animated: false)
#if DEBUG
            scrollResetApplicationCountForTesting &+= 1
            lastScrollResetOffsetForTesting = naturalTop
#endif
        }
    }

    private func renderedItem(for id: Int64) -> IOSUIKitArticleTimelineItem? {
        guard let item = itemsByID[id] else { return nil }
        let presentation = presentationByID[id] ?? presentationBridge?.articleState(for: id, fallback: item.article) ?? .init(isRead: item.article.isRead, isStarred: item.article.isStarred, revision: 0)
        return .init(article: item.article, content: item.content, isRead: presentation.isRead, isStarred: presentation.isStarred, feedIconImage: feedIconPresentationBridge?.feedIcon(for: item.article.feedId, variant: iconVariant))
    }

    private func configure(_ cell: IOSUIKitArticleCell, item: IOSUIKitArticleTimelineItem) {
        let layoutInput = preparedLayoutInput(for: item)
        let layoutMetrics: IOSUIKitArticleLayoutMetrics
        if let prepared = preparedLayoutCoordinator.metrics(for: layoutInput, priority: .visible) {
            performanceMetrics.recordDeterministicHeightRequest(prepared: true)
            layoutMetrics = prepared
        } else {
            let startedAt = DispatchTime.now().uptimeNanoseconds
            layoutMetrics = preparedLayoutCoordinator.measureSynchronously(layoutInput, priority: .visible)
            performanceMetrics.recordDeterministicHeightFallback(durationNanoseconds: DispatchTime.now().uptimeNanoseconds - startedAt)
        }
        cell.performanceMetrics = performanceMetrics
        cell.setArticleImageArrivalAnimationsEnabled(!scrolloverPhase.isScrolling)
        performanceMetrics.recordConfigure()
        cell.configure(
            item: item,
            hasAudio: IOSArticleAudioPresentation.hasAudio(
                audioActionStates[item.article.id]
            ),
            mode: mode,
            previewLines: previewLines,
            showRelativePublicationTime: showRelativePublicationTime,
            displayScale: view.traitCollection.displayScale,
            preparedLayoutMetrics: layoutMetrics
        )
        onRequestFeedIcon?(item.content.article.feedId, iconVariant, view.traitCollection.displayScale)
    }

    func applyPresentationBridgeState(_ bridge: IOSUIKitArticleTimelinePresentationBridge) {
        for id in orderedIDs where itemsByID[id] != nil {
            presentationByID[id] = bridge.articleState(for: id, fallback: itemsByID[id]!.article)
        }
    }

    func applyArticlePresentation(_ delta: IOSUIKitArticlePresentationDelta) {
        guard let current = presentationByID[delta.articleID], delta.state.revision >= current.revision else { return }
        articlePresentationApplicationCount &+= 1
        presentationByID[delta.articleID] = delta.state
        if delta.rearmScrollover {
            scrolloverGeometryTracker.rearm([delta.articleID])
            scrolloverRearmCount &+= 1
        }
        guard let indexPath = dataSource.indexPath(for: delta.articleID),
              let cell = tableView.cellForRow(at: indexPath) as? IOSUIKitArticleCell else { return }
        cell.updateStatus(isRead: delta.state.isRead, isStarred: delta.state.isStarred)
    }

    func applyFeedIconPresentation(_ delta: IOSUIKitFeedIconPresentationDelta) {
        guard delta.key.variant == iconVariant else { return }
        feedIconPresentationApplicationCount &+= 1
        applyFeedIconPresentation(delta, to: materializedVisibleArticleCells())
    }

    func applyFeedIconPresentation(_ delta: IOSUIKitFeedIconPresentationDelta, to cells: [IOSUIKitArticleCell]) {
        for cell in cells {
            guard let id = cell.representedArticleID,
                  let item = itemsByID[id], item.article.feedId == delta.key.feedID else { continue }
            cell.updateFeedIcon(image: delta.image, title: item.content.article.feedTitle)
        }
    }

    func clearFeedIconPresentation() {
        feedIconPresentationApplicationCount &+= 1
        clearFeedIconPresentation(to: materializedVisibleArticleCells())
    }

    func clearFeedIconPresentation(to cells: [IOSUIKitArticleCell]) {
        for cell in cells {
            guard let id = cell.representedArticleID, let item = itemsByID[id] else { continue }
            cell.updateFeedIcon(image: nil, title: item.content.article.feedTitle)
        }
    }

    /// Returns only cells UIKit has already materialized. Avoid
    /// `tableView.visibleCells` from update/presentation paths: on iOS 27 that
    /// accessor may synchronously create cells while a diffable snapshot is
    /// transitioning. During the intentional short window where `itemsByID`
    /// already reflects the new structural state but the table still presents
    /// the old snapshot, forced cell creation can ask the provider for an ID
    /// that was just removed and UIKit asserts when the provider returns nil.
    private func materializedVisibleArticleCells() -> [IOSUIKitArticleCell] {
        (tableView.indexPathsForVisibleRows ?? []).compactMap {
            tableView.cellForRow(at: $0) as? IOSUIKitArticleCell
        }
    }

    private func requestFeedIconsForVisibleCells() {
        for cell in materializedVisibleArticleCells() {
            guard let id = cell.representedArticleID,
                  let item = itemsByID[id]
            else { continue }
            onRequestFeedIcon?(item.content.article.feedId, iconVariant, view.traitCollection.displayScale)
        }
    }

    private func reconfigureVisibleCells(needsLayout: Bool) {
#if DEBUG
        visibleCellReconfigurationPassCountForTesting &+= 1
#endif
        for cell in materializedVisibleArticleCells() {
            guard let id = cell.representedArticleID, let item = renderedItem(for: id) else { continue }
            configure(cell, item: item)
            if needsLayout { cell.setNeedsLayout() }
        }
    }

    @objc private func refreshTriggered() {
        guard showsRefreshControl, let onRefresh else {
            refreshControl.endRefreshing()
            return
        }
        Task { @MainActor [weak self] in
            await onRefresh()
            self?.refreshControl.endRefreshing()
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        guard let id = dataSource.itemIdentifier(for: indexPath), let item = renderedItem(for: id) else { return }
        onArticleTap?(item.article)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        recordResolvedScrolloverFrame(for: cell)
        if let articleCell = cell as? IOSUIKitArticleCell {
            reconcilePresentationForDisplay(articleCell)
        }
        prepareVisibleLayoutMetrics()
        guard !orderedIDs.isEmpty, indexPath.row >= max(0, orderedIDs.count - 5) else { return }
        onApproachingEnd?()
    }

    func reconcilePresentationForDisplay(_ cell: IOSUIKitArticleCell) {
        guard let articleID = cell.representedArticleID,
              let item = itemsByID[articleID] else { return }
        let articleState = presentationBridge?.articleState(for: articleID, fallback: item.article)
        cell.updateStatus(
            isRead: articleState?.isRead ?? item.article.isRead,
            isStarred: articleState?.isStarred ?? item.article.isStarred
        )
        cell.updateFeedIcon(
            image: feedIconPresentationBridge?.feedIcon(for: item.article.feedId, variant: iconVariant),
            title: item.content.article.feedTitle
        )
        cell.updateAudioAvailability(
            IOSArticleAudioPresentation.hasAudio(
                audioActionStates[articleID]
            )
        )
    }

    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        // Keep the resolved frame briefly so either lifecycle/scroll callback order
        // can still prove a crossing using the same content-coordinate geometry.
        recordResolvedScrolloverFrame(for: cell)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
#if DEBUG || FLUX_PERFORMANCE_DIAGNOSTICS
        Self.performanceSignposter.emitEvent("Timeline interaction began")
#endif
        onMeaningfulInteraction?()
        setScrolloverPhase(.interacting)
        sampleScrolloverGeometry()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrolloverPhase.isScrolling else { return }
        sampleScrolloverGeometry()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { sampleScrolloverGeometry() }
        setScrolloverPhase(decelerate ? .decelerating : .idle)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        sampleScrolloverGeometry()
        setScrolloverPhase(.idle)
    }

    func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
        invalidateScrolloverGeometry()
    }

    private func setScrolloverPhase(_ phase: IOSScrolloverPresentationPhase) {
        guard scrolloverPhase != phase else { return }
        scrolloverPhase = phase
        IOSArticleImagePresentationScheduler.shared.setScrolling(phase.isScrolling)
        let animationsEnabled = !phase.isScrolling
        for case let cell as IOSUIKitArticleCell in tableView.visibleCells {
            cell.setArticleImageArrivalAnimationsEnabled(animationsEnabled)
        }
        // Every phase boundary restarts the ballistic baseline.
        scrolloverGeometryTracker.setPhase(phase)
        onScrolloverPhase?(phase)
    }

    private func invalidateScrolloverGeometry() {
        scrolloverLayoutGeneration &+= 1
        resolvedScrolloverFrames.removeAll()
        scrolloverGeometryTracker.invalidateGeometry()
    }

    private func recordResolvedScrolloverFrame(for cell: UITableViewCell) {
        guard let articleCell = cell as? IOSUIKitArticleCell,
              let articleID = articleCell.representedArticleID else { return }
        resolvedScrolloverFrames.record(
            articleID: articleID,
            frame: articleCell.frame
        )
    }

    private func refreshResolvedVisibleScrolloverFrames() {
        for case let cell as IOSUIKitArticleCell in tableView.visibleCells {
            recordResolvedScrolloverFrame(for: cell)
        }
    }

    private func sampleScrolloverGeometry() {
        guard markReadOnScrolloverEnabled, tableView.bounds.height > 0 else { return }

        let effectiveTop = tableView.contentOffset.y + tableView.adjustedContentInset.top
        let effectiveBottom = tableView.contentOffset.y + tableView.bounds.height - tableView.adjustedContentInset.bottom
        // `visibleCells` are UIKit-resolved geometry. The retained source covers a
        // cell whose didEndDisplaying arrives on either side of this scroll callback.
        refreshResolvedVisibleScrolloverFrames()

        let sample = IOSUIKitScrolloverGeometrySample(
            contentOffsetY: tableView.contentOffset.y,
            effectiveTop: effectiveTop,
            effectiveBottom: effectiveBottom,
            contentHeight: tableView.contentSize.height,
            rowFrames: resolvedScrolloverFrames.frames,
            layoutGeneration: scrolloverLayoutGeneration
        )
        let result = scrolloverGeometryTracker.receive(sample, enabled: true)
        if let direction = result.direction { onScrolloverDirection?(direction) }
        if !result.batch.articleIDs.isEmpty { onScrolloverBatch?(result.batch) }
    }

    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        swipeActionsConfiguration(for: .leading, indexPath: indexPath)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        swipeActionsConfiguration(for: .trailing, indexPath: indexPath)
    }

    private func swipeActionsConfiguration(
        for side: IOSArticleSwipeSide,
        indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let id = dataSource.itemIdentifier(for: indexPath),
              let item = renderedItem(for: id)
        else { return nil }

        // Product settings are inner-to-outer. UIKit assigns Full Swipe to its
        // first action, so feed UIKit outer-to-inner and keep the semantic
        // storage independent of UIKit's control ordering.
        let semanticActions = swipeConfiguration.actions(for: side)
        let configuredFullSwipe = semanticActions.last
        let renderedActions = semanticActions
            .reversed()
            .compactMap { semanticAction -> (IOSArticleSwipeAction, UIContextualAction)? in
                guard let action = makeSwipeAction(
                    semanticAction,
                    articleID: id,
                    item: item
                ) else { return nil }
                return (semanticAction, action)
            }

        guard !renderedActions.isEmpty else { return nil }
        let configuration = UISwipeActionsConfiguration(
            actions: renderedActions.map(\.1)
        )
        // A conditional outer action (for example Comments) may be unavailable
        // for this row. Never promote the inner action into Full Swipe merely
        // because UIKit sees it first after filtering.
        configuration.performsFirstActionWithFullSwipe =
            renderedActions.first?.0 == configuredFullSwipe
        return configuration
    }

    private func makeSwipeAction(
        _ semanticAction: IOSArticleSwipeAction,
        articleID: Int64,
        item: IOSUIKitArticleTimelineItem
    ) -> UIContextualAction? {
        switch semanticAction {
        case .readUnread:
            let newValue = !item.isRead
            let action = UIContextualAction(
                style: .normal,
                title: newValue
                    ? String(localized: "Swipe Read")
                    : String(localized: "Swipe Unread")
            ) { [weak self] _, _, completion in
                self?.setRead(id: articleID, value: newValue)
                completion(true)
            }
            action.image = UIImage(
                systemName: newValue ? "envelope.open" : "envelope"
            )
            action.backgroundColor = .tintColor
            return action

        case .starUnstar:
            let newValue = !item.isStarred
            let action = UIContextualAction(
                style: .normal,
                title: newValue
                    ? String(localized: "Swipe Star")
                    : String(localized: "Swipe Unstar")
            ) { [weak self] _, _, completion in
                self?.setStarred(id: articleID, value: newValue)
                completion(true)
            }
            action.image = UIImage(
                systemName: newValue ? "star" : "star.slash"
            )
            action.backgroundColor = .systemOrange
            return action

        case .comments:
            guard item.content.hasComments else { return nil }
            return makeContextSwipeAction(
                article: item.article,
                contextAction: .comments,
                title: String(localized: "Swipe Comments"),
                systemImage: "bubble.left",
                backgroundColor: .systemTeal
            )

        case .openOriginal:
            return makeContextSwipeAction(
                article: item.article,
                contextAction: .original,
                title: String(localized: "Swipe Original"),
                systemImage: "safari",
                backgroundColor: .systemBlue
            )

        case .openMiniflux:
            return makeContextSwipeAction(
                article: item.article,
                contextAction: .miniflux,
                title: String(localized: "Swipe Miniflux"),
                systemImage: "arrow.up.forward.app",
                backgroundColor: .systemIndigo
            )

        case .share:
            return makeContextSwipeAction(
                article: item.article,
                contextAction: .share,
                title: String(localized: "Swipe Share"),
                systemImage: "square.and.arrow.up",
                backgroundColor: .systemBlue
            )

        case .saveToService:
            return makeContextSwipeAction(
                article: item.article,
                contextAction: .saveToService,
                title: String(localized: "Swipe Save"),
                systemImage: "tray.and.arrow.down",
                backgroundColor: .systemPurple
            )

        case .listeningList:
            guard let state = audioActionStates[articleID],
                  !state.audioEnclosures.isEmpty else {
                return nil
            }
            let shouldAdd = !state.isInListeningList
            let action = UIContextualAction(
                style: .normal,
                title: shouldAdd
                    ? String(localized: "Add to Listening List")
                    : String(localized: "Remove from Listening List")
            ) { [weak self] _, _, completion in
                self?.onArticleMediaAction?(
                    item.article,
                    .setListeningList(shouldAdd)
                )
                completion(true)
            }
            action.image = UIImage(
                systemName: shouldAdd ? "plus.circle" : "minus.circle"
            )
            action.backgroundColor = .systemIndigo
            return action

        case .downloadAudio:
            guard !IOSArticleAudioPresentation.downloadableEnclosures(
                audioActionStates[articleID]
            ).isEmpty else {
                return nil
            }
            let action = UIContextualAction(
                style: .normal,
                title: String(localized: "Swipe Download Audio")
            ) { [weak self] _, _, completion in
                self?.onArticleMediaAction?(
                    item.article,
                    .configuredDownloadAudio
                )
                completion(true)
            }
            action.image = UIImage(systemName: "arrow.down.circle")
            action.backgroundColor = .systemGreen
            return action
        }
    }

    private func makeContextSwipeAction(
        article: ArticleSummary,
        contextAction: IOSArticleContextAction,
        title: String,
        systemImage: String,
        backgroundColor: UIColor
    ) -> UIContextualAction {
        let action = UIContextualAction(
            style: .normal,
            title: title
        ) { [weak self] _, _, completion in
            self?.onArticleAction?(article, contextAction)
            completion(true)
        }
        action.image = UIImage(systemName: systemImage)
        action.backgroundColor = backgroundColor
        return action
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let id = dataSource.itemIdentifier(for: indexPath), let item = renderedItem(for: id) else { return nil }
        return UIContextMenuConfiguration(identifier: NSNumber(value: id), previewProvider: nil) { [weak self] _ in
            guard let self, let current = self.renderedItem(for: id) else { return nil }
            var actions: [UIMenuElement] = [
                UIAction(title: current.isStarred ? String(localized: "Unstar") : String(localized: "Star"), image: UIImage(systemName: current.isStarred ? "star.slash" : "star")) { [weak self] _ in
                    self?.setStarred(id: id, value: !current.isStarred)
                },
                UIAction(title: current.isRead ? String(localized: "Mark as Unread") : String(localized: "Mark as Read"), image: UIImage(systemName: current.isRead ? "envelope" : "envelope.open")) { [weak self] _ in
                    self?.setRead(id: id, value: !current.isRead)
                },
                UIMenu(options: .displayInline, children: self.contextNavigationActions(for: item)),
                self.contextAudioMenu(for: item),
                UIMenu(options: .displayInline, children: [
                    UIAction(title: String(localized: "Save to Third-Party Service"), image: UIImage(systemName: "tray.and.arrow.down")) { [weak self] _ in
                        self?.onArticleAction?(item.article, .saveToService)
                    }
                ])
            ]
            actions.removeAll { element in
                if let menu = element as? UIMenu { return menu.children.isEmpty }
                return false
            }
            return UIMenu(children: actions)
        }
    }

    func tableView(_ tableView: UITableView, previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        contextMenuTargetedPreview(for: configuration)
    }

    func tableView(_ tableView: UITableView, previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        contextMenuTargetedPreview(for: configuration)
    }

    private func contextMenuTargetedPreview(for configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let identifier = configuration.identifier as? NSNumber,
              let indexPath = dataSource.indexPath(for: identifier.int64Value),
              let cell = tableView.cellForRow(at: indexPath)
        else { return nil }
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .systemBackground
        parameters.visiblePath = UIBezierPath(roundedRect: cell.bounds, cornerRadius: 16)
        return UITargetedPreview(view: cell, parameters: parameters)
    }

    private func contextAudioMenu(
        for item: IOSUIKitArticleTimelineItem
    ) -> UIMenu {
        guard let state = audioActionStates[item.article.id],
              !state.audioEnclosures.isEmpty else {
            return UIMenu(options: .displayInline, children: [])
        }

        var children: [UIMenuElement] = [
            UIAction(
                title: state.isInListeningList
                    ? String(localized: "Remove from Listening List")
                    : String(localized: "Add to Listening List"),
                image: UIImage(
                    systemName: state.isInListeningList
                        ? "minus.circle"
                        : "plus.circle"
                )
            ) { [weak self] _ in
                self?.onArticleMediaAction?(
                    item.article,
                    .setListeningList(!state.isInListeningList)
                )
            }
        ]

        if state.audioEnclosures.count == 1,
           let enclosure = state.audioEnclosures.first {
            children.append(contentsOf: contextEnclosureActions(
                article: item.article,
                enclosure: enclosure,
                index: 0,
                state: state
            ))
        } else {
            for (index, enclosure) in state.audioEnclosures.enumerated() {
                children.append(
                    UIMenu(
                        title: IOSArticleAudioPresentation.enclosureLabel(
                            enclosure,
                            index: index
                        ),
                        image: UIImage(systemName: "waveform"),
                        children: contextEnclosureActions(
                            article: item.article,
                            enclosure: enclosure,
                            index: index,
                            state: state
                        )
                    )
                )
            }
        }

        return UIMenu(
            title: String(localized: "Audio"),
            image: UIImage(systemName: "headphones"),
            children: children
        )
    }

    private func contextEnclosureActions(
        article: ArticleSummary,
        enclosure: Enclosure,
        index: Int,
        state: IOSArticleAudioActionState
    ) -> [UIMenuElement] {
        var actions: [UIMenuElement] = [
            UIAction(
                title: String(localized: "Play"),
                image: UIImage(systemName: "play.fill")
            ) { [weak self] _ in
                self?.onArticleMediaAction?(
                    article,
                    .play(enclosureID: enclosure.id)
                )
            }
        ]

        let download = state.downloads[enclosure.id]
        switch IOSArticleAudioPresentation.downloadAction(download) {
        case .download:
            actions.append(
                UIAction(
                    title: String(localized: "Download"),
                    image: UIImage(systemName: "arrow.down.circle")
                ) { [weak self] _ in
                    self?.onArticleMediaAction?(
                        article,
                        .requestDownload(enclosureID: enclosure.id)
                    )
                }
            )
        case .retry:
            actions.append(
                UIAction(
                    title: String(localized: "Retry Download"),
                    image: UIImage(systemName: "arrow.clockwise")
                ) { [weak self] _ in
                    self?.onArticleMediaAction?(
                        article,
                        .retryDownload(enclosureID: enclosure.id)
                    )
                }
            )
        case .delete:
            actions.append(
                UIAction(
                    title: String(localized: "Delete Download"),
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { [weak self] _ in
                    self?.onArticleMediaAction?(
                        article,
                        .deleteDownload(enclosureID: enclosure.id)
                    )
                }
            )
        case .pending:
            actions.append(
                UIAction(
                    title: String(localized: "Cancel Download"),
                    image: UIImage(systemName: "xmark.circle")
                ) { [weak self] _ in
                    self?.onArticleMediaAction?(
                        article,
                        .cancelDownload(enclosureID: enclosure.id)
                    )
                }
            )
        case .pendingDeletion:
            actions.append(
                UIAction(
                    title: String(localized: "Deletion Pending"),
                    image: UIImage(systemName: "clock"),
                    attributes: .disabled
                ) { _ in }
            )
        }

        return actions
    }

    private func contextNavigationActions(for item: IOSUIKitArticleTimelineItem) -> [UIMenuElement] {
        var actions: [UIMenuElement] = [
            UIAction(title: String(localized: "Open Original"), image: UIImage(systemName: "safari")) { [weak self] _ in self?.onArticleAction?(item.article, .original) },
            UIAction(title: String(localized: "Open in Reader"), image: UIImage(systemName: "doc.text")) { [weak self] _ in self?.onArticleAction?(item.article, .reader) },
            UIAction(title: String(localized: "Open in Miniflux"), image: UIImage(systemName: "arrow.up.forward.app")) { [weak self] _ in self?.onArticleAction?(item.article, .miniflux) },
        ]
        if item.content.hasComments {
            actions.append(UIAction(title: String(localized: "Open Comments"), image: UIImage(systemName: "bubble.left")) { [weak self] _ in self?.onArticleAction?(item.article, .comments) })
        }
        actions.append(contentsOf: [
            UIAction(title: String(localized: "Copy Link"), image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in self?.onArticleAction?(item.article, .copyLink) },
            UIAction(title: String(localized: "Share"), image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in self?.onArticleAction?(item.article, .share) },
        ])
        return actions
    }

    private func setRead(id: Int64, value: Bool) {
        guard let item = renderedItem(for: id) else { return }
        onSetRead?(item.article, value)
    }

    private func setStarred(id: Int64, value: Bool) {
        guard let item = renderedItem(for: id) else { return }
        onSetStarred?(item.article, value)
    }

    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        let layoutInputs = indexPaths.compactMap { indexPath -> IOSUIKitArticleLayoutInput? in
            guard let id = dataSource.itemIdentifier(for: indexPath), let item = renderedItem(for: id) else { return nil }
            return preparedLayoutInput(for: item)
        }
#if DEBUG
        layoutPrefetchInputCountForTesting += layoutInputs.count
#endif
        preparedLayoutCoordinator.prepare(layoutInputs, priority: .prefetch)

        guard mode.showsArticleImage,
              let direction = articleImagePrefetchDirection(for: indexPaths)
        else { return }

        let visibleIDs = (tableView.indexPathsForVisibleRows ?? [])
            .sorted { $0.row < $1.row }
            .compactMap(dataSource.itemIdentifier(for:))
        let candidateIDs = IOSArticleImagePrefetchPolicy.candidateIDs(
            orderedIDs: orderedIDs,
            visibleIDs: visibleIDs,
            imageIDs: imageArticleIDs,
            direction: direction,
            limit: Self.maximumOffscreenArticleImagePrefetchCount
        )
        reconcileArticleImagePrefetch(candidateIDs)
    }

    func tableView(_ tableView: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard let id = dataSource.itemIdentifier(for: indexPath) else { continue }
            prefetchTasks.removeValue(forKey: id)?.task.cancel()
        }
    }

    private func articleImagePrefetchDirection(for indexPaths: [IndexPath]) -> IOSArticleScrollDirection? {
        guard !indexPaths.isEmpty,
              let firstVisible = tableView.indexPathsForVisibleRows?.map(\.row).min(),
              let lastVisible = tableView.indexPathsForVisibleRows?.map(\.row).max()
        else { return nil }

        let rows = indexPaths.map(\.row)
        if rows.allSatisfy({ $0 > lastVisible }) { return .forward }
        if rows.allSatisfy({ $0 < firstVisible }) { return .backward }

        let forwardDistance = max(0, (rows.max() ?? lastVisible) - lastVisible)
        let backwardDistance = max(0, firstVisible - (rows.min() ?? firstVisible))
        guard forwardDistance != 0 || backwardDistance != 0 else { return nil }
        return forwardDistance >= backwardDistance ? .forward : .backward
    }

    private func reconcileArticleImagePrefetch(_ candidateIDs: [Int64]) {
        let selected: [(id: Int64, request: ArticleImageRequest)] = candidateIDs.compactMap { id in
            guard let item = renderedItem(for: id), let request = imageRequest(for: item) else { return nil }
            return (id, request)
        }
        let selectedIDs = Set(selected.map(\.id))

        for id in prefetchTasks.keys where !selectedIDs.contains(id) {
            prefetchTasks.removeValue(forKey: id)?.task.cancel()
        }

        for candidate in selected {
            if let existing = prefetchTasks[candidate.id], existing.request == candidate.request { continue }
            prefetchTasks.removeValue(forKey: candidate.id)?.task.cancel()
            let request = candidate.request
            let id = candidate.id
            let task = Task { [weak self] in
                defer {
                    if self?.prefetchTasks[id]?.request == request {
                        self?.prefetchTasks[id] = nil
                    }
                }
                _ = try? await ArticleImagePipeline.shared.prefetch(request)
            }
            prefetchTasks[id] = (request, task)
        }
    }

    private func imageRequest(for item: IOSUIKitArticleTimelineItem) -> ArticleImageRequest? {
        guard mode.showsArticleImage,
              let url = item.content.imageURL
        else { return nil }
        let geometry = IOSUIKitArticleGeometry(
            mode: mode,
            containerWidth: tableView.bounds.width
        )
        let targetSize = geometry.imageSize(hasImage: true)
        guard targetSize.width > 0, targetSize.height > 0 else { return nil }
        return ArticleImageRequest(
            url: url,
            targetSize: targetSize,
            displayScale: view.traitCollection.displayScale
        )
    }

    private func cancelAllPrefetch() {
#if DEBUG
        fullPrefetchCancellationCountForTesting &+= 1
#endif
        for prefetch in prefetchTasks.values { prefetch.task.cancel() }
        prefetchTasks.removeAll(keepingCapacity: true)
    }

    private func cancelIncompatibleImagePrefetch() {
        let incompatibleIDs = prefetchTasks.compactMap { id, prefetch in
            guard let item = renderedItem(for: id), imageRequest(for: item) == prefetch.request else { return id }
            return nil
        }
        for id in incompatibleIDs {
            prefetchTasks.removeValue(forKey: id)?.task.cancel()
        }
    }

    deinit {
        preparedWindowTask?.cancel()
        for prefetch in prefetchTasks.values { prefetch.task.cancel() }
    }

    func detachPresentationBridges() {
        presentationBridge?.unsubscribeArticles(self)
        feedIconPresentationBridge?.unsubscribeFeedIcons(self)
        presentationBridge = nil
        feedIconPresentationBridge = nil
    }

    func resetPerformanceMetrics() {
        performanceMetrics.reset()
        preparedLayoutCoordinator.resetInstrumentation()
    }
    func performanceSnapshot() -> IOSUIKitTimelinePerformanceSnapshot { performanceMetrics.snapshot(preparation: preparedLayoutCoordinator.snapshot()) }

    private func preparedLayoutInput(for item: IOSUIKitArticleTimelineItem) -> IOSUIKitArticleLayoutInput {
        .init(
            item: item,
            hasAudio: IOSArticleAudioPresentation.hasAudio(
                audioActionStates[item.article.id]
            ),
            mode: mode,
            previewLines: previewLines,
            showsRelativePublicationTime: showRelativePublicationTime,
            containerWidth: tableView.bounds.width,
            displayScale: view.traitCollection.displayScale,
            contentSizeCategory: view.traitCollection.preferredContentSizeCategory,
            layoutDirection: view.effectiveUserInterfaceLayoutDirection
        )
    }

    private func currentGeometryIdentity() -> IOSUIKitTimelineGeometryIdentity? {
        guard tableView.bounds.width > 0 else { return nil }
        return .init(
            mode: mode,
            previewLines: previewLines,
            showsRelativePublicationTime: showRelativePublicationTime,
            containerWidth: tableView.bounds.width,
            displayScale: view.traitCollection.displayScale,
            contentSizeCategory: view.traitCollection.preferredContentSizeCategory,
            layoutDirection: view.effectiveUserInterfaceLayoutDirection
        )
    }

    private func schedulePreparedLayoutWindow(for identity: IOSUIKitTimelineGeometryIdentity?) {
        guard let identity else { return }
        if scheduledPreparedWindowGeneration != nil {
            performanceMetrics.recordPreparedWindowGenerationSuperseded()
        }
        preparedWindowGeneration &+= 1
        let generation = preparedWindowGeneration
        scheduledPreparedWindowGeneration = generation
        preparedWindowTask?.cancel()
        preparedWindowTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            guard !Task.isCancelled,
                  self.preparedWindowGeneration == generation,
                  self.geometryIdentity == identity
            else {
                if self.scheduledPreparedWindowGeneration == generation {
                    self.scheduledPreparedWindowGeneration = nil
                }
                return
            }
            self.scheduledPreparedWindowGeneration = nil
            self.performanceMetrics.recordPreparedWindowReplacement()
            self.replacePreparedLayoutWindow()
        }
    }

    private func replacePreparedLayoutWindow() {
        guard tableView.bounds.width > 0 else { return }
        let visibleIndexes = (tableView.indexPathsForVisibleRows ?? []).map(\.row).sorted()
        let visibleIDs = visibleIndexes.compactMap { dataSource.itemIdentifier(for: .init(row: $0, section: 0)) }
        let nextIndex = min(orderedIDs.count, (visibleIndexes.last ?? -1) + 1)
        let nearbyIDs = orderedIDs.dropFirst(nextIndex).prefix(IOSUIKitArticleLayoutPreparationCoordinator.nearbyWindowLimit)
        let ids = Array(visibleIDs + nearbyIDs.filter { !visibleIDs.contains($0) })
        preparedLayoutCoordinator.replaceWindow(with: ids.compactMap { renderedItem(for: $0).map(preparedLayoutInput(for:)) }, visibleCount: visibleIDs.count)
    }

    private func prepareVisibleLayoutMetrics() {
        let ids = (tableView.indexPathsForVisibleRows ?? []).sorted { $0.row < $1.row }.compactMap(dataSource.itemIdentifier(for:))
        preparedLayoutCoordinator.prepare(ids.compactMap { renderedItem(for: $0).map(preparedLayoutInput(for:)) }, priority: .visible)
    }
}
