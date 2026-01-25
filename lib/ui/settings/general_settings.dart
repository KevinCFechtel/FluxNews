import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/state_management/flux_news_theme_state.dart';
import 'package:provider/provider.dart';

import '../../state_management/flux_news_state.dart';

class GeneralSettings extends StatelessWidget {
  const GeneralSettings({super.key});

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();

    return FluxNewsGeneralSettingsStatefulWrapper(onInit: () {
      initConfig(context, appState);
    }, child: OrientationBuilder(builder: (context, orientation) {
      appState.orientation = orientation;
      return generalSettingsLayout(context, appState);
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

  Scaffold generalSettingsLayout(BuildContext context, FluxNewsState appState) {
    FluxNewsThemeState themeState = context.read<FluxNewsThemeState>();
    return Scaffold(
        appBar: AppBar(
          forceMaterialTransparency: themeState.useBlackMode ? true : false,
          // set the title of the search page to search text field
          title: Text(AppLocalizations.of(context)!.generalSettings),
        ),
        // show the news list
        body: const FluxNewsGeneralSettingsBody());
  }
}

class FluxNewsGeneralSettingsBody extends StatelessWidget {
  const FluxNewsGeneralSettingsBody({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    FluxNewsThemeState themeState = context.read<FluxNewsThemeState>();
    // return the body of the feed settings
    return SingleChildScrollView(
        child: Container(
            padding: const EdgeInsets.all(12),
            alignment: Alignment.center,
            // this is the main column of the settings page
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Divider(),
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Expanded(
                        child: Text(AppLocalizations.of(context)!.startupCategorie,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.normal,
                              overflow: TextOverflow.visible,
                            ))),
                  ],
                ),
              ),
              RadioGroup<int>(
                  groupValue: appState.startupCategorie,
                  onChanged: (int? value) {
                    if (value != null) {
                      appState.startupCategorie = value;
                      appState.storage
                          .write(key: FluxNewsState.secureStorageStartupCategorieKey, value: value.toString());
                      appState.refreshView();
                    }
                  },
                  child: Column(children: [
                    RadioListTile<int>(
                      title: Text(AppLocalizations.of(context)!.startupCategorieAll,
                          style: Theme.of(context).textTheme.titleMedium),
                      value: 0,
                    ),
                    RadioListTile<int>(
                      title: Text(AppLocalizations.of(context)!.startupCategorieBookmarks,
                          style: Theme.of(context).textTheme.titleMedium),
                      value: 1,
                    ),
                    RadioListTile<int>(
                      title: Text(AppLocalizations.of(context)!.startupCategorieCategorie,
                          style: Theme.of(context).textTheme.titleMedium),
                      value: 2,
                    ),
                    RadioListTile<int>(
                      title: Text(AppLocalizations.of(context)!.startupCategorieFeed,
                          style: Theme.of(context).textTheme.titleMedium),
                      value: 3,
                    )
                  ])),
              appState.startupCategorie == 2 ? const Divider() : const SizedBox.shrink(),
              appState.startupCategorie == 2
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12.0),
                      child: Row(
                        children: [
                          Padding(
                            padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                            child: const Icon(
                              Icons.feed,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              AppLocalizations.of(context)!.startupCategorieCategorieSelection,
                              style: Theme.of(context).textTheme.titleMedium,
                              overflow: TextOverflow.visible,
                            ),
                          ),
                          DropdownButton<KeyValueRecordType>(
                            value: appState.startupCategorieSelection,
                            elevation: 16,
                            underline: Container(
                              height: 2,
                            ),
                            alignment: AlignmentDirectional.centerEnd,
                            onChanged: (KeyValueRecordType? value) {
                              if (value != null) {
                                appState.startupCategorieSelectionKey = int.parse(value.key);
                                appState.startupCategorieSelection = value;
                                appState.storage.write(
                                    key: FluxNewsState.secureStorageStartupCategorieSelectionKey, value: value.key);
                                appState.refreshView();
                              }
                            },
                            items: appState.recordTypesStartupCategories!
                                .map<DropdownMenuItem<KeyValueRecordType>>((recordType) =>
                                    DropdownMenuItem<KeyValueRecordType>(
                                        value: recordType, child: Text(recordType.value)))
                                .toList(),
                          ),
                        ],
                      ))
                  : const SizedBox.shrink(),
              appState.startupCategorie == 3 ? const Divider() : const SizedBox.shrink(),
              appState.startupCategorie == 3
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12.0),
                      child: Row(
                        children: [
                          Padding(
                            padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                            child: const Icon(
                              Icons.feed,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              AppLocalizations.of(context)!.startupCategorieFeedSelection,
                              style: Theme.of(context).textTheme.titleMedium,
                              overflow: TextOverflow.visible,
                            ),
                          ),
                          DropdownButton<KeyValueRecordType>(
                            value: appState.startupFeedSelection,
                            elevation: 16,
                            underline: Container(
                              height: 2,
                            ),
                            alignment: AlignmentDirectional.centerEnd,
                            onChanged: (KeyValueRecordType? value) {
                              if (value != null) {
                                appState.startupFeedSelectionKey = int.parse(value.key);
                                appState.startupFeedSelection = value;
                                appState.storage
                                    .write(key: FluxNewsState.secureStorageStartupFeedSelectionKey, value: value.key);
                                appState.refreshView();
                              }
                            },
                            items: appState.recordTypesStartupFeeds!
                                .map<DropdownMenuItem<KeyValueRecordType>>((recordType) =>
                                    DropdownMenuItem<KeyValueRecordType>(
                                        value: recordType, child: Text(recordType.value)))
                                .toList(),
                          ),
                        ],
                      ))
                  : const SizedBox.shrink(),
              Padding(
                padding: EdgeInsets.only(top: 30),
                child: const Divider(),
              ),
              // this row contains the selection of brightness mode
              // there are the choices of light, dark and system
              Row(
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0, top: 10),
                    child: const Icon(
                      Icons.light_mode,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.brightnesMode,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                  DropdownButton<KeyValueRecordType>(
                    value: appState.brightnessModeSelection,
                    elevation: 16,
                    underline: Container(
                      height: 2,
                    ),
                    alignment: AlignmentDirectional.centerEnd,
                    onChanged: (KeyValueRecordType? value) {
                      if (value != null) {
                        themeState.brightnessMode = value.key;
                        appState.brightnessModeSelection = value;
                        appState.storage.write(key: FluxNewsState.secureStorageBrightnessModeKey, value: value.key);
                        appState.refreshView();
                        themeState.refreshView();
                      }
                    },
                    items: appState.recordTypesBrightnessMode!
                        .map<DropdownMenuItem<KeyValueRecordType>>((recordType) =>
                            DropdownMenuItem<KeyValueRecordType>(value: recordType, child: Text(recordType.value)))
                        .toList(),
                  ),
                ],
              ),
              const Divider(),
              // this row contains the selection if the black mode is turned on
              themeState.brightnessMode != FluxNewsState.brightnessModeLightString
                  ? Row(
                      children: [
                        Padding(
                          padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                          child: const Icon(
                            Icons.settings_display_rounded,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context)!.useBlackMode,
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.visible,
                          ),
                        ),
                        Switch.adaptive(
                          value: themeState.useBlackMode,
                          onChanged: (bool value) {
                            String stringValue = FluxNewsState.secureStorageFalseString;
                            if (value == true) {
                              stringValue = FluxNewsState.secureStorageTrueString;
                            }
                            themeState.useBlackMode = value;
                            appState.storage.write(key: FluxNewsState.secureStorageUseBlackModeKey, value: stringValue);
                            appState.refreshView();
                            themeState.refreshView();
                          },
                        ),
                      ],
                    )
                  : SizedBox.shrink(),
              themeState.brightnessMode != FluxNewsState.brightnessModeLightString
                  ? const Divider()
                  : SizedBox.shrink(),
              // this row contains the selection of the mark as read on scroll over
              // if it is turned on, a news is marked as read if it is scrolled over
              Row(
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                    child: const Icon(
                      Icons.check,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.markAsReadOnScrollover,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                  Switch.adaptive(
                    value: appState.markAsReadOnScrollOver,
                    onChanged: (bool value) {
                      String stringValue = FluxNewsState.secureStorageFalseString;
                      if (value == true) {
                        stringValue = FluxNewsState.secureStorageTrueString;
                      }
                      appState.markAsReadOnScrollOver = value;
                      appState.storage
                          .write(key: FluxNewsState.secureStorageMarkAsReadOnScrollOverKey, value: stringValue);
                      appState.refreshView();
                    },
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
                      Icons.refresh,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.syncOnStart,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                  Switch.adaptive(
                    value: appState.syncOnStart,
                    onChanged: (bool value) {
                      String stringValue = FluxNewsState.secureStorageFalseString;
                      if (value == true) {
                        stringValue = FluxNewsState.secureStorageTrueString;
                      }
                      appState.syncOnStart = value;
                      appState.storage.write(key: FluxNewsState.secureStorageSyncOnStartKey, value: stringValue);
                      appState.refreshView();
                    },
                  ),
                ],
              ),
              const Divider(),
              // this row contains the selection if only feeds and categories with new news are shown
              Row(
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                    child: const Icon(
                      Icons.numbers,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.showOnlyFeedCategoriesWithNewNews,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                  Switch.adaptive(
                    value: appState.showOnlyFeedCategoriesWithNewNews,
                    onChanged: (bool value) {
                      String stringValue = FluxNewsState.secureStorageFalseString;
                      if (value == true) {
                        stringValue = FluxNewsState.secureStorageTrueString;
                      }
                      appState.showOnlyFeedCategoriesWithNewNews = value;
                      appState.storage.write(
                          key: FluxNewsState.secureStorageShowOnlyFeedCategoriesWithNewNeKey, value: stringValue);
                      appState.refreshView();
                    },
                  ),
                ],
              ),
              const Divider(),
              // this row contains the selection if the app bar text is multiline
              // is turned on, the app bar text is showing the news count in the second line
              Row(
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                    child: const Icon(
                      Icons.numbers,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.multilineAppBarTextSetting,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                  Switch.adaptive(
                    value: appState.multilineAppBarText,
                    onChanged: (bool value) {
                      String stringValue = FluxNewsState.secureStorageFalseString;
                      if (value == true) {
                        stringValue = FluxNewsState.secureStorageTrueString;
                      }
                      appState.multilineAppBarText = value;
                      appState.storage
                          .write(key: FluxNewsState.secureStorageMultilineAppBarTextKey, value: stringValue);
                      appState.refreshView();
                    },
                  ),
                ],
              ),
              const Divider(),
              // this row contains the selection if the feed icon is shown
              Row(
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                    child: const Icon(
                      Icons.image,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.showFeedIconsTextSettings,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                  Switch.adaptive(
                    value: appState.showFeedIcons,
                    onChanged: (bool value) {
                      String stringValue = FluxNewsState.secureStorageFalseString;
                      if (value == true) {
                        stringValue = FluxNewsState.secureStorageTrueString;
                      }
                      appState.showFeedIcons = value;
                      appState.storage.write(key: FluxNewsState.secureStorageShowFeedIconsTextKey, value: stringValue);
                      appState.refreshView();
                    },
                  ),
                ],
              ),
              const Divider(),
              // this row contains the selection if the headline is shown on top of the news
              Row(
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                    child: const Icon(
                      Icons.vertical_align_top,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.showHeadlineOnTop,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                  Switch.adaptive(
                    value: appState.showHeadlineOnTop,
                    onChanged: (bool value) {
                      String stringValue = FluxNewsState.secureStorageFalseString;
                      if (value == true) {
                        stringValue = FluxNewsState.secureStorageTrueString;
                      }
                      appState.showHeadlineOnTop = value;
                      appState.storage.write(key: FluxNewsState.secureStorageShowHeadlineOnTopKey, value: stringValue);
                      appState.refreshView();
                    },
                  ),
                ],
              ),
              const Divider(),
              // this row contains the selection if the button to mark as read is turned on
              Row(
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                    child: const Icon(
                      Icons.check_circle_outline,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.floatingActionButton,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                  Switch.adaptive(
                    value: appState.floatingButtonVisible,
                    onChanged: (bool value) {
                      String stringValue = FluxNewsState.secureStorageFalseString;
                      if (value == true) {
                        stringValue = FluxNewsState.secureStorageTrueString;
                      }
                      appState.floatingButtonVisible = value;
                      appState.storage
                          .write(key: FluxNewsState.secureStorageFloatingButtonVisibleKey, value: stringValue);
                      appState.refreshView();
                    },
                  ),
                ],
              ),
            ])));
  }
}

class FluxNewsGeneralSettingsStatefulWrapper extends StatefulWidget {
  final Function onInit;
  final Widget child;
  const FluxNewsGeneralSettingsStatefulWrapper({super.key, required this.onInit, required this.child});
  @override
  FluxNewsBodyState createState() => FluxNewsBodyState();
}

// extend class to save actual scroll state of the list view
class FluxNewsBodyState extends State<FluxNewsGeneralSettingsStatefulWrapper> {
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
