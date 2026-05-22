import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/functions/audio_download_service.dart';
import 'package:flux_news/functions/logging.dart';
import 'package:flux_news/functions/sync_lock.dart';
import 'package:flux_news/functions/widget_service.dart';
import 'package:flux_news/miniflux/miniflux_backend.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:workmanager/workmanager.dart';

const String fluxNewsBackgroundSyncTask = 'fluxNewsBackgroundSync';
const String fluxNewsBackgroundSyncUniqueName =
    'dev.kevincfechtel.fluxNews.backgroundSync';

bool _backgroundSyncRunning = false;

@pragma('vm:entry-point')
void fluxNewsBackgroundCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (task != fluxNewsBackgroundSyncTask &&
        task != fluxNewsBackgroundSyncUniqueName &&
        task != Workmanager.iOSBackgroundTask) {
      return true;
    }

    try {
      await runFluxNewsBackgroundSync();
      return true;
    } catch (e) {
      logThis('backgroundSync', 'Background sync failed: $e', LogLevel.ERROR);
      return false;
    }
  });
}

Future<void> initializeFluxNewsBackgroundSync() async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  await Workmanager().initialize(fluxNewsBackgroundCallbackDispatcher);
}

Future<void> configureFluxNewsBackgroundSync(FluxNewsState appState) async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  final interval = appState.backgroundSyncIntervalMinutes;
  if (interval == 0) {
    await Workmanager().cancelByUniqueName(fluxNewsBackgroundSyncUniqueName);
    return;
  }

  await Workmanager().registerPeriodicTask(
    fluxNewsBackgroundSyncUniqueName,
    fluxNewsBackgroundSyncTask,
    frequency: Duration(minutes: interval),
    initialDelay: Platform.isIOS ? Duration(minutes: interval) : null,
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}

Future<void> runFluxNewsBackgroundSync() async {
  if (_backgroundSyncRunning) return;
  _backgroundSyncRunning = true;
  final appState = FluxNewsState();
  FluxNewsSyncLock? syncLock;

  try {
    await _initializeBackgroundLogging();
    syncLock = await FluxNewsSyncLock.tryAcquire('background');
    if (syncLock == null) return;

    logThis('backgroundSync', 'Starting background sync', LogLevel.INFO);
    await appState.readConfigValues();
    appState.applyStoredConfigValuesHeadless();
    appState.db = await appState.initializeDB();

    if (appState.minifluxURL == null || appState.minifluxAPIKey == null) {
      logThis('backgroundSync', 'Skipped: missing Miniflux config',
          LogLevel.WARNING);
      return;
    }

    final authCheck = await checkMinifluxCredentials(
            appState.minifluxURL, appState.minifluxAPIKey, appState)
        .onError((error, stackTrace) {
      logThis('backgroundSync', 'Auth check failed: $error', LogLevel.ERROR);
      return false;
    });
    if (!authCheck) return;

    await toggleNewsAsRead(appState);
    final newNews = await fetchNews(appState)
        .onError((_, __) => NewsList(news: [], newsCount: 0));
    await markNotFetchedNewsAsRead(newNews, appState);

    final categories = await fetchCategoryInformation(appState)
        .onError((_, __) => Categories(categories: []));
    await insertCategoriesInDB(categories, appState);
    await insertNewsInDB(newNews, appState);
    AudioDownloadService.refreshMediaProgressionCacheFromSync(newNews.news);

    final starredNews = await fetchStarredNews(appState)
        .onError((_, __) => NewsList(news: [], newsCount: 0));
    await updateStarredNewsInDB(starredNews, appState);
    AudioDownloadService.refreshMediaProgressionCacheFromSync(starredNews.news);

    await cleanUnstarredNews(appState);
    await cleanStarredNews(appState);
    await FluxNewsWidgetService.updateWidgetSnapshot(appState);
    await _markPendingForegroundAudioDownloads(appState, newNews.news);
    logThis('backgroundSync', 'Finished background sync', LogLevel.INFO);
  } finally {
    await appState.db?.close();
    await syncLock?.release();
    _backgroundSyncRunning = false;
  }
}

Future<void> _initializeBackgroundLogging() async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  try {
    await FlutterLogs.initLogs(
        logLevelsEnabled: [
          LogLevel.INFO,
          LogLevel.WARNING,
          LogLevel.ERROR,
          LogLevel.SEVERE
        ],
        timeStampFormat: TimeStampFormat.TIME_FORMAT_READABLE,
        directoryStructure: DirectoryStructure.FOR_DATE,
        logFileExtension: LogFileExtension.LOG,
        logsWriteDirectoryName: FluxNewsState.logsWriteDirectoryName,
        logsExportDirectoryName: FluxNewsState.logsExportDirectoryName,
        debugFileOperations: false,
        logsRetentionPeriodInDays: 14,
        zipsRetentionPeriodInDays: 3,
        isDebuggable: false);
  } catch (_) {
    // Logging must never prevent a background sync.
  }
}

Future<void> _markPendingForegroundAudioDownloads(
    FluxNewsState appState, List<News> newNews) async {
  if (!appState.autoDownloadAudioAfterSync || newNews.isEmpty) return;
  final audioNewsIds = newNews
      .where((news) => news.attachments?.isNotEmpty == true)
      .map((news) => news.newsID)
      .toList();
  if (audioNewsIds.isEmpty) return;

  await appState.storage.write(
      key:
          FluxNewsState.secureStoragePendingAudioDownloadAfterBackgroundSyncKey,
      value: FluxNewsState.secureStorageTrueString);
  await appState.storage.write(
      key: FluxNewsState
          .secureStoragePendingAudioDownloadNewsIdsAfterBackgroundSyncKey,
      value: jsonEncode(audioNewsIds));
}

Future<void> runPendingForegroundAudioDownloads(FluxNewsState appState) async {
  if (!appState.autoDownloadAudioAfterSync) return;
  final pending = await appState.storage.read(
      key: FluxNewsState
          .secureStoragePendingAudioDownloadAfterBackgroundSyncKey);
  if (pending != FluxNewsState.secureStorageTrueString) return;

  await appState.storage.write(
      key:
          FluxNewsState.secureStoragePendingAudioDownloadAfterBackgroundSyncKey,
      value: FluxNewsState.secureStorageFalseString);

  final newsIdsValue = await appState.storage.read(
      key: FluxNewsState
          .secureStoragePendingAudioDownloadNewsIdsAfterBackgroundSyncKey);
  await appState.storage.delete(
      key: FluxNewsState
          .secureStoragePendingAudioDownloadNewsIdsAfterBackgroundSyncKey);

  final news = <News>[];
  if (newsIdsValue != null && newsIdsValue.isNotEmpty) {
    final decoded = jsonDecode(newsIdsValue);
    if (decoded is List) {
      for (final id in decoded) {
        final newsID = id is int ? id : int.tryParse(id.toString());
        if (newsID == null) continue;
        final item = await queryNewsByIdFromDB(appState, newsID);
        if (item != null) news.add(item);
      }
    }
  }

  if (news.isEmpty) return;
  unawaited(AudioDownloadService.downloadAudioForNewsList(
    newsList: news,
    retentionDays: appState.audioDownloadRetentionDays,
    onlyOnWifi: appState.downloadAudioOnlyOnWifi,
  ));
}
