import SwiftUI

struct NavigationSidebar: View {
    @ObservedObject var store: BrowserStore
    let onNavigate: (BrowserScope) -> Void

    var body: some View {
        VStack(spacing: 0) {
            List(selection: selectedScope) {
                Section {
                    sidebarRow(SidebarItem(id: "all", scope: .all, title: "All News", count: store.unreadTotal, systemImage: "tray.full", feedID: nil, categoryID: nil, pendingNewCount: 0, children: nil))
                    sidebarRow(SidebarItem(id: "starred", scope: .starred, title: "Starred", count: store.starredTotal, systemImage: "star.fill", feedID: nil, categoryID: nil, pendingNewCount: 0, children: nil))
                    sidebarRow(SidebarItem(id: "listening-list", scope: .listeningList, title: "Listening List", count: 0, systemImage: "headphones", feedID: nil, categoryID: nil, pendingNewCount: 0, children: nil))
                    sidebarRow(SidebarItem(id: "search", scope: .search, title: "Search", count: 0, systemImage: "magnifyingglass", feedID: nil, categoryID: nil, pendingNewCount: 0, children: nil))
                }
                Section("Feeds") {
                    OutlineGroup(categoryItems, children: \.children) { item in sidebarRow(item) }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Button { store.addFeedVisible = true } label: { Label("Add Feed...", systemImage: "plus") }
                Button { store.addCategoryVisible = true } label: { Label("Add Category...", systemImage: "folder.badge.plus") }
            }
            .buttonStyle(.plain)
            .labelStyle(SidebarManagementLabelStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .background(.regularMaterial)
    }

    private var selectedScope: Binding<BrowserScope?> {
        Binding { store.scope } set: { scope in if let scope { onNavigate(scope) } }
    }
    private var categoryItems: [SidebarItem] {
        let visibleFeeds = NavigationVisibility.visibleFeeds(
            store.catalog.feeds.map { NavigationPresentationFeed(id: $0.id, categoryID: $0.categoryId) },
            hidingEmpty: store.hideEmptyNavigationEntries,
            counts: store.feedSidebarCounts
        )
        let visibleFeedIDs = Set(visibleFeeds.map(\.id))
        let visibleCategoryIDs = Set(NavigationVisibility.visibleCategoryIDs(store.catalog.categories.map(\.id), feeds: visibleFeeds))
        return store.catalog.categories.compactMap { category in
            guard !store.hideEmptyNavigationEntries || visibleCategoryIDs.contains(category.id) else { return nil }
            let feeds = store.catalog.feeds.filter { $0.categoryId == category.id && visibleFeedIDs.contains($0.id) }
            return SidebarItem.category(
                category,
                count: store.categorySidebarCounts[category.id] ?? 0,
                pendingNewCount: PendingNewDataAggregation.count(feedIDs: feeds.map(\.id), pendingByFeed: store.pendingNewByFeed),
                feeds: feeds.map { SidebarItem.feed($0, count: store.feedSidebarCounts[$0.id] ?? 0, pendingNewCount: store.pendingNewByFeed[$0.id] ?? 0) }
            )
        }
    }
    @ViewBuilder private func sidebarRow(_ item: SidebarItem) -> some View {
        if item.feedID != nil || item.categoryID != nil {
            sidebarLabel(item, showUnreadText: true)
        } else {
            sidebarLabel(item, showUnreadText: false)
                .badge(Int(item.count))
        }
    }
    private func sidebarLabel(_ item: SidebarItem, showUnreadText: Bool) -> some View {
        Button { onNavigate(item.scope) } label: {
            HStack(spacing: 8) {
                if let image = item.systemImage { Image(systemName: image).frame(width: 16) }
                else if let feedID = item.feedID { FeedIconSlot(feedID: feedID, store: store) }
                Text(item.title).lineLimit(1)
                Spacer(minLength: 0)
                if showUnreadText, item.count > 0 {
                    Text("\(item.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if item.pendingNewCount > 0 {
                    NewDataIndicator(count: item.pendingNewCount)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .tag(item.scope)
        .contextMenu {
            if FeedSettingsRouting.isAvailable(feedID: item.feedID), let feedID = item.feedID {
                Button("Feed Settings...") {
                    store.feedSettingsTarget = FeedSettingsTarget(id: feedID, title: item.title)
                }
            }
        }
    }
}

private struct NewDataIndicator: View {
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "plus")
            Text("\(count) new")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) new articles")
    }
}

private struct SidebarManagementLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.frame(width: 25)
            configuration.title
        }
    }
}

private struct SidebarItem: Identifiable {
    let id: String
    let scope: BrowserScope
    let title: String
    let count: UInt64
    let systemImage: String?
    let feedID: Int64?
    let categoryID: Int64?
    let pendingNewCount: Int
    let children: [SidebarItem]?

    static func category(_ category: Category, count: UInt64, pendingNewCount: Int, feeds: [SidebarItem]) -> SidebarItem {
        SidebarItem(id: "category-\(category.id)", scope: .category(category.id), title: category.title, count: count, systemImage: nil, feedID: nil, categoryID: category.id, pendingNewCount: pendingNewCount, children: feeds.isEmpty ? nil : feeds)
    }
    static func feed(_ feed: Feed, count: UInt64, pendingNewCount: Int) -> SidebarItem {
        SidebarItem(id: "feed-\(feed.id)", scope: .feed(feed.id), title: feed.title, count: count, systemImage: nil, feedID: feed.id, categoryID: nil, pendingNewCount: pendingNewCount, children: nil)
    }
}

struct PlayerNavigationButton: View {
    @ObservedObject var playbackState: MediaPlaybackPresentationState
    @Binding var showingPlayer: Bool

    var body: some View {
        Button { showingPlayer.toggle() } label: {
            Image(systemName: PlayerPresentation.navigationSymbol(showingPlayer: showingPlayer))
        }
        .buttonStyle(.borderless)
        .disabled(PlayerPresentation.navigationDisabled(showingPlayer: showingPlayer, hasLoadedMedia: playbackState.loadedEnclosure != nil))
        .help(showingPlayer ? "Show News List" : "Show Player")
        .accessibilityLabel(showingPlayer ? "Show News List" : "Show Player")
    }
}

/// Compact playback dock for the menu-bar popover. The full player remains
/// reachable by tapping the episode title/cover; play/pause acts in place.
struct MacCompactPlayerBar: View {
    @ObservedObject var playbackState: MediaPlaybackPresentationState
    let coordinator: MediaPlaybackCoordinator?
    let openPlayer: () -> Void
    @State private var artwork: NSImage?

    private var artworkKey: String {
        switch playbackState.artworkSource {
        case let .some(.localReference(reference)): return "local:\(reference)"
        case let .some(.remoteUrl(url)): return "remote:\(url)"
        case .none: return "none"
        }
    }

    var body: some View {
        if let enclosure = playbackState.loadedEnclosure {
            HStack(spacing: 10) {
                Button(action: openPlayer) {
                    HStack(spacing: 9) {
                        Group {
                            if let artwork {
                                Image(nsImage: artwork).resizable().scaledToFill()
                            } else if let fallback = AppleFallbackArtwork.data().flatMap(NSImage.init(data:)) {
                                Image(nsImage: fallback).resizable().scaledToFill()
                            } else {
                                Image(systemName: "waveform").font(.title3)
                            }
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(PlayerPresentation.textOrFallback(
                                playbackState.mediaTitle, fallback: String(localized: "Audio")
                            ))
                            .font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(playbackState.feedTitle).font(.caption)
                                .foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show Player")
                .accessibilityLabel("Show Player")
                Button {
                    coordinator?.skip(bySeconds: -15)
                } label: {
                    Image(systemName: "gobackward.15").frame(width: 23, height: 30)
                }
                .buttonStyle(.borderless)
                .help("Back 15 seconds")
                .accessibilityLabel("Back 15 seconds")
                Button {
                    guard let coordinator else { return }
                    if playbackState.status == .playing {
                        coordinator.pause()
                    } else {
                        try? coordinator.play(enclosureID: enclosure.id)
                    }
                } label: {
                    Image(systemName: playbackState.status == .playing ? "pause.fill" : "play.fill")
                        .frame(width: 28, height: 30)
                }
                .buttonStyle(.borderless)
                .disabled(playbackState.isLoading)
                .help(playbackState.status == .playing ? "Pause" : "Play")
                .accessibilityLabel(playbackState.status == .playing ? "Pause" : "Play")
                Button {
                    coordinator?.skip(bySeconds: 30)
                } label: {
                    Image(systemName: "goforward.30").frame(width: 23, height: 30)
                }
                .buttonStyle(.borderless)
                .help("Forward 30 seconds")
                .accessibilityLabel("Forward 30 seconds")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.regularMaterial)
            .task(id: artworkKey) {
                artwork = nil
                guard let source = playbackState.artworkSource, let coordinator else { return }
                let data = await coordinator.artwork(source: source)
                guard !Task.isCancelled else { return }
                artwork = data.flatMap(NSImage.init(data:))
            }
        }
    }
}

struct MoreMenu: View {
    let isListeningList: Bool
    let unreadOnly: Bool
    let newestFirst: Bool
    let listeningListSort: ListeningListSort
    let listeningListFeedID: Int64?
    let listeningListFeeds: [ListeningListFeed]
    let canMarkAllRead: Bool
    let canMarkAllReadAndNext: Bool
    let markAllRead: () -> Void
    let markAllReadAndNext: () -> Void
    let setUnreadOnly: (Bool) -> Void
    let setNewestFirst: (Bool) -> Void
    let setListeningListSort: (ListeningListSort) -> Void
    let setListeningListFeed: (Int64?) -> Void
    let showSettings: () -> Void
    let quit: () -> Void

    var body: some View {
        Menu {
            if isListeningList {
                listeningListFeedFilter
                Menu {
                    Button { setListeningListSort(.recentlyAdded) } label: { Label("Recently Added", systemImage: listeningListSort == .recentlyAdded ? "checkmark" : "clock") }
                    Button { setListeningListSort(.publicationDate) } label: { Label("Publication Date", systemImage: listeningListSort == .publicationDate ? "checkmark" : "calendar") }
                } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
            } else {
                Button { setUnreadOnly(true) } label: { Label("Show Unread News Only", systemImage: unreadOnly ? "checkmark.circle.fill" : "circle") }
                Button { setUnreadOnly(false) } label: { Label("Show All News", systemImage: unreadOnly ? "circle" : "checkmark.circle.fill") }
                Divider()
                Menu {
                    Button { setNewestFirst(true) } label: { Label("Newest First", systemImage: newestFirst ? "checkmark" : "arrow.down") }
                    Button { setNewestFirst(false) } label: { Label("Oldest First", systemImage: newestFirst ? "arrow.up" : "checkmark") }
                } label: { Label("Sort Order", systemImage: "arrow.up.arrow.down") }
            }
            if !isListeningList {
                Divider()
                Button(action: markAllRead) { Label("Mark All as Read", systemImage: "checkmark.circle") }
                    .disabled(!canMarkAllRead)
                Button(action: markAllReadAndNext) { Label("Mark All as Read & Next", systemImage: "arrow.right.circle") }
                    .disabled(!canMarkAllReadAndNext)
            }
            Divider()
            Button { showSettings() } label: { Label("Settings...", systemImage: "gearshape") }
            Button { quit() } label: { Label("Quit FluxNews", systemImage: "power") }
        } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("More")
            .accessibilityLabel("More")
    }

    private var listeningListFeedFilter: some View {
        Menu {
            Button { setListeningListFeed(nil) } label: { Label("All Feeds", systemImage: listeningListFeedID == nil ? "checkmark" : "circle") }
            ForEach(listeningListFeeds, id: \.feedId) { feed in
                Button { setListeningListFeed(feed.feedId) } label: { Label(feed.feedTitle, systemImage: listeningListFeedID == feed.feedId ? "checkmark" : "circle") }
            }
        } label: { Label("Filter by Feed", systemImage: "line.3.horizontal.decrease.circle") }
    }
}
