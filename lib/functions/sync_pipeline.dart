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
  });

  final NewsList news;
  final Categories categories;
  final NewsList starredNews;
}

typedef NewsListFetcher = Future<NewsList> Function(FluxNewsState appState);
typedef CategoriesFetcher = Future<Categories> Function(FluxNewsState appState);

class RemoteSyncFetchOperations {
  const RemoteSyncFetchOperations({
    required this.fetchNews,
    required this.fetchCategories,
    required this.fetchStarredNews,
  });

  factory RemoteSyncFetchOperations.production() {
    return RemoteSyncFetchOperations(
      fetchNews: (appState) => miniflux.fetchNews(appState),
      fetchCategories: miniflux.fetchCategoryInformation,
      fetchStarredNews: (appState) => miniflux.fetchStarredNews(appState),
    );
  }

  final NewsListFetcher fetchNews;
  final CategoriesFetcher fetchCategories;
  final NewsListFetcher fetchStarredNews;
}

Future<RemoteSyncSnapshot> fetchRemoteSyncSnapshot(
  FluxNewsState appState, {
  RemoteSyncFetchOperations? operations,
}) async {
  final fetchOperations = operations ?? RemoteSyncFetchOperations.production();

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
}) async {
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
