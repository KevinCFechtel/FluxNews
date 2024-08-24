import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/flux_news_localizations.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/state_management/flux_news_counter_state.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:flux_news/functions/logging.dart';
import 'package:flux_news/miniflux/miniflux_backend.dart';
import 'package:flux_news/models/news_model.dart';

// this is a helper function to get the actual tab position
// this position is used to open the context menu of the news card here
void getTapPosition(TapDownDetails details, BuildContext context, FluxNewsState appState) {
  appState.tapPosition = details.globalPosition;
}

// here is the function to show the context menu
// this menu give the option to mark a news as read or unread and to bookmark a news
void showContextMenu(News news, BuildContext context, bool searchView, FluxNewsState appState,
    FluxNewsCounterState appCounterState) async {
  //Offset offset = details.globalPosition;
  final RenderObject overlay = Overlay.of(context).context.findRenderObject()!;

  final result = await showMenu(
      context: context,
      // open the menu on the previous recognized position
      position: RelativeRect.fromRect(Rect.fromLTWH(appState.tapPosition.dx, appState.tapPosition.dy, 100, 100),
          Rect.fromLTWH(0, 0, overlay.paintBounds.size.width, overlay.paintBounds.size.height)),
      items: [
        // bookmark the news
        PopupMenuItem(
          value: FluxNewsState.contextMenuBookmarkString,
          child: Row(children: [
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Icon(
                news.starred ? Icons.star_outline : Icons.star,
              ),
            ),
            Expanded(
              child: news.starred
                  ? Text(
                      AppLocalizations.of(context)!.deleteBookmark,
                      overflow: TextOverflow.visible,
                    )
                  : Text(
                      AppLocalizations.of(context)!.addBookmark,
                      overflow: TextOverflow.visible,
                    ),
            )
          ]),
        ),
        // mark the news as unread or read
        PopupMenuItem(
          value: news.status == FluxNewsState.readNewsStatus
              ? FluxNewsState.unreadNewsStatus
              : FluxNewsState.readNewsStatus,
          child: Row(children: [
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Icon(
                news.status == FluxNewsState.readNewsStatus ? Icons.fiber_new : Icons.remove_red_eye_outlined,
              ),
            ),
            Expanded(
                child: news.status == FluxNewsState.readNewsStatus
                    ? Text(
                        AppLocalizations.of(context)!.markAsUnread,
                        overflow: TextOverflow.visible,
                      )
                    : Text(
                        AppLocalizations.of(context)!.markAsRead,
                        overflow: TextOverflow.visible,
                      )),
          ]),
        ),
        // save the news to third party service
        PopupMenuItem(
            enabled: appState.minifluxVersionString!.startsWith(RegExp(r'[01]|2\.0'))
                ? appState.minifluxVersionInt >= FluxNewsState.minifluxSaveMinVersion
                : true,
            value: FluxNewsState.contextMenuSaveString,
            child: Row(children: [
              const Padding(
                padding: EdgeInsets.only(right: 5),
                child: Icon(
                  Icons.save,
                ),
              ),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.contextSaveButton,
                  overflow: TextOverflow.visible,
                ),
              )
            ])),
      ]);
  switch (result) {
    case FluxNewsState.contextMenuBookmarkString:
      bookmarkAction(news, appState, context, searchView);
      break;
    case FluxNewsState.unreadNewsStatus:
      markNewsAsReadAction(news, appState, context, searchView, appCounterState);
      break;
    case FluxNewsState.readNewsStatus:
      markNewsAsUnreadAction(news, appState, context, searchView, appCounterState);
      break;
    case FluxNewsState.contextMenuSaveString:
      saveToThirdPartyAction(news, appState, context);
      break;
  }
}

Future<void> bookmarkAction(News news, FluxNewsState appState, BuildContext context, bool searchView) async {
// switch between bookmarked or not bookmarked depending on the previous status
  if (news.starred) {
    news.starred = false;
  } else {
    news.starred = true;
  }

  // toggle the news as bookmarked or not bookmarked at the miniflux server
  await toggleBookmark(appState, news).onError((error, stackTrace) {
    logThis('toggleBookmark', 'Caught an error in toggleBookmark function! : ${error.toString()}', LogLevel.ERROR);
    if (context.mounted) {
      if (appState.errorString != AppLocalizations.of(context)!.communicateionMinifluxError) {
        appState.errorString = AppLocalizations.of(context)!.communicateionMinifluxError;
        appState.newError = true;
        appState.refreshView();
      }
    }
  });

  // update the bookmarked status in the database
  try {
    updateNewsStarredStatusInDB(news.newsID, news.starred, appState);
    if (context.mounted) {
      updateStarredCounter(appState, context);
    }
  } catch (e) {
    logThis('updateNewsStarredStatusInDB', 'Caught an error in updateNewsStarredStatusInDB function! : ${e.toString()}',
        LogLevel.ERROR);

    if (context.mounted) {
      if (appState.errorString != AppLocalizations.of(context)!.databaseError) {
        appState.errorString = AppLocalizations.of(context)!.databaseError;
        appState.newError = true;
        appState.refreshView();
      }
    }
  }

  // if we are in the bookmarked category, reload the list of bookmarked news
  // after the previous change, because there happened changes to this list.
  if (context.mounted) {
    if (appState.appBarText == AppLocalizations.of(context)!.bookmarked) {
      appState.feedIDs = [-1];
      appState.newsList = queryNewsFromDB(appState, appState.feedIDs).whenComplete(() {
        appState.jumpToItem(0);
      });
      appState.refreshView();
    } else {
      if (searchView) {
        // update the news list of the main view
        appState.newsList = queryNewsFromDB(appState, appState.feedIDs).onError((error, stackTrace) {
          logThis(
              'queryNewsFromDB', 'Caught an error in queryNewsFromDB function! : ${error.toString()}', LogLevel.ERROR);
          if (context.mounted) {
            appState.errorString = AppLocalizations.of(context)!.databaseError;
          }
          return [];
        });
      }
      appState.refreshView();
    }
  }
}

Future<void> saveToThirdPartyAction(News news, FluxNewsState appState, BuildContext context) async {
  await saveNewsToThirdPartyService(appState, news).onError((error, stackTrace) {
    logThis('saveNewsToThirdPartyService',
        'Caught an error in saveNewsToThirdPartyService function! : ${error.toString()}', LogLevel.ERROR);

    if (!appState.newError) {
      if (context.mounted) {
        appState.errorString = AppLocalizations.of(context)!.communicateionMinifluxError;
      }
      appState.newError = true;
      appState.refreshView();
    }
  });

  if (context.mounted) {
    if (!appState.newError) {
      var successflulSaveSnackBar = SnackBar(
        content: Text(AppLocalizations.of(context)!.successfullSaveToThirdParty),
      );
      ScaffoldMessenger.of(context).showSnackBar(successflulSaveSnackBar);
    }
  }
}

void markNewsAsReadAction(
    News news, FluxNewsState appState, BuildContext context, bool searchView, FluxNewsCounterState appCounterState) {
  // mark a news as read, update the news read status in database
  try {
    updateNewsStatusInDB(news.newsID, FluxNewsState.readNewsStatus, appState);
  } catch (e) {
    logThis(
        'updateNewsStatusInDB', 'Caught an error in updateNewsStatusInDB function! : ${e.toString()}', LogLevel.ERROR);

    if (context.mounted) {
      if (appState.errorString != AppLocalizations.of(context)!.databaseError) {
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
      toggleOneNewsAsRead(appState, news);
    } catch (e) {
      logThis(
          'toggleOneNewsAsRead', 'Caught an error in toggleOneNewsAsRead function! : ${e.toString()}', LogLevel.ERROR);
    }
    // update the news list of the main view
    appState.newsList = queryNewsFromDB(appState, appState.feedIDs).onError((error, stackTrace) {
      logThis('queryNewsFromDB', 'Caught an error in queryNewsFromDB function! : ${error.toString()}', LogLevel.ERROR);
      if (context.mounted) {
        appState.errorString = AppLocalizations.of(context)!.databaseError;
      }
      return [];
    });
    appState.refreshView();
    appCounterState.listUpdated = true;
    appCounterState.refreshView();
  } else {
    appCounterState.listUpdated = true;
    appCounterState.refreshView();
    appState.refreshView();
  }
}

void markNewsAsUnreadAction(
    News news, FluxNewsState appState, BuildContext context, bool searchView, FluxNewsCounterState appCounterState) {
  // mark a news as unread, update the news unread status in database
  try {
    updateNewsStatusInDB(news.newsID, FluxNewsState.unreadNewsStatus, appState);
  } catch (e) {
    logThis(
        'updateNewsStatusInDB', 'Caught an error in updateNewsStatusInDB function! : ${e.toString()}', LogLevel.ERROR);

    if (context.mounted) {
      if (appState.errorString != AppLocalizations.of(context)!.databaseError) {
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
      toggleOneNewsAsRead(appState, news);
    } catch (e) {
      logThis(
          'toggleOneNewsAsRead', 'Caught an error in toggleOneNewsAsRead function! : ${e.toString()}', LogLevel.ERROR);
    }
    // update the news list of the main view
    appState.newsList = queryNewsFromDB(appState, appState.feedIDs).onError((error, stackTrace) {
      logThis('queryNewsFromDB', 'Caught an error in queryNewsFromDB function! : ${error.toString()}', LogLevel.ERROR);
      if (context.mounted) {
        appState.errorString = AppLocalizations.of(context)!.databaseError;
      }
      return [];
    });
    appState.refreshView();
    appCounterState.listUpdated = true;
    appCounterState.refreshView();
  } else {
    appCounterState.listUpdated = true;
    appCounterState.refreshView();
    appState.refreshView();
  }
}
