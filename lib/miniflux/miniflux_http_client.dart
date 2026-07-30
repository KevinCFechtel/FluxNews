import 'dart:async';
import 'dart:io';

import 'package:cronet_http/cronet_http.dart';
import 'package:http/http.dart';
import 'package:http/io_client.dart';

const Duration minifluxRequestTimeout = Duration(seconds: 30);

Client createMinifluxHttpClient() {
  final Client platformClient;
  if (Platform.isAndroid) {
    final engine = CronetEngine.build(
      cacheMode: CacheMode.memory,
      cacheMaxSize: 2 * 1024 * 1024,
    );
    platformClient = CronetClient.fromCronetEngine(engine, closeEngine: true);
  } else {
    final httpClient = HttpClient()..connectionTimeout = minifluxRequestTimeout;
    platformClient = IOClient(httpClient);
  }
  return MinifluxTimeoutClient(platformClient);
}

class MinifluxTimeoutClient extends BaseClient {
  MinifluxTimeoutClient(
    this._inner, {
    this.timeout = minifluxRequestTimeout,
  });

  final Client _inner;
  final Duration timeout;
  bool _closed = false;

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    try {
      final response = await _inner.send(request).timeout(timeout);
      final responseStream = response.stream.timeout(
        timeout,
        onTimeout: (sink) {
          close();
          sink
            ..addError(TimeoutException(
              'Miniflux response timed out after ${timeout.inSeconds}s',
              timeout,
            ))
            ..close();
        },
      );
      return StreamedResponse(
        responseStream,
        response.statusCode,
        contentLength: response.contentLength,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (_) {
      close();
      rethrow;
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _inner.close();
  }
}
