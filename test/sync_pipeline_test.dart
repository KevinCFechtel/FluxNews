import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/functions/sync_pipeline.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/state_management/flux_news_state.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('remote sync snapshot', () {
    test('fetches every part in order and returns one complete snapshot',
        () async {
      final calls = <String>[];
      final news = NewsList(news: [], newsCount: 1);
      final categories = Categories(categories: []);
      final starred = NewsList(news: [], newsCount: 2);

      final snapshot = await fetchRemoteSyncSnapshot(
        FluxNewsState(),
        operations: RemoteSyncFetchOperations(
          fetchNews: (_) async {
            calls.add('news');
            return news;
          },
          fetchCategories: (_) async {
            calls.add('categories');
            return categories;
          },
          fetchStarredNews: (_) async {
            calls.add('starred');
            return starred;
          },
        ),
      );

      expect(calls, ['news', 'categories', 'starred']);
      expect(snapshot.news, same(news));
      expect(snapshot.categories, same(categories));
      expect(snapshot.starredNews, same(starred));
    });

    test('accepts a successful snapshot whose lists are all empty', () async {
      final snapshot = await fetchRemoteSyncSnapshot(
        FluxNewsState(),
        operations: _successfulFetchOperations(),
      );

      expect(snapshot.news.news, isEmpty);
      expect(snapshot.categories.categories, isEmpty);
      expect(snapshot.starredNews.news, isEmpty);
    });

    for (final failureStage in RemoteSyncFetchStage.values) {
      test('reports ${failureStage.name} failure and skips later requests',
          () async {
        final calls = <String>[];
        final operations = RemoteSyncFetchOperations(
          fetchNews: (_) async {
            calls.add('news');
            if (failureStage == RemoteSyncFetchStage.news) {
              throw StateError('news failed');
            }
            return NewsList(news: [], newsCount: 0);
          },
          fetchCategories: (_) async {
            calls.add('categories');
            if (failureStage == RemoteSyncFetchStage.categories) {
              throw StateError('categories failed');
            }
            return Categories(categories: []);
          },
          fetchStarredNews: (_) async {
            calls.add('starred');
            if (failureStage == RemoteSyncFetchStage.starredNews) {
              throw StateError('starred failed');
            }
            return NewsList(news: [], newsCount: 0);
          },
        );

        await expectLater(
          fetchRemoteSyncSnapshot(
            FluxNewsState(),
            operations: operations,
          ),
          throwsA(
            isA<RemoteSyncFetchException>()
                .having((error) => error.stage, 'stage', failureStage)
                .having((error) => error.error, 'error', isA<StateError>()),
          ),
        );

        final expectedCallCount = failureStage.index + 1;
        expect(calls,
            ['news', 'categories', 'starred'].take(expectedCallCount).toList());
      });
    }

    test('aborts after news without requesting categories or starred news',
        () async {
      final appState = FluxNewsState();
      final calls = <String>[];

      await expectLater(
        fetchRemoteSyncSnapshot(
          appState,
          operations: RemoteSyncFetchOperations(
            fetchNews: (_) async {
              calls.add('news');
              appState.longSyncAborted = true;
              return NewsList(news: [], newsCount: 0);
            },
            fetchCategories: (_) async {
              calls.add('categories');
              return Categories(categories: []);
            },
            fetchStarredNews: (_) async {
              calls.add('starred');
              return NewsList(news: [], newsCount: 0);
            },
          ),
        ),
        throwsA(isA<RemoteSyncAbortedException>()),
      );

      expect(calls, ['news']);
    });

    test('aborts after categories without requesting starred news', () async {
      final appState = FluxNewsState();
      final calls = <String>[];

      await expectLater(
        fetchRemoteSyncSnapshot(
          appState,
          operations: RemoteSyncFetchOperations(
            fetchNews: (_) async {
              calls.add('news');
              return NewsList(news: [], newsCount: 0);
            },
            fetchCategories: (_) async {
              calls.add('categories');
              appState.longSyncAborted = true;
              return Categories(categories: []);
            },
            fetchStarredNews: (_) async {
              calls.add('starred');
              return NewsList(news: [], newsCount: 0);
            },
          ),
        ),
        throwsA(isA<RemoteSyncAbortedException>()),
      );

      expect(calls, ['news', 'categories']);
    });

    test('failed snapshot fetch leaves existing database rows unchanged',
        () async {
      final database = await createFluxNewsTestDatabase();
      addTearDown(database.close);
      await insertTestCategory(database, categoryID: 1, title: 'Local');
      await insertTestFeed(database, feedID: 1, title: 'Local Feed');
      await insertTestNews(
        database,
        newsID: 1,
        feedID: 1,
        title: 'Unread local news',
        feedTitle: 'Local Feed',
      );
      final appState = FluxNewsState()..db = database;

      await expectLater(
        fetchRemoteSyncSnapshot(
          appState,
          operations: RemoteSyncFetchOperations(
            fetchNews: (_) async => NewsList(news: [], newsCount: 0),
            fetchCategories: (_) async =>
                throw StateError('incomplete server response'),
            fetchStarredNews: (_) async => NewsList(news: [], newsCount: 0),
          ),
        ),
        throwsA(
          isA<RemoteSyncFetchException>().having(
            (error) => error.stage,
            'stage',
            RemoteSyncFetchStage.categories,
          ),
        ),
      );

      expect(await database.query('categories'), hasLength(1));
      expect(await database.query('feeds'), hasLength(1));
      final newsRows = await database.query('news');
      expect(newsRows, hasLength(1));
      expect(newsRows.single['status'], FluxNewsState.unreadNewsStatus);
    });
  });

  group('local sync reconciliation', () {
    test('partial staged snapshot never authorizes absence cleanup', () async {
      final secureStorage = SecureStorageMock();
      secureStorage.install();
      addTearDown(SecureStorageMock.uninstall);
      final database = await createFluxNewsTestDatabase();
      addTearDown(database.close);
      final appState = FluxNewsState()..db = database;
      await insertTestNews(
        database,
        newsID: 2,
        feedID: 1,
        title: 'Outside cap',
        starred: true,
      );
      await initializeRemoteSyncStaging(appState);

      await reconcileRemoteSyncSnapshot(
        RemoteSyncSnapshot(
          news: NewsList(news: [], newsCount: 100),
          categories: Categories(categories: []),
          starredNews: NewsList(news: [], newsCount: 100),
          staged: true,
          mainComplete: false,
          starredComplete: false,
        ),
        appState,
      );

      final row = (await database.query('news', where: 'newsID = 2')).single;
      expect(row['status'], FluxNewsState.unreadNewsStatus);
      expect(row['starred'], 1);
      await discardRemoteSyncStaging(appState);
    });

    test('staged news transaction rolls back every news-side change', () async {
      final secureStorage = SecureStorageMock();
      secureStorage.install();
      addTearDown(SecureStorageMock.uninstall);
      final database = await createFluxNewsTestDatabase();
      addTearDown(database.close);
      final appState = FluxNewsState()..db = database;
      await insertTestNews(
        database,
        newsID: 1,
        feedID: 1,
        title: 'Missing remotely',
        starred: true,
      );
      await insertTestNews(
        database,
        newsID: 4,
        feedID: 1,
        title: 'Existing unstarred',
        status: FluxNewsState.readNewsStatus,
      );
      await initializeRemoteSyncStaging(appState);
      await stageRemoteSyncNewsPage(
        appState,
        [_entryPayload(2, attachmentID: 20)],
        starred: false,
      );
      await stageRemoteSyncNewsPage(
        appState,
        [_entryPayload(3, starred: true), _entryPayload(4, starred: true)],
        starred: true,
      );

      await expectLater(
        reconcileRemoteSyncSnapshot(
          RemoteSyncSnapshot(
            news: NewsList(news: [], newsCount: 1),
            categories: Categories(categories: []),
            starredNews: NewsList(news: [], newsCount: 2),
            staged: true,
          ),
          appState,
          stagedNewsBeforeCommitForTesting: () async {
            throw StateError('injected before commit');
          },
        ),
        throwsA(
          isA<LocalSyncReconciliationException>()
              .having((error) => error.stage, 'stage',
                  LocalSyncReconciliationStage.news)
              .having((error) => error.error, 'error', isA<StateError>()),
        ),
      );

      final original =
          (await database.query('news', where: 'newsID = 1')).single;
      final existing =
          (await database.query('news', where: 'newsID = 4')).single;
      expect(original['status'], FluxNewsState.unreadNewsStatus);
      expect(original['starred'], 1);
      expect(existing['starred'], 0);
      expect(await database.query('news', where: 'newsID IN (2, 3)'), isEmpty);
      expect(await database.query('attachments'), isEmpty);
      await discardRemoteSyncStaging(appState);
    });

    test('overlapping main and starred entry uses main payload once', () async {
      final secureStorage = SecureStorageMock();
      secureStorage.install();
      addTearDown(SecureStorageMock.uninstall);
      final database = await createFluxNewsTestDatabase();
      addTearDown(database.close);
      final appState = FluxNewsState()..db = database;
      await initializeRemoteSyncStaging(appState);
      await stageRemoteSyncNewsPage(
        appState,
        [_entryPayload(8, title: 'Main payload', attachmentID: 80)],
        starred: false,
      );
      await stageRemoteSyncNewsPage(
        appState,
        [
          _entryPayload(8,
              title: 'Starred payload', starred: true, attachmentID: 81)
        ],
        starred: true,
      );

      await reconcileRemoteSyncSnapshot(
        RemoteSyncSnapshot(
          news: NewsList(news: [], newsCount: 1),
          categories: Categories(categories: []),
          starredNews: NewsList(news: [], newsCount: 1),
          staged: true,
        ),
        appState,
      );

      final news = (await database.query('news', where: 'newsID = 8')).single;
      expect(news['title'], 'Main payload');
      expect(news['starred'], 1);
      expect(
        (await database.query('attachments')).map((row) => row['attachmentID']),
        [80],
      );
      await discardRemoteSyncStaging(appState);
    });

    test('executes every stage in canonical order', () async {
      final calls = <String>[];

      await reconcileRemoteSyncSnapshot(
        _emptySnapshot(),
        FluxNewsState(),
        operations: _recordingReconciliationOperations(calls),
      );

      expect(calls, ['markMissing', 'categories', 'news', 'starred']);
    });

    test('treats a successfully fetched empty snapshot as authoritative',
        () async {
      final secureStorage = SecureStorageMock();
      secureStorage.install();
      addTearDown(SecureStorageMock.uninstall);
      final database = await createFluxNewsTestDatabase();
      addTearDown(database.close);
      await insertTestCategory(database, categoryID: 1, title: 'Local');
      await insertTestFeed(database, feedID: 1, title: 'Local Feed');
      await insertTestNews(
        database,
        newsID: 1,
        feedID: 1,
        title: 'Unread local news',
        feedTitle: 'Local Feed',
      );
      final appState = FluxNewsState()..db = database;

      await reconcileRemoteSyncSnapshot(_emptySnapshot(), appState);

      final newsRows = await database.query('news');
      expect(newsRows, hasLength(1));
      expect(newsRows.single['status'], FluxNewsState.readNewsStatus);
      expect(await database.query('categories'), hasLength(1));
      expect(await database.query('feeds'), hasLength(1));
    });

    for (final failureStage in LocalSyncReconciliationStage.values) {
      test('stops after ${failureStage.name} database failure', () async {
        final calls = <String>[];

        await expectLater(
          reconcileRemoteSyncSnapshot(
            _emptySnapshot(),
            FluxNewsState(),
            operations: _recordingReconciliationOperations(
              calls,
              failureStage: failureStage,
            ),
          ),
          throwsA(
            isA<LocalSyncReconciliationException>()
                .having((error) => error.stage, 'stage', failureStage)
                .having((error) => error.error, 'error', isA<StateError>()),
          ),
        );

        expect(
          calls,
          ['markMissing', 'categories', 'news', 'starred']
              .take(failureStage.index + 1)
              .toList(),
        );
      });
    }
  });
}

Map<String, dynamic> _entryPayload(
  int id, {
  String? title,
  bool starred = false,
  int? attachmentID,
}) {
  return {
    'id': id,
    'feed_id': 1,
    'title': title ?? 'News $id',
    'url': 'https://example.com/$id',
    'comments_url': '',
    'share_code': '',
    'content': '<p>Content $id</p>',
    'hash': 'hash-$id',
    'published_at': '2026-08-20T10:00:00Z',
    'created_at': '2026-08-20T10:00:00Z',
    'status': FluxNewsState.unreadNewsStatus,
    'reading_time': 1,
    'starred': starred,
    'feed': {'title': 'Feed', 'icon': null},
    'enclosures': attachmentID == null
        ? null
        : [
            {
              'id': attachmentID,
              'entry_id': id,
              'url': 'https://example.com/$attachmentID.mp3',
              'mime_type': 'audio/mpeg',
              'media_progression': 5,
            }
          ],
  };
}

RemoteSyncFetchOperations _successfulFetchOperations() {
  return RemoteSyncFetchOperations(
    fetchNews: (_) async => NewsList(news: [], newsCount: 0),
    fetchCategories: (_) async => Categories(categories: []),
    fetchStarredNews: (_) async => NewsList(news: [], newsCount: 0),
  );
}

RemoteSyncSnapshot _emptySnapshot() {
  return RemoteSyncSnapshot(
    news: NewsList(news: [], newsCount: 0),
    categories: Categories(categories: []),
    starredNews: NewsList(news: [], newsCount: 0),
  );
}

SyncReconciliationOperations _recordingReconciliationOperations(
  List<String> calls, {
  LocalSyncReconciliationStage? failureStage,
}) {
  Future<void> record(
      String call, LocalSyncReconciliationStage currentStage) async {
    calls.add(call);
    if (failureStage == currentStage) {
      throw StateError('$call failed');
    }
  }

  return SyncReconciliationOperations(
    markMissingNewsAsRead: (_, __) => record(
      'markMissing',
      LocalSyncReconciliationStage.markMissingNewsAsRead,
    ),
    insertCategories: (_, __) => record(
      'categories',
      LocalSyncReconciliationStage.categories,
    ),
    insertNews: (_, __) => record(
      'news',
      LocalSyncReconciliationStage.news,
    ),
    updateStarredNews: (_, __) => record(
      'starred',
      LocalSyncReconciliationStage.starredNews,
    ),
  );
}
