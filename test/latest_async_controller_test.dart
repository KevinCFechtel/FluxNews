import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/functions/latest_async_controller.dart';

void main() {
  test('runs one task at a time and keeps only the latest pending value',
      () async {
    final firstMayFinish = Completer<void>();
    final values = <int>[];
    var active = 0;
    var maxActive = 0;
    final controller = LatestAsyncController<int>(handler: (value) async {
      values.add(value);
      active++;
      maxActive = maxActive < active ? active : maxActive;
      if (value == 1) await firstMayFinish.future;
      active--;
    });

    controller.add(1);
    controller.add(2);
    final idle = controller.add(3);
    await Future<void>.delayed(Duration.zero);
    expect(values, [1]);

    firstMayFinish.complete();
    await idle;

    expect(values, [1, 3]);
    expect(maxActive, 1);
  });

  test('catches errors and processes the latest pending value', () async {
    final errors = <Object>[];
    final values = <int>[];
    final failureStarted = Completer<void>();
    final releaseFailure = Completer<void>();
    final controller = LatestAsyncController<int>(
      handler: (value) async {
        values.add(value);
        if (value == 1) {
          failureStarted.complete();
          await releaseFailure.future;
          throw StateError('failed');
        }
      },
      onError: (error, _) => errors.add(error),
    );

    controller.add(1);
    await failureStarted.future;
    final idle = controller.add(2);
    releaseFailure.complete();
    await idle;

    expect(values, [1, 2]);
    expect(errors.single, isA<StateError>());
  });
}
