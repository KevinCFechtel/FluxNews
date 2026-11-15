import AVFoundation
import AppKit
import Foundation
import OSLog
import Combine

enum MediaPlaybackPaths {
    static var mediaRootURL: URL {
        // Internal downloads must remain in the app's sandbox container.
        // The pre-release developer's former ~/Movies/FluxNews data is deliberately
        // not migrated when enabling the sandbox.
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FluxNews", isDirectory: true)
            .appendingPathComponent("Media", isDirectory: true)
    }
}

@MainActor
protocol MediaPlaybackCore: AnyObject {
    func preparePlayback(enclosureId: Int64) throws -> PlaybackPreparation
    func checkpointPlayback(enclosureId: Int64, positionMs: UInt64, durationMs: UInt64?) throws
    func playbackCompleted(enclosureId: Int64, durationMs: UInt64?) throws
    func restartPlayback(enclosureId: Int64) throws
    func observeMediaDuration(enclosureId: Int64, durationMs: UInt64) throws
    func mediaChapters(enclosureId: Int64) throws -> [MediaChapter]
    func mediaDownload(enclosureId: Int64) throws -> MediaDownload
    func mediaArtwork(reference: String) throws -> Data?
}

@MainActor
protocol NativePlaybackEngine: AnyObject {
    var currentPositionMs: UInt64 { get }
    var durationMs: UInt64? { get }
    var isPlaying: Bool { get }
    var rate: Double { get set }
    var onEnded: (@MainActor () -> Void)? { get set }
    var onDuration: (@MainActor (UInt64) -> Void)? { get set }
    var onPosition: (@MainActor (UInt64) -> Void)? { get set }
    var onPlaybackStateChanged: (@MainActor (Bool) -> Void)? { get set }
    var onLoadingChanged: (@MainActor (Bool) -> Void)? { get set }
    var onBufferingChanged: (@MainActor (Bool) -> Void)? { get set }
    var onError: (@MainActor (String) -> Void)? { get set }
    func load(url: URL, startAtMs: UInt64)
    func play()
    func pause()
    func unload()
    func seek(toMs: UInt64)
}

@MainActor
final class AVFoundationPlaybackEngine: NativePlaybackEngine {
    private let player = AVPlayer()
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var durationObservation: NSKeyValueObservation?
    private var readinessObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private weak var observedItem: AVPlayerItem?
    private(set) var currentPositionMs: UInt64 = 0
    private(set) var durationMs: UInt64?
    private(set) var isPlaying = false
    var rate: Double = 1.0 {
        didSet { if isPlaying { player.rate = Float(rate) } }
    }
    var onEnded: (@MainActor () -> Void)?
    var onDuration: (@MainActor (UInt64) -> Void)?
    var onPosition: (@MainActor (UInt64) -> Void)?
    var onPlaybackStateChanged: (@MainActor (Bool) -> Void)?
    var onLoadingChanged: (@MainActor (Bool) -> Void)?
    var onBufferingChanged: (@MainActor (Bool) -> Void)?
    var onError: (@MainActor (String) -> Void)?

    init() {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let isPlaying = player.timeControlStatus == .playing
                self.isPlaying = isPlaying
                self.onPlaybackStateChanged?(isPlaying)
                self.onBufferingChanged?(player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
            }
        }
    }

    func load(url: URL, startAtMs: UInt64) {
        let item = AVPlayerItem(url: url)
        removeObservers()
        observedItem = item
        currentPositionMs = 0
        durationMs = nil
        isPlaying = false
        onLoadingChanged?(true)
        readinessObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak observedItem = item] item, _ in
            Task { @MainActor [weak self, weak observedItem] in
                guard let self, let observedItem, self.observedItem === observedItem else { return }
                if item.status == .readyToPlay {
                    self.onLoadingChanged?(false)
                } else if item.status == .failed {
                    self.onLoadingChanged?(false)
                    let error = item.error
                    let url = (item.asset as? AVURLAsset)?.url.absoluteString ?? "unknown"
                    Logger(subsystem: "dev.kevincfechtel.fluxNews", category: "media").error("AVPlayerItem failed; media URL and errors are not logged publicly")
                    self.onError?(error?.localizedDescription ?? "Media playback failed.")
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak item] _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.observedItem === item else { return }
                self.isPlaying = false
                self.currentPositionMs = self.durationMs ?? self.currentPositionMs
                self.onEnded?()
            }
        }
        player.replaceCurrentItem(with: item)
        observeDuration(for: item)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 1_000),
            queue: .main
        ) { [weak self, weak item] time in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.observedItem === item else { return }
                self.updatePosition(time)
            }
        }
        seek(toMs: startAtMs)
    }

    func play() { player.playImmediately(atRate: Float(rate)) }
    func pause() { player.pause(); updatePosition(); isPlaying = false }
    func unload() {
        player.pause()
        removeObservers()
        player.replaceCurrentItem(with: nil)
        currentPositionMs = 0
        durationMs = nil
        isPlaying = false
    }

    func seek(toMs: UInt64) {
        let seconds = CMTime(seconds: Double(toMs) / 1_000, preferredTimescale: 1_000)
        player.seek(to: seconds) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updatePosition() }
        }
    }

    private func observeDuration(for item: AVPlayerItem) {
        durationObservation = item.observe(\AVPlayerItem.duration, options: [.initial, .new]) { [weak self, weak observedItem = item] _, _ in
            guard let observedItem else { return }
            Task { @MainActor [weak self, weak observedItem] in
                guard let self, let observedItem, self.observedItem === observedItem else { return }
                self.updateDuration(observedItem.duration)
            }
        }
        updateDuration(item.duration)
    }

    private func updateDuration(_ time: CMTime) {
        guard let duration = Self.milliseconds(time, requiresPositive: true), durationMs != duration else { return }
        durationMs = duration
        onLoadingChanged?(false)
        onDuration?(duration)
    }

    private func updatePosition() { updatePosition(player.currentTime()) }

    private func updatePosition(_ time: CMTime) {
        guard let position = Self.milliseconds(time, requiresPositive: false) else { return }
        currentPositionMs = position
        onPosition?(position)
    }

    static func milliseconds(_ time: CMTime, requiresPositive: Bool) -> UInt64? {
        guard time.isValid, time.isNumeric else { return nil }
        let seconds = time.seconds
        guard seconds.isFinite, seconds >= 0, (!requiresPositive || seconds > 0) else { return nil }
        let milliseconds = seconds * 1_000
        guard milliseconds <= Double(UInt64.max) else { return nil }
        return UInt64(milliseconds)
    }

    private func removeObservers() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        durationObservation = nil
        readinessObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        observedItem = nil
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        timeControlObservation = nil
    }
}

@MainActor
final class MediaPlaybackCoordinator {
    private let core: MediaPlaybackCore
    private let engine: NativePlaybackEngine
    private let checkpointInterval: TimeInterval
    private var checkpointTimer: Timer?
    private var activeEnclosureID: Int64?
    private var completionSent = false
    private var preparedDurationMs: UInt64?
    private var lastObservedDurationMs: UInt64?
    private var preparedStatus: PlaybackStatus = .notStarted
    let presentationState: MediaPlaybackPresentationState
    let sleepTimer: MediaSleepTimer
    var onPlaybackUseChanged: (() -> Void)?

    init(core: MediaPlaybackCore, engine: NativePlaybackEngine? = nil, checkpointInterval: TimeInterval = 20, presentationState: MediaPlaybackPresentationState? = nil) {
        self.core = core
        self.checkpointInterval = checkpointInterval
        self.presentationState = presentationState ?? MediaPlaybackPresentationState()
        self.sleepTimer = MediaSleepTimer()
        let engine = engine ?? AVFoundationPlaybackEngine()
        self.engine = engine
        engine.onEnded = { @MainActor [weak self] in self?.handleNaturalEnd() }
        engine.onDuration = { @MainActor [weak self] duration in self?.handleDuration(duration) }
        engine.onPosition = { @MainActor [weak self] position in self?.presentationState.positionMs = position }
        engine.onPlaybackStateChanged = { @MainActor [weak self] isPlaying in
            guard let self, isPlaying else { return }
            self.presentationState.status = .playing
            self.startCheckpointTimer()
        }
        engine.onLoadingChanged = { @MainActor [weak self] loading in self?.presentationState.isLoading = loading }
        engine.onBufferingChanged = { @MainActor [weak self] buffering in self?.presentationState.isBuffering = buffering }
        engine.onError = { @MainActor [weak self] message in self?.presentationState.errorMessage = message }
        sleepTimer.onFire = { @MainActor [weak self] in self?.sleepTimerFired() }
    }

    func prepare(enclosureID: Int64) throws -> PlaybackPreparation {
        try prepare(enclosureID: enclosureID, checkpointCurrent: true)
    }

    private func prepare(enclosureID: Int64, checkpointCurrent: Bool) throws -> PlaybackPreparation {
        try stopCurrentIfNeeded(checkpoint: checkpointCurrent)
        let preparation = try core.preparePlayback(enclosureId: enclosureID)
        activeEnclosureID = enclosureID
        onPlaybackUseChanged?()
        completionSent = false
        preparedDurationMs = preparation.durationMs ?? preparation.playbackState.durationMs
        lastObservedDurationMs = preparedDurationMs
        preparedStatus = preparation.playbackState.status
        presentationState.loadedEnclosure = preparation.enclosure
        presentationState.feedTitle = preparation.feedTitle
        presentationState.mediaTitle = preparation.articleTitle
        presentationState.artworkSource = preparation.artworkSource
        presentationState.positionMs = preparation.playbackState.positionMs
        presentationState.durationMs = preparedDurationMs
        presentationState.chapters = (try? core.mediaChapters(enclosureId: enclosureID)) ?? []
        presentationState.status = .paused
        presentationState.errorMessage = nil
        let source: URL
        if let localFile = preparation.localFile,
           let localURL = Self.safeLocalURL(localFile, under: MediaPlaybackPaths.mediaRootURL),
           FileManager.default.isReadableFile(atPath: localURL.path) {
            source = localURL
        } else if let remoteURL = URL(string: preparation.enclosure.url), remoteURL.scheme == "http" || remoteURL.scheme == "https" {
            source = remoteURL
        } else {
            throw MediaPlaybackError.invalidMediaURL
        }
        let startAt = preparation.playbackState.status == .inProgress ? preparation.playbackState.positionMs : 0
        engine.load(url: source, startAtMs: startAt)
        engine.rate = presentationState.playbackRate
        return preparation
    }

    func play(enclosureID: Int64) throws {
        if activeEnclosureID != enclosureID { _ = try prepare(enclosureID: enclosureID) }
        guard activeEnclosureID == enclosureID else { return }
        guard preparedStatus != .completed else { return }
        engine.play()
        if engine.isPlaying {
            presentationState.status = .playing
            startCheckpointTimer()
        }
    }

    func pause() { engine.pause(); checkpoint(); stopCheckpointTimer(); presentationState.positionMs = engine.currentPositionMs; presentationState.status = .paused }
    func stop() {
        guard let activeEnclosureID else { return }
        releaseForDownloadDeletion(enclosureID: activeEnclosureID)
    }
    func applicationDidResignActive() { checkpoint() }
    func applicationDidBecomeActive() { sleepTimer.evaluate() }
    func applicationWillTerminate() { checkpoint(); stopCheckpointTimer(); engine.unload() }

    func seek(toMs: UInt64) {
        engine.seek(toMs: toMs)
        presentationState.positionMs = toMs
        checkpoint()
    }

    func skip(bySeconds seconds: Double) {
        guard seconds.isFinite else { return }
        let current = Double(engine.currentPositionMs) / 1_000
        let target = max(0, current + seconds)
        let bounded = presentationState.durationMs.map { min(target, Double($0) / 1_000) } ?? target
        seek(toMs: UInt64(max(0, bounded * 1_000).rounded()))
    }

    func restart(enclosureID: Int64) throws {
        let wasPlaying = engine.isPlaying
        let wasStopped = presentationState.status == .stopped
        let wasCompleted = preparedStatus == .completed
        try core.restartPlayback(enclosureId: enclosureID)
        _ = try prepare(enclosureID: enclosureID, checkpointCurrent: false)
        if wasPlaying || wasCompleted {
            try play(enclosureID: enclosureID)
        } else if wasStopped {
            presentationState.status = .stopped
        }
    }

    func chapters() throws -> [MediaChapter] {
        guard let activeEnclosureID else { return [] }
        let chapters = try core.mediaChapters(enclosureId: activeEnclosureID)
        presentationState.chapters = chapters
        return chapters
    }

    func artwork(source: MediaArtworkSource) async -> Data? {
        switch source {
        case let .localReference(reference):
            do {
                guard let data = try core.mediaArtwork(reference: reference), NSImage(data: data) != nil else {
                    return nil
                }
                return data
            } catch {
                return nil
            }
        case let .remoteUrl(urlString):
            guard let url = URL(string: urlString),
                  url.scheme == "http" || url.scheme == "https"
            else { return nil }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode),
                      NSImage(data: data) != nil
                else { return nil }
                return data
            } catch {
                return nil
            }
        }
    }
    /// Release a loaded media item after explicit deletion or Stop.
    /// Pause retains the AVPlayer item so playback can resume immediately.
    /// The playback checkpoint is persisted before AVPlayer releases the file.
    func releaseForDownloadDeletion(enclosureID: Int64, checkpointBeforeUnloading: Bool = true) {
        guard activeEnclosureID == enclosureID else { return }
        engine.pause()
        // Completion is already persisted after natural end; a fresh checkpoint
        // here could overwrite the completed position/status in Core.
        if checkpointBeforeUnloading { checkpoint() }
        stopCheckpointTimer()
        engine.unload()
        activeEnclosureID = nil
        completionSent = false
        preparedDurationMs = nil
        lastObservedDurationMs = nil
        preparedStatus = .notStarted
        presentationState.loadedEnclosure = nil
        presentationState.feedTitle = ""
        presentationState.mediaTitle = ""
        presentationState.artworkSource = nil
        presentationState.chapters = []
        presentationState.positionMs = 0
        presentationState.durationMs = nil
        presentationState.status = .stopped
        presentationState.errorMessage = nil
        presentationState.isLoading = false
        presentationState.isBuffering = false
        onPlaybackUseChanged?()
    }

    func isUsing(enclosureID: Int64) -> Bool { activeEnclosureID == enclosureID }

    func setPlaybackRate(_ rate: Double) {
        guard rate.isFinite else { return }
        let clamped = min(3.0, max(0.5, rate))
        presentationState.playbackRate = (clamped * 10).rounded() / 10
        engine.rate = presentationState.playbackRate
    }

    private func stopCurrentIfNeeded(checkpoint: Bool = true) throws {
        guard activeEnclosureID != nil else { return }
        if checkpoint { self.checkpoint() }
        engine.pause()
        stopCheckpointTimer()
    }

    private func checkpoint() {
        guard let activeEnclosureID else { return }
        do {
            try core.checkpointPlayback(enclosureId: activeEnclosureID, positionMs: engine.currentPositionMs, durationMs: engine.durationMs ?? preparedDurationMs)
        } catch {
            Logger(subsystem: "dev.kevincfechtel.fluxNews", category: "media").error("media checkpoint failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func handleNaturalEnd() {
        guard let activeEnclosureID, !completionSent else { return }
        do {
            try core.playbackCompleted(enclosureId: activeEnclosureID, durationMs: engine.durationMs ?? preparedDurationMs)
        } catch {
            presentationState.status = .paused
            Logger(subsystem: "dev.kevincfechtel.fluxNews", category: "media").error("media completion failed: \(error.localizedDescription, privacy: .private)")
            return
        }
        completionSent = true
        preparedStatus = .completed
        presentationState.status = .paused
        presentationState.positionMs = engine.currentPositionMs
        stopCheckpointTimer()
        // Core requests automatic deletion on completed playback when the
        // corresponding policy is enabled. AVPlayer must let go of its local
        // file before transfer reconciliation can remove it.
        if (try? core.mediaDownload(enclosureId: activeEnclosureID))?.state == .deleteRequested {
            releaseForDownloadDeletion(enclosureID: activeEnclosureID, checkpointBeforeUnloading: false)
        } else {
            onPlaybackUseChanged?()
        }
    }

    private func handleDuration(_ duration: UInt64) {
        guard lastObservedDurationMs != duration else { return }
        lastObservedDurationMs = duration
        preparedDurationMs = duration
        presentationState.durationMs = duration
        guard let activeEnclosureID else { return }
        do { try core.observeMediaDuration(enclosureId: activeEnclosureID, durationMs: duration) }
        catch { Logger(subsystem: "dev.kevincfechtel.fluxNews", category: "media").error("media duration observation failed: \(error.localizedDescription, privacy: .private)") }
    }

    private func startCheckpointTimer() {
        guard checkpointTimer == nil else { return }
        checkpointTimer = Timer.scheduledTimer(withTimeInterval: checkpointInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.engine.isPlaying else { return }
                self.checkpoint()
            }
        }
    }

    private func stopCheckpointTimer() { checkpointTimer?.invalidate(); checkpointTimer = nil }

    private func sleepTimerFired() {
        pause()
    }

    private static func safeLocalURL(_ reference: String, under root: URL) -> URL? {
        guard !reference.hasPrefix("/"), !reference.contains("..") else { return nil }
        let url = root.appendingPathComponent(reference).standardizedFileURL
        return url.path == root.standardizedFileURL.path || url.path.hasPrefix(root.standardizedFileURL.path + "/") ? url : nil
    }
}

@MainActor
final class MediaPlaybackPresentationState: ObservableObject {
    @Published fileprivate(set) var loadedEnclosure: Enclosure?
    @Published fileprivate(set) var feedTitle = ""
    @Published fileprivate(set) var mediaTitle = ""
    @Published fileprivate(set) var artworkSource: MediaArtworkSource?
    @Published fileprivate(set) var chapters: [MediaChapter] = []
    @Published fileprivate(set) var status: MediaPlaybackPresentationStatus = .stopped
    @Published fileprivate(set) var positionMs: UInt64 = 0
    @Published fileprivate(set) var durationMs: UInt64?
    @Published fileprivate(set) var isLoading = false
    @Published fileprivate(set) var isBuffering = false
    @Published fileprivate(set) var errorMessage: String?
    @Published fileprivate(set) var playbackRate = 1.0
}

@MainActor
final class MediaSleepTimer: ObservableObject {
    static let intervalsMinutes = Array(stride(from: 30, through: 180, by: 15))

    @Published private(set) var isEnabled = false
    @Published private(set) var intervalMinutes = 30
    @Published private(set) var remainingSeconds: Int?

    private var deadline: Date?
    private var timer: Timer?
    private let now: () -> Date
    var onFire: (() -> Void)?

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    deinit { timer?.invalidate() }

    func setEnabled(_ enabled: Bool) {
        if enabled { start(intervalMinutes: intervalMinutes) } else { disable() }
    }

    func setInterval(_ minutes: Int) {
        guard Self.intervalsMinutes.contains(minutes) else { return }
        intervalMinutes = minutes
        if isEnabled { start(intervalMinutes: minutes) }
    }

    func evaluate(at date: Date? = nil) {
        guard isEnabled, let deadline else { return }
        let current = date ?? now()
        if current >= deadline {
            timer?.invalidate()
            timer = nil
            self.deadline = nil
            isEnabled = false
            remainingSeconds = nil
            onFire?()
        } else {
            remainingSeconds = max(1, Int(ceil(deadline.timeIntervalSince(current))))
        }
    }

    private func start(intervalMinutes: Int) {
        timer?.invalidate()
        let deadline = now().addingTimeInterval(TimeInterval(intervalMinutes * 60))
        self.deadline = deadline
        isEnabled = true
        remainingSeconds = intervalMinutes * 60
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.evaluate() }
        }
    }

    private func disable() {
        timer?.invalidate()
        timer = nil
        deadline = nil
        isEnabled = false
        remainingSeconds = nil
    }
}

enum MediaPlaybackError: LocalizedError {
    case invalidMediaURL
    var errorDescription: String? { "The media URL is not playable." }
}

extension Flux: MediaPlaybackCore {}
