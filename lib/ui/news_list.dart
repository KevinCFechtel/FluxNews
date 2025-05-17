import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/flux_news_localizations.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/state_management/flux_news_counter_state.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:flux_news/functions/logging.dart';
import 'package:flux_news/ui/news_card.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/ui/news_row.dart';
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
                      // to save scroll position persistent
                      : ListViewObserver(
                          autoTriggerObserveTypes: const [ObserverAutoTriggerObserveType.scrollEnd],
                          triggerOnObserveType: ObserverTriggerOnObserveType.directly,
                          customTargetRenderSliverType: (renderObj) {
                            return renderObj.runtimeType.toString() == 'RenderSuperSliverList';
                          },
                          child: SuperListView.builder(
                              key: const PageStorageKey<String>('NewsList'),
                              itemCount: snapshot.data!.length,
                              controller: appState.scrollController,
                              listController: appState.listController,
                              scrollDirection: appState.scrollHorizontal ? Axis.horizontal : Axis.vertical,
                              itemBuilder: (context, i) {
                                return appState.orientation == Orientation.landscape
                                    ? NewsRow(news: snapshot.data![i], context: context, searchView: searchView)
                                    : NewsCard(news: snapshot.data![i], context: context, searchView: searchView);
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
}
