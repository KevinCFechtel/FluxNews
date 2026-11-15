import SwiftUI

enum NewsNavigationPresentation: Equatable { case sidebar, sheet }

enum NewsNavigationSelection {
    static func isSelected(_ rowScope: BrowserScope, activeScope: BrowserScope) -> Bool { rowScope == activeScope }

    enum CategoryPresentation: Equatable {
        case unselected
        case directlySelected
        case containsSelectedFeed
    }

    static func categoryPresentation(categoryID: Int64, activeScope: BrowserScope, catalog: NavigationCatalog) -> CategoryPresentation {
        if activeScope == .category(categoryID) { return .directlySelected }
        guard case let .feed(feedID) = activeScope,
              catalog.feeds.first(where: { $0.id == feedID })?.categoryId == categoryID
        else { return .unselected }
        return .containsSelectedFeed
    }
}

enum IOSNavigationBranding {
    static let assetName = "FluxNewsTemplate"
    static let accessibilityLabel = String(localized: "FluxNews")
    static let iconUsesSolidAccentColor = true
}

struct NewsNavigationExpansionState: Equatable {
    private(set) var expandedCategoryIDs = Set<Int64>()

    mutating func ensureSelectedFeedIsExpanded(scope: BrowserScope, catalog: NavigationCatalog) {
        guard case let .feed(feedID) = scope,
              let categoryID = catalog.feeds.first(where: { $0.id == feedID })?.categoryId
        else { return }
        expandedCategoryIDs.insert(categoryID)
    }

    mutating func setExpanded(_ expanded: Bool, categoryID: Int64) {
        if expanded { expandedCategoryIDs.insert(categoryID) }
        else { expandedCategoryIDs.remove(categoryID) }
    }

    func isExpanded(_ categoryID: Int64) -> Bool { expandedCategoryIDs.contains(categoryID) }
}

struct NewsNavigationView: View {
    @Environment(\.colorScheme) private var colorScheme
    var store: NewsreaderStore
    @Binding var sheetPresented: Bool
    let presentation: NewsNavigationPresentation
    let onListeningList: () -> Void
    let onSearch: () -> Void
    @State private var addDestination: IOSNavigationAddDestination?
    @State private var feedSettingsTarget: IOSFeedSettingsTarget?
    @State private var expansionState = NewsNavigationExpansionState()

    init(
        store: NewsreaderStore,
        sheetPresented: Binding<Bool>,
        presentation: NewsNavigationPresentation,
        onListeningList: @escaping () -> Void = {},
        onSearch: @escaping () -> Void = {}
    ) {
        self.store = store
        self._sheetPresented = sheetPresented
        self.presentation = presentation
        self.onListeningList = onListeningList
        self.onSearch = onSearch
    }

    var body: some View {
        Group {
            if presentation == .sidebar { listContent.listStyle(.sidebar) }
            else { listContent.listStyle(.insetGrouped) }
        }
        .toolbar { addToolbar }
        .sheet(item: $addDestination) { destination in NavigationStack { addView(destination) } }
        .sheet(item: $feedSettingsTarget) { target in NavigationStack { IOSFeedSettingsView(store: store, target: target) } }
        .onAppear(perform: ensureSelectedFeedIsExpanded)
        .onChange(of: store.scope) { _, _ in ensureSelectedFeedIsExpanded() }
    }

    private var listContent: some View {
        List(selection: selection) {
            brandingHeader
            Section("News") {
                scopeRow("All News", systemImage: "newspaper", scope: .all, count: store.unreadTotal)
                scopeRow("Starred", systemImage: "star", scope: .starred, count: store.starredTotal)
                listeningListRow
                searchRow
            }
            Section("Feeds") {
                ForEach(groups) { group in
                    if let categoryID = group.categoryID {
                        categoryNavigationRow(
                            categoryID: categoryID,
                            title: group.title,
                            count: store.categoryCounts[categoryID] ?? 0
                        )
                        .tag(BrowserScope.category(categoryID))

                        if expansionState.isExpanded(categoryID) {
                            ForEach(group.feeds, id: \.id) { feed in
                                feedRow(feedTitle(feed.id), feedID: feed.id, count: store.feedCounts[feed.id] ?? 0)
                                    .padding(.leading, 22)
                            }
                        }
                    } else {
                        ForEach(group.feeds, id: \.id) { feed in
                            feedRow(feedTitle(feed.id), feedID: feed.id, count: store.feedCounts[feed.id] ?? 0)
                        }
                    }
                }
            }
        }
    }

    private var brandingHeader: some View {
        HStack(spacing: 9) {
            Image(IOSNavigationBranding.assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .foregroundStyle(Color.accentColor)
            Text(IOSNavigationBranding.accessibilityLabel)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(IOSNavigationBranding.accessibilityLabel)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var selection: Binding<BrowserScope?> {
        Binding(get: { store.scope }, set: { if let value = $0 { store.select(value); sheetPresented = false } })
    }

    private var groups: [NavigationPresentationGroup] {
        NavigationVisibility.groups(categories: store.catalog.categories.map { .init(id: $0.id, title: $0.title) }, feeds: store.catalog.feeds.map { .init(id: $0.id, categoryID: $0.categoryId) }, hidingEmpty: store.hideEmptyNavigationEntries, counts: store.feedCounts)
    }

    private func feedTitle(_ feedID: Int64) -> String { store.catalog.feeds.first { $0.id == feedID }?.title ?? String(localized: "Feed") }
    private var listeningListRow: some View {
        Button(action: requestListeningList) {
            Label {
                Text("Listening List")
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "headphones")
                    .foregroundStyle(.tint)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("navigation.listeningList")
    }

    private var searchRow: some View {
        Button(action: requestSearch) {
            Label {
                Text("Search")
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tint)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("navigation.search")
    }

    private func requestListeningList() {
        // Like Search, the host owns presentation sequencing so the transient
        // navigation sheet can fully dismiss before the Listening List appears.
        onListeningList()
    }

    private func requestSearch() {
        // The host sequences this: it owns the sheet and therefore its dismissal
        // callback, which fires reliably — unlike this view's `onDisappear`,
        // which runs while the sheet is being torn down.
        onSearch()
    }

    private func scopeRow(_ title: LocalizedStringKey, systemImage: String, scope: BrowserScope, count: UInt64) -> some View {
        Label { localizedLabelTitle(title, count: count) } icon: { Image(systemName: systemImage) }
            .tag(scope)
        .accessibilityValue(count == 0 ? String(localized: "No unread articles") : String(localized: "\(count) unread article"))
    }

    private func localizedLabelTitle(_ title: LocalizedStringKey, count: UInt64) -> some View {
        HStack {
            Text(title)
            Spacer()
            if count > 0 {
                Text(count > 999 ? "999+" : "\(count)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }

    private func categoryNavigationRow(categoryID: Int64, title: String, count: UInt64) -> some View {
        let categoryPresentation = NewsNavigationSelection.categoryPresentation(
            categoryID: categoryID,
            activeScope: store.scope,
            catalog: store.catalog
        )
        let expanded = expansionState.isExpanded(categoryID)

        return HStack(spacing: 6) {
            Button {
                expansionState.setExpanded(!expanded, categoryID: categoryID)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 16, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(expanded ? String(localized: "Collapse category") : String(localized: "Expand category"))
            .accessibilityValue(title)

            Label { labelTitle(title, count: count) } icon: {
                Image(systemName: categoryPresentation == .containsSelectedFeed ? "folder.fill" : "folder")
            }
            .fontWeight(categoryPresentation == .containsSelectedFeed ? .medium : .regular)
        }
    }

    private func feedRow(_ title: String, feedID: Int64?, count: UInt64) -> some View {
        let scope = feedID.map(BrowserScope.feed) ?? .all
        return HStack(spacing: 8) {
            if let feedID {
                FeedIconView(feedID: feedID, title: title, state: store.feedIconPresentationState(for: feedID, variant: iconVariant), onRequest: { store.requestFeedIcon(feedID, variant: iconVariant) }, size: 16)
            }
            labelTitle(title, count: count)
        }
        .tag(scope)
        .contextMenu { if let feedID { Button("Feed Settings") { feedSettingsTarget = .init(id: feedID, title: title) } } }
    }

    private func labelTitle(_ title: String, count: UInt64) -> some View {
        HStack { Text(title); Spacer(); if count > 0 { Text(count > 999 ? "999+" : "\(count)").foregroundStyle(.secondary).font(.caption) } }
    }

    private var iconVariant: FeedIconVariant { IOSFeedIconPresentation.variant(isDark: colorScheme == .dark) }

    private func ensureSelectedFeedIsExpanded() {
        expansionState.ensureSelectedFeedIsExpanded(scope: store.scope, catalog: store.catalog)
    }

    @ToolbarContentBuilder private var addToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Add Feed", systemImage: "plus") { addDestination = .feed }
                Button("Add Category", systemImage: "folder.badge.plus") { addDestination = .category }
            } label: { Label("Add", systemImage: "plus") }
        }
    }

    @ViewBuilder private func addView(_ destination: IOSNavigationAddDestination) -> some View {
        switch destination {
        case .feed: IOSAddFeedView(store: store)
        case .category: IOSAddCategoryView(store: store)
        }
    }
}

private enum IOSNavigationAddDestination: Identifiable { case feed, category; var id: Self { self } }
