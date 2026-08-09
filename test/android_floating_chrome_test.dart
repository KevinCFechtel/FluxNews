import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/state_management/flux_news_counter_state.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:flux_news/ui/android_floating_chrome.dart';
import 'package:flux_news/ui/flux_news_body.dart';
import 'package:provider/provider.dart';

Widget _testApp(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  );
}

Widget _menuTestApp(FluxNewsState appState) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<FluxNewsState>.value(value: appState),
      ChangeNotifierProvider<FluxNewsCounterState>(
        create: (_) => FluxNewsCounterState(),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Row(
            mainAxisSize: MainAxisSize.min,
            children: const FluxNewsBody().appBarButtons(context),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('status bar scrim blurs and fades over scrolling cards',
      (tester) async {
    await tester.pumpWidget(_testApp(const SizedBox(
      height: 40,
      width: 320,
      child: AndroidFloatingStatusBarScrim(),
    )));

    expect(find.byType(BackdropFilter), findsOneWidget);
    final decoratedBox = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
    final decoration = decoratedBox.decoration as BoxDecoration;
    final gradient = decoration.gradient as LinearGradient;
    expect(gradient.colors, hasLength(3));
    expect(
      gradient.colors.first,
      Theme.of(tester.element(find.byType(AndroidFloatingStatusBarScrim)))
          .scaffoldBackgroundColor
          .withValues(alpha: 0.92),
    );
    expect(gradient.colors.last.a, 0);
  });

  testWidgets('floating header uses the current displayed news count',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_testApp(const AndroidFloatingFeedHeader(
        title: 'Feed One',
        newsCount: 12,
        showCount: true,
      )));

      expect(find.text('Feed One'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('12')).label,
        contains('Count: 12'),
      );
      expect(find.byType(AndroidFloatingSurface), findsNWidgets(2));
      final surfaces = tester.widgetList<AndroidFloatingSurface>(
        find.byType(AndroidFloatingSurface),
      );
      expect(surfaces.every((surface) => surface.accentColor != null), isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('floating header keeps the existing count visibility setting',
      (tester) async {
    await tester.pumpWidget(_testApp(const SizedBox(
      width: 360,
      child: AndroidFloatingFeedHeader(
        title: 'Feed One',
        newsCount: 12,
        showCount: false,
      ),
    )));

    expect(find.text('Feed One'), findsOneWidget);
    expect(find.text('12'), findsNothing);
    expect(find.byType(AndroidFloatingSurface), findsOneWidget);
    expect(
      tester.getSize(find.byType(AndroidFloatingSurface)).width,
      lessThan(360),
    );
  });

  testWidgets('long floating title stays within the available header width',
      (tester) async {
    await tester.pumpWidget(_testApp(const SizedBox(
      width: 280,
      child: AndroidFloatingFeedHeader(
        title: 'A very long feed title that cannot fit at its natural width',
        newsCount: 123,
        showCount: true,
      ),
    )));

    expect(find.text('123'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final countSurface = find.ancestor(
      of: find.text('123'),
      matching: find.byType(AndroidFloatingSurface),
    );
    expect(
      tester.getSize(find.byType(AndroidFloatingFeedHeader)).width,
      280,
    );
    expect(
      tester.getTopRight(countSurface).dx,
      tester.getTopRight(find.byType(AndroidFloatingFeedHeader)).dx,
    );
  });

  testWidgets('floating toolbar renders the supplied actions', (tester) async {
    await tester.pumpWidget(_testApp(AndroidFloatingToolbar(
      children: [
        IconButton(onPressed: () {}, icon: const Icon(Icons.menu)),
        IconButton(onPressed: () {}, icon: const Icon(Icons.refresh)),
        IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert)),
      ],
    )));

    expect(find.byIcon(Icons.menu), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    expect(
      tester
          .widget<AndroidFloatingSurface>(
            find.byType(AndroidFloatingSurface),
          )
          .accentColor,
      Theme.of(tester.element(find.byType(AndroidFloatingToolbar)))
          .colorScheme
          .primary,
    );
  });

  testWidgets('floating toolbar scrolls additional actions on narrow screens',
      (tester) async {
    await tester.pumpWidget(_testApp(SizedBox(
      width: 240,
      child: AndroidFloatingToolbar(
        children: [
          for (final icon in const <IconData>[
            Icons.menu,
            Icons.check_circle_outline,
            Icons.podcasts,
            Icons.search,
            Icons.settings,
            Icons.refresh,
            Icons.more_vert,
          ])
            IconButton(onPressed: () {}, icon: Icon(icon)),
        ],
      ),
    )));

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded floating toolbar removes its duplicates from More',
      (tester) async {
    final appState = FluxNewsState()
      ..appBarType = FluxNewsState.appBarFloatingType
      ..androidFloatingToolbarShortcuts = true;
    await tester.pumpWidget(_menuTestApp(appState));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Show all news'), findsOneWidget);
    expect(find.text('Oldest first'), findsOneWidget);
    expect(find.text('Search'), findsNothing);
    expect(find.text('Mark all news as read'), findsNothing);
    expect(find.text('Podcasts'), findsNothing);
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('More stays complete outside expanded floating mode',
      (tester) async {
    final appState = FluxNewsState()
      ..appBarType = FluxNewsState.appBarNormalType
      ..androidFloatingToolbarShortcuts = true;
    await tester.pumpWidget(_menuTestApp(appState));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Mark all news as read'), findsOneWidget);
    expect(find.text('Podcasts'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
