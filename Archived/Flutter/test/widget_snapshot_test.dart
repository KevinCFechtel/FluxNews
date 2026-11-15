import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/functions/widget_service.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;

  setUp(() async {
    database = await createFluxNewsTestDatabase();
    await insertTestCategory(database, categoryID: 7, title: 'Tech');
    await insertTestFeed(
      database,
      feedID: 1,
      title: 'Feed One',
      categoryID: 7,
      iconID: 11,
      manualAdaptDarkModeToIcon: 1,
    );
    await insertTestFeed(
      database,
      feedID: 2,
      title: 'Feed Two',
      categoryID: 8,
    );
    await insertTestNews(
      database,
      newsID: 1,
      feedID: 1,
      title: 'Unread Tech',
      status: FluxNewsState.unreadNewsStatus,
      feedTitle: 'Feed One',
      publishedAt: '2026-07-03T10:00:00Z',
    );
    await insertTestNews(
      database,
      newsID: 2,
      feedID: 1,
      title: 'Read Tech',
      status: FluxNewsState.readNewsStatus,
      feedTitle: 'Feed One',
      publishedAt: '2026-07-03T09:00:00Z',
    );
    await insertTestNews(
      database,
      newsID: 3,
      feedID: 2,
      title: 'Unread Other',
      status: FluxNewsState.unreadNewsStatus,
      feedTitle: 'Feed Two',
      publishedAt: '2026-07-03T08:00:00Z',
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('snapshot payload respects category filter and unread count', () async {
    final appState = FluxNewsState()
      ..db = database
      ..widgetUnreadOnly = true
      ..widgetFilterType = FluxNewsState.widgetFilterCategoryString
      ..widgetFilterId = 7;

    final snapshot =
        await FluxNewsWidgetService.buildWidgetSnapshotPayload(appState);
    final items = snapshot.payload['items'] as List<Object?>;
    final firstItem = Map<String, Object?>.from(items.single as Map);

    expect(snapshot.payload['displayTitle'], 'Tech');
    expect(snapshot.payload['unreadCount'], 1);
    expect(snapshot.payload['countLabel'], isNotEmpty);
    expect(firstItem['id'], 1);
    expect(firstItem['title'], 'Unread Tech');
    expect(firstItem['feedTitle'], 'Feed One');
    expect(firstItem['status'], FluxNewsState.unreadNewsStatus);
    expect(firstItem['manualAdaptDarkModeToIcon'], isTrue);
    expect(firstItem['iconData'], isEmpty);
    expect(jsonEncode(snapshot.payload), contains('Unread Tech'));
    expect(jsonEncode(snapshot.statusPayload), isNot(contains('items')));
  });

  test('snapshot count switches to read status when unread-only is disabled',
      () async {
    final appState = FluxNewsState()
      ..db = database
      ..widgetUnreadOnly = false
      ..widgetFilterType = FluxNewsState.widgetFilterFeedString
      ..widgetFilterId = 1;

    final snapshot =
        await FluxNewsWidgetService.buildWidgetSnapshotPayload(appState);
    final items = snapshot.payload['items'] as List<Object?>;

    expect(snapshot.payload['displayTitle'], 'Feed One');
    expect(snapshot.payload['unreadCount'], 1);
    expect(items, hasLength(2));
    expect(
      items
          .map((item) => Map<String, Object?>.from(item as Map)['title'])
          .toList(),
      ['Unread Tech', 'Read Tech'],
    );
  });
}
