import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flux_news/functions/logging.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:provider/provider.dart';

import '../state_management/flux_news_state.dart';

class RestoreSettingsPage extends StatefulWidget {
  const RestoreSettingsPage({super.key});

  @override
  State<RestoreSettingsPage> createState() => _RestoreSettingsPageState();
}

class _RestoreSettingsPageState extends State<RestoreSettingsPage> {
  bool _restoring = false;

  Future<bool> _confirmRestore(_ParsedBackupData preview) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog.adaptive(
          title: Text(AppLocalizations.of(context)!.confirmRestore),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${AppLocalizations.of(context)!.file}: ${preview.fileName}'),
                const SizedBox(height: 8),
                Text('${AppLocalizations.of(context)!.backupType}: ${preview.backupType}'),
                Text('${AppLocalizations.of(context)!.createdAt}: ${preview.createdAt ?? '-'}'),
                Text('${AppLocalizations.of(context)!.appVersion}: ${preview.appVersion ?? '-'}'),
                Text('${AppLocalizations.of(context)!.settings}: ${preview.settingsCount}'),
                Text('${AppLocalizations.of(context)!.feedSettings}: ${preview.feedSettingsCount}'),
                const SizedBox(height: 12),
                Text(
                  AppLocalizations.of(context)!.confirmRestoreOverride,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
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

  Future<_ParsedBackupData> _parseBackupFile(File backupFile) async {
    final bytes = await backupFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    ArchiveFile? jsonArchiveFile;
    for (final file in archive.files) {
      if (!file.isFile) {
        continue;
      }
      if (file.name.toLowerCase().endsWith('.json')) {
        jsonArchiveFile = file;
        break;
      }
    }

    if (jsonArchiveFile == null) {
      logThis('RestoreSettings', 'Found no JSON file in the ZIP.', LogLevel.ERROR);
      throw Exception('Found no JSON file in the ZIP.');
    }

    final jsonContent = utf8.decode(jsonArchiveFile.content as List<int>);
    final data = jsonDecode(jsonContent);
    if (data is! Map<String, dynamic>) {
      logThis('RestoreSettings', 'Invalid backup format.', LogLevel.ERROR);
      throw Exception('Invalid backup format.');
    }

    final backupType = data['backupType']?.toString() ?? '';
    if (backupType != 'flux_news_settings') {
      logThis('RestoreSettings', 'This ZIP is not a Flux News Settings Backup.', LogLevel.ERROR);
      throw Exception('This ZIP is not a Flux News Settings Backup.');
    }

    final settings = data['settings'];
    if (settings is! Map) {
      logThis('RestoreSettings', 'Settings in the backup are missing or invalid.', LogLevel.ERROR);
      throw Exception('Settings in the backup are missing or invalid.');
    }

    final feedSettings = data['feedSettings'];
    if (feedSettings is! List) {
      logThis('RestoreSettings', 'Feed settings in the backup are missing or invalid.', LogLevel.ERROR);
      throw Exception('Feed settings in the backup are missing or invalid.');
    }

    final storageEntries = Map<String, dynamic>.from(settings);
    final normalizedFeedSettings = <Map<String, dynamic>>[];
    for (final item in feedSettings) {
      if (item is Map) {
        normalizedFeedSettings.add(Map<String, dynamic>.from(item));
      }
    }

    return _ParsedBackupData(
      fileName: backupFile.path.split(Platform.pathSeparator).last,
      backupType: backupType,
      createdAt: data['createdAt']?.toString(),
      appVersion: data['appVersion']?.toString(),
      settings: storageEntries,
      feedSettings: normalizedFeedSettings,
    );
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
        logThis('RestoreSettings', 'Backup check failed: ${e.toString()}', LogLevel.ERROR);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.backupCheckFailed)),
        );
      }
    }
  }

  Future<void> _pickAndRestoreBackup() async {
    if (_restoring) {
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }

      final selectedPath = result.files.single.path;
      if (selectedPath == null || selectedPath.isEmpty) {
        if (mounted) {
          logThis('RestoreSettings', 'The selected file is invalid.', LogLevel.ERROR);
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
        logThis('RestoreSettings', 'The file selection failed: ${e.toString()}', LogLevel.ERROR);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.fileSelectionFailed)),
        );
      }
    }
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is bool) {
      return value ? 1 : 0;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  String _toText(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString();
  }

  Future<void> _restoreBackup(File backupFile, {_ParsedBackupData? parsedBackup}) async {
    if (_restoring) {
      return;
    }

    FluxNewsState appState = context.read<FluxNewsState>();
    setState(() {
      _restoring = true;
    });

    try {
      final parsed = parsedBackup ?? await _parseBackupFile(backupFile);

      final storageEntries = parsed.settings;
      for (final entry in storageEntries.entries) {
        await appState.storage.write(key: entry.key, value: entry.value?.toString());
      }

      appState.db ??= await appState.initializeDB();
      if (appState.db != null) {
        await appState.db!.delete('feeds');

        for (final feedMap in parsed.feedSettings) {
          await appState.db!.insert('feeds', {
            'feedID': _toInt(feedMap['feedID']),
            'title': _toText(feedMap['title']),
            'site_url': _toText(feedMap['site_url']),
            'iconMimeType': _toText(feedMap['iconMimeType']),
            'iconID': _toInt(feedMap['iconID']),
            'newsCount': _toInt(feedMap['newsCount']),
            'crawler': _toInt(feedMap['crawler']),
            'manualTruncate': _toInt(feedMap['manualTruncate']),
            'preferParagraph': _toInt(feedMap['preferParagraph']),
            'preferAttachmentImage': _toInt(feedMap['preferAttachmentImage']),
            'manualAdaptLightModeToIcon': _toInt(feedMap['manualAdaptLightModeToIcon']),
            'manualAdaptDarkModeToIcon': _toInt(feedMap['manualAdaptDarkModeToIcon']),
            'openMinifluxEntry': _toInt(feedMap['openMinifluxEntry']),
            'expandedWithFulltext': _toInt(feedMap['expandedWithFulltext']),
            'expandedFulltextLimit': _toInt(feedMap['expandedFulltextLimit']),
            'categoryID': _toInt(feedMap['categoryID']),
          });
        }
      }

      await appState.readConfigValues();
      if (mounted) {
        appState.readConfig(context);
        appState.readThemeConfigValues(context);
      }
      appState.syncNow = true;
      appState.refreshView();

      if (mounted) {
        logThis('RestoreSettings', 'Backup successfully restored.', LogLevel.INFO);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.backupSuccessfullyRestored)),
        );
        Navigator.pushNamedAndRemoveUntil(context, FluxNewsState.rootRouteString, (route) => false);
      }
    } catch (e) {
      if (mounted) {
        logThis('RestoreSettings', 'Restore failed: ${e.toString()}', LogLevel.ERROR);
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
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.restoreSettings),
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
                        child: Text(AppLocalizations.of(context)!.selectZipBackupFileButton),
                      )
                    : ElevatedButton.icon(
                        onPressed: _restoring ? null : _pickAndRestoreBackup,
                        icon: const Icon(Icons.folder_open),
                        label: Text(AppLocalizations.of(context)!.selectZipBackupFileButton),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ParsedBackupData {
  _ParsedBackupData({
    required this.fileName,
    required this.backupType,
    required this.settings,
    required this.feedSettings,
    this.createdAt,
    this.appVersion,
  });

  final String fileName;
  final String backupType;
  final String? createdAt;
  final String? appVersion;
  final Map<String, dynamic> settings;
  final List<Map<String, dynamic>> feedSettings;

  int get settingsCount => settings.length;
  int get feedSettingsCount => feedSettings.length;
}
