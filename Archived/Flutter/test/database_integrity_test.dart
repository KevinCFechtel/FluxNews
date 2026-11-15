import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/database/database_schema.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late SecureStorageMock secureStorage;

  setUp(() async {
    database = await createFluxNewsTestDatabase();
    secureStorage = SecureStorageMock();
    secureStorage.install();
  });

  tearDown(() async {
    SecureStorageMock.uninstall();
    await database.close();
  });

  test('empty fetched feed list preserves local categories, feeds, and news',
      () async {
    await insertTestCategory(database, categoryID: 1, title: 'Local');
    await insertTestFeed(database, feedID: 1, title: 'Local Feed');
    await insertTestNews(database,
        newsID: 1, feedID: 1, title: 'Local News', feedTitle: 'Local Feed');
    final appState = FluxNewsState()..db = database;

    await insertCategoriesInDB(Categories(categories: []), appState);

    expect(await database.query('categories'), hasLength(1));
    expect(await database.query('feeds'), hasLength(1));
    expect(await database.query('news'), hasLength(1));
  });

  test('non-empty fetched feed list removes feeds missing on server', () async {
    await insertTestCategory(database, categoryID: 1, title: 'Local');
    await insertTestFeed(database, feedID: 1, title: 'Kept Feed');
    await insertTestFeed(database, feedID: 2, title: 'Deleted Feed');
    await insertTestNews(database,
        newsID: 1, feedID: 1, title: 'Kept News', feedTitle: 'Kept Feed');
    await insertTestNews(database,
        newsID: 2, feedID: 2, title: 'Deleted News', feedTitle: 'Deleted Feed');
    final appState = FluxNewsState()..db = database;

    await insertCategoriesInDB(
      Categories(categories: [
        Category(
          categoryID: 1,
          title: 'Server',
          feeds: [
            Feed(
              feedID: 1,
              title: 'Kept Feed',
              siteUrl: 'https://example.com/feed/1',
            ),
          ],
        ),
      ]),
      appState,
    );

    final feeds = await database.query('feeds', orderBy: 'feedID');
    final news = await database.query('news', orderBy: 'newsID');
    expect(feeds.map((row) => row['feedID']), [1]);
    expect(news.map((row) => row['newsID']), [1]);
  });

  test('category news query is globally chronological across feeds', () async {
    await insertTestFeed(database, feedID: 1, title: 'Feed 1');
    await insertTestFeed(database, feedID: 2, title: 'Feed 2');
    await insertTestNews(
      database,
      newsID: 1,
      feedID: 1,
      title: 'Old Feed 1',
      publishedAt: '2026-07-03T08:00:00Z',
      feedTitle: 'Feed 1',
    );
    await insertTestNews(
      database,
      newsID: 2,
      feedID: 2,
      title: 'Newest Feed 2',
      publishedAt: '2026-07-03T10:00:00Z',
      feedTitle: 'Feed 2',
    );
    await insertTestNews(
      database,
      newsID: 3,
      feedID: 1,
      title: 'Middle Feed 1',
      publishedAt: '2026-07-03T09:00:00Z',
      feedTitle: 'Feed 1',
    );
    final appState = FluxNewsState()
      ..db = database
      ..selectedCategoryElementType = FluxNewsState.categoryElementType
      ..feedIDs = [1, 2]
      ..sortOrder = FluxNewsState.sortOrderNewestFirstString;

    final news = await queryNewsFromDB(appState);

    expect(news.map((item) => item.title), [
      'Newest Feed 2',
      'Middle Feed 1',
      'Old Feed 1',
    ]);
  });

  test('category news query supports more than sqlite bind limit feed IDs',
      () async {
    final feedIDs = List<int>.generate(1001, (index) => index + 1);
    for (final feedID in feedIDs) {
      await insertTestFeed(database, feedID: feedID, title: 'Feed $feedID');
    }
    await insertTestNews(
      database,
      newsID: 1001,
      feedID: 1001,
      title: 'Chunked Feed News',
      feedTitle: 'Feed 1001',
    );
    final appState = FluxNewsState()
      ..db = database
      ..selectedCategoryElementType = FluxNewsState.categoryElementType
      ..feedIDs = feedIDs;

    final news = await queryNewsFromDB(appState);

    expect(news.map((item) => item.newsID), [1001]);
  });

  test('feed setting updates immediately persist feed overrides', () async {
    await insertTestFeed(database, feedID: 1, title: 'Feed');
    final appState = FluxNewsState()..db = database;

    await updatePreferParagraphStatusOfFeedInDB(1, true, appState);

    final rawOverrides = secureStorage
        .values[FluxNewsState.secureStorageFeedSettingsOverridesKey];
    expect(rawOverrides, isNotNull);
    final overrides = jsonDecode(rawOverrides!) as Map<String, dynamic>;
    expect(overrides['1']['preferParagraph'], 1);
  });

  test('database schema creates query indexes', () async {
    final rows = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index'",
    );
    final names = rows.map((row) => row['name']).toSet();

    expect(
        names,
        containsAll(<String>{
          'idx_news_published',
          'idx_news_status_published',
          'idx_news_feed_status_published',
          'idx_news_starred_published',
          'idx_news_sync_status',
          'idx_attachments_news',
          'idx_attachments_url',
          'idx_feeds_category',
        }));
    expect(fluxNewsDatabaseVersion, 12);
  });

  test('starred news and attachments are persisted before update returns',
      () async {
    final appState = FluxNewsState()..db = database;
    final news = News(
      newsID: 99,
      feedID: 7,
      title: 'Saved episode',
      url: 'https://example.com/99',
      commentsUrl: '',
      shareCode: '',
      content: 'Episode',
      hash: 'hash-99',
      publishedAt: '2026-07-30T10:00:00Z',
      createdAt: '2026-07-30T10:00:00Z',
      status: FluxNewsState.readNewsStatus,
      readingTime: 1,
      starred: true,
      feedTitle: 'Podcast',
      attachments: [
        Attachment(
          attachmentID: 199,
          newsID: 99,
          attachmentURL: 'https://example.com/99.mp3',
          attachmentMimeType: 'audio/mpeg',
          mediaProgression: 0,
        ),
      ],
    )..prepareListMetadata();

    await updateStarredNewsInDB(
      NewsList(news: [news], newsCount: 1),
      appState,
    );

    expect(await database.query('news', where: 'newsID = 99'), hasLength(1));
    expect(
      await database.query('attachments', where: 'attachmentID = 199'),
      hasLength(1),
    );
  });

  test('staged SQL reconciliation handles 8000 IDs without bind expansion',
      () async {
    final appState = FluxNewsState()..db = database;
    await insertTestNews(
      database,
      newsID: 1,
      feedID: 1,
      title: 'Present',
      starred: true,
    );
    await insertTestNews(
      database,
      newsID: 8001,
      feedID: 1,
      title: 'Missing',
      starred: true,
    );
    await initializeRemoteSyncStaging(appState);
    for (var start = 1; start <= 8000; start += 500) {
      await stageRemoteSyncNewsPage(
        appState,
        List.generate(500, (index) => {'id': start + index}),
        starred: false,
      );
      await stageRemoteSyncNewsPage(
        appState,
        List.generate(500, (index) => {'id': start + index}),
        starred: true,
      );
    }

    await markNewsMissingFromCompleteStagingAsRead(appState);
    await clearStarredMissingFromCompleteStaging(appState);

    final present = (await database.query(
      'news',
      columns: ['status', 'starred'],
      where: 'newsID = 1',
    ))
        .single;
    final missing = (await database.query(
      'news',
      columns: ['status', 'starred'],
      where: 'newsID = 8001',
    ))
        .single;
    expect(present['status'], FluxNewsState.unreadNewsStatus);
    expect(present['starred'], 1);
    expect(missing['status'], FluxNewsState.readNewsStatus);
    expect(missing['starred'], 0);
    await discardRemoteSyncStaging(appState);
  });

  test('counter snapshot reflects current status and selected feed scope',
      () async {
    await insertTestFeed(database, feedID: 1, title: 'First Feed');
    await insertTestFeed(database, feedID: 2, title: 'Second Feed');
    await insertTestNews(
      database,
      newsID: 1,
      feedID: 1,
      title: 'First unread',
    );
    await insertTestNews(
      database,
      newsID: 2,
      feedID: 2,
      title: 'Second unread',
    );
    await insertTestNews(
      database,
      newsID: 3,
      feedID: 1,
      title: 'Already read',
      status: FluxNewsState.readNewsStatus,
    );
    final appState = FluxNewsState()
      ..db = database
      ..newsStatus = FluxNewsState.unreadNewsStatus
      ..selectedCategoryElementType = FluxNewsState.feedElementType
      ..feedIDs = [1];

    var snapshot = await queryNewsCounterSnapshot(appState);
    expect(snapshot.allNewsCount, 2);
    expect(snapshot.currentViewCount, 1);

    await updateNewsStatusInDB(
      1,
      FluxNewsState.readNewsStatus,
      appState,
    );
    snapshot = await queryNewsCounterSnapshot(appState);
    expect(snapshot.allNewsCount, 1);
    expect(snapshot.currentViewCount, 0);
  });
}
