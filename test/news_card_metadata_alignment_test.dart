import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/state_management/flux_news_counter_state.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:flux_news/state_management/flux_news_theme_state.dart';
import 'package:flux_news/ui/news_card.dart';
import 'package:flux_news/ui/news_card_ios.dart';
import 'package:provider/provider.dart';

News _news({bool starred = true, String feedTitle = 'Example Feed'}) => News(
      newsID: 1,
      feedID: 1,
      title: 'A news title',
      url: 'https://example.com/article',
      commentsUrl: '',
      shareCode: '',
      content: 'Article preview',
      hash: 'hash',
      publishedAt: '2026-08-11T10:00:00Z',
      createdAt: '2026-08-11T10:00:00Z',
      status: FluxNewsState.unreadNewsStatus,
      readingTime: 1,
      starred: starred,
      feedTitle: feedTitle,
    );

Widget _cardApp({
  required bool ios,
  bool starred = true,
  String feedTitle = 'Example Feed',
}) {
  final appState = FluxNewsState()
    ..longPressAction = FluxNewsState.longPressActionNoneString
    ..showHeadlineOnTop = false
    ..showFeedIcons = false;
  final news = _news(starred: starred, feedTitle: feedTitle);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<FluxNewsState>.value(value: appState),
      ChangeNotifierProvider(create: (_) => FluxNewsCounterState()),
      ChangeNotifierProvider(create: (_) => FluxNewsThemeState()),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => SizedBox(
            width: 400,
            child: ios
                ? NewsCardIOS(
                    news: news,
                    context: context,
                    searchView: false,
                    itemIndex: 0,
                    newsList: [news],
                  )
                : NewsCard(
                    news: news,
                    context: context,
                    searchView: false,
                    itemIndex: 0,
                    newsList: [news],
                  ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final ios in <bool>[false, true]) {
    testWidgets(
      '${ios ? 'iOS' : 'Android'} card keeps the date at the trailing edge',
      (tester) async {
        await tester.pumpWidget(_cardApp(ios: ios));

        final date = find.byWidgetPredicate(
          (widget) =>
              widget is Text && widget.data?.startsWith('8/11/26 ') == true,
          description: 'publication date text',
        );
        final card = find.ancestor(of: date, matching: find.byType(Card));
        expect(date, findsOneWidget);
        expect(card, findsOneWidget);
        expect(
          tester.getTopRight(card).dx - tester.getTopRight(date).dx,
          lessThanOrEqualTo(32),
        );
      },
    );

    testWidgets(
      '${ios ? 'iOS' : 'Android'} unstarred card gives empty star space to the feed title',
      (tester) async {
        const feedTitle =
            'A deliberately long feed title that needs all available width';
        await tester.pumpWidget(_cardApp(
          ios: ios,
          starred: false,
          feedTitle: feedTitle,
        ));

        final date = find.byWidgetPredicate(
          (widget) =>
              widget is Text && widget.data?.startsWith('8/11/26 ') == true,
          description: 'publication date text',
        );
        final title = find.text(feedTitle);
        expect(title, findsOneWidget);
        expect(date, findsOneWidget);
        expect(
          tester.getTopLeft(date).dx - tester.getTopRight(title).dx,
          closeTo(8, 0.1),
        );
      },
    );
  }
}
