import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;

  setUpAll(() async {
    sqfliteFfiInit();
    database = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
    );
    await database.execute('''CREATE TABLE news(
      newsID INTEGER PRIMARY KEY,
      feedID INTEGER,
      title TEXT,
      url TEXT,
      commentsUrl TEXT,
      shareCode TEXT,
      content TEXT,
      previewText TEXT,
      imageUrl TEXT,
      hash TEXT,
      publishedAt TEXT,
      createdAt TEXT,
      status TEXT,
      readingTime INTEGER,
      starred INTEGER,
      feedTitle TEXT,
      syncStatus TEXT
    )''');
    await database.execute('''CREATE TABLE feeds(
      feedID INTEGER PRIMARY KEY,
      title TEXT,
      site_url TEXT,
      iconMimeType TEXT,
      iconID INTEGER,
      newsCount INTEGER,
      crawler INTEGER,
      manualTruncate INTEGER,
      preferParagraph INTEGER,
      preferAttachmentImage INTEGER,
      manualAdaptLightModeToIcon INTEGER,
      manualAdaptDarkModeToIcon INTEGER,
      openMinifluxEntry INTEGER,
      expandedWithFulltext INTEGER,
      expandedFulltextLimit INTEGER,
      categoryID INTEGER
    )''');
    await database.execute('''CREATE TABLE attachments(
      attachmentID INTEGER PRIMARY KEY,
      newsID INTEGER,
      attachmentURL TEXT,
      attachmentMimeType TEXT,
      mediaProgression INTEGER NOT NULL DEFAULT 0
    )''');
    await database.insert('feeds', {
      'feedID': 1,
      'title': 'Feed',
      'site_url': 'https://example.com',
      'iconMimeType': '',
      'newsCount': 1,
      'preferParagraph': 0,
      'preferAttachmentImage': 0,
    });

    final news = News(
      newsID: 1,
      feedID: 1,
      title: 'Title',
      url: 'https://example.com/article',
      commentsUrl: '',
      shareCode: '',
      content: '<p>Full article content</p><img src="https://example.com/image.jpg">',
      hash: 'hash',
      publishedAt: '2026-07-03T10:00:00Z',
      createdAt: '2026-07-03T10:00:00Z',
      status: FluxNewsState.unreadNewsStatus,
      readingTime: 1,
      starred: false,
      feedTitle: 'Feed',
    )..prepareListMetadata();
    await database.insert('news', news.toMap());
  });

  tearDownAll(() async {
    await database.close();
  });

  test('list query omits content and loads it on demand', () async {
    final appState = FluxNewsState()..db = database;

    final newsList = await queryNewsFromDB(appState);

    expect(newsList, hasLength(1));
    final news = newsList.single;
    expect(news.content, isEmpty);
    expect(news.contentLoaded, isFalse);
    expect(news.previewText, contains('Full article content'));
    expect(news.imageUrl, 'https://example.com/image.jpg');

    await ensureNewsContentLoaded(appState, news);

    expect(news.contentLoaded, isTrue);
    expect(news.content, contains('Full article content'));

    final directNews = await queryNewsByIdFromDB(appState, news.newsID);
    expect(directNews?.contentLoaded, isTrue);
    expect(directNews?.content, contains('Full article content'));
  });

  test('widget query does not load full article content', () async {
    final appState = FluxNewsState()..db = database;

    final newsList = await queryWidgetNewsFromDB(appState);

    expect(newsList, hasLength(1));
    expect(newsList.single.content, isEmpty);
    expect(newsList.single.contentLoaded, isFalse);
    expect(newsList.single.previewText, contains('Full article content'));
  });

  test('missing metadata is backfilled with feed and attachment settings', () async {
    await database.update(
      'feeds',
      {'preferAttachmentImage': 1},
      where: 'feedID = ?',
      whereArgs: [1],
    );
    await database.insert('news', {
      'newsID': 2,
      'feedID': 1,
      'title': 'Migrated title',
      'url': 'https://example.com/migrated',
      'commentsUrl': '',
      'shareCode': '',
      'content': '<p>Migrated article content</p>',
      'hash': 'migrated-hash',
      'publishedAt': '2026-07-03T11:00:00Z',
      'createdAt': '2026-07-03T11:00:00Z',
      'status': FluxNewsState.unreadNewsStatus,
      'readingTime': 1,
      'starred': 0,
      'feedTitle': 'Feed',
      'syncStatus': FluxNewsState.syncedSyncStatus,
    });
    await database.insert('attachments', {
      'attachmentID': 2,
      'newsID': 2,
      'attachmentURL': 'https://example.com/migrated-attachment.jpg',
      'attachmentMimeType': 'image/jpeg',
    });

    final appState = FluxNewsState()..db = database;
    await queryNewsFromDB(appState);

    Map<String, Object?>? migratedRow;
    for (var attempt = 0; attempt < 50; attempt++) {
      final rows = await database.query(
        'news',
        columns: ['previewText', 'imageUrl'],
        where: 'newsID = ?',
        whereArgs: [2],
      );
      migratedRow = rows.single;
      if (migratedRow['previewText'] != null && migratedRow['imageUrl'] != null) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(migratedRow?['previewText'], contains('Migrated article content'));
    expect(
      migratedRow?['imageUrl'],
      'https://example.com/migrated-attachment.jpg',
    );

    await database.delete('attachments', where: 'newsID = ?', whereArgs: [2]);
    await database.delete('news', where: 'newsID = ?', whereArgs: [2]);
    await database.update(
      'feeds',
      {'preferAttachmentImage': 0},
      where: 'feedID = ?',
      whereArgs: [1],
    );
  });
}
