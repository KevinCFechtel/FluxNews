import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/functions/sync_lock.dart';

const MethodChannel _pathProviderChannel =
    MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDirectory;

  setUp(() async {
    supportDirectory =
        await Directory.systemTemp.createTemp('flux-news-sync-lock-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
      if (call.method == 'getApplicationSupportDirectory') {
        return supportDirectory.path;
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    if (await supportDirectory.exists()) {
      await supportDirectory.delete(recursive: true);
    }
  });

  test('only one sync lock is active and release permits the next sync',
      () async {
    final first = await FluxNewsSyncLock.tryAcquire('foreground');
    final blocked = await FluxNewsSyncLock.tryAcquire('background');

    expect(first, isNotNull);
    expect(blocked, isNull);

    await first!.release();
    final next = await FluxNewsSyncLock.tryAcquire('background');
    expect(next, isNotNull);
    await next!.release();
  });

  test('stale lock file is replaced', () async {
    final lockFile = File('${supportDirectory.path}/flux_news_sync.lock');
    final staleDate = DateTime.now().subtract(const Duration(minutes: 11));
    await lockFile.writeAsString(
      '${staleDate.toIso8601String()}|background|999999',
    );

    final lock = await FluxNewsSyncLock.tryAcquire('foreground');

    expect(lock, isNotNull);
    expect(await lockFile.readAsString(), contains('|foreground|'));
    await lock!.release();
  });
}
