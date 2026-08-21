import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/ui/adaptive_feed_icon.dart';

const _contrastSurfaceKey = ValueKey<String>('feed-icon-contrast-surface');

Future<Uint8List> _png(
    {required Color color, required bool transparent}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    transparent
        ? const Rect.fromLTWH(8, 8, 16, 16)
        : const Rect.fromLTWH(0, 0, 32, 32),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(32, 32);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Widget _app(Widget child, {Brightness brightness = Brightness.dark}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Scaffold(body: Center(child: child)),
  );
}

Future<bool> _analyze(
  WidgetTester tester, {
  required Uint8List bytes,
  required String mimeType,
  required int feedIconID,
}) async {
  return (await tester.runAsync(
    () => FeedIconContrastAnalyzer.analyze(
      bytes: bytes,
      mimeType: mimeType,
      feedIconID: feedIconID,
    ),
  ))!;
}

Future<Uint8List> _createPng(
  WidgetTester tester, {
  required Color color,
  required bool transparent,
}) async {
  return (await tester.runAsync(
    () => _png(color: color, transparent: transparent),
  ))!;
}

void main() {
  setUp(FeedIconContrastAnalyzer.clearCache);

  testWidgets('dark transparent raster icon gets a light contrast surface',
      (tester) async {
    final bytes = await _createPng(
      tester,
      color: Colors.black,
      transparent: true,
    );
    expect(
      await _analyze(
        tester,
        bytes: bytes,
        mimeType: 'image/png',
        feedIconID: 1,
      ),
      isTrue,
    );
    await tester.pumpWidget(_app(AdaptiveFeedIcon(
      bytes: bytes,
      mimeType: 'image/png',
      size: 16,
      feedIconID: 1,
      automaticContrastEnabled: true,
      manualAdaptLightMode: false,
      manualAdaptDarkMode: false,
    )));
    await tester.pump();

    expect(find.byKey(_contrastSurfaceKey), findsOneWidget);
    expect(tester.widget<Image>(find.byType(Image)).gaplessPlayback, isTrue);
    final surface = tester.widget<Container>(find.byKey(_contrastSurfaceKey));
    final color = (surface.decoration! as BoxDecoration).color!;
    expect(color.computeLuminance(), greaterThan(0.5));
  });

  testWidgets('opaque dark raster icon keeps its original presentation',
      (tester) async {
    final bytes = await _createPng(
      tester,
      color: Colors.black,
      transparent: false,
    );
    expect(
      await _analyze(
        tester,
        bytes: bytes,
        mimeType: 'image/png',
        feedIconID: 2,
      ),
      isFalse,
    );
    await tester.pumpWidget(_app(AdaptiveFeedIcon(
      bytes: bytes,
      mimeType: 'image/png',
      size: 16,
      feedIconID: 2,
      automaticContrastEnabled: true,
      manualAdaptLightMode: false,
      manualAdaptDarkMode: false,
    )));
    await tester.pump();

    expect(find.byKey(_contrastSurfaceKey), findsNothing);
  });

  testWidgets('light transparent raster icon needs no dark-mode surface',
      (tester) async {
    final bytes = await _createPng(
      tester,
      color: Colors.white,
      transparent: true,
    );
    expect(
      await _analyze(
        tester,
        bytes: bytes,
        mimeType: 'image/png',
        feedIconID: 3,
      ),
      isFalse,
    );
    await tester.pumpWidget(_app(AdaptiveFeedIcon(
      bytes: bytes,
      mimeType: 'image/png',
      size: 16,
      feedIconID: 3,
      automaticContrastEnabled: true,
      manualAdaptLightMode: false,
      manualAdaptDarkMode: false,
    )));
    await tester.pump();

    expect(find.byKey(_contrastSurfaceKey), findsNothing);
  });

  testWidgets('dark transparent SVG gets the same contrast treatment',
      (tester) async {
    final bytes = Uint8List.fromList('''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
        <circle cx="16" cy="16" r="8" fill="#111111" />
      </svg>
    '''
        .codeUnits);
    expect(
      await _analyze(
        tester,
        bytes: bytes,
        mimeType: 'image/svg+xml',
        feedIconID: 4,
      ),
      isTrue,
    );
    await tester.pumpWidget(_app(AdaptiveFeedIcon(
      bytes: bytes,
      mimeType: 'image/svg+xml',
      size: 16,
      feedIconID: 4,
      automaticContrastEnabled: true,
      manualAdaptLightMode: false,
      manualAdaptDarkMode: false,
    )));
    await tester.pump();

    expect(find.byKey(_contrastSurfaceKey), findsOneWidget);
  });

  testWidgets('automatic contrast surface is dark-mode only', (tester) async {
    final bytes = await _createPng(
      tester,
      color: Colors.black,
      transparent: true,
    );
    expect(
      await _analyze(
        tester,
        bytes: bytes,
        mimeType: 'image/png',
        feedIconID: 5,
      ),
      isTrue,
    );
    await tester.pumpWidget(_app(
      AdaptiveFeedIcon(
        bytes: bytes,
        mimeType: 'image/png',
        size: 16,
        feedIconID: 5,
        automaticContrastEnabled: true,
        manualAdaptLightMode: false,
        manualAdaptDarkMode: false,
      ),
      brightness: Brightness.light,
    ));
    await tester.pump();

    expect(find.byKey(_contrastSurfaceKey), findsNothing);
  });

  testWidgets('disabled automatic contrast leaves dark icons unchanged',
      (tester) async {
    final bytes = await _createPng(
      tester,
      color: Colors.black,
      transparent: true,
    );
    await tester.pumpWidget(_app(AdaptiveFeedIcon(
      bytes: bytes,
      mimeType: 'image/png',
      size: 16,
      feedIconID: 6,
      automaticContrastEnabled: false,
      manualAdaptLightMode: false,
      manualAdaptDarkMode: false,
    )));
    await tester.pump();

    expect(find.byKey(_contrastSurfaceKey), findsNothing);
    expect(
      FeedIconContrastAnalyzer.cachedResult(
        bytes: bytes,
        mimeType: 'image/png',
        feedIconID: 6,
      ),
      isNull,
    );
  });

  testWidgets('manual feed setting wins when automatic contrast is disabled',
      (tester) async {
    final bytes = await _createPng(
      tester,
      color: Colors.white,
      transparent: true,
    );
    await tester.pumpWidget(_app(AdaptiveFeedIcon(
      bytes: bytes,
      mimeType: 'image/png',
      size: 16,
      feedIconID: 7,
      automaticContrastEnabled: false,
      manualAdaptLightMode: false,
      manualAdaptDarkMode: true,
    )));
    await tester.pump();

    expect(find.byKey(_contrastSurfaceKey), findsOneWidget);
  });
}
