import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flux_news/database_backend.dart';
import 'package:flux_news/flux_news_counter_state.dart';
import 'package:flux_news/flux_news_state.dart';
import 'package:flux_news/miniflux_backend.dart';
import 'package:flux_news/news_model.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_gen/gen_l10n/flux_news_localizations.dart';

// this is a helper function to get the actual tab position
// this position is used to open the context menue of the news card here
void getTapPosition(
    TapDownDetails details, BuildContext context, FluxNewsState appState) {
  final RenderBox referenceBox = context.findRenderObject() as RenderBox;
  appState.tapPosition = referenceBox.globalToLocal(details.globalPosition);
}

// here is the function to show the context menu
// this menu give the option to mark a news as read or unread and to bookmark a news
void showContextMenu(News news, BuildContext context, FluxNewsState appState,
    bool searchView) async {
  final RenderObject? overlay = Overlay.of(context).context.findRenderObject();
  FluxNewsState appState = context.read<FluxNewsState>();
  FluxNewsCounterState appCounterState = context.read<FluxNewsCounterState>();

  final result = await showMenu(
      context: context,
      // open the menu on the prevoius recognized position
      position: RelativeRect.fromRect(
          Rect.fromLTWH(
              appState.tapPosition.dx, appState.tapPosition.dy, 100, 100),
          Rect.fromLTWH(0, 0, overlay!.paintBounds.size.width,
              overlay.paintBounds.size.height)),
      items: [
        // bokmark the news
        PopupMenuItem(
          value: FluxNewsState.contextMenueBookmarkString,
          child: news.starred
              ? Row(children: [
                  const Icon(
                    Icons.star_outline,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 5),
                    child: Text(AppLocalizations.of(context)!.deleteBookmark),
                  )
                ])
              : Row(children: [
                  const Icon(
                    Icons.star,
                  ),
                  Padding(
                      padding: const EdgeInsets.only(left: 5),
                      child: Text(AppLocalizations.of(context)!.addBookmark)),
                ]),
        ),
        // mark the news as unread or read
        PopupMenuItem(
          value: news.status == FluxNewsState.readNewsStatus
              ? FluxNewsState.unreadNewsStatus
              : FluxNewsState.readNewsStatus,
          child: Row(children: [
            Icon(
              news.status == FluxNewsState.readNewsStatus
                  ? Icons.fiber_new
                  : Icons.remove_red_eye_outlined,
            ),
            Padding(
                padding: const EdgeInsets.only(left: 5),
                child: news.status == FluxNewsState.readNewsStatus
                    ? Text(AppLocalizations.of(context)!.markAsUnread)
                    : Text(AppLocalizations.of(context)!.markAsRead)),
          ]),
        ),
      ]);
  switch (result) {
    case FluxNewsState.contextMenueBookmarkString:
      // switch between bookmarked or not bookmarked depending on the prevoius status
      if (news.starred) {
        news.starred = false;
      } else {
        news.starred = true;
      }

      // toggle the news as bookmarked or not bookmarked at the miniflux server
      await toggleBookmark(http.Client(), appState, news)
          .onError((error, stackTrace) {
        if (Platform.isAndroid || Platform.isIOS) {
          FlutterLogs.logThis(
              tag: FluxNewsState.logTag,
              subTag: 'toggleBookmark',
              logMessage: 'Caught an error in toggleBookmark function!',
              errorMessage: error.toString(),
              level: LogLevel.ERROR);
        }
        if (appState.errorString !=
            AppLocalizations.of(context)!.communicateionMinifluxError) {
          appState.errorString =
              AppLocalizations.of(context)!.communicateionMinifluxError;
          appState.newError = true;
          appState.refreshView();
        }
      });

      // update the bookmarked status in the database
      try {
        updateNewsStarredStatusInDB(news.newsID, news.starred, appState);
        if (context.mounted) {
          updateStarredCounter(appState, context);
        }
      } catch (e) {
        if (Platform.isAndroid || Platform.isIOS) {
          FlutterLogs.logThis(
              tag: FluxNewsState.logTag,
              subTag: 'updateNewsStarredStatusInDB',
              logMessage:
                  'Caught an error in updateNewsStarredStatusInDB function!',
              errorMessage: e.toString(),
              level: LogLevel.ERROR);
        }
        if (context.mounted) {
          if (appState.errorString !=
              AppLocalizations.of(context)!.databaseError) {
            appState.errorString = AppLocalizations.of(context)!.databaseError;
            appState.newError = true;
            appState.refreshView();
          }
        }
      }

      // if we are in the bookmarked categorie, reload the list of bookmarked news
      // after the prevoius change, because there happened changes to this list.
      if (context.mounted) {
        if (appState.appBarText == AppLocalizations.of(context)!.bookmarked) {
          appState.feedIDs = [-1];
          appState.newsList =
              queryNewsFromDB(appState, appState.feedIDs).whenComplete(() {
            waitUntilNewsListBuild(appState).whenComplete(
              () {
                appState.itemScrollController.jumpTo(index: 0);
              },
            );
          });
          appState.refreshView();
        } else {
          if (searchView) {
            // update the news list of the main view
            appState.newsList = queryNewsFromDB(appState, appState.feedIDs)
                .onError((error, stackTrace) {
              if (Platform.isAndroid || Platform.isIOS) {
                FlutterLogs.logThis(
                    tag: FluxNewsState.logTag,
                    subTag: 'queryNewsFromDB',
                    logMessage: 'Caught an error in queryNewsFromDB function!',
                    errorMessage: error.toString(),
                    level: LogLevel.ERROR);
              }
              appState.errorString =
                  AppLocalizations.of(context)!.databaseError;
              return [];
            });
          }
          appState.refreshView();
        }
      }

      break;
    case FluxNewsState.unreadNewsStatus:
      // mark a news as unread, update the news unread status in database
      try {
        updateNewsStatusInDB(
            news.newsID, FluxNewsState.unreadNewsStatus, appState);
      } catch (e) {
        if (Platform.isAndroid || Platform.isIOS) {
          FlutterLogs.logThis(
              tag: FluxNewsState.logTag,
              subTag: 'updateNewsStatusInDB',
              logMessage: 'Caught an error in updateNewsStatusInDB function!',
              errorMessage: e.toString(),
              level: LogLevel.ERROR);
        }
        if (context.mounted) {
          if (appState.errorString !=
              AppLocalizations.of(context)!.databaseError) {
            appState.errorString = AppLocalizations.of(context)!.databaseError;
            appState.newError = true;
            appState.refreshView();
          }
        }
      }
      // set the new unread status to the news object and toggle the recalculation
      // of the news counter
      news.status = FluxNewsState.unreadNewsStatus;
      if (searchView) {
        // update the news status at the miniflux server
        try {
          toggleOneNewsAsRead(http.Client(), appState, news);
        } catch (e) {
          if (Platform.isAndroid || Platform.isIOS) {
            FlutterLogs.logThis(
                tag: FluxNewsState.logTag,
                subTag: 'toggleOneNewsAsRead',
                logMessage: 'Caught an error in toggleOneNewsAsRead function!',
                errorMessage: e.toString(),
                level: LogLevel.ERROR);
          }
        }
        // update the news list of the main view
        appState.newsList = queryNewsFromDB(appState, appState.feedIDs)
            .onError((error, stackTrace) {
          if (Platform.isAndroid || Platform.isIOS) {
            FlutterLogs.logThis(
                tag: FluxNewsState.logTag,
                subTag: 'queryNewsFromDB',
                logMessage: 'Caught an error in queryNewsFromDB function!',
                errorMessage: error.toString(),
                level: LogLevel.ERROR);
          }
          appState.errorString = AppLocalizations.of(context)!.databaseError;
          return [];
        });
      } else {
        appCounterState.listUpdated = true;
        appCounterState.refreshView();
        appState.refreshView();
      }

      break;
    case FluxNewsState.readNewsStatus:
      // mark a news as read, update the news read status in database
      try {
        updateNewsStatusInDB(
            news.newsID, FluxNewsState.readNewsStatus, appState);
      } catch (e) {
        if (Platform.isAndroid || Platform.isIOS) {
          FlutterLogs.logThis(
              tag: FluxNewsState.logTag,
              subTag: 'updateNewsStatusInDB',
              logMessage: 'Caught an error in updateNewsStatusInDB function!',
              errorMessage: e.toString(),
              level: LogLevel.ERROR);
        }
        if (context.mounted) {
          if (appState.errorString !=
              AppLocalizations.of(context)!.databaseError) {
            appState.errorString = AppLocalizations.of(context)!.databaseError;
            appState.newError = true;
            appState.refreshView();
          }
        }
      }
      // set the new read status to the news object and toggle the recalculation
      // of the news counter
      news.status = FluxNewsState.readNewsStatus;

      if (searchView) {
        // update the news status at the miniflux server
        try {
          toggleOneNewsAsRead(http.Client(), appState, news);
        } catch (e) {
          if (Platform.isAndroid || Platform.isIOS) {
            FlutterLogs.logThis(
                tag: FluxNewsState.logTag,
                subTag: 'toggleOneNewsAsRead',
                logMessage: 'Caught an error in toggleOneNewsAsRead function!',
                errorMessage: e.toString(),
                level: LogLevel.ERROR);
          }
        }
        // update the news list of the main view
        appState.newsList = queryNewsFromDB(appState, appState.feedIDs)
            .onError((error, stackTrace) {
          if (Platform.isAndroid || Platform.isIOS) {
            FlutterLogs.logThis(
                tag: FluxNewsState.logTag,
                subTag: 'queryNewsFromDB',
                logMessage: 'Caught an error in queryNewsFromDB function!',
                errorMessage: error.toString(),
                level: LogLevel.ERROR);
          }
          appState.errorString = AppLocalizations.of(context)!.databaseError;
          return [];
        });
      } else {
        appCounterState.listUpdated = true;
        appCounterState.refreshView();
        appState.refreshView();
      }

      break;
  }
}

// this function is needed because after the news are fetched from the database,
// the list of news need some time to be generated.
// only after the list is generated, we can set the scroll position of the list
// we can check that the list is generated if the scroll controller is attached to the list.
// so the function checks the scroll controller and if it's not attached it waits 1 millisecond
// and check then again if the scrol controller is attached.
// With callaing this function as await, we can wait with the further processing
// on finishing with the list build.
Future<void> waitUntilNewsListBuild(FluxNewsState appState) async {
  final completer = Completer();
  if (appState.itemScrollController.isAttached) {
    await Future.delayed(const Duration(milliseconds: 1));
    return waitUntilNewsListBuild(appState);
  } else {
    completer.complete();
  }
  return completer.future;
}
