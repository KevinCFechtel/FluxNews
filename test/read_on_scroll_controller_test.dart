import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/ui/read_on_scroll_controller.dart';

void main() {
  test('captures only newly crossed indexes with immutable bounds', () {
    final controller = IncrementalScrollRangeController<int>();
    final items = <int>[10, 11, 12, 13, 14];

    final first = controller.capture(
      items: items,
      firstVisibleIndex: 2,
      reachedBottom: false,
    );
    final overlap = controller.capture(
      items: items,
      firstVisibleIndex: 1,
      reachedBottom: false,
    );
    final second = controller.capture(
      items: items,
      firstVisibleIndex: 4,
      reachedBottom: false,
    );

    expect((first!.start, first.end), (0, 2));
    expect(first.items, [10, 11]);
    expect(overlap, isNull);
    expect((second!.start, second.end), (2, 4));
    expect(second.items, [12, 13]);
    items[2] = 99;
    expect(second.items, [12, 13]);
  });

  test('bottom captures the remaining range and a new list resets progress',
      () {
    final controller = IncrementalScrollRangeController<int>();
    final firstItems = <int>[1, 2, 3];

    controller.capture(
      items: firstItems,
      firstVisibleIndex: 1,
      reachedBottom: false,
    );
    final bottom = controller.capture(
      items: firstItems,
      firstVisibleIndex: 2,
      reachedBottom: true,
    );
    final replacement = controller.capture(
      items: <int>[4, 5],
      firstVisibleIndex: 1,
      reachedBottom: false,
    );

    expect(bottom!.items, [2, 3]);
    expect(replacement!.items, [4]);
  });

  test('serializes events and continues in order after an error', () async {
    final firstMayFinish = Completer<void>();
    final started = <int>[];
    final completed = <int>[];
    final errors = <Object>[];
    var active = 0;
    var maxActive = 0;
    final controller = SerializedAsyncController<int>(
      handler: (event) async {
        started.add(event);
        active++;
        maxActive = maxActive < active ? active : maxActive;
        if (event == 1) await firstMayFinish.future;
        active--;
        if (event == 2) throw StateError('failed');
        completed.add(event);
      },
      onError: (error, _) => errors.add(error),
    );

    controller.add(1);
    controller.add(2);
    final idle = controller.add(3);
    await Future<void>.delayed(Duration.zero);
    expect(started, [1]);

    firstMayFinish.complete();
    await idle;

    expect(maxActive, 1);
    expect(started, [1, 2, 3]);
    expect(completed, [1, 3]);
    expect(errors.single, isA<StateError>());
  });

  test('runs pending work only after scrolling stays idle', () async {
    final values = <int>[];
    final controller = ScrollIdleTaskController<int>(
      idleDuration: const Duration(milliseconds: 20),
      handler: (value) async => values.add(value),
    );

    controller.markPending(1);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    controller.onScrollStarted();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(values, isEmpty);

    controller.markPending(2);
    controller.onScrollEnded();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(values, [2]);
    controller.dispose();
  });

  test('new scroll cancels an idle refresh without losing pending work',
      () async {
    final values = <int>[];
    final controller = ScrollIdleTaskController<int>(
      idleDuration: const Duration(milliseconds: 20),
      handler: (value) async => values.add(value),
    );

    controller.onScrollStarted();
    controller.markPending(1);
    controller.onScrollEnded();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    controller.onScrollStarted();
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(values, isEmpty);

    controller.onScrollEnded();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(values, [1]);
    controller.dispose();
  });
}
