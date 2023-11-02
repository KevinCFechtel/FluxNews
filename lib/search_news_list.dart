// the list view widget with search result
import 'package:flutter/material.dart';
import 'package:flux_news/flux_news_state.dart';
import 'package:flux_news/news_card.dart';
import 'package:flux_news/news_model.dart';
import 'package:flux_news/news_row.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter_gen/gen_l10n/flux_news_localizations.dart';

class SearchewsList extends StatelessWidget {
  const SearchewsList({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    bool searchView = true;
    var getData = FutureBuilder<List<News>>(
      future: appState.searchNewsList,
      builder: (context, snapshot) {
        switch (snapshot.connectionState) {
          case ConnectionState.none:
          case ConnectionState.waiting:
            return const Center(child: CircularProgressIndicator.adaptive());
          default:
            if (snapshot.hasError) {
              return const SizedBox.shrink();
            } else {
              return snapshot.data == null
                  // show empty dialog if list is null
                  ? Center(
                      child: Text(
                      AppLocalizations.of(context)!.emptySearch,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ))
                  // show empty dialog if list is empty
                  : snapshot.data!.isEmpty
                      ? Center(
                          child: Text(
                          AppLocalizations.of(context)!.emptySearch,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ))
                      // otherwise create list view with the news of the search result
                      : Stack(children: [
                          ScrollablePositionedList.builder(
                              key: const PageStorageKey<String>(
                                  'NewsSearchList'),
                              itemCount: snapshot.data!.length,
                              itemScrollController:
                                  appState.searchItemScrollController,
                              itemPositionsListener:
                                  appState.searchItemPositionsListener,
                              initialScrollIndex: 0,
                              itemBuilder: (context, i) {
                                return appState.orientation ==
                                        Orientation.landscape
                                    ? NewsRow(
                                        news: snapshot.data![i],
                                        context: context,
                                        searchView: searchView)
                                    : NewsCard(
                                        news: snapshot.data![i],
                                        context: context,
                                        searchView: searchView);
                              }),
                        ]);
            }
        }
      },
    );
    return getData;
  }
}
