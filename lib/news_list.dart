import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flux_news/database_backend.dart';
import 'package:flux_news/flux_news_counter_state.dart';
import 'package:flux_news/flux_news_state.dart';
import 'package:flux_news/news_card.dart';
import 'package:flux_news/news_model.dart';
import 'package:flux_news/news_row.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter_gen/gen_l10n/flux_news_localizations.dart';

// the list view widget with news (main view)
class LandscapeNewsList extends StatelessWidget {
  const LandscapeNewsList({
    super.key,
    required this.context,
    required this.appState,
  });
  final BuildContext context;
  final FluxNewsState appState;

  @override
  Widget build(BuildContext context) {
    FluxNewsCounterState appCounterState = context.read<FluxNewsCounterState>();

    var getData = FutureBuilder<List<News>>(
      future: appState.newsList,
      builder: (context, snapshot) {
        switch (snapshot.connectionState) {
          case ConnectionState.none:
          case ConnectionState.waiting:
          default:
            if (snapshot.hasError) {
              return const SizedBox.shrink();
            } else {
              return snapshot.data == null
                  // show empty dialog if list is null
                  ? Center(
                      child: Text(
                      AppLocalizations.of(context)!.noNewEntries,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ))
                  // show empty dialog if list is empty
                  : snapshot.data!.isEmpty
                      ? Center(
                          child: Text(
                          AppLocalizations.of(context)!.noNewEntries,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ))
                      // otherwise create list view with ScrollablePositionedList
                      // to save scroll position persistant
                      : Stack(children: [
                          NotificationListener<ScrollEndNotification>(
                            child: ScrollablePositionedList.builder(
                                key: const PageStorageKey<String>('NewsList'),
                                itemCount: snapshot.data!.length,
                                itemScrollController:
                                    appState.itemScrollController,
                                itemPositionsListener:
                                    appState.itemPositionsListener,
                                initialScrollIndex: appState.scrollPosition,
                                itemBuilder: (context, i) {
                                  return NewsRow(
                                      news: snapshot.data![i],
                                      appState: appState,
                                      context: context,
                                      searchView: false);
                                }),
                            // on ScrollNotification set news as read on scrollover if activated
                            onNotification: (ScrollNotification scrollInfo) {
                              final metrics = scrollInfo.metrics;
                              // check if set read on scrollover is activated in settings
                              if (appState.markAsReadOnScrollOver) {
                                // if the sync is in progress, no news should marked as read
                                if (appState.syncProcess == false) {
                                  // set all news as read if the list reached the bottom (the edge)
                                  if (metrics.atEdge) {
                                    // to ensure that the list is at the bottom edge and not at the top edge
                                    // the amount of scrolled pixels must be greater 0
                                    if (metrics.pixels > 0) {
                                      // iterade through the whole news list and mark news as read
                                      for (int i = 0;
                                          i < snapshot.data!.length;
                                          i++) {
                                        try {
                                          updateNewsStatusInDB(
                                              snapshot.data![i].newsID,
                                              FluxNewsState.readNewsStatus,
                                              appState);
                                        } catch (e) {
                                          if (Platform.isAndroid ||
                                              Platform.isIOS) {
                                            FlutterLogs.logThis(
                                                tag: FluxNewsState.logTag,
                                                subTag: 'updateNewsStatusInDB',
                                                logMessage:
                                                    'Caught an error in updateNewsStatusInDB function!',
                                                errorMessage: e.toString(),
                                                level: LogLevel.ERROR);
                                          }
                                          if (appState.errorString !=
                                              AppLocalizations.of(context)!
                                                  .databaseError) {
                                            appState.errorString =
                                                AppLocalizations.of(context)!
                                                    .databaseError;
                                            appState.newError = true;
                                            appState.refreshView();
                                          }
                                        }
                                        snapshot.data![i].status =
                                            FluxNewsState.readNewsStatus;
                                      }
                                      // set the scroll position back to the top of the list
                                      appState.scrollPosition = 0;
                                    }
                                  } else {
                                    // if the list doesn't reached the bottom,
                                    // mark the news which got scrolled over as read.
                                    // Iterate through the news list from start
                                    // to the actual position and mark them as read
                                    for (int i = 0;
                                        i < appState.scrollPosition;
                                        i++) {
                                      try {
                                        updateNewsStatusInDB(
                                            snapshot.data![i].newsID,
                                            FluxNewsState.readNewsStatus,
                                            appState);
                                      } catch (e) {
                                        if (Platform.isAndroid ||
                                            Platform.isIOS) {
                                          FlutterLogs.logThis(
                                              tag: FluxNewsState.logTag,
                                              subTag: 'updateNewsStatusInDB',
                                              logMessage:
                                                  'Caught an error in updateNewsStatusInDB function!',
                                              errorMessage: e.toString(),
                                              level: LogLevel.ERROR);
                                        }
                                        if (appState.errorString !=
                                            AppLocalizations.of(context)!
                                                .databaseError) {
                                          appState.errorString =
                                              AppLocalizations.of(context)!
                                                  .databaseError;
                                          appState.newError = true;
                                          appState.refreshView();
                                        }
                                      }
                                      snapshot.data![i].status =
                                          FluxNewsState.readNewsStatus;
                                    }
                                  }
                                }
                                // mark the list as updated to recalculate the news count
                                appCounterState.listUpdated = true;
                                appState.refreshView();
                                appCounterState.refreshView();
                              }
                              // return always false to ensure the processing of the notification
                              return false;
                            },
                          ),
                          // get the actual scroll position on stop scrolling
                          positionsView(appState),
                        ]);
            }
        }
      },
    );
    return getData;
  }
}

class PortraitNewsList extends StatelessWidget {
  const PortraitNewsList({
    super.key,
    required this.context,
    required this.appState,
  });
  final BuildContext context;
  final FluxNewsState appState;

  @override
  Widget build(BuildContext context) {
    FluxNewsCounterState appCounterState = context.read<FluxNewsCounterState>();

    var getData = FutureBuilder<List<News>>(
      future: appState.newsList,
      builder: (context, snapshot) {
        switch (snapshot.connectionState) {
          case ConnectionState.none:
          case ConnectionState.waiting:
          default:
            if (snapshot.hasError) {
              return const SizedBox.shrink();
            } else {
              return snapshot.data == null
                  // show empty dialog if list is null
                  ? Center(
                      child: Text(
                      AppLocalizations.of(context)!.noNewEntries,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ))
                  // show empty dialog if list is empty
                  : snapshot.data!.isEmpty
                      ? Center(
                          child: Text(
                          AppLocalizations.of(context)!.noNewEntries,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ))
                      // otherwise create list view with ScrollablePositionedList
                      // to save scroll position persistant
                      : Stack(children: [
                          NotificationListener<ScrollEndNotification>(
                            child: ScrollablePositionedList.builder(
                                key: const PageStorageKey<String>('NewsList'),
                                itemCount: snapshot.data!.length,
                                itemScrollController:
                                    appState.itemScrollController,
                                itemPositionsListener:
                                    appState.itemPositionsListener,
                                initialScrollIndex: appState.scrollPosition,
                                itemBuilder: (context, i) {
                                  return NewsCard(
                                      news: snapshot.data![i],
                                      appState: appState,
                                      context: context,
                                      searchView: false);
                                }),
                            // on ScrollNotification set news as read on scrollover if activated
                            onNotification: (ScrollNotification scrollInfo) {
                              final metrics = scrollInfo.metrics;
                              // check if set read on scrollover is activated in settings
                              if (appState.markAsReadOnScrollOver) {
                                // if the sync is in progress, no news should marked as read
                                if (appState.syncProcess == false) {
                                  // set all news as read if the list reached the bottom (the edge)
                                  if (metrics.atEdge) {
                                    // to ensure that the list is at the bottom edge and not at the top edge
                                    // the amount of scrolled pixels must be greater 0
                                    if (metrics.pixels > 0) {
                                      // iterade through the whole news list and mark news as read
                                      for (int i = 0;
                                          i < snapshot.data!.length;
                                          i++) {
                                        try {
                                          updateNewsStatusInDB(
                                              snapshot.data![i].newsID,
                                              FluxNewsState.readNewsStatus,
                                              appState);
                                        } catch (e) {
                                          if (Platform.isAndroid ||
                                              Platform.isIOS) {
                                            FlutterLogs.logThis(
                                                tag: FluxNewsState.logTag,
                                                subTag: 'updateNewsStatusInDB',
                                                logMessage:
                                                    'Caught an error in updateNewsStatusInDB function!',
                                                errorMessage: e.toString(),
                                                level: LogLevel.ERROR);
                                          }
                                          if (appState.errorString !=
                                              AppLocalizations.of(context)!
                                                  .databaseError) {
                                            appState.errorString =
                                                AppLocalizations.of(context)!
                                                    .databaseError;
                                            appState.newError = true;
                                            appState.refreshView();
                                          }
                                        }
                                        snapshot.data![i].status =
                                            FluxNewsState.readNewsStatus;
                                      }
                                      // set the scroll position back to the top of the list
                                      appState.scrollPosition = 0;
                                    }
                                  } else {
                                    // if the list doesn't reached the bottom,
                                    // mark the news which got scrolled over as read.
                                    // Iterate through the news list from start
                                    // to the actual position and mark them as read
                                    for (int i = 0;
                                        i < appState.scrollPosition;
                                        i++) {
                                      try {
                                        updateNewsStatusInDB(
                                            snapshot.data![i].newsID,
                                            FluxNewsState.readNewsStatus,
                                            appState);
                                      } catch (e) {
                                        if (Platform.isAndroid ||
                                            Platform.isIOS) {
                                          FlutterLogs.logThis(
                                              tag: FluxNewsState.logTag,
                                              subTag: 'updateNewsStatusInDB',
                                              logMessage:
                                                  'Caught an error in updateNewsStatusInDB function!',
                                              errorMessage: e.toString(),
                                              level: LogLevel.ERROR);
                                        }
                                        if (appState.errorString !=
                                            AppLocalizations.of(context)!
                                                .databaseError) {
                                          appState.errorString =
                                              AppLocalizations.of(context)!
                                                  .databaseError;
                                          appState.newError = true;
                                          appState.refreshView();
                                        }
                                      }
                                      snapshot.data![i].status =
                                          FluxNewsState.readNewsStatus;
                                    }
                                  }
                                }
                                // mark the list as updated to recalculate the news count
                                appCounterState.listUpdated = true;
                                appState.refreshView();
                                appCounterState.refreshView();
                              }
                              // return always false to ensure the processing of the notification
                              return false;
                            },
                          ),
                          // get the actual scroll position on stop scrolling
                          positionsView(appState),
                        ]);
            }
        }
      },
    );
    return getData;
  }
}

// here is a helper function to get the first visible widget in the list view
// this widget is used as the limit on marking prevoius news as read.
// so every item of the list, which is prevoius to the first visible
// will be marked as read.
Widget positionsView(FluxNewsState appState) =>
    ValueListenableBuilder<Iterable<ItemPosition>>(
      valueListenable: appState.itemPositionsListener.itemPositions,
      builder: (context, positions, child) {
        FluxNewsState appState = context.watch<FluxNewsState>();
        int? firstItem;
        if (positions.isNotEmpty) {
          firstItem = positions
              .where((ItemPosition position) => position.itemTrailingEdge > 0)
              .reduce((ItemPosition first, ItemPosition position) =>
                  position.itemTrailingEdge < first.itemTrailingEdge
                      ? position
                      : first)
              .index;
        }
        if (firstItem == null) {
          appState.scrollPosition = 0;
          appState.storage.write(
              key: FluxNewsState.secureStorageSavedScrollPositionKey,
              value: '0');
        } else {
          appState.scrollPosition = firstItem;
          appState.storage.write(
              key: FluxNewsState.secureStorageSavedScrollPositionKey,
              value: firstItem.toString());
        }
        /*
          if (appState.debugMode) {
            if (Platform.isAndroid || Platform.isIOS) {
              FlutterLogs.logThis(
                  tag: FluxNewsState.logTag,
                  subTag: 'positionsView',
                  logMessage: 'Actual Position is: $scrollPosition',
                  level: LogLevel.INFO);
            }
          }
          */
        return const SizedBox.shrink();
      },
    );
