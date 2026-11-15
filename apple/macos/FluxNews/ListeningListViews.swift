import SwiftUI
import AppKit
import ImageIO

struct ListeningListView: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var playbackState: MediaPlaybackPresentationState
    @ObservedObject var transferState: MediaTransferPresentationState
    let onOpenPlayer: (Int64) -> Void
    let onPlay: (Enclosure) -> Void
    let onPause: () -> Void
    let coordinator: MediaPlaybackCoordinator?
    let onDownload: (Int64, Int64) -> Void
    let onDelete: (Int64, Int64) -> Void
    let onCancel: (Int64, Int64) -> Void
    let onRemove: (Int64) -> Void

    var body: some View {
        if let error = store.errorMessage, store.listeningListItems.isEmpty {
            ContentUnavailableView("Listening List unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.listeningListItems.isEmpty {
            ContentUnavailableView("Listening List is Empty", systemImage: "headphones", description: Text("Audio News added to the Listening List will appear here."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.listeningListItems, id: \.articleId) { item in
                        ListeningListRow(item: item, store: store, playbackState: playbackState, transferState: transferState, onOpenPlayer: onOpenPlayer, onPlay: onPlay, onPause: onPause, coordinator: coordinator, onDownload: onDownload, onDelete: onDelete, onCancel: onCancel, onRemove: onRemove)
                        Divider().padding(.leading, 12)
                    }
                }
            }
        }
    }
}

private struct ListeningListRow: View {
    let item: ListeningListItem
    @ObservedObject var store: BrowserStore
    @ObservedObject var playbackState: MediaPlaybackPresentationState
    @ObservedObject var transferState: MediaTransferPresentationState
    let onOpenPlayer: (Int64) -> Void
    let onPlay: (Enclosure) -> Void
    let onPause: () -> Void
    let coordinator: MediaPlaybackCoordinator?
    let onDownload: (Int64, Int64) -> Void
    let onDelete: (Int64, Int64) -> Void
    let onCancel: (Int64, Int64) -> Void
    let onRemove: (Int64) -> Void
    @State private var confirmingRemoval = false
    @State private var pendingDeletion: ListeningListEnclosure?
    private static let isoFormatter = ISO8601DateFormatter()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top, spacing: 6) {
                        Text(ListeningListPresentation.textOrFallback(item.title, fallback: String(localized: "Untitled News")))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if ListeningListPresentation.progress(item, runtime: playbackState)?.status == .completed {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.green)
                                .accessibilityLabel(Text("Completed"))
                        } else if ListeningListPresentation.isUnplayed(item, runtime: playbackState) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.accentColor)
                                .accessibilityLabel(Text("Not played yet"))
                        }
                    }
                    HStack(spacing: 5) {
                        FeedIconSlot(feedID: item.feedId, store: store)
                        Text(ListeningListPresentation.textOrFallback(item.feedTitle, fallback: String(localized: "Unknown Feed")))
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                    .font(.caption)
                    if let date = Self.isoFormatter.date(from: item.publishedAt) {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { onOpenPlayer(item.articleId) }
                progress
                status
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            let artwork = ListeningListPresentation.artworkEnclosure(
                item, loadedEnclosureID: playbackState.loadedEnclosure?.id
            )
            MacListeningListArtworkView(
                enclosureID: artwork?.enclosure.id,
                refreshToken: ListeningListPresentation.artworkRefreshToken(artwork)
                    + "|probe:\(store.artworkProbeRevisions[artwork?.enclosure.id ?? -1, default: 0])",
                store: store,
                coordinator: coordinator
            )
            .frame(width: 80, height: 80)
            .contentShape(Rectangle())
            .onTapGesture { onOpenPlayer(item.articleId) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contextMenuIf(item.audioEnclosures.count > 1 && item.activeEnclosureId == nil) {
            ForEach(item.audioEnclosures, id: \.enclosure.id) { audio in
                Button("Play \(ArticleAudioActions.enclosureLabel(audio.enclosure, index: item.audioEnclosures.firstIndex(where: { $0.enclosure.id == audio.enclosure.id }) ?? 0))") { onPlay(audio.enclosure) }
            }
        }
        .alert("Remove from Listening List?", isPresented: $confirmingRemoval) {
            Button("Cancel", role: .cancel) { confirmingRemoval = false }
            Button("Remove", role: .destructive) { confirmingRemoval = false; onRemove(item.articleId) }
        } message: {
            Text("Downloaded audio for this item will also be deleted.")
        }
        .alert("Delete Download?", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })) {
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
            Button("Delete", role: .destructive) {
                if let audio = pendingDeletion { pendingDeletion = nil; onDelete(item.articleId, audio.enclosure.id) }
            }
        } message: {
            Text("The downloaded audio file will be deleted.")
        }
    }

    @ViewBuilder private var progress: some View {
        if let value = ListeningListPresentation.progress(item, runtime: playbackState) {
            if value.status == .completed {
                ProgressView(value: 1)
                    .progressViewStyle(.linear)
                    .tint(.green)
                Text("Completed").foregroundStyle(.secondary)
            } else if let duration = value.durationMs, duration > 0 {
                ProgressView(value: min(Double(value.positionMs) / Double(duration), 1))
                    .progressViewStyle(.linear)
                Text("\(Self.minutes(value.positionMs)) / \(Self.minutes(duration)) min").foregroundStyle(.secondary)
            } else if value.positionMs > 0 {
                Text("\(Self.minutes(value.positionMs)) min").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var status: some View {
        HStack(spacing: 8) {
            if let selected = ListeningListPresentation.preferredEnclosure(item) {
                let pause = ListeningListPresentation.shouldPause(
                    enclosureID: selected.id,
                    loadedEnclosureID: playbackState.loadedEnclosure?.id,
                    isPlaying: playbackState.status == .playing
                )
                Button {
                    if pause { onPause() }
                    else { onPlay(selected) }
                } label: {
                    Image(systemName: pause ? "pause.fill" : "play.fill")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.bordered)
                .help(pause ? "Pause" : "Play")
                .accessibilityLabel(pause ? "Pause" : "Play")
            } else if !item.audioEnclosures.isEmpty {
                Menu {
                    ForEach(item.audioEnclosures.indices, id: \.self) { index in
                        let audio = item.audioEnclosures[index]
                        Button(ArticleAudioActions.enclosureLabel(audio.enclosure, index: index)) {
                            onPlay(audio.enclosure)
                        }
                    }
                } label: {
                    Image(systemName: "play.fill").frame(width: 24, height: 22)
                }
                .menuStyle(.borderlessButton)
                .help("Choose audio to play")
                .accessibilityLabel("Choose audio to play")
            }

            DownloadControl(
                item: item, transferState: transferState, onDownload: onDownload,
                onDelete: { pendingDeletion = $0 }, onCancel: onCancel
            )
            let downloads = ListeningListPresentation.downloadedCount(item)
            if downloads.total > 1 {
                Text("\(downloads.downloaded)/\(downloads.total)")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            Button {
                if ArticleAudioActions.hasLocalDownload(item) { confirmingRemoval = true }
                else { onRemove(item.articleId) }
            } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Remove from Listening List")
                .accessibilityLabel("Remove from Listening List")
        }
    }

    private static func minutes(_ milliseconds: UInt64) -> String {
        String(max(0, Int(milliseconds / 60_000)))
    }

}

/// Per-row artwork uses a bounded decoded-pixel cache. The row's task is
/// cancelled as soon as its LazyVStack view leaves the viewport.
private struct MacListeningListArtworkView: View {
    private struct PreparedThumbnail: @unchecked Sendable {
        let cgImage: CGImage
        let pixelCost: Int
    }

    nonisolated(unsafe) private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 16 * 1_024 * 1_024
        cache.countLimit = 160
        return cache
    }()
    private static let fallback = AppleFallbackArtwork.data().flatMap(NSImage.init(data:))

    let enclosureID: Int64?
    let refreshToken: String
    let store: BrowserStore
    let coordinator: MediaPlaybackCoordinator?
    @State private var image: NSImage?

    private var cacheKey: NSString? {
        enclosureID.map { "\($0)|\(refreshToken)" as NSString }
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else if let fallback = Self.fallback {
                Image(nsImage: fallback).resizable().scaledToFill()
            } else {
                Image(systemName: "waveform")
                    .resizable().scaledToFit().padding(14)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 80, height: 80)
        .background(.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("Media artwork")
        .task(id: refreshToken, priority: .utility) {
            image = nil
            guard let enclosureID, let cacheKey, let coordinator else { return }
            if let cached = Self.cache.object(forKey: cacheKey) {
                image = cached
                return
            }
            // Avoid starting Core and network work for rows passed in a fast fling.
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            let source: MediaArtworkSource? = await withCheckedContinuation { continuation in
                store.loadPlayerArtworkSource(enclosureID: enclosureID) {
                    continuation.resume(returning: $0)
                }
            }
            guard !Task.isCancelled, let source else { return }
            guard let data = await coordinator.artwork(source: source),
                  !Task.isCancelled else { return }
            guard let prepared = await Self.prepareThumbnail(data), !Task.isCancelled else { return }
            // AppKit image creation stays on the main actor; only ImageIO decode runs detached.
            let image = NSImage(
                cgImage: prepared.cgImage,
                size: NSSize(width: prepared.cgImage.width, height: prepared.cgImage.height)
            )
            Self.cache.setObject(image, forKey: cacheKey, cost: prepared.pixelCost)
            self.image = image
        }
    }

    private static func prepareThumbnail(_ data: Data) async -> PreparedThumbnail? {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options: CFDictionary = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 240,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
                return nil
            }
            return PreparedThumbnail(
                cgImage: thumbnail, pixelCost: thumbnail.bytesPerRow * thumbnail.height
            )
        }.value
    }
}

private struct DownloadControl: View {
    let item: ListeningListItem
    @ObservedObject var transferState: MediaTransferPresentationState
    let onDownload: (Int64, Int64) -> Void
    let onDelete: (ListeningListEnclosure) -> Void
    let onCancel: (Int64, Int64) -> Void
    @State private var hoveredDownloadedID: Int64?

    var body: some View {
        if item.audioEnclosures.isEmpty {
            EmptyView()
        } else if item.audioEnclosures.count == 1, let audio = item.audioEnclosures.first {
            control(for: audio)
        } else {
            Menu {
                ForEach(item.audioEnclosures.indices, id: \.self) { index in
                    let audio = item.audioEnclosures[index]
                    Button {
                        activate(audio)
                    } label: {
                        Label(actionTitle(audio, index: index), systemImage: symbol(for: audio))
                    }
                    .disabled(!isActionable(audio))
                }
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Download")
            .accessibilityLabel("Download")
        }
    }

    @ViewBuilder private func control(for audio: ListeningListEnclosure) -> some View {
        let action = ArticleAudioActions.downloadAction(audio.download, runtime: transferState.runtime(for: audio.enclosure.id))
        switch action {
        case .downloading:
            HStack(spacing: 4) {
                ProgressView(value: transferState.runtime(for: audio.enclosure.id)?.fraction)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                Button { onCancel(item.articleId, audio.enclosure.id) } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Cancel Download")
                .accessibilityLabel("Cancel Download")
            }
        case .pending:
            Button { onCancel(item.articleId, audio.enclosure.id) } label: {
                Label("Cancel Download", systemImage: "xmark.circle")
            }
            .buttonStyle(.borderless)
        case .pendingDeletion:
            ProgressView().controlSize(.small).help("Delete Download pending")
        default:
            Button { activate(audio) } label: {
                Image(systemName: symbol(for: audio))
                    .foregroundStyle(action == .delete ? .green : .secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!isActionable(audio))
            .onHover { isHovered in
                hoveredDownloadedID = isHovered && action == .delete ? audio.enclosure.id : nil
            }
            .help(action == .delete && hoveredDownloadedID == audio.enclosure.id ? "Delete Download" : action == .retry ? "Retry Download" : "Download")
            .accessibilityLabel(action == .delete ? "Downloaded" : action == .retry ? "Retry Download" : "Download")
        }
    }

    private func activate(_ audio: ListeningListEnclosure) {
        let action = ArticleAudioActions.downloadAction(audio.download, runtime: transferState.runtime(for: audio.enclosure.id))
        if action == .downloading || action == .pending { onCancel(item.articleId, audio.enclosure.id); return }
        if ArticleAudioActions.canDeleteDownload(audio.download) { onDelete(audio) }
        else if ArticleAudioActions.canRequestDownload(audio.download) { onDownload(item.articleId, audio.enclosure.id) }
    }

    private func isActionable(_ audio: ListeningListEnclosure) -> Bool {
        let action = ArticleAudioActions.downloadAction(audio.download, runtime: transferState.runtime(for: audio.enclosure.id))
        return action == .downloading || action == .pending || ArticleAudioActions.canRequestDownload(audio.download) || ArticleAudioActions.canDeleteDownload(audio.download)
    }

    private func symbol(for audio: ListeningListEnclosure) -> String {
        let action = ArticleAudioActions.downloadAction(audio.download, runtime: transferState.runtime(for: audio.enclosure.id))
        if action == .delete && hoveredDownloadedID == audio.enclosure.id { return "trash" }
        switch action {
        case .delete: return "checkmark.circle.fill"
        case .downloading, .pending: return "xmark.circle"
        case .retry: return "arrow.clockwise.circle"
        default: return "arrow.down.circle"
        }
    }

    private func actionTitle(_ audio: ListeningListEnclosure, index: Int) -> String {
        let label = ArticleAudioActions.enclosureLabel(audio.enclosure, index: index)
        switch ArticleAudioActions.downloadAction(audio.download, runtime: transferState.runtime(for: audio.enclosure.id)) {
        case .delete: return String(localized: "Delete Download: \(label)")
        case .pending: return String(localized: "Cancel Download: \(label)")
        case .downloading: return String(localized: "Cancel Download: \(label)")
        case .pendingDeletion: return String(localized: "Delete Download pending: \(label)")
        case .retry: return String(localized: "Retry Download: \(label)")
        case .download: return String(localized: "Download: \(label)")
        }
    }
}

private extension View {
    @ViewBuilder
    func contextMenuIf<Content: View>(_ enabled: Bool, @ViewBuilder content: @escaping () -> Content) -> some View {
        if enabled {
            contextMenu { content() }
        } else {
            self
        }
    }
}
