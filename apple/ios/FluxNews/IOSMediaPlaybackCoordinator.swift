import AVFoundation
import Combine
import Foundation

enum IOSMediaPlaybackError: LocalizedError {
    case coreUnavailable
    case sessionUnavailable
    case invalidMediaURL
    case audioSession

    var errorDescription: String? {
        switch self {
        case .coreUnavailable:
            return String(localized: "The media Core is unavailable.")
        case .sessionUnavailable:
            return String(localized: "The media Core session is unavailable.")
        case .invalidMediaURL:
            return String(localized: "The media URL is not playable.")
        case .audioSession:
            return String(localized: "The audio session could not be activated.")
        }
    }
}

@MainActor
protocol IOSNativePlaybackEngine: AnyObject {
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
final class IOSAVPlayerPlaybackEngine: IOSNativePlaybackEngine {
    private let player = AVPlayer()
    private let logger = IOSAppLogger(category: "media-playback")
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var durationObservation: NSKeyValueObservation?
    private var readinessObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private weak var observedItem: AVPlayerItem?
    private var currentSourceIsLocal = false

    private(set) var currentPositionMs: UInt64 = 0
    private(set) var durationMs: UInt64?
    private(set) var isPlaying = false

    var rate: Double = 1.0 {
        didSet {
            if isPlaying { player.rate = Float(rate) }
        }
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
                self.onBufferingChanged?(!self.currentSourceIsLocal && player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
            }
        }
    }

    func load(url: URL, startAtMs: UInt64) {
        logger.info("AVPlayer load scheme=\(url.scheme ?? "none") local=\(url.isFileURL) startMs=\(startAtMs)")
        let item = AVPlayerItem(url: url)
        removeItemObservers()
        observedItem = item
        currentSourceIsLocal = url.isFileURL
        currentPositionMs = 0
        durationMs = nil
        isPlaying = false
        onLoadingChanged?(!currentSourceIsLocal)
        onBufferingChanged?(false)

        readinessObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak observedItem = item] item, _ in
            Task { @MainActor [weak self, weak observedItem] in
                guard let self, let observedItem, self.observedItem === observedItem else { return }
                switch item.status {
                case .readyToPlay:
                    self.logger.info("AVPlayer item ready")
                    if !self.currentSourceIsLocal { self.onLoadingChanged?(false) }
                case .failed:
                    let message = item.error?.localizedDescription ?? "Media playback failed."
                    self.logger.error("AVPlayer item failed local=\(self.currentSourceIsLocal) domain=\((item.error as NSError?)?.domain ?? "none") code=\((item.error as NSError?)?.code ?? 0) message=\(message)")
                    self.onLoadingChanged?(false)
                    self.onError?(message)
                default: break
                }
            }
        }

        durationObservation = item.observe(\AVPlayerItem.duration, options: [.initial, .new]) { [weak self, weak observedItem = item] _, _ in
            guard let observedItem else { return }
            Task { @MainActor [weak self, weak observedItem] in
                guard let self, let observedItem, self.observedItem === observedItem,
                      let duration = Self.milliseconds(observedItem.duration, requiresPositive: true),
                      self.durationMs != duration else { return }
                self.durationMs = duration
                if !self.currentSourceIsLocal { self.onLoadingChanged?(false) }
                self.onDuration?(duration)
            }
        }

        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self, weak item] _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.observedItem === item else { return }
                self.isPlaying = false
                self.currentPositionMs = self.durationMs ?? self.currentPositionMs
                self.onEnded?()
            }
        }

        player.replaceCurrentItem(with: item)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 1_000), queue: .main) { [weak self, weak item] time in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.observedItem === item,
                      let position = Self.milliseconds(time, requiresPositive: false) else { return }
                self.currentPositionMs = position
                self.onPosition?(position)
            }
        }
        seek(toMs: startAtMs)
    }

    func play() {
        logger.info("AVPlayer play rate=\(self.rate)")
        player.playImmediately(atRate: Float(rate))
    }

    func pause() {
        player.pause(); updatePosition(); isPlaying = false; onPlaybackStateChanged?(false)
    }

    func unload() {
        player.pause(); removeItemObservers(); player.replaceCurrentItem(with: nil)
        currentPositionMs = 0; durationMs = nil; isPlaying = false; currentSourceIsLocal = false
        onLoadingChanged?(false); onBufferingChanged?(false)
    }

    func seek(toMs: UInt64) {
        let time = CMTime(seconds: Double(toMs) / 1_000, preferredTimescale: 1_000)
        player.seek(to: time) { [weak self] _ in Task { @MainActor [weak self] in self?.updatePosition() } }
    }

    static func milliseconds(_ time: CMTime, requiresPositive: Bool) -> UInt64? {
        guard time.isValid, time.isNumeric else { return nil }
        let seconds = time.seconds
        guard seconds.isFinite, seconds >= 0, (!requiresPositive || seconds > 0) else { return nil }
        let milliseconds = seconds * 1_000
        guard milliseconds <= Double(UInt64.max) else { return nil }
        return UInt64(milliseconds)
    }

    private func updatePosition() {
        guard let position = Self.milliseconds(player.currentTime(), requiresPositive: false) else { return }
        currentPositionMs = position; onPosition?(position)
    }

    private func removeItemObservers() {
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        durationObservation = nil; readinessObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver); self.endObserver = nil }
        observedItem = nil
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeControlObservation = nil
    }
}

@MainActor
protocol IOSMediaAudioSessionManaging: AnyObject {
    var onInterruptionBegan: (() -> Void)? { get set }
    var onInterruptionEndedShouldResume: ((Bool) -> Void)? { get set }
    var onOldDeviceUnavailable: (() -> Void)? { get set }
    func activate() async throws
    func deactivateIfIdle()
}

enum IOSMediaAudioSessionConfiguration {
    static let category: AVAudioSession.Category = .playback
    static let mode: AVAudioSession.Mode = .spokenAudio
    static let options: AVAudioSession.CategoryOptions = []
}

@MainActor
final class IOSMediaAudioSessionCoordinator: IOSMediaAudioSessionManaging {
    var onInterruptionBegan: (() -> Void)?
    var onInterruptionEndedShouldResume: ((Bool) -> Void)?
    var onOldDeviceUnavailable: (() -> Void)?
    private let session: AVAudioSession
    private let notificationCenter: NotificationCenter
    private let activationQueue = DispatchQueue(label: "dev.kevincfechtel.fluxNews.audio-session")
    private let logger = IOSAppLogger(category: "media-playback")
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?

    init(session: AVAudioSession = .sharedInstance(), notificationCenter: NotificationCenter = .default) {
        self.session = session; self.notificationCenter = notificationCenter
        interruptionObserver = notificationCenter.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] notification in
            Task { @MainActor [weak self] in self?.handleInterruption(notification) }
        }
        routeObserver = notificationCenter.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] notification in
            Task { @MainActor [weak self] in self?.handleRouteChange(notification) }
        }
    }

    func activate() async throws {
        let session = session; let activationQueue = activationQueue; let logger = logger
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            activationQueue.async {
                do { try session.setCategory(IOSMediaAudioSessionConfiguration.category, mode: IOSMediaAudioSessionConfiguration.mode, options: IOSMediaAudioSessionConfiguration.options) }
                catch {
                    let nsError = error as NSError
                    logger.error("AVAudioSession setCategory failed domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription)")
                    continuation.resume(throwing: IOSMediaPlaybackError.audioSession); return
                }
                do { try session.setActive(true); continuation.resume(returning: ()) }
                catch {
                    let nsError = error as NSError
                    logger.error("AVAudioSession setActive failed domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription)")
                    continuation.resume(throwing: IOSMediaPlaybackError.audioSession)
                }
            }
        }
    }

    func deactivateIfIdle() {
        let session = session; let logger = logger
        activationQueue.async {
            do {
                try session.setActive(false, options: [.notifyOthersOnDeactivation])
            } catch {
                let nsError = error as NSError
                logger.error("AVAudioSession deactivation failed domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription)")
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began: onInterruptionBegan?()
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            onInterruptionEndedShouldResume?(AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume))
        @unknown default: break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason), reason == .oldDeviceUnavailable else { return }
        onOldDeviceUnavailable?()
    }

    deinit {
        if let interruptionObserver { notificationCenter.removeObserver(interruptionObserver) }
        if let routeObserver { notificationCenter.removeObserver(routeObserver) }
    }
}

@MainActor
protocol IOSMediaPlaybackCoreAccessing: AnyObject {
    func attach(to core: Flux); func detach()
    func preparePlayback(enclosureID: Int64) async throws -> PlaybackPreparation
    func playbackState(enclosureID: Int64) async -> PlaybackState?
    func chapters(enclosureID: Int64) async throws -> [MediaChapter]
    func artworkSource(enclosureID: Int64) async -> MediaArtworkSource?
    func artwork(reference: String) async -> Data?
    func checkpoint(enclosureID: Int64, positionMs: UInt64, durationMs: UInt64?) async
    func completed(enclosureID: Int64, durationMs: UInt64?) async throws
    func restart(enclosureID: Int64) async throws
    func observeDuration(enclosureID: Int64, durationMs: UInt64) async
}

@MainActor
final class IOSMediaPlaybackCoreAccess: IOSMediaPlaybackCoreAccessing {
    private let coreSessionExecutionCoordinator: IOSCoreSessionExecutionCoordinator
    private var core: Flux?
    init(coreSessionExecutionCoordinator: IOSCoreSessionExecutionCoordinator) { self.coreSessionExecutionCoordinator = coreSessionExecutionCoordinator }
    func attach(to core: Flux) { self.core = core }
    func detach() { core = nil }

    func preparePlayback(enclosureID: Int64) async throws -> PlaybackPreparation {
        let core = try requireCore()
        guard let result = await coreSessionExecutionCoordinator.responsiveResult(for: core, { try core.preparePlayback(enclosureId: enclosureID) }) else { throw IOSMediaPlaybackError.sessionUnavailable }
        return try result.get()
    }

    func playbackState(enclosureID: Int64) async -> PlaybackState? {
        guard let core, let result = await coreSessionExecutionCoordinator.responsiveResult(for: core, { try core.playbackState(enclosureId: enclosureID) }) else { return nil }
        switch result { case let .success(state): return state.status == .notStarted ? nil : state; case .failure: return nil }
    }

    func chapters(enclosureID: Int64) async throws -> [MediaChapter] {
        let core = try requireCore()
        guard let result = await coreSessionExecutionCoordinator.responsiveResult(for: core, { try core.mediaChapters(enclosureId: enclosureID) }) else { throw IOSMediaPlaybackError.sessionUnavailable }
        return try result.get()
    }

    func artworkSource(enclosureID: Int64) async -> MediaArtworkSource? {
        guard let core, let result = await coreSessionExecutionCoordinator.responsiveResult(for: core, { try core.mediaArtworkSource(enclosureId: enclosureID) }) else { return nil }
        switch result { case let .success(source): return source; case .failure: return nil }
    }

    func artwork(reference: String) async -> Data? {
        guard let core, let result = await coreSessionExecutionCoordinator.responsiveResult(for: core, { try core.mediaArtwork(reference: reference) }) else { return nil }
        switch result { case let .success(bytes): return bytes.map { Data($0) }; case .failure: return nil }
    }

    func checkpoint(enclosureID: Int64, positionMs: UInt64, durationMs: UInt64?) async {
        guard let core else { return }
        _ = await coreSessionExecutionCoordinator.responsiveResult(for: core, { try core.checkpointPlayback(enclosureId: enclosureID, positionMs: positionMs, durationMs: durationMs) })
    }

    func completed(enclosureID: Int64, durationMs: UInt64?) async throws {
        let core = try requireCore()
        guard let result = await coreSessionExecutionCoordinator.responsiveResult(for: core, { try core.playbackCompleted(enclosureId: enclosureID, durationMs: durationMs) }) else { throw IOSMediaPlaybackError.sessionUnavailable }
        try result.get()
    }

    func restart(enclosureID: Int64) async throws {
        let core = try requireCore()
        guard let result = await coreSessionExecutionCoordinator.responsiveResult(for: core, { try core.restartPlayback(enclosureId: enclosureID) }) else { throw IOSMediaPlaybackError.sessionUnavailable }
        try result.get()
    }

    func observeDuration(enclosureID: Int64, durationMs: UInt64) async {
        guard let core else { return }
        _ = await coreSessionExecutionCoordinator.responsiveResult(for: core, { try core.observeMediaDuration(enclosureId: enclosureID, durationMs: durationMs) })
    }

    private func requireCore() throws -> Flux { guard let core else { throw IOSMediaPlaybackError.coreUnavailable }; return core }
}

@MainActor
final class IOSMediaSleepTimer: ObservableObject {
    static let intervalsMinutes = Array(stride(from: 30, through: 180, by: 15))
    @Published private(set) var isEnabled = false
    @Published private(set) var intervalMinutes = 30
    @Published private(set) var remainingSeconds: Int?
    private var deadline: Date?; private var timer: Timer?; private let now: () -> Date
    var onFire: (() -> Void)?
    init(now: @escaping () -> Date = { Date() }) { self.now = now }
    func setEnabled(_ enabled: Bool) { enabled ? start(intervalMinutes: intervalMinutes) : disable() }
    func setInterval(_ minutes: Int) { guard Self.intervalsMinutes.contains(minutes) else { return }; intervalMinutes = minutes; if isEnabled { start(intervalMinutes: minutes) } }
    func evaluate(at date: Date? = nil) {
        guard isEnabled, let deadline else { return }; let current = date ?? now()
        if current >= deadline { timer?.invalidate(); timer = nil; self.deadline = nil; isEnabled = false; remainingSeconds = nil; onFire?() }
        else { remainingSeconds = max(1, Int(ceil(deadline.timeIntervalSince(current)))) }
    }
    private func start(intervalMinutes: Int) {
        timer?.invalidate(); let deadline = now().addingTimeInterval(TimeInterval(intervalMinutes * 60)); self.deadline = deadline; isEnabled = true; remainingSeconds = intervalMinutes * 60
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor [weak self] in self?.evaluate() } }
    }
    private func disable() { timer?.invalidate(); timer = nil; deadline = nil; isEnabled = false; remainingSeconds = nil }
    deinit { timer?.invalidate() }
}

@MainActor
final class IOSMediaPlaybackCoordinator {
    private static let fallbackArtworkReference = "__flux_bundle_fallback_artwork__"
    private let coreAccess: IOSMediaPlaybackCoreAccessing
    private let engine: IOSNativePlaybackEngine
    private let audioSession: IOSMediaAudioSessionManaging
    private let presentationState: IOSMediaPlaybackPresentationState
    private let checkpointInterval: TimeInterval
    private let logger = IOSAppLogger(category: "media-playback")
    private(set) var lastStartFailureDescription: String?
    let sleepTimer: IOSMediaSleepTimer
    private var checkpointTimer: Timer?
    private(set) var activeEnclosureID: Int64?
    private var completionSent = false
    private var preparedDurationMs: UInt64?
    private var lastObservedDurationMs: UInt64?
    private var preparedStatus: PlaybackStatus = .notStarted
    private var shouldResumeAfterInterruption = false
    var onPlaybackUseChanged: (() -> Void)?

    init(coreAccess: IOSMediaPlaybackCoreAccessing, presentationState: IOSMediaPlaybackPresentationState, engine: IOSNativePlaybackEngine? = nil, audioSession: IOSMediaAudioSessionManaging? = nil, checkpointInterval: TimeInterval = 20, sleepTimer: IOSMediaSleepTimer? = nil) {
        self.coreAccess = coreAccess; self.presentationState = presentationState; self.engine = engine ?? IOSAVPlayerPlaybackEngine(); self.audioSession = audioSession ?? IOSMediaAudioSessionCoordinator(); self.checkpointInterval = checkpointInterval; self.sleepTimer = sleepTimer ?? IOSMediaSleepTimer()
        self.engine.onEnded = { @MainActor [weak self] in self?.handleNaturalEnd() }
        self.engine.onDuration = { @MainActor [weak self] duration in self?.handleDuration(duration) }
        self.engine.onPosition = { @MainActor [weak self] position in self?.presentationState.setPosition(position) }
        self.engine.onPlaybackStateChanged = { @MainActor [weak self] isPlaying in guard let self else { return }; self.logger.info("AVPlayer playback state playing=\(isPlaying)"); if isPlaying { self.presentationState.setStatus(.playing); self.startCheckpointTimer() } }
        self.engine.onLoadingChanged = { @MainActor [weak self] loading in self?.presentationState.setLoading(loading) }
        self.engine.onBufferingChanged = { @MainActor [weak self] buffering in self?.presentationState.setBuffering(buffering) }
        self.engine.onError = { @MainActor [weak self] message in self?.logger.error("playback engine error: \(message)"); self?.presentationState.setErrorMessage(message) }
        self.audioSession.onInterruptionBegan = { [weak self] in self?.handleInterruptionBegan() }
        self.audioSession.onInterruptionEndedShouldResume = { [weak self] shouldResume in self?.handleInterruptionEnded(shouldResume: shouldResume) }
        self.audioSession.onOldDeviceUnavailable = { [weak self] in self?.handleRouteLoss() }
        self.sleepTimer.onFire = { [weak self] in self?.pause() }
    }

    func attach(to core: Flux) { coreAccess.attach(to: core) }
    func replaceCore(with core: Flux) { stopCheckpointTimer(); engine.pause(); engine.unload(); activeEnclosureID = nil; completionSent = false; preparedDurationMs = nil; lastObservedDurationMs = nil; preparedStatus = .notStarted; shouldResumeAfterInterruption = false; coreAccess.detach(); coreAccess.attach(to: core); presentationState.reset(); audioSession.deactivateIfIdle(); onPlaybackUseChanged?() }
    func detach() { stopCheckpointTimer(); engine.pause(); engine.unload(); activeEnclosureID = nil; completionSent = false; preparedDurationMs = nil; lastObservedDurationMs = nil; preparedStatus = .notStarted; shouldResumeAfterInterruption = false; coreAccess.detach(); presentationState.reset(); onPlaybackUseChanged?(); audioSession.deactivateIfIdle() }
    func suspendForCoreLifecycle() async { await checkpoint(); stopCheckpointTimer(); coreAccess.detach() }
    func resumeCoreAccess(_ core: Flux) { coreAccess.attach(to: core); if engine.isPlaying { startCheckpointTimer() } }

    @discardableResult
    func prepare(enclosureID: Int64) async throws -> PlaybackPreparation {
        lastStartFailureDescription = nil; logger.info("prepare requested enclosure=\(enclosureID)")
        if activeEnclosureID != enclosureID { await checkpoint(); engine.pause(); stopCheckpointTimer() }
        let preparation: PlaybackPreparation
        do { preparation = try await coreAccess.preparePlayback(enclosureID: enclosureID) }
        catch { lastStartFailureDescription = startFailureDescription(stage: "core-prepare", error: error); logger.error("prepare Core failed enclosure=\(enclosureID): \(String(reflecting: error))"); throw error }
        logger.info("prepare Core ok enclosure=\(enclosureID) status=\(String(describing: preparation.playbackState.status)) localFile=\(preparation.localFile != nil) durationMs=\(preparation.durationMs ?? preparation.playbackState.durationMs ?? 0)")
        let chapters = (try? await coreAccess.chapters(enclosureID: enclosureID)) ?? []
        activeEnclosureID = enclosureID; completionSent = false; preparedDurationMs = preparation.durationMs ?? preparation.playbackState.durationMs; lastObservedDurationMs = preparedDurationMs; preparedStatus = preparation.playbackState.status
        presentationState.setLoadedMedia(enclosure: preparation.enclosure, feedTitle: preparation.feedTitle, mediaTitle: preparation.articleTitle, artworkSource: preparation.artworkSource ?? .localReference(reference: Self.fallbackArtworkReference), chapters: chapters, positionMs: preparation.playbackState.positionMs, durationMs: preparedDurationMs)
        let source: URL
        do { source = try playbackURL(for: preparation) }
        catch { lastStartFailureDescription = startFailureDescription(stage: "source", error: error); logger.error("playback source resolution failed enclosure=\(enclosureID): \(String(reflecting: error))"); throw error }
        logger.info("playback source enclosure=\(enclosureID) local=\(source.isFileURL) scheme=\(source.scheme ?? "none")")
        presentationState.setPlaybackSource(source.isFileURL ? .local : .remote)
        let startAt = preparation.playbackState.status == .inProgress ? preparation.playbackState.positionMs : 0
        engine.load(url: source, startAtMs: startAt); engine.rate = presentationState.playbackRate; onPlaybackUseChanged?(); return preparation
    }

    func reconcileAfterSuccessfulSync() async {
        guard let enclosureID = activeEnclosureID else { return }; guard !engine.isPlaying else { logger.info("playback sync reconcile skipped active playback enclosure=\(enclosureID)"); return }
        guard let state = await coreAccess.playbackState(enclosureID: enclosureID) else { return }
        guard activeEnclosureID == enclosureID, !engine.isPlaying else { return }
        let targetPosition = state.status == .completed ? (state.durationMs ?? state.positionMs) : state.positionMs
        preparedStatus = state.status
        if let durationMs = state.durationMs { preparedDurationMs = durationMs; lastObservedDurationMs = durationMs; presentationState.setDuration(durationMs) }
        guard engine.currentPositionMs != targetPosition || presentationState.positionMs != targetPosition else { return }
        logger.info("playback sync reconcile enclosure=\(enclosureID) from=\(engine.currentPositionMs) to=\(targetPosition) status=\(String(describing: state.status))")
        engine.seek(toMs: targetPosition); presentationState.setPosition(targetPosition)
    }

    func play(enclosureID: Int64) async throws {
        lastStartFailureDescription = nil; logger.info("play requested enclosure=\(enclosureID) active=\(self.activeEnclosureID ?? -1)")
        if activeEnclosureID != enclosureID { _ = try await prepare(enclosureID: enclosureID) }
        guard activeEnclosureID == enclosureID else { logger.error("play aborted because active enclosure mismatch requested=\(enclosureID) active=\(self.activeEnclosureID ?? -1)"); return }
        guard preparedStatus != .completed else { logger.notice("play ignored because enclosure is already completed enclosure=\(enclosureID)"); return }
        do { try await audioSession.activate(); logger.info("audio session activated enclosure=\(enclosureID)") }
        catch { lastStartFailureDescription = startFailureDescription(stage: "audio-session", error: error); logger.error("audio session activation failed enclosure=\(enclosureID): \(String(reflecting: error))"); throw error }
        engine.play(); if engine.isPlaying { presentationState.setStatus(.playing); startCheckpointTimer() }
    }

    func pause() { engine.pause(); presentationState.setPosition(engine.currentPositionMs); presentationState.setStatus(.paused); stopCheckpointTimer(); onPlaybackUseChanged?(); Task { @MainActor [weak self] in await self?.checkpoint() } }
    func stop() { engine.pause(); presentationState.setPosition(engine.currentPositionMs); presentationState.setStatus(.stopped); stopCheckpointTimer(); onPlaybackUseChanged?(); audioSession.deactivateIfIdle(); Task { @MainActor [weak self] in await self?.checkpoint() } }
    func sceneWillResignActive() { Task { @MainActor [weak self] in await self?.checkpoint() } }
    func sceneDidBecomeActive() { sleepTimer.evaluate() }
    func applicationWillTerminate() { Task { @MainActor [weak self] in guard let self else { return }; await self.checkpoint(); self.stopCheckpointTimer(); self.engine.unload(); self.audioSession.deactivateIfIdle() } }
    func seek(toMs: UInt64) { engine.seek(toMs: toMs); presentationState.setPosition(toMs); Task { @MainActor [weak self] in await self?.checkpoint() } }
    func skip(bySeconds seconds: Double) { guard seconds.isFinite else { return }; let current = Double(engine.currentPositionMs) / 1_000; let target = max(0, current + seconds); let bounded = presentationState.durationMs.map { min(target, Double($0) / 1_000) } ?? target; seek(toMs: UInt64(max(0, bounded * 1_000).rounded())) }
    func restart(enclosureID: Int64) async throws { let wasPlaying = engine.isPlaying; let wasStopped = presentationState.status == .stopped; let wasCompleted = preparedStatus == .completed; try await coreAccess.restart(enclosureID: enclosureID); _ = try await prepare(enclosureID: enclosureID); if wasPlaying || wasCompleted { try await play(enclosureID: enclosureID) } else if wasStopped { presentationState.setStatus(.stopped) } }
    func setPlaybackRate(_ rate: Double) { guard rate.isFinite else { return }; let clamped = min(3.0, max(0.5, rate)); let rounded = (clamped * 10).rounded() / 10; presentationState.setPlaybackRate(rounded); engine.rate = rounded }
    func isUsing(enclosureID: Int64) -> Bool { activeEnclosureID == enclosureID }
    func blocksMediaDeletion(enclosureID: Int64) -> Bool { activeEnclosureID == enclosureID && engine.isPlaying }

    func previewArtworkSource(enclosureID: Int64) async -> MediaArtworkSource? {
        await coreAccess.artworkSource(enclosureID: enclosureID)
            ?? .localReference(reference: Self.fallbackArtworkReference)
    }

    func previewChapters(enclosureID: Int64) async -> [MediaChapter] { (try? await coreAccess.chapters(enclosureID: enclosureID)) ?? [] }

    func artwork(source: MediaArtworkSource) async -> Data? {
        switch source {
        case let .localReference(reference):
            if reference == Self.fallbackArtworkReference { return AppleFallbackArtwork.data() }
            return await coreAccess.artwork(reference: reference) ?? AppleFallbackArtwork.data()
        case let .remoteUrl(urlString):
            guard let url = URL(string: urlString), url.scheme == "http" || url.scheme == "https" else { return AppleFallbackArtwork.data() }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { return AppleFallbackArtwork.data() }
                return data
            } catch { return AppleFallbackArtwork.data() }
        }
    }

    private func startFailureDescription(stage: String, error: Error) -> String { "\(String(localized: "Playback start failed")) [\(stage)]: \(error.localizedDescription)" }
    private func playbackURL(for preparation: PlaybackPreparation) throws -> URL {
        if let localFile = preparation.localFile, let mediaRoot = IOSMediaTransferPathConfiguration.mediaRootURL,
           let localURL = try? MediaTransferFileLayout.destination(reference: localFile, under: mediaRoot) {
            let attributes = try? FileManager.default.attributesOfItem(atPath: localURL.path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? -1
            let readable = FileManager.default.isReadableFile(atPath: localURL.path)
            logger.info("download source check exists=\(attributes != nil) readable=\(readable) bytes=\(size) legacy=\(localFile.hasPrefix("downloads/legacy/"))")
            if readable && size > 0 {
                // Flutter migration used the generic .audio suffix. AVPlayer can
                // reject otherwise valid MP3/MP4 content with AVErrorCannotOpen.
                // Preserve the Core reference and original file; expose a
                // format-specific hard link only when its header is recognized.
                if localFile.hasPrefix("downloads/legacy/"),
                   localURL.pathExtension == "audio",
                   let playableURL = Self.legacyPlayableURL(for: localURL) {
                    logger.info("using format-specific legacy media alias")
                    return playableURL
                }
                logger.info("using downloaded local media file")
                return localURL
            }
        }
        if preparation.localFile != nil { logger.notice("downloaded media reference unavailable; falling back to remote URL") }
        guard let remoteURL = URL(string: preparation.enclosure.url), remoteURL.scheme == "http" || remoteURL.scheme == "https" else { throw IOSMediaPlaybackError.invalidMediaURL }
        return remoteURL
    }
    private static func legacyPlayableURL(for source: URL) -> URL? {
        guard let handle = try? FileHandle(forReadingFrom: source) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 16) else { return nil }
        let bytes = [UInt8](header)
        let ext: String
        if bytes.starts(with: [0x49, 0x44, 0x33])
            || (bytes.count >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) {
            ext = "mp3"
        } else if bytes.count >= 12 && Array(bytes[4..<8]) == [0x66, 0x74, 0x79, 0x70] {
            ext = "m4a"
        } else if bytes.starts(with: [0x4F, 0x67, 0x67, 0x53]) {
            ext = "ogg"
        } else if bytes.starts(with: [0x66, 0x4C, 0x61, 0x43]) {
            ext = "flac"
        } else { return nil }
        let alias = source.deletingPathExtension().appendingPathExtension(ext)
        if FileManager.default.fileExists(atPath: alias.path) {
            guard let originalSize = (try? source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
                  let aliasSize = (try? alias.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
                  originalSize == aliasSize else { return nil }
            return alias
        }
        do {
            try FileManager.default.linkItem(at: source, to: alias)
            return alias
        } catch { return nil }
    }

    private func checkpoint() async { guard let activeEnclosureID else { return }; await coreAccess.checkpoint(enclosureID: activeEnclosureID, positionMs: engine.currentPositionMs, durationMs: engine.durationMs ?? preparedDurationMs) }
    private func handleNaturalEnd() { guard let activeEnclosureID, !completionSent else { return }; Task { @MainActor [weak self] in guard let self else { return }; do { try await self.coreAccess.completed(enclosureID: activeEnclosureID, durationMs: self.engine.durationMs ?? self.preparedDurationMs); self.completionSent = true; self.preparedStatus = .completed; self.presentationState.setStatus(.paused); self.presentationState.setPosition(self.engine.currentPositionMs); self.stopCheckpointTimer(); self.onPlaybackUseChanged?() } catch { self.presentationState.setStatus(.paused); self.logger.error("media completion failed: \(String(reflecting: error))") } } }
    private func handleDuration(_ duration: UInt64) { guard lastObservedDurationMs != duration else { return }; lastObservedDurationMs = duration; preparedDurationMs = duration; presentationState.setDuration(duration); guard let activeEnclosureID else { return }; Task { @MainActor [weak self] in await self?.coreAccess.observeDuration(enclosureID: activeEnclosureID, durationMs: duration) } }
    private func handleInterruptionBegan() { shouldResumeAfterInterruption = engine.isPlaying; engine.pause(); presentationState.setStatus(.paused); stopCheckpointTimer(); Task { @MainActor [weak self] in await self?.checkpoint() } }
    private func handleInterruptionEnded(shouldResume: Bool) { guard shouldResumeAfterInterruption else { return }; shouldResumeAfterInterruption = false; guard shouldResume, let activeEnclosureID else { return }; Task { @MainActor [weak self] in guard let self else { return }; try? await self.play(enclosureID: activeEnclosureID) } }
    private func handleRouteLoss() { guard engine.isPlaying else { return }; engine.pause(); presentationState.setStatus(.paused); stopCheckpointTimer(); Task { @MainActor [weak self] in await self?.checkpoint() } }
    private func startCheckpointTimer() { guard checkpointTimer == nil else { return }; checkpointTimer = Timer.scheduledTimer(withTimeInterval: checkpointInterval, repeats: true) { [weak self] _ in Task { @MainActor [weak self] in guard let self, self.engine.isPlaying else { return }; await self.checkpoint() } } }
    private func stopCheckpointTimer() { checkpointTimer?.invalidate(); checkpointTimer = nil }
}
