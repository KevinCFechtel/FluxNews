import 'package:flutter_test/flutter_test.dart';
import 'package:flux_news/flux_news_body.dart';
import 'package:flux_news/flux_news_state.dart';

import 'package:flux_news/main.dart';
import 'package:flux_news/miniflux_backend.dart';
import 'package:flux_news/news_model.dart';

import 'package:http/http.dart' as http;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'miniflux_backend_test.mocks.dart';

@GenerateMocks([http.Client])
void main() {
  late Database database;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('''CREATE TABLE news(newsID INTEGER PRIMARY KEY, 
                          feedID INTEGER, 
                          title TEXT, 
                          url TEXT, 
                          content TEXT, 
                          hash TEXT, 
                          publishedAt TEXT, 
                          createdAt TEXT, 
                          status TEXT, 
                          readingTime INTEGER, 
                          starred INTEGER, 
                          feedTitle TEXT, 
                          syncStatus TEXT)''');
    var newNews = News(
        newsID: 1,
        feedID: 1,
        title: "Test",
        url: "https://test.de",
        content: "Test",
        hash: "Test",
        publishedAt: "2023-04-24T19:38:05+02:00",
        createdAt: "2023-04-24T19:38:05+02:00",
        status: "unread",
        readingTime: 2,
        starred: true,
        feedTitel: "Test");
    await database.insert('news', newNews.toMap());
  });

  group('miniflux backend', () {
    testWidgets('fetchNews success test', (WidgetTester tester) async {
      await tester.pumpWidget(const FluxNews());
      var fluxNewsApp = tester.firstState(find.byType(FluxNewsBody));
      FluxNewsState appState = fluxNewsApp.context.read<FluxNewsState>();
      var offset = 0;
      appState.minifluxURL = 'https://circle-dev.local/v1/';
      appState.minifluxAPIKey = 'test';

      final client = MockClient();
      final header = {
        FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
        FluxNewsState.httpMinifluxAcceptHeaderString:
            FluxNewsState.httpContentTypeString,
      };

      when(client.get(
              Uri.parse(
                  '${appState.minifluxURL}entries?status=unread&order=published_at&direction=asc&limit=${FluxNewsState.amountOfNewlyCatchedNews}&offset=$offset'),
              headers: header))
          .thenAnswer((_) async => http.Response('''{
        "total": 5,
        "entries": [
          {
            "id": 21123,
            "user_id": 1,
            "feed_id": 5,
            "status": "unread",
            "hash": "d9de31980f4c56619b8b4ad61e3406164b5bf70f7c1b6c51c433368681e9dd8d",
            "title": "Test Title 1",
            "url": "https://circle-dev.local/Url1",
            "comments_url": "",
            "published_at": "2023-04-24T19:38:05+02:00",
            "created_at": "2023-04-24T19:45:34.261091+02:00",
            "changed_at": "2023-04-24T19:45:34.261091+02:00",
            "content": "Test Content 1",
            "author": "",
            "share_code": "",
            "starred": false,
            "reading_time": 1,
            "enclosures": null,
            "feed": {
              "id": 5,
              "user_id": 1,
              "feed_url": "https://circle-dev.local/feed",
              "site_url": "https://circle-dev.local/",
              "title": "Circle-Dev",
              "checked_at": "2023-04-24T20:00:34.001097+02:00",
              "next_check_at": "0001-01-01T00:00:00Z",
              "etag_header": "",
              "last_modified_header": "",
              "parsing_error_message": "",
              "parsing_error_count": 0,
              "scraper_rules": "",
              "rewrite_rules": "",
              "crawler": false,
              "blocklist_rules": "",
              "keeplist_rules": "",
              "urlrewrite_rules": "",
              "user_agent": "",
              "cookie": "",
              "username": "",
              "password": "",
              "disabled": false,
              "ignore_http_cache": false,
              "allow_self_signed_certificates": false,
              "fetch_via_proxy": false,
              "category": {
                "id": 3,
                "title": "Circle-Dev",
                "user_id": 1,
                "hide_globally": false
              },
              "icon": {
                "feed_id": 5,
                "icon_id": 4
              },
              "hide_globally": false
            },
            "tags": [
              "International"
            ]
          },
          {
            "id": 21124,
            "user_id": 1,
            "feed_id": 5,
            "status": "unread",
            "hash": "d9de31980f4c56619b8b4ad61e3406164b5bf70f7c1b6c51c433368681e9dd8d",
            "title": "Test Title 2",
            "url": "https://circle-dev.local/Url2",
            "comments_url": "",
            "published_at": "2023-04-24T19:38:05+02:00",
            "created_at": "2023-04-24T19:45:34.261091+02:00",
            "changed_at": "2023-04-24T19:45:34.261091+02:00",
            "content": "Test Content 2",
            "author": "",
            "share_code": "",
            "starred": false,
            "reading_time": 1,
            "enclosures": null,
            "feed": {
              "id": 5,
              "user_id": 1,
              "feed_url": "https://circle-dev.local/feed",
              "site_url": "https://circle-dev.local/",
              "title": "Circle-Dev",
              "checked_at": "2023-04-24T20:00:34.001097+02:00",
              "next_check_at": "0001-01-01T00:00:00Z",
              "etag_header": "",
              "last_modified_header": "",
              "parsing_error_message": "",
              "parsing_error_count": 0,
              "scraper_rules": "",
              "rewrite_rules": "",
              "crawler": false,
              "blocklist_rules": "",
              "keeplist_rules": "",
              "urlrewrite_rules": "",
              "user_agent": "",
              "cookie": "",
              "username": "",
              "password": "",
              "disabled": false,
              "ignore_http_cache": false,
              "allow_self_signed_certificates": false,
              "fetch_via_proxy": false,
              "category": {
                "id": 3,
                "title": "Circle-Dev",
                "user_id": 1,
                "hide_globally": false
              },
              "icon": {
                "feed_id": 5,
                "icon_id": 4
              },
              "hide_globally": false
            },
            "tags": [
              "International"
            ]
          },
          {
            "id": 21125,
            "user_id": 1,
            "feed_id": 5,
            "status": "unread",
            "hash": "d9de31980f4c56619b8b4ad61e3406164b5bf70f7c1b6c51c433368681e9dd8d",
            "title": "Test Title 3",
            "url": "https://circle-dev.local/Url3",
            "comments_url": "",
            "published_at": "2023-04-24T19:38:05+02:00",
            "created_at": "2023-04-24T19:45:34.261091+02:00",
            "changed_at": "2023-04-24T19:45:34.261091+02:00",
            "content": "Test Content 1",
            "author": "",
            "share_code": "",
            "starred": false,
            "reading_time": 1,
            "enclosures": null,
            "feed": {
              "id": 5,
              "user_id": 1,
              "feed_url": "https://circle-dev.local/feed",
              "site_url": "https://circle-dev.local/",
              "title": "Circle-Dev",
              "checked_at": "2023-04-24T20:00:34.001097+02:00",
              "next_check_at": "0001-01-01T00:00:00Z",
              "etag_header": "",
              "last_modified_header": "",
              "parsing_error_message": "",
              "parsing_error_count": 0,
              "scraper_rules": "",
              "rewrite_rules": "",
              "crawler": false,
              "blocklist_rules": "",
              "keeplist_rules": "",
              "urlrewrite_rules": "",
              "user_agent": "",
              "cookie": "",
              "username": "",
              "password": "",
              "disabled": false,
              "ignore_http_cache": false,
              "allow_self_signed_certificates": false,
              "fetch_via_proxy": false,
              "category": {
                "id": 3,
                "title": "Circle-Dev",
                "user_id": 1,
                "hide_globally": false
              },
              "icon": {
                "feed_id": 5,
                "icon_id": 4
              },
              "hide_globally": false
            },
            "tags": [
              "International"
            ]
          },
          {
            "id": 21126,
            "user_id": 1,
            "feed_id": 5,
            "status": "unread",
            "hash": "d9de31980f4c56619b8b4ad61e3406164b5bf70f7c1b6c51c433368681e9dd8d",
            "title": "Test Title 4",
            "url": "https://circle-dev.local/Url4",
            "comments_url": "",
            "published_at": "2023-04-24T19:38:05+02:00",
            "created_at": "2023-04-24T19:45:34.261091+02:00",
            "changed_at": "2023-04-24T19:45:34.261091+02:00",
            "content": "Test Content 4",
            "author": "",
            "share_code": "",
            "starred": false,
            "reading_time": 1,
            "enclosures": null,
            "feed": {
              "id": 5,
              "user_id": 1,
              "feed_url": "https://circle-dev.local/feed",
              "site_url": "https://circle-dev.local/",
              "title": "Circle-Dev",
              "checked_at": "2023-04-24T20:00:34.001097+02:00",
              "next_check_at": "0001-01-01T00:00:00Z",
              "etag_header": "",
              "last_modified_header": "",
              "parsing_error_message": "",
              "parsing_error_count": 0,
              "scraper_rules": "",
              "rewrite_rules": "",
              "crawler": false,
              "blocklist_rules": "",
              "keeplist_rules": "",
              "urlrewrite_rules": "",
              "user_agent": "",
              "cookie": "",
              "username": "",
              "password": "",
              "disabled": false,
              "ignore_http_cache": false,
              "allow_self_signed_certificates": false,
              "fetch_via_proxy": false,
              "category": {
                "id": 3,
                "title": "Circle-Dev",
                "user_id": 1,
                "hide_globally": false
              },
              "icon": {
                "feed_id": 5,
                "icon_id": 4
              },
              "hide_globally": false
            },
            "tags": [
              "International"
            ]
          },
          {
            "id": 21127,
            "user_id": 1,
            "feed_id": 5,
            "status": "unread",
            "hash": "d9de31980f4c56619b8b4ad61e3406164b5bf70f7c1b6c51c433368681e9dd8d",
            "title": "Test Title 5",
            "url": "https://circle-dev.local/Url5",
            "comments_url": "",
            "published_at": "2023-04-24T19:38:05+02:00",
            "created_at": "2023-04-24T19:45:34.261091+02:00",
            "changed_at": "2023-04-24T19:45:34.261091+02:00",
            "content": "Test Content 5",
            "author": "",
            "share_code": "",
            "starred": false,
            "reading_time": 1,
            "enclosures": null,
            "feed": {
              "id": 5,
              "user_id": 1,
              "feed_url": "https://circle-dev.local/feed",
              "site_url": "https://circle-dev.local/",
              "title": "Circle-Dev",
              "checked_at": "2023-04-24T20:00:34.001097+02:00",
              "next_check_at": "0001-01-01T00:00:00Z",
              "etag_header": "",
              "last_modified_header": "",
              "parsing_error_message": "",
              "parsing_error_count": 0,
              "scraper_rules": "",
              "rewrite_rules": "",
              "crawler": false,
              "blocklist_rules": "",
              "keeplist_rules": "",
              "urlrewrite_rules": "",
              "user_agent": "",
              "cookie": "",
              "username": "",
              "password": "",
              "disabled": false,
              "ignore_http_cache": false,
              "allow_self_signed_certificates": false,
              "fetch_via_proxy": false,
              "category": {
                "id": 3,
                "title": "Circle-Dev",
                "user_id": 1,
                "hide_globally": false
              },
              "icon": {
                "feed_id": 5,
                "icon_id": 4
              },
              "hide_globally": false
            },
            "tags": [
              "International"
            ]
          }
        ]
      }''', 200));

      var newsList = await fetchNews(client, appState);
      expect(newsList, isA<NewsList>());
      expect(newsList.newsCount == 5, isTrue);
      expect(newsList.news.length == 5, isTrue);
      expect(newsList.news.first.title == 'Test Title 1', isTrue);
    });
    testWidgets('fetchNews failure test', (WidgetTester tester) async {
      await tester.pumpWidget(const FluxNews());
      var fluxNewsApp = tester.firstState(find.byType(FluxNewsBody));
      FluxNewsState appState = fluxNewsApp.context.read<FluxNewsState>();
      var offset = 0;
      appState.minifluxURL = 'https://circle-dev.local/v1/';
      appState.minifluxAPIKey = 'test';

      final client = MockClient();
      final header = {
        FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
        FluxNewsState.httpMinifluxAcceptHeaderString:
            FluxNewsState.httpContentTypeString,
      };
      when(client.get(
              Uri.parse(
                  '${appState.minifluxURL!}entries?status=unread&order=published_at&direction=asc&limit=${FluxNewsState.amountOfNewlyCatchedNews}&offset=$offset'),
              headers: header))
          .thenAnswer((_) async => http.Response('Internal server error', 500));

      try {
        await fetchNews(client, appState);
        fail("exception not thrown");
      } catch (e) {
        expect(e.toString() == FluxNewsState.httpUnexpectedResponseErrorString,
            isTrue);
      }
    });

    testWidgets('fetchStarredNews success test', (WidgetTester tester) async {
      await tester.pumpWidget(const FluxNews());
      var fluxNewsApp = tester.firstState(find.byType(FluxNewsBody));
      FluxNewsState appState = fluxNewsApp.context.read<FluxNewsState>();
      var offset = 0;
      appState.minifluxURL = 'https://circle-dev.local/v1/';
      appState.minifluxAPIKey = 'test';

      final client = MockClient();
      final header = {
        FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
        FluxNewsState.httpMinifluxAcceptHeaderString:
            FluxNewsState.httpContentTypeString,
      };

      when(client.get(
              Uri.parse(
                  '${appState.minifluxURL}entries?starred=true&order=published_at&direction=asc&limit=${FluxNewsState.amountOfNewlyCatchedNews}&offset=$offset'),
              headers: header))
          .thenAnswer((_) async => http.Response('''{
        "total": 2,
        "entries": [
          {
            "id": 21123,
            "user_id": 1,
            "feed_id": 5,
            "status": "unread",
            "hash": "d9de31980f4c56619b8b4ad61e3406164b5bf70f7c1b6c51c433368681e9dd8d",
            "title": "Test Title 1",
            "url": "https://circle-dev.local/Url1",
            "comments_url": "",
            "published_at": "2023-04-24T19:38:05+02:00",
            "created_at": "2023-04-24T19:45:34.261091+02:00",
            "changed_at": "2023-04-24T19:45:34.261091+02:00",
            "content": "Test Content 1",
            "author": "",
            "share_code": "",
            "starred": false,
            "reading_time": 1,
            "enclosures": null,
            "feed": {
              "id": 5,
              "user_id": 1,
              "feed_url": "https://circle-dev.local/feed",
              "site_url": "https://circle-dev.local/",
              "title": "Circle-Dev",
              "checked_at": "2023-04-24T20:00:34.001097+02:00",
              "next_check_at": "0001-01-01T00:00:00Z",
              "etag_header": "",
              "last_modified_header": "",
              "parsing_error_message": "",
              "parsing_error_count": 0,
              "scraper_rules": "",
              "rewrite_rules": "",
              "crawler": false,
              "blocklist_rules": "",
              "keeplist_rules": "",
              "urlrewrite_rules": "",
              "user_agent": "",
              "cookie": "",
              "username": "",
              "password": "",
              "disabled": false,
              "ignore_http_cache": false,
              "allow_self_signed_certificates": false,
              "fetch_via_proxy": false,
              "category": {
                "id": 3,
                "title": "Circle-Dev",
                "user_id": 1,
                "hide_globally": false
              },
              "icon": {
                "feed_id": 5,
                "icon_id": 4
              },
              "hide_globally": false
            },
            "tags": [
              "International"
            ]
          },
          {
            "id": 21124,
            "user_id": 1,
            "feed_id": 5,
            "status": "unread",
            "hash": "d9de31980f4c56619b8b4ad61e3406164b5bf70f7c1b6c51c433368681e9dd8d",
            "title": "Test Title 2",
            "url": "https://circle-dev.local/Url2",
            "comments_url": "",
            "published_at": "2023-04-24T19:38:05+02:00",
            "created_at": "2023-04-24T19:45:34.261091+02:00",
            "changed_at": "2023-04-24T19:45:34.261091+02:00",
            "content": "Test Content 2",
            "author": "",
            "share_code": "",
            "starred": false,
            "reading_time": 1,
            "enclosures": null,
            "feed": {
              "id": 5,
              "user_id": 1,
              "feed_url": "https://circle-dev.local/feed",
              "site_url": "https://circle-dev.local/",
              "title": "Circle-Dev",
              "checked_at": "2023-04-24T20:00:34.001097+02:00",
              "next_check_at": "0001-01-01T00:00:00Z",
              "etag_header": "",
              "last_modified_header": "",
              "parsing_error_message": "",
              "parsing_error_count": 0,
              "scraper_rules": "",
              "rewrite_rules": "",
              "crawler": false,
              "blocklist_rules": "",
              "keeplist_rules": "",
              "urlrewrite_rules": "",
              "user_agent": "",
              "cookie": "",
              "username": "",
              "password": "",
              "disabled": false,
              "ignore_http_cache": false,
              "allow_self_signed_certificates": false,
              "fetch_via_proxy": false,
              "category": {
                "id": 3,
                "title": "Circle-Dev",
                "user_id": 1,
                "hide_globally": false
              },
              "icon": {
                "feed_id": 5,
                "icon_id": 4
              },
              "hide_globally": false
            },
            "tags": [
              "International"
            ]
          }
        ]
      }''', 200));

      var newsList = await fetchStarredNews(client, appState);
      expect(newsList, isA<NewsList>());
      expect(newsList.newsCount == 2, isTrue);
      expect(newsList.news.length == 2, isTrue);
      expect(newsList.news.first.title == 'Test Title 1', isTrue);
    });
    testWidgets('fetchStarredNews failure test', (WidgetTester tester) async {
      await tester.pumpWidget(const FluxNews());
      var fluxNewsApp = tester.firstState(find.byType(FluxNewsBody));
      FluxNewsState appState = fluxNewsApp.context.read<FluxNewsState>();
      var offset = 0;
      appState.minifluxURL = 'https://circle-dev.local/v1/';
      appState.minifluxAPIKey = 'test';

      final client = MockClient();
      final header = {
        FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
        FluxNewsState.httpMinifluxAcceptHeaderString:
            FluxNewsState.httpContentTypeString,
      };
      when(client.get(
              Uri.parse(
                  '${appState.minifluxURL!}entries?starred=true&order=published_at&direction=asc&limit=${FluxNewsState.amountOfNewlyCatchedNews}&offset=$offset'),
              headers: header))
          .thenAnswer((_) async => http.Response('Internal server error', 500));

      try {
        await fetchStarredNews(client, appState);
        fail("exception not thrown");
      } catch (e) {
        expect(e.toString() == FluxNewsState.httpUnexpectedResponseErrorString,
            isTrue);
      }
    });
    testWidgets('toggleNewsAsRead failure test', (WidgetTester tester) async {
      await tester.pumpWidget(const FluxNews());
      var fluxNewsApp = tester.firstState(find.byType(FluxNewsBody));
      FluxNewsState appState = fluxNewsApp.context.read<FluxNewsState>();
      appState.db = database;
      appState.minifluxURL = 'https://circle-dev.local/v1/';
      appState.minifluxAPIKey = 'test';
      final client = MockClient();
      final header = {
        FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
        FluxNewsState.httpMinifluxContentTypeHeaderString:
            FluxNewsState.httpContentTypeString,
      };

      when(client.put(Uri.parse('${appState.minifluxURL!}entries'),
              headers: header))
          .thenAnswer((_) async => http.Response('Internal server error', 500));

      try {
        await toggleNewsAsRead(client, appState);
        fail("exception not thrown");
      } catch (e) {
        expect(e.toString() == FluxNewsState.httpUnexpectedResponseErrorString,
            isTrue);
      }
      /*
      await database.close();
      expect(database.isOpen, false);

      */
    });
  });
}
