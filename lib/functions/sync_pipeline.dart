import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/miniflux/miniflux_backend.dart' as miniflux;
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/state_management/flux_news_state.dart';

enum RemoteSyncFetchStage {
  news,
  categories,
  starredNews,
}

class RemoteSyncFetchException implements Exception {
  const RemoteSyncFetchException(this.stage, this.error, this.stackTrace);

  final RemoteSyncFetchStage stage;
  final Object error;
  final StackTrace stackTrace;

  @override
  String toString() => 'Remote sync fetch failed at ${stage.name}: $error';
}

class RemoteSyncAbortedException implements Exception {
  const RemoteSyncAbortedException();

  @override
  String toString() => 'Remote sync was aborted';
}

class RemoteSyncSnapshot {
  const RemoteSyncSnapshot({
    required this.news,
    required this.categories,
    required this.starredNews,
    this.staged = false,
    this.mainComplete = true,
    this.starredComplete = true,
  });

  final NewsList news;
  final Categories categories;
  final NewsList starredNews;
  final bool staged;
  final bool mainComplete;
  final bool starredComplete;

  Future<void> dispose(FluxNewsState appState) async {
    if (staged) await discardRemoteSyncStaging(appState);
  }
}

typedef NewsListFetcher = Future<NewsList> Function(FluxNewsState appState);
typedef CategoriesFetcher = Future<Categories> Function(FluxNewsState appState);

class RemoteSyncFetchOperations {
  const RemoteSyncFetchOperations({
    required this.fetchNews,
    required this.fetchCategories,
    required this.fetchStarredNews,
  });

  final NewsListFetcher fetchNews;
  final CategoriesFetcher fetchCategories;
  final NewsListFetcher fetchStarredNews;
}

Future<RemoteSyncSnapshot> fetchRemoteSyncSnapshot(
  FluxNewsState appState, {
  RemoteSyncFetchOperations? operations,
}) async {
  if (operations == null) {
    return _fetchStagedRemoteSyncSnapshot(appState);
  }
  final fetchOperations = operations;

  final NewsList news;
  try {
    news = await fetchOperations.fetchNews(appState);
  } catch (error, stackTrace) {
    throw RemoteSyncFetchException(
        RemoteSyncFetchStage.news, error, stackTrace);
  }
  _throwIfSyncWasAborted(appState);

  final Categories categories;
  try {
    categories = await fetchOperations.fetchCategories(appState);
  } catch (error, stackTrace) {
    throw RemoteSyncFetchException(
        RemoteSyncFetchStage.categories, error, stackTrace);
  }
  _throwIfSyncWasAborted(appState);

  final NewsList starredNews;
  try {
    starredNews = await fetchOperations.fetchStarredNews(appState);
  } catch (error, stackTrace) {
    throw RemoteSyncFetchException(
        RemoteSyncFetchStage.starredNews, error, stackTrace);
  }
  _throwIfSyncWasAborted(appState);

  return RemoteSyncSnapshot(
    news: news,
    categories: categories,
    starredNews: starredNews,
  );
}

Future<RemoteSyncSnapshot> _fetchStagedRemoteSyncSnapshot(
    FluxNewsState appState) async {
  await initializeRemoteSyncStaging(appState);
  try {
    final miniflux.PagedNewsFetchResult mainResult;
    try {
      mainResult = await miniflux.fetchNewsPages(
        appState,
        starred: false,
        consumePage: (entries) => stageRemoteSyncNewsPage(
          appState,
          entries,
          starred: false,
        ),
      );
    } on miniflux.RemoteFetchAbortedException {
      throw const RemoteSyncAbortedException();
    } catch (error, stackTrace) {
      throw RemoteSyncFetchException(
          RemoteSyncFetchStage.news, error, stackTrace);
    }
    _throwIfSyncWasAborted(appState);

    final Categories categories;
    try {
      categories = await miniflux.fetchCategoryInformation(appState);
    } catch (error, stackTrace) {
      throw RemoteSyncFetchException(
          RemoteSyncFetchStage.categories, error, stackTrace);
    }
    _throwIfSyncWasAborted(appState);

    final miniflux.PagedNewsFetchResult starredResult;
    try {
      starredResult = await miniflux.fetchNewsPages(
        appState,
        starred: true,
        consumePage: (entries) => stageRemoteSyncNewsPage(
          appState,
          entries,
          starred: true,
        ),
      );
    } on miniflux.RemoteFetchAbortedException {
      throw const RemoteSyncAbortedException();
    } catch (error, stackTrace) {
      throw RemoteSyncFetchException(
          RemoteSyncFetchStage.starredNews, error, stackTrace);
    }
    _throwIfSyncWasAborted(appState);

    return RemoteSyncSnapshot(
      news: NewsList(
        news: const [],
        newsCount: mainResult.reportedCount,
      ),
      categories: categories,
      starredNews: NewsList(
        news: const [],
        newsCount: starredResult.reportedCount,
      ),
      staged: true,
      mainComplete: mainResult.complete,
      starredComplete: starredResult.complete,
    );
  } catch (_) {
    await discardRemoteSyncStaging(appState);
    rethrow;
  }
}

void _throwIfSyncWasAborted(FluxNewsState appState) {
  if (appState.longSyncAborted) {
    throw const RemoteSyncAbortedException();
  }
}

enum LocalSyncReconciliationStage {
  markMissingNewsAsRead,
  categories,
  news,
  starredNews,
}

class LocalSyncReconciliationException implements Exception {
  const LocalSyncReconciliationException(
      this.stage, this.error, this.stackTrace);

  final LocalSyncReconciliationStage stage;
  final Object error;
  final StackTrace stackTrace;

  @override
  String toString() =>
      'Local sync reconciliation failed at ${stage.name}: $error';
}

typedef SyncReconciliationStep = Future<void> Function(
  RemoteSyncSnapshot snapshot,
  FluxNewsState appState,
);

class SyncReconciliationOperations {
  const SyncReconciliationOperations({
    required this.markMissingNewsAsRead,
    required this.insertCategories,
    required this.insertNews,
    required this.updateStarredNews,
  });

  factory SyncReconciliationOperations.production() {
    return SyncReconciliationOperations(
      markMissingNewsAsRead: (snapshot, appState) async {
        await markNotFetchedNewsAsRead(snapshot.news, appState);
      },
      insertCategories: (snapshot, appState) async {
        await insertCategoriesInDB(snapshot.categories, appState);
      },
      insertNews: (snapshot, appState) async {
        await insertNewsInDB(snapshot.news, appState);
      },
      updateStarredNews: (snapshot, appState) async {
        await updateStarredNewsInDB(snapshot.starredNews, appState);
      },
    );
  }

  final SyncReconciliationStep markMissingNewsAsRead;
  final SyncReconciliationStep insertCategories;
  final SyncReconciliationStep insertNews;
  final SyncReconciliationStep updateStarredNews;
}

Future<void> reconcileRemoteSyncSnapshot(
  RemoteSyncSnapshot snapshot,
  FluxNewsState appState, {
  SyncReconciliationOperations? operations,
  Future<void> Function()? stagedNewsBeforeCommitForTesting,
}) async {
  if (snapshot.staged && operations == null) {
    await _runReconciliationStep(
      LocalSyncReconciliationStage.categories,
      () => insertCategoriesInDB(snapshot.categories, appState),
    );
    await _runReconciliationStep(
      LocalSyncReconciliationStage.news,
      () => reconcileStagedRemoteNewsInTransaction(
        appState,
        mainComplete: snapshot.mainComplete,
        starredComplete: snapshot.starredComplete,
        beforeCommitForTesting: stagedNewsBeforeCommitForTesting,
      ),
    );
    return;
  }
  final reconciliationOperations =
      operations ?? SyncReconciliationOperations.production();

  await _runReconciliationStep(
    LocalSyncReconciliationStage.markMissingNewsAsRead,
    () => reconciliationOperations.markMissingNewsAsRead(snapshot, appState),
  );
  await _runReconciliationStep(
    LocalSyncReconciliationStage.categories,
    () => reconciliationOperations.insertCategories(snapshot, appState),
  );
  await _runReconciliationStep(
    LocalSyncReconciliationStage.news,
    () => reconciliationOperations.insertNews(snapshot, appState),
  );
  await _runReconciliationStep(
    LocalSyncReconciliationStage.starredNews,
    () => reconciliationOperations.updateStarredNews(snapshot, appState),
  );
}

Future<void> _runReconciliationStep(
  LocalSyncReconciliationStage stage,
  Future<void> Function() operation,
) async {
  try {
    await operation();
  } catch (error, stackTrace) {
    throw LocalSyncReconciliationException(stage, error, stackTrace);
  }
}
