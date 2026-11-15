import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/state_management/flux_news_theme_state.dart';
import 'package:flux_news/ui/ios_overlay_drawer.dart';
import 'package:provider/provider.dart';

void main() {
  group('iOS overlay drawer width', () {
    test('uses 88 percent of a compact phone width', () {
      expect(iosOverlayDrawerWidth(320), closeTo(281.6, 0.001));
      expect(iosOverlayDrawerWidth(390), closeTo(343.2, 0.001));
    });

    test('caps the surface on wider compact layouts', () {
      expect(iosOverlayDrawerWidth(430), 360);
      expect(iosOverlayDrawerWidth(800), 360);
    });
  });

  testWidgets('keeps Drawer behavior behind the floating glass surface',
      (tester) async {
    final scaffoldKey = GlobalKey<ScaffoldState>();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FluxNewsThemeState(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            key: scaffoldKey,
            drawer: const IOSOverlayDrawer(
              child: Text('Navigation content'),
            ),
            body: const SizedBox.expand(),
          ),
        ),
      ),
    );

    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();

    final drawer = tester.widget<Drawer>(find.byType(Drawer));
    expect(drawer.width, closeTo(343.2, 0.001));
    expect(drawer.backgroundColor, Colors.transparent);
    expect(find.text('Navigation content'), findsOneWidget);
  });
}
