import AppKit
import XCTest
@testable import FluxNews

@MainActor
final class MacScrolloverEndPolicyTests: XCTestCase {
    private func article(_ id: Int64, read: Bool = false) -> ArticleSummary {
        ArticleSummary(id: id, feedId: 1, categoryId: 1, feedTitle: "Feed",
            title: "Article", url: "https://example.test", commentsUrl: "",
            publishedAt: "2026-10-17T10:00:00Z", isRead: read, isStarred: false,
            readingTimeMinutes: 0, preview: "", imageUrl: nil)
    }

    func testEndMarksOnlyVisibleUnreadTailInListOrder() {
        let items = [article(1), article(2, read: true), article(3), article(4)]
        XCTAssertEqual(MacScrolloverEndPolicy.remainingUnreadIDs(
            articles: items, visibleIDs: [2, 3, 4], atBottom: true,
            forwardScrollArmed: true), [3, 4])
    }

    func testNoEndCompletionBeforeBottomOrWithoutForwardScroll() {
        let items = [article(1), article(2)]
        for (atBottom, armed) in [(false, true), (true, false)] {
            XCTAssertTrue(MacScrolloverEndPolicy.remainingUnreadIDs(
                articles: items, visibleIDs: [1, 2], atBottom: atBottom,
                forwardScrollArmed: armed).isEmpty)
        }
        XCTAssertTrue(MacScrolloverEndPolicy.remainingUnreadIDs(
            articles: items, visibleIDs: [1], atBottom: true,
            forwardScrollArmed: true).isEmpty)
    }
}

@MainActor
final class BrowserPresentationTests: XCTestCase {
    func testMacMediaArtworkProbeParityWithIOSAndUsesSessionBoundCore() throws {
        let project = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let browser = try String(contentsOf: project.appendingPathComponent("FluxNews/BrowserStore.swift"), encoding: .utf8)
        let list = try String(contentsOf: project.appendingPathComponent("FluxNews/ListeningListViews.swift"), encoding: .utf8)
        let player = try String(contentsOf: project.appendingPathComponent("FluxNews/PlayerView.swift"), encoding: .utf8)

        XCTAssertTrue(browser.contains("func requestMediaArtworkProbe(articleID: Int64)"))
        XCTAssertTrue(browser.contains("try core.probeMediaArtwork(enclosureId: enclosureID)"))
        XCTAssertTrue(browser.contains("self.requestMediaArtworkProbe(articleID: articleID)"))
        XCTAssertTrue(browser.contains("if source == nil { self.enqueueMediaArtworkProbes([enclosureID]) }"))
        XCTAssertTrue(browser.contains("if case .success(true) = result"))
        XCTAssertTrue(browser.contains("self.core === core"))
        XCTAssertTrue(browser.contains("artworkProbeInFlight"))
        XCTAssertTrue(list.contains("store.artworkProbeRevisions["))
        XCTAssertTrue(player.contains("store.artworkProbeRevisions["))
    }

    func testHostATSAllowsUserSuppliedHTTPMediaWithoutChangingWidgetPolicy() throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let hostData = try Data(contentsOf: project.appendingPathComponent("FluxNews/Info.plist"))
        let host = try XCTUnwrap(PropertyListSerialization.propertyList(from: hostData, format: nil) as? [String: Any])
        let ats = try XCTUnwrap(host["NSAppTransportSecurity"] as? [String: Any])
        XCTAssertEqual(ats["NSAllowsArbitraryLoads"] as? Bool, true)
        XCTAssertNil(ats["NSAllowsArbitraryLoadsForMedia"])

        let widgetData = try Data(contentsOf: project.appendingPathComponent("FluxNewsWidgets/Info.plist"))
        let widget = try XCTUnwrap(PropertyListSerialization.propertyList(from: widgetData, format: nil) as? [String: Any])
        XCTAssertNil(widget["NSAppTransportSecurity"])
    }

    func testBrowserStoreUsesSharedAppleCoreExecutionBoundary() throws {
        let macosDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: macosDirectory.appendingPathComponent("FluxNews/BrowserStore.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("AppleCoreSessionExecutionCoordinator()"))
        XCTAssertTrue(source.contains("navigationProjection(countMode:"))
        XCTAssertFalse(source.contains("fatalError(\"Scope has no article query\")"))
        XCTAssertFalse(source.contains("store.value?.searchPageSize"))

        // The only detached work left in BrowserStore is CPU-only image preparation.
        XCTAssertEqual(source.components(separatedBy: "Task.detached").count - 1, 2)
        XCTAssertTrue(source.contains("exportConfigBackup(input: input, password: password)"))
        XCTAssertTrue(source.contains("parseConfigBackup(bytes: bytes, password: password"))
        XCTAssertTrue(source.contains("defer { self?.feedIconRequests.complete(key) }"))
        XCTAssertTrue(source.contains("defer { self?.articleThumbnailRequests.complete(key) }"))
        XCTAssertTrue(source.contains("guard self.core === core else { return }"))
        XCTAssertTrue(source.contains("feedIconRequests = FeedIconRequestState()"))
        XCTAssertTrue(source.contains("articleThumbnailRequests = ArticleThumbnailRequestState()"))
        XCTAssertTrue(source.contains("blockingCancellableResult("))
        XCTAssertTrue(source.contains("syncCancellable(reason: reason, cancellation: cancellation)"))
        XCTAssertFalse(source.contains("reloadLiveUnreadTotal()"))
    }

    func testStartupScopeResolvesKnownTargets() {
        XCTAssertEqual(StartupScopeResolver.resolve(.allNews, categoryID: nil, feedID: nil, categoryIDs: [7], feedIDs: [42]), .all)
        XCTAssertEqual(StartupScopeResolver.resolve(.starred, categoryID: nil, feedID: nil, categoryIDs: [7], feedIDs: [42]), .starred)
        XCTAssertEqual(StartupScopeResolver.resolve(.category, categoryID: 7, feedID: nil, categoryIDs: [7], feedIDs: [42]), .category(7))
        XCTAssertEqual(StartupScopeResolver.resolve(.feed, categoryID: nil, feedID: 42, categoryIDs: [7], feedIDs: [42]), .feed(42))
    }

    func testStartupScopeFallsBackForMissingTarget() {
        XCTAssertEqual(StartupScopeResolver.resolve(.category, categoryID: 7, feedID: nil, categoryIDs: [], feedIDs: []), .all)
        XCTAssertEqual(StartupScopeResolver.resolve(.feed, categoryID: nil, feedID: 42, categoryIDs: [], feedIDs: []), .all)
    }

    func testHideEmptyFiltersFeedsAndThenCategories() {
        let feeds = [NavigationPresentationFeed(id: 1, categoryID: 10), .init(id: 2, categoryID: 10), .init(id: 3, categoryID: 20)]
        let visible = NavigationVisibility.visibleFeeds(feeds, hidingEmpty: true, counts: [1: 0, 2: 3, 3: 0])

        XCTAssertEqual(visible, [.init(id: 2, categoryID: 10)])
        XCTAssertEqual(NavigationVisibility.visibleCategoryIDs([10, 20], feeds: visible), [10])
        XCTAssertEqual(NavigationVisibility.visibleFeeds(feeds, hidingEmpty: false, counts: [:]), feeds)
    }

    func testRemoveOnReadOnlyAppliesToUnreadLocalSnapshots() {
        XCTAssertTrue(ArticleListPresentationPolicy.removesMarkedReadArticle(removeWhenMarkedRead: true, unreadOnly: true, scope: .all))
        XCTAssertFalse(ArticleListPresentationPolicy.removesMarkedReadArticle(removeWhenMarkedRead: false, unreadOnly: true, scope: .all))
        XCTAssertFalse(ArticleListPresentationPolicy.removesMarkedReadArticle(removeWhenMarkedRead: true, unreadOnly: false, scope: .all))
        XCTAssertFalse(ArticleListPresentationPolicy.removesMarkedReadArticle(removeWhenMarkedRead: true, unreadOnly: true, scope: .search))
        XCTAssertFalse(ArticleListPresentationPolicy.removesMarkedReadArticle(removeWhenMarkedRead: true, unreadOnly: true, scope: .listeningList))
    }

    func testListeningListScopeAndDefaults() {
        let store = BrowserStore()
        XCTAssertEqual(store.scope, .all)
        XCTAssertEqual(store.listeningListSort, .recentlyAdded)
        XCTAssertNil(store.listeningListFeedID)
        XCTAssertEqual(BrowserScope.listeningList, .listeningList)
    }

    func testVisualAndCompactActionsStartBelowFullWidthFeedRow() {
        XCTAssertEqual(ArticleHoverActionsLayout.anchor(for: .visual), .adjacentBelowMetadata)
        XCTAssertEqual(ArticleHoverActionsLayout.anchor(for: .visualCompact), .trailingThumbnail)
        XCTAssertEqual(ArticleHoverActionsLayout.anchor(for: .compact), .adjacentBelowMetadata)
    }

    func testCompactPlacesFullWidthMetadataBeforeHoverActions() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FluxNews/ArticleRowView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let compactStart = try XCTUnwrap(source.range(of: "    private var compact: some View {"))
        let compactEnd = try XCTUnwrap(source.range(
            of: "    private var articleTextBelowMetadata: some View {",
            range: compactStart.upperBound..<source.endIndex
        ))
        let compact = String(source[compactStart.lowerBound..<compactEnd.lowerBound])
        let feed = try XCTUnwrap(compact.range(of: "metadata"))
        let actions = try XCTUnwrap(compact.range(of: "quickActions"))
        XCTAssertLessThan(feed.lowerBound, actions.lowerBound)
        XCTAssertTrue(compact.contains("metadata\n                        .frame(maxWidth: .infinity"))
        XCTAssertTrue(compact.contains("HStack(alignment: .top, spacing: 10)"))
        XCTAssertFalse(compact.contains("semanticTextComposition"))
    }

    func testHoverActionHeightFitsAllThreeFullSizeControls() {
        XCTAssertEqual(ArticleHoverActionsLayout.controlSize, 28)
        XCTAssertEqual(ArticleHoverActionsLayout.minimumOverlayHeight, 94)
    }

    func testVisualCompactHoverActionsRequireFourHundredMillisecondPointerDwell() {
        XCTAssertEqual(ArticleHoverActionsLayout.hoverRevealDelayNanoseconds, 400_000_000)
    }

    func testVisualCompactPreviewFlowsAroundRightThumbnail() {
        let exclusion = VisualCompactFlowMetrics.exclusionRect(width: 342)
        XCTAssertEqual(exclusion.minX, 218)
        XCTAssertEqual(exclusion.width, 124)
        XCTAssertEqual(exclusion.minY, 0)
        XCTAssertEqual(exclusion.height, 94)
    }

    func testVisualCompactWithoutImageDoesNotInsertGapBeforePreview() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FluxNews/ArticleRowView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let noImageStart = try XCTUnwrap(source.range(of: "// No thumbnail: never reserve"))
        let noImageEnd = try XCTUnwrap(source.range(
            of: "            audioActions",
            range: noImageStart.lowerBound..<source.endIndex
        ))
        let noImageLayout = String(source[noImageStart.lowerBound..<noImageEnd.lowerBound])
        let preview = try XCTUnwrap(noImageLayout.range(of: "Text(article.preview)"))
        let minimumHeight = try XCTUnwrap(noImageLayout.range(
            of: ".frame(minHeight: ArticleHoverActionsLayout.minimumOverlayHeight"
        ))
        XCTAssertLessThan(preview.lowerBound, minimumHeight.lowerBound)
        XCTAssertFalse(noImageLayout.contains("ThumbnailSlot("))
        XCTAssertTrue(noImageLayout.contains(".overlay(alignment: .topTrailing) { hoverActions }"))
    }

    func testVisualCompactTypographyUsesNativeSemanticTextStyles() {
        let expectedPreview = NSFont.preferredFont(forTextStyle: .subheadline)
        XCTAssertEqual(VisualCompactFlowTypography.previewFont.fontName, expectedPreview.fontName)
        XCTAssertEqual(VisualCompactFlowTypography.previewFont.pointSize, expectedPreview.pointSize)

        let expectedDate = NSFont.preferredFont(forTextStyle: .caption1)
        XCTAssertEqual(VisualCompactFlowTypography.dateFont.fontName, expectedDate.fontName)
        XCTAssertEqual(VisualCompactFlowTypography.dateFont.pointSize, expectedDate.pointSize)
    }

    func testArticlePresentationModesUseVisualAsDefaultAndCanonicalValues() {
        XCTAssertEqual(ArticlePresentationMode.allCases, [.visual, .visualCompact, .compact])
        // macOS now renders `visualCompact` as its own side-thumbnail layout,
        // while retaining the same persisted canonical value as the other clients.
        XCTAssertEqual(ArticlePresentationMode(rawValue: "visualCompact"), .visualCompact)
        XCTAssertTrue(ArticlePresentationMode.visualCompact.showsArticleImage)
        XCTAssertEqual(ArticlePresentationMode(rawValue: "visual"), .visual)
        XCTAssertEqual(ArticlePresentationMode(rawValue: "compact"), .compact)
        XCTAssertTrue(ArticlePresentationMode.visual.showsArticleImage)
        XCTAssertFalse(ArticlePresentationMode.compact.showsArticleImage)

        let defaults = UserDefaults.standard
        let key = "FluxNews.articlePresentationMode"
        let previous = defaults.object(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        defaults.removeObject(forKey: key)
        XCTAssertEqual(BrowserStore().articlePresentationMode, .visual)

        let store = BrowserStore()
        store.setArticlePresentationMode(.compact)
        XCTAssertEqual(defaults.string(forKey: key), "compact")
        store.setArticlePresentationMode(.visual)
        XCTAssertEqual(defaults.string(forKey: key), "visual")
    }

    func testArticlePresentationLayoutUsesDistinctModeDimensionsAndSidebarWidth() {
        XCTAssertEqual(PopoverLayout.contentWidth(for: .visual), 390)
        XCTAssertEqual(PopoverLayout.height(for: .visual), 760)
        XCTAssertEqual(PopoverLayout.width(mode: .visual, sidebarVisible: false), 390)
        XCTAssertEqual(PopoverLayout.width(mode: .visual, sidebarVisible: true), 630)

        XCTAssertEqual(PopoverLayout.contentWidth(for: .visualCompact), 390)
        XCTAssertEqual(PopoverLayout.height(for: .visualCompact), 760)
        XCTAssertEqual(PopoverLayout.width(mode: .visualCompact, sidebarVisible: true), 630)

        XCTAssertEqual(PopoverLayout.contentWidth(for: .compact), 500)
        XCTAssertEqual(PopoverLayout.height(for: .compact), 520)
        XCTAssertEqual(PopoverLayout.width(mode: .compact, sidebarVisible: false), 500)
        XCTAssertEqual(PopoverLayout.width(mode: .compact, sidebarVisible: true), 740)
    }

    func testSharedArticleTemporalPresentationFormatsReadingTimeAndPublication() {
        XCTAssertNil(ArticleTemporalPresentation.readingTime(0))
        XCTAssertNotNil(ArticleTemporalPresentation.readingTime(4))

        let published = "2026-01-01T12:00:00Z"
        let reference = Date(timeIntervalSince1970: 1_767_268_800)
        XCTAssertFalse(
            ArticleTemporalPresentation.publicationValue(
                published,
                showRelative: false,
                relativeTo: reference
            ).isEmpty
        )
        XCTAssertFalse(
            ArticleTemporalPresentation.publicationValue(
                published,
                showRelative: true,
                relativeTo: reference
            ).isEmpty
        )
    }

    func testMediaTransferReconciliationUsesExistingWakeupCallback() {
        let store = BrowserStore()
        var callbackCount = 0
        store.onMediaTransferRequested = { callbackCount += 1 }

        store.requestMediaTransferReconciliation()

        XCTAssertEqual(callbackCount, 1)
    }

    func testArticleAudioActionsUseBatchStateWithoutSelection() {
        let enclosure = Enclosure(id: 1, articleId: 7, url: "https://example.test/audio.mp3", mimeType: "audio/mpeg", sizeBytes: nil, remoteMediaProgressionSeconds: 0, mediaKind: .audio)
        let state = ArticleAudioActionState(articleID: 7, enclosures: [enclosure], isInListeningList: false, downloads: [:])

        XCTAssertTrue(ArticleAudioActions.shouldRender(state, transferStateAvailable: true))
        XCTAssertFalse(ArticleAudioActions.shouldRender(nil, transferStateAvailable: true))
        XCTAssertFalse(ArticleAudioActions.shouldRender(state, transferStateAvailable: false))
    }

    func testListeningListFeedSelectionFallsBackWhenFeedIsNoLongerRepresented() {
        let feeds = [ListeningListFeed(feedId: 11, feedTitle: "News", itemCount: 1)]
        XCTAssertEqual(ListeningListPresentation.validatedFeedID(11, feeds: feeds), 11)
        XCTAssertNil(ListeningListPresentation.validatedFeedID(12, feeds: feeds))
        XCTAssertNil(ListeningListPresentation.validatedFeedID(nil, feeds: feeds))
    }

    func testListeningListUsesOneNewsRowAndActiveEnclosureForPlayback() {
        let first = listeningEnclosure(id: 1, positionMs: 12_000, durationMs: 45_000, status: .inProgress)
        let second = listeningEnclosure(id: 2, positionMs: 3_000, durationMs: 8_000, status: .inProgress)
        let item = listeningItem(enclosures: [first, second], activeID: 2)

        XCTAssertEqual(item.articleId, 7)
        XCTAssertNil(ListeningListPresentation.preferredEnclosure(listeningItem(enclosures: [first, second], activeID: nil)))
        XCTAssertEqual(ListeningListPresentation.preferredEnclosure(item)?.id, 2)
        XCTAssertEqual(ListeningListPresentation.progress(item)?.positionMs, 3_000)
        XCTAssertEqual(ListeningListPresentation.progress(item)?.durationMs, 8_000)
    }

    func testM2ArtworkPrefersLoadedThenActiveThenFirstEnclosure() {
        let first = listeningEnclosure(id: 1, positionMs: 0, durationMs: nil, status: .notStarted)
        let second = listeningEnclosure(id: 2, positionMs: 0, durationMs: nil, status: .notStarted)
        let selected = listeningItem(enclosures: [first, second], activeID: 2)

        XCTAssertEqual(ListeningListPresentation.artworkEnclosure(selected, loadedEnclosureID: 1)?.enclosure.id, 1)
        XCTAssertEqual(ListeningListPresentation.artworkEnclosure(selected, loadedEnclosureID: nil)?.enclosure.id, 2)
        XCTAssertEqual(
            ListeningListPresentation.artworkEnclosure(
                listeningItem(enclosures: [first, second], activeID: nil),
                loadedEnclosureID: nil
            )?.enclosure.id,
            1
        )
        XCTAssertNil(ListeningListPresentation.artworkEnclosure(
            listeningItem(enclosures: [], activeID: nil),
            loadedEnclosureID: nil
        ))
    }

    func testM2ArtworkRefreshTokenTracksEnclosureAndDownloadChanges() {
        let first = listeningEnclosure(id: 1, positionMs: 0, durationMs: nil, status: .notStarted)
        let next = listeningEnclosure(id: 2, positionMs: 0, durationMs: nil, status: .notStarted)
        let downloaded = listeningEnclosure(
            id: 1, positionMs: 0, durationMs: nil, status: .notStarted,
            downloadState: .downloaded
        )
        XCTAssertNotEqual(
            ListeningListPresentation.artworkRefreshToken(first),
            ListeningListPresentation.artworkRefreshToken(next)
        )
        XCTAssertNotEqual(
            ListeningListPresentation.artworkRefreshToken(first),
            ListeningListPresentation.artworkRefreshToken(downloaded)
        )
        XCTAssertEqual(ListeningListPresentation.artworkRefreshToken(nil), "none")
    }

    func testM2PlaybackActionOnlyPausesCurrentPlayingEnclosure() {
        XCTAssertTrue(ListeningListPresentation.shouldPause(
            enclosureID: 5, loadedEnclosureID: 5, isPlaying: true
        ))
        XCTAssertFalse(ListeningListPresentation.shouldPause(
            enclosureID: 5, loadedEnclosureID: 5, isPlaying: false
        ))
        XCTAssertFalse(ListeningListPresentation.shouldPause(
            enclosureID: 5, loadedEnclosureID: 6, isPlaying: true
        ))
    }

    func testM2ArtworkViewRetainsAsyncScrollCancellationAndDownsampling() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("FluxNews")
        let source = try String(
            contentsOf: folder.appendingPathComponent("ListeningListViews.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("MacListeningListArtworkView("))
        XCTAssertTrue(source.contains(".task(id: refreshToken"))
        XCTAssertTrue(source.contains("guard !Task.isCancelled"))
        XCTAssertTrue(source.contains("CGImageSourceCreateThumbnailAtIndex"))
        XCTAssertTrue(source.contains("NSCache<NSString, NSImage>()"))
        XCTAssertTrue(source.contains("onOpenPlayer(item.articleId)"))
    }

    func testListeningListProgressStatesAvoidMisleadingNotStartedAndUnknownDuration() {
        let notStarted = listeningItem(enclosures: [listeningEnclosure(id: 1, positionMs: 0, durationMs: 42_000, status: .notStarted)], activeID: 1)
        XCTAssertNil(ListeningListPresentation.progress(notStarted))

        let unknown = listeningItem(enclosures: [listeningEnclosure(id: 1, positionMs: 28 * 60_000, durationMs: nil, status: .inProgress)], activeID: 1)
        XCTAssertEqual(ListeningListPresentation.progress(unknown)?.positionMs, 28 * 60_000)
        XCTAssertNil(ListeningListPresentation.progress(unknown)?.durationMs)

        let completed = listeningItem(enclosures: [listeningEnclosure(id: 1, positionMs: 42_000, durationMs: 42_000, status: .completed)], activeID: 1)
        XCTAssertEqual(ListeningListPresentation.progress(completed)?.status, .completed)
    }

    func testListeningListUnplayedIndicatorRequiresEveryAudioToBeUnstarted() {
        let first = listeningEnclosure(id: 1, positionMs: 0, durationMs: nil, status: .notStarted)
        let second = listeningEnclosure(id: 2, positionMs: 0, durationMs: nil, status: .notStarted)
        let partial = listeningEnclosure(id: 2, positionMs: 1_000, durationMs: 10_000, status: .inProgress)
        let finished = listeningEnclosure(id: 1, positionMs: 10_000, durationMs: 10_000, status: .completed)

        XCTAssertTrue(ListeningListPresentation.isUnplayed(listeningItem(enclosures: [first, second], activeID: nil)))
        XCTAssertFalse(ListeningListPresentation.isUnplayed(listeningItem(enclosures: [first, partial], activeID: nil)))
        XCTAssertFalse(ListeningListPresentation.isUnplayed(listeningItem(enclosures: [finished], activeID: 1)))
        XCTAssertFalse(ListeningListPresentation.isUnplayed(listeningItem(enclosures: [], activeID: nil)))
    }

    func testListeningListProgressClampsInconsistentPositionAndIgnoresZeroDuration() {
        let inconsistent = listeningItem(enclosures: [listeningEnclosure(id: 1, positionMs: 90_000, durationMs: 42_000, status: .inProgress)], activeID: 1)
        XCTAssertEqual(ListeningListPresentation.progress(inconsistent)?.positionMs, 42_000)

        let zeroDuration = listeningItem(enclosures: [listeningEnclosure(id: 1, positionMs: 12_000, durationMs: 0, status: .inProgress)], activeID: 1)
        XCTAssertNil(ListeningListPresentation.progress(zeroDuration)?.durationMs)
    }

    func testMediaTextFallbackTreatsWhitespaceAsMissing() {
        XCTAssertEqual(ListeningListPresentation.textOrFallback("  \n", fallback: "Untitled News"), "Untitled News")
        XCTAssertEqual(ListeningListPresentation.textOrFallback("Episode", fallback: "Untitled News"), "Episode")
    }

    func testListeningListDownloadSummarySupportsSingleAndMultipleEnclosures() {
        let downloaded = listeningEnclosure(id: 1, positionMs: 0, durationMs: nil, status: .notStarted, downloadState: .downloaded)
        let pending = listeningEnclosure(id: 2, positionMs: 0, durationMs: nil, status: .notStarted, downloadState: .requested)
        let item = listeningItem(enclosures: [downloaded, pending], activeID: nil)

        XCTAssertEqual(ListeningListPresentation.downloadedCount(item).downloaded, 1)
        XCTAssertEqual(ListeningListPresentation.downloadedCount(item).total, 2)
        XCTAssertEqual(ListeningListPresentation.downloadedCount(item).pending, 1)
        XCTAssertEqual(ListeningListPresentation.downloadedCount(listeningItem(enclosures: [downloaded], activeID: 1)).downloaded, 1)
    }


    func testC31StarredScopeAlwaysIncludesReadAndUnreadArticles() {
        let store = BrowserStore()
        store.scope = .starred
        store.unreadOnly = true
        let unreadOnlyEnabled = store.query()
        XCTAssertEqual(unreadOnlyEnabled?.readFilter, .all)
        XCTAssertEqual(unreadOnlyEnabled?.starredFilter, .starred)

        store.unreadOnly = false
        let unreadOnlyDisabled = store.query()
        XCTAssertEqual(unreadOnlyDisabled?.readFilter, .all)
        XCTAssertEqual(unreadOnlyDisabled?.starredFilter, .starred)
        XCTAssertEqual(ScopeReadActionPolicy.unreadQuery(from: try! XCTUnwrap(unreadOnlyDisabled)).readFilter, .unread)

        store.scope = .all
        store.unreadOnly = true
        XCTAssertEqual(store.query()?.readFilter, .unread)
    }

    func testC31MarkAllAndNextVisibilityAndLastSibling() {
        XCTAssertTrue(ScopeReadActionPolicy.supportsMarkAll(.all))
        XCTAssertTrue(ScopeReadActionPolicy.supportsMarkAll(.starred))
        XCTAssertTrue(ScopeReadActionPolicy.supportsMarkAll(.feed(1)))
        XCTAssertTrue(ScopeReadActionPolicy.supportsMarkAll(.category(10)))
        XCTAssertFalse(ScopeReadActionPolicy.supportsMarkAll(.search))
        XCTAssertFalse(ScopeReadActionPolicy.supportsMarkAll(.listeningList))

        let feeds: [FluxNews.NavigationPresentationFeed] = [
            .init(id: 1, categoryID: 10), .init(id: 2, categoryID: 10),
            .init(id: 3, categoryID: 20)
        ]
        let counts: [Int64: UInt64] = [1: 1, 2: 0, 3: 2]
        func next(_ scope: FluxNews.BrowserScope, hidden: Bool = true) -> FluxNews.BrowserScope? {
            ScopeReadActionPolicy.nextVisibleScope(
                after: scope, categoryIDs: [10, 20], feeds: feeds,
                hidingEmpty: hidden, counts: counts
            )
        }
        XCTAssertEqual(next(.feed(1)), .feed(3))
        XCTAssertEqual(next(.feed(1), hidden: false), .feed(2))
        XCTAssertNil(next(.feed(3)))
        XCTAssertNil(next(.feed(2)))
        XCTAssertEqual(next(.category(10)), .category(20))
        XCTAssertNil(next(.category(20)))
        XCTAssertNil(next(.starred))
        XCTAssertNil(next(.all))
        XCTAssertNil(next(.search))
        XCTAssertNil(next(.listeningList))
    }


    func testC32BulkFeedSelectionPreservesHiddenFeedsAndRemovesDeletedFeeds() {
        let selected = BulkFeedSettingsPolicy.selectVisible([2, 3], retaining: Set<Int64>([1]))
        XCTAssertEqual(selected, Set<Int64>([1, 2, 3]))
        XCTAssertEqual(
            BulkFeedSettingsPolicy.reconcile(selected, availableIDs: [1, 3, 4]),
            Set<Int64>([1, 3])
        )
        XCTAssertTrue(BulkFeedSettingsPolicy.reconcile([1, 2], availableIDs: []).isEmpty)
    }

    func testC32MixedValuesNeverBecomeAnImplicitPreferencePatch() {
        XCTAssertNil(BulkFeedSettingsPolicy.commonValue([true, false]))
        XCTAssertNil(BulkFeedSettingsPolicy.commonValue([DetailRenderingMode.rendered, .textOnly]))
        XCTAssertNil(BulkFeedSettingsPolicy.commonValue([Bool]()))
        XCTAssertEqual(BulkFeedSettingsPolicy.commonValue([true, true, true]), true)
        XCTAssertEqual(
            BulkFeedSettingsPolicy.commonValue([DetailRenderingMode.textOnly, .textOnly]),
            .textOnly
        )

        let patch = FeedPreferencesPatch(
            systemNotificationsEnabled: nil,
            detailRendering: nil,
            truncateDetail: true,
            openInMiniflux: nil,
            autoDownloadAudio: nil
        )
        XCTAssertEqual(patch.truncateDetail, true)
        XCTAssertNil(patch.detailRendering)
        XCTAssertNil(patch.systemNotificationsEnabled)
        XCTAssertNil(patch.openInMiniflux)
        XCTAssertNil(patch.autoDownloadAudio)
    }

    func testC36BackgroundRecoveryRequiresPreferenceConnectionAndNoActiveSync() {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        func allowed(configured: Bool = true, enabled: Bool = true,
                     available: Bool? = true, inFlight: Bool = false,
                     last: Date? = nil) -> Bool {
            BackgroundRecoveryPolicy.shouldAttempt(
                configured: configured, backgroundEnabled: enabled,
                networkAvailable: available, syncInFlight: inFlight,
                lastAttempt: last, now: now
            )
        }
        XCTAssertTrue(allowed())
        XCTAssertTrue(allowed(available: nil)) // Before first network callback.
        XCTAssertFalse(allowed(configured: false))
        XCTAssertFalse(allowed(enabled: false))
        XCTAssertFalse(allowed(available: false))
        XCTAssertFalse(allowed(inFlight: true))
        XCTAssertFalse(allowed(last: now.addingTimeInterval(-10)))
        XCTAssertFalse(allowed(last: now.addingTimeInterval(-59)))
        XCTAssertTrue(allowed(last: now.addingTimeInterval(-60)))
        XCTAssertTrue(allowed(last: now.addingTimeInterval(-900)))
    }

    func testC36NetworkRecoveryOnlyFiresOnActualReconnect() {
        var state = NetworkRecoveryState()
        XCTAssertFalse(state.observe(isAvailable: true)) // Initial online, no duplicate startup sync.
        XCTAssertFalse(state.observe(isAvailable: true))
        XCTAssertFalse(state.observe(isAvailable: false))
        XCTAssertFalse(state.observe(isAvailable: false))
        XCTAssertTrue(state.observe(isAvailable: true))
        XCTAssertFalse(state.observe(isAvailable: true))
        XCTAssertFalse(state.observe(isAvailable: false))
        XCTAssertTrue(state.observe(isAvailable: true)) // A second real reconnect.
    }

    func testC36FirstOfflineThenOnlineTriggersRecovery() {
        var state = NetworkRecoveryState()
        XCTAssertFalse(state.observe(isAvailable: false))
        XCTAssertTrue(state.observe(isAvailable: true))
    }

    func testC36LifecycleObserversExistAndUseSingleRecoveryGate() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let appDelegate = try String(contentsOf: root.appendingPathComponent("FluxNews/AppDelegate.swift"), encoding: .utf8)
        let store = try String(contentsOf: root.appendingPathComponent("FluxNews/BrowserStore.swift"), encoding: .utf8)
        XCTAssertTrue(appDelegate.contains("NSWorkspace.didWakeNotification"))
        XCTAssertTrue(appDelegate.contains("NWPathMonitor()"))
        XCTAssertTrue(appDelegate.contains("networkMonitor?.cancel()"))
        XCTAssertTrue(store.contains("BackgroundRecoveryPolicy.shouldAttempt("))
        XCTAssertTrue(store.contains("networkRecoveryState.observe(isAvailable: isAvailable)"))
        XCTAssertTrue(store.contains("syncIfStale(reason: .resume)"))
        XCTAssertTrue(store.contains("lastSyncAttempt = .now"))
    }

    private func listeningItem(enclosures: [ListeningListEnclosure], activeID: Int64?) -> ListeningListItem {
        ListeningListItem(articleId: 7, feedId: 11, title: "Episode", feedTitle: "Feed", publishedAt: "2026-01-01T00:00:00Z", addedAt: "2026-01-02T00:00:00Z", remotePresent: true, audioEnclosures: enclosures, activeEnclosureId: activeID)
    }

    private func listeningEnclosure(id: Int64, positionMs: UInt64, durationMs: UInt64?, status: PlaybackStatus, downloadState: DownloadState? = nil) -> ListeningListEnclosure {
        let enclosure = Enclosure(id: id, articleId: 7, url: "https://example.test/\(id).mp3", mimeType: "audio/mpeg", sizeBytes: nil, remoteMediaProgressionSeconds: 0, mediaKind: .audio)
        let playback = PlaybackState(enclosureId: id, positionMs: positionMs, durationMs: durationMs, status: status, updatedAt: nil)
        let download = downloadState.map { MediaDownload(enclosureId: id, state: $0, origin: .manual, localFile: nil, fileSizeBytes: nil, downloadedAt: nil, failureKind: nil) }
        return ListeningListEnclosure(enclosure: enclosure, remotePresent: true, playbackState: playback, download: download, durationMs: durationMs)
    }
}
