import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/functions/news_widget_functions.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/state_management/flux_news_state.dart';

class _RecordingFluxNewsState extends FluxNewsState {
  final List<(int, bool)> collapsedItemJumps = [];

  @override
  Future<void> jumpToCollapsedNewsItem(
    int index, {
    required bool searchView,
  }) async {
    collapsedItemJumps.add((index, searchView));
  }
}

News _news() => News(
      newsID: 42,
      feedID: 1,
      title: 'Article',
      url: 'https://example.com/article',
      commentsUrl: '',
      shareCode: '',
      content: 'Full article content',
      hash: 'hash',
      publishedAt: '2026-08-26T12:00:00Z',
      createdAt: '2026-08-26T12:00:00Z',
      status: FluxNewsState.unreadNewsStatus,
      readingTime: 1,
      starred: false,
      feedTitle: 'Feed',
    );

void main() {
  test('expanding leaves the list position unchanged', () async {
    final state = _RecordingFluxNewsState();
    final news = _news();

    await toggleNewsExpandedAction(news, state, 3, false);

    expect(news.expanded, isTrue);
    expect(state.collapsedItemJumps, isEmpty);
  });

  test('collapsing repositions the matching item in the active list', () async {
    final state = _RecordingFluxNewsState();
    final news = _news()..expanded = true;

    await toggleNewsExpandedAction(news, state, 3, true);

    expect(news.expanded, isFalse);
    expect(state.collapsedItemJumps, [(3, true)]);
  });
}
