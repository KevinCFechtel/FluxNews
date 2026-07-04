import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/functions/logging.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:path_provider/path_provider.dart';

class BackupPasswordRequiredException implements Exception {}

class BackupPasswordInvalidException implements Exception {}

class ParsedSettingsBackup {
  const ParsedSettingsBackup({
    required this.fileName,
    required this.backupType,
    required this.settings,
    required this.feedSettings,
    this.createdAt,
    this.appVersion,
    this.encrypted = false,
  });

  final String fileName;
  final String backupType;
  final String? createdAt;
  final String? appVersion;
  final Map<String, dynamic> settings;
  final List<Map<String, dynamic>> feedSettings;
  final bool encrypted;

  int get settingsCount => settings.length;
  int get feedSettingsCount => feedSettings.length;
}

class AndroidAutoBackupFileStatus {
  const AndroidAutoBackupFileStatus({
    required this.exists,
    this.modified,
    this.size,
  });

  final bool exists;
  final DateTime? modified;
  final int? size;
}

class SettingsBackupService {
  static const String encryptedBackupType = 'flux_news_encrypted_settings';
  static const String plainBackupType = 'flux_news_settings';
  static const String autoBackupDirectoryName = 'android_auto_backup';
  static const String autoBackupFileName = 'flux_news_auto_backup.fnbak';
  static const String storedBackupPasswordKey = 'androidAutoBackupPassword';
  static const String androidAutoBackupEnabledKey = 'androidAutoBackupEnabled';
  static const String handledAutoBackupFingerprintKey =
      'androidAutoBackupHandledFingerprint';

  static const int _backupFormatVersion = 1;
  static const int _argon2Memory = 32 * 1024;
  static const int _argon2Iterations = 2;
  static const int _argon2Parallelism = 2;
  static const int _keyLength = 32;

  static Future<String?> readStoredBackupPassword(
      FluxNewsState appState) async {
    if (!Platform.isAndroid) return null;
    return appState.storage.read(key: storedBackupPasswordKey);
  }

  static Future<void> writeStoredBackupPassword(
      FluxNewsState appState, String password) async {
    if (!Platform.isAndroid) return;
    await appState.storage.write(key: storedBackupPasswordKey, value: password);
  }

  static Future<void> deleteStoredBackupPassword(FluxNewsState appState) async {
    if (!Platform.isAndroid) return;
    await appState.storage.delete(key: storedBackupPasswordKey);
  }

  static Future<bool> readAndroidAutoBackupEnabled(
      FluxNewsState appState) async {
    if (!Platform.isAndroid) return false;
    final value = await appState.storage.read(key: androidAutoBackupEnabledKey);
    return value == FluxNewsState.secureStorageTrueString;
  }

  static Future<void> writeAndroidAutoBackupEnabled(
      FluxNewsState appState, bool enabled) async {
    if (!Platform.isAndroid) return;
    await appState.storage.write(
      key: androidAutoBackupEnabledKey,
      value: enabled
          ? FluxNewsState.secureStorageTrueString
          : FluxNewsState.secureStorageFalseString,
    );
  }

  static Future<void> deleteAndroidAutoBackupFileIfExists() async {
    if (!Platform.isAndroid) return;
    final file = await androidAutoBackupFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<AndroidAutoBackupFileStatus>
      readAndroidAutoBackupFileStatus() async {
    if (!Platform.isAndroid) {
      return const AndroidAutoBackupFileStatus(exists: false);
    }
    final file = await androidAutoBackupFile();
    if (!await file.exists()) {
      return const AndroidAutoBackupFileStatus(exists: false);
    }
    final stat = await file.stat();
    return AndroidAutoBackupFileStatus(
      exists: true,
      modified: stat.modified,
      size: stat.size,
    );
  }

  static Future<File> androidAutoBackupFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(
        '${directory.path}/$autoBackupDirectoryName/$autoBackupFileName');
  }

  static Future<File?> findPendingAndroidAutoBackupRestore(
    FluxNewsState appState, {
    bool ignoreHandledFingerprint = false,
  }) async {
    debugPrint(
        'SettingsBackupService: Checking for pending Android auto backup restore. '
        'platform=${Platform.operatingSystem} '
        'ignoreHandledFingerprint=$ignoreHandledFingerprint');
    logThis(
        'SettingsBackupService',
        'Checking for pending Android auto backup restore. '
            'platform=${Platform.operatingSystem} ignoreHandledFingerprint=$ignoreHandledFingerprint',
        LogLevel.INFO);
    if (!Platform.isAndroid) {
      debugPrint(
          'SettingsBackupService: Skipped Android auto backup restore check on non-Android platform.');
      logThis(
          'SettingsBackupService',
          'Skipped Android auto backup restore check on non-Android platform.',
          LogLevel.INFO);
      return null;
    }
    if (appState.minifluxURL != null && appState.minifluxAPIKey != null) {
      debugPrint(
          'SettingsBackupService: Skipped Android auto backup restore check because app is already configured.');
      logThis(
          'SettingsBackupService',
          'Skipped Android auto backup restore check because app is already configured.',
          LogLevel.INFO);
      return null;
    }
    final file = await androidAutoBackupFile();
    if (!await file.exists()) {
      debugPrint(
          'SettingsBackupService: No Android auto backup file found at ${file.path}.');
      logThis('SettingsBackupService',
          'No Android auto backup file found at ${file.path}.', LogLevel.INFO);
      return null;
    }
    final fingerprint = await _fileFingerprint(file);
    final handledFingerprint =
        await appState.storage.read(key: handledAutoBackupFingerprintKey);
    logThis(
        'SettingsBackupService',
        'Android auto backup file found. path=${file.path} '
            'fingerprint=$fingerprint handledFingerprint=$handledFingerprint',
        LogLevel.INFO);
    debugPrint('SettingsBackupService: Android auto backup file found. '
        'path=${file.path} fingerprint=$fingerprint '
        'handledFingerprint=$handledFingerprint');
    if (!ignoreHandledFingerprint && handledFingerprint == fingerprint) {
      debugPrint(
          'SettingsBackupService: Skipped Android auto backup restore because fingerprint was already handled.');
      logThis(
          'SettingsBackupService',
          'Skipped Android auto backup restore because fingerprint was already handled.',
          LogLevel.INFO);
      return null;
    }
    return file;
  }

  static Future<void> markAndroidAutoBackupHandled(
      FluxNewsState appState, File file) async {
    if (!Platform.isAndroid) return;
    await appState.storage.write(
      key: handledAutoBackupFingerprintKey,
      value: await _fileFingerprint(file),
    );
  }

  static Future<void> refreshAndroidAutoBackupIfPossible(
      FluxNewsState appState) async {
    if (!Platform.isAndroid) return;
    final enabled = await readAndroidAutoBackupEnabled(appState);
    if (!enabled) {
      if (appState.minifluxURL == null || appState.minifluxAPIKey == null) {
        debugPrint(
            'SettingsBackupService: Keeping Android auto backup file because app is not configured yet.');
        logThis(
            'SettingsBackupService',
            'Keeping Android auto backup file because app is not configured yet.',
            LogLevel.INFO);
        return;
      }
      await deleteAndroidAutoBackupFileIfExists();
      return;
    }
    final password = await readStoredBackupPassword(appState);
    try {
      final file = await androidAutoBackupFile();
      await writeBackupFile(appState, file, password: password);
      logThis('SettingsBackupService', 'Android auto backup file refreshed.',
          LogLevel.INFO);
    } catch (e) {
      logThis('SettingsBackupService',
          'Could not refresh Android auto backup file: $e', LogLevel.WARNING);
    }
  }

  static Future<File> writeManualBackupFile(
    FluxNewsState appState,
    Directory exportDirectory,
    String? password,
  ) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File(
        '${exportDirectory.path}/flux_news_settings_backup_$timestamp.fnbak');
    await writeBackupFile(appState, file,
        password: password, timestamp: timestamp);
    return file;
  }

  static Future<void> writeBackupFile(
    FluxNewsState appState,
    File file, {
    String? password,
    int? timestamp,
  }) async {
    final plainZipBytes = await createPlainZipBackupBytes(appState,
        timestamp: timestamp ?? DateTime.now().millisecondsSinceEpoch);
    final bytes = password == null || password.isEmpty
        ? plainZipBytes
        : await encryptBackupBytes(plainZipBytes, password);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  static Future<List<int>> createPlainZipBackupBytes(
    FluxNewsState appState, {
    required int timestamp,
  }) async {
    final backupData = await createBackupData(appState);
    final backupJson = const JsonEncoder.withIndent('  ').convert(backupData);
    final jsonBytes = utf8.encode(backupJson);
    final archive = Archive();
    archive.addFile(ArchiveFile(
      'flux_news_settings_backup_$timestamp.json',
      jsonBytes.length,
      jsonBytes,
    ));
    return ZipEncoder().encode(archive);
  }

  static Future<Map<String, Object?>> createBackupData(
      FluxNewsState appState) async {
    await syncCurrentFeedSettingsOverridesFromDB(appState);
    final storageSettings = await appState.storage.readAll();
    storageSettings.remove(storedBackupPasswordKey);
    storageSettings.remove(handledAutoBackupFingerprintKey);

    return {
      'backupType': plainBackupType,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'appVersion': FluxNewsState.applicationVersion,
      'settings': storageSettings,
      'feedSettings': <Map<String, Object?>>[],
    };
  }

  static Future<List<int>> encryptBackupBytes(
      List<int> plainBytes, String password) async {
    final salt = _secureRandomBytes(16);
    final nonce = _secureRandomBytes(12);
    final secretKey = await _deriveKey(password, salt);
    final algorithm = AesGcm.with256bits();
    final box = await algorithm.encrypt(
      plainBytes,
      secretKey: secretKey,
      nonce: nonce,
    );
    final payload = {
      'backupType': encryptedBackupType,
      'version': _backupFormatVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'appVersion': FluxNewsState.applicationVersion,
      'kdf': {
        'algorithm': 'argon2id',
        'memory': _argon2Memory,
        'iterations': _argon2Iterations,
        'parallelism': _argon2Parallelism,
        'keyLength': _keyLength,
        'salt': base64Encode(salt),
      },
      'cipher': {
        'algorithm': 'aes-256-gcm',
        'nonce': base64Encode(box.nonce),
        'cipherText': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      },
    };
    return utf8.encode(const JsonEncoder.withIndent('  ').convert(payload));
  }

  static Future<ParsedSettingsBackup> parseBackupFile(
    File backupFile, {
    String? password,
  }) async {
    final bytes = await backupFile.readAsBytes();
    return parseBackupBytes(
      bytes,
      fileName: backupFile.path.split(Platform.pathSeparator).last,
      password: password,
    );
  }

  static Future<ParsedSettingsBackup> parseBackupBytes(
    List<int> bytes, {
    required String fileName,
    String? password,
  }) async {
    final decoded = _tryDecodeJson(bytes);
    if (decoded is Map<String, dynamic> &&
        decoded['backupType'] == encryptedBackupType) {
      if (password == null || password.isEmpty) {
        throw BackupPasswordRequiredException();
      }
      final decrypted = await decryptBackupBytes(decoded, password);
      final parsed = await _parsePlainZipBytes(decrypted, fileName: fileName);
      return ParsedSettingsBackup(
        fileName: parsed.fileName,
        backupType: parsed.backupType,
        createdAt: parsed.createdAt,
        appVersion: parsed.appVersion,
        settings: parsed.settings,
        feedSettings: parsed.feedSettings,
        encrypted: true,
      );
    }
    return _parsePlainZipBytes(bytes, fileName: fileName);
  }

  static Future<List<int>> decryptBackupBytes(
      Map<String, dynamic> encryptedBackup, String password) async {
    try {
      final kdf = Map<String, dynamic>.from(encryptedBackup['kdf'] as Map);
      final cipher =
          Map<String, dynamic>.from(encryptedBackup['cipher'] as Map);
      final salt = base64Decode(kdf['salt']?.toString() ?? '');
      final nonce = base64Decode(cipher['nonce']?.toString() ?? '');
      final cipherText = base64Decode(cipher['cipherText']?.toString() ?? '');
      final mac = base64Decode(cipher['mac']?.toString() ?? '');
      final secretKey = await _deriveKey(
        password,
        salt,
        memory: _toInt(kdf['memory'], _argon2Memory),
        iterations: _toInt(kdf['iterations'], _argon2Iterations),
        parallelism: _toInt(kdf['parallelism'], _argon2Parallelism),
      );
      final algorithm = AesGcm.with256bits();
      return await algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: secretKey,
      );
    } on BackupPasswordInvalidException {
      rethrow;
    } catch (_) {
      throw BackupPasswordInvalidException();
    }
  }

  static Future<void> restoreBackup(
      FluxNewsState appState, ParsedSettingsBackup parsed) async {
    final storageEntries = parsed.settings;
    for (final entry in storageEntries.entries) {
      await appState.storage
          .write(key: entry.key, value: entry.value?.toString());
    }

    if (parsed.feedSettings.isNotEmpty) {
      final oldBackupOverrides = <String, dynamic>{};
      for (final feedMap in parsed.feedSettings) {
        final feedID = _toInt(feedMap['feedID'], 0);
        if (feedID <= 0) continue;
        oldBackupOverrides[feedID.toString()] =
            feedSettingsOverrideFromMap(feedMap);
      }
      if (oldBackupOverrides.isNotEmpty) {
        final restoredOverrides = await readFeedSettingsOverrides(appState);
        await writeFeedSettingsOverrides(appState, {
          ...oldBackupOverrides,
          ...restoredOverrides,
        });
      }
    }

    await applyFeedSettingsOverridesToDB(appState);
  }

  static Future<bool> maybePromptForAndroidAutoBackupRestore(
    BuildContext context,
    FluxNewsState appState, {
    bool ignoreHandledFingerprint = false,
    bool showNoBackupMessage = false,
  }) async {
    debugPrint(
        'SettingsBackupService: maybePromptForAndroidAutoBackupRestore started. '
        'platform=${Platform.operatingSystem} mounted=${context.mounted}');
    if (!Platform.isAndroid || !context.mounted) return false;
    final localizations = AppLocalizations.of(context)!;
    final file = await findPendingAndroidAutoBackupRestore(
      appState,
      ignoreHandledFingerprint: ignoreHandledFingerprint,
    );
    if (file == null || !context.mounted) {
      debugPrint(
          'SettingsBackupService: No pending Android auto backup restore file available.');
      if (showNoBackupMessage && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.noAndroidAutoBackupFound)),
        );
      }
      return false;
    }

    debugPrint(
        'SettingsBackupService: Showing Android auto backup restore prompt.');
    logThis('SettingsBackupService',
        'Showing Android auto backup restore prompt.', LogLevel.INFO);
    final wantsRestore = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(localizations.androidAutoBackupFoundTitle),
        content: Text(localizations.androidAutoBackupFoundMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(localizations.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(localizations.restore),
          ),
        ],
      ),
    );
    if (wantsRestore != true) {
      debugPrint(
          'SettingsBackupService: User dismissed Android auto backup restore prompt.');
      logThis(
          'SettingsBackupService',
          'User dismissed Android auto backup restore prompt. Marking file as handled.',
          LogLevel.INFO);
      await markAndroidAutoBackupHandled(appState, file);
      return false;
    }
    if (!context.mounted) return false;
    try {
      ParsedSettingsBackup parsed;
      BackupPasswordResult? password;
      try {
        debugPrint(
            'SettingsBackupService: Parsing Android auto backup file without password.');
        logThis(
            'SettingsBackupService',
            'Parsing Android auto backup file without password.',
            LogLevel.INFO);
        parsed = await parseBackupFile(file);
      } on BackupPasswordRequiredException {
        debugPrint(
            'SettingsBackupService: Android auto backup is encrypted. Prompting for backup password.');
        logThis(
            'SettingsBackupService',
            'Android auto backup is encrypted. Prompting for backup password.',
            LogLevel.INFO);
        if (!context.mounted) return false;
        password = await promptForBackupPassword(
          context,
          title: localizations.backupPassword,
          confirmPassword: false,
        );
        if (password == null || !context.mounted) {
          debugPrint(
              'SettingsBackupService: Android auto backup password prompt was cancelled.');
          logThis(
              'SettingsBackupService',
              'Android auto backup password prompt was cancelled.',
              LogLevel.INFO);
          return false;
        }
        debugPrint(
            'SettingsBackupService: Parsing encrypted Android auto backup file with entered password.');
        logThis(
            'SettingsBackupService',
            'Parsing encrypted Android auto backup file with entered password.',
            LogLevel.INFO);
        parsed = await parseBackupFile(file, password: password.password);
      }
      if (!context.mounted) return false;
      debugPrint('SettingsBackupService: Restoring Android auto backup. '
          'encrypted=${parsed.encrypted} settings=${parsed.settingsCount} '
          'legacyFeedSettings=${parsed.feedSettingsCount}');
      logThis(
          'SettingsBackupService',
          'Restoring Android auto backup. encrypted=${parsed.encrypted} '
              'settings=${parsed.settingsCount} legacyFeedSettings=${parsed.feedSettingsCount}',
          LogLevel.INFO);
      await restoreBackup(appState, parsed);
      if (password != null && password.password.isNotEmpty) {
        await writeStoredBackupPassword(appState, password.password);
      }
      await markAndroidAutoBackupHandled(appState, file);
      if (!await appState.readConfigValues()) {
        logThis(
            'SettingsBackupService',
            'Android auto backup was restored, but restored settings could '
                'not be read from secure storage',
            LogLevel.ERROR);
        return false;
      }
      if (context.mounted) {
        appState.readConfig(context);
        appState.readThemeConfigValues(context);
      }
      appState.syncNow = true;
      appState.refreshView();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.backupSuccessfullyRestored)),
        );
        Navigator.pushNamedAndRemoveUntil(
            context, FluxNewsState.rootRouteString, (route) => false);
      }
      return true;
    } on BackupPasswordInvalidException {
      debugPrint(
          'SettingsBackupService: Android auto backup password was invalid.');
      logThis('SettingsBackupService',
          'Android auto backup password was invalid.', LogLevel.WARNING);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.backupPasswordInvalid)),
        );
      }
      return false;
    } catch (e) {
      debugPrint(
          'SettingsBackupService: Android auto backup restore failed: $e');
      logThis('SettingsBackupService', 'Android auto backup restore failed: $e',
          LogLevel.ERROR);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.restoreFailed)),
        );
      }
      return false;
    }
  }

  static Future<BackupPasswordResult?> promptForBackupPassword(
    BuildContext context, {
    required String title,
    bool confirmPassword = true,
    bool allowUnencryptedBackup = false,
  }) async {
    final localizations = AppLocalizations.of(context)!;
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    var unencryptedBackup = false;
    String? errorText;

    final result = await showDialog<BackupPasswordResult>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(builder: (context, setState) {
          void setUnencrypted(bool value) {
            setState(() {
              unencryptedBackup = value;
              if (unencryptedBackup) errorText = null;
            });
          }

          void submit() {
            final password = passwordController.text;
            if (!unencryptedBackup && password.isEmpty) {
              setState(() => errorText = localizations.backupPasswordRequired);
              return;
            }
            if (!unencryptedBackup &&
                confirmPassword &&
                password != confirmController.text) {
              setState(() => errorText = localizations.backupPasswordMismatch);
              return;
            }
            Navigator.pop(
              dialogContext,
              BackupPasswordResult(
                password: unencryptedBackup ? '' : password,
                unencrypted: unencryptedBackup,
              ),
            );
          }

          if (Platform.isIOS) {
            return CupertinoAlertDialog(
              title: Text(title, textAlign: TextAlign.left),
              content: DefaultTextStyle.merge(
                textAlign: TextAlign.left,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (allowUnencryptedBackup) ...[
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(localizations.createUnencryptedBackup),
                                  const SizedBox(height: 3),
                                  Text(
                                    localizations
                                        .createUnencryptedBackupWarning,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: CupertinoColors.secondaryLabel,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            CupertinoSwitch(
                              value: unencryptedBackup,
                              onChanged: setUnencrypted,
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      CupertinoTextField(
                        controller: passwordController,
                        obscureText: true,
                        enabled: !unencryptedBackup,
                        placeholder: localizations.backupPassword,
                        padding: const EdgeInsets.all(10),
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            errorText!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: CupertinoColors.systemRed,
                            ),
                          ),
                        ),
                      ],
                      if (confirmPassword) ...[
                        const SizedBox(height: 8),
                        CupertinoTextField(
                          controller: confirmController,
                          obscureText: true,
                          enabled: !unencryptedBackup,
                          placeholder: localizations.backupPasswordRepeat,
                          padding: const EdgeInsets.all(10),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(localizations.cancel),
                ),
                CupertinoDialogAction(
                  onPressed: submit,
                  child: Text(localizations.ok),
                ),
              ],
            );
          }

          return AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (allowUnencryptedBackup)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: unencryptedBackup,
                      onChanged: setUnencrypted,
                      title: Text(localizations.createUnencryptedBackup),
                      subtitle:
                          Text(localizations.createUnencryptedBackupWarning),
                    ),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    enabled: !unencryptedBackup,
                    decoration: InputDecoration(
                      labelText: localizations.backupPassword,
                      errorText: errorText,
                    ),
                  ),
                  if (confirmPassword)
                    TextField(
                      controller: confirmController,
                      obscureText: true,
                      enabled: !unencryptedBackup,
                      decoration: InputDecoration(
                        labelText: localizations.backupPasswordRepeat,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(localizations.cancel),
              ),
              TextButton(
                onPressed: submit,
                child: Text(localizations.ok),
              ),
            ],
          );
        });
      },
    );
    passwordController.dispose();
    confirmController.dispose();
    return result;
  }

  static Future<SecretKey> _deriveKey(
    String password,
    List<int> salt, {
    int memory = _argon2Memory,
    int iterations = _argon2Iterations,
    int parallelism = _argon2Parallelism,
  }) {
    return Argon2id(
      memory: memory,
      iterations: iterations,
      parallelism: parallelism,
      hashLength: _keyLength,
    ).deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
  }

  static Future<ParsedSettingsBackup> _parsePlainZipBytes(
    List<int> bytes, {
    required String fileName,
  }) async {
    final archive = ZipDecoder().decodeBytes(bytes);

    ArchiveFile? jsonArchiveFile;
    for (final file in archive.files) {
      if (file.isFile && file.name.toLowerCase().endsWith('.json')) {
        jsonArchiveFile = file;
        break;
      }
    }

    if (jsonArchiveFile == null) {
      throw Exception('Found no JSON file in the ZIP.');
    }

    final jsonContent = utf8.decode(jsonArchiveFile.content as List<int>);
    final data = jsonDecode(jsonContent);
    if (data is! Map<String, dynamic>) {
      throw Exception('Invalid backup format.');
    }

    final backupType = data['backupType']?.toString() ?? '';
    if (backupType != plainBackupType) {
      throw Exception('This ZIP is not a Flux News Settings Backup.');
    }

    final settings = data['settings'];
    if (settings is! Map) {
      throw Exception('Settings in the backup are missing or invalid.');
    }

    final feedSettings = data['feedSettings'];
    if (feedSettings is! List) {
      throw Exception('Feed settings in the backup are missing or invalid.');
    }

    final normalizedFeedSettings = <Map<String, dynamic>>[];
    for (final item in feedSettings) {
      if (item is Map) {
        normalizedFeedSettings.add(Map<String, dynamic>.from(item));
      }
    }

    return ParsedSettingsBackup(
      fileName: fileName,
      backupType: backupType,
      createdAt: data['createdAt']?.toString(),
      appVersion: data['appVersion']?.toString(),
      settings: Map<String, dynamic>.from(settings),
      feedSettings: normalizedFeedSettings,
    );
  }

  static Object? _tryDecodeJson(List<int> bytes) {
    try {
      return jsonDecode(utf8.decode(bytes));
    } catch (_) {
      return null;
    }
  }

  static List<int> _secureRandomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  static int _toInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is bool) return value ? 1 : 0;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static Future<String> _fileFingerprint(File file) async {
    final stat = await file.stat();
    return '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
  }
}

class BackupPasswordResult {
  const BackupPasswordResult({
    required this.password,
    required this.unencrypted,
  });

  final String password;
  final bool unencrypted;
}
