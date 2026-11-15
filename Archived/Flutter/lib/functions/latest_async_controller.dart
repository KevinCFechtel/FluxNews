import 'dart:async';

class LatestAsyncController<T> {
  LatestAsyncController({
    required Future<void> Function(T value) handler,
    void Function(Object error, StackTrace stackTrace)? onError,
  })  : _handler = handler,
        _onError = onError;

  final Future<void> Function(T value) _handler;
  final void Function(Object error, StackTrace stackTrace)? _onError;
  T? _pendingValue;
  bool _hasPendingValue = false;
  bool _isRunning = false;
  Completer<void>? _idleCompleter;

  Future<void> add(T value) {
    _pendingValue = value;
    _hasPendingValue = true;
    _idleCompleter ??= Completer<void>();
    if (!_isRunning) unawaited(_drain());
    return _idleCompleter!.future;
  }

  Future<void> get idle => _idleCompleter?.future ?? Future<void>.value();

  Future<void> _drain() async {
    _isRunning = true;
    while (_hasPendingValue) {
      final value = _pendingValue as T;
      _pendingValue = null;
      _hasPendingValue = false;
      try {
        await _handler(value);
      } catch (error, stackTrace) {
        _onError?.call(error, stackTrace);
      }
    }
    _isRunning = false;
    _idleCompleter?.complete();
    _idleCompleter = null;
  }
}
