import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    as sec_store;
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioProgressStore {
  static final _legacyStorage = sec_store.FlutterSecureStorage(
    iOptions: const sec_store.IOSOptions(
      accessibility: sec_store.KeychainAccessibility.first_unlock,
    ),
  );

  static String keyForNews(int newsID) =>
      '${FluxNewsState.audioProgressKeyPrefix}$newsID';

  static Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(key);
    if (value != null) return value;

    final legacyValue = await _readLegacy(key);
    if (legacyValue != null) {
      await prefs.setString(key, legacyValue);
      await _deleteLegacy(key);
    }
    return legacyValue;
  }

  static Future<void> write(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
    await _deleteLegacy(key);
  }

  static Future<void> delete(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
    await _deleteLegacy(key);
  }

  static Future<String?> _readLegacy(String key) async {
    try {
      return await _legacyStorage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _deleteLegacy(String key) async {
    try {
      await _legacyStorage.delete(key: key);
    } catch (_) {}
  }
}
