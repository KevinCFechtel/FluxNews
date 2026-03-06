import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:provider/provider.dart';

import '../../state_management/flux_news_state.dart';

class HeaderSettings extends StatelessWidget {
  const HeaderSettings({super.key});

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();

    return FluxNewsHeaderSettingsStatefulWrapper(onInit: () {
      initConfig(context, appState);
    }, child: OrientationBuilder(builder: (context, orientation) {
      appState.orientation = orientation;
      return headerSettingsLayout(context, appState);
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

  Scaffold headerSettingsLayout(BuildContext context, FluxNewsState appState) {
    return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          // set the title of the search page to search text field
          title: Text(AppLocalizations.of(context)!.headers),
        ),
        // show the news list
        body: const FluxNewsHeaderSettingsBody());
  }
}

class FluxNewsHeaderSettingsBody extends StatelessWidget {
  const FluxNewsHeaderSettingsBody({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    TextEditingController haderKeycontroller = TextEditingController();
    TextEditingController haderValuecontroller = TextEditingController();
    // return the body of the feed settings
    return SingleChildScrollView(
        child: Container(
            padding: const EdgeInsets.all(12),
            alignment: Alignment.center,
            // this is the main column of the settings page
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(children: [
                Text(AppLocalizations.of(context)!.headerKey),
                TextField(
                  controller: haderKeycontroller,
                )
              ]),
              Wrap(children: [
                Text(AppLocalizations.of(context)!.headerValue),
                TextField(
                  controller: haderValuecontroller,
                )
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: OutlinedButton(
                  onPressed: () {
                    String newHeaderKey = "";
                    String newHeaderValue = "";
                    if (haderKeycontroller.text != '') {
                      newHeaderKey = haderKeycontroller.text;
                    }
                    if (newHeaderKey != '') {
                      if (haderValuecontroller.text != '') {
                        newHeaderValue = haderValuecontroller.text;
                      }

                      var header = {
                        newHeaderKey: newHeaderValue,
                      };

                      appState.customHeaders.addAll(header);

                      appState.saveCustomHeadersToStorage();
                      appState.refreshView();
                    }
                  },
                  child: Text(AppLocalizations.of(context)!.save),
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Expanded(
                        child: Text(AppLocalizations.of(context)!.headers,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.normal,
                              overflow: TextOverflow.visible,
                            ))),
                  ],
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    DataColumn(
                      label: Text(
                        AppLocalizations.of(context)!.headerKey,
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        AppLocalizations.of(context)!.headerValue,
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        '',
                      ),
                    ),
                  ],
                  rows: appState.customHeaders.entries
                      .map(
                        (entry) => DataRow(cells: [
                          DataCell(Text(entry.key)),
                          DataCell(Text(entry.value)),
                          DataCell(TextButton(
                            onPressed: () {
                              appState.customHeaders.remove(entry.key);
                              appState.saveCustomHeadersToStorage();
                              appState.refreshView();
                            },
                            child: Text(AppLocalizations.of(context)!.delete),
                          ))
                        ]),
                      )
                      .toList(),
                ),
              ),
            ])));
  }
}

class FluxNewsHeaderSettingsStatefulWrapper extends StatefulWidget {
  final Function onInit;
  final Widget child;
  const FluxNewsHeaderSettingsStatefulWrapper({super.key, required this.onInit, required this.child});
  @override
  FluxNewsBodyState createState() => FluxNewsBodyState();
}

// extend class to save actual scroll state of the list view
class FluxNewsBodyState extends State<FluxNewsHeaderSettingsStatefulWrapper> {
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
