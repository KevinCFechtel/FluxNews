import SwiftUI
import UIKit

enum IOSArticleListActionPlacement: Equatable {
    case bottomBar
    case topBarTrailing
    case floatingTopTrailing
}

enum IOSArticleListChromeMode: Equatable {
    case compactPortrait
    case compactLandscape
    case persistentSplit
    case persistentSplitCollapsed
}

enum IOSArticleListTitleCapsulePlacement: Equatable {
    case floatingTopCenter
    case navigationTopLeading
    case floatingTopLeading
    case hidden
}

enum IOSArticleListChromePresentation {
    static func mode(
        for presentation: AdaptivePresentation,
        verticalSizeClass: UserInterfaceSizeClass?,
        splitColumnVisibility: NavigationSplitViewVisibility
    ) -> IOSArticleListChromeMode {
        // Size-class adaptation wins when the app has become compact. During a
        // Duo/fold or rotation transition SwiftUI can publish the new size
        // classes one render pass before NavigationSplitView writes its updated
        // column visibility. Treating that stale .all value as a visible sidebar
        // briefly selects persistent-split chrome on a compact phone canvas.
        guard presentation.usesPersistentSplitNavigation else {
            return verticalSizeClass == .compact ? .compactLandscape : .compactPortrait
        }

        // In a genuinely regular presentation the split visibility is the
        // authoritative user/system state: a visible sidebar suppresses duplicate
        // scope chrome, while detailOnly restores the collapsed-split controls.
        return splitColumnVisibility == .detailOnly
            ? .persistentSplitCollapsed
            : .persistentSplit
    }

    static func actionPlacement(
        for mode: IOSArticleListChromeMode,
        systemPrefersVerticalToolbar: Bool = false,
        systemUsesAdaptiveToolbar: Bool = false
    ) -> IOSArticleListActionPlacement {
        switch mode {
        case .compactPortrait:
            systemPrefersVerticalToolbar ? .topBarTrailing : .bottomBar
        case .compactLandscape:
            .topBarTrailing
        case .persistentSplit, .persistentSplitCollapsed:
            systemUsesAdaptiveToolbar || systemPrefersVerticalToolbar
                ? .topBarTrailing
                : .floatingTopTrailing
        }
    }

    static func configurableDirectActionCapacity(
        for mode: IOSArticleListChromeMode,
        systemPrefersVerticalToolbar: Bool = false
    ) -> Int {
        switch mode {
        case .compactPortrait:
            3
        case .compactLandscape:
            2
        case .persistentSplit:
            systemPrefersVerticalToolbar ? 3 : 5
        case .persistentSplitCollapsed:
            3
        }
    }

    static func titleCapsulePlacement(
        for mode: IOSArticleListChromeMode,
        systemPrefersVerticalToolbar: Bool = false,
        systemUsesAdaptiveToolbar: Bool = false
    ) -> IOSArticleListTitleCapsulePlacement {
        switch mode {
        case .compactPortrait:
            .floatingTopCenter
        case .compactLandscape:
            .navigationTopLeading
        case .persistentSplitCollapsed:
            // Collapsed regular layouts keep the passive scope capsule in the
            // native top bar beside the system sidebar toggle. This applies to
            // iPad and both Duo inner-display orientations; the system may move
            // trailing actions to a vertical edge independently.
            .navigationTopLeading
        case .persistentSplit:
            .hidden
        }
    }

    static func navigationBarVisibility(
        for mode: IOSArticleListChromeMode,
        systemPrefersVerticalToolbar: Bool = false,
        systemUsesAdaptiveToolbar: Bool = false
    ) -> Visibility {
        switch mode {
        case .compactPortrait:
            // On iOS 27.1+ a non-nil toolbarVerticalEdge reports the system's
            // preferred vertical-bar edge even when that bar is currently hidden.
            // Compact portrait actions move to .topBarTrailing in that context,
            // and on iOS the top bar is the navigation bar. Keep that host visible
            // so the system can actually render the actions on the vertical edge.
            return systemPrefersVerticalToolbar ? .visible : .hidden
        case .compactLandscape:
            return .visible
        case .persistentSplit, .persistentSplitCollapsed:
            // On iOS 27.1+ keep horizontal regular layouts fully system-adaptive
            // (important for Duo portrait startup), but pin the navigation bar
            // when the system moves toolbar controls to a vertical edge. In that
            // landscape presentation the native sidebar toggle and passive title
            // capsule are essential navigation/context and must not scroll away.
            if systemUsesAdaptiveToolbar {
                return systemPrefersVerticalToolbar ? .visible : .automatic
            }
            return systemPrefersVerticalToolbar ? .visible : .hidden
        }
    }

    static func usesNativeTopEdgeEffect(
        for mode: IOSArticleListChromeMode,
        systemPrefersVerticalToolbar: Bool = false
    ) -> Bool {
        // Vertical-bar preference changes where actions live, not the Timeline's
        // established top-edge policy. Only compact iPhone landscape disables it.
        _ = systemPrefersVerticalToolbar
        return mode != .compactLandscape
    }
}

enum IOSArticleListActionChromeMetrics {
    static let floatingHorizontalPadding: CGFloat = 8
    static let floatingVerticalPadding: CGFloat = 5
    static let floatingSpacing: CGFloat = 6
}

enum IOSArticleListTitleCapsuleMetrics {
    /// The title capsule is deliberately outside UINavigationBar chrome. These
    /// insets create a small transparent floating row without registering the
    /// capsule as a scroll-edge element.
    static let floatingHorizontalInset: CGFloat = 12
    static let floatingVerticalInset: CGFloat = 4
    static let floatingRowSpacing: CGFloat = 10
    static let stackedVerticalPadding: CGFloat = 7

    static func portraitNaturalTopContentInset(showSubtitle: Bool) -> CGFloat {
        let titleHeight = UIFont.preferredFont(forTextStyle: .headline).lineHeight
        let contentHeight = showSubtitle
            ? titleHeight + 1 + UIFont.preferredFont(forTextStyle: .caption1).lineHeight
            : titleHeight
        return contentHeight
            + (stackedVerticalPadding * 2)
            + (floatingVerticalInset * 2)
    }

    /// The iPad collapsed-split inline capsule still needs a useful minimum title
    /// width beside the trailing toolbar actions.
    static let inlineMinimumContentWidth: CGFloat = 280
    /// Count semantics are more important than preserving every character of a
    /// long scope/feed title in the remaining inline iPad presentation.
    static let inlineTitlePriority: Double = 1
    static let inlineCountPriority: Double = 2
    /// Keep enough room for a meaningful regular-toolbar title. The count is
    /// optional under pressure; the scope title is not.
    static let regularToolbarTitleMinimumWidth: CGFloat = 96

    /// Compact-height iPhone landscape uses the same two-line information
    /// hierarchy as portrait, but trims the capsule itself so the separate
    /// floating row does not consume unnecessary landscape height.
    static let compactStackedVerticalPadding: CGFloat = 0
    static let compactStackedHorizontalPadding: CGFloat = 8
    static let compactStackedSpacing: CGFloat = 6
    /// Give ordinary feed/category titles enough room in the independent floating
    /// row. Very long titles may still truncate rather than claiming the full
    /// detail width.
    static let compactStackedMinimumContentWidth: CGFloat = 190
    static let compactStackedTitlePriority: Double = 3
}

enum IOSScopeNavigation {
    static func nextScope(
        after scope: BrowserScope,
        catalog: NavigationCatalog,
        hidingEmpty: Bool,
        counts: [Int64: UInt64]
    ) -> BrowserScope? {
        let groups = NavigationVisibility.groups(
            categories: catalog.categories.map { .init(id: $0.id, title: $0.title) },
            feeds: catalog.feeds.map { .init(id: $0.id, categoryID: $0.categoryId) },
            hidingEmpty: hidingEmpty,
            counts: counts
        )
        switch scope {
        case let .feed(feedID):
            let feeds = groups.flatMap(\.feeds)
            guard let index = feeds.firstIndex(where: { $0.id == feedID }), feeds.indices.contains(feeds.index(after: index)) else { return nil }
            return .feed(feeds[feeds.index(after: index)].id)
        case let .category(categoryID):
            let categories = groups.compactMap(\.categoryID)
            guard let index = categories.firstIndex(of: categoryID), categories.indices.contains(categories.index(after: index)) else { return nil }
            return .category(categories[categories.index(after: index)])
        case .all, .starred, .search, .listeningList:
            return nil
        }
    }
}

enum IOSNavigationButtonPresentation {
    static let imageName = "FluxNewsTemplate"
    static let accessibilityLabel = String(localized: "Choose news scope")
    static let glyphSize: CGFloat = 22
}

enum IOSReaderDismissalPresentation {
    static let title = String(localized: "Done")
}

enum IOSArticleNavigationPresentation {
    // Keep the outer navigation container on the native large-title-compatible
    // path so semantic resets preserve the expected navigation-controller
    // geometry. The accepted visible article-list title remains the explicit
    // scope capsule, whose inner chrome overrides the visible display mode.
    static let titleDisplayMode: NavigationBarItem.TitleDisplayMode = .large
}

#if FLUX_HAS_VERTICAL_TOOLBAR_API
@available(iOS 27.1, *)
struct IOSArticleListVerticalToolbarCapabilityEnvironment<Content: View>: View {
    @Environment(\.toolbarVerticalEdge) private var toolbarVerticalEdge
    private let content: (_ systemUsesAdaptiveToolbar: Bool, _ systemPrefersVerticalToolbar: Bool) -> Content

    init(
        @ViewBuilder content: @escaping (
            _ systemUsesAdaptiveToolbar: Bool,
            _ systemPrefersVerticalToolbar: Bool
        ) -> Content
    ) {
        self.content = content
    }

    var body: some View {
        content(true, toolbarVerticalEdge != nil)
    }
}
#endif

private enum ArticleListTitleCapsuleLayout: Equatable {
    case stacked
    case compactStacked
    case regularToolbar
    case inline
}

private struct ArticleListTitleCapsule: View {
    let title: String
    let subtitle: String?
    let widthReservationSubtitle: String?
    let layout: ArticleListTitleCapsuleLayout
    var action: (() -> Void)?
    var showsBrandMark = false
    var reservesInlineMinimumWidth = true
    var usesSystemToolbarGlass = false
    // Read so the derived glyph height is recomputed when the text size changes.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The combined height of the two lines, from the same font metrics that lay
    /// them out. A fixed point size would drift apart from them under Dynamic
    /// Type, and a flexible frame would let the glyph drive the capsule's height.
    private var glyphHeight: CGFloat {
        switch layout {
        case .stacked:
            let titleHeight = UIFont.preferredFont(forTextStyle: .headline).lineHeight
            guard subtitle != nil else { return titleHeight }
            return titleHeight + 1 + UIFont.preferredFont(forTextStyle: .caption1).lineHeight
        case .compactStacked, .regularToolbar:
            return UIFont.preferredFont(forTextStyle: .subheadline).lineHeight
        case .inline:
            return UIFont.preferredFont(forTextStyle: .headline).lineHeight
        }
    }

    private var horizontalSpacing: CGFloat {
        layout == .compactStacked ? IOSArticleListTitleCapsuleMetrics.compactStackedSpacing : 8
    }

    private var horizontalPadding: CGFloat {
        if layout == .compactStacked {
            return IOSArticleListTitleCapsuleMetrics.compactStackedHorizontalPadding
        }
        return action == nil ? 16 : 12
    }

    var body: some View {
        // This capsule replaced the navigation title, so it has to carry that
        // role too: the label is what the screen *is* (the scope), the value is
        // its state, and the hint is what tapping does. Announcing the action as
        // the label would put the least useful part first.
        //
        // `.isHeader` restores what `.navigationTitle("")` gave up — without it
        // VoiceOver's heading rotor finds nothing on this screen.
        if let action {
            Button(action: action) { capsule }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(subtitle ?? "")
                .accessibilityHint(IOSNavigationButtonPresentation.accessibilityLabel)
                .accessibilityAddTraits(.isHeader)
        } else {
            // No action on a persistent sidebar, but the two lines would still be
            // read as separate, role-less elements without this.
            capsule
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(subtitle ?? "")
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var capsule: some View {
        HStack(spacing: horizontalSpacing) {
            if action != nil || showsBrandMark {
                Image(IOSNavigationButtonPresentation.imageName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: layout == .compactStacked ? max(glyphHeight, 34) : glyphHeight,
                        height: layout == .compactStacked ? max(glyphHeight, 34) : glyphHeight
                    )
                    // `.plain` hands its content the label colour. The brand mark
                    // keeps the accent it had as a standalone button.
                    .foregroundStyle(Color.accentColor)
            }
            titleAndSubtitle
            if action != nil {
                // Glass says "interactive", the chevron says what kind. No
                // explicit colour: an inherited one still flips with the glass
                // over dark content, a semantic one would not.
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .opacity(0.55)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background {
            ArticleListChromeCapsuleBackground(
                usesSystemToolbarGlass: usesSystemToolbarGlass,
                isInteractive: action != nil
            )
        }
        .contentShape(Capsule())
        .accessibilityElement(children: .combine)
    }

    private var verticalPadding: CGFloat {
        switch layout {
        case .stacked: IOSArticleListTitleCapsuleMetrics.stackedVerticalPadding
        case .compactStacked, .regularToolbar: IOSArticleListTitleCapsuleMetrics.compactStackedVerticalPadding
        case .inline: 5
        }
    }

    @ViewBuilder
    private var titleAndSubtitle: some View {
        switch layout {
        case .stacked:
            VStack(spacing: 1) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }
            }
        case .compactStacked:
            VStack(alignment: .leading, spacing: 0) {
                // Prefer the full one-line scope title when the landscape toolbar
                // can accommodate it. Only fall back to truncation when the
                // trailing action group actually needs that space.
                ViewThatFits(in: .horizontal) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(.primary)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.primary)
                }
                .layoutPriority(IOSArticleListTitleCapsuleMetrics.compactStackedTitlePriority)
                if let subtitle {
                    ZStack(alignment: .leading) {
                        Text(subtitle)
                            .foregroundStyle(.primary)
                        if let widthReservationSubtitle {
                            Text(widthReservationSubtitle)
                                .hidden()
                        }
                    }
                    .font(.caption2)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: true)
                }
            }
            .frame(
                minWidth: IOSArticleListTitleCapsuleMetrics.compactStackedMinimumContentWidth,
                alignment: .leading
            )
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(IOSArticleListTitleCapsuleMetrics.compactStackedTitlePriority)
        case .regularToolbar:
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                    .layoutPriority(2)
                if let subtitle {
                    HStack(spacing: 4) {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(subtitle)
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(.secondary)
                    }
                    .layoutPriority(1)
                }
            }
            // Report the content's true intrinsic width to the native toolbar.
            // Toolbar visibility priority, rather than a synthetic frame width,
            // decides what yields when the bar becomes constrained.
            .fixedSize(horizontal: true, vertical: false)
        case .inline:
            HStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(IOSArticleListTitleCapsuleMetrics.inlineTitlePriority)
                if let subtitle {
                    HStack(spacing: 4) {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(subtitle)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    // Keep the semantic count intact. On a constrained toolbar
                    // the scope/feed title truncates before the count does.
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(IOSArticleListTitleCapsuleMetrics.inlineCountPriority)
                }
            }
            // Let the title use its natural width. The navigation bar already
            // knows how much room the trailing Sync/Filter/More group needs, so
            // an app-level maximum would only cause premature truncation on wide
            // landscape phones.
            .frame(
                minWidth: reservesInlineMinimumWidth
                    ? IOSArticleListTitleCapsuleMetrics.inlineMinimumContentWidth
                    : 0,
                alignment: .leading
            )
        }
    }
}

struct ArticleListChromeCapsuleBackground: View {
    var usesSystemToolbarGlass = false
    var isInteractive = false

    /// Whether the system is asked to avoid see-through backgrounds. Glass is
    /// exactly that, and the title has to stay legible over scrolling articles,
    /// so this substitutes an opaque fill rather than trusting the effect to
    /// adapt on its own.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *), usesSystemToolbarGlass {
            Color.clear
        } else if reduceTransparency {
            Capsule().fill(Color(uiColor: .secondarySystemBackground))
        } else if #available(iOS 26.0, *) {
            ArticleListGlassCapsule(isInteractive: isInteractive)
        } else {
            Capsule().fill(.regularMaterial)
        }
    }
}

@available(iOS 26.0, *)
private struct ArticleListGlassCapsule: UIViewRepresentable {
    let isInteractive: Bool

    func makeUIView(context: Context) -> UIVisualEffectView {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = isInteractive
        let view = UIVisualEffectView(effect: effect)
        // Resolves the capsule shape without a mask layer.
        view.cornerConfiguration = .capsule()
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = isInteractive
        uiView.effect = effect
    }

    /// A `UIVisualEffectView` has no useful intrinsic size, so the representable
    /// has to answer for it. Returning the proposal unchanged also returns
    /// `.infinity` when the container offers unbounded space, and the effect then
    /// claims everything it is given — which is how a capsule background can end
    /// up as a full-height panel. Unbounded proposals collapse to zero instead;
    /// as a background it is always handed the concrete foreground size.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIVisualEffectView, context: Context) -> CGSize? {
        let size = proposal.replacingUnspecifiedDimensions(by: .zero)
        return CGSize(
            width: size.width.isFinite ? size.width : 0,
            height: size.height.isFinite ? size.height : 0
        )
    }
}

enum ArticleListTitlePresentation {
    static func title(scope: BrowserScope, catalog: NavigationCatalog) -> String {
        scopeTitle(scope: scope, catalog: catalog)
    }

    private static func scopeTitle(scope: BrowserScope, catalog: NavigationCatalog) -> String {
        switch scope {
        case .all: String(localized: "All News")
        case .starred: String(localized: "Starred")
        case .category(let id): catalog.categories.first { $0.id == id }?.title ?? String(localized: "Category")
        case .feed(let id): catalog.feeds.first { $0.id == id }?.title ?? String(localized: "Feed")
        case .search: String(localized: "Search")
        case .listeningList: String(localized: "Listening List")
        }
    }
}

enum ArticleListCounterPresentation {
    static func inlineLandscapeLabel(
        scope: BrowserScope,
        unreadOnly: Bool,
        count: UInt64,
        locale: Locale = .current
    ) -> String {
        if unreadOnly && scope != .starred {
            return String(localized: "\(Int(count)) unread", locale: locale)
        }
        return String(localized: "\(Int(count)) article", locale: locale)
    }

    static func isVisible(showArticleCount: Bool) -> Bool { showArticleCount }
    static func usesNativeSubtitle(showArticleCount: Bool, supportsNativeSubtitle: Bool) -> Bool {
        showArticleCount && supportsNativeSubtitle
    }
    static func usesToolbarFallback(showArticleCount: Bool, supportsNativeSubtitle: Bool) -> Bool {
        showArticleCount && !supportsNativeSubtitle
    }

    static func expandedLabel(scope: BrowserScope, unreadOnly: Bool, count: UInt64, locale: Locale = .current) -> String {
        if unreadOnly && scope != .starred {
            return String(localized: "\(Int(count)) unread article", locale: locale)
        }
        return String(localized: "\(Int(count)) article", locale: locale)
    }
}

enum IOSSyncButtonPresentation {
    enum State: Equatable {
        case idle
        case syncing
        case cancelling
        case success
    }

    static func resolve(
        manualSyncState: IOSManualSyncState,
        transientState: State
    ) -> State {
        switch manualSyncState {
        case .idle: transientState
        case .running: .syncing
        case .cancelling: .cancelling
        }
    }

    static func symbolName(for state: State) -> String {
        switch state {
        case .syncing: "xmark"
        case .success: "checkmark"
        case .idle, .cancelling: "arrow.clockwise"
        }
    }

    static func accessibilityLabel(for state: State) -> String {
        state == .syncing
            ? String(localized: "Cancel sync")
            : String(localized: "Sync news")
    }

    static func accessibilityValue(for state: State) -> String {
        switch state {
        case .idle: String(localized: "Ready")
        case .syncing: String(localized: "Syncing")
        case .cancelling: String(localized: "Cancelling")
        case .success: String(localized: "Sync complete")
        }
    }

    static func canEndSuccess(generation: UInt64, currentGeneration: UInt64, isSyncing: Bool) -> Bool {
        generation == currentGeneration && !isSyncing
    }
}

private struct ArticleListFloatingActionGroup<Actions: View>: View {
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: IOSArticleListActionChromeMetrics.floatingSpacing) {
            actions()
                .labelStyle(.iconOnly)
        }
        .padding(.horizontal, IOSArticleListActionChromeMetrics.floatingHorizontalPadding)
        .padding(.vertical, IOSArticleListActionChromeMetrics.floatingVerticalPadding)
        .background { ArticleListChromeCapsuleBackground() }
        .fixedSize()
    }
}

private struct ArticleListDetachedTopChromeHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ArticleListNavigationChrome<Content: View, TopActions: View, TopAccessory: View>: View {
    var store: NewsreaderStore
    /// Absent when a persistent sidebar already offers scope selection.
    var onSelectScope: (() -> Void)?
    var chromeMode: IOSArticleListChromeMode
    var actionPlacement: IOSArticleListActionPlacement
    var systemUsesAdaptiveToolbar = false
    var systemPrefersVerticalToolbar = false
    @ViewBuilder let topActions: () -> TopActions
    @ViewBuilder let topAccessory: () -> TopAccessory
    @ViewBuilder let content: (CGFloat) -> Content
    @State private var detachedTopChromeHeight: CGFloat = 0

    private func capsuleSubtitle(_ subtitle: String) -> String? {
        ArticleListCounterPresentation.usesNativeSubtitle(showArticleCount: store.showArticleCount, supportsNativeSubtitle: true) ? subtitle : nil
    }

    var body: some View {
        let title = ArticleListTitlePresentation.title(scope: store.scope, catalog: store.catalog)
        let countLabel = ArticleListCounterPresentation.expandedLabel(
            scope: store.scope,
            unreadOnly: store.unreadOnly,
            count: store.selectionTotal
        )
        let portraitSubtitle = store.isSyncing ? String(localized: "Syncing…") : countLabel
        let landscapeCountLabel = ArticleListCounterPresentation.inlineLandscapeLabel(
            scope: store.scope,
            unreadOnly: store.unreadOnly,
            count: store.selectionTotal
        )
        let syncingLabel = String(localized: "Syncing…")
        let landscapeSubtitle = store.isSyncing ? syncingLabel : landscapeCountLabel
        // Reserve the alternate second-line state so Count -> Syncing -> Count
        // does not make the compact landscape capsule breathe horizontally.
        let landscapeWidthReservationSubtitle = store.isSyncing ? landscapeCountLabel : syncingLabel

        let capsulePlacement = IOSArticleListChromePresentation.titleCapsulePlacement(
            for: chromeMode,
            systemPrefersVerticalToolbar: systemPrefersVerticalToolbar,
            systemUsesAdaptiveToolbar: systemUsesAdaptiveToolbar
        )
        let naturalTopContentInset: CGFloat = if chromeMode == .compactPortrait {
            detachedTopChromeHeight > 0
                ? detachedTopChromeHeight
                : IOSArticleListTitleCapsuleMetrics.portraitNaturalTopContentInset(
                    showSubtitle: store.showArticleCount
                )
        } else {
            0
        }

        // Keep the Timeline itself outside the chrome-mode switch. Compact
        // portrait and persistent split modes retain detached safe-area chrome;
        // compact iPhone landscape deliberately returns to UINavigationBar.
        content(naturalTopContentInset)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) {
                switch (capsulePlacement, actionPlacement, chromeMode) {
                case (.floatingTopCenter, .bottomBar, .compactPortrait),
                     (.floatingTopCenter, .topBarTrailing, .compactPortrait):
                    ArticleListTitleCapsule(
                        title: title,
                        subtitle: capsuleSubtitle(portraitSubtitle),
                        widthReservationSubtitle: nil,
                        layout: .stacked,
                        action: onSelectScope
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, IOSArticleListTitleCapsuleMetrics.floatingHorizontalInset)
                    .padding(.vertical, IOSArticleListTitleCapsuleMetrics.floatingVerticalInset)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ArticleListDetachedTopChromeHeightPreferenceKey.self,
                                value: proxy.size.height
                            )
                        }
                    }
                case (.hidden, .floatingTopTrailing, .persistentSplit):
                    HStack {
                        Spacer(minLength: 0)
                        ArticleListFloatingActionGroup(actions: topActions)
                    }
                    .padding(.horizontal, IOSArticleListTitleCapsuleMetrics.floatingHorizontalInset)
                    .padding(.vertical, IOSArticleListTitleCapsuleMetrics.floatingVerticalInset)
                case (.floatingTopLeading, .floatingTopTrailing, .persistentSplitCollapsed):
                    HStack(spacing: IOSArticleListTitleCapsuleMetrics.floatingRowSpacing) {
                        ArticleListTitleCapsule(
                            title: title,
                            subtitle: capsuleSubtitle(landscapeSubtitle),
                            widthReservationSubtitle: nil,
                            layout: .inline,
                            action: nil,
                            showsBrandMark: true
                        )
                        Spacer(minLength: IOSArticleListTitleCapsuleMetrics.floatingRowSpacing)
                        topAccessory()
                        Spacer(minLength: IOSArticleListTitleCapsuleMetrics.floatingRowSpacing)
                        ArticleListFloatingActionGroup(actions: topActions)
                    }
                    .padding(.horizontal, IOSArticleListTitleCapsuleMetrics.floatingHorizontalInset)
                    .padding(.vertical, IOSArticleListTitleCapsuleMetrics.floatingVerticalInset)
                case (.floatingTopLeading, .topBarTrailing, .persistentSplitCollapsed):
                    VStack(spacing: IOSArticleListTitleCapsuleMetrics.floatingRowSpacing) {
                        ArticleListTitleCapsule(
                            title: title,
                            subtitle: capsuleSubtitle(landscapeSubtitle),
                            widthReservationSubtitle: nil,
                            layout: .inline,
                            action: nil,
                            showsBrandMark: true
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if systemPrefersVerticalToolbar {
                            HStack {
                                topAccessory()
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, IOSArticleListTitleCapsuleMetrics.floatingHorizontalInset)
                    .padding(.vertical, IOSArticleListTitleCapsuleMetrics.floatingVerticalInset)
                default:
                    EmptyView()
                }
            }
            .onPreferenceChange(ArticleListDetachedTopChromeHeightPreferenceKey.self) { height in
                guard abs(detachedTopChromeHeight - height) > 0.5 else { return }
                detachedTopChromeHeight = height
            }
            .toolbar {
                if capsulePlacement == .navigationTopLeading {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: IOSArticleListTitleCapsuleMetrics.floatingRowSpacing) {
                            ArticleListTitleCapsule(
                                title: title,
                                subtitle: capsuleSubtitle(landscapeSubtitle),
                                widthReservationSubtitle: capsuleSubtitle(landscapeWidthReservationSubtitle),
                                layout: chromeMode == .persistentSplitCollapsed ? .regularToolbar : .compactStacked,
                                action: chromeMode == .persistentSplitCollapsed ? nil : onSelectScope,
                                showsBrandMark: chromeMode == .persistentSplitCollapsed,
                                reservesInlineMinimumWidth: chromeMode != .persistentSplitCollapsed,
                                // Native leading toolbar items receive Liquid Glass.
                                usesSystemToolbarGlass: true
                            )
                            if chromeMode == .compactLandscape
                                || (UIDevice.current.userInterfaceIdiom == .pad
                                    && chromeMode == .persistentSplitCollapsed
                                    && actionPlacement == .topBarTrailing) {
                                // Keep the compact player beside the scope capsule in
                                // the native leading toolbar allocation on Duo and iPad.
                                // A separate .principal item can introduce full-width
                                // navigation-bar chrome on iPad.
                                topAccessory()
                            }
                        }
                    }
                }

                if chromeMode == .persistentSplitCollapsed,
                   actionPlacement == .topBarTrailing,
                   systemPrefersVerticalToolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        topAccessory()
                    }
                }

                if chromeMode == .persistentSplitCollapsed,
                   actionPlacement == .topBarTrailing,
                   !systemPrefersVerticalToolbar,
                   UIDevice.current.userInterfaceIdiom != .pad {
                    ToolbarItem(placement: .principal) {
                        topAccessory()
                    }
                }
            }
    }
}
