import Foundation
import SwiftUI
import UIKit

struct IOSMediaPlayerDownloadEnclosure: Identifiable {
    let enclosure: Enclosure
    let download: MediaDownload?
    var id: Int64 { enclosure.id }
}

enum IOSMediaPlayerLayoutMode: Equatable {
    case stacked
    case sideBySide
}

enum IOSMediaPlayerTransportControl: Hashable {
    case back15
    case playPause
    case forward30
    case stop

    static let ordered: [Self] = [
        .back15,
        .playPause,
        .forward30,
        .stop,
    ]
}

enum IOSMediaPlayerSecondaryAction: Hashable {
    case playbackRate
    case sleepTimer
    case downloads
    case restart
}

enum IOSMediaPlayerActionPlacement {
    static let persistentStatus: [IOSMediaPlayerSecondaryAction] = [
        .playbackRate,
        .sleepTimer,
    ]

    static let overflow: [IOSMediaPlayerSecondaryAction] = [
        .downloads,
        .restart,
    ]
}

enum IOSMediaPlayerWaitIndicatorPolicy {
    static let delay: Duration = .milliseconds(300)
    static let playPauseDiameter: CGFloat = 54
    static let ringDiameter: CGFloat = 72
    static let ringLineWidth: CGFloat = 3

    static func shouldRequestIndicator(
        isPreviewingInactiveItem: Bool,
        source: IOSMediaPlaybackSource?,
        isLoading: Bool,
        isBuffering: Bool
    ) -> Bool {
        !isPreviewingInactiveItem
            && source == .remote
            && (isLoading || isBuffering)
    }
}

private struct IOSMediaPlayerBufferingRing: View {
    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1)

            Circle()
                .trim(from: 0.06, to: 0.78)
                .stroke(
                    Color.accentColor,
                    style: StrokeStyle(
                        lineWidth: IOSMediaPlayerWaitIndicatorPolicy.ringLineWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(phase * 360))
        }
        .frame(
            width: IOSMediaPlayerWaitIndicatorPolicy.ringDiameter,
            height: IOSMediaPlayerWaitIndicatorPolicy.ringDiameter
        )
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

enum IOSMediaPlayerPreviewPresentation {
    static func isPreviewingInactiveItem(
        item: ListeningListItem?,
        loadedEnclosureID: Int64?
    ) -> Bool {
        guard let item else { return false }
        guard let loadedEnclosureID else { return true }
        return !item.audioEnclosures.contains(
            where: { $0.enclosure.id == loadedEnclosureID }
        )
    }

    static func preferredEnclosure(
        item: ListeningListItem?
    ) -> ListeningListEnclosure? {
        guard let item else { return nil }
        return IOSListeningListPresentation.selectedEnclosure(item)
            ?? item.audioEnclosures.first
    }

    static func positionMs(
        item: ListeningListItem?,
        loadedEnclosureID: Int64?,
        runtimePositionMs: UInt64
    ) -> UInt64 {
        guard isPreviewingInactiveItem(
            item: item,
            loadedEnclosureID: loadedEnclosureID
        ) else {
            return runtimePositionMs
        }
        return preferredEnclosure(item: item)?.playbackState?.positionMs ?? 0
    }
}

enum IOSMediaTimePresentation {
    static func label(_ milliseconds: UInt64) -> String {
        let totalSeconds = milliseconds / 1_000
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return String(
                format: "%llu:%02llu:%02llu",
                hours,
                minutes,
                seconds
            )
        }
        return String(
            format: "%llu:%02llu",
            totalMinutes,
            seconds
        )
    }
}

enum IOSMediaChapterListPresentation {
    static func title(_ chapter: MediaChapter, index: Int) -> String {
        MediaChapterPresentation.usesGeneratedTitle(chapter.title)
            ? String(localized: "Chapter \(index + 1)")
            : chapter.title
    }

    static func positionLabel(_ milliseconds: UInt64) -> String {
        IOSMediaTimePresentation.label(milliseconds)
    }

    static func activeIndex(
        positionMs: UInt64,
        chapters: [MediaChapter]
    ) -> Int? {
        chapters.indices.last { index in
            let chapter = chapters[index]
            let end = chapter.endMs
                ?? chapters.dropFirst(index + 1).first?.startMs
            return positionMs >= chapter.startMs
                && (end == nil || positionMs < end!)
        }
    }
}

struct IOSMediaPlayerChapterSummary: Equatable {
    let index: Int
    let count: Int
    let title: String

    static func resolve(
        positionMs: UInt64,
        chapters: [MediaChapter]
    ) -> Self? {
        guard let index = IOSMediaChapterListPresentation.activeIndex(
            positionMs: positionMs,
            chapters: chapters
        ) else {
            return nil
        }
        return .init(
            index: index,
            count: chapters.count,
            title: IOSMediaChapterListPresentation.title(
                chapters[index],
                index: index
            )
        )
    }
}

struct IOSMediaPlayerAudioSelection: Equatable {
    let enclosureID: Int64
    let index: Int
    let count: Int
    let title: String

    static func resolve(
        item: ListeningListItem,
        loadedEnclosureID: Int64?
    ) -> Self? {
        guard !item.audioEnclosures.isEmpty else { return nil }

        let selected: ListeningListEnclosure
        if let loadedEnclosureID,
           let loaded = item.audioEnclosures.first(
               where: { $0.enclosure.id == loadedEnclosureID }
           ) {
            selected = loaded
        } else {
            selected = IOSListeningListPresentation.selectedEnclosure(item)
                ?? item.audioEnclosures[0]
        }

        guard let index = item.audioEnclosures.firstIndex(
            where: { $0.enclosure.id == selected.enclosure.id }
        ) else {
            return nil
        }

        return .init(
            enclosureID: selected.enclosure.id,
            index: index,
            count: item.audioEnclosures.count,
            title: IOSListeningListPresentation.enclosureLabel(
                selected.enclosure,
                index: index
            )
        )
    }
}

enum IOSMediaPlayerLayoutPolicy {
    static func mode(
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?
    ) -> IOSMediaPlayerLayoutMode {
        if horizontalSizeClass == .regular || verticalSizeClass == .compact {
            return .sideBySide
        }
        return .stacked
    }
}

enum IOSMediaPlayerFoldLayoutPolicy {
    static func usesTabletopLayout(for divisionFrame: CGRect) -> Bool {
        divisionFrame.width > divisionFrame.height
            && divisionFrame.width > 0
            && divisionFrame.height > 0
    }
}

struct IOSMediaPlayerView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var playbackState: IOSMediaPlaybackPresentationState
    @ObservedObject var transferState: IOSMediaTransferPresentationState
    @ObservedObject var sleepTimer: IOSMediaSleepTimer
    let playbackCoordinator: IOSMediaPlaybackCoordinator
    let item: ListeningListItem?
    let downloadEnclosures: [IOSMediaPlayerDownloadEnclosure]
    let onDownloadAction: (
        _ enclosureID: Int64,
        _ action: IOSListeningListPresentation.DownloadAction
    ) -> Void
    let feedIconFeedID: Int64?
    let feedIconTitle: String
    let feedIconState: (_ feedID: Int64, _ variant: FeedIconVariant) -> IOSFeedIconPresentationState
    let onRequestFeedIcon: (_ feedID: Int64, _ variant: FeedIconVariant) -> Void
    let showNotesDocument: ReaderDocument?
    let showNotesIsLoading: Bool
    let showNotesErrorMessage: String?
    let onSelectEnclosure: (Int64) -> Void
    let onShowNotes: () -> Void
    let onDismiss: () -> Void

    @State private var seekPosition: Double = 0
    @State private var isSeeking = false
    @State private var showNotesExpanded = false
    @State private var chapterListPresented = false
    @State private var chapterListSnapshot: [MediaChapter] = []
    @State private var chapterInitialIndex: Int?
    @State private var ratePickerPresented = false
    @State private var sleepTimerPresented = false
    @State private var artworkImage: UIImage?
    @State private var artworkIsLoading = false
    @State private var showPlaybackWaitIndicator = false
    @State private var previewChapters: [MediaChapter] = []

    private var layoutMode: IOSMediaPlayerLayoutMode {
        IOSMediaPlayerLayoutPolicy.mode(
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass
        )
    }

    private var previewEnclosure: ListeningListEnclosure? {
        IOSMediaPlayerPreviewPresentation.preferredEnclosure(item: item)
    }

    private var isPreviewingInactiveItem: Bool {
        IOSMediaPlayerPreviewPresentation.isPreviewingInactiveItem(
            item: item,
            loadedEnclosureID: playbackState.loadedEnclosure?.id
        )
    }

    private var displayedTitle: String {
        if isPreviewingInactiveItem, let item {
            return IOSListeningListPresentation.textOrFallback(
                item.title,
                fallback: String(localized: "Audio")
            )
        }
        return playbackState.mediaTitle.isEmpty
            ? String(localized: "Audio")
            : playbackState.mediaTitle
    }

    private var displayedFeedTitle: String {
        if isPreviewingInactiveItem, let item {
            return IOSListeningListPresentation.textOrFallback(
                item.feedTitle,
                fallback: String(localized: "Unknown Feed")
            )
        }
        return playbackState.feedTitle
    }

    private var displayedPositionMs: UInt64 {
        IOSMediaPlayerPreviewPresentation.positionMs(
            item: item,
            loadedEnclosureID: playbackState.loadedEnclosure?.id,
            runtimePositionMs: playbackState.positionMs
        )
    }

    private var displayedDurationMs: UInt64? {
        if isPreviewingInactiveItem {
            return previewEnclosure?.durationMs
                ?? previewEnclosure?.playbackState?.durationMs
        }
        return playbackState.durationMs
    }

    private var displayedIsPlaying: Bool {
        !isPreviewingInactiveItem && playbackState.status == .playing
    }

    var body: some View {
        NavigationStack {
            playerContent
            .navigationTitle("Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done", action: onDismiss)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if hasOverflowActions {
                        moreMenu
                    }
                }
            }
        }
        .onAppear {
            seekPosition = Double(displayedPositionMs)
        }
        .task(id: artworkTaskKey) {
            await loadArtwork()
        }
        .task(id: playbackWaitTaskKey) {
            showPlaybackWaitIndicator = false
            guard shouldRequestPlaybackWaitIndicator else { return }
            do {
                try await Task.sleep(
                    for: IOSMediaPlayerWaitIndicatorPolicy.delay
                )
            } catch {
                return
            }
            guard shouldRequestPlaybackWaitIndicator else { return }
            showPlaybackWaitIndicator = true
        }
        .task(id: chapterPreviewTaskKey) {
            await loadPreviewChapters()
        }
    }

    @ViewBuilder
    private var playerContent: some View {
#if FLUX_HAS_VERTICAL_TOOLBAR_API
        if #available(iOS 27.1, *) {
            GeometryReader { proxy in
                let divisions = proxy.reservedRegions(kind: .division)
                if let division = divisions.first?.frame,
                   IOSMediaPlayerFoldLayoutPolicy.usesTabletopLayout(
                       for: division
                   ) {
                    tabletopPlayerContent(
                        size: proxy.size,
                        divisionFrame: division
                    )
                } else {
                    standardPlayerContent
                }
            }
        } else {
            standardPlayerContent
        }
#else
        standardPlayerContent
#endif
    }

    @ViewBuilder
    private var standardPlayerContent: some View {
        switch layoutMode {
        case .stacked:
            ScrollView {
                VStack(spacing: 24) {
                    artwork
                        .frame(maxWidth: 300)
                    controls
                }
                .frame(maxWidth: 560)
                .padding(24)
                .frame(maxWidth: .infinity)
            }

        case .sideBySide:
            ScrollView {
                HStack(alignment: .top, spacing: 32) {
                    artwork
                        .frame(maxWidth: 360)

                    controls
                        .frame(maxWidth: 520)
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

#if FLUX_HAS_VERTICAL_TOOLBAR_API
    @available(iOS 27.1, *)
    private func tabletopPlayerContent(
        size: CGSize,
        divisionFrame: CGRect
    ) -> some View {
        let topHeight = max(0, divisionFrame.minY)
        let bottomHeight = max(0, size.height - divisionFrame.maxY)

        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    artwork
                        .frame(maxWidth: min(260, max(160, topHeight * 0.58)))
                    header
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
            .frame(height: topHeight)

            Color.clear
                .frame(height: divisionFrame.height)
                .accessibilityHidden(true)

            ScrollView {
                playbackControls
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: bottomHeight)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }
#endif

    private var controls: some View {
        VStack(spacing: 24) {
            header
            playbackControls
        }
    }

    private var playbackControls: some View {
        VStack(spacing: 24) {
            if let item,
               item.audioEnclosures.count > 1,
               let audioSelection = IOSMediaPlayerAudioSelection.resolve(
                   item: item,
                   loadedEnclosureID: playbackState.loadedEnclosure?.id
               ) {
                audioSelectionRow(item, selection: audioSelection)
            }

            if let duration = displayedDurationMs, duration > 0 {
                VStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: {
                                isSeeking
                                    ? seekPosition
                                    : Double(displayedPositionMs)
                            },
                            set: { seekPosition = $0 }
                        ),
                        in: 0...Double(duration),
                        onEditingChanged: { editing in
                            isSeeking = editing
                            if editing {
                                seekPosition = Double(displayedPositionMs)
                            } else {
                                if !isPreviewingInactiveItem {
                                    playbackCoordinator.seek(
                                        toMs: UInt64(max(0, seekPosition))
                                    )
                                }
                            }
                        }
                    )

                    HStack {
                        Text(timeLabel(displayedPositionMs))
                        Spacer()
                        Text(timeLabel(duration))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }

            transportControls

            persistentStatusControls

            if let chapterSummary {
                chapterSummaryRow(chapterSummary)
            }

            showNotesSection

            if !isPreviewingInactiveItem,
               let error = playbackState.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var transportControls: some View {
        HStack(spacing: 24) {
            ForEach(
                IOSMediaPlayerTransportControl.ordered,
                id: \.self
            ) { control in
                transportButton(control)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func transportButton(
        _ control: IOSMediaPlayerTransportControl
    ) -> some View {
        switch control {
        case .back15:
            Button {
                if !isPreviewingInactiveItem {
                    playbackCoordinator.skip(bySeconds: -15)
                }
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.title2)
            }
            .accessibilityLabel(String(localized: "Back 15 seconds"))
            .disabled(isPreviewingInactiveItem)

        case .playPause:
            Button {
                togglePlayback()
            } label: {
                ZStack {
                    Image(
                        systemName: displayedIsPlaying
                            ? "pause.circle.fill"
                            : "play.circle.fill"
                    )
                    .font(
                        .system(
                            size: IOSMediaPlayerWaitIndicatorPolicy
                                .playPauseDiameter
                        )
                    )

                    if showPlaybackWaitIndicator {
                        IOSMediaPlayerBufferingRing()
                    }
                }
                .frame(
                    width: IOSMediaPlayerWaitIndicatorPolicy.ringDiameter,
                    height: IOSMediaPlayerWaitIndicatorPolicy.ringDiameter
                )
            }
            .accessibilityLabel(
                displayedIsPlaying
                    ? String(localized: "Pause")
                    : String(localized: "Play")
            )

        case .forward30:
            Button {
                if !isPreviewingInactiveItem {
                    playbackCoordinator.skip(bySeconds: 30)
                }
            } label: {
                Image(systemName: "goforward.30")
                    .font(.title2)
            }
            .accessibilityLabel(String(localized: "Forward 30 seconds"))
            .disabled(isPreviewingInactiveItem)

        case .stop:
            Button {
                if !isPreviewingInactiveItem {
                    playbackCoordinator.stop()
                }
            } label: {
                Image(systemName: "stop.circle")
                    .font(.title2)
            }
            .accessibilityLabel(String(localized: "Stop"))
            .disabled(isPreviewingInactiveItem)
        }
    }

    private var persistentStatusControls: some View {
        HStack(spacing: 10) {
            ForEach(
                IOSMediaPlayerActionPlacement.persistentStatus,
                id: \.self
            ) { action in
                persistentStatusControl(action)
            }
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func persistentStatusControl(
        _ action: IOSMediaPlayerSecondaryAction
    ) -> some View {
        switch action {
        case .playbackRate:
            rateMenu
                .frame(maxWidth: .infinity)
        case .sleepTimer:
            sleepTimerButton
                .frame(maxWidth: .infinity)
        case .downloads, .restart:
            EmptyView()
        }
    }

    private var displayedChapters: [MediaChapter] {
        isPreviewingInactiveItem ? previewChapters : playbackState.chapters
    }

    private var chapterSummary: IOSMediaPlayerChapterSummary? {
        IOSMediaPlayerChapterSummary.resolve(
            positionMs: displayedPositionMs,
            chapters: displayedChapters
        )
    }

    private func chapterSummaryRow(
        _ summary: IOSMediaPlayerChapterSummary
    ) -> some View {
        Button {
            presentChapterList()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        String(
                            localized:
                                "Chapter \(summary.index + 1) of \(summary.count)"
                        )
                    )
                    .font(.subheadline.weight(.semibold))

                    Text(summary.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Chapters"))
        .popover(
            isPresented: $chapterListPresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            chapterListContent
        }
    }

    private var showNotesSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showNotesExpanded.toggle()
                }
                if showNotesExpanded,
                   showNotesDocument == nil,
                   !showNotesIsLoading {
                    onShowNotes()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(Color.accentColor)
                    Text("Show Notes")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Image(
                        systemName: showNotesExpanded
                            ? "chevron.up"
                            : "chevron.down"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(
                showNotesExpanded
                    ? String(localized: "Expanded")
                    : String(localized: "Collapsed")
            )

            if showNotesExpanded {
                Divider()
                    .padding(.horizontal, 12)

                Group {
                    if showNotesIsLoading {
                        ProgressView("Loading article…")
                            .frame(maxWidth: .infinity)
                            .padding(20)
                    } else if let showNotesErrorMessage {
                        VStack(spacing: 10) {
                            Label(
                                "Unable to load article",
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.subheadline.weight(.semibold))

                            Text(showNotesErrorMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Button("Retry") {
                                onShowNotes()
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(20)
                    } else if let showNotesDocument {
                        ReaderDocumentContent(
                            document: showNotesDocument,
                            openOriginal: nil,
                            contentPadding: 12
                        )
                        .textSelection(.enabled)
                    } else {
                        ProgressView("Loading article…")
                            .frame(maxWidth: .infinity)
                            .padding(20)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var shouldRequestPlaybackWaitIndicator: Bool {
        IOSMediaPlayerWaitIndicatorPolicy.shouldRequestIndicator(
            isPreviewingInactiveItem: isPreviewingInactiveItem,
            source: playbackState.playbackSource,
            isLoading: playbackState.isLoading,
            isBuffering: playbackState.isBuffering
        )
    }

    private var playbackWaitTaskKey: String {
        [
            playbackState.playbackSource == .local ? "local" :
                playbackState.playbackSource == .remote ? "remote" : "none",
            playbackState.isLoading ? "loading" : "idle",
            playbackState.isBuffering ? "buffering" : "steady",
            isPreviewingInactiveItem ? "preview" : "active",
        ].joined(separator: ":")
    }

    private func audioSelectionRow(
        _ item: ListeningListItem,
        selection: IOSMediaPlayerAudioSelection
    ) -> some View {
        Menu {
            ForEach(
                Array(item.audioEnclosures.enumerated()),
                id: \.element.enclosure.id
            ) { index, enclosure in
                Button {
                    onSelectEnclosure(enclosure.enclosure.id)
                } label: {
                    if enclosure.enclosure.id == selection.enclosureID {
                        Label(
                            IOSListeningListPresentation.enclosureLabel(
                                enclosure.enclosure,
                                index: index
                            ),
                            systemImage: "checkmark"
                        )
                    } else {
                        Text(
                            IOSListeningListPresentation.enclosureLabel(
                                enclosure.enclosure,
                                index: index
                            )
                        )
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        String(
                            localized:
                                "Audio \(selection.index + 1) of \(selection.count)"
                        )
                    )
                    .font(.subheadline.weight(.semibold))

                    Text(selection.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Choose audio"))
    }


    private var artwork: some View {
        Group {
            if let artworkImage {
                Image(uiImage: artworkImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .accessibilityLabel(String(localized: "Media artwork"))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.secondary.opacity(0.12))
                    if artworkIsLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "waveform")
                            .font(.system(size: 54))
                            .foregroundStyle(.secondary)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(displayedTitle)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            if !displayedFeedTitle.isEmpty {
                HStack(spacing: 6) {
                    if let feedIconFeedID {
                        FeedIconView(
                            feedID: feedIconFeedID,
                            title: feedIconTitle,
                            state: feedIconState(
                                feedIconFeedID,
                                feedIconVariant
                            ),
                            onRequest: {
                                onRequestFeedIcon(
                                    feedIconFeedID,
                                    feedIconVariant
                                )
                            },
                            size: 18
                        )
                    }
                    Text(displayedFeedTitle)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var feedIconVariant: FeedIconVariant {
        IOSFeedIconPresentation.variant(
            isDark: colorScheme == .dark
        )
    }

    private var rateMenu: some View {
        Button {
            ratePickerPresented = true
        } label: {
            Label(
                rateLabel(playbackState.playbackRate),
                systemImage: "speedometer"
            )
            .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(String(localized: "Playback speed"))
        .disabled(isPreviewingInactiveItem)
        .popover(
            isPresented: $ratePickerPresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            VStack(spacing: 18) {
                Text("Playback speed")
                    .font(.headline)

                HStack(spacing: 20) {
                    Button {
                        adjustPlaybackRate(by: -0.1)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                    }
                    .disabled(playbackState.playbackRate <= 0.5)

                    Text(rateLabel(playbackState.playbackRate))
                        .font(.title2.monospacedDigit())
                        .frame(minWidth: 72)

                    Button {
                        adjustPlaybackRate(by: 0.1)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .disabled(playbackState.playbackRate >= 3.0)
                }

                HStack(spacing: 8) {
                    ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Button(rateLabel(rate)) {
                            playbackCoordinator.setPlaybackRate(rate)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(20)
            .frame(minWidth: 320)
            .presentationCompactAdaptation(.sheet)
            .presentationDetents([.height(220)])
        }
    }

    private var chapterListContent: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(
                        Array(chapterListSnapshot.enumerated()),
                        id: \.offset
                    ) { index, chapter in
                        let isActive = IOSMediaChapterListPresentation
                            .activeIndex(
                                positionMs: playbackState.positionMs,
                                chapters: chapterListSnapshot
                            ) == index
                        Button {
                            playbackCoordinator.seek(toMs: chapter.startMs)
                            chapterListPresented = false
                        } label: {
                            HStack(
                                alignment: .firstTextBaseline,
                                spacing: 12
                            ) {
                                Image(
                                    systemName: isActive
                                        ? "play.fill"
                                        : "circle.fill"
                                )
                                .font(.caption2)
                                .foregroundStyle(
                                    isActive
                                        ? Color.accentColor
                                        : Color.clear
                                )
                                .frame(width: 12)

                                Text(
                                    IOSMediaChapterListPresentation
                                        .positionLabel(chapter.startMs)
                                )
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 52, alignment: .leading)

                                Text(
                                    IOSMediaChapterListPresentation.title(
                                        chapter,
                                        index: index
                                    )
                                )
                                .fontWeight(
                                    isActive ? .semibold : .regular
                                )
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(
                                    horizontal: false,
                                    vertical: true
                                )
                            }
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                            .padding(.vertical, 3)
                            .background(
                                isActive
                                    ? Color.accentColor.opacity(0.10)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isPreviewingInactiveItem)
                        .id(index)
                    }
                }
                .listStyle(.plain)
                .onAppear {
                    if let chapterInitialIndex {
                        DispatchQueue.main.async {
                            proxy.scrollTo(
                                chapterInitialIndex,
                                anchor: .center
                            )
                        }
                    }
                }
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        chapterListPresented = false
                    }
                }
            }
        }
        .frame(
            minWidth: 340,
            idealWidth: 440,
            maxWidth: 520,
            minHeight: 320,
            idealHeight: 480
        )
        .presentationCompactAdaptation(.sheet)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var sleepTimerButton: some View {
        Button {
            sleepTimerPresented = true
        } label: {
            Label(
                sleepTimer.isEnabled
                    ? sleepTimerStatusLabel
                    : String(localized: "Sleep Timer"),
                systemImage: sleepTimer.isEnabled
                    ? "moon.zzz.fill"
                    : "moon.zzz"
            )
            .frame(maxWidth: .infinity)
        }
        .popover(
            isPresented: $sleepTimerPresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(
                    "Sleep Timer",
                    isOn: Binding(
                        get: { sleepTimer.isEnabled },
                        set: sleepTimer.setEnabled
                    )
                )

                Picker(
                    "Duration",
                    selection: Binding(
                        get: { sleepTimer.intervalMinutes },
                        set: sleepTimer.setInterval
                    )
                ) {
                    ForEach(
                        IOSMediaSleepTimer.intervalsMinutes,
                        id: \.self
                    ) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .disabled(!sleepTimer.isEnabled)

                if let remaining = sleepTimer.remainingSeconds {
                    Text(
                        "\(String(localized: "Stops in")) "
                            + sleepTimerRemainingLabel(remaining)
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(minWidth: 300)
            .presentationCompactAdaptation(.sheet)
            .presentationDetents([.height(260)])
        }
    }

    private var downloadOverflowMenu: some View {
        Menu {
            ForEach(downloadEnclosures) { entry in
                let action = IOSListeningListPresentation.downloadAction(
                    download: entry.download,
                    runtime: transferState.runtime(
                        for: entry.enclosure.id
                    )
                )
                Button {
                    onDownloadAction(entry.enclosure.id, action)
                } label: {
                    downloadLabel(
                        action,
                        enclosureID: entry.enclosure.id
                    )
                }
                .disabled(
                    action == .cancelling
                        || action == .pendingDeletion
                )
            }
        } label: {
            Label("Downloads", systemImage: "arrow.down.circle")
        }
    }

    @ViewBuilder
    private func downloadLabel(
        _ action: IOSListeningListPresentation.DownloadAction,
        enclosureID: Int64
    ) -> some View {
        switch action {
        case .download:
            Label("Download", systemImage: "arrow.down.circle")
        case .pending:
            Label("Cancel Download", systemImage: "xmark.circle")
        case .downloading:
            if let fraction = transferState.runtime(
                for: enclosureID
            )?.fraction {
                Label(
                    "\(Int((fraction * 100).rounded()))% downloaded",
                    systemImage: "xmark.circle"
                )
            } else {
                Label("Cancel Download", systemImage: "xmark.circle")
            }
        case .cancelling:
            Label("Cancelling Download", systemImage: "clock")
        case .delete:
            Label("Delete Download", systemImage: "trash")
        case .pendingDeletion:
            Label("Deletion Pending", systemImage: "clock")
        case .retry:
            Label("Retry Download", systemImage: "arrow.clockwise")
        }
    }

    private var hasOverflowActions: Bool {
        !downloadEnclosures.isEmpty
            || (!isPreviewingInactiveItem
                && playbackState.loadedEnclosure != nil)
    }

    private var moreMenu: some View {
        Menu {
            ForEach(
                IOSMediaPlayerActionPlacement.overflow,
                id: \.self
            ) { action in
                overflowAction(action)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(String(localized: "More"))
    }

    @ViewBuilder
    private func overflowAction(
        _ action: IOSMediaPlayerSecondaryAction
    ) -> some View {
        switch action {
        case .downloads:
            if !downloadEnclosures.isEmpty {
                downloadOverflowMenu
            }

        case .restart:
            if !isPreviewingInactiveItem,
               let enclosureID = playbackState.loadedEnclosure?.id {
                Button {
                    Task {
                        try? await playbackCoordinator.restart(
                            enclosureID: enclosureID
                        )
                    }
                } label: {
                    Label("Restart", systemImage: "arrow.counterclockwise")
                }
            }

        case .playbackRate, .sleepTimer:
            EmptyView()
        }
    }

    private func presentChapterList() {
        chapterListSnapshot = displayedChapters
        chapterInitialIndex = IOSMediaChapterListPresentation.activeIndex(
            positionMs: displayedPositionMs,
            chapters: displayedChapters
        )
        chapterListPresented = true
    }

    private var chapterPreviewTaskKey: String {
        guard isPreviewingInactiveItem,
              let enclosureID = previewEnclosure?.enclosure.id else {
            return "active"
        }
        return "preview:\(enclosureID)"
    }

    @MainActor
    private func loadPreviewChapters() async {
        guard isPreviewingInactiveItem,
              let enclosureID = previewEnclosure?.enclosure.id else {
            previewChapters = []
            return
        }
        let chapters = await playbackCoordinator.previewChapters(
            enclosureID: enclosureID
        )
        guard !Task.isCancelled,
              isPreviewingInactiveItem,
              previewEnclosure?.enclosure.id == enclosureID else {
            return
        }
        previewChapters = chapters
    }

    private var artworkTaskKey: String {
        if isPreviewingInactiveItem {
            return "preview:\(previewEnclosure?.enclosure.id ?? -1)"
        }
        switch playbackState.artworkSource {
        case let .some(.localReference(reference)):
            return "local:\(reference)"
        case let .some(.remoteUrl(url)):
            return "remote:\(url)"
        case .none:
            return "none"
        }
    }

    @MainActor
    private func loadArtwork() async {
        artworkImage = nil
        let source: MediaArtworkSource?
        if isPreviewingInactiveItem,
           let enclosureID = previewEnclosure?.enclosure.id {
            source = await playbackCoordinator.previewArtworkSource(
                enclosureID: enclosureID
            )
        } else {
            source = playbackState.artworkSource
        }
        guard let source else {
            artworkIsLoading = false
            return
        }

        artworkIsLoading = true
        let data = await playbackCoordinator.artwork(source: source)
        guard !Task.isCancelled else { return }
        artworkImage = data.flatMap(UIImage.init(data:))
        artworkIsLoading = false
    }

    private func adjustPlaybackRate(by delta: Double) {
        playbackCoordinator.setPlaybackRate(
            playbackState.playbackRate + delta
        )
    }

    private var sleepTimerStatusLabel: String {
        guard let remaining = sleepTimer.remainingSeconds else {
            return String(localized: "Sleep Timer")
        }
        return "\(String(localized: "Stops in")) \(sleepTimerRemainingLabel(remaining))"
    }

    private func sleepTimerRemainingLabel(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0
            ? "\(minutes)m"
            : "\(minutes)m \(remainder)s"
    }

    private func togglePlayback() {
        if isPreviewingInactiveItem {
            guard let enclosureID = previewEnclosure?.enclosure.id else { return }
            onSelectEnclosure(enclosureID)
            return
        }

        guard let enclosureID = playbackState.loadedEnclosure?.id else { return }
        if playbackState.status == .playing {
            playbackCoordinator.pause()
        } else {
            Task {
                try? await playbackCoordinator.play(
                    enclosureID: enclosureID
                )
            }
        }
    }

    private func timeLabel(_ milliseconds: UInt64) -> String {
        IOSMediaTimePresentation.label(milliseconds)
    }

    private func rateLabel(_ rate: Double) -> String {
        rate == floor(rate)
            ? "\(Int(rate))×"
            : String(format: "%.2g×", rate)
    }
}
