import Foundation
import WidgetKit
import XCTest

final class WidgetSnapshotTests: XCTestCase {
    func testRoundTripAndInvalidationDoNotExposeCredentials() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = WidgetSnapshotStore(root: temporary)
        let snapshot = WidgetSnapshotV1(
            schemaVersion: 1, state: .ready, generatedAt: "2026-08-27T12:00:00Z", lastSuccessfulSyncAt: "2026-08-27T11:00:00Z",
            feeds: [.init(id: 42, categoryID: 7, title: "Development", normalIconFile: "icons/feed-42-normal.png", darkIconFile: nil)],
            categories: [.init(id: 7, title: "Work")],
            articles: [.init(id: 999_999_999, feedID: 42, categoryID: 7, feedTitle: "Development", title: "Article", publishedAt: "2026-08-27T10:00:00Z", isRead: false, isStarred: true)],
            counts: .init(allUnread: 10_000, bookmarks: 1, feedUnread: [.init(id: 42, count: 10_000)], categoryUnread: [.init(id: 7, count: 10_000)])
        )
        try store.write(snapshot)
        XCTAssertEqual(try store.read(), snapshot)
        let serialized = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertFalse(serialized.contains("apiKey"))
        XCTAssertFalse(serialized.contains("server"))
        XCTAssertTrue(serialized.contains("999999999"))
        _ = try store.writeIcon(Data([1, 2]), feedID: 42, dark: false)
        try store.invalidate()
        XCTAssertNil(try store.read())
    }

    func testUnsupportedAndCorruptSnapshotsAreRejectedSafely() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = WidgetSnapshotStore(root: temporary)
        let unsupported = WidgetSnapshotV1(schemaVersion: 2, state: .noAccount, generatedAt: "", lastSuccessfulSyncAt: nil, feeds: [], categories: [], articles: [], counts: .init(allUnread: 0, bookmarks: 0, feedUnread: [], categoryUnread: []))
        XCTAssertThrowsError(try store.write(unsupported))
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: temporary.appendingPathComponent("widget-snapshot-v1.json"))
        XCTAssertThrowsError(try store.read()) { XCTAssertEqual($0 as? WidgetSnapshotStoreError, .corruptSnapshot) }
    }

    func testUnavailableStoreDoesNotPreventLaterStoreFromWriting() throws {
        XCTAssertThrowsError(try WidgetSnapshotStore(appGroupContainer: nil)) { XCTAssertEqual($0 as? WidgetSnapshotStoreError, .unavailableAppGroup) }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = WidgetSnapshotStore(root: temporary)
        let snapshot = WidgetSnapshotV1(schemaVersion: 1, state: .ready, generatedAt: "", lastSuccessfulSyncAt: nil, feeds: [], categories: [], articles: [], counts: .init(allUnread: 0, bookmarks: 0, feedUnread: [], categoryUnread: []))

        try store.write(snapshot)

        XCTAssertEqual(try store.read(), snapshot)
    }

    func testSnapshotWritesWhenFeedIconsAreMissing() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let snapshot = WidgetSnapshotV1(schemaVersion: 1, state: .ready, generatedAt: "", lastSuccessfulSyncAt: "2026-08-28T07:04:07Z", feeds: [.init(id: 42, categoryID: 7, title: "Development", normalIconFile: nil, darkIconFile: nil)], categories: [.init(id: 7, title: "Work")], articles: [], counts: .init(allUnread: 0, bookmarks: 0, feedUnread: [], categoryUnread: []))
        let store = WidgetSnapshotStore(root: temporary)

        try store.write(snapshot)

        XCTAssertEqual(try store.read(), snapshot)
    }

    func testV1SnapshotDecodesISOTimestampFormat() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let snapshotJSON = """
        {"schemaVersion":1,"state":"ready","generatedAt":"2026-08-28T07:04:07Z","lastSuccessfulSyncAt":"2026-08-28T07:04:07Z","feeds":[],"categories":[],"articles":[],"counts":{"allUnread":21,"bookmarks":4,"feedUnread":[],"categoryUnread":[]}}
        """
        try Data(snapshotJSON.utf8).write(to: temporary.appendingPathComponent("widget-snapshot-v1.json"))

        let snapshot = try XCTUnwrap(try WidgetSnapshotStore(root: temporary).read())

        XCTAssertEqual(snapshot.generatedAt, "2026-08-28T07:04:07Z")
        XCTAssertEqual(snapshot.lastSuccessfulSyncAt, "2026-08-28T07:04:07Z")
        XCTAssertEqual(snapshot.counts.allUnread, 21)
    }

    func testPresentationUsesAuthoritativeCountsAndFiltersBookmarksIndependentlyOfReadState() {
        let model = WidgetContentModel.make(snapshotResult: .success(sampleSnapshot), selection: .init(scope: .bookmarks, categoryID: nil, feedID: nil))

        XCTAssertEqual(model.state, .ready)
        XCTAssertEqual(model.title, "Bookmarks")
        XCTAssertEqual(model.count, 99)
        XCTAssertEqual(model.countLabel, "bookmarked")
        XCTAssertEqual(model.articles.map(\.id), [3, 1])
        XCTAssertEqual(model.lastSuccessfulSyncAt, "2026-08-27T11:00:00Z")
    }

    func testPresentationMarksDeletedConfiguredFeedUnavailable() {
        let model = WidgetContentModel.make(snapshotResult: .success(sampleSnapshot), selection: .init(scope: .feed, categoryID: nil, feedID: 404))

        XCTAssertEqual(model.state, .unavailableSelection("Selected feed unavailable"))
        XCTAssertTrue(model.articles.isEmpty)
    }

    func testPresentationMarksDeletedConfiguredCategoryUnavailable() {
        let model = WidgetContentModel.make(snapshotResult: .success(sampleSnapshot), selection: .init(scope: .category, categoryID: 404, feedID: nil))

        XCTAssertEqual(model.state, .unavailableSelection("Selected category unavailable"))
        XCTAssertTrue(model.articles.isEmpty)
    }

    func testHeadlinesUsesDocumentedFamilyCapacities() {
        XCTAssertEqual(HeadlinesPresentation.capacity(for: .systemSmall), 1)
        XCTAssertEqual(HeadlinesPresentation.capacity(for: .systemMedium), 3)
        XCTAssertEqual(HeadlinesPresentation.capacity(for: .systemLarge), 7)
        XCTAssertEqual(HeadlinesPresentation.capacity(for: .systemExtraLarge), 12)
    }

    func testPresentationDistinguishesSnapshotAndAccountStates() {
        XCTAssertEqual(WidgetContentModel.make(snapshotResult: .success(nil), selection: .init(scope: .allNews, categoryID: nil, feedID: nil)).state, .missingSnapshot)
        XCTAssertEqual(WidgetContentModel.make(snapshotResult: .success(WidgetSnapshotV1(schemaVersion: 1, state: .noAccount, generatedAt: "", lastSuccessfulSyncAt: nil, feeds: [], categories: [], articles: [], counts: .init(allUnread: 0, bookmarks: 0, feedUnread: [], categoryUnread: []))), selection: .init(scope: .allNews, categoryID: nil, feedID: nil)).state, .noAccount)
        XCTAssertEqual(WidgetContentModel.make(snapshotResult: .failure(WidgetSnapshotStoreError.corruptSnapshot), selection: .init(scope: .allNews, categoryID: nil, feedID: nil)).state, .corruptSnapshot)
    }

    func testReadIconRejectsPathsOutsideIconsDirectory() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = WidgetSnapshotStore(root: temporary)
        let path = try store.writeIcon(Data([1, 2]), feedID: 42, dark: false)

        XCTAssertEqual(store.readIcon(relativePath: path), Data([1, 2]))
        XCTAssertNil(store.readIcon(relativePath: "../widget-snapshot-v1.json"))
        XCTAssertNil(store.readIcon(relativePath: "icons/nested/file.png"))
    }

    func testWidgetActionsRoundTripOnlyStableIdentifiers() {
        let actions: [WidgetAction] = [.article(42), .sync, .open(.init(scope: .allNews, categoryID: nil, feedID: nil)), .open(.init(scope: .bookmarks, categoryID: nil, feedID: nil)), .open(.init(scope: .feed, categoryID: nil, feedID: 7)), .open(.init(scope: .category, categoryID: 8, feedID: nil))]
        for action in actions { XCTAssertEqual(WidgetAction(url: action.url()), action) }
        XCTAssertNil(WidgetAction(url: URL(string: "fluxnews://widget/v1/article?id=nope")!))
        XCTAssertNil(WidgetAction(url: URL(string: "fluxnews://widget/v1/open?scope=feed")!))
        XCTAssertNil(WidgetAction(url: URL(string: "https://example.com/v1/sync")!))
        XCTAssertNil(WidgetAction(url: URL(string: "fluxnews://widget/v1/unknown")!))
    }

    func testHeadlinesCapacitiesAndLatestArticlesAreBounded() {
        XCTAssertEqual(HeadlinesPresentation.capacity(for: .systemSmall), 1)
        XCTAssertEqual(HeadlinesPresentation.capacity(for: .systemMedium), 3)
        XCTAssertEqual(HeadlinesPresentation.capacity(for: .systemLarge), 7)
        XCTAssertEqual(HeadlinesPresentation.capacity(for: .systemExtraLarge), 12)
        let articles = (1...20).map { WidgetSnapshotV1.Article(id: Int64($0), feedID: 42, categoryID: 7, feedTitle: "Development", title: "\($0)", publishedAt: String(format: "2026-08-27T%02d:00:00Z", $0), isRead: false, isStarred: false) }.reversed()
        let snapshot = WidgetSnapshotV1(schemaVersion: 1, state: .ready, generatedAt: "", lastSuccessfulSyncAt: nil, feeds: [.init(id: 42, categoryID: 7, title: "Development", normalIconFile: nil, darkIconFile: nil)], categories: [.init(id: 7, title: "Work")], articles: Array(articles), counts: .init(allUnread: 100, bookmarks: 0, feedUnread: [.init(id: 42, count: 100)], categoryUnread: [.init(id: 7, count: 100)]))
        let model = WidgetContentModel.make(snapshotResult: .success(snapshot), selection: .init(scope: .allNews, categoryID: nil, feedID: nil))
        XCTAssertEqual(model.latestArticles(limit: HeadlinesPresentation.capacity(for: .systemMedium)).count, 3)
        XCTAssertEqual(model.latestArticles(limit: HeadlinesPresentation.capacity(for: .systemMedium)).map(\.id), [20, 19, 18])
        XCTAssertEqual(model.latestArticles(limit: HeadlinesPresentation.capacity(for: .systemLarge)).count, 7)
        XCTAssertEqual(model.latestArticles(limit: HeadlinesPresentation.capacity(for: .systemExtraLarge)).count, 12)
        XCTAssertEqual(model.count, 100)
    }

    func testD9ConfigurationSupportsReadFilterAndBothSortDirections() {
        let snapshot = WidgetSnapshotV1(
            schemaVersion: 1,
            state: .ready,
            generatedAt: "2026-09-28T12:00:00Z",
            lastSuccessfulSyncAt: "2026-09-28T11:59:00Z",
            feeds: [
                .init(id: 42, categoryID: 7, title: "Development", normalIconFile: nil, darkIconFile: nil),
            ],
            categories: [.init(id: 7, title: "Work")],
            articles: [
                .init(id: 4, feedID: 42, categoryID: 7, feedTitle: "Development", title: "Newest read", publishedAt: "2026-09-28T11:00:00Z", isRead: true, isStarred: false),
                .init(id: 3, feedID: 42, categoryID: 7, feedTitle: "Development", title: "Newest unread bookmark", publishedAt: "2026-09-28T10:00:00Z", isRead: false, isStarred: true),
                .init(id: 2, feedID: 42, categoryID: 7, feedTitle: "Development", title: "Older read bookmark", publishedAt: "2026-09-28T09:00:00Z", isRead: true, isStarred: true),
                .init(id: 1, feedID: 42, categoryID: 7, feedTitle: "Development", title: "Oldest unread", publishedAt: "2026-09-28T08:00:00Z", isRead: false, isStarred: false),
            ],
            counts: .init(
                allUnread: 2,
                bookmarks: 2,
                feedUnread: [.init(id: 42, count: 2)],
                categoryUnread: [.init(id: 7, count: 2)]
            ),
            configuration: .init(
                allArticles: 4,
                bookmarksUnread: 1,
                feedAll: [.init(id: 42, count: 4)],
                categoryAll: [.init(id: 7, count: 4)]
            )
        )

        let unreadNewest = WidgetContentModel.make(
            snapshotResult: .success(snapshot),
            selection: .init(
                scope: .feed,
                categoryID: nil,
                feedID: 42,
                readFilter: .unread,
                sortOrder: .newestFirst
            )
        )
        XCTAssertEqual(unreadNewest.count, 2)
        XCTAssertEqual(unreadNewest.countLabel, "unread")
        XCTAssertEqual(unreadNewest.articles.map(\.id), [3, 1])

        let unreadOldest = WidgetContentModel.make(
            snapshotResult: .success(snapshot),
            selection: .init(
                scope: .feed,
                categoryID: nil,
                feedID: 42,
                readFilter: .unread,
                sortOrder: .oldestFirst
            )
        )
        XCTAssertEqual(unreadOldest.articles.map(\.id), [1, 3])

        let allNewest = WidgetContentModel.make(
            snapshotResult: .success(snapshot),
            selection: .init(
                scope: .feed,
                categoryID: nil,
                feedID: 42,
                readFilter: .all,
                sortOrder: .newestFirst
            )
        )
        XCTAssertEqual(allNewest.count, 4)
        XCTAssertEqual(allNewest.countLabel, "articles")
        XCTAssertEqual(allNewest.articles.map(\.id), [4, 3, 2, 1])

        let allOldest = WidgetContentModel.make(
            snapshotResult: .success(snapshot),
            selection: .init(
                scope: .feed,
                categoryID: nil,
                feedID: 42,
                readFilter: .all,
                sortOrder: .oldestFirst
            )
        )
        XCTAssertEqual(allOldest.articles.map(\.id), [1, 2, 3, 4])

        let unreadBookmarks = WidgetContentModel.make(
            snapshotResult: .success(snapshot),
            selection: .init(
                scope: .bookmarks,
                categoryID: nil,
                feedID: nil,
                readFilter: .unread,
                sortOrder: .newestFirst
            )
        )
        XCTAssertEqual(unreadBookmarks.count, 1)
        XCTAssertEqual(unreadBookmarks.articles.map(\.id), [3])
    }

    func testLegacyV1SnapshotKeepsExistingDefaultSemanticsAndRejectsNewProjectionNeeds() {
        let legacy = sampleSnapshot

        let allNews = WidgetContentModel.make(
            snapshotResult: .success(legacy),
            selection: .init(scope: .allNews, categoryID: nil, feedID: nil)
        )
        XCTAssertEqual(allNews.state, .ready)
        XCTAssertEqual(allNews.articles.map(\.id), [1, 2])

        let bookmarks = WidgetContentModel.make(
            snapshotResult: .success(legacy),
            selection: .init(scope: .bookmarks, categoryID: nil, feedID: nil)
        )
        XCTAssertEqual(bookmarks.state, .ready)
        XCTAssertEqual(bookmarks.articles.map(\.id), [3, 1])

        let allConfigured = WidgetContentModel.make(
            snapshotResult: .success(legacy),
            selection: .init(
                scope: .allNews,
                categoryID: nil,
                feedID: nil,
                readFilter: .all,
                sortOrder: .newestFirst
            )
        )
        XCTAssertEqual(
            allConfigured.state,
            .unavailableSelection("Open FluxNews to refresh widget data")
        )
    }

    private var sampleSnapshot: WidgetSnapshotV1 {
        .init(schemaVersion: 1, state: .ready, generatedAt: "2026-08-27T12:00:00Z", lastSuccessfulSyncAt: "2026-08-27T11:00:00Z", feeds: [.init(id: 42, categoryID: 7, title: "Development", normalIconFile: nil, darkIconFile: nil)], categories: [.init(id: 7, title: "Work")], articles: [.init(id: 1, feedID: 42, categoryID: 7, feedTitle: "Development", title: "Unread bookmark", publishedAt: "2026-08-27T10:00:00Z", isRead: false, isStarred: true), .init(id: 2, feedID: 42, categoryID: 7, feedTitle: "Development", title: "Unread article", publishedAt: "2026-08-27T09:00:00Z", isRead: false, isStarred: false), .init(id: 3, feedID: 42, categoryID: 7, feedTitle: "Development", title: "Read bookmark", publishedAt: "2026-08-27T11:00:00Z", isRead: true, isStarred: true)], counts: .init(allUnread: 10, bookmarks: 99, feedUnread: [.init(id: 42, count: 10)], categoryUnread: [.init(id: 7, count: 10)]))
    }
}
