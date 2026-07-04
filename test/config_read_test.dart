import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/state_management/flux_news_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  test('failed config read preserves previously loaded values', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(secureStorageChannel,
        (call) async {
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

  test('successful empty config read is distinct from a read failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(secureStorageChannel,
        (call) async {
      expect(call.method, 'readAll');
      return <String, String>{};
    });
    final appState = FluxNewsState()..storageValues = {'existing': 'value'};

    final result = await appState.readConfigValues();

    expect(result, isTrue);
    expect(appState.storageValues, isEmpty);
    expect(appState.configValuesReadSuccessfully, isTrue);
  });
}
