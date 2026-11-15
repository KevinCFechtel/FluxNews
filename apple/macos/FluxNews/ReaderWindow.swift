import AppKit
import Combine
import SwiftUI

@MainActor
final class ReaderWindowController: NSObject, ObservableObject {
    @Published fileprivate var article: ArticleSummary?
    @Published fileprivate var document: ReaderDocument?
    @Published fileprivate var isLoading = false
    @Published fileprivate var errorMessage: String?

    private weak var store: BrowserStore?
    private var panel: NSPanel?
    private var requests = ReaderRequestState()
    private var sharingPicker: NSSharingServicePicker?
    private var articlesObservation: AnyCancellable?
    var onVisibilityChanged: ((Bool) -> Void)?

    init(store: BrowserStore) {
        self.store = store
        super.init()
        articlesObservation = store.$articles.sink { [weak self] articles in self?.synchronizeArticleState(from: articles) }
    }

    func show(article: ArticleSummary, togglesPreview: Bool, preferredScreen: NSScreen?) {
        makePanelIfNeeded()
        guard let panel else { return }
        switch ReaderPreviewAction.resolve(isVisible: panel.isVisible, currentArticleID: self.article?.id, requestedArticleID: article.id, togglesSameArticle: togglesPreview) {
        case .hide:
            panel.orderOut(nil)
            return
        case .show:
            position(panel, on: preferredScreen ?? currentScreen())
        case .replace:
            break
        }
        let requestID = requests.begin()
        self.article = article
        document = nil
        errorMessage = nil
        isLoading = true
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        onVisibilityChanged?(true)
        store?.setRead(article, true)
        store?.loadReaderDocument(article) { [weak self] result in
            guard let self, self.requests.isCurrent(requestID) else { return }
            self.isLoading = false
            switch result {
            case let .success(document): self.document = document
            case let .failure(error): self.errorMessage = NativeErrorPresentation.message(for: error)
            }
        }
    }

    func openOriginal() {
        guard let url = article.flatMap({ URL(string: $0.url) }) else { return }
        NSWorkspace.shared.open(url)
    }

    func toggleStarred() {
        guard let article else { return }
        store?.setStarred(article, !article.isStarred) { [weak self] accepted in
            guard accepted, let self, self.article?.id == article.id else { return }
            self.article = ArticleSummary(id: article.id, feedId: article.feedId, categoryId: article.categoryId, feedTitle: article.feedTitle, title: article.title, url: article.url, commentsUrl: article.commentsUrl, publishedAt: article.publishedAt, isRead: article.isRead, isStarred: !article.isStarred, readingTimeMinutes: article.readingTimeMinutes, preview: article.preview, imageUrl: article.imageUrl)
            self.updateStarToolbarItem()
        }
    }

    @objc private func toggleStarredFromToolbar() { toggleStarred() }
    @objc private func shareFromToolbar(_ sender: NSButton) {
        guard let article, let url = URL(string: article.url) else { return }
        let picker = NSSharingServicePicker(items: [article.title, url])
        sharingPicker = picker
        picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }
    @objc private func openFromToolbar() { guard let article else { return }; store?.open(article) }
    @objc private func openOriginalFromToolbar() { openOriginal() }
    @objc private func showMoreMenu(_ sender: NSButton) { moreMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender) }
    @objc private func markUnread() { guard let article else { return }; store?.setRead(article, false) }
    @objc private func openInMiniflux() { guard let article else { return }; store?.openInMiniflux(article) }
    @objc private func openComments() { guard let article else { return }; store?.openComments(article) }
    @objc private func copyLink() { guard let article else { return }; store?.copyLink(article) }

    private func makePanelIfNeeded() {
        guard panel == nil else { return }
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame FluxNews.Reader")
        let panel = ReaderPreviewPanel(contentRect: NSRect(origin: .zero, size: ReaderPreviewGeometry.persistedSize()), styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .hudWindow], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.title = String(localized: "Detail Preview")
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .transient]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.titlebarAppearsTransparent = true
        let toolbar = NSToolbar(identifier: "FluxNews.Reader.Toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        panel.toolbar = toolbar
        panel.toolbarStyle = .unifiedCompact
        panel.titleVisibility = .hidden
        panel.contentViewController = ReaderVisualEffectViewController(rootView: ReaderWindowView(controller: self))
        self.panel = panel
    }

    private func position(_ panel: NSPanel, on screen: NSScreen?) {
        let size = ReaderPreviewGeometry.persistedSize()
        panel.setContentSize(size)
        let visibleFrame = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        panel.setFrameOrigin(ReaderPreviewGeometry.centeredFrame(size: panel.frame.size, visibleFrame: visibleFrame).origin)
    }

    func hide() {
        guard panel?.isVisible == true else { return }
        panel?.orderOut(nil)
        onVisibilityChanged?(false)
    }

    private func starImage(starred: Bool) -> NSImage? {
        let base = NSImage(
            systemSymbolName: starred ? "star.fill" : "star",
            accessibilityDescription: starred ? String(localized: "Unstar") : String(localized: "Star")
        )

        return base?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(
                pointSize: 16,
                weight: .regular
            )
        )
    }

    private func updateStarToolbarItem() {

        guard let item = panel?.toolbar?.items.first(where: { $0.itemIdentifier == .star }) else { return }
        let starred = article?.isStarred == true
        item.image = starImage(starred: starred)
        item.label = starred ? String(localized: "Unstar") : String(localized: "Star")
        item.paletteLabel = item.label
        item.toolTip = item.label
    }

    private func currentScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
    }

    private func synchronizeArticleState(from visibleArticles: [ArticleSummary]) {
        guard let article,
              let starred = ReaderArticleState.starredState(articleID: article.id, visibleArticles: visibleArticles.map { ($0.id, $0.isStarred) }),
              starred != article.isStarred else { return }
        self.article = ArticleSummary(id: article.id, feedId: article.feedId, categoryId: article.categoryId, feedTitle: article.feedTitle, title: article.title, url: article.url, commentsUrl: article.commentsUrl, publishedAt: article.publishedAt, isRead: article.isRead, isStarred: starred, readingTimeMinutes: article.readingTimeMinutes, preview: article.preview, imageUrl: article.imageUrl)
        updateStarToolbarItem()
    }
}

private final class ReaderPreviewPanel: NSPanel {
    override func cancelOperation(_ sender: Any?) { orderOut(sender) }
}

private final class ReaderVisualEffectViewController: NSViewController {
    private let rootView: ReaderWindowView

    init(rootView: ReaderWindowView) { self.rootView = rootView; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState
        let host = NSHostingController(rootView: rootView)
        addChild(host)
        host.view.frame = effect.bounds
        host.view.autoresizingMask = [.width, .height]
        effect.addSubview(host.view)
        view = effect
    }
}

extension NSToolbarItem.Identifier {
    static let star = Self("FluxNews.Reader.Star")
    static let share = Self("FluxNews.Reader.Share")
    static let open = Self("FluxNews.Reader.Open")
    static let more = Self("FluxNews.Reader.More")
}

extension ReaderWindowController: NSToolbarDelegate {
    nonisolated func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.star, .share, .open, .more, .flexibleSpace] }
    nonisolated func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, .star, .share, .open, .more] }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        switch itemIdentifier {
        case .star:
            let starred = article?.isStarred == true
            item.label = starred ? String(localized: "Unstar") : String(localized: "Star")
            item.paletteLabel = item.label
            item.toolTip = item.label
            item.image = starImage(starred: starred)
            item.target = self
            item.action = #selector(toggleStarredFromToolbar)
        case .share:
            item.label = String(localized: "Share")
            item.view = button(symbol: "square.and.arrow.up", label: String(localized: "Share"), action: #selector(shareFromToolbar(_:)))
        case .open:
            item.label = String(localized: "Open")
            item.view = button(symbol: "arrow.up.forward.app", label: String(localized: "Open"), action: #selector(openFromToolbar))
        case .more:
            item.label = String(localized: "More")
            item.view = button(symbol: "ellipsis", label: String(localized: "More"), action: #selector(showMoreMenu(_:)))
        default: return nil
        }
        return item
    }

    private func button(symbol: String, label: String, action: Selector?) -> NSButton {
      let baseImage = NSImage(
          systemSymbolName: symbol,
          accessibilityDescription: label
      )!

      let image = baseImage.withSymbolConfiguration(
          NSImage.SymbolConfiguration(
              pointSize: 16,
              weight: .regular
          )
      ) ?? baseImage
      let button = NSButton(image: image, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.toolTip = label
        button.setAccessibilityLabel(label)
        return button
    }

    private func moreMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: String(localized: "Mark as Unread"), action: #selector(markUnread), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Open Original"), action: #selector(openOriginalFromToolbar), keyEquivalent: "").target = self
        menu.addItem(withTitle: String(localized: "Open in Miniflux"), action: #selector(openInMiniflux), keyEquivalent: "").target = self
        if article?.commentsUrl.isEmpty == false { menu.addItem(withTitle: String(localized: "Open Comments"), action: #selector(openComments), keyEquivalent: "").target = self }
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Copy Link"), action: #selector(copyLink), keyEquivalent: "").target = self
        return menu
    }
}

extension ReaderWindowController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        onVisibilityChanged?(false)
        return false
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel, panel.isVisible, let contentView = panel.contentView else { return }
        ReaderPreviewGeometry.persist(size: contentView.bounds.size)
    }
}

private struct ReaderWindowView: View {
    @ObservedObject var controller: ReaderWindowController

    var body: some View {
        VStack(spacing: 0) {
            if let article = controller.article { ReaderArticleHeader(article: article) }
            Group {
                if controller.isLoading { ProgressView("Loading article...") }
                else if let error = controller.errorMessage { ContentUnavailableView("Unable to load article", systemImage: "exclamationmark.triangle", description: Text(error)) }
                else if let document = controller.document { ReaderDocumentView(document: document, openOriginal: controller.openOriginal) }
                else { ContentUnavailableView("No article selected", systemImage: "doc.text") }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            KeyboardCommandObserver { command in
                if command == .openDetail || command == .dismiss { controller.hide() }
            }
        }
        .environment(\.openURL, OpenURLAction { url in NSWorkspace.shared.open(url); return .handled })
    }
}

private struct ReaderDocumentView: View {
    let document: ReaderDocument
    let openOriginal: () -> Void
    var body: some View {
        ScrollView {
            ReaderDocumentContent(document: document, openOriginal: openOriginal)
        }.textSelection(.enabled)
    }
}
