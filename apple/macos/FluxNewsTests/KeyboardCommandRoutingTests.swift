import AppKit
import XCTest

final class KeyboardCommandRoutingTests: XCTestCase {
    func testSpaceOpensReaderDetail() {
        XCTAssertEqual(ArticleKeyboardRouting.command(keyCode: 49, charactersIgnoringModifiers: " ", modifierFlags: []), .openDetail)
    }

    func testModifiedSpaceIsNotHandled() {
        XCTAssertNil(ArticleKeyboardRouting.command(keyCode: 49, charactersIgnoringModifiers: " ", modifierFlags: .command))
    }

    func testHoveredArticleTakesPriorityOverKeyboardSelection() {
        XCTAssertEqual(ArticleReaderTarget.articleID(hoveredID: 1, selectedID: 2, availableIDs: [1, 2]), 1)
    }

    func testKeyboardSelectionIsUsedWithoutHover() {
        XCTAssertEqual(ArticleReaderTarget.articleID(hoveredID: nil, selectedID: 2, availableIDs: [1, 2]), 2)
    }

    func testNoReaderTargetWithoutHoverOrSelection() {
        XCTAssertNil(ArticleReaderTarget.articleID(hoveredID: nil, selectedID: nil, availableIDs: [1, 2]))
    }

    func testSpaceForVisibleArticleTogglesPreviewClosed() {
        XCTAssertEqual(ReaderPreviewAction.resolve(isVisible: true, currentArticleID: 1, requestedArticleID: 1, togglesSameArticle: true), .hide)
    }

    func testSpaceForDifferentArticleReplacesPreviewContent() {
        XCTAssertEqual(ReaderPreviewAction.resolve(isVisible: true, currentArticleID: 1, requestedArticleID: 2, togglesSameArticle: true), .replace)
    }

    func testValidPreviewSizePersists() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let size = NSSize(width: 960, height: 740)
        ReaderPreviewGeometry.persist(size: size, defaults: defaults)
        XCTAssertEqual(ReaderPreviewGeometry.persistedSize(defaults: defaults), size)
        defaults.removePersistentDomain(forName: #function)
    }

    func testTinyPreviewSizeFallsBackToDefault() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set([100, 100], forKey: ReaderPreviewGeometry.sizeDefaultsKey)
        XCTAssertEqual(ReaderPreviewGeometry.persistedSize(defaults: defaults), ReaderPreviewGeometry.defaultSize)
        defaults.removePersistentDomain(forName: #function)
    }

    func testPreviewPositionIsCenteredOnChosenScreen() {
        let size = NSSize(width: 800, height: 700)
        let firstScreen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let secondScreen = NSRect(x: 1440, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(ReaderPreviewGeometry.centeredFrame(size: size, visibleFrame: firstScreen).origin, NSPoint(x: 320, y: 100))
        XCTAssertEqual(ReaderPreviewGeometry.centeredFrame(size: size, visibleFrame: secondScreen).origin, NSPoint(x: 2_000, y: 190))
    }

    func testReaderArticleStateUsesMatchingExternalArticle() {
        XCTAssertEqual(ReaderArticleState.starredState(articleID: 2, visibleArticles: [(1, false), (2, true)]), true)
    }

    func testReaderArticleStateIgnoresUnrelatedExternalArticle() {
        XCTAssertNil(ReaderArticleState.starredState(articleID: 2, visibleArticles: [(1, true)]))
    }
}
