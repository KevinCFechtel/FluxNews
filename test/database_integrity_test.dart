import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/database/database_backend.dart';
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
}
