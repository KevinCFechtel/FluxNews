import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:provider/provider.dart';

import '../../state_management/flux_news_state.dart';

class SyncSettings extends StatelessWidget {
  const SyncSettings({super.key});

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();

    return FluxNewsSyncSettingsStatefulWrapper(onInit: () {
      initConfig(context, appState);
    }, child: OrientationBuilder(builder: (context, orientation) {
      appState.orientation = orientation;
      return syncSettingsLayout(context, appState);
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

  Scaffold syncSettingsLayout(BuildContext context, FluxNewsState appState) {
    return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          // set the title of the search page to search text field
          title: Text(AppLocalizations.of(context)!.syncSettings),
        ),
        // show the news list
        body: const FluxNewsSyncSettingsBody());
  }
}

class FluxNewsSyncSettingsBody extends StatelessWidget {
  const FluxNewsSyncSettingsBody({
    super.key,
  });

  // define the selection lists for the settings of saved news and starred news
  static const List<int> amountOfSavedNewsList = <int>[50, 100, 200, 500, 1000, 2000, 5000, 10000];
  static const List<int> amountOfSavedStarredNewsList = <int>[50, 100, 200, 500, 1000, 2000, 5000, 10000];

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
              // this row contains the selection of the amount of saved news
              // if the news exceeds the amount, the oldest news were deleted
              Row(
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                    child: const Icon(
                      Icons.save_alt,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.amountSaved,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                  DropdownButton<int>(
                    value: appState.amountOfSavedNews,
                    elevation: 16,
                    underline: Container(
                      height: 2,
                    ),
                    alignment: AlignmentDirectional.centerEnd,
                    onChanged: (int? value) {
                      if (value != null) {
                        appState.amountOfSavedNews = value;
                        appState.storage
                            .write(key: FluxNewsState.secureStorageAmountOfSavedNewsKey, value: value.toString());
                        appState.refreshView();
                      }
                    },
                    items: amountOfSavedNewsList.map<DropdownMenuItem<int>>((int value) {
                      return DropdownMenuItem<int>(
                        value: value,
                        child: Text(value.toString()),
                      );
                    }).toList(),
                  ),
                ],
              ),
              const Divider(),
              // this row contains the selection of the amount of saved starred news
              // if the news exceeds the amount, the oldest news were deleted
              Row(
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                    child: const Icon(
                      Icons.star,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.amountSavedStarred,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                  DropdownButton<int>(
                    value: appState.amountOfSavedStarredNews,
                    elevation: 16,
                    underline: Container(
                      height: 2,
                    ),
                    alignment: AlignmentDirectional.centerEnd,
                    onChanged: (int? value) {
                      if (value != null) {
                        appState.amountOfSavedStarredNews = value;
                        appState.storage.write(
                            key: FluxNewsState.secureStorageAmountOfSavedStarredNewsKey, value: value.toString());
                        appState.refreshView();
                      }
                    },
                    items: amountOfSavedStarredNewsList.map<DropdownMenuItem<int>>((int value) {
                      return DropdownMenuItem<int>(
                        value: value,
                        child: Text(value.toString()),
                      );
                    }).toList(),
                  ),
                ],
              ),
              const Divider(),
              // this row contains the selection of the amount of synced news
              // there are the choices of all, 1000, 2000, 5000 and 10000
              Row(
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                    child: const Icon(
                      Icons.repeat_one,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.amountOfSyncedNews,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                  DropdownButton<KeyValueRecordType>(
                    value: appState.amontOfSyncedNewsSelection,
                    elevation: 16,
                    underline: Container(
                      height: 2,
                    ),
                    alignment: AlignmentDirectional.centerEnd,
                    onChanged: (KeyValueRecordType? value) {
                      if (value != null) {
                        appState.amountOfSyncedNews = int.parse(value.key);
                        appState.amontOfSyncedNewsSelection = value;
                        appState.storage.write(key: FluxNewsState.secureStorageAmountOfSyncedNewsKey, value: value.key);
                        appState.refreshView();
                      }
                    },
                    items: appState.recordTypesAmountOfSyncedNews!
                        .map<DropdownMenuItem<KeyValueRecordType>>((recordType) => DropdownMenuItem<KeyValueRecordType>(
                              value: recordType,
                              child: Text(
                                recordType.value,
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ),
              const Divider(),
              // this row contains the selection of the amount of searched news
              // there are the choices of all, 1000, 2000, 5000 and 10000
              Row(
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                    child: const Icon(
                      Icons.manage_search,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.amountOfSearchedNews,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                  DropdownButton<KeyValueRecordType>(
                    value: appState.amontOfSearchedNewsSelection,
                    elevation: 16,
                    underline: Container(
                      height: 2,
                    ),
                    alignment: AlignmentDirectional.centerEnd,
                    onChanged: (KeyValueRecordType? value) {
                      if (value != null) {
                        appState.amountOfSearchedNews = int.parse(value.key);
                        appState.amontOfSearchedNewsSelection = value;
                        appState.storage
                            .write(key: FluxNewsState.secureStorageAmountOfSearchedNewsKey, value: value.key);
                        appState.refreshView();
                      }
                    },
                    items: appState.recordTypesAmountOfSearchedNews!
                        .map<DropdownMenuItem<KeyValueRecordType>>((recordType) => DropdownMenuItem<KeyValueRecordType>(
                              value: recordType,
                              child: Text(
                                recordType.value,
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ),
              const Divider(),
              // this row contains the selection of the sync on start
              Row(
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                    child: const Icon(
                      Icons.checklist_outlined,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.syncReadNews,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                  Switch.adaptive(
                    value: appState.syncReadNews,
                    onChanged: (bool value) {
                      String stringValue = FluxNewsState.secureStorageFalseString;
                      if (value == true) {
                        stringValue = FluxNewsState.secureStorageTrueString;
                      }
                      appState.syncReadNews = value;
                      appState.storage.write(key: FluxNewsState.secureStorageSyncReadNewsKey, value: stringValue);
                      appState.refreshView();
                    },
                  ),
                ],
              ),
              appState.syncReadNews ? const Divider() : const SizedBox.shrink(),
              // this row contains the selection of the amount read news to sync after days
              appState.syncReadNews
                  ? Row(
                      children: [
                        Padding(
                          padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                          child: const Icon(
                            Icons.calendar_view_day,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context)!.syncReadNewsAfterDays,
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.visible,
                          ),
                        ),
                        DropdownButton<KeyValueRecordType>(
                          value: appState.syncReadNewsAfterDaysSelection,
                          elevation: 16,
                          underline: Container(
                            height: 2,
                          ),
                          alignment: AlignmentDirectional.centerEnd,
                          onChanged: (KeyValueRecordType? value) {
                            if (value != null) {
                              appState.syncReadNewsAfterDays = int.parse(value.key);
                              appState.syncReadNewsAfterDaysSelection = value;
                              appState.storage
                                  .write(key: FluxNewsState.secureStorageSyncReadNewsAfterDaysKey, value: value.key);
                              appState.refreshView();
                            }
                          },
                          items: appState.recordTypesSyncReadNewsAfterDays!
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
              const Divider(),
              // this row contains the selection of the sync on start
              Row(
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                    child: const Icon(
                      Icons.timelapse,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.skipLongSync,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                  Switch.adaptive(
                    value: appState.skipLongSync,
                    onChanged: (bool value) {
                      String stringValue = FluxNewsState.secureStorageFalseString;
                      if (value == true) {
                        stringValue = FluxNewsState.secureStorageTrueString;
                      }
                      appState.skipLongSync = value;
                      appState.storage.write(key: FluxNewsState.secureStorageSkipLongSyncKey, value: stringValue);
                      appState.refreshView();
                    },
                  ),
                ],
              ),
            ])));
  }
}

class FluxNewsSyncSettingsStatefulWrapper extends StatefulWidget {
  final Function onInit;
  final Widget child;
  const FluxNewsSyncSettingsStatefulWrapper({super.key, required this.onInit, required this.child});
  @override
  FluxNewsBodyState createState() => FluxNewsBodyState();
}

// extend class to save actual scroll state of the list view
class FluxNewsBodyState extends State<FluxNewsSyncSettingsStatefulWrapper> {
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
