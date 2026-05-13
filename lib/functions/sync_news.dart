import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flux_news/functions/audio_download_service.dart';
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:flux_news/functions/logging.dart';
import 'package:flux_news/miniflux/miniflux_backend.dart';
import 'package:flux_news/models/news_model.dart';

Future<void> syncNews(FluxNewsState appState, BuildContext context) async {
  logThis('syncNews', 'Start syncing with miniflux server.', LogLevel.INFO);
  appState.longSyncAlerted = false;
  appState.longSyncAborted = false;
  final stopwatch = Stopwatch();
  if (appState.debugMode) {
    // Debugging execution time with many news
    stopwatch.start();
  }

  // this is the part where the app syncs with the miniflux server
  // to reduce the appearance of error pop ups,
  // the error handling in all steps is to only through new errors,
  // if the new error is not already thrown by a previous step.
  // set the state to sync
  // (needed for the processing cycle and the positioning of the list view)
  appState.syncProcess = true;
  appState.refreshView();
  // also resetting the error string for new errors occurring within this sync
  appState.errorString = '';

  // remove the native splash after updating the list view
  FlutterNativeSplash.remove();
  // check the miniflux credentials to enable the sync
  bool authCheck = await checkMinifluxCredentials(appState.minifluxURL, appState.minifluxAPIKey, appState)
      .onError((error, stackTrace) {
    logThis('authCheck', 'Caught an error in authCheck function! : ${error.toString()}', LogLevel.ERROR);
    if (context.mounted) {
      if (appState.errorString != AppLocalizations.of(context)!.communicateionMinifluxError) {
        appState.errorString = AppLocalizations.of(context)!.communicateionMinifluxError;
        appState.newError = true;
        appState.refreshView();
      }
    }
    return false;
  });

  // if there is no new error (network error), set the errorOnMinifluxAuth flag
  if (!appState.newError) {
    appState.errorOnMinifluxAuth = !authCheck;
  }

  // check if there are no authentication errors before start syncing
  if (!appState.errorOnMinifluxAuth && appState.errorString == '') {
    // at first toggle news as read so that this news don't show up in the next step
    await toggleNewsAsRead(appState).onError((error, stackTrace) {
      logThis(
          'toggleNewsAsRead', 'Caught an error in toggleNewsAsRead function! : ${error.toString()}', LogLevel.ERROR);
      if (context.mounted) {
        if (appState.errorString != AppLocalizations.of(context)!.communicateionMinifluxError) {
          appState.errorString = AppLocalizations.of(context)!.communicateionMinifluxError;
          appState.newError = true;
          appState.refreshView();
        }
      }
    });

    // fetch only unread news from the miniflux server
    NewsList newNews = await fetchNews(appState).onError((error, stackTrace) {
      logThis('fetchNews', 'Caught an error in fetchNews function! : ${error.toString()}', LogLevel.ERROR);
      if (context.mounted) {
        if (appState.errorString != AppLocalizations.of(context)!.communicateionMinifluxError) {
          appState.errorString = AppLocalizations.of(context)!.communicateionMinifluxError;
          appState.newError = true;
          appState.refreshView();
        }
      }
      return NewsList(news: [], newsCount: 0);
    });
    if (!appState.longSyncAborted && appState.errorString == '') {
      // if news in this app are marked as unread, but don't exist in the list from
      // the previous step, this news must be marked as read by another app.
      // So this step mark news, which are not fetched previous as read in this app.
      await markNotFetchedNewsAsRead(newNews, appState).onError((error, stackTrace) {
        logThis('markNotFetchedNewsAsRead',
            'Caught an error in markNotFetchedNewsAsRead function! : ${error.toString()}', LogLevel.ERROR);
        if (context.mounted) {
          if (appState.errorString != AppLocalizations.of(context)!.databaseError) {
            appState.errorString = AppLocalizations.of(context)!.databaseError;
            appState.newError = true;
            appState.refreshView();
          }
        }
        return 0;
      });
    }

    Categories newCategories = Categories(categories: []);
    if (!appState.longSyncAborted) {
      // fetch the categories from the miniflux server
      newCategories = await fetchCategoryInformation(appState).onError((error, stackTrace) {
        logThis('fetchCategoryInformation',
            'Caught an error in fetchCategoryInformation function! : ${error.toString()}', LogLevel.ERROR);
        if (context.mounted) {
          if (appState.errorString != AppLocalizations.of(context)!.communicateionMinifluxError) {
            appState.errorString = AppLocalizations.of(context)!.communicateionMinifluxError;
            appState.newError = true;
            appState.refreshView();
          }
        }
        return Future<Categories>.value(Categories(categories: []));
      });
    }

    if (!appState.longSyncAborted && appState.errorString == '') {
      // insert or update the fetched categories in the database
      await insertCategoriesInDB(newCategories, appState).onError((error, stackTrace) {
        logThis('insertCategoriesInDB', 'Caught an error in insertCategoriesInDB function! : ${error.toString()}',
            LogLevel.ERROR);
        if (context.mounted) {
          if (appState.errorString != AppLocalizations.of(context)!.databaseError) {
            appState.errorString = AppLocalizations.of(context)!.databaseError;
            appState.newError = true;
            appState.refreshView();
          }
        }
        return 0;
      });
    }

    if (!appState.longSyncAborted && appState.errorString == '') {
      // insert or update the fetched news in the database
      await insertNewsInDB(newNews, appState).onError((error, stackTrace) {
        logThis('insertNewsInDB', 'Caught an error in insertNewsInDB function! : ${error.toString()}', LogLevel.ERROR);
        if (context.mounted) {
          if (appState.errorString != AppLocalizations.of(context)!.databaseError) {
            appState.errorString = AppLocalizations.of(context)!.databaseError;
            appState.newError = true;
            appState.refreshView();
          }
        }
        return 0;
      });

      // Refresh the in-memory mediaProgression cache so CarPlay / Android Auto
      // pick up the server's latest position on the next playback without a DB query.
      AudioDownloadService.refreshMediaProgressionCacheFromSync(newNews.news);

      if (appState.autoDownloadAudioAfterSync) {
        unawaited(AudioDownloadService.downloadAudioForNewsList(
          newsList: newNews.news,
          retentionDays: appState.audioDownloadRetentionDays,
          onlyOnWifi: appState.downloadAudioOnlyOnWifi,
        ));
      }
    }
    if (!appState.longSyncAborted) {
      // after inserting the news, renew the list view with the new news
      appState.scrollPosition = 0;
      appState.storage.write(key: FluxNewsState.secureStorageSavedScrollPositionKey, value: '0');
      appState.newsList = queryNewsFromDB(appState).whenComplete(() {
        appState.jumpToItem(0);
      });
    }

    if (!appState.longSyncAborted) {
      // renew the news count of "All News"
      if (context.mounted) {
        await renewAllNewsCount(appState, context).onError((error, stackTrace) {
          logThis('renewAllNewsCount', 'Caught an error in renewAllNewsCount function! : ${error.toString()}',
              LogLevel.ERROR);
        });
      }
      appState.refreshView();
    }
    // remove the native splash after updating the list view
    // Moved to the beginning of sync
    //FlutterNativeSplash.remove();

    NewsList starredNews = NewsList(news: [], newsCount: 0);
    if (!appState.longSyncAborted) {
      // fetch the starred news (read or unread) from the miniflux server
      starredNews = await fetchStarredNews(appState).onError((error, stackTrace) {
        logThis(
            'fetchStarredNews', 'Caught an error in fetchStarredNews function! : ${error.toString()}', LogLevel.ERROR);
        if (context.mounted) {
          if (appState.errorString != AppLocalizations.of(context)!.communicateionMinifluxError) {
            appState.errorString = AppLocalizations.of(context)!.communicateionMinifluxError;
            appState.newError = true;
            appState.refreshView();
          }
        }
        return NewsList(news: [], newsCount: 0);
      });
    }

    if (!appState.longSyncAborted) {
      // update the previous fetched starred news in the database
      // maybe some other app has marked a news a starred
      // also refresh progression cache for starred news (includes read+starred)
      await updateStarredNewsInDB(starredNews, appState).onError((error, stackTrace) {
        logThis('updateStarredNewsInDB', 'Caught an error in updateStarredNewsInDB function! ${error.toString()}',
            LogLevel.ERROR);
        if (context.mounted) {
          if (appState.errorString != AppLocalizations.of(context)!.databaseError) {
            appState.errorString = AppLocalizations.of(context)!.databaseError;
            appState.newError = true;
            appState.refreshView();
          }
        }
        return 0;
      });
      // Refresh progression cache for starred (read or unread) news.
      AudioDownloadService.refreshMediaProgressionCacheFromSync(starredNews.news);
    }

    if (!appState.longSyncAborted) {
      // Sync media progression for downloaded episodes not covered by the
      // regular syncs (i.e. already-read, non-starred downloaded podcasts).
      await _syncDownloadedAudioProgressions(
        appState,
        alreadySyncedIds: {
          ...newNews.news.map((n) => n.newsID),
          ...starredNews.news.map((n) => n.newsID),
        },
      ).onError((e, _) => logThis('syncDownloadedAudioProgressions',
          'Error syncing downloaded progression: $e', LogLevel.ERROR));
    }

    if (!appState.longSyncAborted) {
      // delete all unstarred news depending the defined limit in the settings,
      await cleanUnstarredNews(appState).onError((error, stackTrace) {
        logThis('cleanUnstarredNews', 'Caught an error in cleanUnstarredNews function! : ${error.toString()}',
            LogLevel.ERROR);
        if (context.mounted) {
          if (appState.errorString != AppLocalizations.of(context)!.databaseError) {
            appState.errorString = AppLocalizations.of(context)!.databaseError;
            appState.newError = true;
            appState.refreshView();
          }
        }
      });
    }

    if (!appState.longSyncAborted) {
      // delete all starred news depending the defines limit in the settings
      await cleanStarredNews(appState).onError((error, stackTrace) {
        logThis(
            'cleanStarredNews', 'Caught an error in cleanStarredNews function! : ${error.toString()}', LogLevel.ERROR);
        if (context.mounted) {
          if (appState.errorString != AppLocalizations.of(context)!.databaseError) {
            appState.errorString = AppLocalizations.of(context)!.databaseError;
            appState.newError = true;
            appState.refreshView();
          }
        }
      });
    }

    if (!appState.longSyncAborted) {
      // update the starred (bookmarked) counter of news
      try {
        if (context.mounted) {
          updateStarredCounter(appState, context);
        }
      } catch (e) {
        logThis('updateStarredCounter', 'Caught an error in updateStarredCounter function! : ${e.toString()}',
            LogLevel.ERROR);

        if (context.mounted) {
          if (appState.errorString != AppLocalizations.of(context)!.databaseError) {
            appState.errorString = AppLocalizations.of(context)!.databaseError;
            appState.newError = true;
            appState.refreshView();
          }
        }
      }
    }

    if (!appState.longSyncAborted) {
      // fetch the updated categories from the db and generate the category view
      if (context.mounted) {
        appState.categoryList = queryCategoriesFromDB(appState, context);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (newNews.newsCount > 0 && appState.feedIDs == null) {
          // if new news exists and the "All News" category is selected,
          // set the list view position to the top
          appState.jumpToItem(0);
        } else if (starredNews.newsCount > 0 && appState.feedIDs != null) {
          if (appState.feedIDs != null && appState.feedIDs!.isNotEmpty && appState.feedIDs?.first == -1) {
            // if new news exists and the "Bookmarked" category is selected,
            // set the list view position to the top
            appState.jumpToItem(0);
          }
        }
      });
    }

    // end the sync process
    appState.syncProcess = false;
    appState.scrolloverSyncFailed = false;
    appState.refreshView();
  } else {
    // Auth failed or network error before sync — load locally cached news as fallback.
    appState.newsList = queryNewsFromDB(appState);
    if (context.mounted) {
      try {
        updateStarredCounter(appState, context);
        await renewAllNewsCount(appState, context);
      } catch (_) {}
    }
    appState.syncProcess = false;
    appState.refreshView();
  }
  if (appState.debugMode) {
    // Debugging execution time with many news
    logThis('syncNews', 'Syncing with miniflux server executed in ${stopwatch.elapsed}', LogLevel.INFO);
  }
  logThis('syncNews', 'Finished syncing with miniflux server.', LogLevel.INFO);
}

/// Fetches the latest media_progression from the server for all locally
/// Syncs media progression for all locally downloaded episodes in both
/// directions:
///
/// INBOUND (Server → App): fetches the latest media_progression from the
/// server for episodes not covered by the regular sync (read, non-starred),
/// then updates the DB and in-memory cache.
///
/// OUTBOUND (App → Server): for every downloaded episode, compares the local
/// Keychain position with the server cache value. If the local position is
/// ahead (e.g. because CarPlay/Android Auto was terminated before the
/// fire-and-forget PUT could complete), it is pushed to the server here.
Future<void> _syncDownloadedAudioProgressions(
  FluxNewsState appState, {
  required Set<int> alreadySyncedIds,
}) async {
  final downloadedNewsIds = await getDownloadedAudioNewsIds(appState);
  if (downloadedNewsIds.isEmpty) return;

  // ── INBOUND ──────────────────────────────────────────────────────────────
  // Fetch server progression for read/non-starred episodes not yet covered.
  final toFetch = downloadedNewsIds.difference(alreadySyncedIds);
  if (toFetch.isNotEmpty) {
    if (appState.debugMode) {
      logThis('syncDownloadedAudioProgressions',
          'INBOUND: fetching progression for ${toFetch.length} read episode(s).', LogLevel.INFO);
    }
    final fetched = await fetchEntriesProgressionByIds(appState, toFetch.toList());
    if (fetched.news.isNotEmpty) {
      await updateAttachmentProgressionsInDB(fetched, appState);
      AudioDownloadService.refreshMediaProgressionCacheFromSync(fetched.news);
      if (appState.debugMode) {
        logThis('syncDownloadedAudioProgressions',
            'INBOUND: updated ${fetched.news.length} episode(s).', LogLevel.INFO);
      }
    }
  } else if (appState.debugMode) {
    logThis('syncDownloadedAudioProgressions',
        'INBOUND: all downloaded episodes already covered by regular sync.', LogLevel.INFO);
  }

  // ── OUTBOUND ─────────────────────────────────────────────────────────────
  // For every downloaded episode: if the local Keychain position is ahead of
  // the server cache, push it to the server. This handles cases where
  // CarPlay / Android Auto was terminated before the fire-and-forget PUT
  // could complete.
  final downloadedAudios = await AudioDownloadService.getDownloadedAudios();
  int pushedCount = 0;

  for (final download in downloadedAudios) {
    if (download.attachmentID < 0) continue;

    // Resolve newsID: in-memory cache first, then DB.
    int? newsID = AudioDownloadService.getDownloadNewsId(download.attachmentID);
    newsID ??= await queryNewsIdByAttachmentId(appState, download.attachmentID);
    if (newsID == null) continue;

    // Read local Keychain position (milliseconds).
    String? localStr;
    try {
      localStr = await appState.storage.read(
          key: '${FluxNewsState.audioProgressKeyPrefix}$newsID');
    } catch (_) {
      continue;
    }
    final localMs = localStr != null ? int.tryParse(localStr) ?? 0 : 0;
    if (localMs <= 0) continue;

    // Server position from in-memory cache (seconds → milliseconds).
    final serverSeconds =
        AudioDownloadService.getDownloadMediaProgression(download.attachmentID) ?? 0;

    if (localMs > serverSeconds * 1000) {
      if (appState.debugMode) {
        logThis('syncDownloadedAudioProgressions',
            'OUTBOUND: attachment ${download.attachmentID} — local ${localMs ~/ 1000}s > server ${serverSeconds}s, pushing.',
            LogLevel.INFO);
      }
      await syncMediaProgression(
          appState, newsID, download.attachmentID, localMs ~/ 1000);
      pushedCount++;
    }
  }

  if (appState.debugMode && pushedCount > 0) {
    logThis('syncDownloadedAudioProgressions',
        'OUTBOUND: pushed $pushedCount episode(s) to server.', LogLevel.INFO);
  }
}
