import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/flux_news_localizations.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flux_news/functions/logging.dart';
import 'package:flux_news/ui/search_news_list.dart';
import 'package:provider/provider.dart';

import '../state_management/flux_news_state.dart';
import '../miniflux/miniflux_backend.dart';
import '../models/news_model.dart';

class Search extends StatelessWidget {
  const Search({super.key});

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();

    return FluxNewsSearchStatefulWrapper(onInit: () {
      initConfig(context, appState);
    }, child: OrientationBuilder(builder: (context, orientation) {
      appState.orientation = orientation;
      return searchLayout(context, appState);
    }));
  }

  // initConfig reads the config values from the persistent storage and sets the state
  // accordingly.
  // It also initializes the database connection.
  Future<void> initConfig(BuildContext context, FluxNewsState appState) async {
    await appState.readConfigValues();
    if (context.mounted) {
      appState.readConfig(context);
    }
  }

  Scaffold searchLayout(BuildContext context, FluxNewsState appState) {
    return Scaffold(
        appBar: AppBar(
          // set the title of the search page to search text field
          title: TextField(
            controller: appState.searchController,
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context)!.searchHint,
              hintStyle: Theme.of(context).textTheme.bodyLarge,
              border: UnderlineInputBorder(borderRadius: BorderRadius.circular(2)),
              suffixIcon: IconButton(
                onPressed: () {
                  appState.searchController.clear();
                  appState.searchNewsList = Future<List<News>>.value([]);
                  appState.refreshView();
                },
                icon: const Icon(Icons.clear),
              ),
            ),

            // on change of the search text field, fetch the news list
            onSubmitted: (value) async {
              if (value != '') {
                // fetch the news list from the backend with the search text
                Future<List<News>> searchNewsListResult =
                    fetchSearchedNews(appState, value).onError((error, stackTrace) {
                  logThis('fetchSearchedNews', 'Caught an error in fetchSearchedNews function! : ${error.toString()}',
                      LogLevel.ERROR);
                  if (context.mounted) {
                    if (appState.errorString != AppLocalizations.of(context)!.communicateionMinifluxError) {
                      appState.errorString = AppLocalizations.of(context)!.communicateionMinifluxError;
                      appState.newError = true;
                      appState.refreshView();
                    }
                  }
                  return [];
                });
                // set the state with the fetched news list
                appState.searchNewsList = searchNewsListResult;
                appState.refreshView();
              } else {
                // if search text is empty, set the state with an empty list
                appState.searchNewsList = Future<List<News>>.value([]);
                appState.refreshView();
              }
            },
          ),
        ),
        // show the news list
        body: const FluxNewsSearchBody());
  }
}

class FluxNewsSearchBody extends StatelessWidget {
  const FluxNewsSearchBody({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    // return the body of the search view
    // if there are too many news detected, an error message is shown
    // otherwise the normal list view is returned
    if (appState.tooManyNews) {
      return const TooManyNewsWidget();
    } else {
      return const SearchNewsList();
    }
  }
}

// this widget replace the normal news list widget, if too many news are detected
// it will pop up an too many news warning dialog and then show the normal news list in the background.
class TooManyNewsWidget extends StatelessWidget {
  const TooManyNewsWidget({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    Timer.run(() {
      showTooManyNewsWidget(context).then((value) {
        appState.tooManyNews = false;
        appState.refreshView();
      });
    });
    return const SearchNewsList();
  }

  // this is the error dialog which is shown, if a error occurs.
  // to prevent the multi pop up (f.e. if the internet connection ist lost
  // not every function which require the connection should raise a pop up)
  // we check if the error which is shown is a new error.
  Future showTooManyNewsWidget(BuildContext context) async {
    FluxNewsState appState = context.read<FluxNewsState>();
    if (appState.tooManyNews) {
      showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog.adaptive(
              title: Text(AppLocalizations.of(context)!.error),
              content: Text(AppLocalizations.of(context)!.tooManyNews),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    Navigator.pop(context, FluxNewsState.cancelContextString);
                  },
                  child: Text(AppLocalizations.of(context)!.ok),
                ),
              ],
            );
          });
    }
  }
}

class FluxNewsSearchStatefulWrapper extends StatefulWidget {
  final Function onInit;
  final Widget child;
  const FluxNewsSearchStatefulWrapper({super.key, required this.onInit, required this.child});
  @override
  FluxNewsBodyState createState() => FluxNewsBodyState();
}

// extend class to save actual scroll state of the list view
class FluxNewsBodyState extends State<FluxNewsSearchStatefulWrapper> {
  // init the state of FluxNewsBody to load the config and the data on startup
  @override
  void initState() {
    widget.onInit();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
