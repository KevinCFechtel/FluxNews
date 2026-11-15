import CarPlay
import Combine
import Foundation
import MediaPlayer
import UIKit

enum IOSMediaPlaybackSource: Equatable, Hashable {
    case local
    case remote
}

@MainActor
final class IOSMediaPlaybackPresentationState: ObservableObject {
    @Published private(set) var loadedEnclosure: Enclosure?
    @Published private(set) var feedTitle = ""
    @Published private(set) var mediaTitle = ""
    @Published private(set) var artworkSource: MediaArtworkSource?
    @Published private(set) var chapters: [MediaChapter] = []
    @Published private(set) var status: MediaPlaybackPresentationStatus = .stopped
    @Published private(set) var positionMs: UInt64 = 0
    @Published private(set) var durationMs: UInt64?
    @Published private(set) var playbackSource: IOSMediaPlaybackSource?
    @Published private(set) var isLoading = false
    @Published private(set) var isBuffering = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var playbackRate = 1.0

    func reset() {
        loadedEnclosure = nil
        feedTitle = ""
        mediaTitle = ""
        artworkSource = nil
        chapters = []
        status = .stopped
        positionMs = 0
        durationMs = nil
        playbackSource = nil
        isLoading = false
        isBuffering = false
        errorMessage = nil
        playbackRate = 1.0
    }

    func setLoadedMedia(
        enclosure: Enclosure,
        feedTitle: String,
        mediaTitle: String,
        artworkSource: MediaArtworkSource?,
        chapters: [MediaChapter],
        positionMs: UInt64,
        durationMs: UInt64?
    ) {
        loadedEnclosure = enclosure
        self.feedTitle = feedTitle
        self.mediaTitle = mediaTitle
        self.artworkSource = artworkSource
        self.chapters = chapters
        self.positionMs = positionMs
        self.durationMs = durationMs
        playbackSource = nil
        status = .paused
        isLoading = false
        isBuffering = false
        errorMessage = nil
    }

    func setStatus(_ status: MediaPlaybackPresentationStatus) { self.status = status }
    func setPosition(_ positionMs: UInt64) { self.positionMs = positionMs }
    func setDuration(_ durationMs: UInt64?) { self.durationMs = durationMs }
    func setPlaybackSource(_ playbackSource: IOSMediaPlaybackSource?) { self.playbackSource = playbackSource }
    func setLoading(_ isLoading: Bool) { self.isLoading = isLoading }
    func setBuffering(_ isBuffering: Bool) { self.isBuffering = isBuffering }
    func setErrorMessage(_ errorMessage: String?) { self.errorMessage = errorMessage }
    func setPlaybackRate(_ playbackRate: Double) { self.playbackRate = playbackRate }
    func setChapters(_ chapters: [MediaChapter]) { self.chapters = chapters }
}

@MainActor
final class IOSMediaTransferPresentationState: ObservableObject {
    @Published private(set) var transfers: [Int64: MediaTransferRuntime] = [:]

    func runtime(for enclosureID: Int64) -> MediaTransferRuntime? { transfers[enclosureID] }
    func set(_ runtime: MediaTransferRuntime) { transfers[runtime.enclosureID] = runtime }
    func remove(enclosureID: Int64) { transfers[enclosureID] = nil }
    func reset() { transfers.removeAll() }
}

protocol IOSNowPlayingInfoPublishing: AnyObject {
    var nowPlayingInfo: [String: Any]? { get set }
    var playbackState: MPNowPlayingPlaybackState { get set }
}

extension MPNowPlayingInfoCenter: IOSNowPlayingInfoPublishing {}

@MainActor
final class IOSNowPlayingCoordinator {
    private let playbackCoordinator: IOSMediaPlaybackCoordinator
    private let presentationState: IOSMediaPlaybackPresentationState
    private let nowPlaying: IOSNowPlayingInfoPublishing
    private let remoteCommandCenter: MPRemoteCommandCenter
    private var cancellables = Set<AnyCancellable>()
    private var commandRegistrations: [(MPRemoteCommand, Any)] = []
    private var artworkGeneration = 0
    private var artworkSource: MediaArtworkSource?
    private var artworkData: Data?
    private var publishedArtworkData: Data?
    private var publishedArtwork: MPMediaItemArtwork?
    private var hasPublishedArtwork = false

    private(set) var remoteCommandRegistrationCount = 0

    init(
        playbackCoordinator: IOSMediaPlaybackCoordinator,
        presentationState: IOSMediaPlaybackPresentationState,
        nowPlaying: IOSNowPlayingInfoPublishing = MPNowPlayingInfoCenter.default(),
        remoteCommandCenter: MPRemoteCommandCenter = .shared()
    ) {
        self.playbackCoordinator = playbackCoordinator
        self.presentationState = presentationState
        self.nowPlaying = nowPlaying
        self.remoteCommandCenter = remoteCommandCenter
        observePresentationState()
        startRemoteCommands()
        publish()
    }

    func cleanup() {
        removeRemoteCommandTargets()
        cancellables.removeAll()
        artworkGeneration += 1
        artworkSource = nil
        artworkData = nil
        publishedArtworkData = nil
        publishedArtwork = nil
        hasPublishedArtwork = false
        clear()
    }

    func startRemoteCommands() {
        guard commandRegistrations.isEmpty else { return }
        registerRemoteCommands()
    }

    func dispatch(_ command: AppleMediaRemoteCommand) -> MPRemoteCommandHandlerStatus {
        switch command {
        case .play: return handlePlay()
        case .pause: return handlePause()
        case .stop: return handleStop()
        case .toggle: return handleToggle()
        case .skipBackward: return handleSkip(seconds: -AppleMediaRemoteCommandPolicy.skipBackwardIntervalSeconds)
        case .skipForward: return handleSkip(seconds: AppleMediaRemoteCommandPolicy.skipForwardIntervalSeconds)
        case let .seek(seconds): return handleSeek(seconds: seconds)
        }
    }

    private func observePresentationState() {
        presentationState.$positionMs
            .sink { [weak self] _ in self?.publishElapsed() }
            .store(in: &cancellables)

        // @Published emits before the backing property changes. Pass the status
        // through so Stop clears the system projection in that same emission.
        presentationState.$status
            .sink { [weak self] status in self?.publish(status: status) }
            .store(in: &cancellables)

        Publishers.MergeMany(
            presentationState.$loadedEnclosure.map { _ in () }.eraseToAnyPublisher(),
            presentationState.$feedTitle.map { _ in () }.eraseToAnyPublisher(),
            presentationState.$mediaTitle.map { _ in () }.eraseToAnyPublisher(),
            presentationState.$artworkSource.map { _ in () }.eraseToAnyPublisher(),
            presentationState.$durationMs.map { _ in () }.eraseToAnyPublisher(),
            presentationState.$playbackRate.map { _ in () }.eraseToAnyPublisher(),
            presentationState.$errorMessage.map { _ in () }.eraseToAnyPublisher()
        )
        .sink { [weak self] _ in self?.publish() }
        .store(in: &cancellables)
    }

    private func registerRemoteCommands() {
        remoteCommandRegistrationCount += 1
        remoteCommandCenter.nextTrackCommand.isEnabled = false
        remoteCommandCenter.previousTrackCommand.isEnabled = false

        add(remoteCommandCenter.playCommand) { [weak self] _ in self?.dispatch(.play) ?? .commandFailed }
        add(remoteCommandCenter.pauseCommand) { [weak self] _ in self?.dispatch(.pause) ?? .commandFailed }
        add(remoteCommandCenter.stopCommand) { [weak self] _ in self?.dispatch(.stop) ?? .commandFailed }
        add(remoteCommandCenter.togglePlayPauseCommand) { [weak self] _ in self?.dispatch(.toggle) ?? .commandFailed }

        remoteCommandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: AppleMediaRemoteCommandPolicy.skipBackwardIntervalSeconds)]
        remoteCommandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: AppleMediaRemoteCommandPolicy.skipForwardIntervalSeconds)]
        add(remoteCommandCenter.skipBackwardCommand) { [weak self] _ in self?.dispatch(.skipBackward) ?? .commandFailed }
        add(remoteCommandCenter.skipForwardCommand) { [weak self] _ in self?.dispatch(.skipForward) ?? .commandFailed }
        add(remoteCommandCenter.changePlaybackPositionCommand) { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            return self?.dispatch(.seek(seconds: event.positionTime)) ?? .commandFailed
        }
    }

    private func add(_ command: MPRemoteCommand, handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
        command.isEnabled = true
        commandRegistrations.append((command, command.addTarget(handler: handler)))
    }

    private func removeRemoteCommandTargets() {
        for (command, token) in commandRegistrations { command.removeTarget(token) }
        commandRegistrations.removeAll()
    }

    private func handlePlay() -> MPRemoteCommandHandlerStatus {
        guard let enclosureID = presentationState.loadedEnclosure?.id else { return .commandFailed }
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await self.playbackCoordinator.play(enclosureID: enclosureID)
        }
        return .success
    }

    private func handlePause() -> MPRemoteCommandHandlerStatus {
        guard presentationState.loadedEnclosure != nil else { return .commandFailed }
        playbackCoordinator.pause()
        return .success
    }

    private func handleStop() -> MPRemoteCommandHandlerStatus {
        guard presentationState.loadedEnclosure != nil else { return .commandFailed }
        playbackCoordinator.stop()
        return .success
    }

    private func handleToggle() -> MPRemoteCommandHandlerStatus {
        guard presentationState.loadedEnclosure != nil else { return .commandFailed }
        if presentationState.status == .playing {
            playbackCoordinator.pause()
            return .success
        }
        return handlePlay()
    }

    private func handleSkip(seconds: Double) -> MPRemoteCommandHandlerStatus {
        guard presentationState.loadedEnclosure != nil else { return .commandFailed }
        playbackCoordinator.skip(bySeconds: seconds)
        return .success
    }

    private func handleSeek(seconds: Double) -> MPRemoteCommandHandlerStatus {
        guard seconds.isFinite, seconds >= 0, presentationState.loadedEnclosure != nil else { return .commandFailed }
        let bounded = presentationState.durationMs.map { min(seconds, Double($0) / 1_000) } ?? seconds
        guard bounded.isFinite, bounded <= Double(UInt64.max) / 1_000 else { return .commandFailed }
        playbackCoordinator.seek(toMs: UInt64(bounded * 1_000))
        return .success
    }

    private func projection(
        status: MediaPlaybackPresentationStatus
    ) -> AppleNowPlayingProjection? {
        guard let enclosure = presentationState.loadedEnclosure else { return nil }
        return AppleNowPlayingProjection.make(
            title: presentationState.mediaTitle,
            sourceTitle: presentationState.feedTitle,
            enclosureURL: enclosure.url,
            durationMs: presentationState.durationMs,
            positionMs: presentationState.positionMs,
            status: status,
            playbackRate: presentationState.playbackRate,
            errorMessage: presentationState.errorMessage,
            artworkData: artworkData
        )
    }

    private func publish(
        status: MediaPlaybackPresentationStatus? = nil
    ) {
        let status = status ?? presentationState.status
        guard status != .stopped,
              let projection = projection(status: status)
        else {
            clear()
            return
        }
        requestArtworkIfNeeded()

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: projection.title,
            MPMediaItemPropertyAlbumTitle: projection.sourceTitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: projection.elapsedSeconds,
            MPNowPlayingInfoPropertyPlaybackRate: projection.effectivePlaybackRate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: projection.defaultPlaybackRate
        ]
        if let assetURL = projection.assetURL { info[MPNowPlayingInfoPropertyAssetURL] = assetURL }
        if let duration = projection.durationSeconds { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if !hasPublishedArtwork || publishedArtworkData != projection.artworkData {
            publishedArtworkData = projection.artworkData
            hasPublishedArtwork = true
            if let data = projection.artworkData, let image = UIImage(data: data) {
                publishedArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            } else {
                publishedArtwork = nil
            }
        }
        if let publishedArtwork { info[MPMediaItemPropertyArtwork] = publishedArtwork }
        nowPlaying.nowPlayingInfo = info
        nowPlaying.playbackState = projection.playbackState == .playing ? .playing : .paused
    }

    private func publishElapsed() {
        guard presentationState.status != .stopped,
              let projection = projection(status: presentationState.status),
              var info = nowPlaying.nowPlayingInfo
        else {
            publish()
            return
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = projection.elapsedSeconds
        info[MPNowPlayingInfoPropertyPlaybackRate] = projection.effectivePlaybackRate
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = projection.defaultPlaybackRate
        nowPlaying.nowPlayingInfo = info
        nowPlaying.playbackState = projection.playbackState == .playing ? .playing : .paused
    }

    private func clear() {
        nowPlaying.nowPlayingInfo = nil
        nowPlaying.playbackState = .unknown
    }

    private func requestArtworkIfNeeded() {
        let source = presentationState.artworkSource
        guard source != artworkSource else { return }
        artworkSource = source
        artworkData = nil
        artworkGeneration += 1
        let generation = artworkGeneration
        guard let source else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let data = await self.playbackCoordinator.artwork(source: source)
            guard self.artworkGeneration == generation, self.presentationState.artworkSource == source else { return }
            self.artworkData = data
            self.publish()
        }
    }
}

enum IOSCarPlayPlaybackIndicator: Equatable {
    case unplayed
    case completed

    @MainActor
    static func indicator(
        for item: ListeningListItem,
        runtime: IOSMediaPlaybackPresentationState
    ) -> Self? {
        if IOSListeningListPresentation.progress(item, runtime: runtime)?.status == .completed {
            return .completed
        }
        if IOSListeningListPresentation.isUnplayed(item, runtime: runtime) {
            return .unplayed
        }
        return nil
    }
}

@MainActor
final class IOSCarPlayCoordinator {
    private weak var interfaceController: CPInterfaceController?
    private let mediaRuntime: IOSMediaRuntime
    private var rootListTemplate: CPListTemplate?
    private var loadGeneration: UInt64 = 0
    private var selectedFeedID: Int64?
    private var feeds: [ListeningListFeed] = []
    private var visibleItems: [ListeningListItem] = []
    private var listItemsByEnclosureID: [Int64: CPListItem] = [:]
    private var cancellables = Set<AnyCancellable>()

    init(mediaRuntime: IOSMediaRuntime) {
        self.mediaRuntime = mediaRuntime
        observePlaybackState()
    }

    func connect(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        installRootTemplate()
        reloadListeningList()
    }

    func disconnect() {
        loadGeneration &+= 1
        interfaceController = nil
        rootListTemplate = nil
        visibleItems.removeAll()
        listItemsByEnclosureID.removeAll()
    }

    func reloadListeningList() {
        guard let core = mediaRuntime.core else {
            updateRootMessage(String(localized: "Media is not available yet."))
            return
        }

        loadGeneration &+= 1
        let generation = loadGeneration
        let requestedFeedID = selectedFeedID
        let executionCoordinator = mediaRuntime.coreSessionExecutionCoordinator

        Task { @MainActor [weak self, core, executionCoordinator] in
            guard let result = await executionCoordinator.responsiveResult(
                for: core,
                {
                    let feeds = try core.listeningListFeeds()
                    let validatedFeedID = requestedFeedID.flatMap { id in
                        feeds.contains(where: { $0.feedId == id }) ? id : nil
                    }
                    let items = try core.listeningList(feedId: validatedFeedID, sort: .recentlyAdded)
                    return (feeds, validatedFeedID, items)
                }
            ) else { return }
            guard let self, self.loadGeneration == generation, self.mediaRuntime.core === core else { return }

            switch result {
            case let .success((feeds, validatedFeedID, items)):
                NSLog(
                    "Flux CarPlay ListeningList requestedFeedID=%@ validatedFeedID=%@ feeds=%d items=%d",
                    requestedFeedID.map(String.init) ?? "nil",
                    validatedFeedID.map(String.init) ?? "nil",
                    feeds.count,
                    items.count
                )
                self.feeds = feeds
                self.selectedFeedID = validatedFeedID
                self.visibleItems = items
                self.showListeningList(items)
            case let .failure(error):
                NSLog("Flux CarPlay ListeningList load failed: %@", String(describing: error))
                self.updateRootMessage(String(localized: "The Listening List could not be loaded."))
            }
        }
    }

    private func observePlaybackState() {
        Publishers.CombineLatest3(
            mediaRuntime.playbackPresentationState.$loadedEnclosure,
            mediaRuntime.playbackPresentationState.$positionMs,
            mediaRuntime.playbackPresentationState.$status
        )
        .sink { [weak self] _, _, _ in self?.refreshPlaybackIndicators() }
        .store(in: &cancellables)

        mediaRuntime.playbackPresentationState.$durationMs
            .sink { [weak self] _ in self?.refreshPlaybackIndicators() }
            .store(in: &cancellables)
    }

    private func installRootTemplate() {
        let loading = CPListItem(text: String(localized: "Loading…"), detailText: nil)
        loading.isEnabled = false
        let template = CPListTemplate(
            title: String(localized: "Listening List"),
            sections: [CPListSection(items: [loading])]
        )
        rootListTemplate = template
        interfaceController?.setRootTemplate(template, animated: false, completion: nil)
    }

    private func updateRootMessage(_ message: String) {
        guard let template = rootListTemplate else { return }
        listItemsByEnclosureID.removeAll()
        visibleItems.removeAll()
        let item = CPListItem(text: message, detailText: nil)
        item.isEnabled = false
        template.updateSections([CPListSection(items: [item])])
        configureFilterButton(on: template)
    }

    private func showListeningList(_ items: [ListeningListItem]) {
        guard let template = rootListTemplate else { return }
        listItemsByEnclosureID.removeAll()
        visibleItems = items
        guard !items.isEmpty else {
            updateRootMessage(String(localized: "No audio items available."))
            return
        }

        let limit = CPListTemplate.maximumItemCount
        let projected = items.prefix(limit).map(makeListItem)
        template.updateSections([CPListSection(items: Array(projected))])
        configureFilterButton(on: template)
        refreshPlaybackIndicators()
        loadArtworkForVisibleItems(generation: loadGeneration)
    }

    private func configureFilterButton(on template: CPListTemplate) {
        guard !feeds.isEmpty else {
            template.trailingNavigationBarButtons = []
            return
        }
        template.trailingNavigationBarButtons = [
            CPBarButton(title: String(localized: "Filter")) { [weak self] _ in
                self?.showFeedFilter()
            }
        ]
    }

    private func showFeedFilter() {
        guard let interfaceController else { return }
        var filterItems: [CPListItem] = []

        let all = CPListItem(text: String(localized: "All Feeds"), detailText: nil)
        all.setAccessoryImage(selectedFeedID == nil ? UIImage(systemName: "checkmark") : nil)
        all.handler = { [weak self] _, completion in
            self?.selectFeed(nil)
            completion()
        }
        filterItems.append(all)

        let remaining = max(0, CPListTemplate.maximumItemCount - 1)
        for feed in feeds.prefix(remaining) {
            let detail = String(localized: "\(feed.itemCount) items")
            let item = CPListItem(text: feed.feedTitle, detailText: detail)
            item.setAccessoryImage(selectedFeedID == feed.feedId ? UIImage(systemName: "checkmark") : nil)
            item.handler = { [weak self] _, completion in
                self?.selectFeed(feed.feedId)
                completion()
            }
            filterItems.append(item)
        }

        let template = CPListTemplate(
            title: String(localized: "Filter by Feed"),
            sections: [CPListSection(items: filterItems)]
        )
        interfaceController.pushTemplate(template, animated: true, completion: nil)
    }

    private func selectFeed(_ feedID: Int64?) {
        selectedFeedID = feedID
        interfaceController?.popTemplate(animated: true, completion: nil)
        reloadListeningList()
    }

    private func makeListItem(_ item: ListeningListItem) -> CPListItem {
        let title = IOSListeningListPresentation.textOrFallback(item.title, fallback: String(localized: "Untitled"))
        let feedTitle = IOSListeningListPresentation.textOrFallback(item.feedTitle, fallback: String(localized: "Unknown Feed"))

        guard let selected = IOSListeningListPresentation.selectedEnclosure(item) else {
            let detail = item.audioEnclosures.count > 1 ? String(localized: "Multiple audio files") : feedTitle
            let listItem = CPListItem(text: title, detailText: detail)
            listItem.isEnabled = false
            listItem.setAccessoryImage(playbackIndicatorImage(for: item))
            return listItem
        }

        let detail = detailText(for: item, selected: selected)
        let listItem = CPListItem(text: title, detailText: detail)
        let enclosureID = selected.enclosure.id
        listItemsByEnclosureID[enclosureID] = listItem
        applyPlaybackPresentation(to: listItem, item: item, selected: selected)

        listItem.handler = { [weak self] _, completion in
            Task { @MainActor [weak self] in
                guard let self else { completion(); return }
                do {
                    try await self.mediaRuntime.playbackCoordinator.play(enclosureID: enclosureID)
                    self.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
                } catch {
                    // Playback errors remain owned by the shared media runtime.
                }
                completion()
            }
        }
        return listItem
    }

    private func detailText(for item: ListeningListItem, selected: ListeningListEnclosure) -> String {
        let feedTitle = IOSListeningListPresentation.textOrFallback(item.feedTitle, fallback: String(localized: "Unknown Feed"))
        let runtime = mediaRuntime.playbackPresentationState
        let isRuntimeItem = runtime.loadedEnclosure?.id == selected.enclosure.id
        let position = isRuntimeItem ? runtime.positionMs : selected.playbackState?.positionMs ?? 0
        let duration = isRuntimeItem
            ? runtime.durationMs ?? selected.durationMs ?? selected.playbackState?.durationMs
            : selected.durationMs ?? selected.playbackState?.durationMs

        guard let duration, duration > 0 else { return feedTitle }
        let durationLabel = IOSMediaTimePresentation.label(duration)
        guard position > 0 else { return "\(feedTitle) · \(durationLabel)" }
        let positionLabel = IOSMediaTimePresentation.label(min(position, duration))
        return "\(feedTitle) · \(positionLabel) / \(durationLabel)"
    }

    private func playbackIndicatorImage(for item: ListeningListItem) -> UIImage? {
        switch IOSCarPlayPlaybackIndicator.indicator(
            for: item,
            runtime: mediaRuntime.playbackPresentationState
        ) {
        case .unplayed:
            return UIImage(
                systemName: "circle.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            )
        case .completed:
            return UIImage(systemName: "checkmark.circle.fill")
        case nil:
            return nil
        }
    }

    private func applyPlaybackPresentation(
        to listItem: CPListItem,
        item: ListeningListItem,
        selected: ListeningListEnclosure
    ) {
        let runtime = mediaRuntime.playbackPresentationState
        let isRuntimeItem = runtime.loadedEnclosure?.id == selected.enclosure.id
        let position = isRuntimeItem ? runtime.positionMs : selected.playbackState?.positionMs ?? 0
        let duration = isRuntimeItem
            ? runtime.durationMs ?? selected.durationMs ?? selected.playbackState?.durationMs
            : selected.durationMs ?? selected.playbackState?.durationMs
        listItem.isPlaying = isRuntimeItem && runtime.status == .playing
        if let duration, duration > 0 {
            listItem.playbackProgress = min(max(Double(position) / Double(duration), 0), 1)
        } else {
            listItem.playbackProgress = 0
        }
        listItem.setDetailText(detailText(for: item, selected: selected))
        // A trailing symbol complements native CarPlay playback progress / Now Playing.
        // No custom row type or driver interaction is introduced.
        listItem.setAccessoryImage(playbackIndicatorImage(for: item))
    }

    private func refreshPlaybackIndicators() {
        for item in visibleItems {
            guard let selected = IOSListeningListPresentation.selectedEnclosure(item),
                  let listItem = listItemsByEnclosureID[selected.enclosure.id] else { continue }
            applyPlaybackPresentation(to: listItem, item: item, selected: selected)
        }
    }

    private func loadArtworkForVisibleItems(generation: UInt64) {
        for item in visibleItems.prefix(CPListTemplate.maximumItemCount) {
            guard let selected = IOSListeningListPresentation.selectedEnclosure(item),
                  let listItem = listItemsByEnclosureID[selected.enclosure.id] else { continue }
            let enclosureID = selected.enclosure.id
            Task { @MainActor [weak self, weak listItem] in
                guard let self, let listItem else { return }
                guard let source = await self.mediaRuntime.playbackCoordinator.previewArtworkSource(enclosureID: enclosureID),
                      let data = await self.mediaRuntime.playbackCoordinator.artwork(source: source),
                      let image = UIImage(data: data),
                      self.loadGeneration == generation,
                      self.listItemsByEnclosureID[enclosureID] === listItem else { return }
                listItem.setImage(image)
            }
        }
    }
}

@MainActor
@objc(IOSCarPlaySceneDelegate)
final class IOSCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var coordinator: IOSCarPlayCoordinator?
    private var startupTask: Task<Void, Never>?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        let runtime = IOSAppRuntime.shared
        let coordinator = IOSCarPlayCoordinator(mediaRuntime: runtime.mediaRuntime)
        self.coordinator = coordinator
        coordinator.connect(interfaceController: interfaceController)

        startupTask?.cancel()
        startupTask = Task { @MainActor [weak self, weak coordinator] in
            guard let self, let coordinator else { return }
            guard await runtime.bootstrapper.ensureStarted() != nil else {
                guard !Task.isCancelled, self.coordinator === coordinator else { return }
                coordinator.reloadListeningList()
                return
            }
            guard !Task.isCancelled, self.coordinator === coordinator else { return }
            coordinator.reloadListeningList()
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        startupTask?.cancel()
        startupTask = nil
        coordinator?.disconnect()
        coordinator = nil
    }
}
