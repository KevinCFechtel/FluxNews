import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:flux_news/state_management/flux_news_theme_state.dart';
import 'package:flux_news/ui/settings/adaptive_settings_controls.dart';
import 'package:flux_news/ui/settings/adaptive_settings_scaffold.dart';
import 'package:flux_news/ui/settings/android_floating_toolbar_settings.dart';
import 'package:flux_news/ui/settings/general_settings.dart';
import 'package:provider/provider.dart';

import 'test_helpers.dart';

Widget _settingsTestApp(
  FluxNewsState appState, {
  bool iosToolbar = false,
}) {
  return ChangeNotifierProvider<FluxNewsState>.value(
    value: appState,
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: iosToolbar
            ? const IOSToolbarSettingsTile()
            : const AndroidFloatingToolbarSettingsTile(),
      ),
    ),
  );
}

Widget _generalSettingsTestApp(FluxNewsState appState) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<FluxNewsState>.value(value: appState),
      ChangeNotifierProvider<FluxNewsThemeState>(
        create: (_) => FluxNewsThemeState(),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: FluxNewsGeneralSettingsBody()),
    ),
  );
}

void main() {
  final storage = SecureStorageMock();

  setUp(storage.install);
  tearDown(SecureStorageMock.uninstall);

  testWidgets('the complete settings tile opens a dedicated page',
      (tester) async {
    final appState = FluxNewsState();
    await tester.pumpWidget(_settingsTestApp(appState));

    expect(find.byType(AdaptiveSettingsNavigationRow), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);

    await tester.tap(find.text('Configure floating toolbar actions'));
    await tester.pumpAndSettle();

    expect(find.byType(AndroidFloatingToolbarSettings), findsOneWidget);
    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(find.byType(AdaptiveSettingsGroupSurface), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(7));
    final dividerTheme = tester.widget<DividerTheme>(
      find.descendant(
        of: find.byType(AdaptiveSettingsGroupSurface),
        matching: find.byType(DividerTheme),
      ),
    );
    expect(dividerTheme.data.indent, 16);
    expect(dividerTheme.data.space, 8);
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(7));
    expect(find.text('Toggle all/unread news'), findsOneWidget);
    expect(find.text('Change sort order'), findsOneWidget);
    expect(find.text('Mark as read and open next'), findsOneWidget);
  });

  testWidgets('toolbar action changes are saved immediately', (tester) async {
    final appState = FluxNewsState()
      ..androidFloatingToolbarActions = <String>[
        FluxNewsState.androidFloatingActionSearch,
      ];
    await tester.pumpWidget(_settingsTestApp(appState));

    await tester.tap(find.byIcon(Icons.dashboard_customize_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Podcasts'));
    await tester.pump();

    expect(
      appState.androidFloatingToolbarActions,
      <String>[
        FluxNewsState.androidFloatingActionSearch,
        FluxNewsState.androidFloatingActionPodcasts,
      ],
    );
    expect(
      storage
          .values[FluxNewsState.secureStorageAndroidFloatingToolbarActionsKey],
      '["search","podcasts"]',
    );
    expect(
      storage.values[
          FluxNewsState.secureStorageAndroidFloatingToolbarActionOrderKey],
      '["search","newsStatus","sortOrder","markAsRead","markAsReadAndNext","podcasts","settings"]',
    );
  });

  testWidgets('Apple toolbar settings expose and persist all seven actions',
      (tester) async {
    final appState = FluxNewsState()
      ..iosToolbarActions = <String>[
        FluxNewsState.androidFloatingActionSearch,
      ];
    await tester.pumpWidget(_settingsTestApp(appState, iosToolbar: true));

    await tester.tap(find.text('Configure floating toolbar actions'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(AdaptiveSettingsGroupSurface), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(7));
    expect(find.text('Mark as read and open next'), findsOneWidget);

    await tester.tap(find.text('Mark as read and open next'));
    await tester.pump();

    expect(
      appState.iosToolbarActions,
      <String>[
        FluxNewsState.androidFloatingActionSearch,
        FluxNewsState.floatingToolbarActionMarkAsReadAndNext,
      ],
    );
    expect(
      storage.values[FluxNewsState.secureStorageIOSToolbarActionsKey],
      '["search","markAsReadAndNext"]',
    );
  });

  test('disabled action order is persisted independently of selection',
      () async {
    final appState = FluxNewsState();
    const order = <String>[
      FluxNewsState.androidFloatingActionSettings,
      FluxNewsState.androidFloatingActionSearch,
      FluxNewsState.androidFloatingActionNewsStatus,
      FluxNewsState.androidFloatingActionSortOrder,
      FluxNewsState.androidFloatingActionMarkAsRead,
      FluxNewsState.floatingToolbarActionMarkAsReadAndNext,
      FluxNewsState.androidFloatingActionPodcasts,
    ];

    appState.updateAndroidFloatingToolbarActions(
      const <String>[FluxNewsState.androidFloatingActionSearch],
      orderedActions: order,
    );
    await Future<void>.delayed(Duration.zero);

    expect(appState.androidFloatingToolbarActionOrder, order);
    expect(
      storage.values[
          FluxNewsState.secureStorageAndroidFloatingToolbarActionOrderKey],
      '["settings","search","newsStatus","sortOrder","markAsRead","markAsReadAndNext","podcasts"]',
    );
  });

  testWidgets('tablet hides phone chrome settings but keeps toolbar actions',
      (tester) async {
    final brightnessMode = KeyValueRecordType(
      key: FluxNewsState.brightnessModeSystemString,
      value: 'System',
    );
    final appState = FluxNewsState()
      ..isTablet = true
      ..appBarType = FluxNewsState.appBarNormalType
      ..floatingButtonVisible = true
      ..recordTypesBrightnessMode = <KeyValueRecordType>[brightnessMode]
      ..brightnessModeSelection = brightnessMode;
    await tester.pumpWidget(_generalSettingsTestApp(appState));

    expect(find.byType(AdaptiveSettingsGroup), findsOneWidget);
    expect(find.text('Configure floating toolbar actions'), findsOneWidget);
    expect(find.text('Show newscount in Appbar'), findsNothing);
    expect(find.text('Select the App Bar Type'), findsNothing);
    expect(
      find.text('Use an extra button for additional functions'),
      findsNothing,
    );
    expect(
      find.text('Show the extra button with a glass effect'),
      findsNothing,
    );
    expect(
      find.text('Select the action for the extra button'),
      findsNothing,
    );
  });

  testWidgets('Android settings body respects the bottom system inset',
      (tester) async {
    const bodyKey = Key('settings-body');
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(padding: EdgeInsets.only(bottom: 32)),
          child: AdaptiveSettingsScaffold(
            title: 'Settings',
            body: SizedBox(key: bodyKey),
          ),
        ),
      ),
    );

    final safeArea = tester.widget<SafeArea>(
      find.ancestor(
        of: find.byKey(bodyKey),
        matching: find.byType(SafeArea),
      ),
    );
    expect(safeArea.top, isFalse);
    expect(safeArea.bottom, isTrue);
  });
}
