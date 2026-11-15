import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/functions/audio_progress_store.dart';
import 'package:flux_news/functions/background_sync_service.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    SecureStorageMock.uninstall();
  });

  test('foreground active marker distinguishes active stale and invalid values',
      () {
    final now = DateTime.parse('2026-07-08T10:00:00Z');

    expect(
      evaluateFluxNewsForegroundActiveMarker(null, now: now),
      FluxNewsForegroundActiveMarkerStatus.missing,
    );
    expect(
      evaluateFluxNewsForegroundActiveMarker('not-a-date', now: now),
      FluxNewsForegroundActiveMarkerStatus.invalid,
    );
    expect(
      evaluateFluxNewsForegroundActiveMarker(
        now.subtract(const Duration(minutes: 1)).toIso8601String(),
        now: now,
      ),
      FluxNewsForegroundActiveMarkerStatus.active,
    );
    expect(
      evaluateFluxNewsForegroundActiveMarker(
        now.subtract(const Duration(minutes: 3)).toIso8601String(),
        now: now,
      ),
      FluxNewsForegroundActiveMarkerStatus.stale,
    );
  });

  test('audio progress migrates legacy secure-storage value to preferences',
      () async {
    SharedPreferences.setMockInitialValues({});
    final key = AudioProgressStore.keyForNews(42);
    final secureStorage = SecureStorageMock({key: '12345'});
    secureStorage.install();

    final value = await AudioProgressStore.read(key);
    final prefs = await SharedPreferences.getInstance();

    expect(value, '12345');
    expect(prefs.getString(key), '12345');
    expect(secureStorage.values.containsKey(key), isFalse);
  });

  test('audio progress prefers shared preferences over legacy storage',
      () async {
    final key = AudioProgressStore.keyForNews(43);
    SharedPreferences.setMockInitialValues({key: 'pref-value'});
    final secureStorage = SecureStorageMock({key: 'legacy-value'});
    secureStorage.install();

    final value = await AudioProgressStore.read(key);

    expect(value, 'pref-value');
    expect(secureStorage.values[key], 'legacy-value');
  });

  test('audio progress write stores preferences and deletes legacy value',
      () async {
    SharedPreferences.setMockInitialValues({});
    final key = '${FluxNewsState.audioProgressKeyPrefix}44';
    final secureStorage = SecureStorageMock({key: 'legacy-value'});
    secureStorage.install();

    await AudioProgressStore.write(key, '67890');
    final prefs = await SharedPreferences.getInstance();

    expect(prefs.getString(key), '67890');
    expect(secureStorage.values.containsKey(key), isFalse);
  });
}
