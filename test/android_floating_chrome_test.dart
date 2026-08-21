import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/state_management/flux_news_counter_state.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:flux_news/ui/android_floating_chrome.dart';
import 'package:flux_news/ui/floating_chrome_edge_gradient.dart';
import 'package:flux_news/ui/flux_news_body.dart';
import 'package:provider/provider.dart';

Widget _testApp(Widget child, {ThemeData? theme}) {
  return MaterialApp(
    locale: const Locale('en'),
    theme: theme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  );
}

Widget _menuTestApp(
  FluxNewsState appState, {
  bool hideConfiguredFloatingActionsFromMore = false,
  bool showConfiguredFloatingToolbarActions = false,
}) {
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
            children: showConfiguredFloatingToolbarActions
                ? const FluxNewsBody().androidFloatingToolbarButtons(context)
                : const FluxNewsBody().appBarButtons(
                    context,
                    hideConfiguredFloatingActionsFromMore:
                        hideConfiguredFloatingActionsFromMore,
                  ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('category menu keeps previous data while refresh is pending',
      (tester) async {
    final refresh = Completer<Categories>();
    final previous = Categories(categories: [
      Category(
        categoryID: 1,
        title: 'Previous Category',
        feeds: [
          Feed(
            feedID: 10,
            title: 'Previous Feed',
            siteUrl: 'https://example.com/previous',
          ),
        ],
      ),
    ]);
    final appState = FluxNewsState()
      ..actualCategoryList = previous
      ..categoryList = refresh.future;

    await tester.pumpWidget(MultiProvider(
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
        home: const Scaffold(body: CategoryList()),
      ),
    ));

    expect(find.text('Previous Category'), findsOneWidget);
    expect(find.text('All News'), findsOneWidget);

    refresh.complete(Categories(categories: [
      Category(categoryID: 2, title: 'Updated Category'),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('Previous Category'), findsNothing);
    expect(find.text('Updated Category'), findsOneWidget);
  });

  testWidgets('tablet sidebar header uses the Drawer icon and title',
      (tester) async {
    await tester.pumpWidget(_testApp(const SizedBox(
      width: 280,
      child: AndroidTabletSidebarHeader(title: 'Flux News'),
    )));

    expect(find.text('Flux News'), findsOneWidget);
    final icon = tester.widget<FaIcon>(find.byType(FaIcon));
    expect(icon.icon, FontAwesomeIcons.bookOpen.data);
  });

  testWidgets('status bar scrim blurs and fades over scrolling cards',
      (tester) async {
    await tester.pumpWidget(_testApp(const SizedBox(
      height: 40,
      width: 320,
      child: AndroidStatusBarScrim(),
    )));

    expect(find.byType(BackdropFilter), findsOneWidget);
    final decoratedBox = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
    final decoration = decoratedBox.decoration as BoxDecoration;
    final gradient = decoration.gradient as LinearGradient;
    expect(gradient.colors, hasLength(3));
    expect(
      gradient.colors.first,
      Theme.of(tester.element(find.byType(AndroidStatusBarScrim)))
          .scaffoldBackgroundColor
          .withValues(alpha: 0.92),
    );
    expect(gradient.colors.last.a, 0);
  });

  testWidgets('floating top scrim mirrors the curved fade toward the edge',
      (tester) async {
    await tester.pumpWidget(_testApp(const MediaQuery(
      data: MediaQueryData(padding: EdgeInsets.only(top: 24)),
      child: FloatingChromeEdgeGradient(
        edge: FloatingChromeEdge.top,
        chromeExtent: 56,
      ),
    )));

    expect(
      tester.getSize(find.byType(FloatingChromeEdgeGradient)).height,
      105,
    );
    expect(
      find.descendant(
        of: find.byType(FloatingChromeEdgeGradient),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );
    final decoratedBox = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
    final gradient =
        (decoratedBox.decoration as BoxDecoration).gradient as LinearGradient;
    expect(gradient.colors.first.a, greaterThan(gradient.colors.last.a));
    expect(
      gradient.colors.map((color) => color.a),
      floatingChromeGradientLightOpacities.reversed,
    );
    expect(gradient.stops, floatingChromeGradientStops);
  });

  testWidgets('floating bottom scrim follows the real bottom chrome height',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        extendBody: true,
        body: Stack(
          children: [
            PositionedDirectional(
              bottom: 0,
              start: 0,
              end: 0,
              child: FloatingChromeEdgeGradient(
                edge: FloatingChromeEdge.bottom,
              ),
            ),
          ],
        ),
        bottomNavigationBar: SizedBox(height: 80),
      ),
    ));

    expect(
      tester.getSize(find.byType(FloatingChromeEdgeGradient)).height,
      105,
    );
    final decoratedBox = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
    final gradient =
        (decoratedBox.decoration as BoxDecoration).gradient as LinearGradient;
    expect(
      gradient.colors.map((color) => color.a),
      floatingChromeGradientLightOpacities,
    );
    expect(gradient.stops, floatingChromeGradientStops);
  });

  testWidgets('dark floating gradient keeps the stronger opacity curve',
      (tester) async {
    await tester.pumpWidget(_testApp(
      const FloatingChromeEdgeGradient(
        edge: FloatingChromeEdge.bottom,
        chromeExtent: 56,
      ),
      theme: ThemeData.dark(),
    ));

    final decoratedBox = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
    final gradient =
        (decoratedBox.decoration as BoxDecoration).gradient as LinearGradient;
    expect(
      gradient.colors.map((color) => color.a),
      floatingChromeGradientDarkOpacities,
    );
    expect(gradient.stops, floatingChromeGradientStops);
  });

  testWidgets('fixed chrome extent can ignore inherited media padding',
      (tester) async {
    await tester.pumpWidget(_testApp(const MediaQuery(
      data: MediaQueryData(padding: EdgeInsets.only(top: 24)),
      child: FloatingChromeEdgeGradient(
        edge: FloatingChromeEdge.top,
        chromeExtent: 68,
        includeMediaPadding: false,
      ),
    )));

    expect(
      tester.getSize(find.byType(FloatingChromeEdgeGradient)).height,
      93,
    );
  });

  testWidgets('floating header uses the current displayed news count',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var drawerOpened = false;
    try {
      await tester.pumpWidget(_testApp(AndroidFloatingFeedHeader(
        title: 'Feed One',
        newsCount: 12,
        showCount: true,
        onOpenDrawer: () => drawerOpened = true,
      )));

      expect(find.text('Feed One'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('12')).label,
        contains('Count: 12'),
      );
      expect(find.byType(AndroidFloatingSurface), findsNWidgets(2));
      final titleSurface = find.ancestor(
        of: find.text('Feed One'),
        matching: find.byType(AndroidFloatingSurface),
      );
      final drawerSurface = find.byType(AndroidFloatingSurface).first;
      expect(
        tester.getSize(titleSurface).height,
        lessThan(tester.getSize(drawerSurface).height),
      );
      expect(
        tester.getSize(drawerSurface),
        const Size.square(androidFloatingDrawerVisualExtent),
      );
      expect(
        tester.getSize(find.byType(IconButton).first),
        const Size.square(androidFloatingDrawerTouchExtent),
      );
      expect(tester.widget<FaIcon>(find.byType(FaIcon)).size, 24);
      expect(
        tester.widget<AndroidFloatingSurface>(titleSurface).padding,
        const EdgeInsetsDirectional.fromSTEB(12, 6, 12, 6),
      );
      expect(
        find
            .ancestor(
              of: find.text('Feed One'),
              matching: find.byType(AndroidFloatingSurface),
            )
            .evaluate()
            .single,
        find
            .ancestor(
              of: find.text('12'),
              matching: find.byType(AndroidFloatingSurface),
            )
            .evaluate()
            .single,
      );
      await tester.tap(find.byType(FaIcon));
      expect(drawerOpened, isTrue);
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
    await tester.pumpWidget(_testApp(SizedBox(
      width: 360,
      child: AndroidFloatingFeedHeader(
        title: 'Feed One',
        newsCount: 12,
        showCount: false,
        onOpenDrawer: () {},
      ),
    )));

    expect(find.text('Feed One'), findsOneWidget);
    expect(find.text('12'), findsNothing);
    expect(find.byType(AndroidFloatingSurface), findsNWidgets(2));
    final titleSurface = find.ancestor(
      of: find.text('Feed One'),
      matching: find.byType(AndroidFloatingSurface),
    );
    expect(
      tester.getSize(titleSurface).width,
      lessThan(360),
    );
  });

  testWidgets('long floating title stays within the available header width',
      (tester) async {
    await tester.pumpWidget(_testApp(SizedBox(
      width: 280,
      child: AndroidFloatingFeedHeader(
        title: 'A very long feed title that cannot fit at its natural width',
        newsCount: 123,
        showCount: true,
        onOpenDrawer: () {},
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
      tester.getSize(find.byType(AndroidFloatingSurface)).height,
      androidFloatingToolbarVisualHeight,
    );
    expect(
      tester.getSize(find.byType(AndroidFloatingToolbar)).height,
      androidFloatingToolbarTouchHeight,
    );
    final syncButton = find.widgetWithIcon(IconButton, Icons.refresh);
    final syncStateLayer = find.descendant(
      of: syncButton,
      matching: find.byType(Material),
    );
    expect(tester.getSize(syncButton), const Size.square(48));
    expect(syncStateLayer, findsOneWidget);
    expect(
      tester.getSize(syncStateLayer),
      const Size.square(androidFloatingToolbarStateLayerExtent),
    );
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

  testWidgets('accent tint can be disabled for all floating elements',
      (tester) async {
    await tester.pumpWidget(_testApp(Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AndroidFloatingFeedHeader(
          title: 'Feed One',
          newsCount: 12,
          showCount: true,
          onOpenDrawer: () {},
          useAccentColor: false,
        ),
        AndroidFloatingToolbar(
          useAccentColor: false,
          children: [
            IconButton(onPressed: () {}, icon: const Icon(Icons.menu)),
          ],
        ),
      ],
    )));

    final surfaces = tester.widgetList<AndroidFloatingSurface>(
      find.byType(AndroidFloatingSurface),
    );
    expect(surfaces, hasLength(3));
    expect(surfaces.every((surface) => surface.accentColor == null), isTrue);
  });

  testWidgets('dark floating surfaces use a darker neutral base',
      (tester) async {
    final darkTheme = ThemeData.dark();
    await tester.pumpWidget(_testApp(
      const AndroidFloatingSurface(child: SizedBox.square(dimension: 48)),
      theme: darkTheme,
    ));

    final surfaceFinder = find.byType(AndroidFloatingSurface);
    final decoratedBox = tester.widget<DecoratedBox>(find.descendant(
      of: surfaceFinder,
      matching: find.byType(DecoratedBox),
    ));
    final surfaceColor = (decoratedBox.decoration as BoxDecoration).color!;
    expect(
      surfaceColor.computeLuminance(),
      lessThan(darkTheme.colorScheme.surfaceContainer.computeLuminance()),
    );
  });

  testWidgets('true black surfaces remain translucent without accent tint',
      (tester) async {
    final baseTheme = ThemeData.dark();
    final trueBlackTheme = baseTheme.copyWith(
      scaffoldBackgroundColor: Colors.black,
      colorScheme: baseTheme.colorScheme.copyWith(surface: Colors.black),
    );
    await tester.pumpWidget(_testApp(
      const AndroidFloatingSurface(child: SizedBox.square(dimension: 48)),
      theme: trueBlackTheme,
    ));

    final decoratedBox = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(AndroidFloatingSurface),
        matching: find.byType(DecoratedBox),
      ),
    );
    final surfaceColor = (decoratedBox.decoration as BoxDecoration).color!;
    expect(surfaceColor, Colors.black.withValues(alpha: 0.72));
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('floating toolbar scrolls additional actions on narrow screens',
      (tester) async {
    await tester.pumpWidget(_testApp(SizedBox(
      width: 240,
      child: AndroidFloatingToolbar(
        leadingChildren: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.menu)),
          IconButton(onPressed: () {}, icon: const Icon(Icons.refresh)),
        ],
        trailingChildren: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert)),
        ],
        children: [
          for (final icon in const <IconData>[
            Icons.check_circle_outline,
            Icons.podcasts,
            Icons.search,
            Icons.settings,
            Icons.sort,
          ])
            IconButton(onPressed: () {}, icon: Icon(icon)),
        ],
      ),
    )));

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    expect(
      tester.getCenter(find.byIcon(Icons.more_vert)).dx,
      lessThanOrEqualTo(
        tester.getTopRight(find.byType(AndroidFloatingToolbar)).dx,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected floating toolbar actions are removed from More',
      (tester) async {
    final appState = FluxNewsState()
      ..appBarType = FluxNewsState.appBarFloatingType
      ..androidFloatingToolbarActions = <String>[
        FluxNewsState.androidFloatingActionSearch,
        FluxNewsState.androidFloatingActionMarkAsRead,
        FluxNewsState.floatingToolbarActionMarkAsReadAndNext,
        FluxNewsState.androidFloatingActionPodcasts,
        FluxNewsState.androidFloatingActionSettings,
      ];
    await tester.pumpWidget(_menuTestApp(
      appState,
      hideConfiguredFloatingActionsFromMore: true,
    ));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Show all news'), findsOneWidget);
    expect(find.text('Oldest first'), findsOneWidget);
    expect(find.text('Search'), findsNothing);
    expect(find.text('Mark all news as read'), findsNothing);
    expect(find.text('Mark as read and open next'), findsNothing);
    expect(find.text('Podcasts'), findsNothing);
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('More stays complete outside expanded floating mode',
      (tester) async {
    final appState = FluxNewsState()
      ..appBarType = FluxNewsState.appBarNormalType
      ..androidFloatingToolbarActions = List<String>.of(
        FluxNewsState.androidFloatingToolbarAvailableActions,
      );
    await tester.pumpWidget(_menuTestApp(appState));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Mark all news as read'), findsOneWidget);
    expect(find.text('Mark as read and open next'), findsNothing);
    expect(find.text('Podcasts'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('unselected floating actions remain available in More',
      (tester) async {
    final appState = FluxNewsState()
      ..appBarType = FluxNewsState.appBarFloatingType
      ..androidFloatingToolbarActions = <String>[
        FluxNewsState.androidFloatingActionSearch,
        FluxNewsState.androidFloatingActionPodcasts,
      ];
    await tester.pumpWidget(_menuTestApp(
      appState,
      hideConfiguredFloatingActionsFromMore: true,
    ));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Search'), findsNothing);
    expect(find.text('Podcasts'), findsNothing);
    expect(find.text('Mark all news as read'), findsOneWidget);
    expect(find.text('Mark as read and open next'), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('tablet floating toolbar shows every action and hides More',
      (tester) async {
    final appState = FluxNewsState()
      ..appBarType = FluxNewsState.appBarNormalType
      ..selectedCategoryElementType = FluxNewsState.feedElementType
      ..androidFloatingToolbarActions = List<String>.of(
        FluxNewsState.androidFloatingToolbarAvailableActions,
      );
    await tester.pumpWidget(_menuTestApp(
      appState,
      showConfiguredFloatingToolbarActions: true,
    ));

    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byIcon(Icons.checklist), findsOneWidget);
    expect(find.byIcon(Icons.sort), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.skip_next), findsOneWidget);
    expect(find.byIcon(Icons.podcasts), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets('tablet floating sync indicator keeps its stable 15dp extent',
      (tester) async {
    final appState = FluxNewsState()..syncProcess = true;
    await tester.pumpWidget(_menuTestApp(
      appState,
      showConfiguredFloatingToolbarActions: true,
    ));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.getSize(find.byType(CircularProgressIndicator)),
      const Size.square(15),
    );
  });

  testWidgets('all-news scope omits Mark-and-next without an empty More menu',
      (tester) async {
    final appState = FluxNewsState()
      ..appBarType = FluxNewsState.appBarNormalType
      ..androidFloatingToolbarActions = FluxNewsState
          .androidFloatingToolbarAvailableActions
          .where(
            (action) =>
                action != FluxNewsState.floatingToolbarActionMarkAsReadAndNext,
          )
          .toList(growable: false);
    await tester.pumpWidget(_menuTestApp(
      appState,
      showConfiguredFloatingToolbarActions: true,
    ));

    expect(find.byIcon(Icons.skip_next), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });
}
