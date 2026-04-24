import 'dart:io';
import 'dart:convert';

import 'package:archive/archive_io.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flux_news/functions/flux_news_audio_handler.dart';
import 'package:flux_news/functions/flux_news_carplay_service.dart';
import 'package:flux_news/ui/log_viewer.dart';
import 'package:flux_news/functions/logging.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/state_management/flux_news_counter_state.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flux_news/ui/settings/download_storage_settings.dart';

import '../state_management/flux_news_state.dart';
import '../miniflux/miniflux_backend.dart';

class Settings extends StatelessWidget {
  const Settings({super.key});

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();

    return FluxNewsSettingsStatefulWrapper(onInit: () {
      initConfig(context);
    }, child: OrientationBuilder(builder: (context, orientation) {
      appState.orientation = orientation;
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          scrolledUnderElevation: 0,
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
                      '${AppLocalizations.of(context)!.apiKey}: ${appState.minifluxAPIKey != null ? '******************' : ''}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  onTap: () {
                    _showApiKeyEditDialog(context, appState);
                  },
                ),
                const Divider(),
                // this list tile contains sync settings
                // it is clickable and opens the sync settings
                ListTile(
                  leading: const Icon(
                    Icons.code,
                  ),
                  title: Padding(
                    padding: Platform.isAndroid
                        ? const EdgeInsets.fromLTRB(15, 0, 0, 0)
                        : const EdgeInsets.fromLTRB(0, 0, 0, 0),
                    child: Text(
                      AppLocalizations.of(context)!.headerSettings,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  onTap: () {
                    // navigate to the search page
                    Navigator.pushNamed(context, FluxNewsState.headerSettingsRouteString);
                  },
                  trailing: const Icon(
                    Icons.arrow_right,
                  ),
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
                const Divider(),
                // this list tile contains general settings
                // it is clickable and opens the general settings
                ListTile(
                  leading: const Icon(
                    Icons.settings_applications,
                  ),
                  title: Padding(
                    padding: Platform.isAndroid
                        ? const EdgeInsets.fromLTRB(15, 0, 0, 0)
                        : const EdgeInsets.fromLTRB(0, 0, 0, 0),
                    child: Text(
                      AppLocalizations.of(context)!.generalSettings,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  onTap: () {
                    // navigate to the search page
                    Navigator.pushNamed(context, FluxNewsState.generalSettingsRouteString);
                  },
                  trailing: const Icon(
                    Icons.arrow_right,
                  ),
                ),
                const Divider(),

                // this list tile contains sync settings
                // it is clickable and opens the sync settings
                ListTile(
                  leading: const Icon(
                    Icons.sync,
                  ),
                  title: Padding(
                    padding: Platform.isAndroid
                        ? const EdgeInsets.fromLTRB(15, 0, 0, 0)
                        : const EdgeInsets.fromLTRB(0, 0, 0, 0),
                    child: Text(
                      AppLocalizations.of(context)!.syncSettings,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  onTap: () {
                    // navigate to the search page
                    Navigator.pushNamed(context, FluxNewsState.syncSettingsRouteString);
                  },
                  trailing: const Icon(
                    Icons.arrow_right,
                  ),
                ),
                const Divider(),
                // this list tile contains news item settings
                // it is clickable and opens the news item settings
                ListTile(
                  leading: const Icon(
                    Icons.article,
                  ),
                  title: Padding(
                    padding: Platform.isAndroid
                        ? const EdgeInsets.fromLTRB(15, 0, 0, 0)
                        : const EdgeInsets.fromLTRB(0, 0, 0, 0),
                    child: Text(
                      AppLocalizations.of(context)!.newsItemSettings,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  onTap: () {
                    // navigate to the search page
                    Navigator.pushNamed(context, FluxNewsState.newsItemSettingsRouteString);
                  },
                  trailing: const Icon(
                    Icons.arrow_right,
                  ),
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
                  trailing: const Icon(
                    Icons.arrow_right,
                  ),
                ),
                const Divider(),

                // this list tile contains truncate settings
                // it is clickable and opens the truncate settings
                ListTile(
                  leading: const Icon(
                    Icons.cut_outlined,
                  ),
                  title: Padding(
                    padding: Platform.isAndroid
                        ? const EdgeInsets.fromLTRB(15, 0, 0, 0)
                        : const EdgeInsets.fromLTRB(0, 0, 0, 0),
                    child: Text(
                      AppLocalizations.of(context)!.truncateMode,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  onTap: () {
                    // navigate to the search page
                    Navigator.pushNamed(context, FluxNewsState.truncateSettingsRouteString);
                  },
                  trailing: const Icon(
                    Icons.arrow_right,
                  ),
                ),

                const Divider(),
                ListTile(
                  leading: const Icon(
                    Icons.storage_rounded,
                  ),
                  title: Padding(
                    padding: Platform.isAndroid
                        ? const EdgeInsets.fromLTRB(15, 0, 0, 0)
                        : const EdgeInsets.fromLTRB(0, 0, 0, 0),
                    child: Text(
                      AppLocalizations.of(context)!.downloadedData,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  subtitle: Padding(
                    padding: Platform.isAndroid
                        ? const EdgeInsets.fromLTRB(15, 0, 0, 0)
                        : const EdgeInsets.fromLTRB(0, 0, 0, 0),
                    child: Text(
                      AppLocalizations.of(context)!.downloadsManagerClearAll,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => const DownloadStorageSettings(),
                      ),
                    );
                  },
                  trailing: const Icon(
                    Icons.arrow_right,
                  ),
                ),

                const Divider(),
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
                        if (Platform.isIOS) {
                          FluxNewsCarPlayService.setDebugMode(value);
                        }
                        FluxNewsAudioHandler.setDebugMode(value);
                        appState.refreshView();
                      },
                    ),
                  ],
                ),
                const Divider(),
                // Log viewer
                ListTile(
                  leading: const Icon(Icons.list_alt),
                  title: Padding(
                    padding: Platform.isAndroid
                        ? const EdgeInsets.fromLTRB(15, 0, 0, 0)
                        : const EdgeInsets.fromLTRB(0, 0, 0, 0),
                    child: Text(
                      AppLocalizations.of(context)!.showLogs,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const LogViewerScreen(),
                      ),
                    );
                  },
                  trailing: const Icon(Icons.arrow_right),
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
                ListTile(
                  leading: const Icon(
                    Icons.backup,
                  ),
                  title: Padding(
                    padding: Platform.isAndroid
                        ? const EdgeInsets.fromLTRB(15, 0, 0, 0)
                        : const EdgeInsets.fromLTRB(0, 0, 0, 0),
                    child: Text(
                      AppLocalizations.of(context)!.backupSettings,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  subtitle: Padding(
                    padding: Platform.isAndroid
                        ? const EdgeInsets.fromLTRB(15, 0, 0, 0)
                        : const EdgeInsets.fromLTRB(0, 0, 0, 0),
                    child: Text(
                      AppLocalizations.of(context)!.backupSettingsDescription,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  onTap: () {
                    exportSettingsBackup(context, appState);
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
                  applicationIcon: const FaIcon(
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
    appState.recordTypesStartupCategories = <KeyValueRecordType>[];
    appState.recordTypesStartupFeeds = <KeyValueRecordType>[];
    await appState.readConfigValues();
    if (context.mounted) {
      appState.readConfig(context);
      appState.readThemeConfigValues(context);
    }
    appState.db = await appState.initializeDB();
    Categories? actualCategoryList;
    if (context.mounted) {
      actualCategoryList = await queryCategoriesFromDB(appState, context);
    }
    if (actualCategoryList != null) {
      for (Category category in actualCategoryList.categories) {
        appState.recordTypesStartupCategories!.add(
          KeyValueRecordType(key: category.categoryID.toString(), value: category.title),
        );
        if (category.categoryID == appState.startupCategorieSelectionKey) {
          appState.startupCategorieSelection =
              KeyValueRecordType(key: category.categoryID.toString(), value: category.title);
        }
      }

      for (Category category in actualCategoryList.categories) {
        for (Feed feed in category.feeds) {
          appState.recordTypesStartupFeeds!.add(
            KeyValueRecordType(key: feed.feedID.toString(), value: feed.title),
          );
          if (feed.feedID == appState.startupFeedSelectionKey) {
            appState.startupFeedSelection = KeyValueRecordType(key: feed.feedID.toString(), value: feed.title);
          }
        }
      }
    }
    appState.refreshView();
  }

  Future<void> exportSettingsBackup(BuildContext context, FluxNewsState appState) async {
    try {
      appState.db ??= await appState.initializeDB();

      final storageSettings = await appState.storage.readAll();
      final feedSettings = <Map<String, Object?>>[];
      if (appState.db != null) {
        final feeds = await appState.db!.rawQuery('''SELECT feedID,
                                                            title,
                                                            site_url,
                                                            iconMimeType,
                                                            iconID,
                                                            newsCount,
                                                            crawler,
                                                            manualTruncate,
                                                            preferParagraph,
                                                            preferAttachmentImage,
                                                            manualAdaptLightModeToIcon,
                                                            manualAdaptDarkModeToIcon,
                                                            openMinifluxEntry,
                                                            expandedWithFulltext,
                                                            expandedFulltextLimit,
                                                            categoryID
                                                       FROM feeds
                                                   ORDER BY UPPER(title) ASC''');
        for (final feed in feeds) {
          feedSettings.add(Map<String, Object?>.from(feed));
        }
      }

      final backupData = {
        'backupType': 'flux_news_settings',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'appVersion': FluxNewsState.applicationVersion,
        'settings': storageSettings,
        'feedSettings': feedSettings,
      };

      final backupJson = const JsonEncoder.withIndent('  ').convert(backupData);
      Directory? exportDirectory;
      if (Platform.isIOS) {
        exportDirectory = await getApplicationDocumentsDirectory();
      } else {
        exportDirectory = await getExternalStorageDirectory();
      }

      if (exportDirectory == null) {
        logThis('fetchNews', 'Error export directory for the backup could not be determined', LogLevel.ERROR);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.backupError)),
          );
        }
        return;
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final jsonFile = File('${exportDirectory.path}/flux_news_settings_backup_$timestamp.json');
      await jsonFile.writeAsString(backupJson, flush: true);

      final zipFilePath = '${exportDirectory.path}/flux_news_settings_backup_$timestamp.zip';
      final zipEncoder = ZipFileEncoder();
      zipEncoder.create(zipFilePath);
      await zipEncoder.addFile(jsonFile);
      zipEncoder.close();

      await jsonFile.delete();

      if (context.mounted) {
        if (Platform.isIOS) {
          final box = context.findRenderObject() as RenderBox?;
          await SharePlus.instance.share(ShareParams(
              files: [XFile(zipFilePath)],
              sharePositionOrigin: box!.localToGlobal(Offset.zero) & const Size(100, 100)));
        } else {
          await SharePlus.instance.share(ShareParams(files: [XFile(zipFilePath)]));
        }
      }
    } catch (e) {
      logThis('fetchNews', 'Error shareing the backup: ${e.toString()}', LogLevel.ERROR);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.backupError)),
        );
      }
    }
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
