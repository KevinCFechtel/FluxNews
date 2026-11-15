import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/functions/audio_download_service.dart';
import 'package:flux_news/state_management/flux_news_state.dart';

import 'test_helpers.dart';

const MethodChannel _pathProviderChannel =
    MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory appSupportDirectory;
  late Directory audioDirectory;
  late Directory artworkDirectory;
  late SecureStorageMock secureStorage;

  setUp(() async {
    appSupportDirectory =
        await Directory.systemTemp.createTemp('flux-news-audio-cleanup-');
    audioDirectory = Directory(
        '${appSupportDirectory.path}/${FluxNewsState.audioCachePath}');
    artworkDirectory = Directory(
        '${appSupportDirectory.path}/${FluxNewsState.artworkCacheDirectoryName}');
    await audioDirectory.create(recursive: true);
    await artworkDirectory.create(recursive: true);

    await File('${audioDirectory.path}/audio_42_1.mp3').writeAsBytes([1]);
    await File('${audioDirectory.path}/audio_42_2.mp3').writeAsBytes([2]);
    await File('${audioDirectory.path}/audio_orphan.mp3').writeAsBytes([3]);
    await File('${audioDirectory.path}/keep.txt').writeAsString('keep');
    await File('${artworkDirectory.path}/artwork_42.png').writeAsBytes([4]);

    secureStorage = SecureStorageMock({
      '${FluxNewsState.downloadPathKeyPrefix}42':
          '${audioDirectory.path}/audio_42_2.mp3',
      '${FluxNewsState.downloadPathByUrlKeyPrefix}encoded': 'path',
      '${FluxNewsState.downloadTimestampKeyPrefix}42': '2026-07-27',
      '${FluxNewsState.downloadSkippedKeyPrefix}42': 'true',
      '${FluxNewsState.downloadTitleKeyPrefix}42': 'Episode',
      '${FluxNewsState.downloadFeedTitleKeyPrefix}42': 'Feed',
      'unrelated_setting': 'keep',
    });
    secureStorage.install();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
      if (call.method == 'getApplicationSupportDirectory') {
        return appSupportDirectory.path;
      }
      return null;
    });
  });

  tearDown(() async {
    SecureStorageMock.uninstall();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    if (await appSupportDirectory.exists()) {
      await appSupportDirectory.delete(recursive: true);
    }
  });

  test('delete all removes audio files, artwork, and download metadata',
      () async {
    await AudioDownloadService.deleteAllDownloadedAudios();

    final remainingAudioEntries =
        await audioDirectory.list(followLinks: false).toList();
    expect(
      remainingAudioEntries.whereType<File>().map((file) => file.path),
      [endsWith('keep.txt')],
    );
    expect(await artworkDirectory.exists(), isFalse);
    expect(secureStorage.values, {'unrelated_setting': 'keep'});
  });
}
