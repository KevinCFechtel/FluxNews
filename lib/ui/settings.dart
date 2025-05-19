import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/flux_news_localizations.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/state_management/flux_news_counter_state.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/state_management/flux_news_theme_state.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'dart:io' show Platform;

import '../state_management/flux_news_state.dart';
import '../miniflux/miniflux_backend.dart';

class Settings extends StatelessWidget {
  const Settings({super.key});

  // define the selection lists for the settings of saved news and starred news
  static const List<int> amountOfSavedNewsList = <int>[50, 100, 200, 500, 1000, 2000, 5000, 10000];
  static const List<int> amountOfSavedStarredNewsList = <int>[50, 100, 200, 500, 1000, 2000, 5000, 10000];
  static const List<int> amountOfCharactersToTruncate = <int>[100, 200, 300, 400, 500, 600, 700, 800, 900, 1000];

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    FluxNewsThemeState themeState = context.read<FluxNewsThemeState>();

    return FluxNewsSettingsStatefulWrapper(onInit: () {
      initConfig(context);
    }, child: OrientationBuilder(builder: (context, orientation) {
      appState.orientation = orientation;
      return Scaffold(
        appBar: AppBar(
          forceMaterialTransparency: themeState.useBlackMode ? true : false,
          // set the title of the settings page to the localized settings string
          title: Text(AppLocalizations.of(context)!.settings, style: Theme.of(context).textTheme.titleLarge),
        ),
        // set the body of the settings page
        body: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(12),
            alignment: Alignment.center,
            // this is the main column of the settings page
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // the first row contains the headline of the settings for the miniflux server
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Text(AppLocalizations.of(context)!.minifluxSettings,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.normal,
                        )),
                  ],
                ),
                // this list tile contains the url of the miniflux server
                // it is clickable and opens a dialog to edit the url
                ListTile(
                  leading: const Icon(
                    Icons.link,
                  ),
                  title: Padding(
                    padding: Platform.isAndroid
                        ? const EdgeInsets.fromLTRB(15, 0, 0, 0)
                        : const EdgeInsets.fromLTRB(0, 0, 0, 0),
                    child: Text(
                      '${AppLocalizations.of(context)!.apiUrl}: ${appState.minifluxURL ?? ''}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  onTap: () {
                    _showURLEditDialog(context, appState);
                  },
                ),
                const Divider(),
                // this list tile contains the api key of the miniflux server
                // it is clickable and opens a dialog to edit the api key
                ListTile(
                  leading: const Icon(
                    Icons.api,
                  ),
                  title: Padding(
                    padding: Platform.isAndroid
                        ? const EdgeInsets.fromLTRB(15, 0, 0, 0)
                        : const EdgeInsets.fromLTRB(0, 0, 0, 0),
                    child: Text(
                      '${AppLocalizations.of(context)!.apiKey}: ${appState.minifluxAPIKey ?? ''}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  onTap: () {
                    _showApiKeyEditDialog(context, appState);
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(
                    Icons.numbers,
                  ),
                  title: Padding(
                    padding: Platform.isAndroid
                        ? const EdgeInsets.fromLTRB(15, 0, 0, 0)
                        : const EdgeInsets.fromLTRB(0, 0, 0, 0),
                    child: Text(
                      '${AppLocalizations.of(context)!.minifluxVersion}: ${appState.minifluxVersionString ?? ''}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                // it there is an error on the authentication of the miniflux server
                // there is shown a error message
                appState.errorOnMinifluxAuth
                    ? appState.minifluxAPIKey != null
                        ? Padding(
                            padding: const EdgeInsets.only(top: 10, bottom: 10),
                            child: Text(
                              AppLocalizations.of(context)!.authError,
                              style: const TextStyle(color: Colors.red, fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                          )
                        : const SizedBox.shrink()
                    : const SizedBox.shrink(),
                appState.insecureMinifluxURL
                    ? Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 10),
                        child: Text(
                          AppLocalizations.of(context)!.insecureMinifluxURL,
                          style: const TextStyle(color: Colors.red, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      )
                    : const SizedBox.shrink(),
                // this headline indicate the general settings section
                Padding(
                  padding: const EdgeInsets.only(top: 50.0, bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Text(AppLocalizations.of(context)!.generalSettings,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.normal,
                          )),
                    ],
                  ),
                ),
                // this row contains the selection of brightness mode
                // there are the choices of light, dark and system
                Row(
                  children: [
                    Padding(
                      padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
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
                        appState.storage
                            .write(key: FluxNewsState.secureStorageShowFeedIconsTextKey, value: stringValue);
                        appState.refreshView();
                      },
                    ),
                  ],
                ),
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
                          appState.storage
                              .write(key: FluxNewsState.secureStorageAmountOfSyncedNewsKey, value: value.key);
                          appState.refreshView();
                        }
                      },
                      items: appState.recordTypesAmountOfSyncedNews!
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
                ),
                const Divider(),
                // this row contains the selection if the horizontal scrolling is turned on
                Row(
                  children: [
                    Padding(
                      padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                      child: const Icon(
                        Icons.swap_horiz,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)!.scrollHorizontal,
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                    Switch.adaptive(
                      value: appState.scrollHorizontal,
                      onChanged: (bool value) {
                        String stringValue = FluxNewsState.secureStorageFalseString;
                        if (value == true) {
                          appState.activateSwipeGestures = false;
                          appState.storage.write(
                              key: FluxNewsState.secureStorageActivateSwipeGesturesKey,
                              value: FluxNewsState.secureStorageFalseString);
                          stringValue = FluxNewsState.secureStorageTrueString;
                        }
                        appState.scrollHorizontal = value;
                        appState.storage.write(key: FluxNewsState.secureStorageScrollHorizontalKey, value: stringValue);
                        appState.refreshView();
                      },
                    ),
                  ],
                ),
                const Divider(),
                // this row contains the selection if the horizontal scrolling is turned on
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
                const Divider(),
                // this row contains the selection if the horizontal scrolling is turned on
                Row(
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
                ),
                const Divider(),
                // this list tile contains feed settings
                // it is clickable and opens the feed settings
                ListTile(
                  leading: const Icon(
                    Icons.feed,
                  ),
                  title: Padding(
                    padding: Platform.isAndroid
                        ? const EdgeInsets.fromLTRB(15, 0, 0, 0)
                        : const EdgeInsets.fromLTRB(0, 0, 0, 0),
                    child: Text(
                      AppLocalizations.of(context)!.feedSettings,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  onTap: () {
                    // navigate to the search page
                    Navigator.pushNamed(context, FluxNewsState.feedSettingsRouteString);
                  },
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
                          appState.scrollHorizontal = false;
                          appState.storage.write(
                              key: FluxNewsState.secureStorageScrollHorizontalKey,
                              value: FluxNewsState.secureStorageFalseString);
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
                // this row contains the selection of left swipe action
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
                Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Text(AppLocalizations.of(context)!.truncateSettings,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.normal,
                          )),
                    ],
                  ),
                ),
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
                    ? RadioListTile<int>(
                        title: Text(AppLocalizations.of(context)!.truncateModeAll,
                            style: Theme.of(context).textTheme.titleMedium),
                        value: 0,
                        groupValue: appState.truncateMode,
                        onChanged: (int? value) {
                          if (value != null) {
                            appState.truncateMode = value;
                            appState.storage
                                .write(key: FluxNewsState.secureStorageTruncateModeKey, value: value.toString());
                            appState.refreshView();
                          }
                        },
                      )
                    : const SizedBox.shrink(),
                appState.activateTruncate
                    ? RadioListTile<int>(
                        title: Text(AppLocalizations.of(context)!.truncateModeScraper,
                            style: Theme.of(context).textTheme.titleMedium),
                        value: 1,
                        groupValue: appState.truncateMode,
                        onChanged: (int? value) {
                          if (value != null) {
                            appState.truncateMode = value;
                            appState.storage
                                .write(key: FluxNewsState.secureStorageTruncateModeKey, value: value.toString());
                            appState.refreshView();
                          }
                        },
                      )
                    : const SizedBox.shrink(),
                appState.activateTruncate
                    ? RadioListTile<int>(
                        title: Text(AppLocalizations.of(context)!.truncateModeManual,
                            style: Theme.of(context).textTheme.titleMedium),
                        value: 2,
                        groupValue: appState.truncateMode,
                        onChanged: (int? value) {
                          if (value != null) {
                            appState.truncateMode = value;
                            appState.storage
                                .write(key: FluxNewsState.secureStorageTruncateModeKey, value: value.toString());
                            appState.refreshView();
                          }
                        },
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

                Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Text(AppLocalizations.of(context)!.debugSettings,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.normal,
                          )),
                    ],
                  ),
                ),
                // this row contains the selection if the debug mode is turned on
                Row(
                  children: [
                    Padding(
                      padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                      child: const Icon(
                        Icons.developer_mode,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)!.debugModeTextSettings,
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                    Switch.adaptive(
                      value: appState.debugMode,
                      onChanged: (bool value) {
                        String stringValue = FluxNewsState.secureStorageFalseString;
                        if (value == true) {
                          stringValue = FluxNewsState.secureStorageTrueString;
                        }
                        appState.debugMode = value;
                        appState.storage.write(key: FluxNewsState.secureStorageDebugModeKey, value: stringValue);
                        appState.refreshView();
                      },
                    ),
                  ],
                ),
                const Divider(),
                // this list tile contains the ability to export the collected logs
                ListTile(
                  leading: const Icon(
                    Icons.import_export,
                  ),
                  title: Padding(
                    padding: Platform.isAndroid
                        ? const EdgeInsets.fromLTRB(15, 0, 0, 0)
                        : const EdgeInsets.fromLTRB(0, 0, 0, 0),
                    child: Text(
                      AppLocalizations.of(context)!.exportLogs,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  onTap: () {
                    if (Platform.isAndroid || Platform.isIOS) {
                      FlutterLogs.exportLogs(exportType: ExportType.ALL);
                    }
                  },
                ),
                const Divider(),
                // this list tile delete the local news database
                ListTile(
                  leading: const Icon(
                    Icons.delete_forever,
                    color: Colors.red,
                  ),
                  title: Padding(
                    padding: Platform.isAndroid
                        ? const EdgeInsets.fromLTRB(15, 0, 0, 0)
                        : const EdgeInsets.fromLTRB(0, 0, 0, 0),
                    child: Text(
                      AppLocalizations.of(context)!.deleteLocalCache,
                      style: Theme.of(context).textTheme.titleMedium!.copyWith(color: Colors.red),
                    ),
                  ),
                  onTap: () {
                    _showDeleteLocalCacheDialog(context, appState);
                  },
                ),
                const Divider(),
                // this list tile contains the about dialog
                AboutListTile(
                  icon: Padding(
                    padding: Platform.isAndroid
                        ? const EdgeInsets.fromLTRB(0, 0, 15, 0)
                        : const EdgeInsets.fromLTRB(0, 0, 0, 0),
                    child: const Icon(Icons.info),
                  ),
                  applicationIcon: const Icon(
                    FontAwesomeIcons.bookOpen,
                  ),
                  applicationName: FluxNewsState.applicationName,
                  applicationVersion: FluxNewsState.applicationVersion,
                  applicationLegalese: FluxNewsState.applicationLegalese,
                  aboutBoxChildren: [
                    const SizedBox(height: 24),
                    RichText(
                      text: TextSpan(
                        style: Theme.of(context).textTheme.bodyMedium,
                        children: <TextSpan>[
                          TextSpan(text: AppLocalizations.of(context)!.descriptionMinifluxApp),
                          const TextSpan(text: '${FluxNewsState.miniFluxProjectUrl}\n'),
                          TextSpan(text: AppLocalizations.of(context)!.descriptionMoreInformation),
                          const TextSpan(text: FluxNewsState.applicationProjectUrl),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }));
  }

  // initConfig reads the config values from the persistent storage and sets the state
  // accordingly.
  // It also initializes the database connection.
  Future<void> initConfig(BuildContext context) async {
    FluxNewsState appState = context.read<FluxNewsState>();
    await appState.readConfigValues();
    if (context.mounted) {
      appState.readConfig(context);
      appState.readThemeConfigValues(context);
    }
    appState.db = await appState.initializeDB();
    appState.refreshView();
  }

  // this method shows a dialog to enter the miniflux url
  // the url is saved in the secure storage
  // the url is matched against a regular expression for a valid https url
  // if the api key is set, the connection is tested
  Future _showURLEditDialog(BuildContext context, FluxNewsState appState) {
    final formKey = GlobalKey<FormState>();
    bool errorInForm = false;
    TextEditingController controller = TextEditingController();
    if (appState.minifluxURL != null) {
      controller.text = appState.minifluxURL!;
    }
    return showDialog(
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(builder: (context, setState) {
            return AlertDialog.adaptive(
              title: Text(AppLocalizations.of(context)!.titleURL),
              content: Platform.isIOS
                  ? Wrap(children: [
                      Padding(
                          padding: const EdgeInsets.only(top: 10, bottom: 5),
                          child: Text(AppLocalizations.of(context)!.enterURL)),
                      CupertinoTextField(
                        controller: controller,
                      ),
                      errorInForm
                          ? Text(
                              AppLocalizations.of(context)!.enterValidURL,
                              style: const TextStyle(color: Colors.red),
                            )
                          : const SizedBox.shrink()
                    ])
                  : Wrap(children: [
                      Text(AppLocalizations.of(context)!.enterURL),
                      Form(
                        key: formKey,
                        child: TextFormField(
                          controller: controller,
                          decoration: const InputDecoration(errorMaxLines: 2),
                          validator: (value) {
                            value ??= '';
                            RegExp regex = RegExp(FluxNewsState.urlValidationRegex);
                            if (!regex.hasMatch(value)) {
                              return AppLocalizations.of(context)!.enterValidURL;
                            } else {
                              return null;
                            }
                          },
                        ),
                      ),
                    ]),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(context, FluxNewsState.cancelContextString),
                  child: Text(AppLocalizations.of(context)!.cancel),
                ),
                TextButton(
                  onPressed: () async {
                    String? newText;
                    if (Platform.isIOS) {
                      RegExp regex = RegExp(FluxNewsState.urlValidationRegex);
                      if (!regex.hasMatch(controller.text)) {
                        setState(() {
                          errorInForm = true;
                        });
                      } else {
                        newText = controller.text;
                        if (!newText.endsWith('/v1/')) {
                          if (!newText.endsWith('/v1')) {
                            if (newText.endsWith('/')) {
                              newText = newText + FluxNewsState.apiVersionPath;
                            } else {
                              newText = "$newText/${FluxNewsState.apiVersionPath}";
                            }
                          } else {
                            newText = "$newText/";
                          }
                        }
                        if (appState.minifluxAPIKey != null && appState.minifluxAPIKey != '') {
                          bool authCheck = await checkMinifluxCredentials(newText, appState.minifluxAPIKey!, appState)
                              .onError((error, stackTrace) => false);

                          appState.errorOnMinifluxAuth = !authCheck;
                          appState.insecureMinifluxURL = !newText.toLowerCase().startsWith('https');
                          appState.refreshView();
                        }
                        appState.storage.write(key: FluxNewsState.secureStorageMinifluxURLKey, value: newText);
                        appState.minifluxURL = newText;
                        if (context.mounted) {
                          Navigator.pop(context);
                          appState.refreshView();
                        }
                      }
                    } else {
                      if (formKey.currentState!.validate()) {
                        if (controller.text != '') {
                          newText = controller.text;
                          if (!newText.endsWith('/v1/')) {
                            if (!newText.endsWith('/v1')) {
                              if (newText.endsWith('/')) {
                                newText = newText + FluxNewsState.apiVersionPath;
                              } else {
                                newText = "$newText/${FluxNewsState.apiVersionPath}";
                              }
                            } else {
                              newText = "$newText/";
                            }
                          }
                        }
                        if (appState.minifluxAPIKey != null && appState.minifluxAPIKey != '' && newText != null) {
                          bool authCheck = await checkMinifluxCredentials(newText, appState.minifluxAPIKey!, appState)
                              .onError((error, stackTrace) => false);

                          appState.errorOnMinifluxAuth = !authCheck;
                          appState.insecureMinifluxURL = !newText.toLowerCase().startsWith('https');
                          appState.refreshView();
                        }
                        appState.storage.write(key: FluxNewsState.secureStorageMinifluxURLKey, value: newText);
                        appState.minifluxURL = newText;
                        if (context.mounted) {
                          Navigator.pop(context);
                          appState.refreshView();
                        }
                      }
                    }
                  },
                  child: Text(AppLocalizations.of(context)!.save),
                ),
              ],
            );
          });
        });
  }

  // this method shows a dialog to enter the miniflux api key
  // the api key is saved in the secure storage
  // if the url is set, the connection is tested
  Future _showApiKeyEditDialog(BuildContext context, FluxNewsState appState) {
    TextEditingController controller = TextEditingController();
    if (appState.minifluxAPIKey != null) {
      controller.text = appState.minifluxAPIKey!;
    }
    return showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog.adaptive(
            title: Text(AppLocalizations.of(context)!.titleAPIKey),
            content: Platform.isIOS
                ? Wrap(
                    children: [
                      Padding(
                          padding: const EdgeInsets.only(top: 10, bottom: 5),
                          child: Text(AppLocalizations.of(context)!.enterAPIKey)),
                      CupertinoTextField(
                        controller: controller,
                      ),
                    ],
                  )
                : Wrap(children: [
                    Text(AppLocalizations.of(context)!.enterAPIKey),
                    TextField(
                      controller: controller,
                    )
                  ]),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, FluxNewsState.cancelContextString),
                child: Text(AppLocalizations.of(context)!.cancel),
              ),
              TextButton(
                onPressed: () async {
                  String? newText;
                  if (controller.text != '') {
                    newText = controller.text;
                  }
                  if (appState.minifluxURL != null && appState.minifluxURL != '' && newText != null) {
                    bool authCheck = await checkMinifluxCredentials(appState.minifluxURL!, newText, appState)
                        .onError((error, stackTrace) => false);
                    appState.errorOnMinifluxAuth = !authCheck;
                    appState.insecureMinifluxURL = !appState.minifluxURL!.toLowerCase().startsWith('https');
                    appState.refreshView();
                  }

                  appState.storage.write(key: FluxNewsState.secureStorageMinifluxAPIKey, value: newText);
                  appState.minifluxAPIKey = newText;
                  if (context.mounted) {
                    Navigator.pop(context);
                    appState.refreshView();
                  }
                },
                child: Text(AppLocalizations.of(context)!.save),
              ),
            ],
          );
        });
  }

  // this method shows a dialog to enter the miniflux api key
  // the api key is saved in the secure storage
  // if the url is set, the connection is tested
  Future _showDeleteLocalCacheDialog(BuildContext context, FluxNewsState appState) {
    TextEditingController controller = TextEditingController();
    if (appState.minifluxAPIKey != null) {
      controller.text = appState.minifluxAPIKey!;
    }
    return showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog.adaptive(
            title: Text(AppLocalizations.of(context)!.deleteLocalCacheDialogTitle),
            content: Wrap(children: [
              Text(AppLocalizations.of(context)!.deleteLocalCacheDialogContent),
            ]),
            actions: Platform.isIOS
                ? <CupertinoDialogAction>[
                    CupertinoDialogAction(
                      isDefaultAction: true,
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: Text(AppLocalizations.of(context)!.cancel),
                    ),
                    CupertinoDialogAction(
                      /// This parameter indicates the action would perform
                      /// a destructive action such as deletion, and turns
                      /// the action's text color to red.
                      isDestructiveAction: true,
                      onPressed: () {
                        deleteLocalNewsCache(appState, context);
                        appState.newsList = Future<List<News>>.value([]);
                        appState.categoryList = Future<Categories>.value(Categories(categories: []));
                        context.read<FluxNewsCounterState>().allNewsCount = 0;
                        context.read<FluxNewsCounterState>().appBarNewsCount = 0;
                        context.read<FluxNewsCounterState>().starredCount = 0;
                        context.read<FluxNewsCounterState>().refreshView();
                        appState.refreshView();
                        Navigator.pop(context);
                      },
                      child: Text(AppLocalizations.of(context)!.ok),
                    ),
                  ]
                : <Widget>[
                    TextButton(
                      onPressed: () => Navigator.pop(context, FluxNewsState.cancelContextString),
                      child: Text(AppLocalizations.of(context)!.cancel),
                    ),
                    TextButton(
                      onPressed: () async {
                        deleteLocalNewsCache(appState, context);
                        appState.newsList = Future<List<News>>.value([]);
                        appState.categoryList = Future<Categories>.value(Categories(categories: []));
                        context.read<FluxNewsCounterState>().allNewsCount = 0;
                        context.read<FluxNewsCounterState>().appBarNewsCount = 0;
                        context.read<FluxNewsCounterState>().starredCount = 0;
                        context.read<FluxNewsCounterState>().refreshView();
                        appState.refreshView();
                        Navigator.pop(context);
                      },
                      child: Text(
                        AppLocalizations.of(context)!.ok,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
          );
        });
  }
}

class FluxNewsSettingsStatefulWrapper extends StatefulWidget {
  final Function onInit;
  final Widget child;
  const FluxNewsSettingsStatefulWrapper({super.key, required this.onInit, required this.child});
  @override
  FluxNewsBodyState createState() => FluxNewsBodyState();
}

// extend class to save actual scroll state of the list view
class FluxNewsBodyState extends State<FluxNewsSettingsStatefulWrapper> {
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
