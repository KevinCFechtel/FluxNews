import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/miniflux/miniflux_backend.dart';
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/functions/widget_service.dart';
import 'package:flux_news/state_management/flux_news_counter_state.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:flux_news/functions/logging.dart';
import 'package:flux_news/ui/news_card.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/ui/news_row.dart';
import 'package:flux_news/ui/sliver_glass_app_bar.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';
import 'package:scrollview_observer/scrollview_observer.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

// the list view widget with news (main view)
class BodyNewsList extends StatelessWidget {
  const BodyNewsList({
    super.key,
    this.largeTitleController,
    this.topContentInset = 0,
  });

  final GlassLargeTitleController? largeTitleController;
  final double topContentInset;

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    FluxNewsCounterState appCounterState =
        context.watch<FluxNewsCounterState>();
    bool searchView = false;
    Widget listHeader({required bool emptyBody}) {
      if (largeTitleController != null) {
        final showCount = appState.multilineAppBarText;
        final largeTitle = GlassLargeTitle(
          text: appState.appBarText.isEmpty
              ? AppLocalizations.of(context)!.fluxNews
              : appState.appBarText,
          controller: largeTitleController!,
          padding: EdgeInsetsDirectional.fromSTEB(24, 0, 24, showCount ? 2 : 8),
        );
        final count = appCounterState.appBarNewsCount;
        final slivers = <Widget>[
          if (topContentInset > 0)
            SliverToBoxAdapter(child: SizedBox(height: topContentInset)),
          largeTitle,
          if (showCount)
            SliverToBoxAdapter(
              child: AnimatedBuilder(
                animation: largeTitleController!,
                builder: (context, child) {
                  final opacity = Curves.easeIn.transform(
                    (1 - largeTitleController!.collapseProgress)
                        .clamp(0.0, 1.0),
                  );
                  return Opacity(opacity: opacity, child: child);
                },
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 10),
                  child: Semantics(
                    label: '${AppLocalizations.of(context)!.itemCount}: $count',
                    child: Text(
                      AppLocalizations.of(context)!.largeTitleNewsCount(count),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: CupertinoColors.secondaryLabel
                                .resolveFrom(context),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ),
              ),
            ),
        ];
        if (slivers.length == 1) return largeTitle;
        return SliverMainAxisGroup(
          slivers: slivers,
        );
      }
      return !appState.isTablet
          ? SliverGlassAppBar(emptyBody: emptyBody)
          : const SliverToBoxAdapter(child: SizedBox.shrink());
    }

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
                  ? CustomScrollView(
                      controller: appState.scrollController,
                      slivers: <Widget>[
                          listHeader(emptyBody: true),
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Container(
                                alignment: Alignment.center,
                                child: Text(
                                  appState.syncProcess
                                      ? AppLocalizations.of(context)!
                                          .syncInProgress
                                      : AppLocalizations.of(context)!
                                          .noNewEntries,
                                  style:
                                      Theme.of(context).textTheme.headlineSmall,
                                )),
                          )
                        ])
                  // show empty dialog if list is empty
                  : snapshot.data!.isEmpty
                      ? CustomScrollView(
                          controller: appState.scrollController,
                          slivers: <Widget>[
                              listHeader(emptyBody: true),
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: Container(
                                    alignment: Alignment.center,
                                    child: Text(
                                      appState.syncProcess
                                          ? AppLocalizations.of(context)!
                                              .syncInProgress
                                          : AppLocalizations.of(context)!
                                              .noNewEntries,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall,
                                    )),
                              )
                            ])
                      // otherwise create list view with ScrollablePositionedList
                      // to save scroll position persistent
                      : ListViewObserver(
                          autoTriggerObserveTypes: const [
                            ObserverAutoTriggerObserveType.scrollEnd
                          ],
                          triggerOnObserveType:
                              ObserverTriggerOnObserveType.directly,
                          customTargetRenderSliverType: (renderObj) {
                            return renderObj.runtimeType.toString() ==
                                'RenderSuperSliverList';
                          },
                          child: largeTitleController != null ||
                                  !appState.isTablet
                              ? largeTitleController != null ||
                                      appState.useSliverAppBar
                                  ? CustomScrollView(
                                      controller: appState.scrollController,
                                      physics: AlwaysScrollableScrollPhysics(),
                                      slivers: <Widget>[
                                          listHeader(emptyBody: false),
                                          SuperSliverList.builder(
                                              key: const PageStorageKey<String>(
                                                  'NewsList'),
                                              itemCount: snapshot.data!.length,
                                              listController:
                                                  appState.listController,
                                              itemBuilder: (context, i) {
                                                return appState.orientation ==
                                                        Orientation.landscape
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
                                      key: const PageStorageKey<String>(
                                          'NewsList'),
                                      itemCount: snapshot.data!.length,
                                      controller: appState.scrollController,
                                      listController: appState.listController,
                                      itemBuilder: (context, i) {
                                        return appState.orientation ==
                                                Orientation.landscape
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
                                    return appState.orientation ==
                                            Orientation.landscape
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
                          onObserve: (resultModel) async {
                            final appCounterState =
                                context.read<FluxNewsCounterState>();
                            final databaseError =
                                AppLocalizations.of(context)!.databaseError;
                            final communicationMinifluxError =
                                AppLocalizations.of(context)!
                                    .communicateionMinifluxError;
                            final scaffoldMessenger =
                                ScaffoldMessenger.of(context);
                            int lastItem = 0;
                            double lastItemTrailingMarginToViewport = -1.0;
                            int firstItem = 0;
                            var allItemsVisible = false;
                            if (resultModel
                                .displayingChildIndexList.isNotEmpty) {
                              firstItem =
                                  resultModel.displayingChildIndexList.first;
                              lastItem =
                                  resultModel.displayingChildIndexList.last;
                              lastItemTrailingMarginToViewport = resultModel
                                  .displayingChildModelList
                                  .last
                                  .trailingMarginToViewport;
                              allItemsVisible =
                                  resultModel.displayingChildIndexList.length >=
                                      snapshot.data!.length;
                            }
                            appState.scrollPosition = firstItem;

                            appState.storage.write(
                                key: FluxNewsState
                                    .secureStorageSavedScrollPositionKey,
                                value: firstItem.toString());

                            if (appState.markAsReadOnScrollOver) {
                              // if the sync is in progress, no news should marked as read
                              if (appState.syncProcess == false) {
                                final List<int> scrollIds = [];
                                // set all news as read if the list reached the bottom (the last item is more then 95% visible)
                                if (!allItemsVisible &&
                                    lastItem == snapshot.data!.length - 1 &&
                                    lastItemTrailingMarginToViewport >= 0) {
                                  // to ensure that the list is at the bottom edge and not at the top edge
                                  // the amount of scrolled pixels must be greater 0
                                  // iterate through the whole news list and mark news as read
                                  for (int i = 0;
                                      i < snapshot.data!.length;
                                      i++) {
                                    if (snapshot.data![i].status ==
                                        FluxNewsState.readNewsStatus) {
                                      continue;
                                    }
                                    try {
                                      await updateNewsStatusInDB(
                                          snapshot.data![i].newsID,
                                          FluxNewsState.readNewsStatus,
                                          appState);
                                    } catch (e) {
                                      logThis(
                                          'updateNewsStatusInDB',
                                          'Caught an error in updateNewsStatusInDB function! : ${e.toString()}',
                                          LogLevel.ERROR);

                                      if (appState.errorString !=
                                          databaseError) {
                                        appState.errorString = databaseError;
                                        appState.newError = true;
                                        appState.refreshView();
                                      }
                                    }
                                    scrollIds.add(snapshot.data![i].newsID);
                                    snapshot.data![i].status =
                                        FluxNewsState.readNewsStatus;
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
                                    if (snapshot.data![i].status !=
                                        FluxNewsState.readNewsStatus) {
                                      try {
                                        await updateNewsStatusInDB(
                                            snapshot.data![i].newsID,
                                            FluxNewsState.readNewsStatus,
                                            appState);
                                      } catch (e) {
                                        logThis(
                                            'updateNewsStatusInDB',
                                            'Caught an error in updateNewsStatusInDB function! : ${e.toString()}',
                                            LogLevel.ERROR);

                                        if (appState.errorString !=
                                            databaseError) {
                                          appState.errorString = databaseError;
                                          appState.newError = true;
                                          appState.refreshView();
                                        }
                                      }
                                      scrollIds.add(snapshot.data![i].newsID);
                                      snapshot.data![i].status =
                                          FluxNewsState.readNewsStatus;
                                    }
                                  }
                                }
                                if (scrollIds.isNotEmpty) {
                                  if (appState.syncReadStatusImmediately) {
                                    unawaited(pushNewsStatusToServer(
                                      scrollIds,
                                      FluxNewsState.readNewsStatus,
                                      appState,
                                      scaffoldMessenger,
                                      communicationMinifluxError,
                                      suppressAfterFirstError: true,
                                    ));
                                  }
                                  unawaited(FluxNewsWidgetService
                                      .updateWidgetSnapshot(appState));
                                }
                              }
                              // mark the list as updated to recalculate the news count
                              appCounterState.listUpdated = true;
                              appState.refreshView();
                              appCounterState.refreshView();
                            }
                          },
                        );
            }
        }
      },
    );
    return getData;
  }
}
