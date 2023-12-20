import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flux_news/database_backend.dart';
import 'package:flux_news/flux_news_state.dart';
import 'package:flux_news/logging.dart';
import 'package:flux_news/miniflux_backend.dart';
import 'package:flux_news/news_model.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_gen/gen_l10n/flux_news_localizations.dart';

Future<void> syncNews(FluxNewsState appState, BuildContext context) async {
  logThis('syncNews', 'Start syncing with miniflux server.', LogLevel.INFO);

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

  // check the miniflux credentials to enable the sync
  bool authCheck = await checkMinifluxCredentials(http.Client(),
          appState.minifluxURL, appState.minifluxAPIKey, appState)
      .onError((error, stackTrace) {
    logThis(
        'authCheck',
        'Caught an error in authCheck function! : ${error.toString()}',
        LogLevel.ERROR);

    if (appState.errorString !=
        AppLocalizations.of(context)!.communicateionMinifluxError) {
      appState.errorString =
          AppLocalizations.of(context)!.communicateionMinifluxError;
      appState.newError = true;
      appState.refreshView();
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
    await toggleNewsAsRead(http.Client(), appState)
        .onError((error, stackTrace) {
      logThis(
          'toggleNewsAsRead',
          'Caught an error in toggleNewsAsRead function! : ${error.toString()}',
          LogLevel.ERROR);

      if (appState.errorString !=
          AppLocalizations.of(context)!.communicateionMinifluxError) {
        appState.errorString =
            AppLocalizations.of(context)!.communicateionMinifluxError;
        appState.newError = true;
        appState.refreshView();
      }
    });

    // fetch only unread news from the miniflux server
    NewsList newNews =
        await fetchNews(http.Client(), appState).onError((error, stackTrace) {
      logThis(
          'fetchNews',
          'Caught an error in fetchNews function! : ${error.toString()}',
          LogLevel.ERROR);

      if (appState.errorString !=
          AppLocalizations.of(context)!.communicateionMinifluxError) {
        appState.errorString =
            AppLocalizations.of(context)!.communicateionMinifluxError;
        appState.newError = true;
        appState.refreshView();
      }
      return NewsList(news: [], newsCount: 0);
    });

    // if news in this app are marked as unread, but don't exist in the list from
    // the previous step, this news must be marked as read by another app.
    // So this step mark news, which are not fetched previous as read in this app.
    await markNotFetchedNewsAsRead(newNews, appState)
        .onError((error, stackTrace) {
      logThis(
          'markNotFetchedNewsAsRead',
          'Caught an error in markNotFetchedNewsAsRead function! : ${error.toString()}',
          LogLevel.ERROR);

      if (appState.errorString != AppLocalizations.of(context)!.databaseError) {
        appState.errorString = AppLocalizations.of(context)!.databaseError;
        appState.newError = true;
        appState.refreshView();
      }
      return 0;
    });

    // insert or update the fetched news in the database
    await insertNewsInDB(newNews, appState).onError((error, stackTrace) {
      logThis(
          'insertNewsInDB',
          'Caught an error in insertNewsInDB function! : ${error.toString()}',
          LogLevel.ERROR);

      if (appState.errorString != AppLocalizations.of(context)!.databaseError) {
        appState.errorString = AppLocalizations.of(context)!.databaseError;
        appState.newError = true;
        appState.refreshView();
      }
      return 0;
    });

    // after inserting the news, renew the list view with the new news
    appState.scrollPosition = 0;
    appState.storage.write(
        key: FluxNewsState.secureStorageSavedScrollPositionKey, value: '0');
    appState.newsList =
        queryNewsFromDB(appState, appState.feedIDs).whenComplete(() {
      waitUntilNewsListBuild(appState).whenComplete(
        () {
          // set the view position to the top of the new list
          if (appState.itemScrollController.isAttached) {
            appState.itemScrollController.jumpTo(index: 0);
          }
        },
      );
    });

    // renew the news count of "All News"
    if (context.mounted) {
      await renewAllNewsCount(appState, context).onError((error, stackTrace) {
        logThis(
            'renewAllNewsCount',
            'Caught an error in renewAllNewsCount function! : ${error.toString()}',
            LogLevel.ERROR);
      });
    }
    appState.refreshView();
    // remove the native splash after updating the list view
    FlutterNativeSplash.remove();

    // fetch the categories from the miniflux server
    Categories newCategories =
        await fetchCategoryInformation(http.Client(), appState)
            .onError((error, stackTrace) {
      logThis(
          'fetchCategoryInformation',
          'Caught an error in fetchCategoryInformation function! : ${error.toString()}',
          LogLevel.ERROR);

      if (appState.errorString !=
          AppLocalizations.of(context)!.communicateionMinifluxError) {
        appState.errorString =
            AppLocalizations.of(context)!.communicateionMinifluxError;
        appState.newError = true;
        appState.refreshView();
      }
      return Future<Categories>.value(Categories(categories: []));
    });

    // insert or update the fetched categories in the database
    await insertCategoriesInDB(newCategories, appState)
        .onError((error, stackTrace) {
      logThis(
          'insertCategoriesInDB',
          'Caught an error in insertCategoriesInDB function! : ${error.toString()}',
          LogLevel.ERROR);

      if (appState.errorString != AppLocalizations.of(context)!.databaseError) {
        appState.errorString = AppLocalizations.of(context)!.databaseError;
        appState.newError = true;
        appState.refreshView();
      }
      return 0;
    });

    // fetch the starred news (read or unread) from the miniflux server
    NewsList starredNews = await fetchStarredNews(http.Client(), appState)
        .onError((error, stackTrace) {
      logThis(
          'fetchStarredNews',
          'Caught an error in fetchStarredNews function! : ${error.toString()}',
          LogLevel.ERROR);

      if (appState.errorString !=
          AppLocalizations.of(context)!.communicateionMinifluxError) {
        appState.errorString =
            AppLocalizations.of(context)!.communicateionMinifluxError;
        appState.newError = true;
        appState.refreshView();
      }
      return NewsList(news: [], newsCount: 0);
    });

    // update the previous fetched starred news in the database
    // maybe some other app has marked a news a starred
    await updateStarredNewsInDB(starredNews, appState)
        .onError((error, stackTrace) {
      logThis(
          'updateStarredNewsInDB',
          'Caught an error in updateStarredNewsInDB function! ${error.toString()}',
          LogLevel.ERROR);

      if (appState.errorString != AppLocalizations.of(context)!.databaseError) {
        appState.errorString = AppLocalizations.of(context)!.databaseError;
        appState.newError = true;
        appState.refreshView();
      }
      return 0;
    });

    // delete all unstarred news depending the defined limit in the settings,
    await cleanUnstarredNews(appState).onError((error, stackTrace) {
      logThis(
          'cleanUnstarredNews',
          'Caught an error in cleanUnstarredNews function! : ${error.toString()}',
          LogLevel.ERROR);

      if (appState.errorString != AppLocalizations.of(context)!.databaseError) {
        appState.errorString = AppLocalizations.of(context)!.databaseError;
        appState.newError = true;
        appState.refreshView();
      }
    });

    // delete all starred news depending the defines limit in the settings
    await cleanStarredNews(appState).onError((error, stackTrace) {
      logThis(
          'cleanStarredNews',
          'Caught an error in cleanStarredNews function! : ${error.toString()}',
          LogLevel.ERROR);

      if (appState.errorString != AppLocalizations.of(context)!.databaseError) {
        appState.errorString = AppLocalizations.of(context)!.databaseError;
        appState.newError = true;
        appState.refreshView();
      }
    });

    // update the starred (bookmarked) counter of news
    try {
      if (context.mounted) {
        updateStarredCounter(appState, context);
      }
    } catch (e) {
      logThis(
          'updateStarredCounter',
          'Caught an error in updateStarredCounter function! : ${e.toString()}',
          LogLevel.ERROR);

      if (context.mounted) {
        if (appState.errorString !=
            AppLocalizations.of(context)!.databaseError) {
          appState.errorString = AppLocalizations.of(context)!.databaseError;
          appState.newError = true;
          appState.refreshView();
        }
      }
    }

    // fetch the updated categories from the db and generate the category view
    if (context.mounted) {
      appState.categoryList = queryCategoriesFromDB(appState, context);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (newNews.newsCount > 0 && appState.feedIDs == null) {
        // if new news exists and the "All News" category is selected,
        // set the list view position to the top
        if (appState.itemScrollController.isAttached) {
          appState.itemScrollController.jumpTo(index: 0);
        }
      } else if (starredNews.newsCount > 0 && appState.feedIDs != null) {
        if (appState.feedIDs?.first == -1) {
          // if new news exists and the "Bookmarked" category is selected,
          // set the list view position to the top
          appState.itemScrollController.jumpTo(index: 0);
        }
      }
    });
    // end the sync process
    appState.syncProcess = false;
    appState.refreshView();
  } else {
    // end the sync process
    appState.syncProcess = false;
    appState.refreshView();
    // remove the native splash after updating the list view
    FlutterNativeSplash.remove();
  }
  logThis('syncNews', 'Finished syncing with miniflux server.', LogLevel.INFO);
}

Future<void> waitUntilNewsListBuild(FluxNewsState appState) async {
  final completer = Completer();
  if (appState.itemScrollController.isAttached) {
    completer.complete();
  } else {
    await Future.delayed(const Duration(milliseconds: 1));
    return waitUntilNewsListBuild(appState);
  }
  return completer.future;
}
