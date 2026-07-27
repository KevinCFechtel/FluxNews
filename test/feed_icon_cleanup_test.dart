import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/state_management/flux_news_state.dart';

void main() {
  late Directory externalDirectory;
  late FluxNewsState appState;

  setUp(() async {
    externalDirectory =
        await Directory.systemTemp.createTemp('flux-news-icon-cleanup-');
    appState = FluxNewsState()..externalDirectory = externalDirectory;

    final iconDirectory = Directory('${externalDirectory.path}/FeedIcons');
    await iconDirectory.create(recursive: true);
    await File('${iconDirectory.path}/icon_1').writeAsBytes([1]);
    await File('${iconDirectory.path}/icon_2').writeAsBytes([2]);
    await File('${externalDirectory.path}/keep.txt').writeAsString('keep');
  });

  tearDown(() async {
    appState.dispose();
    if (await externalDirectory.exists()) {
      await externalDirectory.delete(recursive: true);
    }
  });

  test('deletes only the feed icon directory and can run repeatedly', () async {
    await appState.deleteAllFeedIconFiles();
    await appState.deleteAllFeedIconFiles();

    expect(
      await Directory('${externalDirectory.path}/FeedIcons').exists(),
      isFalse,
    );
    expect(await File('${externalDirectory.path}/keep.txt').readAsString(),
        'keep');
  });
}
