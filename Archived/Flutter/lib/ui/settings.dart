import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flux_news/functions/android_url_launcher.dart';
import 'package:flux_news/functions/flux_news_audio_handler.dart';
import 'package:flux_news/functions/flux_news_carplay_service.dart';
import 'package:flux_news/ui/log_viewer.dart';
import 'package:flux_news/functions/logging.dart';
import 'package:flux_news/functions/settings_backup_service.dart';
import 'package:flux_news/functions/widget_service.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/state_management/flux_news_counter_state.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/ui/adaptive_feed_icon.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flux_news/ui/settings/adaptive_settings_scaffold.dart';
import 'package:flux_news/ui/settings/adaptive_settings_controls.dart';
import 'package:flux_news/ui/settings/download_storage_settings.dart';
import 'package:flux_news/ui/ios_liquid_glass_style.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:url_launcher/url_launcher.dart';

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
      final overviewContent = Container(
        padding: const EdgeInsets.all(12),
        alignment: Alignment.center,
        // this is the main column of the settings page
        child: _AdaptiveSettingsOverviewContent(
          children: [
            // the first row contains the headline of the settings for the miniflux server
            _SettingsSectionHeader(
              title: AppLocalizations.of(context)!.minifluxSettings,
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
            AdaptiveSettingsNavigationRow(
              icon: Icons.code,
              title: AppLocalizations.of(context)!.headerSettings,
              onTap: () {
                Navigator.pushNamed(
                    context, FluxNewsState.headerSettingsRouteString);
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
                          style: const TextStyle(
                              color: Colors.red,
                              fontSize: 20,
                              fontWeight: FontWeight.bold),
                        ),
                      )
                    : const SizedBox.shrink()
                : const SizedBox.shrink(),
            appState.insecureMinifluxURL
                ? Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 10),
                    child: Text(
                      AppLocalizations.of(context)!.insecureMinifluxURL,
                      style: const TextStyle(
                          color: Colors.red,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                    ),
                  )
                : const SizedBox.shrink(),
            const Divider(),
            _SettingsSectionHeader(
              title: AppLocalizations.of(context)!.settings,
            ),
            // this list tile contains general settings
            // it is clickable and opens the general settings
            AdaptiveSettingsNavigationRow(
              icon: Icons.settings_applications,
              title: AppLocalizations.of(context)!.generalSettings,
              onTap: () {
                Navigator.pushNamed(
                    context, FluxNewsState.generalSettingsRouteString);
              },
            ),
            const Divider(),

            // this list tile contains sync settings
            // it is clickable and opens the sync settings
            AdaptiveSettingsNavigationRow(
              icon: Icons.sync,
              title: AppLocalizations.of(context)!.syncSettings,
              onTap: () {
                Navigator.pushNamed(
                    context, FluxNewsState.syncSettingsRouteString);
              },
            ),
            const Divider(),
            // this list tile contains news item settings
            // it is clickable and opens the news item settings
            AdaptiveSettingsNavigationRow(
              icon: Icons.article,
              title: AppLocalizations.of(context)!.newsItemSettings,
              onTap: () {
                Navigator.pushNamed(
                    context, FluxNewsState.newsItemSettingsRouteString);
              },
            ),
            const Divider(),

            // this list tile contains feed settings
            // it is clickable and opens the feed settings
            AdaptiveSettingsNavigationRow(
              icon: Icons.feed,
              title: AppLocalizations.of(context)!.feedSettings,
              onTap: () {
                Navigator.pushNamed(
                    context, FluxNewsState.feedSettingsRouteString);
              },
            ),
            const Divider(),

            // this list tile contains truncate settings
            // it is clickable and opens the truncate settings
            AdaptiveSettingsNavigationRow(
              icon: Icons.cut_outlined,
              title: AppLocalizations.of(context)!.truncateMode,
              onTap: () {
                Navigator.pushNamed(
                    context, FluxNewsState.truncateSettingsRouteString);
              },
            ),

            const Divider(),
            AdaptiveSettingsNavigationRow(
              icon: Icons.storage_rounded,
              title: AppLocalizations.of(context)!.downloadedData,
              subtitle: AppLocalizations.of(context)!.downloadsManagerClearAll,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const DownloadStorageSettings(),
                  ),
                );
              },
            ),

            const Divider(),
            AdaptiveSettingsNavigationRow(
              icon: Icons.widgets_outlined,
              title: AppLocalizations.of(context)!.widgetSettings,
              onTap: () {
                Navigator.pushNamed(
                    context, FluxNewsState.widgetSettingsRouteString);
              },
            ),

            const Divider(),
            _SettingsSectionHeader(
              title: AppLocalizations.of(context)!.debugSettings,
              topPadding: 12,
            ),
            // this row contains the selection if the debug mode is turned on
            _AdaptiveSettingsSwitchRow(
              icon: Icons.developer_mode,
              title: AppLocalizations.of(context)!.debugModeTextSettings,
              value: appState.debugMode,
              onChanged: (bool value) {
                String stringValue = FluxNewsState.secureStorageFalseString;
                if (value == true) {
                  stringValue = FluxNewsState.secureStorageTrueString;
                }
                appState.debugMode = value;
                appState.storage.write(
                    key: FluxNewsState.secureStorageDebugModeKey,
                    value: stringValue);
                if (Platform.isIOS) {
                  FluxNewsCarPlayService.setDebugMode(value);
                }
                FluxNewsAudioHandler.setDebugMode(value);
                appState.refreshView();
              },
            ),
            const Divider(),
            // clear logs on start toggle
            _AdaptiveSettingsSwitchRow(
              icon: Icons.delete_sweep,
              title: AppLocalizations.of(context)!.clearLogsOnStart,
              value: appState.clearLogsOnStart,
              onChanged: (bool value) {
                appState.clearLogsOnStart = value;
                appState.storage.write(
                  key: FluxNewsState.secureStorageClearLogsOnStartKey,
                  value: value
                      ? FluxNewsState.secureStorageTrueString
                      : FluxNewsState.secureStorageFalseString,
                );
                appState.refreshView();
              },
            ),
            const Divider(),
            // Log viewer
            AdaptiveSettingsNavigationRow(
              icon: Icons.list_alt,
              title: AppLocalizations.of(context)!.showLogs,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LogViewerScreen(),
                  ),
                );
              },
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
              onTap: () async {
                if (Platform.isAndroid || Platform.isIOS) {
                  await exportLogs(context);
                }
              },
            ),
            const Divider(),
            _SettingsSectionHeader(
              title: AppLocalizations.of(context)!.backupSettings,
            ),
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
            if (Platform.isAndroid) const Divider(),
            if (Platform.isAndroid)
              FutureBuilder<bool>(
                future: SettingsBackupService.readAndroidAutoBackupEnabled(
                    appState),
                builder: (context, snapshot) {
                  final enabled = snapshot.data ?? false;
                  return Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.cloud_upload_outlined),
                        title: Padding(
                          padding: const EdgeInsets.fromLTRB(15, 0, 0, 0),
                          child: Text(
                            AppLocalizations.of(context)!
                                .includeSettingsInAndroidBackup,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.fromLTRB(15, 0, 0, 0),
                          child: Text(
                            AppLocalizations.of(context)!
                                .includeSettingsInAndroidBackupDescription,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        trailing: AdaptiveSettingsSwitch(
                          value: enabled,
                          onChanged: snapshot.connectionState ==
                                  ConnectionState.waiting
                              ? null
                              : (value) => _setAndroidAutoBackupEnabled(
                                    context,
                                    appState,
                                    value,
                                  ),
                        ),
                      ),
                      if (enabled)
                        FutureBuilder<AndroidAutoBackupFileStatus>(
                          future: SettingsBackupService
                              .readAndroidAutoBackupFileStatus(),
                          builder: (context, statusSnapshot) {
                            final status = statusSnapshot.data;
                            final hasFile = status?.exists == true;
                            final subtitle = hasFile && status?.modified != null
                                ? '${AppLocalizations.of(context)!.lastChange}: '
                                    '${appState.dateFormat.format(status!.modified!.toLocal())}'
                                : AppLocalizations.of(context)!
                                    .androidAutoBackupFileMissing;
                            return ListTile(
                              leading: const Icon(Icons.check_circle_outline),
                              title: Padding(
                                padding: const EdgeInsets.fromLTRB(15, 0, 0, 0),
                                child: Text(
                                  hasFile
                                      ? AppLocalizations.of(context)!
                                          .androidAutoBackupSuccessful
                                      : AppLocalizations.of(context)!
                                          .androidAutoBackupNotCreated,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.fromLTRB(15, 0, 0, 0),
                                child: Text(
                                  subtitle,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  );
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
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium!
                      .copyWith(color: Colors.red),
                ),
              ),
              onTap: () {
                _showDeleteLocalCacheDialog(context, appState);
              },
            ),
            const Divider(),
            ListTile(
              leading: const FaIcon(FontAwesomeIcons.github),
              title: Padding(
                padding: Platform.isAndroid
                    ? const EdgeInsets.fromLTRB(15, 0, 0, 0)
                    : const EdgeInsets.fromLTRB(0, 0, 0, 0),
                child: Text(
                  AppLocalizations.of(context)!.openSource,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              onTap: () async {
                if (Platform.isAndroid) {
                  AndroidUrlLauncher.launchUrl(
                      context, FluxNewsState.applicationProjectUrl);
                } else {
                  // catch exception if no app is installed to handle the url
                  final bool nativeAppLaunchSucceeded = await launchUrl(
                    Uri.parse(FluxNewsState.applicationProjectUrl),
                    mode: LaunchMode.externalNonBrowserApplication,
                  );
                  //if exception is caught, open the app in web-view
                  if (!nativeAppLaunchSucceeded) {
                    await launchUrl(
                      Uri.parse(FluxNewsState.applicationProjectUrl),
                      mode: LaunchMode.inAppWebView,
                    );
                  }
                }
              },
              trailing: const Icon(Icons.open_in_new),
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
                      TextSpan(
                          text: AppLocalizations.of(context)!
                              .descriptionMinifluxApp),
                      const TextSpan(
                          text: '${FluxNewsState.miniFluxProjectUrl}\n'),
                      TextSpan(
                          text: AppLocalizations.of(context)!
                              .descriptionMoreInformation),
                      const TextSpan(
                          text: ' ${FluxNewsState.applicationProjectUrl}'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
      return AdaptiveSettingsScaffold(
        title: AppLocalizations.of(context)!.settings,
        useLargeTitle: true,
        body: SingleChildScrollView(child: overviewContent),
        iosLargeTitleBody: overviewContent,
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
    if (!await appState.readConfigValues()) return;
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
          KeyValueRecordType(
              key: category.categoryID.toString(), value: category.title),
        );
        if (category.categoryID == appState.startupCategorieSelectionKey) {
          appState.startupCategorieSelection = KeyValueRecordType(
              key: category.categoryID.toString(), value: category.title);
        }
      }

      for (Category category in actualCategoryList.categories) {
        for (Feed feed in category.feeds) {
          appState.recordTypesStartupFeeds!.add(
            KeyValueRecordType(key: feed.feedID.toString(), value: feed.title),
          );
          if (feed.feedID == appState.startupFeedSelectionKey) {
            appState.startupFeedSelection = KeyValueRecordType(
                key: feed.feedID.toString(), value: feed.title);
          }
        }
      }
    }
    appState.refreshView();
  }

  Future<void> exportLogs(BuildContext context) async {
    try {
      Directory? logsDir;
      Directory? exportDirectory;

      if (Platform.isIOS) {
        final appSupport = await getApplicationSupportDirectory();
        logsDir = Directory(
            '${appSupport.path}/${FluxNewsState.logsWriteDirectoryName}');
        exportDirectory = await getApplicationDocumentsDirectory();
      } else if (Platform.isAndroid) {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          logsDir = Directory(
              '${extDir.path}/${FluxNewsState.logsWriteDirectoryName}');
          exportDirectory = extDir;
        }
      }

      if (logsDir == null || !logsDir.existsSync()) {
        logThis('exportLogs', 'Log directory not found: ${logsDir?.path}',
            LogLevel.ERROR);
        return;
      }

      if (exportDirectory == null) {
        logThis('exportLogs', 'Export directory not available', LogLevel.ERROR);
        return;
      }

      final archive = Archive();
      for (final entity in logsDir.listSync(recursive: true)) {
        if (entity is! File) continue;
        final relativePath = entity.path.substring(logsDir.path.length + 1);
        // Skip the nested export subdirectory (native plugin artifacts) and any ZIPs
        if (relativePath
            .startsWith('${FluxNewsState.logsWriteDirectoryName}/')) {
          continue;
        }
        if (relativePath.endsWith('.zip')) continue;
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
      }

      if (archive.files.isEmpty) {
        logThis('exportLogs', 'No log files found to export', LogLevel.WARNING);
        return;
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final zipPath = '${exportDirectory.path}/flux_news_logs_$timestamp.zip';
      final zipBytes = ZipEncoder().encode(archive);
      await File(zipPath).writeAsBytes(zipBytes, flush: true);

      if (context.mounted) {
        if (Platform.isIOS) {
          final box = context.findRenderObject() as RenderBox?;
          await SharePlus.instance.share(ShareParams(
            files: [XFile(zipPath)],
            sharePositionOrigin: box != null
                ? box.localToGlobal(Offset.zero) & const Size(100, 100)
                : null,
          ));
        } else {
          await SharePlus.instance.share(ShareParams(files: [XFile(zipPath)]));
        }
      }
    } catch (e) {
      logThis('exportLogs', 'Error exporting logs: ${e.toString()}',
          LogLevel.ERROR);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.backupError)),
        );
      }
    }
  }

  Future<void> _setAndroidAutoBackupEnabled(
    BuildContext context,
    FluxNewsState appState,
    bool enabled,
  ) async {
    try {
      if (!enabled) {
        await SettingsBackupService.writeAndroidAutoBackupEnabled(
            appState, false);
        await SettingsBackupService.deleteStoredBackupPassword(appState);
        await SettingsBackupService.deleteAndroidAutoBackupFileIfExists();
        appState.refreshView();
        return;
      }

      final password = await SettingsBackupService.promptForBackupPassword(
        context,
        title: AppLocalizations.of(context)!.backupPassword,
        allowUnencryptedBackup: true,
      );
      if (password == null) {
        appState.refreshView();
        return;
      }

      if (password.unencrypted) {
        await SettingsBackupService.deleteStoredBackupPassword(appState);
      } else {
        await SettingsBackupService.writeStoredBackupPassword(
            appState, password.password);
      }
      await SettingsBackupService.writeAndroidAutoBackupEnabled(appState, true);
      await SettingsBackupService.writeBackupFile(
        appState,
        await SettingsBackupService.androidAutoBackupFile(),
        password: password.password,
      );
      appState.refreshView();
    } catch (e) {
      logThis(
          'androidAutoBackupSettings',
          'Error updating Android auto backup setting: ${e.toString()}',
          LogLevel.ERROR);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.backupError)),
        );
      }
      appState.refreshView();
    }
  }

  Future<void> exportSettingsBackup(
      BuildContext context, FluxNewsState appState) async {
    try {
      final password = await SettingsBackupService.promptForBackupPassword(
        context,
        title: AppLocalizations.of(context)!.backupPassword,
        allowUnencryptedBackup: true,
      );
      if (password == null) return;
      Directory? exportDirectory;
      if (Platform.isIOS) {
        exportDirectory = await getApplicationDocumentsDirectory();
      } else {
        exportDirectory = await getExternalStorageDirectory();
      }

      if (exportDirectory == null) {
        logThis(
            'fetchNews',
            'Error export directory for the backup could not be determined',
            LogLevel.ERROR);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.backupError)),
          );
        }
        return;
      }

      final backupFile = await SettingsBackupService.writeManualBackupFile(
          appState, exportDirectory, password.password);

      if (context.mounted) {
        if (Platform.isIOS) {
          final box = context.findRenderObject() as RenderBox?;
          await SharePlus.instance.share(ShareParams(
              files: [XFile(backupFile.path)],
              sharePositionOrigin: box != null
                  ? box.localToGlobal(Offset.zero) & const Size(100, 100)
                  : null));
        } else {
          await SharePlus.instance
              .share(ShareParams(files: [XFile(backupFile.path)]));
        }
      }
    } catch (e) {
      logThis('fetchNews', 'Error shareing the backup: ${e.toString()}',
          LogLevel.ERROR);
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
    if (Platform.isIOS) {
      StateSetter? updateDialog;
      return showAdaptiveSettingsGlassDialog<void>(
        context: context,
        title: AppLocalizations.of(context)!.titleURL,
        settings: iosLiquidGlassMenuSettings(
          context,
          useClearEffect: appState.iosClearLiquidGlass,
        ),
        quality: GlassQuality.standard,
        maxWidth: 340,
        content: StatefulBuilder(
          builder: (dialogContext, setState) {
            updateDialog = setState;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLocalizations.of(dialogContext)!.enterURL),
                const SizedBox(height: 10),
                AdaptiveSettingsTextField(
                  controller: controller,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  useOwnLayer: false,
                ),
                if (errorInForm) ...[
                  const SizedBox(height: 6),
                  Text(
                    AppLocalizations.of(dialogContext)!.enterValidURL,
                    style: const TextStyle(color: CupertinoColors.systemRed),
                  ),
                ],
              ],
            );
          },
        ),
        actions: [
          GlassDialogAction(
            label: AppLocalizations.of(context)!.cancel,
            onPressed: () => Navigator.pop(context),
          ),
          GlassDialogAction(
            label: AppLocalizations.of(context)!.save,
            isPrimary: true,
            onPressed: () async {
              final regex = RegExp(FluxNewsState.urlValidationRegex);
              if (!regex.hasMatch(controller.text)) {
                updateDialog?.call(() => errorInForm = true);
                return;
              }

              String newText = controller.text;
              if (!newText.endsWith('/v1/')) {
                if (!newText.endsWith('/v1')) {
                  newText = newText.endsWith('/')
                      ? newText + FluxNewsState.apiVersionPath
                      : '$newText/${FluxNewsState.apiVersionPath}';
                } else {
                  newText = '$newText/';
                }
              }
              if (appState.minifluxAPIKey?.isNotEmpty ?? false) {
                final authCheck = await checkMinifluxCredentials(
                  newText,
                  appState.minifluxAPIKey!,
                  appState,
                ).onError((error, stackTrace) => false);
                appState.errorOnMinifluxAuth = !authCheck;
                appState.insecureMinifluxURL =
                    !newText.toLowerCase().startsWith('https');
              }
              await appState.storage.write(
                key: FluxNewsState.secureStorageMinifluxURLKey,
                value: newText,
              );
              appState.minifluxURL = newText;
              if (context.mounted) {
                Navigator.pop(context);
                appState.refreshView();
              }
            },
          ),
        ],
      );
    }
    return showDialog(
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(builder: (context, setState) {
            return AlertDialog.adaptive(
              title: Text(AppLocalizations.of(context)!.titleURL),
              content: Wrap(children: [
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
                  onPressed: () =>
                      Navigator.pop(context, FluxNewsState.cancelContextString),
                  child: Text(AppLocalizations.of(context)!.cancel),
                ),
                TextButton(
                  onPressed: () async {
                    String? newText;
                    if (formKey.currentState!.validate()) {
                      if (controller.text != '') {
                        newText = controller.text;
                        if (!newText.endsWith('/v1/')) {
                          if (!newText.endsWith('/v1')) {
                            if (newText.endsWith('/')) {
                              newText = newText + FluxNewsState.apiVersionPath;
                            } else {
                              newText =
                                  "$newText/${FluxNewsState.apiVersionPath}";
                            }
                          } else {
                            newText = "$newText/";
                          }
                        }
                      }
                      if (appState.minifluxAPIKey != null &&
                          appState.minifluxAPIKey != '' &&
                          newText != null) {
                        bool authCheck = await checkMinifluxCredentials(
                                newText, appState.minifluxAPIKey!, appState)
                            .onError((error, stackTrace) => false);

                        appState.errorOnMinifluxAuth = !authCheck;
                        appState.insecureMinifluxURL =
                            !newText.toLowerCase().startsWith('https');
                        appState.refreshView();
                      }
                      appState.storage.write(
                          key: FluxNewsState.secureStorageMinifluxURLKey,
                          value: newText);
                      appState.minifluxURL = newText;
                      if (context.mounted) {
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
    if (Platform.isIOS) {
      return showAdaptiveSettingsGlassDialog<void>(
        context: context,
        title: AppLocalizations.of(context)!.titleAPIKey,
        settings: iosLiquidGlassMenuSettings(
          context,
          useClearEffect: appState.iosClearLiquidGlass,
        ),
        quality: GlassQuality.standard,
        maxWidth: 340,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context)!.enterAPIKey),
            const SizedBox(height: 10),
            AdaptiveSettingsTextField(
              controller: controller,
              textInputAction: TextInputAction.done,
              useOwnLayer: false,
            ),
          ],
        ),
        actions: [
          GlassDialogAction(
            label: AppLocalizations.of(context)!.cancel,
            onPressed: () => Navigator.pop(context),
          ),
          GlassDialogAction(
            label: AppLocalizations.of(context)!.save,
            isPrimary: true,
            onPressed: () async {
              final newText = controller.text.isEmpty ? null : controller.text;
              if (appState.minifluxURL?.isNotEmpty == true && newText != null) {
                final authCheck = await checkMinifluxCredentials(
                  appState.minifluxURL!,
                  newText,
                  appState,
                ).onError((error, stackTrace) => false);
                appState.errorOnMinifluxAuth = !authCheck;
                appState.insecureMinifluxURL =
                    !appState.minifluxURL!.toLowerCase().startsWith('https');
              }
              await appState.storage.write(
                key: FluxNewsState.secureStorageMinifluxAPIKey,
                value: newText,
              );
              appState.minifluxAPIKey = newText;
              if (context.mounted) {
                Navigator.pop(context);
                appState.refreshView();
              }
            },
          ),
        ],
      );
    }
    return showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog.adaptive(
            title: Text(AppLocalizations.of(context)!.titleAPIKey),
            content: Wrap(children: [
              Text(AppLocalizations.of(context)!.enterAPIKey),
              TextField(controller: controller),
            ]),
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
                            appState.minifluxURL!, newText, appState)
                        .onError((error, stackTrace) => false);
                    appState.errorOnMinifluxAuth = !authCheck;
                    appState.insecureMinifluxURL = !appState.minifluxURL!
                        .toLowerCase()
                        .startsWith('https');
                    appState.refreshView();
                  }

                  appState.storage.write(
                      key: FluxNewsState.secureStorageMinifluxAPIKey,
                      value: newText);
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

  Future<void> _deleteFeedIconsOnly(
      BuildContext context, FluxNewsState appState) async {
    await appState.deleteAllFeedIconFiles();
    FeedIconContrastAnalyzer.clearCache();

    try {
      final news = await appState.newsList;
      for (final item in news) {
        item.icon = null;
      }
    } catch (error) {
      logThis('deleteFeedIconsOnly',
          'Could not clear loaded news icons: $error', LogLevel.WARNING);
    }

    try {
      final categories = await appState.categoryList;
      for (final category in categories.categories) {
        for (final feed in category.feeds) {
          feed.icon = null;
        }
      }
    } catch (error) {
      logThis('deleteFeedIconsOnly',
          'Could not clear loaded feed icons: $error', LogLevel.WARNING);
    }

    final actualCategories = appState.actualCategoryList;
    if (actualCategories != null) {
      for (final category in actualCategories.categories) {
        for (final feed in category.feeds) {
          feed.icon = null;
        }
      }
    }

    try {
      await FluxNewsWidgetService.updateWidgetSnapshot(appState);
    } catch (error) {
      logThis('deleteFeedIconsOnly', 'Could not update widget snapshot: $error',
          LogLevel.WARNING);
    }

    if (!context.mounted) return;
    appState.refreshView();
    Navigator.pop(context);
  }

  Future<void> _deleteAllLocalData(
      BuildContext context, FluxNewsState appState) async {
    await stopFluxNewsAudioHandlerIfInitialized();
    await deleteLocalNewsCache(appState);
    FeedIconContrastAnalyzer.clearCache();
    if (!context.mounted) return;

    appState.newsList = Future<List<News>>.value([]);
    appState.categoryList =
        Future<Categories>.value(Categories(categories: []));
    context.read<FluxNewsCounterState>().allNewsCount = 0;
    context.read<FluxNewsCounterState>().appBarNewsCount = 0;
    context.read<FluxNewsCounterState>().starredCount = 0;
    context.read<FluxNewsCounterState>().refreshView();
    appState.refreshView();
    Navigator.pop(context);
  }

  Future _showDeleteLocalCacheDialog(
      BuildContext context, FluxNewsState appState) {
    if (Platform.isIOS) {
      return showAdaptiveSettingsGlassDialog<void>(
        context: context,
        title: AppLocalizations.of(context)!.deleteLocalCacheDialogTitle,
        message: AppLocalizations.of(context)!.deleteLocalCacheDialogContent,
        settings: iosLiquidGlassMenuSettings(
          context,
          useClearEffect: appState.iosClearLiquidGlass,
        ),
        quality: GlassQuality.standard,
        maxWidth: 360,
        actions: [
          GlassDialogAction(
            label: AppLocalizations.of(context)!.cancel,
            isPrimary: true,
            onPressed: () => Navigator.pop(context),
          ),
          GlassDialogAction(
            label: AppLocalizations.of(context)!.deleteFeedIconsOnly,
            onPressed: () => _deleteFeedIconsOnly(context, appState),
          ),
          GlassDialogAction(
            label: AppLocalizations.of(context)!.deleteAllLocalData,
            isDestructive: true,
            onPressed: () => _deleteAllLocalData(context, appState),
          ),
        ],
      );
    }
    return showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog.adaptive(
            title:
                Text(AppLocalizations.of(context)!.deleteLocalCacheDialogTitle),
            content: Text(
              AppLocalizations.of(context)!.deleteLocalCacheDialogContent,
              textAlign: TextAlign.start,
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, FluxNewsState.cancelContextString),
                child: Text(AppLocalizations.of(context)!.cancel),
              ),
              TextButton(
                onPressed: () async {
                  await _deleteFeedIconsOnly(context, appState);
                },
                child: Text(AppLocalizations.of(context)!.deleteFeedIconsOnly),
              ),
              TextButton(
                onPressed: () async {
                  await _deleteAllLocalData(context, appState);
                },
                child: Text(
                  AppLocalizations.of(context)!.deleteAllLocalData,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],
          );
        });
  }
}

class _AdaptiveSettingsSwitchRow extends StatelessWidget {
  const _AdaptiveSettingsSwitchRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: Platform.isIOS ? 44 : 0),
      child: Row(
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: 17,
              right: Platform.isIOS ? 15 : 30,
            ),
            child: Icon(icon),
          ),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              overflow: TextOverflow.visible,
            ),
          ),
          AdaptiveSettingsSwitch(
            value: value,
            onChanged: onChanged,
            semanticLabel: title,
          ),
        ],
      ),
    );
  }
}

class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader({
    required this.title,
    this.topPadding = 0,
  });

  final String title;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdaptiveSettingsOverviewContent extends StatelessWidget {
  const _AdaptiveSettingsOverviewContent({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final sections = <({String title, List<Widget> children})>[];
    String? currentTitle;
    var currentChildren = <Widget>[];

    void finishSection() {
      if (currentTitle == null) return;
      while (currentChildren.isNotEmpty && currentChildren.first is Divider) {
        currentChildren.removeAt(0);
      }
      while (currentChildren.isNotEmpty && currentChildren.last is Divider) {
        currentChildren.removeLast();
      }
      sections.add((title: currentTitle, children: currentChildren));
      currentChildren = <Widget>[];
    }

    for (final child in children) {
      if (child is _SettingsSectionHeader) {
        finishSection();
        currentTitle = child.title;
      } else {
        currentChildren.add(child);
      }
    }
    finishSection();

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final section in sections)
                AdaptiveSettingsGroup(
                  title: section.title,
                  children: section.children,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class FluxNewsSettingsStatefulWrapper extends StatefulWidget {
  final Function onInit;
  final Widget child;
  const FluxNewsSettingsStatefulWrapper(
      {super.key, required this.onInit, required this.child});
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
