import AppKit
import SwiftUI

enum PlayerPresentation {
    static func textOrFallback(_ value: String, fallback: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : value
    }

    static func navigationSymbol(showingPlayer: Bool) -> String {
        showingPlayer ? "list.bullet" : "waveform"
    }

    static func navigationDisabled(showingPlayer: Bool, hasLoadedMedia: Bool) -> Bool {
        !showingPlayer && !hasLoadedMedia
    }

    static func seekTarget(positionMs: UInt64, deltaMs: Int64, durationMs: UInt64?) -> UInt64 {
        let target: UInt64
        if deltaMs < 0 {
            let distance = UInt64(deltaMs.magnitude)
            target = positionMs > distance ? positionMs - distance : 0
        } else {
            let result = positionMs.addingReportingOverflow(UInt64(deltaMs))
            target = result.overflow ? UInt64.max : result.partialValue
        }
        return durationMs.map { min(target, $0) } ?? target
    }

    static func formatDuration(_ milliseconds: UInt64) -> String {
        let totalSeconds = milliseconds / 1_000
        let seconds = totalSeconds % 60
        let minutes = totalSeconds / 60
        if minutes >= 60 {
            return String(format: "%d:%02d:%02d", minutes / 60, minutes % 60, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func timelineAccessibilityValue(positionMs: UInt64, durationMs: UInt64) -> String {
        let position = min(positionMs, durationMs)
        return String(localized: "Playback position \(formatDuration(position)) of \(formatDuration(durationMs))")
    }

    static func activeChapterIndex(positionMs: UInt64, chapters: [MediaChapter]) -> Int? {
        chapters.indices.last { index in
            let chapter = chapters[index]
            let end = chapter.endMs ?? chapters.dropFirst(index + 1).first?.startMs
            return positionMs >= chapter.startMs && (end == nil || positionMs < end!)
        }
    }
}

struct PlayerView: View {
    let store: BrowserStore
    @ObservedObject var state: MediaPlaybackPresentationState
    let coordinator: MediaPlaybackCoordinator?
    let previewArticleID: Int64?
    let onPlayEnclosure: (Enclosure) -> Void
    let onDownload: (Int64, Int64) -> Void
    let onDelete: (Int64, Int64) -> Void
    let onCancel: (Int64, Int64) -> Void
    let onStop: () -> Void
    @ObservedObject private var sleepTimer: MediaSleepTimer
    @State private var isScrubbing = false
    @State private var scrubPositionMs = 0.0
    @State private var readerDocument: ReaderDocument?
    @State private var isLoadingReaderDocument = false
    @State private var readerError: String?
    @State private var readerRequest = 0
    @State private var showNotesExpanded = false
    @State private var advancedSettingsExpanded = false
    @State private var artworkImage: NSImage?
    @State private var artworkLoading = false
    @State private var previewChapters: [MediaChapter] = []

    init(store: BrowserStore, state: MediaPlaybackPresentationState, coordinator: MediaPlaybackCoordinator?,
         previewArticleID: Int64? = nil, onPlayEnclosure: @escaping (Enclosure) -> Void = { _ in },
         onDownload: @escaping (Int64, Int64) -> Void = { _, _ in },
         onDelete: @escaping (Int64, Int64) -> Void = { _, _ in },
         onCancel: @escaping (Int64, Int64) -> Void = { _, _ in },
         onStop: @escaping () -> Void = {}) {
        self.store = store
        self.state = state
        self.coordinator = coordinator
        self.previewArticleID = previewArticleID
        self.onPlayEnclosure = onPlayEnclosure
        self.onDownload = onDownload
        self.onDelete = onDelete
        self.onCancel = onCancel
        self.onStop = onStop
        _sleepTimer = ObservedObject(wrappedValue: coordinator?.sleepTimer ?? MediaSleepTimer())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            fixedPlayback
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    audioSelection
                    showNotes
                    chapters
                    advancedSettings
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: state.positionMs) { _, position in
            if !isScrubbing { scrubPositionMs = Double(position) }
        }
        .onAppear { resetShowNotes() }
        .onChange(of: displayedArticleID) { _, _ in resetShowNotes() }
        .task(id: artworkKey) { await loadArtwork() }
        .task(id: chapterPreviewKey) { await loadPreviewChapters() }
    }

    private var previewItem: ListeningListItem? {
        previewArticleID.flatMap { id in store.listeningListItems.first(where: { $0.articleId == id }) }
    }
    private var previewing: Bool {
        guard let previewArticleID else { return false }
        return state.loadedEnclosure?.articleId != previewArticleID
    }
    private var displayedArticleID: Int64? {
        previewing ? previewArticleID : state.loadedEnclosure?.articleId
    }
    private var previewEnclosure: ListeningListEnclosure? {
        guard let item = previewItem else { return nil }
        return item.audioEnclosures.first(where: { $0.enclosure.id == item.activeEnclosureId })
            ?? item.audioEnclosures.first
    }
    private var chapterPreviewKey: String {
        previewing ? "preview:\(previewEnclosure?.enclosure.id ?? -1)" : "active"
    }
    private var displayedChapters: [MediaChapter] {
        previewing ? previewChapters : state.chapters
    }
    private func loadPreviewChapters() async {
        previewChapters = []
        guard previewing, let id = previewEnclosure?.enclosure.id else { return }
        let chapters: [MediaChapter] = await withCheckedContinuation { continuation in
            store.loadPlayerPreviewChapters(enclosureID: id) {
                continuation.resume(returning: $0)
            }
        }
        guard !Task.isCancelled, previewing, previewEnclosure?.enclosure.id == id else { return }
        previewChapters = chapters
    }
    private var artworkEnclosureID: Int64? {
        previewing ? previewEnclosure?.enclosure.id : state.loadedEnclosure?.id
    }
    private var artworkKey: String {
        let revision = store.artworkProbeRevisions[artworkEnclosureID ?? -1, default: 0]
        if previewing { return "preview:\(artworkEnclosureID ?? -1)|probe:\(revision)" }
        switch state.artworkSource {
        case let .some(.localReference(reference)): return "local:\(reference)|probe:\(revision)"
        case let .some(.remoteUrl(url)): return "remote:\(url)|probe:\(revision)"
        case .none: return "none|probe:\(revision)"
        }
    }
    private func loadArtwork() async {
        artworkImage = nil
        artworkLoading = true
        defer { artworkLoading = false }
        guard let coordinator else { return }
        let source: MediaArtworkSource?
        if let id = artworkEnclosureID, (previewing || state.artworkSource == nil) {
            source = await withCheckedContinuation { continuation in
                store.loadPlayerArtworkSource(enclosureID: id) { continuation.resume(returning: $0) }
            }
        } else {
            source = state.artworkSource
        }
        guard !Task.isCancelled, let source else { return }
        let data = await coordinator.artwork(source: source)
        guard !Task.isCancelled else { return }
        artworkImage = data.flatMap(NSImage.init(data:))
    }

    private var fixedPlayback: some View {
        VStack(alignment: .leading, spacing: 14) {
            if previewing {
                VStack(alignment: .leading, spacing: 6) {
                    Slider(value: .constant(0), in: 0...1)
                        .disabled(true)
                        .accessibilityLabel("Playback timeline unavailable")
                    HStack {
                        Text("0:00")
                        Spacer()
                        Text("--:--")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                controls
            } else {
                timeline
                controls
                runtimeStatus
            }
        }
        .padding(16)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.secondary.opacity(0.12))
                if let artworkImage {
                    Image(nsImage: artworkImage).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("Media artwork")
                } else if artworkLoading {
                    ProgressView().controlSize(.small)
                } else if let fallback = AppleFallbackArtwork.data().flatMap(NSImage.init(data:)) {
                    Image(nsImage: fallback).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "waveform").font(.title).foregroundStyle(.secondary)
                }
            }
            .frame(width: 88, height: 88)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if let articleID = displayedArticleID,
                       let feedID = store.feedID(forArticleID: articleID) {
                        FeedIconSlot(feedID: feedID, store: store)
                    }
                    Text(PlayerPresentation.textOrFallback(previewing ? (previewItem?.feedTitle ?? "") : state.feedTitle,
                        fallback: String(localized: "Unknown Feed")))
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(PlayerPresentation.textOrFallback(previewing ? (previewItem?.title ?? "") : state.mediaTitle,
                    fallback: String(localized: "Untitled Media")))
                    .font(.headline).lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let duration = state.durationMs, duration > 0 {
                    Slider(value: sliderBinding, in: 0...Double(duration), onEditingChanged: finishScrubbing)
                        .accessibilityLabel("Playback timeline")
                        .accessibilityValue(PlayerPresentation.timelineAccessibilityValue(positionMs: currentPositionMs, durationMs: duration))
                HStack {
                    Text(PlayerPresentation.formatDuration(currentPositionMs))
                    Spacer()
                    Text(PlayerPresentation.formatDuration(duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            } else {
                Slider(value: .constant(0), in: 0...1)
                    .disabled(true)
                    .accessibilityLabel("Playback timeline unavailable")
                HStack {
                    Text(PlayerPresentation.formatDuration(currentPositionMs))
                    Spacer()
                    Text("--:--")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            controlButton("gobackward.15", label: "Back 15 seconds") { seek(by: -Int64(AppleMediaRemoteCommandPolicy.skipBackwardIntervalSeconds * 1_000)) }
                .disabled(previewing || state.loadedEnclosure == nil)
            controlButton(!previewing && state.status == .playing ? "pause.fill" : "play.fill", label: !previewing && state.status == .playing ? "Pause" : "Play") {
                if previewing {
                    if let enclosure = previewEnclosure { onPlayEnclosure(enclosure.enclosure) }
                } else {
                    togglePlayback()
                }
            }
                .disabled(state.isLoading || (previewing ? previewEnclosure == nil : state.loadedEnclosure == nil))
            controlButton("stop.fill", label: "Stop") {
                coordinator?.stop()
                onStop()
            }
                .disabled(previewing || state.loadedEnclosure == nil)
            controlButton("goforward.30", label: "Forward 30 seconds") { seek(by: Int64(AppleMediaRemoteCommandPolicy.skipForwardIntervalSeconds * 1_000)) }
                .disabled(previewing || state.loadedEnclosure == nil)
            controlButton("arrow.counterclockwise", label: "Restart") { restart() }
                .disabled(previewing || state.loadedEnclosure == nil)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var chapters: some View {
        if !displayedChapters.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Chapters").font(.headline)
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(displayedChapters.enumerated()), id: \.offset) { index, chapter in
                                chapterRow(chapter, index: index)
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                    .onChange(of: activeChapterIndex) { _, index in
                        guard let index else { return }
                        withAnimation { proxy.scrollTo(index, anchor: .center) }
                    }
                }
            }
        }
    }

    private func chapterRow(_ chapter: MediaChapter, index: Int) -> some View {
        let active = activeChapterIndex == index
        return Button {
            guard !previewing, let coordinator, let enclosure = state.loadedEnclosure else { return }
            coordinator.seek(toMs: chapter.startMs)
            if state.status != .playing { try? coordinator.play(enclosureID: enclosure.id) }
        } label: {
            HStack(spacing: 8) {
                Text(PlayerPresentation.formatDuration(chapter.startMs)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text(chapter.title.isEmpty ? String(localized: "Untitled Chapter") : chapter.title).lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .background(active ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .disabled(previewing)
        .accessibilityLabel(chapter.title.isEmpty ? String(localized: "Untitled Chapter") : chapter.title)
        .accessibilityValue(String(localized: "Starts at \(PlayerPresentation.formatDuration(chapter.startMs))") + (active ? String(localized: ", current chapter") : ""))
        .id(index)
    }

    @ViewBuilder private var audioSelection: some View {
        if let item = previewItem ?? displayedArticleID.flatMap({ id in
            store.listeningListItems.first(where: { $0.articleId == id })
        }), item.audioEnclosures.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Audio").font(.headline)
                ForEach(Array(item.audioEnclosures.enumerated()), id: \.offset) { index, audio in
                    HStack(spacing: 8) {
                        Text(ArticleAudioActions.enclosureLabel(audio.enclosure, index: index))
                            .font(.caption).lineLimit(2)
                        Spacer(minLength: 4)
                        Button { onPlayEnclosure(audio.enclosure) } label: {
                            Image(systemName: "play.fill")
                        }.buttonStyle(.borderless).help("Play")
                        switch ArticleAudioActions.downloadAction(audio.download) {
                        case .download, .retry:
                            Button { onDownload(item.articleId, audio.enclosure.id) } label: {
                                Image(systemName: "arrow.down.circle")
                            }.buttonStyle(.borderless).help("Download")
                        case .pending, .downloading:
                            Button { onCancel(item.articleId, audio.enclosure.id) } label: {
                                Image(systemName: "xmark.circle")
                            }.buttonStyle(.borderless).help("Cancel Download")
                        case .delete:
                            Button { onDelete(item.articleId, audio.enclosure.id) } label: {
                                Image(systemName: "trash")
                            }.buttonStyle(.borderless).help("Delete Download")
                        case .pendingDeletion:
                            Image(systemName: "clock").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var showNotes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showNotesExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(showNotesExpanded ? 90 : 0))
                    Label("Show Notes", systemImage: "doc.text")
                        .font(.headline)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showNotesExpanded {
                VStack(alignment: .leading, spacing: 10) {
                if isLoadingReaderDocument {
                    ProgressView("Loading Show Notes...").controlSize(.small)
                } else if let readerError {
                    Label(readerError, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { loadReaderDocument() }.buttonStyle(.bordered)
                } else if let readerDocument {
                    ReaderDocumentContent(document: readerDocument, openOriginal: openOriginal, contentPadding: 0)
                        .textSelection(.enabled)
                } else {
                    Text("Show Notes unavailable").font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { loadReaderDocument() }.buttonStyle(.bordered)
                }
                }
                .padding(.top, 8)
            }
        }
        .onChange(of: showNotesExpanded) { _, expanded in
            if expanded && readerDocument == nil && !isLoadingReaderDocument { loadReaderDocument() }
        }
    }

    private var advancedSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                advancedSettingsExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(advancedSettingsExpanded ? 90 : 0))
                    Text("Advanced Settings")
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if advancedSettingsExpanded {
                VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Playback Speed")
                        Spacer()
                        Text(String(format: "%.1f×", state.playbackRate)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: speedBinding, in: 0.5...3.0, step: 0.1)
                        .accessibilityLabel("Playback Speed")
                        .accessibilityValue(String(format: "%.1f×", state.playbackRate))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Sleep Timer", isOn: Binding(get: { sleepTimer.isEnabled }, set: sleepTimer.setEnabled))
                    Picker("Duration", selection: Binding(get: { sleepTimer.intervalMinutes }, set: sleepTimer.setInterval)) {
                        ForEach(MediaSleepTimer.intervalsMinutes, id: \.self) { minutes in
                            Text("\(minutes) minutes").tag(minutes)
                        }
                    }
                    .disabled(!sleepTimer.isEnabled)
                    if let remaining = sleepTimer.remainingSeconds {
                        Text("Stops in \(sleepTimerDescription(remaining))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                }
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder private var runtimeStatus: some View {
        if state.isLoading || state.isBuffering {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(state.isBuffering ? "Buffering..." : "Loading media...")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if state.errorMessage != nil {
            Label("Playback failed. Try again.", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var currentPositionMs: UInt64 {
        let position = isScrubbing ? UInt64(max(0, scrubPositionMs)) : state.positionMs
        return state.durationMs.map { min(position, $0) } ?? position
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { isScrubbing ? scrubPositionMs : Double(state.positionMs) },
            set: { scrubPositionMs = $0 }
        )
    }

    private var speedBinding: Binding<Double> {
        Binding(get: { state.playbackRate }, set: { coordinator?.setPlaybackRate($0) })
    }

    private var activeChapterIndex: Int? {
        previewing ? nil : PlayerPresentation.activeChapterIndex(positionMs: state.positionMs, chapters: displayedChapters)
    }

    private func sleepTimerDescription(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
    }

    private func resetShowNotes() {
        readerRequest += 1
        readerDocument = nil
        readerError = nil
        isLoadingReaderDocument = false
        if showNotesExpanded { loadReaderDocument() }
    }

    private func loadReaderDocument() {
        readerRequest += 1
        let request = readerRequest
        guard let articleID = displayedArticleID else {
            readerDocument = nil
            isLoadingReaderDocument = false
            readerError = nil
            return
        }
        readerDocument = nil
        readerError = nil
        isLoadingReaderDocument = true
        store.loadPlayerShowNotes(articleID: articleID) { result in
            guard request == readerRequest, displayedArticleID == articleID else { return }
            isLoadingReaderDocument = false
            switch result {
            case let .success(document): readerDocument = document
            case let .failure(error): readerError = NativeErrorPresentation.message(for: error)
            }
        }
    }

    private func openOriginal() {
        guard let articleID = displayedArticleID else { return }
        store.openOriginalArticle(articleID: articleID)
    }

    private func finishScrubbing(_ editing: Bool) {
        if editing {
            scrubPositionMs = Double(state.positionMs)
            isScrubbing = true
        } else {
            isScrubbing = false
            coordinator?.seek(toMs: UInt64(max(0, scrubPositionMs)))
        }
    }

    private func togglePlayback() {
        guard let coordinator, let enclosure = state.loadedEnclosure else { return }
        if state.status == .playing {
            coordinator.pause()
        } else {
            try? coordinator.play(enclosureID: enclosure.id)
        }
    }

    private func seek(by deltaMs: Int64) {
        guard let coordinator else { return }
        coordinator.seek(toMs: PlayerPresentation.seekTarget(positionMs: state.positionMs, deltaMs: deltaMs, durationMs: state.durationMs))
    }

    private func restart() {
        guard let coordinator, let enclosure = state.loadedEnclosure else { return }
        try? coordinator.restart(enclosureID: enclosure.id)
    }

    private func controlButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.title3) }
            .buttonStyle(.borderless)
            .help(label)
            .accessibilityLabel(label)
    }

}
