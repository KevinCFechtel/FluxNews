import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/state_management/flux_news_state.dart';

News _news({required String content}) {
  return News(
    newsID: 1,
    feedID: 1,
    title: 'Title',
    url: 'https://example.com/article',
    commentsUrl: '',
    shareCode: '',
    content: content,
    hash: 'hash',
    publishedAt: '2026-07-03T10:00:00Z',
    createdAt: '2026-07-03T10:00:00Z',
    status: FluxNewsState.unreadNewsStatus,
    readingTime: 1,
    starred: false,
    feedTitle: 'Feed',
  );
}

void main() {
  test('image URL cache is invalidated when article content changes', () {
    final news = _news(
      content: '<p>Text</p><img src="https://example.com/first.jpg">',
    );

    expect(news.getImageURL(), 'https://example.com/first.jpg');

    news.content = '<p>Updated</p><img src="https://example.com/second.jpg">';
    expect(news.getImageURL(), 'https://example.com/second.jpg');
  });

  test('image URL cache respects attachment preference changes', () {
    final news = _news(
      content: '<img src="https://example.com/article.jpg">',
    );
    news.attachments = [
      Attachment(
        attachmentID: 1,
        newsID: 1,
        attachmentURL: 'https://example.com/attachment.jpg',
        attachmentMimeType: 'image/jpeg',
      ),
    ];

    expect(news.getImageURL(), 'https://example.com/article.jpg');

    news.preferAttachmentImage = true;
    expect(news.getImageURL(), 'https://example.com/attachment.jpg');
  });

  test('prepared metadata respects preferred attachment image', () {
    final news = _news(
      content: '<p>Article text</p><img src="https://example.com/article.jpg">',
    )
      ..attachments = [
        Attachment(
          attachmentID: 1,
          newsID: 1,
          attachmentURL: 'https://example.com/attachment.jpg',
          attachmentMimeType: 'image/jpeg',
        ),
      ]
      ..preferAttachmentImage = true;

    news.prepareListMetadata();

    expect(news.imageUrl, 'https://example.com/attachment.jpg');
    expect(news.previewText, contains('Article text'));
  });

  test('preview text cache respects truncation setting changes', () {
    final news = _news(content: '<p>1234567890</p>');
    final appState = FluxNewsState()
      ..activateTruncate = true
      ..charactersToTruncateLimit = 0
      ..charactersToTruncate = 5;

    final truncated = news.getText(appState);

    appState.activateTruncate = false;
    expect(news.getText(appState), isNot(truncated));
    expect(news.getText(appState), contains('1234567890'));
  });
}
