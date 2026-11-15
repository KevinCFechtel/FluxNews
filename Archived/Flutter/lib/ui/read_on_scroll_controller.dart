import 'dart:async';
import 'dart:collection';

class ScrollReadRange<T> {
  const ScrollReadRange({
    required this.start,
    required this.end,
    required this.items,
  });

  final int start;
  final int end;
  final List<T> items;
}

class IncrementalScrollRangeController<T> {
  Object? _source;
  int _nextIndex = 0;

  ScrollReadRange<T>? capture({
    required List<T> items,
    required int firstVisibleIndex,
    required bool reachedBottom,
  }) {
    if (!identical(_source, items)) {
      _source = items;
      _nextIndex = 0;
    }

    _nextIndex = _nextIndex.clamp(0, items.length);
    final end = (reachedBottom ? items.length : firstVisibleIndex)
        .clamp(0, items.length);
    if (end <= _nextIndex) return null;

    final start = _nextIndex;
    _nextIndex = end;
    return ScrollReadRange<T>(
      start: start,
      end: end,
      items: List<T>.unmodifiable(items.getRange(start, end)),
    );
  }
}

class ScrollIdleTaskController<T> {
  ScrollIdleTaskController({
    required this.idleDuration,
    required Future<void> Function(T value) handler,
    void Function(Object error, StackTrace stackTrace)? onError,
  })  : _handler = handler,
        _onError = onError;

  final Duration idleDuration;
  final Future<void> Function(T value) _handler;
  final void Function(Object error, StackTrace stackTrace)? _onError;
  Timer? _timer;
  T? _pendingValue;
  bool _hasPendingValue = false;
  bool _isScrolling = false;

  void markPending(T value) {
    _pendingValue = value;
    _hasPendingValue = true;
    if (!_isScrolling) _schedule();
  }

  void onScrollStarted() {
    _isScrolling = true;
    _timer?.cancel();
    _timer = null;
  }

  void onScrollEnded() {
    _isScrolling = false;
    if (_hasPendingValue) _schedule();
  }

  void dispose({bool flushPending = false}) {
    _timer?.cancel();
    _timer = null;
    if (flushPending && _hasPendingValue) _runPending();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(idleDuration, _runPending);
  }

  void _runPending() {
    _timer = null;
    if (!_hasPendingValue || _isScrolling) return;
    final value = _pendingValue as T;
    _pendingValue = null;
    _hasPendingValue = false;
    unawaited(_run(value));
  }

  Future<void> _run(T value) async {
    try {
      await _handler(value);
    } catch (error, stackTrace) {
      _onError?.call(error, stackTrace);
    }
  }
}

class SerializedAsyncController<T> {
  SerializedAsyncController({
    required Future<void> Function(T event) handler,
    void Function(Object error, StackTrace stackTrace)? onError,
  })  : _handler = handler,
        _onError = onError;

  final Future<void> Function(T event) _handler;
  final void Function(Object error, StackTrace stackTrace)? _onError;
  final Queue<T> _events = Queue<T>();
  Completer<void>? _idleCompleter;
  bool _isRunning = false;

  Future<void> add(T event) {
    _events.addLast(event);
    _idleCompleter ??= Completer<void>();
    if (!_isRunning) unawaited(_drain());
    return _idleCompleter!.future;
  }

  Future<void> get idle => _idleCompleter?.future ?? Future<void>.value();

  Future<void> _drain() async {
    _isRunning = true;
    while (_events.isNotEmpty) {
      final event = _events.removeFirst();
      try {
        await _handler(event);
      } catch (error, stackTrace) {
        _onError?.call(error, stackTrace);
      }
    }
    _isRunning = false;
    _idleCompleter?.complete();
    _idleCompleter = null;
  }
}
