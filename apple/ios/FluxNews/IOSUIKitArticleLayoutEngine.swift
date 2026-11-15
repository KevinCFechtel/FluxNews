import UIKit
import CoreText

/// Immutable geometry input. Mutable presentation pixels and read/starred state
/// are intentionally absent: they must never affect article-card geometry.
struct IOSUIKitArticleLayoutInput: Hashable {
    let title: String
    let feedTitle: String
    let publishedDate: String
    let showsRelativePublicationTime: Bool
    let readingTime: String?
    let preview: String
    let hasImage: Bool
    let hasComments: Bool
    let hasAudio: Bool
    let mode: ArticlePresentationMode
    let previewLines: ArticlePreviewLines
    let containerWidth: CGFloat
    let displayScale: CGFloat
    let contentSizeCategory: UIContentSizeCategory
    let layoutDirection: UIUserInterfaceLayoutDirection

    init(item: IOSUIKitArticleTimelineItem, hasAudio: Bool = false, mode: ArticlePresentationMode, previewLines: ArticlePreviewLines, showsRelativePublicationTime: Bool = false, containerWidth: CGFloat, displayScale: CGFloat, contentSizeCategory: UIContentSizeCategory, layoutDirection: UIUserInterfaceLayoutDirection) {
        title = item.content.article.title
        feedTitle = item.content.article.feedTitle
        publishedDate = showsRelativePublicationTime ? item.content.publishedAge : item.content.publishedDate
        self.showsRelativePublicationTime = showsRelativePublicationTime
        readingTime = item.content.readingTime
        preview = item.content.article.preview
        hasImage = item.content.imageURL != nil
        hasComments = item.content.hasComments
        self.hasAudio = hasAudio
        self.mode = mode
        self.previewLines = previewLines
        self.containerWidth = containerWidth
        self.displayScale = displayScale
        self.contentSizeCategory = contentSizeCategory
        self.layoutDirection = layoutDirection
    }

    init(title: String, feedTitle: String, publishedDate: String, showsRelativePublicationTime: Bool = false, readingTime: String? = nil, preview: String, hasImage: Bool, hasComments: Bool, hasAudio: Bool = false, mode: ArticlePresentationMode, previewLines: ArticlePreviewLines, containerWidth: CGFloat, displayScale: CGFloat, contentSizeCategory: UIContentSizeCategory, layoutDirection: UIUserInterfaceLayoutDirection) {
        self.title = title
        self.feedTitle = feedTitle
        self.publishedDate = publishedDate
        self.showsRelativePublicationTime = showsRelativePublicationTime
        self.readingTime = readingTime
        self.preview = preview
        self.hasImage = hasImage; self.hasComments = hasComments; self.hasAudio = hasAudio; self.mode = mode; self.previewLines = previewLines
        self.containerWidth = containerWidth; self.displayScale = displayScale; self.contentSizeCategory = contentSizeCategory
        self.layoutDirection = layoutDirection
    }
}

struct IOSUIKitArticleLayoutKey: Hashable {
    let title: String
    let feedTitle: String
    let publishedDate: String
    let showsRelativePublicationTime: Bool
    let readingTime: String?
    let preview: String
    let hasComments: Bool
    let hasAudio: Bool
    let variant: IOSUIKitArticleCellLayoutVariant
    let previewLines: ArticlePreviewLines
    let containerWidthPixels: Int
    let displayScaleHundredths: Int
    let contentSizeCategory: String
    let layoutDirection: UIUserInterfaceLayoutDirection

    static func canonicalContainerWidthPixels(_ width: CGFloat, displayScale: CGFloat) -> Int {
        Int((width * max(displayScale, 1)).rounded())
    }

    static func canonicalDisplayScaleHundredths(_ displayScale: CGFloat) -> Int {
        Int((max(displayScale, 1) * 100).rounded())
    }

    init(_ input: IOSUIKitArticleLayoutInput) {
        let scale = max(input.displayScale, 1)
        let geometry = IOSUIKitArticleGeometry(
            mode: input.mode,
            containerWidth: input.containerWidth
        )
        title = input.title
        feedTitle = input.feedTitle
        let resolvedVariant = geometry.variant(hasImage: input.hasImage && input.mode.showsArticleImage)
        variant = resolvedVariant
        // The selected frozen publication representation and optional Miniflux
        // reading time are both part of the deterministic publication row.
        publishedDate = input.publishedDate
        showsRelativePublicationTime = input.showsRelativePublicationTime
        readingTime = input.readingTime
        preview = input.preview
        hasComments = input.hasComments
        hasAudio = input.hasAudio
        previewLines = input.previewLines
        containerWidthPixels = Self.canonicalContainerWidthPixels(input.containerWidth, displayScale: scale)
        displayScaleHundredths = Self.canonicalDisplayScaleHundredths(scale)
        contentSizeCategory = input.contentSizeCategory.rawValue
        layoutDirection = input.layoutDirection
    }
}

/// The Timeline's layout environment, using the same pixel canonicalization as
/// deterministic item metrics. This intentionally excludes device identity and
/// mutable article presentation state.
struct IOSUIKitTimelineGeometryIdentity: Hashable {
    let containerWidthPixels: Int
    let displayScaleHundredths: Int
    let contentSizeCategory: String
    let layoutDirection: UIUserInterfaceLayoutDirection
    let mode: ArticlePresentationMode
    let previewLines: ArticlePreviewLines
    let showsRelativePublicationTime: Bool

    init(mode: ArticlePresentationMode, previewLines: ArticlePreviewLines, showsRelativePublicationTime: Bool = false, containerWidth: CGFloat, displayScale: CGFloat, contentSizeCategory: UIContentSizeCategory, layoutDirection: UIUserInterfaceLayoutDirection) {
        containerWidthPixels = IOSUIKitArticleLayoutKey.canonicalContainerWidthPixels(containerWidth, displayScale: displayScale)
        displayScaleHundredths = IOSUIKitArticleLayoutKey.canonicalDisplayScaleHundredths(displayScale)
        self.contentSizeCategory = contentSizeCategory.rawValue
        self.layoutDirection = layoutDirection
        self.mode = mode
        self.previewLines = previewLines
        self.showsRelativePublicationTime = showsRelativePublicationTime
    }
}

struct IOSUIKitArticleLayoutMetrics: Equatable {
    let variant: IOSUIKitArticleCellLayoutVariant
    let cellSize: CGSize
    let contentFrame: CGRect
    let imageFrame: CGRect?
    let textFrame: CGRect
    let titleFrame: CGRect
    let metadataFrame: CGRect
    let unreadFrame: CGRect
    let feedIconFrame: CGRect
    let feedTitleFrame: CGRect
    let commentsFrame: CGRect?
    let starFrame: CGRect
    let dateFrame: CGRect
    let publicationTimeIconFrame: CGRect?
    let landscapeReadingTimeContainerFrame: CGRect?
    let landscapeReadingTimeIconFrame: CGRect?
    let landscapeReadingTimeFrame: CGRect?
    let previewFrame: CGRect?
    let previewContinuationFrame: CGRect?
    let previewSideText: String
    let previewContinuationText: String
    let horizontalInset: CGFloat
    let verticalInset: CGFloat
    let titleHeight: CGFloat
    let metadataHeight: CGFloat
    let previewHeight: CGFloat
    let textBlockHeight: CGFloat
}

/// A deterministic FIFO cache. Reuse is keyed exclusively by the canonical
/// layout identity, so mutable article presentation never invalidates it.
@MainActor
final class IOSUIKitPreparedArticleLayoutMetricsCache {
    let capacity: Int
    private var values: [IOSUIKitArticleLayoutKey: IOSUIKitArticleLayoutMetrics] = [:]
    private var insertionOrder: [IOSUIKitArticleLayoutKey] = []

    init(capacity: Int = 512) {
        self.capacity = max(1, capacity)
        values.reserveCapacity(self.capacity)
        insertionOrder.reserveCapacity(self.capacity)
    }

    var count: Int { values.count }

    func metrics(for key: IOSUIKitArticleLayoutKey) -> IOSUIKitArticleLayoutMetrics? {
        values[key]
    }

    func insert(_ metrics: IOSUIKitArticleLayoutMetrics, for key: IOSUIKitArticleLayoutKey) {
        if values.updateValue(metrics, forKey: key) != nil { return }
        if insertionOrder.count == capacity {
            values.removeValue(forKey: insertionOrder.removeFirst())
        }
        insertionOrder.append(key)
    }

    func removeAll() {
        values.removeAll(keepingCapacity: true)
        insertionOrder.removeAll(keepingCapacity: true)
    }
}

struct IOSUIKitArticleLayoutPreparationSnapshot: Equatable {
    let requests: UInt64
    let cacheHits: UInt64
    let cacheMisses: UInt64
    let measurementsStarted: UInt64
    let measurementsCompleted: UInt64
    let discardedResults: UInt64
    let cancellations: UInt64
    let maximumConcurrentMeasurements: UInt64
    let visibleRequests: UInt64
    let visibleCacheHits: UInt64
    let visibleCacheMisses: UInt64
    let prefetchRequests: UInt64
    let prefetchCacheHits: UInt64
    let prefetchCacheMisses: UInt64
}

/// Keeps at most two immutable Core Text measurements in flight. UIKit captures
/// inputs on the main actor; only the pure deterministic engine leaves it.
@MainActor
final class IOSUIKitArticleLayoutPreparationCoordinator {
    static let nearbyWindowLimit = 24
    enum Priority: Int {
        case prefetch
        case nearby
        case visible
    }

    private struct Request {
        let key: IOSUIKitArticleLayoutKey
        let input: IOSUIKitArticleLayoutInput
        let priority: Priority
        let sequence: UInt64
    }

    private struct ActiveMeasurement {
        let generation: UInt64
        let task: Task<Void, Never>
    }

    private let cache: IOSUIKitPreparedArticleLayoutMetricsCache
    private let maximumConcurrency: Int
    private let measurement: @Sendable (IOSUIKitArticleLayoutInput) async -> IOSUIKitArticleLayoutMetrics
    private var generation: UInt64 = 0
    private var sequence: UInt64 = 0
    private var pending: [IOSUIKitArticleLayoutKey: Request] = [:]
    private var active: [IOSUIKitArticleLayoutKey: ActiveMeasurement] = [:]
    private var requests: UInt64 = 0
    private var cacheHits: UInt64 = 0
    private var cacheMisses: UInt64 = 0
    private var measurementsStarted: UInt64 = 0
    private var measurementsCompleted: UInt64 = 0
    private var discardedResults: UInt64 = 0
    private var cancellations: UInt64 = 0
    private var maximumConcurrentMeasurements: UInt64 = 0
    private var visibleRequests: UInt64 = 0
    private var visibleCacheHits: UInt64 = 0
    private var visibleCacheMisses: UInt64 = 0
    private var prefetchRequests: UInt64 = 0
    private var prefetchCacheHits: UInt64 = 0
    private var prefetchCacheMisses: UInt64 = 0

    init(cache: IOSUIKitPreparedArticleLayoutMetricsCache? = nil, maximumConcurrency: Int = 2, measurement: @escaping @Sendable (IOSUIKitArticleLayoutInput) async -> IOSUIKitArticleLayoutMetrics = { input in
        await Task.detached(priority: .utility) {
            IOSUIKitArticleLayoutEngine.metrics(for: input)
        }.value
    }) {
        self.cache = cache ?? .init()
        self.maximumConcurrency = max(1, maximumConcurrency)
        self.measurement = measurement
    }

    func metrics(for input: IOSUIKitArticleLayoutInput, priority: Priority) -> IOSUIKitArticleLayoutMetrics? {
        let key = IOSUIKitArticleLayoutKey(input)
        if let metrics = cache.metrics(for: key) {
            recordCacheHit(priority)
            return metrics
        }
        enqueue(input, key: key, priority: priority)
        return nil
    }

    /// A displayed cell cannot wait for preparation. Retain its deterministic
    /// result in the same cache used by background preparation and retire an
    /// equivalent queued/running measurement so the miss converges to one value.
    func measureSynchronously(_ input: IOSUIKitArticleLayoutInput, priority: Priority) -> IOSUIKitArticleLayoutMetrics {
        let key = IOSUIKitArticleLayoutKey(input)
        if let metrics = cache.metrics(for: key) {
            recordCacheHit(priority)
            return metrics
        }

        pending.removeValue(forKey: key)
        if let activeMeasurement = active.removeValue(forKey: key) {
            activeMeasurement.task.cancel()
            cancellations &+= 1
        }
        let metrics = IOSUIKitArticleLayoutEngine.metrics(for: input)
        cache.insert(metrics, for: key)
        startNextMeasurements()
        return metrics
    }

    func replaceWindow(with inputs: [IOSUIKitArticleLayoutInput], visibleCount: Int) {
        generation &+= 1
        let cancelled = active.count
        active.values.forEach { $0.task.cancel() }
        active.removeAll(keepingCapacity: true)
        pending.removeAll(keepingCapacity: true)
        cancellations &+= UInt64(cancelled)
        for (index, input) in inputs.prefix(visibleCount + Self.nearbyWindowLimit).enumerated() {
            _ = metrics(for: input, priority: index < visibleCount ? .visible : .nearby)
        }
    }

    func prepare(_ inputs: [IOSUIKitArticleLayoutInput], priority: Priority) {
        for input in inputs {
            _ = metrics(for: input, priority: priority)
        }
    }

    func cancel() {
        generation &+= 1
        let cancelled = active.count
        active.values.forEach { $0.task.cancel() }
        active.removeAll(keepingCapacity: true)
        pending.removeAll(keepingCapacity: true)
        cancellations &+= UInt64(cancelled)
    }

    func snapshot() -> IOSUIKitArticleLayoutPreparationSnapshot {
        .init(requests: requests, cacheHits: cacheHits, cacheMisses: cacheMisses, measurementsStarted: measurementsStarted, measurementsCompleted: measurementsCompleted, discardedResults: discardedResults, cancellations: cancellations, maximumConcurrentMeasurements: maximumConcurrentMeasurements, visibleRequests: visibleRequests, visibleCacheHits: visibleCacheHits, visibleCacheMisses: visibleCacheMisses, prefetchRequests: prefetchRequests, prefetchCacheHits: prefetchCacheHits, prefetchCacheMisses: prefetchCacheMisses)
    }

    func resetInstrumentation() {
        requests = 0; cacheHits = 0; cacheMisses = 0; measurementsStarted = 0; measurementsCompleted = 0
        discardedResults = 0; cancellations = 0; maximumConcurrentMeasurements = UInt64(active.count)
        visibleRequests = 0; visibleCacheHits = 0; visibleCacheMisses = 0
        prefetchRequests = 0; prefetchCacheHits = 0; prefetchCacheMisses = 0
    }

    private func enqueue(_ input: IOSUIKitArticleLayoutInput, key: IOSUIKitArticleLayoutKey, priority: Priority) {
        requests &+= 1
        cacheMisses &+= 1
        if priority == .visible { visibleRequests &+= 1; visibleCacheMisses &+= 1 }
        if priority == .prefetch { prefetchRequests &+= 1; prefetchCacheMisses &+= 1 }
        if active[key] != nil { return }
        if let existing = pending[key] {
            guard priority.rawValue > existing.priority.rawValue else { return }
            pending[key] = .init(key: key, input: input, priority: priority, sequence: existing.sequence)
            return
        }
        sequence &+= 1
        pending[key] = .init(key: key, input: input, priority: priority, sequence: sequence)
        startNextMeasurements()
    }

    private func startNextMeasurements() {
        while active.count < maximumConcurrency,
              let request = pending.values.max(by: { lhs, rhs in
                  lhs.priority == rhs.priority ? lhs.sequence > rhs.sequence : lhs.priority.rawValue < rhs.priority.rawValue
              }) {
            pending.removeValue(forKey: request.key)
            let requestGeneration = generation
            let measurement = measurement
            measurementsStarted &+= 1
            let task = Task { [weak self] in
                let metrics = await measurement(request.input)
                self?.finish(request, metrics: metrics, generation: requestGeneration, cancelled: Task.isCancelled)
            }
            active[request.key] = .init(generation: requestGeneration, task: task)
            maximumConcurrentMeasurements = max(maximumConcurrentMeasurements, UInt64(active.count))
        }
    }

    private func finish(_ request: Request, metrics: IOSUIKitArticleLayoutMetrics, generation resultGeneration: UInt64, cancelled: Bool) {
        if active[request.key]?.generation == resultGeneration {
            active.removeValue(forKey: request.key)
        }
        guard !cancelled, resultGeneration == generation else {
            discardedResults &+= 1
            startNextMeasurements()
            return
        }
        cache.insert(metrics, for: request.key)
        measurementsCompleted &+= 1
        startNextMeasurements()
    }

    private func recordCacheHit(_ priority: Priority) {
        cacheHits &+= 1
        if priority == .visible { visibleCacheHits &+= 1 }
        if priority == .prefetch { prefetchCacheHits &+= 1 }
    }
}

/// Slot sizes for the metadata glyphs, grown with the text they accompany.
///
/// Apple's guidance is that glyphs beside text scale with it, but not without
/// bound here: the feed icon is a bitmap prepared at a fixed size, and at the
/// largest accessibility categories an unclamped slot would both dwarf the row
/// and upscale that bitmap badly. The cap keeps the proportion sane and the
/// raster acceptable; lifting it means threading the scaled size through the
/// feed-icon pipeline as well.
struct IOSUIKitArticleAccessoryMetrics: Equatable {
    static let maximumScale: CGFloat = 1.5

    let unread: CGFloat
    let feedIcon: CGFloat
    let star: CGFloat
    let comments: CGFloat
    let infoIcon: CGFloat

    init(contentSizeCategory: UIContentSizeCategory) {
        let traits = UITraitCollection(preferredContentSizeCategory: contentSizeCategory)
        let reference = IOSUIKitArticleGeometry.feedIconSize
        let scaled = UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: reference, compatibleWith: traits)
        // Whole points keep every derived frame on a predictable grid.
        let scale = min(Self.maximumScale, max(1, scaled / reference))
        unread = (IOSUIKitArticleGeometry.unreadSize * scale).rounded()
        feedIcon = (reference * scale).rounded()
        star = (IOSUIKitArticleGeometry.starSlotSize * scale).rounded()
        comments = (IOSUIKitArticleGeometry.commentSlotSize * scale).rounded()
        infoIcon = (IOSUIKitArticleGeometry.dateRowInfoIconSize * scale).rounded()
    }
}

enum IOSArticleAccessoryKind: Equatable, CaseIterable {
    case unread
    case star
    case comments
    case audio
}

enum IOSArticleAccessoryOrdering {
    /// Semantic order measured from the visual outer edge inward, or from the
    /// top of a vertical rail downward. Audio owns its optional duration and
    /// therefore remains one accessory rather than two independent slots.
    static let outerToInner: [IOSArticleAccessoryKind] = [.unread, .star, .comments, .audio]

    /// UIKit lays a horizontal trailing group from leading to trailing, so the
    /// semantic order appears reversed in coordinate order.
    static let horizontalLeadingToTrailing: [IOSArticleAccessoryKind] = Array(outerToInner.reversed())
}

/// The non-text geometry contract shared by the renderer and deterministic sizing.
/// It deliberately has no presentation pixels or read/starred state.
struct IOSUIKitArticleGeometry: Equatable {
    static let wideInsetThreshold: CGFloat = 700
    /// Mirrors `ArticlePresentationLayout.usesLandscapeVisual`, which applies the
    /// same threshold to the `.visual` mode.
    static let wideContainerThreshold: CGFloat = 600
    static let compactInset: CGFloat = 10
    static let visualInset: CGFloat = 16
    static let wideInset: CGFloat = 28
    static let compactVerticalPadding: CGFloat = 11
    static let portraitVerticalPadding: CGFloat = 15
    static let landscapeVerticalPadding: CGFloat = 13
    static let textSpacing: CGFloat = 7
    /// Spacing between the full-width Visual portrait image and its text stack.
    static let portraitSpacing: CGFloat = 10
    static let dateRowInfoIconSize: CGFloat = 14
    // "Visual compact": a thumbnail beside the title, with the metadata bar above
    // and — on a narrow container — the preview underneath.
    static let sideTitleImageAllocation: CGFloat = 0.32
    static let sideTitleImageAspectRatio: CGFloat = 4.0 / 3
    static let sideTitleSpacing: CGFloat = 12
    static let landscapeSpacing: CGFloat = 14
    static let landscapeDateReadingTimeSpacing: CGFloat = 4
    static let landscapeReadingTimeIconTextSpacing: CGFloat = 4
    static let unreadSize: CGFloat = 6
    static let feedIconSize: CGFloat = 22
    static let articleImageCornerRadius: CGFloat = 10
    static let starSlotSize: CGFloat = 17
    static let commentSlotSize: CGFloat = 17
    static let metadataLeadingSpacing: CGFloat = 6
    static let metadataAccessorySpacing: CGFloat = 6
    static let metadataTitleSpacing: CGFloat = 6

    let mode: ArticlePresentationMode
    let containerWidth: CGFloat
    let horizontalInset: CGFloat
    let availableWidth: CGFloat
    let isLandscapeVisual: Bool
    /// `Visual compact`: a thumbnail beside the title instead of a full-width image.
    let usesSideTitle: Bool
    let isWideContainer: Bool
    let verticalPadding: CGFloat

    init(mode: ArticlePresentationMode, containerWidth: CGFloat) {
        self.mode = mode
        self.containerWidth = containerWidth
        horizontalInset = containerWidth > Self.wideInsetThreshold ? Self.wideInset : mode == .compact ? Self.compactInset : Self.visualInset
        availableWidth = max(0, containerWidth - horizontalInset * 2)
        isLandscapeVisual = ArticlePresentationLayout.usesLandscapeVisual(mode: mode, availableWidth: availableWidth)
        usesSideTitle = mode == .visualCompact
        // `isLandscapeVisual` is false for every mode but `.visual`, so the
        // side-title variants need the width test on its own.
        isWideContainer = availableWidth > Self.wideContainerThreshold
        verticalPadding = mode == .compact ? Self.compactVerticalPadding : isLandscapeVisual ? Self.landscapeVerticalPadding : Self.portraitVerticalPadding
    }

    func variant(hasImage: Bool) -> IOSUIKitArticleCellLayoutVariant {
        guard mode.showsArticleImage else { return .compact }
        // Image-less variants keep the same semantic text order as rows with
        // images: metadata -> title -> publication row -> preview. Visual compact
        // only selects a different image-bearing geometry when an image exists.
        guard hasImage else { return usesSideTitle ? .visualSideTitleTextOnly : .visualTextOnly }
        // On a wide container the preview has room to sit beside the image.
        if usesSideTitle { return isWideContainer ? .visualSideTitleWide : .visualSideTitle }
        if isLandscapeVisual { return .visualLandscape }
        return .visualPortrait
    }

    func imageSize(hasImage: Bool) -> CGSize {
        guard hasImage, mode.showsArticleImage else { return .zero }
        if usesSideTitle {
            // Same proportion at every width; only what sits beside it changes.
            let width = (availableWidth * Self.sideTitleImageAllocation).rounded()
            return .init(width: width, height: (width / Self.sideTitleImageAspectRatio).rounded())
        }
        if isLandscapeVisual {
            let width = ArticlePresentationLayout.landscapeImageWidth(availableWidth: availableWidth)
            return .init(width: width, height: ArticlePresentationLayout.landscapeImageHeight(imageWidth: width))
        }
        // Visual portrait uses the full available content width.
        let width = availableWidth.rounded()
        return .init(width: width, height: width * (1 / ArticlePresentationLayout.portraitImageAspectRatio))
    }

    func metadataLayout(width: CGFloat, hasComments: Bool, hasAudio: Bool = false, height: CGFloat, accessories: IOSUIKitArticleAccessoryMetrics) -> MetadataLayout {
        let trailingAccessorySlots = staticAccessorySlotWidths(
            hasComments: hasComments,
            hasAudio: hasAudio,
            accessories: accessories
        )
        let commentsWidth = hasComments ? accessories.comments : 0
        let trailingAccessoriesWidth = trailingAccessorySlots.reduce(0, +) + CGFloat(max(0, trailingAccessorySlots.count - 1)) * Self.metadataAccessorySpacing
        // Leading edge: feed icon, then the feed name. Trailing edge is the
        // horizontal projection of the stable semantic accessory order:
        // unread outermost, then star, comments, and eventually audio.
        let feedTitleWidth = max(0, width - accessories.feedIcon - Self.metadataLeadingSpacing - Self.metadataTitleSpacing - trailingAccessoriesWidth)
        let unreadX = width - accessories.unread
        let starX = unreadX - Self.metadataAccessorySpacing - accessories.star
        return .init(
            unreadX: unreadX,
            feedIconX: 0,
            feedTitleX: accessories.feedIcon + Self.metadataLeadingSpacing,
            feedTitleWidth: feedTitleWidth,
            commentsX: starX - (hasComments ? Self.metadataAccessorySpacing + accessories.comments : 0),
            commentsWidth: commentsWidth,
            starX: starX,
            height: height
        )
    }

    /// Existing horizontal slots in coordinate order. A future audio slot is
    /// inserted on the leading/inner side of comments; it must never displace
    /// unread from the outer edge or star from the second position.
    func staticAccessorySlotWidths(
        hasComments: Bool,
        hasAudio: Bool = false,
        accessories: IOSUIKitArticleAccessoryMetrics
    ) -> [CGFloat] {
        (hasAudio ? [accessories.comments] : [])
            + (hasComments ? [accessories.comments] : [])
            + [accessories.star, accessories.unread]
    }

    struct MetadataLayout: Equatable {
        let unreadX: CGFloat
        let feedIconX: CGFloat
        let feedTitleX: CGFloat
        let feedTitleWidth: CGFloat
        let commentsX: CGFloat
        let commentsWidth: CGFloat
        let starX: CGFloat
        let height: CGFloat
    }
}

/// A Core Text break plan shared by the background sizing engine and the cell.
/// The preview has a fixed total line budget. Only the lines fitting between
/// the date and the thumbnail bottom use the narrow column; the rest use full
/// width below it. No main-thread text measurement is performed during reuse.
struct IOSVisualCompactPreviewFlow: Equatable {
    let beside: String
    let below: String
    let besideHeight: CGFloat
    let belowHeight: CGFloat

    static func prepare(
        text: String, narrowWidth: CGFloat, fullWidth: CGFloat,
        heightBesideImage: CGFloat, maxLines: Int, font: UIFont,
        displayScale: CGFloat
    ) -> Self {
        guard !text.isEmpty, maxLines > 0, fullWidth > 0 else {
            return .init(beside: "", below: "", besideHeight: 0, belowHeight: 0)
        }
        let scale = max(1, displayScale)
        let lineStep = font.lineHeight + font.leading
        // A side-column line only needs to START above the image bottom.
        // It can extend below that edge without ever crossing the image:
        // the whole line remains in the narrow column. Requiring the entire
        // glyph height to fit leaves a visible empty strip before the first
        // full-width continuation line.
        let sideLines = narrowWidth > 0 && heightBesideImage > 0
            ? min(maxLines, max(0, Int(ceil(
                heightBesideImage / max(1, lineStep)
            )))) : 0

        let content = text as NSString
        let attributed = NSAttributedString(
            string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: font as CTFont]
        )
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        var consumed = 0
        var visibleSideLines = 0
        while consumed < content.length && visibleSideLines < sideLines {
            var length = CTTypesetterSuggestLineBreak(typesetter, consumed, Double(narrowWidth))
            if length == 0 {
                length = CTTypesetterSuggestClusterBreak(typesetter, consumed, Double(narrowWidth))
            }
            guard length > 0 else { break }
            consumed += length
            visibleSideLines += 1
        }

        let side = content.substring(to: consumed).trimmingCharacters(in: .newlines)
        let rest = content.substring(from: consumed)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let belowLines = max(0, maxLines - visibleSideLines)
        let besideHeight = visibleSideLines > 0
            ? ceil((CGFloat(visibleSideLines) * font.lineHeight
                + CGFloat(visibleSideLines - 1) * font.leading) * scale) / scale
            : 0
        let belowHeight: CGFloat
        if rest.isEmpty || belowLines == 0 {
            belowHeight = 0
        } else {
            // Equivalent to the existing Core Text row measurement.
            let restText = NSAttributedString(
                string: rest, attributes: [kCTFontAttributeName as NSAttributedString.Key: font as CTFont]
            )
            let restTypesetter = CTTypesetterCreateWithAttributedString(restText)
            var index = 0
            var lines = 0
            while index < restText.length && lines < belowLines {
                var length = CTTypesetterSuggestLineBreak(restTypesetter, index, Double(fullWidth))
                if length == 0 {
                    length = CTTypesetterSuggestClusterBreak(restTypesetter, index, Double(fullWidth))
                }
                guard length > 0 else { break }
                index += length
                lines += 1
            }
            belowHeight = ceil((CGFloat(lines) * font.lineHeight
                + CGFloat(max(0, lines - 1)) * font.leading) * scale) / scale
        }
        return .init(
            beside: side, below: belowLines > 0 ? rest : "",
            besideHeight: besideHeight, belowHeight: belowHeight
        )
    }
}

/// Deterministic, cell-free counterpart to the current UIKit constraint geometry.
/// Core Text typesetting is immutable and does not require main-actor view ownership.
enum IOSUIKitArticleLayoutEngine {
    static func metrics(for input: IOSUIKitArticleLayoutInput) -> IOSUIKitArticleLayoutMetrics {
        let scale = max(input.displayScale, 1)
        let geometry = IOSUIKitArticleGeometry(
            mode: input.mode,
            containerWidth: input.containerWidth
        )
        let hasImage = input.hasImage && input.mode.showsArticleImage
        let variant = geometry.variant(hasImage: hasImage)
        var imageSize = geometry.imageSize(hasImage: hasImage)
        if variant == .visualPortrait {
            // NSLayoutConstraint resolves the 16:9 frame on the display-pixel grid.
            imageSize.height = pixelAligned(imageSize.height, scale: scale)
        }
        let textWidth = variant == .visualLandscape ? max(0, geometry.availableWidth - imageSize.width - IOSUIKitArticleGeometry.landscapeSpacing) : geometry.availableWidth
        // In the side-title variant the image sits beside the title and the date,
        // so those two are narrower. The metadata bar and the preview keep the
        // full width — the metadata because the feed name is squeezed first, the
        // preview because it needs the room to read as a paragraph.
        let isSideTitleVariant = variant == .visualSideTitle || variant == .visualSideTitleWide
        // Every productive article layout uses one semantic order:
        // metadata -> title -> publication row -> preview.
        let titleWidth = isSideTitleVariant
            ? max(0, geometry.availableWidth - imageSize.width - IOSUIKitArticleGeometry.sideTitleSpacing)
            : textWidth
        let infoWidth = textWidth
        // On a wide container the preview joins the column beside the image
        // rather than running underneath it.
        let previewWidth: CGFloat
        if variant == .visualSideTitleWide {
            previewWidth = titleWidth
        } else {
            previewWidth = infoWidth
        }

        let accessories = IOSUIKitArticleAccessoryMetrics(contentSizeCategory: input.contentSizeCategory)
        let titleFont = font(.headline, category: input.contentSizeCategory, bold: false)
        let titleHeight = coreTextHeight(input.title, font: titleFont, width: titleWidth, maximumLines: nil, displayScale: scale)
        let metadataHeight = max(accessories.feedIcon, font(.subheadline, category: input.contentSizeCategory, bold: true).lineHeight)
        let dateFont = font(.caption1, category: input.contentSizeCategory, bold: false)
        let usesDateRowReadingTime = input.readingTime != nil
        // Reading time is one inline metadata group with the publication value:
        // "date · [doc.text] duration". The separator stays attached to the date
        // so the optional reading-time container can follow it immediately.
        let publicationText = usesDateRowReadingTime
            ? "\(input.publishedDate) ·"
            : input.publishedDate
        let dateHeight = fixedLineHeight(publicationText, font: dateFont)
        let publicationDateTextWidth = coreTextWidth(publicationText, font: dateFont, displayScale: scale)
        let publicationTimeIconSize = input.showsRelativePublicationTime
            ? min(accessories.infoIcon, dateHeight)
            : 0
        let publicationTimeLeadingWidth = input.showsRelativePublicationTime
            ? publicationTimeIconSize + IOSUIKitArticleGeometry.landscapeReadingTimeIconTextSpacing
            : 0
        let previewFont = font(.subheadline, category: input.contentSizeCategory, bold: false)
        let sidePreviewFlow: IOSVisualCompactPreviewFlow?
        if isSideTitleVariant {
            let topOfPreview = titleHeight + IOSUIKitArticleGeometry.textSpacing
                + dateHeight + IOSUIKitArticleGeometry.textSpacing
            sidePreviewFlow = IOSVisualCompactPreviewFlow.prepare(
                text: input.preview,
                narrowWidth: titleWidth,
                fullWidth: infoWidth,
                heightBesideImage: max(0, imageSize.height - topOfPreview),
                maxLines: input.previewLines.rawValue,
                font: previewFont, displayScale: scale
            )
        } else {
            sidePreviewFlow = nil
        }
        let previewHeight = sidePreviewFlow?.besideHeight
            ?? coreTextHeight(input.preview, font: previewFont, width: previewWidth,
                maximumLines: input.previewLines.rawValue, displayScale: scale)
        let continuationHeight = sidePreviewFlow?.belowHeight ?? 0
        // This is one continuous paragraph, not two independently spaced
        // paragraphs. Only keep the normal text spacing if there was no line
        // beside the image at all.
        let continuationSpacing = (sidePreviewFlow?.besideHeight ?? 0) > 0
            ? CGFloat.zero : IOSUIKitArticleGeometry.textSpacing

        let dateRowReadingTimeTextWidth = usesDateRowReadingTime
            ? coreTextWidth(input.readingTime ?? "", font: dateFont, displayScale: scale)
            : 0
        let dateRowReadingTimeIconSize = usesDateRowReadingTime
            ? min(accessories.infoIcon, dateHeight)
            : 0
        let dateRowReadingTimeBlockWidth = usesDateRowReadingTime
            ? dateRowReadingTimeIconSize
                + IOSUIKitArticleGeometry.landscapeReadingTimeIconTextSpacing
                + dateRowReadingTimeTextWidth
            : 0

        let textBlockHeight: CGFloat
        // The column that shares its row with the image. On a wide container the
        // preview belongs to it, so it is part of the height the image competes
        // with; otherwise the preview follows below the whole row.
        let sideTitleColumnHeight = titleHeight + IOSUIKitArticleGeometry.textSpacing + dateHeight
            + (isSideTitleVariant && previewHeight > 0
                ? IOSUIKitArticleGeometry.textSpacing + previewHeight : 0)
        // A side preview may end before the thumbnail bottom. Continuation
        // starts beneath the taller of the image and text column.
        let sideTitleRowHeight = max(sideTitleColumnHeight, imageSize.height)
        if isSideTitleVariant {
            textBlockHeight = metadataHeight + IOSUIKitArticleGeometry.textSpacing
                + sideTitleRowHeight
                + (continuationHeight > 0 ? continuationSpacing + continuationHeight : 0)
        } else if variant == .visualSideTitleTextOnly {
            textBlockHeight = metadataHeight + IOSUIKitArticleGeometry.textSpacing
                + sideTitleRowHeight
                + (previewHeight > 0 ? IOSUIKitArticleGeometry.textSpacing + previewHeight : 0)
        } else {
            textBlockHeight = metadataHeight
                + IOSUIKitArticleGeometry.textSpacing + titleHeight
                + IOSUIKitArticleGeometry.textSpacing + dateHeight
                + (previewHeight > 0 ? IOSUIKitArticleGeometry.textSpacing + previewHeight : 0)
        }
        let contentHeight: CGFloat
        switch variant {
        case .visualPortrait:
            // Full-width image -> metadata -> title -> date/reading time -> preview.
            contentHeight = imageSize.height
                + IOSUIKitArticleGeometry.portraitSpacing
                + textBlockHeight
        case .visualLandscape: contentHeight = max(imageSize.height, textBlockHeight)
        default: contentHeight = textBlockHeight
        }
        let totalHeight = ceil(contentHeight + geometry.verticalPadding * 2)
        let contentFrame = CGRect(x: geometry.horizontalInset, y: geometry.verticalPadding, width: geometry.availableWidth, height: contentHeight)
        let logicalImageX: CGFloat
        if isSideTitleVariant {
            logicalImageX = geometry.horizontalInset + geometry.availableWidth - imageSize.width
        } else {
            logicalImageX = geometry.horizontalInset
        }
        // Side-title starts below metadata. Standard Visual portrait starts with
        // its full-width image at the top of the cell.
        let logicalImageY: CGFloat
        if isSideTitleVariant {
            logicalImageY = geometry.verticalPadding + metadataHeight + IOSUIKitArticleGeometry.textSpacing
        } else {
            logicalImageY = geometry.verticalPadding
        }
        let imageFrame: CGRect? = imageSize == .zero ? nil : CGRect(x: physicalX(logicalX: logicalImageX, width: imageSize.width, in: input.containerWidth, direction: input.layoutDirection), y: logicalImageY, width: imageSize.width, height: imageSize.height)
        let logicalTextX = variant == .visualLandscape ? geometry.horizontalInset + imageSize.width + IOSUIKitArticleGeometry.landscapeSpacing : geometry.horizontalInset
        let textOriginY = variant == .visualPortrait
            ? logicalImageY + imageSize.height + IOSUIKitArticleGeometry.portraitSpacing
            : geometry.verticalPadding
        let textOrigin = CGPoint(
            x: physicalX(logicalX: logicalTextX, width: textWidth, in: input.containerWidth, direction: input.layoutDirection),
            y: textOriginY
        )
        let metadataFrame = CGRect(x: textOrigin.x, y: textOrigin.y, width: infoWidth, height: metadataHeight)
        let titleTop = metadataFrame.maxY + IOSUIKitArticleGeometry.textSpacing
        let titleFrame = CGRect(x: textOrigin.x, y: titleTop, width: titleWidth, height: titleHeight)
        let metadataLayout = geometry.metadataLayout(
            width: infoWidth,
            hasComments: input.hasComments,
            hasAudio: input.hasAudio,
            height: metadataHeight,
            accessories: accessories
        )
        func metadataX(_ logicalX: CGFloat, width: CGFloat) -> CGFloat { input.layoutDirection == .rightToLeft ? metadataFrame.maxX - logicalX - width : metadataFrame.minX + logicalX }
        let feedIconFrame = CGRect(x: metadataX(metadataLayout.feedIconX, width: accessories.feedIcon), y: metadataFrame.midY - accessories.feedIcon / 2, width: accessories.feedIcon, height: accessories.feedIcon)
        let feedTitleFrame = CGRect(x: metadataX(metadataLayout.feedTitleX, width: metadataLayout.feedTitleWidth), y: metadataFrame.minY, width: metadataLayout.feedTitleWidth, height: metadataHeight)

        let unreadFrame = CGRect(
            x: metadataX(metadataLayout.unreadX, width: accessories.unread),
            y: metadataFrame.midY - accessories.unread / 2,
            width: accessories.unread,
            height: accessories.unread
        )
        let commentsFrame = input.hasComments
            ? CGRect(
                x: metadataX(metadataLayout.commentsX, width: accessories.comments),
                y: metadataFrame.midY - accessories.comments / 2,
                width: accessories.comments,
                height: accessories.comments
            )
            : nil
        let starFrame = CGRect(
            x: metadataX(metadataLayout.starX, width: accessories.star),
            y: metadataFrame.midY - accessories.star / 2,
            width: accessories.star,
            height: accessories.star
        )

        let dateFrame: CGRect
        let publicationTimeIconFrame: CGRect?
        let landscapeReadingTimeContainerFrame: CGRect?
        let landscapeReadingTimeIconFrame: CGRect?
        let landscapeReadingTimeFrame: CGRect?

        let dateRowY = titleFrame.maxY + IOSUIKitArticleGeometry.textSpacing
        let dateRowWidth = isSideTitleVariant ? titleWidth : infoWidth
        let readingTimeReservedWidth = usesDateRowReadingTime && dateRowReadingTimeBlockWidth > 0
            ? IOSUIKitArticleGeometry.landscapeDateReadingTimeSpacing + dateRowReadingTimeBlockWidth
            : 0
        let availableDateWidth = max(
            0,
            dateRowWidth - publicationTimeLeadingWidth - readingTimeReservedWidth
        )
        let dateWidth = min(publicationDateTextWidth, availableDateWidth)
        let dateLogicalX = logicalTextX + publicationTimeLeadingWidth
        dateFrame = CGRect(
            x: physicalX(
                logicalX: dateLogicalX,
                width: dateWidth,
                in: input.containerWidth,
                direction: input.layoutDirection
            ),
            y: dateRowY,
            width: dateWidth,
            height: dateHeight
        )
        publicationTimeIconFrame = input.showsRelativePublicationTime
            ? CGRect(
                x: physicalX(
                    logicalX: logicalTextX,
                    width: publicationTimeIconSize,
                    in: input.containerWidth,
                    direction: input.layoutDirection
                ),
                y: dateRowY + (dateHeight - publicationTimeIconSize) / 2,
                width: publicationTimeIconSize,
                height: publicationTimeIconSize
            )
            : nil

        if usesDateRowReadingTime, dateRowReadingTimeBlockWidth > 0 {

                let blockLogicalX = dateLogicalX
                    + dateWidth
                    + IOSUIKitArticleGeometry.landscapeDateReadingTimeSpacing
                let blockX = physicalX(
                    logicalX: blockLogicalX,
                    width: dateRowReadingTimeBlockWidth,
                    in: input.containerWidth,
                    direction: input.layoutDirection
                )
                landscapeReadingTimeContainerFrame = CGRect(
                    x: blockX,
                    y: dateRowY,
                    width: dateRowReadingTimeBlockWidth,
                    height: dateHeight
                )
                landscapeReadingTimeIconFrame = CGRect(
                    x: physicalX(
                        logicalX: blockLogicalX,
                        width: dateRowReadingTimeIconSize,
                        in: input.containerWidth,
                        direction: input.layoutDirection
                    ),
                    y: dateRowY + (dateHeight - dateRowReadingTimeIconSize) / 2,
                    width: dateRowReadingTimeIconSize,
                    height: dateRowReadingTimeIconSize
                )
                landscapeReadingTimeFrame = CGRect(
                    x: physicalX(
                        logicalX: blockLogicalX
                            + dateRowReadingTimeIconSize
                            + IOSUIKitArticleGeometry.landscapeReadingTimeIconTextSpacing,
                        width: dateRowReadingTimeTextWidth,
                        in: input.containerWidth,
                        direction: input.layoutDirection
                    ),
                    y: dateRowY,
                    width: dateRowReadingTimeTextWidth,
                    height: dateHeight
                )
        } else {
            landscapeReadingTimeContainerFrame = nil
            landscapeReadingTimeIconFrame = nil
            landscapeReadingTimeFrame = nil
        }
        let previewTop: CGFloat
        if variant == .visualSideTitleTextOnly {
            previewTop = titleTop + sideTitleRowHeight + IOSUIKitArticleGeometry.textSpacing
        } else {
            previewTop = dateFrame.maxY + IOSUIKitArticleGeometry.textSpacing
        }
        let actualPreviewWidth = isSideTitleVariant ? titleWidth : previewWidth
        let previewFrame = previewHeight == 0 ? nil : CGRect(
            x: textOrigin.x, y: previewTop, width: actualPreviewWidth, height: previewHeight
        )
        let previewContinuationFrame: CGRect?
        if continuationHeight > 0 && isSideTitleVariant {
            let nextY = titleTop + sideTitleRowHeight + continuationSpacing
            previewContinuationFrame = CGRect(
                x: textOrigin.x, y: nextY,
                width: infoWidth, height: continuationHeight
            )
        } else {
            previewContinuationFrame = nil
        }
        return .init(
            variant: variant,
            cellSize: .init(width: input.containerWidth, height: totalHeight),
            contentFrame: contentFrame,
            imageFrame: imageFrame,
            textFrame: CGRect(x: textOrigin.x, y: textOrigin.y, width: infoWidth, height: textBlockHeight),
            titleFrame: titleFrame,
            metadataFrame: metadataFrame,
            unreadFrame: unreadFrame,
            feedIconFrame: feedIconFrame,
            feedTitleFrame: feedTitleFrame,
            commentsFrame: commentsFrame,
            starFrame: starFrame,
            dateFrame: dateFrame,
            publicationTimeIconFrame: publicationTimeIconFrame,
            landscapeReadingTimeContainerFrame: landscapeReadingTimeContainerFrame,
            landscapeReadingTimeIconFrame: landscapeReadingTimeIconFrame,
            landscapeReadingTimeFrame: landscapeReadingTimeFrame,
            previewFrame: previewFrame,
            previewContinuationFrame: previewContinuationFrame,
            previewSideText: sidePreviewFlow?.beside ?? input.preview,
            previewContinuationText: sidePreviewFlow?.below ?? "",
            horizontalInset: geometry.horizontalInset,
            verticalInset: geometry.verticalPadding,
            titleHeight: titleHeight,
            metadataHeight: metadataHeight,
            previewHeight: previewHeight,
            textBlockHeight: textBlockHeight
        )
    }

    private static func pixelAligned(_ length: CGFloat, scale: CGFloat) -> CGFloat {
        (length * scale).rounded() / scale
    }

    private static func physicalX(logicalX: CGFloat, width: CGFloat, in containerWidth: CGFloat, direction: UIUserInterfaceLayoutDirection) -> CGFloat {
        direction == .rightToLeft ? containerWidth - logicalX - width : logicalX
    }

    private static func font(_ style: UIFont.TextStyle, category: UIContentSizeCategory, bold: Bool) -> UIFont {
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let font = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits)
        guard bold else { return font }
        return UIFont(descriptor: font.fontDescriptor.withSymbolicTraits(.traitBold) ?? font.fontDescriptor, size: font.pointSize)
    }

    private static func fixedLineHeight(_ text: String, font: UIFont) -> CGFloat {
        text.isEmpty ? 0 : font.lineHeight
    }

    private static func coreTextWidth(_ text: String, font: UIFont, displayScale: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let coreTextFont = font as CTFont
        let attributedText = NSAttributedString(
            string: text,
            attributes: [kCTFontAttributeName as NSAttributedString.Key: coreTextFont]
        )
        let line = CTLineCreateWithAttributedString(attributedText)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let scale = max(displayScale, 1)
        return ceil(width * scale) / scale
    }

    /// Counts only the lines that can affect visible height. The unbounded title
    /// consumes every line; preview stops as soon as its configured limit is reached.
    private static func coreTextHeight(_ text: String, font: UIFont, width: CGFloat, maximumLines: Int?, displayScale: CGFloat) -> CGFloat {
        guard !text.isEmpty, width > 0 else { return 0 }
        let coreTextFont = font as CTFont
        let attributedText = NSAttributedString(string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: coreTextFont])
        let typesetter = CTTypesetterCreateWithAttributedString(attributedText)
        let length = attributedText.length
        var index = 0
        var lineCount = 0
        while index < length, maximumLines.map({ lineCount < $0 }) ?? true {
            var lineLength = CTTypesetterSuggestLineBreak(typesetter, index, Double(width))
            if lineLength == 0 {
                lineLength = CTTypesetterSuggestClusterBreak(typesetter, index, Double(width))
            }
            guard lineLength > 0 else { break }
            index += lineLength
            lineCount += 1
        }
        // UILabel uses its font line height plus inter-line font leading, then
        // resolves the final label extent on the display-pixel grid.
        let height = CGFloat(lineCount) * font.lineHeight + CGFloat(max(0, lineCount - 1)) * font.leading
        return ceil(height * displayScale) / displayScale
    }
}

/// Exact row heights for every loaded article.
///
/// A table with estimation disabled asks for the height of *every* row before it
/// can lay out, so a bounded cache is not sufficient: a miss would run Core Text
/// synchronously on the main actor. This store keeps one height per loaded
/// article and, while a new geometry generation is being measured, keeps serving
/// the superseded heights. A rotation or Dynamic Type change therefore never
/// blocks a frame waiting for a full re-measurement.
@MainActor
final class IOSUIKitArticleRowHeightStore {
    private(set) var identity: IOSUIKitTimelineGeometryIdentity?
    private var current: [Int64: CGFloat] = [:]
    private var superseded: [Int64: CGFloat] = [:]

    var preparedCount: Int { current.count }
    var isServingSupersededHeights: Bool { !superseded.isEmpty }

    /// An exact height for the active identity, or the superseded one while a
    /// replacement generation is still being measured.
    func height(for id: Int64) -> CGFloat? {
        current[id] ?? superseded[id]
    }

    func hasExactHeight(for id: Int64) -> Bool { current[id] != nil }

    /// Starts a new generation. Existing heights keep serving until `store`
    /// replaces them, so the caller can measure without blocking.
    func beginGeneration(_ newIdentity: IOSUIKitTimelineGeometryIdentity) {
        guard identity != newIdentity else { return }
        if !current.isEmpty { superseded = current }
        current = [:]
        identity = newIdentity
    }

    /// Results measured for a stale identity are dropped rather than mixed in.
    func store(_ measured: [Int64: CGFloat], for measuredIdentity: IOSUIKitTimelineGeometryIdentity) {
        guard measuredIdentity == identity else { return }
        current.merge(measured) { _, new in new }
    }

    /// Superseded heights are only safe to drop once every loaded row has an
    /// exact height for the active identity.
    func retireSupersededHeights(ifComplete ids: [Int64]) -> Bool {
        guard !superseded.isEmpty else { return false }
        guard ids.allSatisfy({ current[$0] != nil }) else { return false }
        superseded.removeAll()
        return true
    }

    func missingIDs(in ids: [Int64]) -> [Int64] {
        ids.filter { current[$0] == nil }
    }

    func remove(_ ids: some Sequence<Int64>) {
        for id in ids {
            current[id] = nil
            superseded[id] = nil
        }
    }

    func removeAll() {
        current.removeAll()
        superseded.removeAll()
        identity = nil
    }
}

/// Measures whole pages of rows off the main actor.
///
/// Heights are the only value needed to lay the table out; the full per-subview
/// metrics stay with the existing preparation coordinator, which the cell uses
/// when it is actually configured.
enum IOSUIKitArticleRowHeightMeasurement {
    static func heights(for inputs: [(id: Int64, input: IOSUIKitArticleLayoutInput)]) async -> [Int64: CGFloat] {
        guard !inputs.isEmpty else { return [:] }
        let payload = inputs.map { ($0.id, $0.input) }
        return await Task.detached(priority: .userInitiated) {
            var result = [Int64: CGFloat](minimumCapacity: payload.count)
            for (id, input) in payload {
                result[id] = IOSUIKitArticleLayoutEngine.metrics(for: input).cellSize.height
            }
            return result
        }.value
    }
}
