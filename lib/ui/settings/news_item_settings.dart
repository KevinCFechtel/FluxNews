import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/state_management/flux_news_theme_state.dart';
import 'package:provider/provider.dart';

import '../../state_management/flux_news_state.dart';

class NewsItemSettings extends StatelessWidget {
  const NewsItemSettings({super.key});

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();

    return FluxNewsNewsItemSettingsStatefulWrapper(onInit: () {
      initConfig(context, appState);
    }, child: OrientationBuilder(builder: (context, orientation) {
      appState.orientation = orientation;
      return newsItemSettingsLayout(context, appState);
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

  Scaffold newsItemSettingsLayout(BuildContext context, FluxNewsState appState) {
    FluxNewsThemeState themeState = context.read<FluxNewsThemeState>();
    return Scaffold(
        appBar: AppBar(
          forceMaterialTransparency: themeState.useBlackMode ? true : false,
          // set the title of the search page to search text field
          title: Text(AppLocalizations.of(context)!.newsItemSettings),
        ),
        // show the news list
        body: const FluxNewsNewsItemSettingsBody());
  }
}

class FluxNewsNewsItemSettingsBody extends StatelessWidget {
  const FluxNewsNewsItemSettingsBody({
    super.key,
  });

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
              // this row contains the selection of the tab action
              Row(
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                    child: const Icon(
                      Icons.touch_app,
                    ),
                  ),
                  Expanded(
                    child: Column(children: [
                      Text(
                        AppLocalizations.of(context)!.tabActionSettings,
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.visible,
                      ),
                      appState.tabAction == FluxNewsState.tabActionSplittedString
                          ? Text(
                              AppLocalizations.of(context)!.splittedDescription,
                              style: Theme.of(context).textTheme.titleMedium!.copyWith(fontStyle: FontStyle.italic),
                              overflow: TextOverflow.visible,
                            )
                          : SizedBox.shrink(),
                    ]),
                  ),
                  DropdownButton<KeyValueRecordType>(
                    value: appState.tabActionSelection,
                    elevation: 16,
                    underline: Container(
                      height: 2,
                    ),
                    alignment: AlignmentDirectional.centerEnd,
                    onChanged: (KeyValueRecordType? value) {
                      if (value != null) {
                        appState.tabAction = value.key;
                        appState.tabActionSelection = value;
                        appState.storage.write(key: FluxNewsState.secureStorageTabActionKey, value: value.key);
                        appState.refreshView();
                      }
                    },
                    items: appState.recordTypesTabActions!
                        .map<DropdownMenuItem<KeyValueRecordType>>((recordType) =>
                            DropdownMenuItem<KeyValueRecordType>(value: recordType, child: Text(recordType.value)))
                        .toList(),
                  ),
                ],
              ),
              const Divider(),
              // this row contains the selection of the long press action
              Row(
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                    child: const Icon(
                      Icons.touch_app_outlined,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.longPressActionSettings,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                  DropdownButton<KeyValueRecordType>(
                    value: appState.longPressActionSelection,
                    elevation: 16,
                    underline: Container(
                      height: 2,
                    ),
                    alignment: AlignmentDirectional.centerEnd,
                    onChanged: (KeyValueRecordType? value) {
                      if (value != null) {
                        appState.longPressAction = value.key;
                        appState.longPressActionSelection = value;
                        appState.storage.write(key: FluxNewsState.secureStorageLongPressActionKey, value: value.key);
                        appState.refreshView();
                      }
                    },
                    items: appState.recordTypesLongPressActions!
                        .map<DropdownMenuItem<KeyValueRecordType>>((recordType) =>
                            DropdownMenuItem<KeyValueRecordType>(value: recordType, child: Text(recordType.value)))
                        .toList(),
                  ),
                ],
              ),
              const Divider(),
              // this row contains the selection if swiping is enabled
              Row(
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                    child: const Icon(
                      Icons.remove_from_queue,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.removeNewsFromListWhenRead,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                  Switch.adaptive(
                    value: appState.removeNewsFromListWhenRead,
                    onChanged: (bool value) {
                      String stringValue = FluxNewsState.secureStorageFalseString;
                      if (value == true) {
                        stringValue = FluxNewsState.secureStorageTrueString;
                      }
                      appState.removeNewsFromListWhenRead = value;
                      appState.storage
                          .write(key: FluxNewsState.secureStorageRemoveNewsFromListWhenReadKey, value: stringValue);
                      appState.refreshView();
                    },
                  ),
                ],
              ),
              const Divider(),
              // this row contains the selection if swiping is enabled
              Row(
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                    child: const Icon(
                      Icons.swipe,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.activateSwiping,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                  Switch.adaptive(
                    value: appState.activateSwipeGestures,
                    onChanged: (bool value) {
                      String stringValue = FluxNewsState.secureStorageFalseString;
                      if (value == true) {
                        stringValue = FluxNewsState.secureStorageTrueString;
                      }
                      appState.activateSwipeGestures = value;
                      appState.storage
                          .write(key: FluxNewsState.secureStorageActivateSwipeGesturesKey, value: stringValue);
                      appState.refreshView();
                    },
                  ),
                ],
              ),
              const Divider(),
              // this row contains the selection of left swipe action
              // there are the choices of read, bookmark and save
              appState.activateSwipeGestures
                  ? Row(
                      children: [
                        Padding(
                          padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                          child: const Icon(
                            Icons.swipe_left,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context)!.leftSwipeSelectionOption,
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.visible,
                          ),
                        ),
                        DropdownButton<KeyValueRecordType>(
                          value: appState.leftSwipeActionSelection,
                          elevation: 16,
                          underline: Container(
                            height: 2,
                          ),
                          alignment: AlignmentDirectional.centerEnd,
                          onChanged: (KeyValueRecordType? value) {
                            if (value != null) {
                              appState.leftSwipeAction = value.key;
                              appState.leftSwipeActionSelection = value;
                              appState.storage
                                  .write(key: FluxNewsState.secureStorageLeftSwipeActionKey, value: value.key);
                              appState.refreshView();
                            }
                          },
                          items: appState.recordTypesSwipeActions!
                              .map<DropdownMenuItem<KeyValueRecordType>>((recordType) =>
                                  DropdownMenuItem<KeyValueRecordType>(
                                      value: recordType, child: Text(recordType.value)))
                              .toList(),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
              appState.activateSwipeGestures ? const Divider() : const SizedBox.shrink(),
              // this row contains the selection of second left swipe action
              // there are the choices of none, read, bookmark and save
              appState.activateSwipeGestures
                  ? Row(
                      children: [
                        Padding(
                          padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                          child: const Icon(
                            Icons.swipe_left,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context)!.secondLeftSwipeSelectionOption,
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.visible,
                          ),
                        ),
                        DropdownButton<KeyValueRecordType>(
                          value: appState.secondLeftSwipeActionSelection,
                          elevation: 16,
                          underline: Container(
                            height: 2,
                          ),
                          alignment: AlignmentDirectional.centerEnd,
                          onChanged: (KeyValueRecordType? value) {
                            if (value != null) {
                              appState.secondLeftSwipeAction = value.key;
                              appState.secondLeftSwipeActionSelection = value;
                              appState.storage
                                  .write(key: FluxNewsState.secureStorageSecondLeftSwipeActionKey, value: value.key);
                              appState.refreshView();
                            }
                          },
                          items: appState.recordTypesSecondSwipeActions!
                              .map<DropdownMenuItem<KeyValueRecordType>>((recordType) =>
                                  DropdownMenuItem<KeyValueRecordType>(
                                      value: recordType, child: Text(recordType.value)))
                              .toList(),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
              appState.activateSwipeGestures ? const Divider() : const SizedBox.shrink(),
              // this row contains the selection of right swipe action
              // there are the choices of read, bookmark and save
              appState.activateSwipeGestures
                  ? Row(
                      children: [
                        Padding(
                          padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                          child: const Icon(
                            Icons.swipe_right,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context)!.rightSwipeSelectionOption,
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.visible,
                          ),
                        ),
                        DropdownButton<KeyValueRecordType>(
                          value: appState.rightSwipeActionSelection,
                          elevation: 16,
                          underline: Container(
                            height: 2,
                          ),
                          alignment: AlignmentDirectional.centerEnd,
                          onChanged: (KeyValueRecordType? value) {
                            if (value != null) {
                              appState.rightSwipeAction = value.key;
                              appState.rightSwipeActionSelection = value;
                              appState.storage
                                  .write(key: FluxNewsState.secureStorageRightSwipeActionKey, value: value.key);
                              appState.refreshView();
                            }
                          },
                          items: appState.recordTypesSwipeActions!
                              .map<DropdownMenuItem<KeyValueRecordType>>((recordType) =>
                                  DropdownMenuItem<KeyValueRecordType>(
                                      value: recordType, child: Text(recordType.value)))
                              .toList(),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
              appState.activateSwipeGestures ? const Divider() : const SizedBox.shrink(),
              // this row contains the selection of second right swipe action
              // there are the choices of none, read, bookmark and save
              appState.activateSwipeGestures
                  ? Row(
                      children: [
                        Padding(
                          padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                          child: const Icon(
                            Icons.swipe_right,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context)!.secondRightSwipeSelectionOption,
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.visible,
                          ),
                        ),
                        DropdownButton<KeyValueRecordType>(
                          value: appState.secondRightSwipeActionSelection,
                          elevation: 16,
                          underline: Container(
                            height: 2,
                          ),
                          alignment: AlignmentDirectional.centerEnd,
                          onChanged: (KeyValueRecordType? value) {
                            if (value != null) {
                              appState.secondRightSwipeAction = value.key;
                              appState.secondRightSwipeActionSelection = value;
                              appState.storage
                                  .write(key: FluxNewsState.secureStorageSecondRightSwipeActionKey, value: value.key);
                              appState.refreshView();
                            }
                          },
                          items: appState.recordTypesSecondSwipeActions!
                              .map<DropdownMenuItem<KeyValueRecordType>>((recordType) =>
                                  DropdownMenuItem<KeyValueRecordType>(
                                      value: recordType, child: Text(recordType.value)))
                              .toList(),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
              appState.activateSwipeGestures ? const Divider() : const SizedBox.shrink(),
            ])));
  }
}

class FluxNewsNewsItemSettingsStatefulWrapper extends StatefulWidget {
  final Function onInit;
  final Widget child;
  const FluxNewsNewsItemSettingsStatefulWrapper({super.key, required this.onInit, required this.child});
  @override
  FluxNewsBodyState createState() => FluxNewsBodyState();
}

// extend class to save actual scroll state of the list view
class FluxNewsBodyState extends State<FluxNewsNewsItemSettingsStatefulWrapper> {
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
