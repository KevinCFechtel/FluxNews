import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/state_management/flux_news_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  test('floating chrome is the default Android app bar layout', () {
    final appState = FluxNewsState();

    expect(
      appState.appBarType,
      Platform.isIOS
          ? FluxNewsState.appBarGlassType
          : FluxNewsState.appBarFloatingType,
    );
  });

  test('failed config read preserves previously loaded values', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      throw PlatformException(code: 'unavailable');
    });
    final appState = FluxNewsState()
      ..storageValues = {'existing': 'value'}
      ..configValuesReadSuccessfully = true;

    final result = await appState.readConfigValues();

    expect(result, isFalse);
    expect(appState.storageValues, {'existing': 'value'});
    expect(appState.configValuesReadSuccessfully, isFalse);
  });

  test('successful empty config read is distinct from a read failure',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      expect(call.method, 'readAll');
      return <String, String>{};
    });
    final appState = FluxNewsState()..storageValues = {'existing': 'value'};

    final result = await appState.readConfigValues();

    expect(result, isTrue);
    expect(appState.storageValues, isEmpty);
    expect(appState.configValuesReadSuccessfully, isTrue);
  });

  test('legacy mark-as-read FAB migrates to the iOS quick action', () {
    expect(
      FluxNewsState.legacyFloatingButtonEnablesIOSMarkAsReadQuickAction({
        FluxNewsState.secureStorageFloatingButtonVisibleKey:
            FluxNewsState.secureStorageTrueString,
        FluxNewsState.secureStorageFloatingButtonKey:
            FluxNewsState.floatingButtonMarkAsReadAction,
      }),
      isTrue,
    );
  });

  test('legacy sync or hidden FAB does not enable the iOS quick action', () {
    expect(
      FluxNewsState.legacyFloatingButtonEnablesIOSMarkAsReadQuickAction({
        FluxNewsState.secureStorageFloatingButtonVisibleKey:
            FluxNewsState.secureStorageTrueString,
        FluxNewsState.secureStorageFloatingButtonKey:
            FluxNewsState.floatingButtonSyncAction,
      }),
      isFalse,
    );
    expect(
      FluxNewsState.legacyFloatingButtonEnablesIOSMarkAsReadQuickAction({}),
      isFalse,
    );
  });

  test('fresh Apple toolbar configuration defaults to Mark as read', () {
    expect(
      FluxNewsState.initialIOSToolbarActionsForLegacyValues(const {}),
      const <String>[FluxNewsState.androidFloatingActionMarkAsRead],
    );
  });

  test('legacy Apple toolbar preference is preserved', () {
    expect(
      FluxNewsState.initialIOSToolbarActionsForLegacyValues(const {
        FluxNewsState.secureStorageIOSMarkAsReadQuickActionKey:
            FluxNewsState.secureStorageFalseString,
      }),
      isEmpty,
    );
    expect(
      FluxNewsState.initialIOSToolbarActionsForLegacyValues(const {
        FluxNewsState.secureStorageFloatingButtonVisibleKey:
            FluxNewsState.secureStorageTrueString,
        FluxNewsState.secureStorageFloatingButtonKey:
            FluxNewsState.floatingButtonMarkAsReadAction,
      }),
      const <String>[FluxNewsState.androidFloatingActionMarkAsRead],
    );
  });

  test('floating toolbar action normalization preserves valid order', () {
    expect(
      FluxNewsState.normalizeAndroidFloatingToolbarActions(const <String>[
        FluxNewsState.androidFloatingActionSearch,
        FluxNewsState.androidFloatingActionNewsStatus,
        FluxNewsState.androidFloatingActionSortOrder,
        'unsupported',
        FluxNewsState.androidFloatingActionSettings,
        FluxNewsState.androidFloatingActionSearch,
      ]),
      const <String>[
        FluxNewsState.androidFloatingActionSearch,
        FluxNewsState.androidFloatingActionNewsStatus,
        FluxNewsState.androidFloatingActionSortOrder,
        FluxNewsState.androidFloatingActionSettings,
      ],
    );
  });

  test('floating toolbar complete order appends missing valid actions', () {
    expect(
      FluxNewsState.normalizeAndroidFloatingToolbarActionOrder(const <String>[
        FluxNewsState.androidFloatingActionSettings,
        FluxNewsState.androidFloatingActionSearch,
        'unsupported',
      ]),
      const <String>[
        FluxNewsState.androidFloatingActionSettings,
        FluxNewsState.androidFloatingActionSearch,
        FluxNewsState.androidFloatingActionNewsStatus,
        FluxNewsState.androidFloatingActionSortOrder,
        FluxNewsState.androidFloatingActionMarkAsRead,
        FluxNewsState.floatingToolbarActionMarkAsReadAndNext,
        FluxNewsState.androidFloatingActionPodcasts,
      ],
    );
  });

  test('Apple toolbar normalization includes its seventh action', () {
    expect(
      FluxNewsState.normalizeIOSToolbarActionOrder(const <String>[
        FluxNewsState.floatingToolbarActionMarkAsReadAndNext,
        FluxNewsState.androidFloatingActionSearch,
        'unsupported',
      ]),
      const <String>[
        FluxNewsState.floatingToolbarActionMarkAsReadAndNext,
        FluxNewsState.androidFloatingActionSearch,
        FluxNewsState.androidFloatingActionNewsStatus,
        FluxNewsState.androidFloatingActionSortOrder,
        FluxNewsState.androidFloatingActionMarkAsRead,
        FluxNewsState.androidFloatingActionPodcasts,
        FluxNewsState.androidFloatingActionSettings,
      ],
    );
  });

  test('Apple toolbar defaults to Mark as read', () {
    expect(
      FluxNewsState().iosToolbarActions,
      const <String>[FluxNewsState.androidFloatingActionMarkAsRead],
    );
  });
}
