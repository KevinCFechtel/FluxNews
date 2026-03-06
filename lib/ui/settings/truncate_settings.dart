import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:provider/provider.dart';

import '../../state_management/flux_news_state.dart';

class TruncateSettings extends StatelessWidget {
  const TruncateSettings({super.key});

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();

    return FluxNewsTruncateSettingsStatefulWrapper(onInit: () {
      initConfig(context, appState);
    }, child: OrientationBuilder(builder: (context, orientation) {
      appState.orientation = orientation;
      return truncateSettingsLayout(context, appState);
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

  Scaffold truncateSettingsLayout(BuildContext context, FluxNewsState appState) {
    return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          // set the title of the search page to search text field
          title: Text(AppLocalizations.of(context)!.truncateSettings),
        ),
        // show the news list
        body: const FluxNewsTruncateSettingsBody());
  }
}

class FluxNewsTruncateSettingsBody extends StatelessWidget {
  const FluxNewsTruncateSettingsBody({
    super.key,
  });

  static const List<int> amountOfCharactersToTruncate = <int>[100, 200, 300, 400, 500, 600, 700, 800, 900, 1000];

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    // return the body of the feed settings
    return SingleChildScrollView(
        child: Container(
            padding: const EdgeInsets.all(12),
            alignment: Alignment.center,
            // this is the main column of the settings page
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Divider(),
              // this sections contains the truncate options
              Row(
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                    child: const Icon(
                      Icons.cut_outlined,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.activateTruncate,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                  Switch.adaptive(
                    value: appState.activateTruncate,
                    onChanged: (bool value) {
                      String stringValue = FluxNewsState.secureStorageFalseString;
                      if (value == true) {
                        stringValue = FluxNewsState.secureStorageTrueString;
                      }
                      appState.activateTruncate = value;
                      appState.storage.write(key: FluxNewsState.secureStorageActivateTruncateKey, value: stringValue);
                      appState.refreshView();
                    },
                  ),
                ],
              ),
              const Divider(),
              appState.activateTruncate
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12.0, left: 20.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Text(AppLocalizations.of(context)!.truncateMode,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.normal,
                              )),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
              appState.activateTruncate
                  ? RadioGroup<int>(
                      groupValue: appState.truncateMode,
                      onChanged: (int? value) {
                        if (value != null) {
                          appState.truncateMode = value;
                          appState.storage
                              .write(key: FluxNewsState.secureStorageTruncateModeKey, value: value.toString());
                          appState.refreshView();
                        }
                      },
                      child: Column(children: [
                        RadioListTile<int>(
                          title: Text(AppLocalizations.of(context)!.truncateModeAll,
                              style: Theme.of(context).textTheme.titleMedium),
                          value: 0,
                        ),
                        RadioListTile<int>(
                          title: Text(AppLocalizations.of(context)!.truncateModeScraper,
                              style: Theme.of(context).textTheme.titleMedium),
                          value: 1,
                        ),
                        RadioListTile<int>(
                          title: Text(AppLocalizations.of(context)!.truncateModeManual,
                              style: Theme.of(context).textTheme.titleMedium),
                          value: 2,
                        )
                      ]))
                  : const SizedBox.shrink(),

              appState.activateTruncate ? const Divider() : const SizedBox.shrink(),
              appState.activateTruncate
                  ? Row(
                      children: [
                        Padding(
                          padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                          child: const Icon(
                            Icons.cut_outlined,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context)!.charactersToTruncate,
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.visible,
                          ),
                        ),
                        DropdownButton<int>(
                          value: appState.charactersToTruncate,
                          elevation: 16,
                          underline: Container(
                            height: 2,
                          ),
                          alignment: AlignmentDirectional.centerEnd,
                          onChanged: (int? value) {
                            if (value != null) {
                              appState.charactersToTruncate = value;
                              appState.storage.write(
                                  key: FluxNewsState.secureStorageCharactersToTruncateKey, value: value.toString());
                              appState.refreshView();
                            }
                          },
                          items: amountOfCharactersToTruncate.map<DropdownMenuItem<int>>((int value) {
                            return DropdownMenuItem<int>(
                              value: value,
                              child: Text(value.toString()),
                            );
                          }).toList(),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
              appState.activateTruncate ? const Divider() : const SizedBox.shrink(),
              appState.activateTruncate
                  ? Row(
                      children: [
                        Padding(
                          padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                          child: const Icon(
                            Icons.cut_outlined,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context)!.charactersToTruncateLimit,
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.visible,
                          ),
                        ),
                        DropdownButton<KeyValueRecordType>(
                          value: appState.amountOfCharactersToTruncateLimitSelection,
                          elevation: 16,
                          underline: Container(
                            height: 2,
                          ),
                          alignment: AlignmentDirectional.centerEnd,
                          onChanged: (KeyValueRecordType? value) {
                            if (value != null) {
                              appState.charactersToTruncateLimit = int.parse(value.key);
                              appState.amountOfCharactersToTruncateLimitSelection = value;
                              appState.storage.write(
                                  key: FluxNewsState.secureStorageCharactersToTruncateLimitKey, value: value.key);
                              appState.refreshView();
                            }
                          },
                          items: appState.recordTypesAmountOfCharactersToTruncateLimit!
                              .map<DropdownMenuItem<KeyValueRecordType>>(
                                  (recordType) => DropdownMenuItem<KeyValueRecordType>(
                                        value: recordType,
                                        child: Text(
                                          recordType.value,
                                        ),
                                      ))
                              .toList(),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
              appState.activateTruncate ? const Divider() : const SizedBox.shrink(),
            ])));
  }
}

class FluxNewsTruncateSettingsStatefulWrapper extends StatefulWidget {
  final Function onInit;
  final Widget child;
  const FluxNewsTruncateSettingsStatefulWrapper({super.key, required this.onInit, required this.child});
  @override
  FluxNewsBodyState createState() => FluxNewsBodyState();
}

// extend class to save actual scroll state of the list view
class FluxNewsBodyState extends State<FluxNewsTruncateSettingsStatefulWrapper> {
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
