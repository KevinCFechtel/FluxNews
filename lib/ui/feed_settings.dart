import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/flux_news_localizations.dart';
import 'package:flux_news/database/database_backend.dart';
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
      appState.feedSettingsList = queryFeedsFromDB(appState, context);
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
    }
  }

  Scaffold feedSettingsLayout(BuildContext context, FluxNewsState appState) {
    return Scaffold(
        appBar: AppBar(
          forceMaterialTransparency: appState.useBlackMode ? true : false,
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
    // return the body of the feed settings
    return const FeedSettingsList();
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
