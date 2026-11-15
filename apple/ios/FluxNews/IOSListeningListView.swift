import ImageIO
import SwiftUI
import UIKit

struct IOSListeningListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: IOSListeningListStore
    @ObservedObject var playbackState: IOSMediaPlaybackPresentationState
    @ObservedObject var transferState: IOSMediaTransferPresentationState
    let playbackCoordinator: IOSMediaPlaybackCoordinator
    let onOpenPlayer: (_ articleID: Int64) -> Void
    let onPlay: (_ articleID: Int64, _ enclosureID: Int64) -> Void
    let feedIconState: (_ feedID: Int64, _ variant: FeedIconVariant) -> IOSFeedIconPresentationState
    let onRequestFeedIcon: (_ feedID: Int64, _ variant: FeedIconVariant) -> Void

    private static let isoFormatter = ISO8601DateFormatter()

    var body: some View {
        Group {
            if store.isLoading && store.items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.errorMessage, store.items.isEmpty {
                ContentUnavailableView {
                    Label("Listening List", systemImage: "headphones")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { store.reload() }
                }
            } else if store.items.isEmpty {
                ContentUnavailableView(
                    "Listening List is Empty",
                    systemImage: "headphones",
                    description: Text(
                        "Add audio news to your Listening List to find them here."
                    )
                )
            } else {
                List(store.items, id: \.articleId) { item in
                    row(item)
                }
                .refreshable { store.reload() }
            }
        }
        .navigationTitle("Listening List")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                feedMenu
                sortMenu
            }
        }
    }

    @ViewBuilder
    private func row(_ item: ListeningListItem) -> some View {
        let playbackProgress = IOSListeningListPresentation.progress(
            item,
            runtime: playbackState
        )
        let isCompleted = playbackProgress?.status == .completed
        let isUnplayed = !isCompleted && IOSListeningListPresentation.isUnplayed(
            item,
            runtime: playbackState
        )

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                let artworkEnclosure = artworkEnclosure(item)
                IOSListeningListArtworkView(
                    enclosureID: artworkEnclosure?.enclosure.id,
                    refreshToken: artworkRefreshToken(artworkEnclosure),
                    playbackCoordinator: playbackCoordinator
                )
                .frame(width: 80, height: 80)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 6) {
                        Text(
                            IOSListeningListPresentation.textOrFallback(
                                item.title,
                                fallback: String(localized: "Untitled News")
                            )
                        )
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)

                        if isCompleted {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                                .accessibilityLabel(String(localized: "Completed"))
                        } else if isUnplayed {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.accentColor)
                                .accessibilityLabel(String(localized: "Not played yet"))
                        }
                    }

                    HStack(spacing: 6) {
                        FeedIconView(
                            feedID: item.feedId,
                            title: item.feedTitle,
                            state: feedIconState(
                                item.feedId,
                                feedIconVariant
                            ),
                            onRequest: {
                                onRequestFeedIcon(
                                    item.feedId,
                                    feedIconVariant
                                )
                            },
                            size: 16
                        )
                        Text(
                            IOSListeningListPresentation.textOrFallback(
                                item.feedTitle,
                                fallback: String(localized: "Unknown Feed")
                            )
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    if let date = Self.isoFormatter.date(
                        from: item.publishedAt
                    ) {
                        Text(
                            date.formatted(
                                date: .abbreviated,
                                time: .omitted
                            )
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    onOpenPlayer(item.articleId)
                }

            }

            if let playbackProgress {
                VStack(alignment: .leading, spacing: 4) {
                    if isCompleted {
                        ProgressView(value: 1)
                            .tint(.green)
                    } else if let fraction = playbackProgress.fraction {
                        ProgressView(value: fraction)
                    }
                    Text(progressLabel(playbackProgress))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    onOpenPlayer(item.articleId)
                }
            }

            let downloads = IOSListeningListPresentation.downloadSummary(
                item,
                transfers: transferState.transfers
            )
            HStack(spacing: 10) {
                HStack(spacing: 12) {
                    mediaStatusMetric(
                        enclosureLabel(item.audioEnclosures.count),
                        systemImage: "waveform"
                    )
                    if downloads.downloaded > 0 {
                        mediaStatusMetric(
                            String(localized: "\(downloads.downloaded) downloaded"),
                            systemImage: "arrow.down.circle.fill"
                        )
                    } else if downloads.pending > 0 {
                        mediaStatusMetric(
                            String(localized: "\(downloads.pending) pending"),
                            systemImage: "clock"
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    onOpenPlayer(item.articleId)
                }

                HStack(spacing: 4) {
                    primaryPlayControl(item)
                    itemMenu(item)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let transfer = IOSListeningListPresentation.transferProgress(
                item,
                transfers: transferState.transfers
            ) {
                HStack(spacing: 8) {
                    if let fraction = transfer.fraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView()
                    }
                    Text(transfer.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    onOpenPlayer(item.articleId)
                }
            }
        }
        .padding(.vertical, 4)
        .alignmentGuide(.listRowSeparatorLeading) { dimensions in
            dimensions[.leading]
        }
        .alignmentGuide(.listRowSeparatorTrailing) { dimensions in
            dimensions[.trailing]
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func primaryPlayControl(_ item: ListeningListItem) -> some View {
        if let enclosure = IOSListeningListPresentation.selectedEnclosure(item) {
            let action = IOSListeningListPresentation.playbackAction(
                enclosureID: enclosure.enclosure.id,
                loadedEnclosureID: playbackState.loadedEnclosure?.id,
                status: playbackState.status
            )
            Button {
                performPlaybackAction(
                    action,
                    item: item,
                    enclosureID: enclosure.enclosure.id
                )
            } label: {
                Image(
                    systemName: action == .pause
                        ? "pause.fill"
                        : "play.fill"
                )
                .frame(width: 22, height: 22)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(
                action == .pause
                    ? String(localized: "Pause")
                    : String(localized: "Play")
            )
        } else if !item.audioEnclosures.isEmpty {
            Menu {
                ForEach(
                    Array(item.audioEnclosures.enumerated()),
                    id: \.element.enclosure.id
                ) { index, enclosure in
                    Button {
                        onPlay(
                            item.articleId,
                            enclosure.enclosure.id
                        )
                    } label: {
                        Text(
                            IOSListeningListPresentation.enclosureLabel(
                                enclosure.enclosure,
                                index: index
                            )
                        )
                    }
                }
            } label: {
                Image(systemName: "play.fill")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(String(localized: "Play"))
        }
    }

    private func itemMenu(_ item: ListeningListItem) -> some View {
        Menu {
            ForEach(
                Array(item.audioEnclosures.enumerated()),
                id: \.element.enclosure.id
            ) { index, enclosure in
                Menu {
                    let action = IOSListeningListPresentation.playbackAction(
                        enclosureID: enclosure.enclosure.id,
                        loadedEnclosureID: playbackState.loadedEnclosure?.id,
                        status: playbackState.status
                    )
                    Button {
                        performPlaybackAction(
                            action,
                            item: item,
                            enclosureID: enclosure.enclosure.id
                        )
                    } label: {
                        Label(
                            action == .pause
                                ? String(localized: "Pause")
                                : String(localized: "Play"),
                            systemImage: action == .pause
                                ? "pause.fill"
                                : "play.fill"
                        )
                    }

                    downloadAction(
                        enclosure,
                        label: IOSListeningListPresentation.enclosureLabel(
                            enclosure.enclosure,
                            index: index
                        )
                    )
                } label: {
                    Label(
                        IOSListeningListPresentation.enclosureLabel(
                            enclosure.enclosure,
                            index: index
                        ),
                        systemImage: "waveform"
                    )
                }
            }

            Divider()

            Button(role: .destructive) {
                Task {
                    await store.removeFromListeningList(
                        articleID: item.articleId
                    )
                }
            } label: {
                Label(
                    "Remove from Listening List",
                    systemImage: "minus.circle"
                )
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(String(localized: "Listening List actions"))
    }

    private func artworkEnclosure(
        _ item: ListeningListItem
    ) -> ListeningListEnclosure? {
        if let loadedID = playbackState.loadedEnclosure?.id,
           let loaded = item.audioEnclosures.first(
            where: { $0.enclosure.id == loadedID }
           ) {
            return loaded
        }
        if let activeID = item.activeEnclosureId,
           let active = item.audioEnclosures.first(
            where: { $0.enclosure.id == activeID }
           ) {
            return active
        }
        return item.audioEnclosures.first
    }

    private func artworkRefreshToken(
        _ enclosure: ListeningListEnclosure?
    ) -> String {
        guard let enclosure else { return "none" }
        let state = enclosure.download.map { String(describing: $0.state) } ?? "none"
        let downloadedAt = enclosure.download?.downloadedAt ?? ""
        return [String(enclosure.enclosure.id), state, downloadedAt].joined(separator: "|")
    }

    private func performPlaybackAction(
        _ action: IOSListeningListPresentation.PlaybackAction,
        item: ListeningListItem,
        enclosureID: Int64
    ) {
        switch action {
        case .pause:
            playbackCoordinator.pause()
        case .play:
            onPlay(item.articleId, enclosureID)
        }
    }

    @ViewBuilder
    private func downloadAction(
        _ enclosure: ListeningListEnclosure,
        label: String
    ) -> some View {
        let action = IOSListeningListPresentation.downloadAction(
            enclosure,
            runtime: transferState.runtime(for: enclosure.enclosure.id)
        )
        switch action {
        case .delete:
            Button(role: .destructive) {
                Task {
                    await store.deleteDownload(
                        enclosureID: enclosure.enclosure.id
                    )
                }
            } label: {
                Label("Delete Download", systemImage: "trash")
            }

        case .pending, .downloading:
            Button {
                Task {
                    await store.cancelDownload(
                        enclosureID: enclosure.enclosure.id
                    )
                }
            } label: {
                if action == .downloading,
                   let fraction = transferState.runtime(
                       for: enclosure.enclosure.id
                   )?.fraction {
                    Label(
                        String(
                            localized: "\(Int((fraction * 100).rounded()))% downloaded"
                        ),
                        systemImage: "xmark.circle"
                    )
                } else {
                    Label("Cancel Download", systemImage: "xmark.circle")
                }
            }

        case .cancelling:
            Label("Cancelling Download", systemImage: "clock")

        case .retry:
            Button {
                Task {
                    await store.retryDownload(
                        enclosureID: enclosure.enclosure.id
                    )
                }
            } label: {
                Label("Retry Download", systemImage: "arrow.clockwise")
            }

        case .pendingDeletion:
            Label("Deletion Pending", systemImage: "clock")

        case .download:
            Button {
                Task {
                    await store.requestDownload(
                        enclosureID: enclosure.enclosure.id
                    )
                }
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        }
    }

    private struct IOSListeningListArtworkView: View {
        private struct PreparedArtwork: @unchecked Sendable {
            let image: UIImage
            let pixelCost: Int
        }

        nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()
        nonisolated(unsafe) private static let fallbackImage: UIImage? =
            AppleFallbackArtwork.data().flatMap(UIImage.init(data:))

        let enclosureID: Int64?
        let refreshToken: String
        let playbackCoordinator: IOSMediaPlaybackCoordinator

        @State private var image: UIImage?

        private var cacheKey: NSString? {
            enclosureID.map { "\($0)|\(refreshToken)" as NSString }
        }

        var body: some View {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if let fallback = Self.fallbackImage {
                    Image(uiImage: fallback)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "waveform")
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .task(id: refreshToken, priority: .utility) {
                guard let enclosureID, let cacheKey else {
                    image = nil
                    return
                }
                if let cached = Self.cache.object(forKey: cacheKey) {
                    image = cached
                    return
                }

                // Avoid starting network/Core work for rows that only flash by
                // during a fast scroll. SwiftUI cancels the task when the row
                // leaves the hierarchy.
                try? await Task.sleep(nanoseconds: 90_000_000)
                guard !Task.isCancelled else { return }

                guard let source = await playbackCoordinator.previewArtworkSource(
                    enclosureID: enclosureID
                ),
                      let data = await playbackCoordinator.artwork(source: source),
                      !Task.isCancelled else {
                    image = nil
                    return
                }
                let displayScale = UIScreen.main.scale
                guard let prepared = await Self.prepareThumbnail(
                    data,
                    displayScale: displayScale
                ) else {
                    image = nil
                    return
                }

                Self.cache.setObject(
                    prepared.image,
                    forKey: cacheKey,
                    cost: prepared.pixelCost
                )
                image = prepared.image
            }
        }

        private static func prepareThumbnail(
            _ data: Data,
            displayScale: CGFloat
        ) async -> PreparedArtwork? {
            await Task.detached(priority: .utility) {
                let maxPixelSize = Int((56 * max(displayScale, 1)).rounded(.up))
                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                    return nil
                }
                let options: CFDictionary = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary
                guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                    source,
                    0,
                    options
                ) else {
                    return nil
                }
                return PreparedArtwork(
                    image: UIImage(cgImage: thumbnail),
                    pixelCost: thumbnail.bytesPerRow * thumbnail.height
                )
            }.value
        }
    }

    private var feedMenu: some View {
        Menu {
            Button {
                store.setFeedID(nil)
            } label: {
                filterLabel(
                    String(localized: "All Feeds"),
                    selected: store.feedID == nil
                )
            }

            ForEach(store.feeds, id: \.feedId) { feed in
                Button {
                    store.setFeedID(feed.feedId)
                } label: {
                    filterLabel(
                        feed.feedTitle,
                        selected: store.feedID == feed.feedId
                    )
                }
            }
        } label: {
            Label("Feed", systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel(String(localized: "Filter Listening List by feed"))
    }

    private var sortMenu: some View {
        Menu {
            Button {
                store.setSort(.recentlyAdded)
            } label: {
                filterLabel(
                    String(localized: "Recently Added"),
                    selected: store.sort == .recentlyAdded
                )
            }
            Button {
                store.setSort(.publicationDate)
            } label: {
                filterLabel(
                    String(localized: "Publication Date"),
                    selected: store.sort == .publicationDate
                )
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .accessibilityLabel(String(localized: "Sort Listening List"))
    }

    @ViewBuilder
    private func filterLabel(_ title: String, selected: Bool) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private func progressLabel(
        _ progress: IOSListeningListPresentation.Progress
    ) -> String {
        if progress.status == .completed {
            return String(localized: "Completed")
        }
        let position = IOSMediaTimePresentation.label(progress.positionMs)
        guard let duration = progress.durationMs else {
            return position
        }
        let total = IOSMediaTimePresentation.label(duration)
        return "\(position) / \(total)"
    }

    private var feedIconVariant: FeedIconVariant {
        IOSFeedIconPresentation.variant(
            isDark: colorScheme == .dark
        )
    }

    private func mediaStatusMetric(
        _ text: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .imageScale(.small)
            Text(text)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func enclosureLabel(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 audio")
            : String(localized: "\(count) audio")
    }
}
