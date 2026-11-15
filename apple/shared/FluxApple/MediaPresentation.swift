import Foundation

enum MediaPlaybackPresentationStatus: Equatable {
    case stopped
    case paused
    case playing
}

enum AppleMediaRemoteCommand: Equatable {
    case play
    case pause
    case stop
    case toggle
    case skipBackward
    case skipForward
    case seek(seconds: Double)
}

enum AppleMediaRemoteCommandPolicy {
    static let skipBackwardIntervalSeconds: Double = 15
    static let skipForwardIntervalSeconds: Double = 30
}

enum AppleFallbackArtwork {
    static func data(bundle: Bundle = .main) -> Data? {
        guard let url = bundle.url(
            forResource: "FallbackArtwork",
            withExtension: "png"
        ) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }
}

struct AppleNowPlayingProjection: Equatable {
    let title: String
    let sourceTitle: String
    let durationSeconds: Double?
    let elapsedSeconds: Double
    let effectivePlaybackRate: Double
    let defaultPlaybackRate: Double
    let playbackState: MediaPlaybackPresentationStatus
    let assetURL: URL?
    let artworkData: Data?

    static func make(
        title: String,
        sourceTitle: String,
        enclosureURL: String,
        durationMs: UInt64?,
        positionMs: UInt64,
        status: MediaPlaybackPresentationStatus,
        playbackRate: Double,
        errorMessage: String?,
        artworkData: Data? = nil,
        fallbackArtworkData: Data? = AppleFallbackArtwork.data()
    ) -> AppleNowPlayingProjection {
        let duration = durationMs.flatMap { milliseconds in
            let seconds = Double(milliseconds) / 1_000
            return seconds.isFinite && seconds > 0 ? seconds : nil
        }
        let rawElapsed = Double(positionMs) / 1_000
        let elapsed = rawElapsed.isFinite && rawElapsed >= 0
            ? min(rawElapsed, duration ?? rawElapsed)
            : 0
        let configuredRate = playbackRate.isFinite
            ? min(3.0, max(0.5, playbackRate))
            : 1.0
        let isPlaying = status == .playing && errorMessage == nil
        let assetURL = URL(string: enclosureURL).flatMap { url in
            url.scheme == "http" || url.scheme == "https" ? url : nil
        }

        return AppleNowPlayingProjection(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "FluxNews Audio"
                : title,
            sourceTitle: sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "FluxNews"
                : sourceTitle,
            durationSeconds: duration,
            elapsedSeconds: elapsed,
            effectivePlaybackRate: isPlaying ? configuredRate : 0,
            defaultPlaybackRate: configuredRate,
            playbackState: isPlaying ? .playing : status,
            assetURL: assetURL,
            artworkData: artworkData ?? fallbackArtworkData
        )
    }
}

enum MediaTransferRuntimePhase: Equatable {
    case starting
    case transferring
    case cancelling
}

struct MediaTransferRuntime: Equatable {
    let enclosureID: Int64
    let bytesReceived: Int64
    let expectedBytes: Int64?
    let phase: MediaTransferRuntimePhase

    var fraction: Double? {
        guard bytesReceived >= 0, let expectedBytes, expectedBytes > 0 else { return nil }
        return min(max(Double(bytesReceived) / Double(expectedBytes), 0), 1)
    }
}


enum MediaChapterPresentation {
    static func usesGeneratedTitle(_ title: String) -> Bool {
        let normalized = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }

        guard !normalized.isEmpty else { return true }

        for prefix in ["cp", "ch", "chp", "chap", "chapter"] {
            guard normalized.hasPrefix(prefix) else { continue }
            let suffix = normalized.dropFirst(prefix.count)
            if !suffix.isEmpty && suffix.allSatisfy(\.isNumber) {
                return true
            }
        }
        return false
    }
}
