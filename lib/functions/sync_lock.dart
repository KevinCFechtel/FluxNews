import 'dart:io';

import 'package:flutter_logs/flutter_logs.dart';
import 'package:flux_news/functions/logging.dart';
import 'package:path_provider/path_provider.dart';

class FluxNewsSyncLock {
  FluxNewsSyncLock._(this._file, this._token, this.owner);

  static const Duration staleAfter = Duration(minutes: 30);
  static const String _lockFileName = 'flux_news_sync.lock';

  final File _file;
  final String _token;
  final String owner;

  static Future<FluxNewsSyncLock?> tryAcquire(String owner) async {
    final supportDirectory = await getApplicationSupportDirectory();
    final file = File('${supportDirectory.path}/$_lockFileName');
    final token = '${DateTime.now().toIso8601String()}|$owner|$pid';

    if (file.existsSync()) {
      final modified = file.statSync().modified;
      if (DateTime.now().difference(modified) > staleAfter) {
        try {
          file.deleteSync();
          logThis('syncLock', 'Removed stale sync lock', LogLevel.WARNING);
        } catch (e) {
          logThis('syncLock', 'Could not remove stale sync lock: $e',
              LogLevel.WARNING);
          return null;
        }
      }
    }

    try {
      file.createSync(exclusive: true);
      file.writeAsStringSync(token, flush: true);
      logThis('syncLock', 'Acquired sync lock for $owner', LogLevel.INFO);
      return FluxNewsSyncLock._(file, token, owner);
    } on FileSystemException {
      logThis('syncLock', 'Sync lock already held; skipping $owner sync',
          LogLevel.INFO);
      return null;
    }
  }

  Future<void> release() async {
    try {
      if (!_file.existsSync()) return;
      final currentToken = await _file.readAsString();
      if (currentToken == _token) {
        await _file.delete();
        logThis('syncLock', 'Released sync lock for $owner', LogLevel.INFO);
      }
    } catch (e) {
      logThis('syncLock', 'Could not release sync lock for $owner: $e',
          LogLevel.WARNING);
    }
  }
}
