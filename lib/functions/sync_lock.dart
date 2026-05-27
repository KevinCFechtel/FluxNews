import 'dart:io';

import 'package:flutter_logs/flutter_logs.dart';
import 'package:flux_news/functions/logging.dart';
import 'package:path_provider/path_provider.dart';

class FluxNewsSyncLock {
  FluxNewsSyncLock._(this._file, this._token, this.owner);

  static const Duration staleAfter = Duration(minutes: 10);
  static const String _lockFileName = 'flux_news_sync.lock';
  static bool _activeInIsolate = false;

  final File _file;
  final String _token;
  final String owner;

  static Future<FluxNewsSyncLock?> tryAcquire(String owner) async {
    final supportDirectory = await getApplicationSupportDirectory();
    final file = File('${supportDirectory.path}/$_lockFileName');
    final token = '${DateTime.now().toIso8601String()}|$owner|$pid';

    if (file.existsSync()) {
      final removed = await _removeStaleOrOrphanedLock(file);
      if (!removed && file.existsSync()) {
        final details = await _readLockDetails(file);
        logThis(
            'syncLock',
            'Sync lock already held; skipping $owner sync'
                '${details == null ? '' : ' (${details.describe()})'}',
            LogLevel.INFO);
        return null;
      }
    }

    try {
      file.createSync(exclusive: true);
      file.writeAsStringSync(token, flush: true);
      _activeInIsolate = true;
      logThis('syncLock', 'Acquired sync lock for $owner', LogLevel.INFO);
      return FluxNewsSyncLock._(file, token, owner);
    } on FileSystemException {
      final details = await _readLockDetails(file);
      logThis(
          'syncLock',
          'Sync lock already held; skipping $owner sync'
              '${details == null ? '' : ' (${details.describe()})'}',
          LogLevel.INFO);
      return null;
    }
  }

  static Future<bool> _removeStaleOrOrphanedLock(File file) async {
    final details = await _readLockDetails(file);
    final now = DateTime.now();
    final age = details == null
        ? now.difference(file.statSync().modified)
        : now.difference(details.createdAt);
    final samePid = details?.pid == pid;
    final shouldRemove = age > staleAfter || (samePid && !_activeInIsolate);

    if (!shouldRemove) {
      return false;
    }

    try {
      await file.delete();
      logThis(
          'syncLock',
          'Removed ${age > staleAfter ? 'stale' : 'orphaned same-process'} sync lock'
              '${details == null ? '' : ' (${details.describe()})'} '
              'ageSeconds=${age.inSeconds}',
          LogLevel.WARNING);
      return true;
    } catch (e) {
      logThis(
          'syncLock', 'Could not remove stale sync lock: $e', LogLevel.WARNING);
      return false;
    }
  }

  static Future<_SyncLockDetails?> _readLockDetails(File file) async {
    try {
      final value = await file.readAsString();
      final parts = value.trim().split('|');
      if (parts.length != 3) return null;

      final createdAt = DateTime.tryParse(parts[0]);
      final lockPid = int.tryParse(parts[2]);
      if (createdAt == null || lockPid == null) return null;

      return _SyncLockDetails(
        createdAt: createdAt,
        owner: parts[1],
        pid: lockPid,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> release() async {
    try {
      if (!_file.existsSync()) return;
      final currentToken = await _file.readAsString();
      if (currentToken == _token) {
        await _file.delete();
        _activeInIsolate = false;
        logThis('syncLock', 'Released sync lock for $owner', LogLevel.INFO);
      }
    } catch (e) {
      logThis('syncLock', 'Could not release sync lock for $owner: $e',
          LogLevel.WARNING);
    } finally {
      _activeInIsolate = false;
    }
  }
}

class _SyncLockDetails {
  const _SyncLockDetails({
    required this.createdAt,
    required this.owner,
    required this.pid,
  });

  final DateTime createdAt;
  final String owner;
  final int pid;

  String describe() {
    final age = DateTime.now().difference(createdAt);
    return 'owner=$owner pid=$pid ageSeconds=${age.inSeconds}';
  }
}
