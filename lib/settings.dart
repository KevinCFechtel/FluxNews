import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gen/gen_l10n/flux_news_localizations.dart';
import 'package:http/http.dart' as http;

import 'flux_news_state.dart';
import 'miniflux_backend.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  @override
  void initState() {
    super.initState();
    initConfig();
  }

  // initConfig reads the config values from the persistant storage and sets the state
  // accordingly.
  // It also initializes the database connection.
  Future<void> initConfig() async {
    FluxNewsState appState = context.read<FluxNewsState>();
    await appState.readConfigValues(context);
    if (context.mounted) {
      appState.readConfig(context);
    }
    appState.db = await appState.initializeDB();
    appState.refreshView();
  }

  // define the selection lists for the settings of saved news and starred news
  static const List<int> amountOfSavedNewsList = <int>[
    50,
    100,
    200,
    500,
    1000,
    2000
  ];
  static const List<int> amountOfSavedStarredNewsList = <int>[
    50,
    100,
    200,
    500,
    1000,
    2000
  ];

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    // init the scaffold of the settings page
    return Scaffold(
      appBar: AppBar(
        // set the title of the settings page to the localized settings string
        title: Text(AppLocalizations.of(context)!.settings,
            style: Theme.of(context).textTheme.titleLarge),
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
                title: Text(
                  '${AppLocalizations.of(context)!.apiUrl}: ${appState.minifluxURL ?? ''}',
                  style: Theme.of(context).textTheme.titleMedium,
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
                title: Text(
                  '${AppLocalizations.of(context)!.apiKey}: ${appState.minifluxAPIKey ?? ''}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                onTap: () {
                  _showApiKeyEditDialog(context, appState);
                },
              ),
              // it there is an error on the authentication of the miniflux server
              // there is shown a error message
              appState.errorOnMicrofluxAuth
                  ? appState.minifluxAPIKey != null
                      ? Padding(
                          padding: const EdgeInsets.only(top: 10, bottom: 10),
                          child: Text(
                            AppLocalizations.of(context)!.authError,
                            style: const TextStyle(
                                color: Colors.red,
                                fontSize: 20,
                                fontWeight: FontWeight.bold),
                          ),
                        )
                      : const SizedBox.shrink()
                  : const SizedBox.shrink(),
              // this headline inidcate the general settings section
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
              // there are the chovices of light, dark and system
              Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 17.0),
                    child: Icon(
                      Icons.light_mode,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 30.0),
                    child: Text(AppLocalizations.of(context)!.brightnesMode,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  const Spacer(),
                  DropdownButton<KeyValueRecordType>(
                    value: appState.brightnessModeSelection,
                    elevation: 16,
                    underline: Container(
                      height: 2,
                    ),
                    onChanged: (KeyValueRecordType? value) {
                      if (value != null) {
                        appState.brightnessMode = value.key;
                        appState.brightnessModeSelection = value;
                        appState.storage.write(
                            key: FluxNewsState.secureStorageBrightnessModeKey,
                            value: value.key);
                        appState.refreshView();
                      }
                    },
                    items: appState.recordTypesBrightnessMode!
                        .map<DropdownMenuItem<KeyValueRecordType>>(
                            (recordType) =>
                                DropdownMenuItem<KeyValueRecordType>(
                                    value: recordType,
                                    child: Text(recordType.value)))
                        .toList(),
                  ),
                ],
              ),
              const Divider(),
              // this row contains the selection of the mark as read on scroll over
              // if it is turned on, a news is marked as read if it is scrolled over
              Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 17.0),
                    child: Icon(
                      Icons.remove_red_eye,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 30.0),
                    child: Text(
                      AppLocalizations.of(context)!.markAsReadOnScrollover,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const Spacer(),
                  Switch.adaptive(
                    value: appState.markAsReadOnScrollOver,
                    onChanged: (bool value) {
                      String stringValue =
                          FluxNewsState.secureStorageFalseString;
                      if (value == true) {
                        stringValue = FluxNewsState.secureStorageTrueString;
                      }
                      appState.markAsReadOnScrollOver = value;
                      appState.storage.write(
                          key: FluxNewsState
                              .secureStorageMarkAsReadOnScrollOverKey,
                          value: stringValue);
                      appState.refreshView();
                    },
                  ),
                ],
              ),
              const Divider(),
              // this row contains the selection of the sync on start
              Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 17.0),
                    child: Icon(
                      Icons.refresh,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 30.0),
                    child: Text(
                      AppLocalizations.of(context)!.syncOnStart,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const Spacer(),
                  Switch.adaptive(
                    value: appState.syncOnStart,
                    onChanged: (bool value) {
                      String stringValue =
                          FluxNewsState.secureStorageFalseString;
                      if (value == true) {
                        stringValue = FluxNewsState.secureStorageTrueString;
                      }
                      appState.syncOnStart = value;
                      appState.storage.write(
                          key: FluxNewsState.secureStorageSyncOnStartKey,
                          value: stringValue);
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
                  const Padding(
                    padding: EdgeInsets.only(left: 17.0),
                    child: Icon(
                      Icons.numbers,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 30.0),
                    child: Text(
                      AppLocalizations.of(context)!.multilineAppBarTextSetting,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const Spacer(),
                  Switch.adaptive(
                    value: appState.multilineAppBarText,
                    onChanged: (bool value) {
                      String stringValue =
                          FluxNewsState.secureStorageFalseString;
                      if (value == true) {
                        stringValue = FluxNewsState.secureStorageTrueString;
                      }
                      appState.multilineAppBarText = value;
                      appState.storage.write(
                          key:
                              FluxNewsState.secureStorageMultilineAppBarTextKey,
                          value: stringValue);
                      appState.refreshView();
                    },
                  ),
                ],
              ),
              const Divider(),
              // this row contains the selection if the feed icon is shown
              Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 17.0),
                    child: Icon(
                      Icons.image,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 30.0),
                    child: Text(
                      AppLocalizations.of(context)!.showFeedIconsTextSettings,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const Spacer(),
                  Switch.adaptive(
                    value: appState.showFeedIcons,
                    onChanged: (bool value) {
                      String stringValue =
                          FluxNewsState.secureStorageFalseString;
                      if (value == true) {
                        stringValue = FluxNewsState.secureStorageTrueString;
                      }
                      appState.showFeedIcons = value;
                      appState.storage.write(
                          key: FluxNewsState.secureStorageShowFeedIconsTextKey,
                          value: stringValue);
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
                  const Padding(
                    padding: EdgeInsets.only(left: 17.0),
                    child: Icon(
                      Icons.save_alt,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 30.0),
                    child: Text(AppLocalizations.of(context)!.amountSaved,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  const Spacer(),
                  DropdownButton<int>(
                    value: appState.amountOfSavedNews,
                    elevation: 16,
                    underline: Container(
                      height: 2,
                    ),
                    onChanged: (int? value) {
                      if (value != null) {
                        appState.amountOfSavedNews = value;
                        appState.storage.write(
                            key:
                                FluxNewsState.secureStorageAmountOfSavedNewsKey,
                            value: value.toString());
                        appState.refreshView();
                      }
                    },
                    items: amountOfSavedNewsList
                        .map<DropdownMenuItem<int>>((int value) {
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
                  const Padding(
                    padding: EdgeInsets.only(left: 17.0),
                    child: Icon(
                      Icons.star,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 30.0),
                    child: Text(
                        AppLocalizations.of(context)!.amountSavedStarred,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  const Spacer(),
                  DropdownButton<int>(
                    value: appState.amountOfSavedStarredNews,
                    elevation: 16,
                    underline: Container(
                      height: 2,
                    ),
                    onChanged: (int? value) {
                      if (value != null) {
                        appState.amountOfSavedStarredNews = value;
                        appState.storage.write(
                            key: FluxNewsState
                                .secureStorageAmountOfSavedStarredNewsKey,
                            value: value.toString());
                        appState.refreshView();
                      }
                    },
                    items: amountOfSavedStarredNewsList
                        .map<DropdownMenuItem<int>>((int value) {
                      return DropdownMenuItem<int>(
                        value: value,
                        child: Text(value.toString()),
                      );
                    }).toList(),
                  ),
                ],
              ),
              const Divider(),
              // this list tile contains the about dialog
              AboutListTile(
                icon: const Icon(Icons.info),
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
                        TextSpan(
                            text: AppLocalizations.of(context)!
                                .descriptionMinifluxApp),
                        const TextSpan(
                            text: '${FluxNewsState.miniFluxProjectUrl}\n'),
                        TextSpan(
                            text: AppLocalizations.of(context)!
                                .descriptionMoreInformation),
                        const TextSpan(
                            text: FluxNewsState.applicationProjectUrl),
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
  }

  // this method shows a dialog to enter the miniflux url
  // the url is saved in the secure storage
  // the url is matched against a regular expression for a valid https url
  // if the api key is set, the connection is tested
  Future _showURLEditDialog(BuildContext context, FluxNewsState appState) {
    final formKey = GlobalKey<FormState>();
    TextEditingController controller = TextEditingController();
    if (appState.minifluxURL != null) {
      controller.text = appState.minifluxURL!;
    }
    return showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(AppLocalizations.of(context)!.enterURL),
            content: Form(
              key: formKey,
              child: TextFormField(
                controller: controller,
                decoration: const InputDecoration(errorMaxLines: 2),
                validator: (value) {
                  value ??= '';
                  RegExp regex = RegExp(
                      r'https:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)\/v1\/');
                  if (!regex.hasMatch(value)) {
                    return AppLocalizations.of(context)!.enterValidURL;
                  } else {
                    return null;
                  }
                },
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, FluxNewsState.cancelContextString),
                child: Text(AppLocalizations.of(context)!.cancel),
              ),
              TextButton(
                onPressed: () async {
                  if (formKey.currentState!.validate()) {
                    String? newText;
                    if (controller.text != '') {
                      newText = controller.text;
                    }
                    if (appState.minifluxAPIKey != null &&
                        appState.minifluxAPIKey != '' &&
                        newText != null) {
                      bool authCheck = await checkMinifluxCredentials(
                              http.Client(), newText, appState.minifluxAPIKey!)
                          .onError((error, stackTrace) => false);

                      appState.errorOnMicrofluxAuth = !authCheck;
                      appState.refreshView();
                    }
                    appState.storage.write(
                        key: FluxNewsState.secureStorageMinifluxURLKey,
                        value: newText);
                    appState.minifluxURL = newText;
                    if (mounted) {
                      Navigator.pop(context);
                      appState.refreshView();
                    }
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
  Future _showApiKeyEditDialog(BuildContext context, FluxNewsState appState) {
    TextEditingController controller = TextEditingController();
    if (appState.minifluxAPIKey != null) {
      controller.text = appState.minifluxAPIKey!;
    }
    return showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(AppLocalizations.of(context)!.enterAPIKey),
            content: TextField(
              controller: controller,
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, FluxNewsState.cancelContextString),
                child: Text(AppLocalizations.of(context)!.cancel),
              ),
              TextButton(
                onPressed: () async {
                  String? newText;
                  if (controller.text != '') {
                    newText = controller.text;
                  }
                  if (appState.minifluxURL != null &&
                      appState.minifluxURL != '' &&
                      newText != null) {
                    bool authCheck = await checkMinifluxCredentials(
                            http.Client(), appState.minifluxURL!, newText)
                        .onError((error, stackTrace) => false);
                    appState.errorOnMicrofluxAuth = !authCheck;
                    appState.refreshView();
                  }

                  appState.storage.write(
                      key: FluxNewsState.secureStorageMinifluxAPIKey,
                      value: newText);
                  appState.minifluxAPIKey = newText;
                  if (mounted) {
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
}
