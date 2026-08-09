import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:flux_news/ui/adaptive_layout.dart';
import 'package:flux_news/ui/ios_toolbar_layout.dart';

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

  test('iPad toolbar keeps selected order and overflows on narrow panes', () {
    final visibleActions = iosTabletVisibleToolbarActions(
      selectedActions: FluxNewsState.iosToolbarAvailableActions,
      availableActions: FluxNewsState.iosToolbarAvailableActions,
      newsPaneWidth: 640,
    );

    expect(
      visibleActions,
      FluxNewsState.iosToolbarAvailableActions.take(5),
    );
  });

  test('iPad toolbar can omit More when every action fits', () {
    expect(
      iosTabletVisibleToolbarActions(
        selectedActions: FluxNewsState.iosToolbarAvailableActions,
        availableActions: FluxNewsState.iosToolbarAvailableActions,
        newsPaneWidth: 764,
      ),
      FluxNewsState.iosToolbarAvailableActions,
    );
  });

  test('iPhone toolbar keeps the first three selected actions', () {
    expect(
      iosPhoneVisibleToolbarActions(
        selectedActions: const <String>[
          FluxNewsState.androidFloatingActionSettings,
          'unsupported',
          FluxNewsState.androidFloatingActionSearch,
          FluxNewsState.androidFloatingActionSettings,
          FluxNewsState.androidFloatingActionPodcasts,
        ],
        availableActions: FluxNewsState.iosToolbarAvailableActions,
      ),
      const <String>[
        FluxNewsState.androidFloatingActionSettings,
        FluxNewsState.androidFloatingActionSearch,
        FluxNewsState.androidFloatingActionPodcasts,
      ],
    );
  });

  test('Mark as read and next is limited to feeds and categories', () {
    const action = FluxNewsState.floatingToolbarActionMarkAsReadAndNext;

    expect(
      FluxNewsState.isToolbarActionAvailableForElementType(
        action,
        FluxNewsState.feedElementType,
      ),
      isTrue,
    );
    expect(
      FluxNewsState.isToolbarActionAvailableForElementType(
        action,
        FluxNewsState.categoryElementType,
      ),
      isTrue,
    );
    expect(
      FluxNewsState.isToolbarActionAvailableForElementType(
        action,
        FluxNewsState.allNewsElementType,
      ),
      isFalse,
    );
    expect(
      FluxNewsState.isToolbarActionAvailableForElementType(
        action,
        FluxNewsState.bookmarkedNewsElementType,
      ),
      isFalse,
    );
  });
}
