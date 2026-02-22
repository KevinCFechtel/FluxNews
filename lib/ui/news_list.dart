import 'package:flutter/material.dart';
import 'package:flux_news/functions/news_widget_functions.dart';
import 'package:flux_news/functions/sync_news.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/state_management/flux_news_counter_state.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:flux_news/functions/logging.dart';
import 'package:flux_news/state_management/flux_news_theme_state.dart';
import 'package:flux_news/ui/flux_news_body.dart';
import 'package:flux_news/ui/news_card.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/ui/news_row.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:scrollview_observer/scrollview_observer.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

// the list view widget with news (main view)
class BodyNewsList extends StatelessWidget {
  const BodyNewsList({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    bool searchView = false;
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
              FluxNewsThemeState themeState = context.read<FluxNewsThemeState>();
              return snapshot.data == null
                  // show empty dialog if list is null
                  ? Center(
                      child: Text(
                      appState.syncProcess
                          ? AppLocalizations.of(context)!.syncInProgress
                          : AppLocalizations.of(context)!.noNewEntries,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ))
                  // show empty dialog if list is empty
                  : snapshot.data!.isEmpty
                      ? Center(
                          child: Text(
                          appState.syncProcess
                              ? AppLocalizations.of(context)!.syncInProgress
                              : AppLocalizations.of(context)!.noNewEntries,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ))
                      // otherwise create list view with ScrollablePositionedList
                      // to save scroll position persistent
                      : ListViewObserver(
                          autoTriggerObserveTypes: const [ObserverAutoTriggerObserveType.scrollEnd],
                          triggerOnObserveType: ObserverTriggerOnObserveType.directly,
                          customTargetRenderSliverType: (renderObj) {
                            return renderObj.runtimeType.toString() == 'RenderSuperSliverList';
                          },
                          child: !appState.isTablet
                              ? appState.scrolloverAppBar
                                  ? CustomScrollView(slivers: <Widget>[
                                      SliverAppBar(
                                        backgroundColor: themeState.useBlackMode ? Colors.black : null,
                                        floating: true,
                                        leading: Builder(
                                          builder: (BuildContext context) {
                                            return IconButton(
                                              icon: const Icon(
                                                FontAwesomeIcons.bookOpen,
                                              ),
                                              onPressed: () {
                                                Scaffold.of(context).openDrawer();
                                              },
                                              tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
                                            );
                                          },
                                        ),
                                        title: const AppBarTitle(),
                                        actions: appBarButtons(context),
                                      ),
                                      SuperSliverList.builder(
                                          key: const PageStorageKey<String>('NewsList'),
                                          itemCount: snapshot.data!.length,
                                          listController: appState.listController,
                                          itemBuilder: (context, i) {
                                            return appState.orientation == Orientation.landscape
                                                ? NewsRow(
                                                    news: snapshot.data![i],
                                                    context: context,
                                                    searchView: searchView,
                                                    itemIndex: i,
                                                    newsList: snapshot.data,
                                                  )
                                                : NewsCard(
                                                    news: snapshot.data![i],
                                                    context: context,
                                                    searchView: searchView,
                                                    itemIndex: i,
                                                    newsList: snapshot.data,
                                                  );
                                          }),
                                    ])
                                  : SuperListView.builder(
                                      key: const PageStorageKey<String>('NewsList'),
                                      itemCount: snapshot.data!.length,
                                      controller: appState.scrollController,
                                      listController: appState.listController,
                                      itemBuilder: (context, i) {
                                        return appState.orientation == Orientation.landscape
                                            ? NewsRow(
                                                news: snapshot.data![i],
                                                context: context,
                                                searchView: searchView,
                                                itemIndex: i,
                                                newsList: snapshot.data,
                                              )
                                            : NewsCard(
                                                news: snapshot.data![i],
                                                context: context,
                                                searchView: searchView,
                                                itemIndex: i,
                                                newsList: snapshot.data,
                                              );
                                      })
                              : SuperListView.builder(
                                  key: const PageStorageKey<String>('NewsList'),
                                  itemCount: snapshot.data!.length,
                                  controller: appState.scrollController,
                                  listController: appState.listController,
                                  itemBuilder: (context, i) {
                                    return appState.orientation == Orientation.landscape
                                        ? NewsRow(
                                            news: snapshot.data![i],
                                            context: context,
                                            searchView: searchView,
                                            itemIndex: i,
                                            newsList: snapshot.data,
                                          )
                                        : NewsCard(
                                            news: snapshot.data![i],
                                            context: context,
                                            searchView: searchView,
                                            itemIndex: i,
                                            newsList: snapshot.data,
                                          );
                                  }),
                          onObserve: (resultModel) {
                            int lastItem = 0;
                            double lastItemTrailingMarginToViewport = -1.0;
                            int firstItem = 0;
                            if (resultModel.displayingChildIndexList.isNotEmpty) {
                              firstItem = resultModel.displayingChildIndexList.first;
                              lastItem = resultModel.displayingChildIndexList.last;
                              lastItemTrailingMarginToViewport =
                                  resultModel.displayingChildModelList.last.trailingMarginToViewport;
                            }
                            appState.scrollPosition = firstItem;

                            appState.storage.write(
                                key: FluxNewsState.secureStorageSavedScrollPositionKey, value: firstItem.toString());

                            if (appState.markAsReadOnScrollOver) {
                              // if the sync is in progress, no news should marked as read
                              if (appState.syncProcess == false) {
                                // set all news as read if the list reached the bottom (the last item is more then 95% visible)
                                if (lastItem == snapshot.data!.length - 1 && lastItemTrailingMarginToViewport >= 0) {
                                  // to ensure that the list is at the bottom edge and not at the top edge
                                  // the amount of scrolled pixels must be greater 0
                                  // iterate through the whole news list and mark news as read
                                  for (int i = 0; i < snapshot.data!.length; i++) {
                                    try {
                                      updateNewsStatusInDB(
                                          snapshot.data![i].newsID, FluxNewsState.readNewsStatus, appState);
                                    } catch (e) {
                                      logThis(
                                          'updateNewsStatusInDB',
                                          'Caught an error in updateNewsStatusInDB function! : ${e.toString()}',
                                          LogLevel.ERROR);

                                      if (context.read<FluxNewsState>().errorString !=
                                          AppLocalizations.of(context)!.databaseError) {
                                        context.read<FluxNewsState>().errorString =
                                            AppLocalizations.of(context)!.databaseError;
                                        context.read<FluxNewsState>().newError = true;
                                        context.read<FluxNewsState>().refreshView();
                                      }
                                    }
                                    snapshot.data![i].status = FluxNewsState.readNewsStatus;
                                    // set the scroll position back to the top of the list
                                    appState.scrollPosition = 0;
                                  }
                                } else {
                                  // if the list doesn't reached the bottom,
                                  // mark the news which got scrolled over as read.
                                  // Iterate through the news list from start
                                  // to the actual position and mark them as read
                                  for (int i = 0; i < appState.scrollPosition; i++) {
                                    if (snapshot.data![i].status != FluxNewsState.readNewsStatus) {
                                      try {
                                        updateNewsStatusInDB(
                                            snapshot.data![i].newsID, FluxNewsState.readNewsStatus, appState);
                                      } catch (e) {
                                        logThis(
                                            'updateNewsStatusInDB',
                                            'Caught an error in updateNewsStatusInDB function! : ${e.toString()}',
                                            LogLevel.ERROR);

                                        if (appState.errorString != AppLocalizations.of(context)!.databaseError) {
                                          appState.errorString = AppLocalizations.of(context)!.databaseError;
                                          appState.newError = true;
                                          appState.refreshView();
                                        }
                                      }
                                      snapshot.data![i].status = FluxNewsState.readNewsStatus;
                                    }
                                  }
                                }
                              }
                              // mark the list as updated to recalculate the news count
                              context.read<FluxNewsCounterState>().listUpdated = true;
                              appState.refreshView();
                              context.read<FluxNewsCounterState>().refreshView();
                            }
                          },
                        );
            }
        }
      },
    );
    return getData;
  }

  List<Widget> appBarButtons(BuildContext context) {
    FluxNewsCounterState appCounterState = context.read<FluxNewsCounterState>();
    FluxNewsState appState = context.read<FluxNewsState>();
    // define the app bar buttons to sync with miniflux,
    // search for news and switch between all and only unread news view
    // and the navigation to the settings
    return <Widget>[
      // here is the sync part
      IconButton(
        onPressed: () async {
          if (appState.syncProcess) {
            appState.longSyncAborted = true;
            appState.refreshView();
          } else {
            await syncNews(appState, context);
          }
        },
        icon: appState.syncProcess
            ? const SizedBox(
                height: 15.0,
                width: 15.0,
                child: CircularProgressIndicator.adaptive(),
              )
            : const Icon(
                Icons.refresh,
              ),
      ),
      // here is the popup menu where the user can search,
      // choose between all and only unread news view
      // and navigate to the settings
      PopupMenuButton(
          icon: const Icon(Icons.more_vert),
          itemBuilder: (context) {
            return [
              // the search button
              PopupMenuItem<int>(
                value: 0,
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(right: 5),
                      child: Icon(
                        Icons.search,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)!.search,
                        overflow: TextOverflow.visible,
                      ),
                    )
                  ],
                ),
              ),
              // the switch between all and only unread news view
              PopupMenuItem<int>(
                value: 1,
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: Icon(
                        appState.newsStatus == FluxNewsState.unreadNewsStatus ? Icons.checklist : Icons.fiber_new,
                      ),
                    ),
                    Expanded(
                      child: appState.newsStatus == FluxNewsState.unreadNewsStatus
                          ? Text(
                              AppLocalizations.of(context)!.showRead,
                              overflow: TextOverflow.visible,
                            )
                          : Text(
                              AppLocalizations.of(context)!.showUnread,
                              overflow: TextOverflow.visible,
                            ),
                    )
                  ],
                ),
              ),
              // the selection of the sort order of the news (newest first or oldest first)
              PopupMenuItem<int>(
                value: 2,
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(right: 5),
                      child: Icon(
                        Icons.sort,
                      ),
                    ),
                    Expanded(
                      child: appState.sortOrder == FluxNewsState.sortOrderNewestFirstString
                          ? Text(
                              AppLocalizations.of(context)!.oldestFirst,
                              overflow: TextOverflow.visible,
                            )
                          : Text(
                              AppLocalizations.of(context)!.newestFirst,
                              overflow: TextOverflow.visible,
                            ),
                    )
                  ],
                ),
              ),
              PopupMenuItem<int>(
                value: 3,
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(right: 5),
                      child: Icon(
                        Icons.check_circle_outline,
                      ),
                    ),
                    Expanded(
                      child: appState.selectedCategoryElementType == FluxNewsState.feedElementType
                          ? Text(
                              AppLocalizations.of(context)!.markFeedAsRead,
                              overflow: TextOverflow.visible,
                            )
                          : appState.selectedCategoryElementType == FluxNewsState.categoryElementType
                              ? Text(
                                  AppLocalizations.of(context)!.markCategoryAsRead,
                                  overflow: TextOverflow.visible,
                                )
                              : appState.selectedCategoryElementType == FluxNewsState.bookmarkedNewsElementType
                                  ? Text(
                                      AppLocalizations.of(context)!.markBookmarkedAsRead,
                                      overflow: TextOverflow.visible,
                                    )
                                  : Text(
                                      AppLocalizations.of(context)!.markAllAsRead,
                                      overflow: TextOverflow.visible,
                                    ),
                    )
                  ],
                ),
              ),
              // the navigation to the settings
              PopupMenuItem<int>(
                value: 4,
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(right: 5),
                      child: Icon(
                        Icons.settings,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)!.settings,
                        overflow: TextOverflow.visible,
                      ),
                    )
                  ],
                ),
              ),
            ];
          },
          onSelected: (value) async {
            if (value == 0) {
              // navigate to the search page
              Navigator.pushNamed(context, FluxNewsState.searchRouteString);
            } else if (value == 1) {
              // switch between all and only unread news view
              // if the current view is unread news change to all news
              if (appState.newsStatus == FluxNewsState.unreadNewsStatus) {
                // switch the state to all news
                appState.newsStatus = FluxNewsState.allNewsString;

                // save the state persistent
                appState.storage
                    .write(key: FluxNewsState.secureStorageNewsStatusKey, value: FluxNewsState.allNewsString);

                // refresh news list with the all news state
                appState.newsList = queryNewsFromDB(appState).whenComplete(() {
                  appState.jumpToItem(0);
                });

                // notify the categories to update the news count
                appCounterState.listUpdated = true;
                appCounterState.refreshView();
                appState.refreshView();
                // if the current view is all news change to only unread news
              } else {
                // switch the state to show only unread news
                appState.newsStatus = FluxNewsState.unreadNewsStatus;

                // save the state persistent
                appState.storage
                    .write(key: FluxNewsState.secureStorageNewsStatusKey, value: FluxNewsState.unreadNewsStatus);

                // refresh news list with the only unread news state
                appState.newsList = queryNewsFromDB(appState).whenComplete(() {
                  appState.jumpToItem(0);
                });

                // notify the categories to update the news count
                appCounterState.listUpdated = true;
                appCounterState.refreshView();
                appState.refreshView();
              }
            } else if (value == 2) {
              // switch between newest first and oldest first
              // if the current sort order is newest first change to oldest first
              if (appState.sortOrder == FluxNewsState.sortOrderNewestFirstString) {
                // switch the state to all news
                appState.sortOrder = FluxNewsState.sortOrderOldestFirstString;

                // save the state persistent
                appState.storage.write(
                    key: FluxNewsState.secureStorageSortOrderKey, value: FluxNewsState.sortOrderOldestFirstString);

                // refresh news list with the all news state
                appState.newsList = queryNewsFromDB(appState).whenComplete(() {
                  appState.jumpToItem(0);
                });

                // notify the categories to update the news count
                appCounterState.listUpdated = true;
                appCounterState.refreshView();
                appState.refreshView();
                // if the current sort order is oldest first change to newest first
              } else {
                // switch the state to show only unread news
                appState.sortOrder = FluxNewsState.sortOrderNewestFirstString;

                // save the state persistent
                appState.storage.write(
                    key: FluxNewsState.secureStorageSortOrderKey, value: FluxNewsState.sortOrderNewestFirstString);

                // refresh news list with the only unread news state
                appState.newsList = queryNewsFromDB(appState).whenComplete(() {
                  appState.jumpToItem(0);
                });

                // notify the categories to update the news count
                appCounterState.listUpdated = true;
                appCounterState.refreshView();
                appState.refreshView();
              }
            } else if (value == 3) {
              showDeleteAllDialog(context, appState, appCounterState);
            } else if (value == 4) {
              // navigate to the settings page
              Navigator.pushNamed(context, FluxNewsState.settingsRouteString);
            }
          }),
    ];
  }
}
