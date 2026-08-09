import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/ui/adaptive_layout.dart';

void main() {
  test('two-pane layout uses shared width and height breakpoints', () {
    expect(useTwoPaneLayout(const Size(599, 1000)), isFalse);
    expect(useTwoPaneLayout(const Size(600, 480)), isTrue);
    expect(useTwoPaneLayout(const Size(900, 479)), isFalse);
  });

  test('sidebar width stays within its compact bounds', () {
    expect(adaptiveSidebarWidth(600), minimumSidebarWidth);
    expect(adaptiveSidebarWidth(1000), 280);
    expect(adaptiveSidebarWidth(2000), maximumSidebarWidth);
  });

  test('separating display features are classified by direction', () {
    const size = Size(1000, 800);
    const verticalHinge = Rect.fromLTWH(495, 0, 10, 800);
    const horizontalHinge = Rect.fromLTWH(0, 395, 1000, 10);

    expect(
      verticalSeparatingDisplayFeature(size, const [verticalHinge]),
      verticalHinge,
    );
    expect(
      horizontalSeparatingDisplayFeature(size, const [horizontalHinge]),
      horizontalHinge,
    );
    expect(
      verticalSeparatingDisplayFeature(size, const [horizontalHinge]),
      isNull,
    );
  });
}
