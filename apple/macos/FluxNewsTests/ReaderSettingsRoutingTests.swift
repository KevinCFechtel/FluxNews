import XCTest

final class ReaderSettingsRoutingTests: XCTestCase {
    func testPreviewLinesDefaultsToStandardAndSupportsOnlyConfiguredValues() {
        XCTAssertEqual(ArticlePreviewLines.standard.rawValue, 3)
        XCTAssertEqual(ArticlePreviewLines.allCases.map(\.rawValue), [2, 3, 5])
    }

    func testClickOnNewsDefaultsToOpenLink() {
        XCTAssertEqual(ClickOnNews.openLink.rawValue, "openLink")
    }

    func testOpenLinkUsesNormalFeedDestination() {
        XCTAssertEqual(ArticleOpenRouting.action(clickOnNews: .openLink, openInMiniflux: false), .original)
        XCTAssertEqual(ArticleOpenRouting.action(clickOnNews: .openLink, openInMiniflux: true), .miniflux)
    }

    func testOpenDetailViewClickAlwaysUsesDetailPreview() {
        XCTAssertEqual(ArticleOpenRouting.action(clickOnNews: .openDetailView, openInMiniflux: false), .detail)
        XCTAssertEqual(ArticleOpenRouting.action(clickOnNews: .openDetailView, openInMiniflux: true), .detail)
    }

    func testSearchReaderUsesRemoteSourceAndNormalScopesUseLocalSource() {
        XCTAssertEqual(ReaderDocumentSource.forScope(.search), .search)
        XCTAssertEqual(ReaderDocumentSource.forScope(.all), .local)
        XCTAssertEqual(ReaderDocumentSource.forScope(.starred), .local)
    }

    func testOnlyRealFeedsExposeFeedSettings() {
        XCTAssertTrue(FeedSettingsRouting.isAvailable(feedID: 10))
        XCTAssertFalse(FeedSettingsRouting.isAvailable(feedID: nil))
    }
}
