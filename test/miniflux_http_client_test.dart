import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/miniflux/miniflux_http_client.dart';
import 'package:http/http.dart';

void main() {
  test('request timeout closes the underlying client', () async {
    final inner = _NeverRespondingClient();
    final client = MinifluxTimeoutClient(
      inner,
      timeout: const Duration(milliseconds: 20),
    );

    await expectLater(
      client.get(Uri.parse('https://example.com')),
      throwsA(isA<TimeoutException>()),
    );
    expect(inner.closed, isTrue);
  });
}

class _NeverRespondingClient extends BaseClient {
  final Completer<StreamedResponse> _response = Completer<StreamedResponse>();
  bool closed = false;

  @override
  Future<StreamedResponse> send(BaseRequest request) => _response.future;

  @override
  void close() {
    closed = true;
  }
}
