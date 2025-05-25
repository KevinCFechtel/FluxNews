import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/flux_news_localizations.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/functions/logging.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/state_management/flux_news_theme_state.dart';
import 'package:flux_news/ui/feed_settings_list.dart';
import 'package:provider/provider.dart';

import '../state_management/flux_news_state.dart';

class FeedSettings extends StatelessWidget {
  const FeedSettings({super.key});

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();

    return FluxNewsFeedSettingsStatefulWrapper(onInit: () {
      initConfig(context, appState);
      appState.feedSettingsList = queryFeedsFromDB(appState, context, '');
    }, child: OrientationBuilder(builder: (context, orientation) {
      appState.orientation = orientation;
      return feedSettingsLayout(context, appState);
    }));
  }

  // initConfig reads the config values from the persistent storage and sets the state
  // accordingly.
  // It also initializes the database connection.
  Future<void> initConfig(BuildContext context, FluxNewsState appState) async {
    await appState.readConfigValues();
    if (context.mounted) {
      appState.readConfig(context);
      appState.readThemeConfigValues(context);
    }
  }

  Scaffold feedSettingsLayout(BuildContext context, FluxNewsState appState) {
    FluxNewsThemeState themeState = context.read<FluxNewsThemeState>();
    return Scaffold(
        appBar: AppBar(
          forceMaterialTransparency: themeState.useBlackMode ? true : false,
          // set the title of the search page to search text field
          title: Text(AppLocalizations.of(context)!.feedSettings),
        ),
        // show the news list
        body: const FluxNewsFeedSettingsBody());
  }
}

class FluxNewsFeedSettingsBody extends StatelessWidget {
  const FluxNewsFeedSettingsBody({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    // return the body of the feed settings
    return Column(children: [
      Padding(
        padding: EdgeInsets.only(left: 10, right: 10),
        child: TextField(
          controller: appState.searchController,
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context)!.searchHint,
            hintStyle: Theme.of(context).textTheme.bodyLarge,
            border: UnderlineInputBorder(borderRadius: BorderRadius.circular(2)),
            suffixIcon: IconButton(
              onPressed: () {
                appState.searchController.clear();
                appState.feedSettingsList = queryFeedsFromDB(appState, context, '');
                appState.refreshView();
              },
              icon: const Icon(Icons.clear),
            ),
          ),

          // on change of the search text field, fetch the news list
          onChanged: (value) async {
            if (value != '') {
              // fetch the news list from the backend with the search text
              Future<List<Feed>> searchFeedListResult =
                  queryFeedsFromDB(appState, context, value).onError((error, stackTrace) {
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
              appState.feedSettingsList = searchFeedListResult;
              appState.refreshView();
            } else {
              // if search text is empty, set the state with an empty list
              appState.feedSettingsList = queryFeedsFromDB(appState, context, '');
              appState.refreshView();
            }
          },
        ),
      ),
      Expanded(child: const FeedSettingsList())
    ]);
  }
}

class FluxNewsFeedSettingsStatefulWrapper extends StatefulWidget {
  final Function onInit;
  final Widget child;
  const FluxNewsFeedSettingsStatefulWrapper({super.key, required this.onInit, required this.child});
  @override
  FluxNewsBodyState createState() => FluxNewsBodyState();
}

// extend class to save actual scroll state of the list view
class FluxNewsBodyState extends State<FluxNewsFeedSettingsStatefulWrapper> {
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
