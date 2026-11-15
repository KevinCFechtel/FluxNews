import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/functions/settings_backup_service.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late SecureStorageMock secureStorage;

  setUp(() async {
    database = await createFluxNewsTestDatabase();
    secureStorage = SecureStorageMock({
      FluxNewsState.secureStorageMinifluxURLKey: 'https://miniflux.example/v1/',
      FluxNewsState.secureStorageMinifluxAPIKey: 'secret',
      SettingsBackupService.storedBackupPasswordKey: 'do-not-export',
      SettingsBackupService.handledAutoBackupFingerprintKey: 'handled',
    });
    secureStorage.install();
  });

  tearDown(() async {
    SecureStorageMock.uninstall();
    await database.close();
  });

  test('plain backup includes settings but excludes internal backup keys',
      () async {
    final appState = FluxNewsState()..db = database;

    final bytes = await SettingsBackupService.createPlainZipBackupBytes(
      appState,
      timestamp: 1,
    );
    final parsed = await SettingsBackupService.parseBackupBytes(
      bytes,
      fileName: 'backup.fnbak',
    );

    expect(parsed.encrypted, isFalse);
    expect(
        parsed.settings[FluxNewsState.secureStorageMinifluxAPIKey], 'secret');
    expect(
      parsed.settings,
      isNot(containsPair(
          SettingsBackupService.storedBackupPasswordKey, anything)),
    );
    expect(
      parsed.settings,
      isNot(containsPair(
          SettingsBackupService.handledAutoBackupFingerprintKey, anything)),
    );
  });

  test('encrypted backup requires and validates password', () async {
    final plainBytes = await SettingsBackupService.createPlainZipBackupBytes(
      FluxNewsState()..db = database,
      timestamp: 2,
    );
    final encryptedBytes =
        await SettingsBackupService.encryptBackupBytes(plainBytes, 'pass');

    expect(
      () => SettingsBackupService.parseBackupBytes(
        encryptedBytes,
        fileName: 'encrypted.fnbak',
      ),
      throwsA(isA<BackupPasswordRequiredException>()),
    );
    expect(
      () => SettingsBackupService.parseBackupBytes(
        encryptedBytes,
        fileName: 'encrypted.fnbak',
        password: 'wrong',
      ),
      throwsA(isA<BackupPasswordInvalidException>()),
    );

    final parsed = await SettingsBackupService.parseBackupBytes(
      encryptedBytes,
      fileName: 'encrypted.fnbak',
      password: 'pass',
    );
    expect(parsed.encrypted, isTrue);
    expect(
        parsed.settings[FluxNewsState.secureStorageMinifluxAPIKey], 'secret');
  });

  test('restore applies settings and legacy feed settings overrides', () async {
    await insertTestFeed(database, feedID: 1, title: 'Feed');
    final appState = FluxNewsState()..db = database;
    final parsed = ParsedSettingsBackup(
      fileName: 'legacy.fnbak',
      backupType: SettingsBackupService.plainBackupType,
      settings: {
        FluxNewsState.secureStorageMinifluxURLKey:
            'https://restored.example/v1/',
      },
      feedSettings: [
        {
          'feedID': 1,
          'manualTruncate': 1,
          'preferParagraph': 1,
          'preferAttachmentImage': 0,
          'manualAdaptLightModeToIcon': 1,
          'manualAdaptDarkModeToIcon': 0,
          'openMinifluxEntry': 1,
          'expandedWithFulltext': 1,
          'expandedFulltextLimit': 800,
        },
      ],
    );

    await SettingsBackupService.restoreBackup(appState, parsed);

    expect(
      secureStorage.values[FluxNewsState.secureStorageMinifluxURLKey],
      'https://restored.example/v1/',
    );
    final overrides = jsonDecode(
      secureStorage
          .values[FluxNewsState.secureStorageFeedSettingsOverridesKey]!,
    ) as Map<String, dynamic>;
    expect(overrides['1']['manualTruncate'], 1);

    final rows = await database.query(
      'feeds',
      where: 'feedID = ?',
      whereArgs: [1],
    );
    expect(rows.single['manualTruncate'], 1);
    expect(rows.single['preferParagraph'], 1);
    expect(rows.single['expandedFulltextLimit'], 800);
  });
}
