import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/functions/audio_download_service.dart';
import 'package:flux_news/functions/logging.dart';
import 'package:flux_news/functions/sync_lock.dart';
import 'package:flux_news/functions/widget_service.dart';
import 'package:flux_news/miniflux/miniflux_backend.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

const String fluxNewsBackgroundSyncTask = 'fluxNewsBackgroundSync';
const String fluxNewsBackgroundSyncUniqueName =
    'dev.kevincfechtel.fluxNews.backgroundSync';
const String fluxNewsBackgroundProcessingSyncUniqueName =
    'dev.kevincfechtel.fluxNews.backgroundProcessingSync';

bool _backgroundSyncRunning = false;
const String _foregroundActiveAtKey = 'flux_news_foreground_active_at';
const String _lastBackgroundSyncFinishedAtKey =
    'flux_news_last_background_sync_finished_at';
const Duration _foregroundActiveStaleAfter = Duration(minutes: 2);

@pragma('vm:entry-point')
void fluxNewsBackgroundCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await _initializeBackgroundLogging();
    logThis(
        'backgroundSync',
        'WorkManager task received: task=$task inputData=${inputData ?? {}}',
        LogLevel.INFO);
    if (task != fluxNewsBackgroundSyncTask &&
        task != fluxNewsBackgroundSyncUniqueName &&
        task != fluxNewsBackgroundProcessingSyncUniqueName &&
        task != Workmanager.iOSBackgroundTask) {
      logThis('backgroundSync', 'Ignored unknown WorkManager task: $task',
          LogLevel.WARNING);
      return true;
    }

    try {
      await runFluxNewsBackgroundSync();
      return true;
    } catch (e, stackTrace) {
      logThis('backgroundSync', 'Background sync failed: $e\n$stackTrace',
          LogLevel.ERROR);
      return false;
    } finally {
      if (Platform.isIOS &&
          task == fluxNewsBackgroundProcessingSyncUniqueName) {
        await _rescheduleIosProcessingTaskIfEnabled();
      }
    }
  });
}

Future<void> initializeFluxNewsBackgroundSync() async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  logThis('backgroundSync', 'Initializing WorkManager background sync',
      LogLevel.INFO);
  await Workmanager().initialize(fluxNewsBackgroundCallbackDispatcher);
}

Future<void> configureFluxNewsBackgroundSync(FluxNewsState appState,
    {String reason = 'unspecified'}) async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  if (!appState.configValuesReadSuccessfully) {
    logThis(
        'backgroundSync',
        'Background sync configuration skipped because app configuration '
            'was not read successfully: reason=$reason',
        LogLevel.WARNING);
    return;
  }
  logThis(
      'backgroundSync',
      'Configuring background sync: reason=$reason '
          'storedInterval=${appState.backgroundSyncIntervalMinutes}m '
          'platform=${Platform.operatingSystem}',
      LogLevel.INFO);
  var storedInterval = appState.backgroundSyncIntervalMinutes;
  if (storedInterval == 0) {
    logThis(
        'backgroundSync',
        'Cancelling background sync because interval is disabled: '
            'reason=$reason',
        LogLevel.INFO);
    await Workmanager().cancelByUniqueName(fluxNewsBackgroundSyncUniqueName);
    if (Platform.isIOS) {
      await Workmanager()
          .cancelByUniqueName(fluxNewsBackgroundProcessingSyncUniqueName);
    }
    return;
  }

  const interval = FluxNewsState.enabledBackgroundSyncIntervalMinutes;
  final shouldResetPendingIosTask =
      Platform.isIOS && storedInterval != interval;
  if (storedInterval != interval) {
    logThis(
        'backgroundSync',
        'Normalizing stored background sync interval from '
            '${storedInterval}m to ${interval}m',
        LogLevel.INFO);
    storedInterval = interval;
    appState.backgroundSyncIntervalMinutes = interval;
    await appState.storage.write(
        key: FluxNewsState.secureStorageBackgroundSyncIntervalMinutesKey,
        value: interval.toString());
  }

  if (shouldResetPendingIosTask) {
    await Workmanager().cancelByUniqueName(fluxNewsBackgroundSyncUniqueName);
    await Workmanager()
        .cancelByUniqueName(fluxNewsBackgroundProcessingSyncUniqueName);
  }

  logThis(
      'backgroundSync',
      'Registering periodic background sync: interval=${interval}m '
          'storedInterval=${storedInterval}m '
          'reason=$reason '
          'platform=${Platform.operatingSystem}',
      LogLevel.INFO);
  await Workmanager().registerPeriodicTask(
    fluxNewsBackgroundSyncUniqueName,
    fluxNewsBackgroundSyncTask,
    frequency: Duration(minutes: interval),
    initialDelay: Platform.isIOS ? Duration(minutes: interval) : null,
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
  if (Platform.isIOS) {
    await _scheduleIosProcessingTask(interval);
  }
  await _logScheduledBackgroundTasks();
}

Future<void> _scheduleIosProcessingTask(int intervalMinutes) async {
  logThis(
      'backgroundSync',
      'Registering iOS processing background sync: '
          'interval=${intervalMinutes}m',
      LogLevel.INFO);
  await Workmanager().registerProcessingTask(
    fluxNewsBackgroundProcessingSyncUniqueName,
    fluxNewsBackgroundSyncTask,
    initialDelay: Duration(minutes: intervalMinutes),
    constraints: Constraints(networkType: NetworkType.connected),
  );
}

Future<void> _rescheduleIosProcessingTaskIfEnabled() async {
  try {
    final appState = FluxNewsState();
    final storedIntervalValue = await appState.storage
        .read(key: FluxNewsState.secureStorageBackgroundSyncIntervalMinutesKey);
    final storedInterval = int.tryParse(storedIntervalValue ?? '') ?? 0;
    if (storedInterval <= 0) {
      logThis(
          'backgroundSync',
          'iOS processing background sync not rescheduled: disabled',
          LogLevel.INFO);
      return;
    }

    await _scheduleIosProcessingTask(
        FluxNewsState.enabledBackgroundSyncIntervalMinutes);
  } catch (e) {
    logThis(
        'backgroundSync',
        'Could not reschedule iOS processing background sync: $e',
        LogLevel.WARNING);
  }
}

Future<void> runFluxNewsBackgroundSync() async {
  final startedAt = DateTime.now();
  if (_backgroundSyncRunning) {
    logThis(
        'backgroundSync',
        'Skipped: background sync already running in this isolate',
        LogLevel.INFO);
    return;
  }
  _backgroundSyncRunning = true;
  final appState = FluxNewsState();
  FluxNewsSyncLock? syncLock;

  try {
    await _initializeBackgroundLogging();
    if (await isFluxNewsForegroundActive()) {
      logThis('backgroundSync',
          'Skipped: app is currently active in foreground', LogLevel.INFO);
      return;
    }

    logThis(
        'backgroundSync',
        'Background sync execution started at ${startedAt.toIso8601String()}',
        LogLevel.INFO);
    syncLock = await FluxNewsSyncLock.tryAcquire('background');
    if (syncLock == null) {
      logThis(
          'backgroundSync',
          'Skipped: foreground/background sync lock is already held',
          LogLevel.INFO);
      return;
    }

    logThis('backgroundSync', 'Reading background sync configuration',
        LogLevel.INFO);
    final configReadSuccessfully = await appState.readConfigValues();
    if (!configReadSuccessfully) {
      logThis(
          'backgroundSync',
          'Skipped: background configuration could not be read; '
              'stored values and schedule remain unchanged',
          LogLevel.WARNING);
      return;
    }
    appState.applyStoredConfigValuesHeadless();
    if (appState.backgroundSyncIntervalMinutes > 0 &&
        appState.backgroundSyncIntervalMinutes !=
            FluxNewsState.enabledBackgroundSyncIntervalMinutes) {
      logThis(
          'backgroundSync',
          'Normalizing loaded background sync interval from '
              '${appState.backgroundSyncIntervalMinutes}m to '
              '${FluxNewsState.enabledBackgroundSyncIntervalMinutes}m',
          LogLevel.INFO);
      appState.backgroundSyncIntervalMinutes =
          FluxNewsState.enabledBackgroundSyncIntervalMinutes;
      await appState.storage.write(
          key: FluxNewsState.secureStorageBackgroundSyncIntervalMinutesKey,
          value: FluxNewsState.enabledBackgroundSyncIntervalMinutes.toString());
    }
    appState.db = await appState.initializeDB();
    logThis(
        'backgroundSync',
        'Configuration loaded: backgroundInterval='
            '${appState.backgroundSyncIntervalMinutes}m '
            'minifluxUrlConfigured=${appState.minifluxURL != null} '
            'apiKeyConfigured=${appState.minifluxAPIKey != null} '
            'autoDownloadAudioAfterSync=${appState.autoDownloadAudioAfterSync}',
        LogLevel.INFO);

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
    if (!authCheck) {
      logThis('backgroundSync', 'Skipped: Miniflux auth check failed',
          LogLevel.WARNING);
      return;
    }

    logThis('backgroundSync', 'Running Miniflux sync steps', LogLevel.INFO);
    await toggleNewsAsRead(appState);
    final newNews = await fetchNews(appState).onError((error, stackTrace) {
      logThis('backgroundSync', 'Fetching news failed: $error', LogLevel.ERROR);
      return NewsList(news: [], newsCount: 0);
    });
    logThis(
        'backgroundSync',
        'Fetched news: count=${newNews.news.length} '
            'reportedCount=${newNews.newsCount}',
        LogLevel.INFO);
    await markNotFetchedNewsAsRead(newNews, appState);

    Categories categories;
    try {
      categories = await fetchCategoryInformation(appState);
    } catch (error, stackTrace) {
      logThis(
          'backgroundSync',
          'Fetching categories failed; aborting background sync before local feed/category cleanup: '
              '$error\n$stackTrace',
          LogLevel.ERROR);
      return;
    }
    logThis(
        'backgroundSync',
        'Fetched categories: count=${categories.categories.length}',
        LogLevel.INFO);
    await insertCategoriesInDB(categories, appState);
    await insertNewsInDB(newNews, appState);
    AudioDownloadService.refreshMediaProgressionCacheFromSync(newNews.news);

    final starredNews =
        await fetchStarredNews(appState).onError((error, stackTrace) {
      logThis('backgroundSync', 'Fetching starred news failed: $error',
          LogLevel.ERROR);
      return NewsList(news: [], newsCount: 0);
    });
    logThis(
        'backgroundSync',
        'Fetched starred news: count=${starredNews.news.length}',
        LogLevel.INFO);
    await updateStarredNewsInDB(starredNews, appState);
    AudioDownloadService.refreshMediaProgressionCacheFromSync(starredNews.news);

    await cleanUnstarredNews(appState);
    await cleanStarredNews(appState);
    logThis('backgroundSync', 'Updating widget snapshot after background sync',
        LogLevel.INFO);
    await FluxNewsWidgetService.updateWidgetSnapshot(appState);
    await markFluxNewsBackgroundSyncFinished();
    await _markPendingForegroundAudioDownloads(appState, newNews.news);
    logThis(
        'backgroundSync',
        'Finished background sync in '
            '${DateTime.now().difference(startedAt).inSeconds}s',
        LogLevel.INFO);
  } finally {
    appState.db = null;
    await syncLock?.release();
    _backgroundSyncRunning = false;
    logThis('backgroundSync', 'Background sync execution cleanup finished',
        LogLevel.INFO);
  }
}

Future<void> markFluxNewsBackgroundSyncFinished() async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  try {
    final finishedAt = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _lastBackgroundSyncFinishedAtKey, finishedAt.toIso8601String());
    logThis(
        'backgroundSync',
        'Marked background sync finished: '
            '${finishedAt.toIso8601String()}',
        LogLevel.INFO);
  } catch (e) {
    logThis('backgroundSync', 'Could not mark background sync finished: $e',
        LogLevel.WARNING);
  }
}

Future<DateTime?> readFluxNewsBackgroundSyncFinishedAt() async {
  if (!Platform.isAndroid && !Platform.isIOS) return null;
  try {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_lastBackgroundSyncFinishedAtKey);
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  } catch (e) {
    logThis('backgroundSync',
        'Could not read background sync finished marker: $e', LogLevel.WARNING);
    return null;
  }
}

Future<void> markFluxNewsForegroundActive() async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _foregroundActiveAtKey, DateTime.now().toIso8601String());
    logThis('backgroundSync', 'Marked app foreground active', LogLevel.INFO);
  } catch (e) {
    logThis('backgroundSync', 'Could not mark app foreground active: $e',
        LogLevel.WARNING);
  }
}

Future<void> markFluxNewsForegroundInactive() async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_foregroundActiveAtKey);
    logThis('backgroundSync', 'Marked app foreground inactive', LogLevel.INFO);
  } catch (e) {
    logThis('backgroundSync', 'Could not mark app foreground inactive: $e',
        LogLevel.WARNING);
  }
}

Future<bool> isFluxNewsForegroundActive() async {
  if (!Platform.isAndroid && !Platform.isIOS) return false;
  try {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_foregroundActiveAtKey);
    if (value == null || value.isEmpty) return false;

    final activeAt = DateTime.tryParse(value);
    if (activeAt == null) {
      await prefs.remove(_foregroundActiveAtKey);
      logThis(
          'backgroundSync',
          'Ignoring invalid foreground active marker: $value',
          LogLevel.WARNING);
      return false;
    }

    final age = DateTime.now().difference(activeAt);
    if (age > _foregroundActiveStaleAfter) {
      await prefs.remove(_foregroundActiveAtKey);
      logThis(
          'backgroundSync',
          'Ignoring stale foreground active marker: '
              'ageSeconds=${age.inSeconds}',
          LogLevel.INFO);
      return false;
    }

    logThis(
        'backgroundSync',
        'Foreground active marker found: ageSeconds=${age.inSeconds}',
        LogLevel.INFO);
    return true;
  } catch (e) {
    logThis('backgroundSync', 'Could not read foreground active marker: $e',
        LogLevel.WARNING);
    return false;
  }
}

Future<void> _logScheduledBackgroundTasks() async {
  if (Platform.isAndroid) {
    try {
      final isScheduled = await Workmanager()
          .isScheduledByUniqueName(fluxNewsBackgroundSyncUniqueName);
      logThis(
          'backgroundSync',
          'Background sync scheduled check: '
              'isScheduled=$isScheduled',
          LogLevel.INFO);
    } catch (e) {
      logThis(
          'backgroundSync',
          'Could not check scheduled background sync task: $e',
          LogLevel.WARNING);
    }
  }

  if (Platform.isIOS) {
    try {
      final scheduledTasks = await Workmanager().printScheduledTasks();
      logThis('backgroundSync', 'Scheduled background tasks: $scheduledTasks',
          LogLevel.INFO);
    } catch (e) {
      logThis('backgroundSync',
          'Could not print scheduled background tasks: $e', LogLevel.WARNING);
    }
  }
}

Future<void> _initializeBackgroundLogging() async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  try {
    await initFluxNewsLogging();
  } catch (_) {
    // Logging must never prevent a background sync.
  }
}

Future<void> _markPendingForegroundAudioDownloads(
    FluxNewsState appState, List<News> newNews) async {
  if (!appState.autoDownloadAudioAfterSync) {
    logThis(
        'backgroundSync',
        'Foreground audio downloads not marked: setting disabled',
        LogLevel.INFO);
    return;
  }
  if (newNews.isEmpty) {
    logThis('backgroundSync',
        'Foreground audio downloads not marked: no new news', LogLevel.INFO);
    return;
  }
  final audioNewsIds = newNews
      .where((news) => news.attachments?.isNotEmpty == true)
      .map((news) => news.newsID)
      .toList();
  if (audioNewsIds.isEmpty) {
    logThis(
        'backgroundSync',
        'Foreground audio downloads not marked: no audio attachments',
        LogLevel.INFO);
    return;
  }

  await appState.storage.write(
      key:
          FluxNewsState.secureStoragePendingAudioDownloadAfterBackgroundSyncKey,
      value: FluxNewsState.secureStorageTrueString);
  await appState.storage.write(
      key: FluxNewsState
          .secureStoragePendingAudioDownloadNewsIdsAfterBackgroundSyncKey,
      value: jsonEncode(audioNewsIds));
  logThis(
      'backgroundSync',
      'Marked pending foreground audio downloads: '
          'count=${audioNewsIds.length}',
      LogLevel.INFO);
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
