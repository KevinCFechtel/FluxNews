import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/ui/settings/adaptive_settings_scaffold.dart';
import 'package:flux_news/ui/settings/adaptive_settings_controls.dart';
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
    if (!await appState.readConfigValues()) return;
    if (context.mounted) {
      appState.readConfig(context);
      appState.readThemeConfigValues(context);
    }
  }

  Widget headerSettingsLayout(BuildContext context, FluxNewsState appState) {
    return AdaptiveSettingsScaffold(
      title: AppLocalizations.of(context)!.headers,
      useLargeTitle: true,
      body: const FluxNewsHeaderSettingsBody(),
    );
  }
}

class FluxNewsHeaderSettingsBody extends StatefulWidget {
  const FluxNewsHeaderSettingsBody({
    super.key,
  });

  @override
  State<FluxNewsHeaderSettingsBody> createState() =>
      _FluxNewsHeaderSettingsBodyState();
}

class _FluxNewsHeaderSettingsBodyState
    extends State<FluxNewsHeaderSettingsBody> {
  final TextEditingController _headerKeyController = TextEditingController();
  final TextEditingController _headerValueController = TextEditingController();

  @override
  void dispose() {
    _headerKeyController.dispose();
    _headerValueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    // return the body of the feed settings
    return SingleChildScrollView(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: AdaptiveSettingsGroup(children: [
              Wrap(children: [
                Text(AppLocalizations.of(context)!.headerKey),
                AdaptiveSettingsTextField(
                  controller: _headerKeyController,
                )
              ]),
              Wrap(children: [
                Text(AppLocalizations.of(context)!.headerValue),
                AdaptiveSettingsTextField(
                  controller: _headerValueController,
                )
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: AdaptiveSettingsButton(
                  onPressed: () {
                    String newHeaderKey = "";
                    String newHeaderValue = "";
                    if (_headerKeyController.text != '') {
                      newHeaderKey = _headerKeyController.text;
                    }
                    if (newHeaderKey != '') {
                      if (_headerValueController.text != '') {
                        newHeaderValue = _headerValueController.text;
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
  const FluxNewsHeaderSettingsStatefulWrapper(
      {super.key, required this.onInit, required this.child});
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
