import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flux_news/functions/logging.dart';
import 'package:flux_news/functions/settings_backup_service.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/ui/ios_liquid_glass_style.dart';
import 'package:flux_news/ui/settings/adaptive_settings_controls.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';

import '../state_management/flux_news_state.dart';

class RestoreSettingsPage extends StatefulWidget {
  const RestoreSettingsPage({super.key});

  @override
  State<RestoreSettingsPage> createState() => _RestoreSettingsPageState();
}

class _RestoreSettingsPageState extends State<RestoreSettingsPage> {
  bool _restoring = false;

  Future<bool> _confirmRestore(ParsedSettingsBackup preview) async {
    final previewContent = SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${AppLocalizations.of(context)!.file}: ${preview.fileName}'),
          const SizedBox(height: 8),
          Text(
              '${AppLocalizations.of(context)!.backupType}: ${preview.backupType}'),
          Text(
              '${AppLocalizations.of(context)!.createdAt}: ${preview.createdAt ?? '-'}'),
          Text(
              '${AppLocalizations.of(context)!.appVersion}: ${preview.appVersion ?? '-'}'),
          Text(
              '${AppLocalizations.of(context)!.settings}: ${preview.settingsCount}'),
          Text(
              '${AppLocalizations.of(context)!.feedSettings}: ${preview.feedSettingsCount}'),
          const SizedBox(height: 12),
          Text(
            AppLocalizations.of(context)!.confirmRestoreOverride,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );

    if (Platform.isIOS) {
      final appState = context.read<FluxNewsState>();
      return await showAdaptiveGlassDialog<bool>(
            context: context,
            title: AppLocalizations.of(context)!.confirmRestore,
            content: previewContent,
            settings: iosLiquidGlassMenuSettings(
              context,
              useClearEffect: appState.iosClearLiquidGlass,
            ),
            quality: GlassQuality.standard,
            maxWidth: 360,
            actions: [
              GlassDialogAction(
                label: AppLocalizations.of(context)!.cancel,
                onPressed: () => Navigator.pop(context, false),
              ),
              GlassDialogAction(
                label: AppLocalizations.of(context)!.restore,
                isPrimary: true,
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ) ??
          false;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog.adaptive(
          title: Text(AppLocalizations.of(context)!.confirmRestore),
          content: previewContent,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppLocalizations.of(context)!.restore),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<ParsedSettingsBackup> _parseBackupFile(File backupFile) async {
    try {
      return await SettingsBackupService.parseBackupFile(backupFile);
    } on BackupPasswordRequiredException {
      if (!mounted) rethrow;
      final password = await SettingsBackupService.promptForBackupPassword(
        context,
        title: AppLocalizations.of(context)!.backupPassword,
        confirmPassword: false,
      );
      if (password == null) {
        throw BackupPasswordRequiredException();
      }
      final parsed = await SettingsBackupService.parseBackupFile(
        backupFile,
        password: password.password,
      );
      return parsed;
    } on BackupPasswordInvalidException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(AppLocalizations.of(context)!.backupPasswordInvalid)),
        );
      }
      rethrow;
    }
  }

  Future<void> _previewAndRestore(File backupFile) async {
    try {
      final preview = await _parseBackupFile(backupFile);
      if (!mounted) {
        return;
      }
      final confirmed = await _confirmRestore(preview);
      if (!confirmed) {
        return;
      }
      await _restoreBackup(backupFile, parsedBackup: preview);
    } catch (e) {
      if (mounted) {
        logThis('RestoreSettings', 'Backup check failed: ${e.toString()}',
            LogLevel.ERROR);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!.backupCheckFailed)),
        );
      }
    }
  }

  Future<void> _pickAndRestoreBackup() async {
    if (_restoring) {
      return;
    }

    try {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['zip', 'fnbak'],
      );
      if (result == null) {
        return;
      }

      final selectedPath = result.path;
      if (selectedPath == null || selectedPath.isEmpty) {
        if (mounted) {
          logThis('RestoreSettings', 'The selected file is invalid.',
              LogLevel.ERROR);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.invalidFile)),
          );
        }
        return;
      }

      final selectedFile = File(selectedPath);
      await _previewAndRestore(selectedFile);
    } catch (e) {
      if (mounted) {
        logThis('RestoreSettings', 'The file selection failed: ${e.toString()}',
            LogLevel.ERROR);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!.fileSelectionFailed)),
        );
      }
    }
  }

  Future<void> _restoreBackup(File backupFile,
      {ParsedSettingsBackup? parsedBackup}) async {
    if (_restoring) {
      return;
    }

    FluxNewsState appState = context.read<FluxNewsState>();
    setState(() {
      _restoring = true;
    });

    try {
      final parsed = parsedBackup ?? await _parseBackupFile(backupFile);

      await SettingsBackupService.restoreBackup(appState, parsed);

      if (!await appState.readConfigValues()) {
        throw StateError(
            'Restored settings could not be read from secure storage');
      }
      if (mounted) {
        appState.readConfig(context);
        appState.readThemeConfigValues(context);
      }
      appState.syncNow = true;
      appState.refreshView();

      if (mounted) {
        logThis(
            'RestoreSettings', 'Backup successfully restored.', LogLevel.INFO);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  AppLocalizations.of(context)!.backupSuccessfullyRestored)),
        );
        Navigator.pushNamedAndRemoveUntil(
            context, FluxNewsState.rootRouteString, (route) => false);
      }
    } catch (e) {
      if (mounted) {
        logThis('RestoreSettings', 'Restore failed: ${e.toString()}',
            LogLevel.ERROR);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.restoreFailed)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _restoring = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      final appState = context.watch<FluxNewsState>();
      final glassSettings = iosLiquidGlassSettings(
        context,
        useClearEffect: appState.iosClearLiquidGlass,
      );
      final glassQuality = iosLiquidGlassQuality(
        useClearEffect: appState.iosClearLiquidGlass,
      );
      final foreground = iosLiquidGlassForeground(context);
      final title = AppLocalizations.of(context)!.restoreSettings;
      return Scaffold(
        extendBodyBehindAppBar: true,
        appBar: GlassAppBar(
          centerTitle: false,
          buttonSettings: glassSettings,
          leading: Navigator.canPop(context)
              ? GlassIconButton(
                  useOwnLayer: true,
                  quality: glassQuality,
                  settings: glassSettings,
                  semanticLabel:
                      MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => Navigator.maybePop(context),
                  icon: Icon(CupertinoIcons.back, color: foreground),
                )
              : null,
          title: Padding(
            padding: const EdgeInsetsDirectional.only(start: 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: GlassContainer(
                useOwnLayer: true,
                quality: glassQuality,
                settings: glassSettings,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
          ),
        ),
        body: Padding(
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top + 52,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: GlassContainer(
                  useOwnLayer: true,
                  quality: GlassQuality.standard,
                  settings: glassSettings,
                  shape: const LiquidRoundedSuperellipse(borderRadius: 26),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _restoring
                          ? CupertinoActivityIndicator(
                              radius: 16,
                              color: foreground,
                            )
                          : Icon(
                              CupertinoIcons.folder_open,
                              size: 36,
                              color: foreground,
                            ),
                      const SizedBox(height: 16),
                      Text(
                        AppLocalizations.of(context)!.selectZipBackupFile,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: foreground,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: AdaptiveSettingsButton(
            onPressed: _restoring ? null : _pickAndRestoreBackup,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(CupertinoIcons.folder_open, size: 19),
                const SizedBox(width: 8),
                Text(AppLocalizations.of(context)!.selectZipBackupFileButton),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.restoreSettings,
            style: Theme.of(context).textTheme.titleLarge),
      ),
      body: Column(
        children: [
          if (_restoring) const LinearProgressIndicator(),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  AppLocalizations.of(context)!.selectZipBackupFile,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: SizedBox(
                width: double.infinity,
                child: Platform.isIOS
                    ? CupertinoButton.filled(
                        onPressed: _restoring ? null : _pickAndRestoreBackup,
                        child: Text(AppLocalizations.of(context)!
                            .selectZipBackupFileButton),
                      )
                    : ElevatedButton.icon(
                        onPressed: _restoring ? null : _pickAndRestoreBackup,
                        icon: const Icon(Icons.folder_open),
                        label: Text(AppLocalizations.of(context)!
                            .selectZipBackupFileButton),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
