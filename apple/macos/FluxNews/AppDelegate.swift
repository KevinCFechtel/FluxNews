import AppKit
import Combine
import CoreSpotlight
import Network
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    let store = BrowserStore()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!
    private var statusItemWidthLocked = false
    private var countObservation: AnyCancellable?
    private var settingsObservation: AnyCancellable?
    private var catalogObservation: AnyCancellable?
    private var shortcutObservation: AnyCancellable?
    private var networkMonitor: NWPathMonitor?
    private let networkMonitorQueue = DispatchQueue(label: "FluxNews.macOS.network-recovery")
    private let spotlightIndexer = SpotlightIndexer()
    private let playbackPresentationState = MediaPlaybackPresentationState()
    private let transferPresentationState = MediaTransferPresentationState()
    private(set) var playbackCoordinator: MediaPlaybackCoordinator?
    private var mediaRemoteControlCoordinator: MediaRemoteControlCoordinator?
    private var transferCoordinator: MediaTransferCoordinator?
    private lazy var shortcutRegistrar = GlobalShortcutRegistrar { [weak self] in self?.show() }
    private var sidebarVisible = false
    private var fallbackPanel: NSPanel?
    private var settingsWindowController: NSWindowController?
    private lazy var readerWindow = ReaderWindowController(store: store)

    func applicationDidResignActive(_ notification: Notification) {
        playbackCoordinator?.applicationDidResignActive()
        readerWindow.hide()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.didWakeNotification, object: nil)
        networkMonitor?.cancel()
        networkMonitor = nil
        mediaRemoteControlCoordinator?.cleanup()
        playbackCoordinator?.applicationWillTerminate()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.onCoreConfigured = { [weak self] core in
            guard let self else { return }
            mediaRemoteControlCoordinator?.cleanup()
            playbackCoordinator?.applicationWillTerminate()
            playbackCoordinator?.onPlaybackUseChanged = nil
            transferCoordinator?.shutdown()
            transferCoordinator?.onWorkChanged = nil
            store.onMediaTransferRequested = { [weak self] in self?.transferCoordinator?.reconcile() }
            store.onCancelMediaTransferRequested = { [weak self] id in self?.transferCoordinator?.cancel(enclosureID: id) }
            store.onReleaseMediaForDownloadDeletion = { [weak self] id in
                self?.playbackCoordinator?.releaseForDownloadDeletion(enclosureID: id)
            }
            self.transferCoordinator = MediaTransferCoordinator(core: core, isMediaInUse: { [weak self] enclosureID in
                self?.playbackCoordinator?.isUsing(enclosureID: enclosureID) ?? false
            }, presentationState: self.transferPresentationState)
            self.transferCoordinator?.onWorkChanged = { [weak store = self.store] in
                store?.refreshArticleAudioActions()
                store?.refreshListeningListIfVisible()
            }
            self.playbackCoordinator = MediaPlaybackCoordinator(core: core, presentationState: self.playbackPresentationState)
            self.playbackCoordinator?.onPlaybackUseChanged = { [weak self] in self?.transferCoordinator?.reconcile() }
            if let playbackCoordinator = self.playbackCoordinator {
                self.mediaRemoteControlCoordinator = MediaRemoteControlCoordinator(playbackCoordinator: playbackCoordinator, presentationState: self.playbackPresentationState)
            }
            self.popover.contentViewController = self.host()
            self.fallbackPanel?.contentViewController = self.host()
            self.transferCoordinator?.reconcile()
        }
        SystemNotificationManager.shared.configure()
        SystemNotificationManager.shared.onFeedSelected = { [weak self] feedID in
            guard let self else { return }
            self.show()
            self.store.selectNotificationFeed(feedID)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: 28)
        if let button = statusItem.button {
            button.image = Bundle.main.url(forResource: "FluxNewsTemplate", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
            button.image?.size = NSSize(width: 18, height: 18)
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.alignment = .left
            button.toolTip = "FluxNews"
            button.setAccessibilityLabel("FluxNews")
            button.target = self
            button.action = #selector(togglePopover)
        }
        countObservation = store.$unreadTotal.combineLatest(store.$hasPendingNewData).sink { [weak self] unreadTotal, hasPendingNewData in
            self?.updateStatusItem(unreadTotal: unreadTotal, hasPendingNewData: hasPendingNewData)
        }
        settingsObservation = store.$settingsVisible.removeDuplicates().sink { [weak self] visible in
            guard let self else { return }
            if visible {
                self.showSettingsWindow()
            } else if self.settingsWindowController?.window?.isVisible == true {
                self.settingsWindowController?.close()
            }
        }
        popover.behavior = .transient; popover.animates = true; popover.delegate = self; popover.contentSize = size(sidebarVisible: false); popover.contentViewController = host()
        AppRouter.shared.configure(open: { [weak self] route in self?.store.route(to: route); self?.show() }, refresh: { [weak self] in self?.show(); self?.store.sync(reason: .manual) }, widgetAction: { [weak self] action in self?.store.handleWidgetAction(action); self?.show() })
        readerWindow.onVisibilityChanged = { [weak self] visible in
            guard let self else { return }
            self.popover.behavior = visible ? .applicationDefined : .transient
        }
        store.onOpenDetail = { [weak self] article, togglesPreview in
            guard let self else { return }
            // Keep the timeline interactive while the coupled Reader takes focus.
            // The Reader reuses its existing panel and only replaces its article.
            self.popover.behavior = .applicationDefined
            self.readerWindow.show(
                article: article,
                togglesPreview: togglesPreview,
                preferredScreen: self.detailScreen()
            )
        }
        store.onInvalidateContent = { [weak self] in self?.readerWindow.hide() }
        catalogObservation = store.$catalog.dropFirst().removeDuplicates().sink { [weak self] catalog in
            AppRouter.shared.updateCatalog(catalog)
            self?.spotlightIndexer.update(catalog)
            FluxNewsShortcuts.updateAppShortcutParameters()
        }
        shortcutObservation = store.$globalShortcut.sink { [weak self] shortcut in
            guard let self else { return }
            let status = shortcutRegistrar.register(shortcut)
            if status == noErr { store.globalShortcutRegistrationError = nil }
            else {
                NativeLog.shortcut.error("global shortcut registration failed status=\(status, privacy: .public)")
                store.globalShortcutRegistrationError = "The selected global shortcut is unavailable. Choose another shortcut."
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        startNetworkMonitoring()
        store.start()
    }

    private func startNetworkMonitoring() {
        guard networkMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.store.networkAvailabilityChanged(isAvailable: available)
            }
        }
        networkMonitor = monitor
        monitor.start(queue: networkMonitorQueue)
    }

    @objc private func handleSystemWake(_ notification: Notification) {
        store.systemDidWake()
        transferCoordinator?.reconcile()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        playbackCoordinator?.applicationDidBecomeActive()
        store.resume()
        transferCoordinator?.reconcile()
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { _ = AppRouter.shared.handle(url: url) }
    }
    @objc private func togglePopover() { if popover.isShown || fallbackPanel?.isVisible == true { dismiss() } else { show() } }
    func popoverWillShow(_ notification: Notification) {
        lockStatusItemWidth()
        store.popoverVisible = true
        popover.contentSize = size(sidebarVisible: sidebarVisible)
    }
    func popoverDidClose(_ notification: Notification) {
        store.popoverVisible = false
        unlockStatusItemWidth()
        store.syncIfStale()
    }
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSPanel === fallbackPanel {
            store.popoverVisible = false
            unlockStatusItemWidth()
            store.syncIfStale()
            return
        }

        if notification.object as? NSWindow === settingsWindowController?.window {
            settingsWindowController = nil
            if store.settingsVisible {
                store.settingsVisible = false
            }
        }
    }
    func application(_ application: NSApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([NSUserActivityRestoring]) -> Void) -> Bool {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let route = SpotlightIndexer.route(from: identifier) else { return false }
        AppRouter.shared.open(route)
        return true
    }
    private func host() -> NSHostingController<PopoverContentView> {
        NSHostingController(
            rootView: PopoverContentView(
                store: store,
                playbackState: playbackPresentationState,
                playbackCoordinator: playbackCoordinator,
                transferState: transferPresentationState,
                layoutChanged: { [weak self] visible in
                    self?.resize(sidebarVisible: visible)
                },
                showSettings: { [weak self] in
                    self?.showSettingsWindow()
                },
                dismiss: { [weak self] in
                    self?.dismiss()
                }
            )
        )
    }
    private func show() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        lockStatusItemWidth()
        if let button = usableButton() {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        } else {
            showFallback()
        }
    }
    private func detailScreen() -> NSScreen? { popover.contentViewController?.view.window?.screen ?? fallbackPanel?.screen ?? statusItem.button?.window?.screen }
    private func usableButton() -> NSStatusBarButton? { guard let button = statusItem.button, let window = button.window, let screen = window.screen else { return nil }; return screen.frame.intersects(window.convertToScreen(button.convert(button.bounds, to: nil))) ? button : nil }
    private func dismiss() { if popover.isShown { popover.performClose(nil) }; fallbackPanel?.close() }
    private func showFallback() {
        lockStatusItemWidth()
        let panel = fallbackPanel ?? makeFallback()
        fallbackPanel = panel
        panel.setContentSize(size(sidebarVisible: sidebarVisible))
        store.popoverVisible = true
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }
    private func showSettingsWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let window = settingsWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let visibleFrame = NSScreen.main?.visibleFrame
        let width = min(820, max(680, (visibleFrame?.width ?? 900) - 80))
        // Accommodate all settings sections in the permanently visible sidebar.
        let height = min(650, max(540, (visibleFrame?.height ?? 730) - 80))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: width, height: height)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "FluxNews Settings"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: min(680, width), height: min(540, height))
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: SettingsView(store: store))
        window.center()

        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeFallback() -> NSPanel { let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size(sidebarVisible: sidebarVisible)), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false); panel.title = "FluxNews"; panel.isFloatingPanel = true; panel.level = .floating; panel.collectionBehavior = [.moveToActiveSpace, .transient]; panel.isReleasedWhenClosed = false; panel.delegate = self; panel.contentViewController = host(); return panel }
    private func resize(sidebarVisible: Bool) { self.sidebarVisible = sidebarVisible; let newSize = size(sidebarVisible: sidebarVisible); guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { popover.contentSize = newSize; fallbackPanel?.setContentSize(newSize); return }; if popover.isShown { NSAnimationContext.runAnimationGroup { $0.duration = PopoverLayout.animation; $0.allowsImplicitAnimation = true; popover.contentSize = newSize } } else { fallbackPanel?.setContentSize(newSize) } }
    private func updateStatusItem(unreadTotal: UInt64, hasPendingNewData: Bool) {
        guard let button = statusItem.button else { return }
        button.title = StatusItemPresentation.title(
            unreadTotal: unreadTotal,
            hasPendingNewData: hasPendingNewData
        )
        button.setAccessibilityValue(
            StatusItemPresentation.accessibilityValue(
                unreadTotal: unreadTotal,
                hasPendingNewData: hasPendingNewData
            )
        )

        if !statusItemWidthLocked {
            applyStatusItemWidth()
        }
    }

    private func applyStatusItemWidth() {
        guard let button = statusItem.button else { return }
        let width = max(28, ceil(button.intrinsicContentSize.width + 4))
        if abs(statusItem.length - width) > 0.5 {
            statusItem.length = width
        }
    }

    private func lockStatusItemWidth() {
        statusItemWidthLocked = true
    }

    private func unlockStatusItemWidth() {
        statusItemWidthLocked = false
        applyStatusItemWidth()
    }

    private func size(sidebarVisible: Bool) -> NSSize {
        let visibleHeight = statusItem.button?.window?.screen?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
            ?? PopoverLayout.visualHeight + PopoverLayout.verticalScreenMargin
        return NSSize(
            width: PopoverLayout.width(mode: store.articlePresentationMode, sidebarVisible: sidebarVisible),
            height: min(PopoverLayout.height(for: store.articlePresentationMode), max(320, visibleHeight - PopoverLayout.verticalScreenMargin))
        )
    }
}
