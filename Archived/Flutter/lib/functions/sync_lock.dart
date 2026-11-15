import 'dart:async';
import 'dart:io';

import 'package:flux_news/functions/logging.dart';
import 'package:path_provider/path_provider.dart';

class FluxNewsSyncLock {
  FluxNewsSyncLock._(this._file, this._token, this.owner) {
    _heartbeat = Timer.periodic(heartbeatInterval, (_) => _refreshLease());
  }

  static const Duration staleAfter = Duration(minutes: 10);
  static const Duration heartbeatInterval = Duration(minutes: 1);
  static const String _lockFileName = 'flux_news_sync.lock';

  final File _file;
  final String _token;
  final String owner;
  Timer? _heartbeat;

  static Future<FluxNewsSyncLock?> tryAcquire(String owner) async {
    final supportDirectory = await getApplicationSupportDirectory();
    final file = File('${supportDirectory.path}/$_lockFileName');
    final token = '${DateTime.now().toIso8601String()}|$owner|$pid|'
        '${DateTime.now().microsecondsSinceEpoch}';

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
    final age = DateTime.now().difference(file.statSync().modified);
    final shouldRemove = age > staleAfter;

    if (!shouldRemove) {
      return false;
    }

    try {
      await file.delete();
      logThis(
          'syncLock',
          'Removed stale sync lock'
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
      if (parts.length != 3 && parts.length != 4) return null;

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
    _heartbeat?.cancel();
    _heartbeat = null;
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

  Future<void> _refreshLease() async {
    try {
      if (!await _file.exists()) return;
      if (await _file.readAsString() != _token) {
        _heartbeat?.cancel();
        _heartbeat = null;
        return;
      }
      await _file.setLastModified(DateTime.now());
    } catch (e) {
      logThis('syncLock', 'Could not refresh sync lock lease for $owner: $e',
          LogLevel.WARNING);
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
