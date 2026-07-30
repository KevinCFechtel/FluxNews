import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all Dart asset references exist', () {
    final missingAssets = <String>{};
    final assetPattern = RegExp(r'''['"](assets/[^'"]+)['"]''');

    for (final entity
        in Directory('lib').listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final match in assetPattern.allMatches(source)) {
        final assetPath = match.group(1)!;
        if (!File(assetPath).existsSync()) {
          missingAssets.add(assetPath);
        }
      }
    }

    expect(missingAssets, isEmpty);
  });
}
