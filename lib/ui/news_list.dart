import 'dart:async';
import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
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
import 'package:flux_news/ui/read_on_scroll_controller.dart';
import 'package:flux_news/ui/adaptive_layout.dart';
import 'package:flux_news/ui/sliver_glass_app_bar.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';
import 'package:scrollview_observer/scrollview_observer.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

// the list view widget with news (main view)
class BodyNewsList extends StatefulWidget {
  const BodyNewsList({
    super.key,
    this.largeTitleController,
    this.topContentInset = 0,
  });

  final GlassLargeTitleController? largeTitleController;
  final double topContentInset;

  @override
  State<BodyNewsList> createState() => _BodyNewsListState();
}

class _ScrollReadEvent {
  const _ScrollReadEvent({
    required this.news,
    required this.appState,
    required this.counterState,
    required this.databaseError,
    required this.communicationError,
    required this.scaffoldMessenger,
    required this.resetScrollPosition,
  });

  final List<News> news;
  final FluxNewsState appState;
  final FluxNewsCounterState counterState;
  final String databaseError;
  final String communicationError;
  final ScaffoldMessengerState scaffoldMessenger;
  final bool resetScrollPosition;
}

class _BodyNewsListState extends State<BodyNewsList> {
  final IncrementalScrollRangeController<News> _rangeController =
      IncrementalScrollRangeController<News>();
  late final ScrollIdleTaskController<FluxNewsState> _widgetRefreshController =
      ScrollIdleTaskController<FluxNewsState>(
    idleDuration: const Duration(milliseconds: 750),
    handler: FluxNewsWidgetService.updateWidgetSnapshot,
    onError: (error, stackTrace) {
      logThis(
        'BodyNewsList',
        'Could not refresh widgets after scrolling: $error\n$stackTrace',
        LogLevel.ERROR,
      );
    },
  );
  late final SerializedAsyncController<_ScrollReadEvent> _eventController =
      SerializedAsyncController<_ScrollReadEvent>(
    handler: _processScrollReadEvent,
    onError: (error, stackTrace) {
      logThis(
        'BodyNewsList',
        'Caught an unexpected mark-as-read observer error: '
            '$error\n$stackTrace',
        LogLevel.ERROR,
      );
    },
  );

  @override
  void dispose() {
    _widgetRefreshController.dispose(flushPending: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    final appCounterState = context.read<FluxNewsCounterState>();
    final useAndroidFloatingChrome = Platform.isAndroid &&
        (appState.isTablet ||
            appState.appBarType == FluxNewsState.appBarFloatingType);
    final usesFloatingPhoneActions = !appState.isTablet &&
        (Platform.isIOS ||
            (Platform.isAndroid &&
                appState.appBarType == FluxNewsState.appBarFloatingType));
    final useTopFloatingActions = usesFloatingPhoneActions &&
        useTopFloatingActionsInCompactLandscape(
          isTabletLayout: appState.isTablet,
          availableSize: MediaQuery.sizeOf(context),
        );
    final hasBottomFloatingActions =
        usesFloatingPhoneActions && !useTopFloatingActions;
    final mediaQuery = MediaQuery.of(context);
    final bottomContentInset = useTopFloatingActions
        ? bottomSystemNavigationInset(mediaQuery)
        : floatingNewsListBottomInset(
            hasFloatingBottomToolbar: hasBottomFloatingActions,
            mediaBottomPadding: mediaQuery.padding.bottom,
          );
    bool searchView = false;
    Widget listHeader({required bool emptyBody}) {
      if (useAndroidFloatingChrome) {
        return SliverToBoxAdapter(
          child: SizedBox(height: widget.topContentInset),
        );
      }
      if (useStandaloneTabletListHeaderInset(
        isTablet: appState.isTablet,
        topContentInset: widget.topContentInset,
        hasLargeTitleController: widget.largeTitleController != null,
      )) {
        return SliverToBoxAdapter(
          child: SizedBox(height: widget.topContentInset),
        );
      }
      if (widget.largeTitleController != null) {
        final showCount = appState.multilineAppBarText;
        final largeTitle = GlassLargeTitle(
          text: appState.appBarText.isEmpty
              ? AppLocalizations.of(context)!.fluxNews
              : appState.appBarText,
          controller: widget.largeTitleController!,
          padding: EdgeInsetsDirectional.fromSTEB(24, 0, 24, showCount ? 2 : 8),
        );
        final slivers = <Widget>[
          if (widget.topContentInset > 0)
            SliverToBoxAdapter(child: SizedBox(height: widget.topContentInset)),
          largeTitle,
          if (showCount)
            SliverToBoxAdapter(
              child: AnimatedBuilder(
                animation: widget.largeTitleController!,
                builder: (context, child) {
                  final opacity = Curves.easeIn.transform(
                    (1 - widget.largeTitleController!.collapseProgress)
                        .clamp(0.0, 1.0),
                  );
                  return Opacity(opacity: opacity, child: child);
                },
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 10),
                  child: ValueListenableBuilder<int>(
                    valueListenable: appCounterState.appBarNewsCountListenable,
                    builder: (context, count, _) => Semantics(
                      label:
                          '${AppLocalizations.of(context)!.itemCount}: $count',
                      child: Text(
                        AppLocalizations.of(context)!
                            .largeTitleNewsCount(count),
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
                      : NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification is ScrollStartNotification) {
                              _widgetRefreshController.onScrollStarted();
                            } else if (notification is ScrollEndNotification) {
                              _widgetRefreshController.onScrollEnded();
                            }
                            return false;
                          },
                          child: ListViewObserver(
                            autoTriggerObserveTypes: const [
                              ObserverAutoTriggerObserveType.scrollEnd
                            ],
                            triggerOnObserveType:
                                ObserverTriggerOnObserveType.directly,
                            customTargetRenderSliverType: (renderObj) {
                              return renderObj.runtimeType.toString() ==
                                  'RenderSuperSliverList';
                            },
                            child: widget.largeTitleController != null ||
                                    !appState.isTablet ||
                                    widget.topContentInset > 0
                                ? widget.largeTitleController != null ||
                                        appState.useSliverAppBar ||
                                        useAndroidFloatingChrome ||
                                        widget.topContentInset > 0
                                    ? CustomScrollView(
                                        controller: appState.scrollController,
                                        physics:
                                            AlwaysScrollableScrollPhysics(),
                                        slivers: <Widget>[
                                            listHeader(emptyBody: false),
                                            SuperSliverList.builder(
                                                key: const PageStorageKey<
                                                    String>('NewsList'),
                                                itemCount:
                                                    snapshot.data!.length,
                                                listController:
                                                    appState.listController,
                                                itemBuilder: (context, i) {
                                                  return _buildObservedNewsItem(
                                                    appState,
                                                    snapshot.data!,
                                                    i,
                                                    searchView,
                                                  );
                                                }),
                                            if (bottomContentInset > 0)
                                              SliverToBoxAdapter(
                                                child: SizedBox(
                                                  height: bottomContentInset,
                                                ),
                                              ),
                                          ])
                                    : SuperListView.builder(
                                        key: const PageStorageKey<String>(
                                            'NewsList'),
                                        itemCount: snapshot.data!.length,
                                        controller: appState.scrollController,
                                        listController: appState.listController,
                                        itemBuilder: (context, i) {
                                          return _buildObservedNewsItem(
                                            appState,
                                            snapshot.data!,
                                            i,
                                            searchView,
                                          );
                                        })
                                : SuperListView.builder(
                                    key: const PageStorageKey<String>(
                                        'NewsList'),
                                    itemCount: snapshot.data!.length,
                                    controller: appState.scrollController,
                                    listController: appState.listController,
                                    itemBuilder: (context, i) {
                                      return _buildObservedNewsItem(
                                        appState,
                                        snapshot.data!,
                                        i,
                                        searchView,
                                      );
                                    }),
                            onObserve: (resultModel) {
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
                                allItemsVisible = resultModel
                                        .displayingChildIndexList.length >=
                                    snapshot.data!.length;
                              }
                              appState.scrollPosition = firstItem;

                              appState.storage.write(
                                  key: FluxNewsState
                                      .secureStorageSavedScrollPositionKey,
                                  value: firstItem.toString());

                              if (!appState.markAsReadOnScrollOver ||
                                  appState.syncProcess) {
                                return;
                              }

                              final reachedBottom = !allItemsVisible &&
                                  lastItem == snapshot.data!.length - 1 &&
                                  lastItemTrailingMarginToViewport >= 0;
                              final range = _rangeController.capture(
                                items: snapshot.data!,
                                firstVisibleIndex: firstItem,
                                reachedBottom: reachedBottom,
                              );
                              if (range == null) return;

                              unawaited(_eventController.add(_ScrollReadEvent(
                                news: range.items,
                                appState: appState,
                                counterState: appCounterState,
                                databaseError: databaseError,
                                communicationError: communicationMinifluxError,
                                scaffoldMessenger: scaffoldMessenger,
                                resetScrollPosition: reachedBottom,
                              )));
                            },
                          ),
                        );
            }
        }
      },
    );
    return getData;
  }

  Future<void> _processScrollReadEvent(_ScrollReadEvent event) async {
    final scrollIds = <int>[];
    var errorChanged = false;
    for (final news in event.news) {
      if (news.status == FluxNewsState.readNewsStatus) continue;
      try {
        await updateNewsStatusInDB(
          news.newsID,
          FluxNewsState.readNewsStatus,
          event.appState,
        );
      } catch (error) {
        logThis(
          'updateNewsStatusInDB',
          'Caught an error in updateNewsStatusInDB function: $error',
          LogLevel.ERROR,
        );
        if (event.appState.errorString != event.databaseError) {
          event.appState.errorString = event.databaseError;
          event.appState.newError = true;
          errorChanged = true;
        }
        continue;
      }

      news.updateStatus(FluxNewsState.readNewsStatus);
      scrollIds.add(news.newsID);
    }

    if (event.resetScrollPosition && scrollIds.isNotEmpty) {
      event.appState.scrollPosition = 0;
    }
    if (scrollIds.isEmpty) {
      if (errorChanged) event.appState.refreshView();
      return;
    }

    if (event.appState.syncReadStatusImmediately) {
      unawaited(pushNewsStatusToServer(
        scrollIds,
        FluxNewsState.readNewsStatus,
        event.appState,
        event.scaffoldMessenger,
        event.communicationError,
        suppressAfterFirstError: true,
      ));
    }
    _widgetRefreshController.markPending(event.appState);
    final counters = await queryNewsCounterSnapshot(event.appState);
    event.counterState.allNewsCount = counters.allNewsCount;
    event.counterState.appBarNewsCount = counters.currentViewCount;
  }

  Widget _buildObservedNewsItem(
    FluxNewsState appState,
    List<News> newsList,
    int index,
    bool searchView,
  ) {
    final news = newsList[index];
    return ValueListenableBuilder<String>(
      valueListenable: news.statusListenable,
      builder: (context, _, __) {
        return appState.orientation == Orientation.landscape
            ? NewsRow(
                news: news,
                context: context,
                searchView: searchView,
                itemIndex: index,
                newsList: newsList,
              )
            : NewsCard(
                news: news,
                context: context,
                searchView: searchView,
                itemIndex: index,
                newsList: newsList,
              );
      },
    );
  }
}
