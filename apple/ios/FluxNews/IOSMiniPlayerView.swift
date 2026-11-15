import SwiftUI
import UIKit

enum IOSMiniPlayerPlacement: Equatable {
    case portraitBottomDock
    case compactTopBar
    case sidebarFooter
}

enum IOSMiniPlayerPlacementPolicy {
    static func placement(
        for chromeMode: IOSArticleListChromeMode
    ) -> IOSMiniPlayerPlacement {
        switch chromeMode {
        case .compactPortrait:
            .portraitBottomDock
        case .compactLandscape, .persistentSplitCollapsed:
            .compactTopBar
        case .persistentSplit:
            .sidebarFooter
        }
    }
}

enum IOSCompactPortraitBottomInsetPresentation: Equatable {
    case none
    case standaloneMiniPlayer
    case combinedMiniPlayerAndActions
}

enum IOSCompactPortraitBottomInsetPolicy {
    static func presentation(
        chromeMode: IOSArticleListChromeMode,
        actionPlacement: IOSArticleListActionPlacement,
        miniPlayerIsVisible: Bool
    ) -> IOSCompactPortraitBottomInsetPresentation {
        guard chromeMode == .compactPortrait, miniPlayerIsVisible else {
            return .none
        }

        switch actionPlacement {
        case .topBarTrailing:
            // Vertical toolbar actions remain in native navigation chrome. The
            // player occupies the bottom inset independently.
            return .standaloneMiniPlayer
        case .bottomBar:
            // Ordinary compact portrait keeps its established combined bottom
            // dock when the system does not offer a vertical toolbar edge.
            return .combinedMiniPlayerAndActions
        case .floatingTopTrailing:
            return .none
        }
    }
}

enum IOSMiniPlayerPresentation {
    static func isVisible(
        loadedEnclosureID: Int64?,
        status: MediaPlaybackPresentationStatus
    ) -> Bool {
        loadedEnclosureID != nil && status != .stopped
    }

    static func elapsedDurationLabel(
        positionMs: UInt64,
        durationMs: UInt64?
    ) -> String? {
        guard let durationMs, durationMs > 0 else { return nil }
        let positionMs = min(positionMs, durationMs)
        return "\(IOSMediaTimePresentation.label(positionMs)) / \(IOSMediaTimePresentation.label(durationMs))"
    }
}

enum IOSMiniPlayerStyle: Equatable {
    case portraitDock
    case compactTopBar
    case expandedLandscapeTopBar
    case regularFloating
    case regularToolbar
    case sidebarFooter
}

enum IOSMiniPlayerMetrics {
    static let portraitArtworkSize: CGFloat = 38
    static let topBarArtworkSize: CGFloat = 26
    static let sidebarArtworkSize: CGFloat = 34
    static let topBarExpandedWidth: CGFloat = 270
    static let topBarCompactWidth: CGFloat = 68
    static let regularFloatingArtworkSize: CGFloat = 34
    static let regularFloatingWidth: CGFloat = 320
    static let dockCornerRadius: CGFloat = 26
    static let sidebarCornerRadius: CGFloat = 18
}

struct IOSMiniPlayerView: View {
    @ObservedObject var playbackState: IOSMediaPlaybackPresentationState
    let playbackCoordinator: IOSMediaPlaybackCoordinator
    let style: IOSMiniPlayerStyle
    let onOpen: () -> Void

    @State private var artworkImage: UIImage?

    private var isPlaying: Bool {
        playbackState.status == .playing
    }

    private var displayTitle: String {
        let mediaTitle = playbackState.mediaTitle.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !mediaTitle.isEmpty {
            return mediaTitle
        }

        let feedTitle = playbackState.feedTitle.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return feedTitle.isEmpty ? String(localized: "Audio") : feedTitle
    }

    private var displayFeedTitle: String? {
        let value = playbackState.feedTitle.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !value.isEmpty, value != displayTitle else { return nil }
        return value
    }

    private var progressFraction: Double? {
        guard let duration = playbackState.durationMs, duration > 0 else {
            return nil
        }
        return min(
            max(Double(playbackState.positionMs) / Double(duration), 0),
            1
        )
    }

    private var artworkTaskKey: String {
        switch playbackState.artworkSource {
        case let .some(.localReference(reference)):
            "local:\(reference)"
        case let .some(.remoteUrl(url)):
            "remote:\(url)"
        case .none:
            "none"
        }
    }

    var body: some View {
        Group {
            switch style {
            case .portraitDock:
                portraitDockContent
            case .compactTopBar:
                compactTopBarContent
            case .expandedLandscapeTopBar:
                // Force the title-bearing width in folded landscape. Letting
                // ViewThatFits negotiate inside a native toolbar item caused
                // premature fallback to the 68pt icon-only player.
                compactTopBarCandidate(showsTitle: true)
                    .frame(width: IOSMiniPlayerMetrics.topBarExpandedWidth)
                    .fixedSize(horizontal: true, vertical: false)
            case .regularFloating:
                regularFloatingContent
            case .regularToolbar:
                regularToolbarContent
            case .sidebarFooter:
                sidebarFooterContent
            }
        }
        .task(id: artworkTaskKey) {
            await loadArtwork()
        }
    }

    private var portraitDockContent: some View {
        VStack(spacing: 5) {
            HStack(spacing: 10) {
                openButton(
                    artworkSize: IOSMiniPlayerMetrics.portraitArtworkSize,
                    showsFeedTitle: true
                )

                Button {
                    playbackCoordinator.skip(bySeconds: -15)
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.body.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Back 15 seconds"))

                playPauseButton(diameter: 34)
            }

            progressWithTime
        }
    }

    private var compactTopBarContent: some View {
        ViewThatFits(in: .horizontal) {
            compactTopBarCandidate(showsTitle: true)
                .frame(width: IOSMiniPlayerMetrics.topBarExpandedWidth)

            compactTopBarCandidate(showsTitle: false)
                .frame(width: IOSMiniPlayerMetrics.topBarCompactWidth)
        }
    }

    private func compactTopBarCandidate(
        showsTitle: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Button(action: onOpen) {
                HStack(spacing: 6) {
                    artwork(size: IOSMiniPlayerMetrics.topBarArtworkSize)

                    if showsTitle {
                        Text(displayTitle)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(String(localized: "Now Playing")), \(displayTitle)"
            )

            playPauseButton(diameter: 28)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        // The native iPhone landscape toolbar already supplies its own glass
        // capsule. Drawing another capsule inside it creates a double shell.
        .background {
            if style != .expandedLandscapeTopBar {
                IOSMiniPlayerCapsuleBackground()
            }
        }
    }

    // Native toolbar glass has a system-controlled height. Keep the artwork,
    // labels, time and progress inside a single compact row rather than trying
    // to enlarge the toolbar with a minimum-height frame.
    private var regularToolbarContent: some View {
        VStack(spacing: 3) {
            HStack(spacing: 8) {
                Button(action: onOpen) {
                    HStack(spacing: 8) {
                        artwork(size: 30)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(displayTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            HStack(spacing: 6) {
                                if let displayFeedTitle {
                                    Text(displayFeedTitle)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }

                                Spacer(minLength: 0)

                                if let timeLabel = IOSMiniPlayerPresentation.elapsedDurationLabel(
                                    positionMs: playbackState.positionMs,
                                    durationMs: playbackState.durationMs
                                ) {
                                    Text(timeLabel)
                                        .monospacedDigit()
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(String(localized: "Now Playing")), \(displayTitle)"
                )

                playPauseButton(diameter: 30)
            }

            if let progressFraction {
                ProgressView(value: progressFraction)
                    .progressViewStyle(.linear)
                    .tint(Color.accentColor)
                    .controlSize(.mini)
                    .accessibilityLabel(String(localized: "Playback progress"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(width: IOSMiniPlayerMetrics.regularFloatingWidth)
    }

    private var regularFloatingContent: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                openButton(
                    artworkSize: IOSMiniPlayerMetrics.regularFloatingArtworkSize,
                    showsFeedTitle: true
                )
                playPauseButton(diameter: 32)
            }

            progressWithTime
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: IOSMiniPlayerMetrics.regularFloatingWidth)
        .background {
            IOSMiniPlayerCapsuleBackground()
        }
    }

    private var sidebarFooterContent: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                openButton(
                    artworkSize: IOSMiniPlayerMetrics.sidebarArtworkSize,
                    showsFeedTitle: true
                )
                playPauseButton(diameter: 32)
            }

            progressWithTime
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            IOSMiniPlayerRoundedBackground(
                cornerRadius: IOSMiniPlayerMetrics.sidebarCornerRadius
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func openButton(
        artworkSize: CGFloat,
        showsFeedTitle: Bool
    ) -> some View {
        Button(action: onOpen) {
            HStack(spacing: 9) {
                artwork(size: artworkSize)

                VStack(alignment: .leading, spacing: 1) {
                    Text(displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if showsFeedTitle, let displayFeedTitle {
                        Text(displayFeedTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(String(localized: "Now Playing")), \(displayTitle)"
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func artwork(size: CGFloat) -> some View {
        Group {
            if let artworkImage {
                Image(uiImage: artworkImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.12)
                    Image(systemName: "waveform")
                        .font(.system(size: max(12, size * 0.42)))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(
            RoundedRectangle(
                cornerRadius: max(6, size * 0.22),
                style: .continuous
            )
        )
        .accessibilityHidden(true)
    }

    private func playPauseButton(
        diameter: CGFloat
    ) -> some View {
        Button {
            togglePlayback()
        } label: {
            Group {
                if playbackState.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(
                        systemName: isPlaying
                            ? "pause.fill"
                            : "play.fill"
                    )
                }
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isPlaying
                ? String(localized: "Pause")
                : String(localized: "Play")
        )
    }

    @ViewBuilder
    private var progressWithTime: some View {
        if let progressFraction,
           let timeLabel = IOSMiniPlayerPresentation.elapsedDurationLabel(
               positionMs: playbackState.positionMs,
               durationMs: playbackState.durationMs
           ) {
            HStack(spacing: 8) {
                ProgressView(value: progressFraction)
                    .progressViewStyle(.linear)
                    .tint(Color.accentColor)
                    .frame(maxWidth: .infinity)

                Text(timeLabel)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Playback progress"))
            .accessibilityValue(timeLabel)
        }
    }

    private func togglePlayback() {
        guard let enclosureID = playbackState.loadedEnclosure?.id else {
            return
        }

        if isPlaying {
            playbackCoordinator.pause()
            return
        }

        Task {
            try? await playbackCoordinator.play(
                enclosureID: enclosureID
            )
        }
    }

    @MainActor
    private func loadArtwork() async {
        artworkImage = nil
        guard let source = playbackState.artworkSource else {
            return
        }
        let data = await playbackCoordinator.artwork(source: source)
        guard !Task.isCancelled,
              playbackState.artworkSource == source else {
            return
        }
        artworkImage = data.flatMap(UIImage.init(data:))
    }
}

struct IOSStandalonePortraitMiniPlayerDock: View {
    @ObservedObject var playbackState: IOSMediaPlaybackPresentationState
    let playbackCoordinator: IOSMediaPlaybackCoordinator
    let onOpenPlayer: () -> Void

    var body: some View {
        IOSMiniPlayerView(
            playbackState: playbackState,
            playbackCoordinator: playbackCoordinator,
            style: .portraitDock,
            onOpen: onOpenPlayer
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            IOSMiniPlayerCapsuleBackground()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

struct IOSArticleListBottomDock<Actions: View>: View {
    @ObservedObject var playbackState: IOSMediaPlaybackPresentationState
    let playbackCoordinator: IOSMediaPlaybackCoordinator
    let onOpenPlayer: () -> Void
    @ViewBuilder let actions: () -> Actions

    private var showsMiniPlayer: Bool {
        IOSMiniPlayerPresentation.isVisible(
            loadedEnclosureID: playbackState.loadedEnclosure?.id,
            status: playbackState.status
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsMiniPlayer {
                IOSMiniPlayerView(
                    playbackState: playbackState,
                    playbackCoordinator: playbackCoordinator,
                    style: .portraitDock,
                    onOpen: onOpenPlayer
                )
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)

                Divider()
                    .padding(.horizontal, 10)
            }

            HStack(spacing: 22) {
                Spacer(minLength: 0)
                actions()
                    .labelStyle(.iconOnly)
                    // Use the adaptive primary color for portrait dock actions
                    // instead of the app accent or a fixed black.
                    .tint(.primary)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 8)
        }
        .background {
            IOSMiniPlayerRoundedBackground(
                cornerRadius: IOSMiniPlayerMetrics.dockCornerRadius
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

private struct IOSMiniPlayerCapsuleBackground: View {
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    @ViewBuilder
    var body: some View {
        if reduceTransparency {
            Capsule()
                .fill(Color(uiColor: .secondarySystemBackground))
        } else if #available(iOS 26.0, *) {
            IOSMiniPlayerGlassEffectView()
                .clipShape(Capsule())
        } else {
            Capsule()
                .fill(.regularMaterial)
        }
    }
}

private struct IOSMiniPlayerRoundedBackground: View {
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    @ViewBuilder
    var body: some View {
        if reduceTransparency {
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
            .fill(Color(uiColor: .secondarySystemBackground))
        } else if #available(iOS 26.0, *) {
            IOSMiniPlayerGlassEffectView()
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                )
        } else {
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
            .fill(.regularMaterial)
        }
    }
}

@available(iOS 26.0, *)
private struct IOSMiniPlayerGlassEffectView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(
            effect: UIGlassEffect(style: .regular)
        )
    }

    func updateUIView(
        _ uiView: UIVisualEffectView,
        context: Context
    ) {
        uiView.effect = UIGlassEffect(style: .regular)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UIVisualEffectView,
        context: Context
    ) -> CGSize? {
        let size = proposal.replacingUnspecifiedDimensions(by: .zero)
        return CGSize(
            width: size.width.isFinite ? size.width : 0,
            height: size.height.isFinite ? size.height : 0
        )
    }
}
