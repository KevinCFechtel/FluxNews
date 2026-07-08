import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const MethodChannel secureStorageTestChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

class SecureStorageMock {
  SecureStorageMock([Map<String, String>? initialValues])
      : values = Map<String, String>.from(initialValues ?? {});

  final Map<String, String> values;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageTestChannel, (call) async {
      final args = Map<Object?, Object?>.from(
          call.arguments as Map<Object?, Object?>? ?? {});
      final key = args['key']?.toString();
      switch (call.method) {
        case 'readAll':
          return Map<String, String>.from(values);
        case 'read':
          return key == null ? null : values[key];
        case 'write':
          if (key != null) {
            values[key] = args['value']?.toString() ?? '';
          }
          return null;
        case 'delete':
          if (key != null) values.remove(key);
          return null;
        case 'deleteAll':
          values.clear();
          return null;
        case 'containsKey':
          return key != null && values.containsKey(key);
      }
      return null;
    });
  }

  static void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageTestChannel, null);
  }
}

Future<Database> createFluxNewsTestDatabase() async {
  sqfliteFfiInit();
  final database =
      await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
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
  await database.execute('''CREATE TABLE categories(
    categoryID INTEGER PRIMARY KEY,
    title TEXT
  )''');
  await database.execute('''CREATE TABLE attachments(
    attachmentID INTEGER PRIMARY KEY,
    newsID INTEGER,
    attachmentURL TEXT,
    attachmentMimeType TEXT,
    mediaProgression INTEGER NOT NULL DEFAULT 0
  )''');
  return database;
}

Future<void> insertTestCategory(Database database,
    {required int categoryID, required String title}) {
  return database.insert('categories', {
    'categoryID': categoryID,
    'title': title,
  });
}

Future<void> insertTestFeed(
  Database database, {
  required int feedID,
  required String title,
  int categoryID = 1,
  int newsCount = 0,
  int iconID = 0,
  int crawler = 0,
  int manualTruncate = 0,
  int preferParagraph = 0,
  int preferAttachmentImage = 0,
  int manualAdaptLightModeToIcon = 0,
  int manualAdaptDarkModeToIcon = 0,
  int openMinifluxEntry = 0,
  int expandedWithFulltext = 0,
  int expandedFulltextLimit = 0,
}) {
  return database.insert('feeds', {
    'feedID': feedID,
    'title': title,
    'site_url': 'https://example.com/feed/$feedID',
    'iconMimeType': '',
    'iconID': iconID,
    'newsCount': newsCount,
    'crawler': crawler,
    'manualTruncate': manualTruncate,
    'preferParagraph': preferParagraph,
    'preferAttachmentImage': preferAttachmentImage,
    'manualAdaptLightModeToIcon': manualAdaptLightModeToIcon,
    'manualAdaptDarkModeToIcon': manualAdaptDarkModeToIcon,
    'openMinifluxEntry': openMinifluxEntry,
    'expandedWithFulltext': expandedWithFulltext,
    'expandedFulltextLimit': expandedFulltextLimit,
    'categoryID': categoryID,
  });
}

Future<void> insertTestNews(
  Database database, {
  required int newsID,
  required int feedID,
  required String title,
  String publishedAt = '2026-07-03T10:00:00Z',
  String status = FluxNewsState.unreadNewsStatus,
  bool starred = false,
  String feedTitle = 'Feed',
  String content = '<p>Full article content</p>',
}) {
  final news = News(
    newsID: newsID,
    feedID: feedID,
    title: title,
    url: 'https://example.com/news/$newsID',
    commentsUrl: '',
    shareCode: '',
    content: content,
    hash: 'hash-$newsID',
    publishedAt: publishedAt,
    createdAt: publishedAt,
    status: status,
    readingTime: 1,
    starred: starred,
    feedTitle: feedTitle,
  )..prepareListMetadata();
  return database.insert('news', news.toMap());
}

Future<void> insertTestAttachment(
  Database database, {
  required int attachmentID,
  required int newsID,
  required String attachmentURL,
  String attachmentMimeType = 'audio/mpeg',
  int mediaProgression = 0,
}) {
  return database.insert('attachments', {
    'attachmentID': attachmentID,
    'newsID': newsID,
    'attachmentURL': attachmentURL,
    'attachmentMimeType': attachmentMimeType,
    'mediaProgression': mediaProgression,
  });
}
