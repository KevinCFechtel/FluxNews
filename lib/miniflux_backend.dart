import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import 'flux_news_state.dart';
import 'news_model.dart';

import 'package:http/http.dart' as http;

// this is the class to reflect the update status json body, which is send
// to the miniflux server to update the status of the news, which are provided
// by the entry ids.
class ReadNewsList {
  ReadNewsList({
    required this.newsIds,
    required this.status,
  });
  List<int> newsIds = [];
  String status = '';

  Map toJson() => {
        'entry_ids': newsIds,
        'status': status,
      };
}

// fetch all unread news from the miniflux backend
Future<NewsList> fetchNews(http.Client client, FluxNewsState appState) async {
  List<News> emptyList = [];
  // init the returning news list
  NewsList newsList = NewsList(news: emptyList, newsCount: 0);
  // init a temporary news list, which will be parsed from every
  // response of the miniflux server and then added to the news list
  // which was initialized above.
  NewsList tempNewsList = NewsList(news: emptyList, newsCount: 0);
  // set the size of the returned news initially to the maximum of news,
  // which will be provided by a response.
  // this size is set to 100.
  int listSize = FluxNewsState.amountOfNewlyCatchedNews;
  // set the offset (the amount of news, which should be skipped in the next response)
  // to zero for the first request.
  int offset = 0;
  // set the offset counter (multiplier) to 1 for the first request.
  int offsetCounter = 1;
  // check if the miniflux url and api key is set.
  if (appState.minifluxURL != null && appState.minifluxAPIKey != null) {
    // define the header for the request.
    // the header containes the api key and the accepted content type
    final header = {
      FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
      FluxNewsState.httpMinifluxAcceptHeaderString:
          FluxNewsState.httpContentTypeString,
    };
    // while the list size of the response is equal the defined maximum of news
    // which will be provided by a response, there are more unread news at the
    // miniflux server.
    // so we need to update the offset, to skip the already transfered amount of news
    // and to request the unread news again until the list size is lower as the maximum
    // of news provided by a response.
    // this is a kind of pagination.
    while (listSize == FluxNewsState.amountOfNewlyCatchedNews) {
      // request the unread news with the parameter, how many news should be provided by
      // one response (limit) and the amount of news which should be skipped, because
      // they were already transfered (offset).
      final response = await client.get(
          Uri.parse(
              '${appState.minifluxURL!}entries?status=unread&order=published_at&direction=asc&limit=${FluxNewsState.amountOfNewlyCatchedNews}&offset=$offset'),
          headers: header);
      // only the response code 200 ist ok
      if (response.statusCode == 200) {
        // parse the body to the temp news list
        tempNewsList =
            NewsList.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
        // add the temp news list to the returning news list
        newsList.news.addAll(tempNewsList.news);
        // add the news count to the returning news list (this is the same count for every iteration)
        newsList.newsCount = tempNewsList.newsCount;
        // update the list size to the count of the provided news
        listSize = tempNewsList.news.length;
        // update the offset to the maximum of provided news for each request,
        // multiplied by a incrementing counter
        offset = FluxNewsState.amountOfNewlyCatchedNews * offsetCounter;
        // increment the offset counter for the next run
        offsetCounter++;
      } else {
        // if the status is not 200, throw a exception
        throw FluxNewsState.httpUnexpectedResponseErrorString;
      }
    }
    // return the news list
    return newsList;
  } else {
    // return an empty news list
    return newsList;
  }
}

// fetch the bookmarked news from the miniflux server
// this is the same procedure as described above
// the only difference is that the requested parameter is
// starred=true and not status=unread
// for details of the implementation see the comments above
Future<NewsList> fetchStarredNews(
    http.Client client, FluxNewsState appState) async {
  List<News> emptyList = [];
  NewsList newsList = NewsList(news: emptyList, newsCount: 0);
  NewsList tempNewsList = NewsList(news: emptyList, newsCount: 0);
  int listSize = FluxNewsState.amountOfNewlyCatchedNews;
  int offset = 0;
  int offsetCounter = 1;
  if (appState.minifluxURL != null && appState.minifluxAPIKey != null) {
    final header = {
      FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
      FluxNewsState.httpMinifluxAcceptHeaderString:
          FluxNewsState.httpContentTypeString,
    };
    while (listSize == FluxNewsState.amountOfNewlyCatchedNews) {
      final response = await client.get(
          Uri.parse(
              '${appState.minifluxURL!}entries?starred=true&order=published_at&direction=asc&limit=${FluxNewsState.amountOfNewlyCatchedNews}&offset=$offset'),
          headers: header);
      if (response.statusCode == 200) {
        tempNewsList =
            NewsList.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
        newsList.news.addAll(tempNewsList.news);
        newsList.newsCount = tempNewsList.newsCount;
        listSize = tempNewsList.news.length;
        offset = FluxNewsState.amountOfNewlyCatchedNews * offsetCounter;
        offsetCounter++;
      } else {
        throw FluxNewsState.httpUnexpectedResponseErrorString;
      }
    }
    return newsList;
  } else {
    return newsList;
  }
}

// search news with the given search string on the miniflux server
// this is the same procedure as fetchNews
// the only difference is that the requested parameter is
// starred=true and not status=unread
// for details of the implementation see the comments above
Future<List<News>> fetchSearchedNews(
    http.Client client, FluxNewsState appState, String searchString) async {
  // init a empty news list
  List<News> newList = [];
  // init a temporary news list, which will be parsed from every
  // response of the miniflux server and then added to the news list
  // which was initialized above.
  NewsList tempNewsList = NewsList(news: newList, newsCount: 0);
  // set the size of the returned news initially to the maximum of news,
  // which will be provided by a response.
  // this size is set to 100.
  int listSize = FluxNewsState.amountOfNewlyCatchedNews;
  // set the offset (the amount of news, which should be skipped in the next response)
  // to zero for the first request.
  int offset = 0;
  // set the offset counter (multiplier) to 1 for the first request.
  int offsetCounter = 1;
  // check if the miniflux url and api key is set.
  if (appState.minifluxURL != null && appState.minifluxAPIKey != null) {
    // define the header for the request.
    // the header containes the api key and the accepted content type
    final header = {
      FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
      FluxNewsState.httpMinifluxAcceptHeaderString:
          FluxNewsState.httpContentTypeString,
    };
    // while the list size of the response is equal the defined maximum of news
    // which will be provided by a response, there are more unread news at the
    // miniflux server.
    // so we need to update the offset, to skip the already transfered amount of news
    // and to request the unread news again until the list size is lower as the maximum
    // of news provided by a response.
    // this is a kind of pagination.
    while (listSize == FluxNewsState.amountOfNewlyCatchedNews) {
      // request the unread news with the parameter, how many news should be provided by
      // one response (limit) and the amount of news which should be skipped, because
      // they were already transfered (offset).
      final response = await client.get(
          Uri.parse(
              '${appState.minifluxURL!}entries?search=$searchString&order=published_at&direction=asc&limit=${FluxNewsState.amountOfNewlyCatchedNews}&offset=$offset'),
          headers: header);
      // only the response code 200 ist ok
      if (response.statusCode == 200) {
        tempNewsList =
            NewsList.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
        // add the news of the response to the news list
        newList.addAll(tempNewsList.news);
        // update the list size to the count of the provided news
        listSize = tempNewsList.news.length;
        // update the offset to the maximum of provided news for each request,
        // multiplied by a incrementing counter
        offset = FluxNewsState.amountOfNewlyCatchedNews * offsetCounter;
        // increment the offset counter for the next run
        offsetCounter++;
      } else {
        // if the status is not 200, throw a exception
        throw FluxNewsState.httpUnexpectedResponseErrorString;
      }
    }
    // Auslesen der Feed Icons
    // check if the database is initialized
    // if not, initialize the database
    appState.db ??= await appState.initializeDB();
    if (appState.db != null) {
      // for each news in the list, get the feed icon from the database
      for (News news in newList) {
        // get the feed icon from the database
        List<Map<String, Object?>> queryResult = await appState.db!
            .rawQuery('SELECT * FROM feeds WHERE feedID = ?', [news.feedID]);
        // if the query result is not empty, set the icon and the icon mime type
        news.icon = queryResult.map((e) {
          if (e['icon'] != null) {
            return e['icon'] as Uint8List;
          } else {
            return null;
          }
        }).first;

        // get the feed icon mime type from the database
        news.iconMimeType = queryResult.map((e) {
          if (e['iconMimeType'] != null) {
            return e['iconMimeType'] as String;
          } else {
            return null;
          }
        }).first;
      }
    }
    // return the news list
    return newList;
  } else {
    // if the miniflux url or api key is not set, return the empty news list
    return newList;
  }
}

// mark the news as read at the miniflux server
Future<void> toggleNewsAsRead(
    http.Client client, FluxNewsState appState) async {
  // check if the miniflux url and api key is set
  if (appState.minifluxURL != null && appState.minifluxAPIKey != null) {
    List<int> newsIds = [];
    appState.db ??= await appState.initializeDB();
    if (appState.db != null) {
      // query the database for all news with the status read and the sync status not synced
      final List<Map<String, Object?>> queryResult = await appState.db!
          .rawQuery(
              'SELECT * FROM news WHERE status LIKE ? AND syncStatus = ?', [
        FluxNewsState.readNewsStatus,
        FluxNewsState.notSyncedSyncStatus
      ]);
      List<News> newsList = queryResult.map((e) => News.fromMap(e)).toList();
      // iterate over the news list and add the news id to the news id list
      for (News news in newsList) {
        newsIds.add(news.newsID);
      }
      // if the news id list is not empty, create a new ReadNewsList object
      if (newsIds.isNotEmpty) {
        // add the news id list and the status to the ReadNewsList object
        ReadNewsList newReadNewsList = ReadNewsList(
            newsIds: newsIds, status: FluxNewsState.readNewsStatus);
        final header = {
          FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
          FluxNewsState.httpMinifluxContentTypeHeaderString:
              FluxNewsState.httpContentTypeString,
        };
        // send the ReadNewsList object to the miniflux server to mark the news as read
        final response = await client.put(
            Uri.parse('${appState.minifluxURL!}entries'),
            headers: header,
            body: jsonEncode(newReadNewsList));
        if (response.statusCode != 204) {
          // if the response code is not 204, throw a error
          throw FluxNewsState.httpUnexpectedResponseErrorString;
        } else {
          // if the response code is 204, update the sync status of the news in the database to synced
          for (News news in newsList) {
            await appState.db!.rawUpdate(
                'UPDATE news SET syncStatus = ? WHERE newsId = ?',
                [FluxNewsState.syncedSyncStatus, news.newsID]);
          }
        }
      }
    }
  }
}

// mark one news directly as read at the miniflux server
Future<void> toggleOneNewsAsRead(
    http.Client client, FluxNewsState appState, News news) async {
  // check if the miniflux url and api key is set
  if (appState.minifluxURL != null && appState.minifluxAPIKey != null) {
    List<int> newsIds = [];

    newsIds.add(news.newsID);
    ReadNewsList newReadNewsList =
        ReadNewsList(newsIds: newsIds, status: news.status);
    final header = {
      FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
      FluxNewsState.httpMinifluxContentTypeHeaderString:
          FluxNewsState.httpContentTypeString,
    };
    // send the ReadNewsList object to the miniflux server to mark the news as read
    final response = await client.put(
        Uri.parse('${appState.minifluxURL!}entries'),
        headers: header,
        body: jsonEncode(newReadNewsList));
    if (response.statusCode != 204) {
      // if the response code is not 204, throw a error
      throw FluxNewsState.httpUnexpectedResponseErrorString;
    }
  }
}

// mark a news as bookmarked at the miniflux server
Future<void> toggleBookmark(
    http.Client client, FluxNewsState appState, News news) async {
  // first check if the miniflux url and api key is set
  if (appState.minifluxURL != null && appState.minifluxAPIKey != null) {
    appState.db ??= await appState.initializeDB();
    if (appState.db != null) {
      final header = {
        FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
      };
      // toggle the bookmark status of the news at the miniflux server
      final response = await client.put(
        Uri.parse('${appState.minifluxURL!}entries/${news.newsID}/bookmark'),
        headers: header,
      );
      if (response.statusCode != 204) {
        // if the response code is not 204, throw an error
        throw FluxNewsState.httpUnexpectedResponseErrorString;
      } else {
        // if the response code is 204, update the bookmark status of the news in the database
        await appState.db!.rawUpdate(
            'UPDATE news SET starred = ? WHERE newsId = ?',
            [news.starred ? 1 : 0, news.newsID]);
      }
    }
  }
}

// fetch the information about the categories from the miniflux server
Future<Categories> fetchCategorieInformation(
    http.Client client, FluxNewsState appState) async {
  List<Categorie> newCategorieList = [];
  http.Response response;
  // first check if the miniflux url and api key is set
  if (appState.minifluxURL != null && appState.minifluxAPIKey != null) {
    appState.db ??= await appState.initializeDB();
    if (appState.db != null) {
      final header = {
        FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
        FluxNewsState.httpMinifluxAcceptHeaderString:
            FluxNewsState.httpContentTypeString,
      };
      // then request the categories from the miniflux server
      response = await client.get(
        Uri.parse('${appState.minifluxURL!}categories'),
        headers: header,
      );
      if (response.statusCode != 200) {
        // if the response code is not 200, throw an error
        throw FluxNewsState.httpUnexpectedResponseErrorString;
      } else {
        // if the response code is 200, decode the response body and create a new Categories list
        Iterable l = json.decode(utf8.decode(response.bodyBytes));
        newCategorieList =
            List<Categorie>.from(l.map((model) => Categorie.fromJson(model)));

        // iterate over the categories list and request the feeds for each category
        for (Categorie categorie in newCategorieList) {
          List<Feed> feedList = [];
          response = await client.get(
            Uri.parse(
                '${appState.minifluxURL!}categories/${categorie.categorieID}/feeds'),
            headers: header,
          );
          if (response.statusCode != 200) {
            // if the response code is not 200, throw an error
            throw FluxNewsState.httpUnexpectedResponseErrorString;
          } else {
            // if the response code is 200, decode the response body and create a new Feeds list
            Iterable l = json.decode(utf8.decode(response.bodyBytes));
            feedList = List<Feed>.from(l.map((model) => Feed.fromJson(model)));

            // iterate over the feeds list and query the database for the news count of the feed
            for (Feed feed in feedList) {
              int? count;
              count = Sqflite.firstIntValue(await appState.db!.rawQuery(
                  'SELECT COUNT(*) FROM news WHERE feedID = ?', [feed.feedID]));
              count ??= 0;

              // add the news count to the feed object
              feed.newsCount = count;

              // if the feed icon id is not null, request the feed icon from the miniflux server
              if (feed.feedIconID != null) {
                response = await client.get(
                  Uri.parse(
                      '${appState.minifluxURL!}feeds/${feed.feedID}/icon'),
                  headers: header,
                );
                if (response.statusCode != 200) {
                  // if the response code is not 200, throw an error
                  throw FluxNewsState.httpUnexpectedResponseErrorString;
                } else {
                  FeedIcon feedIcon = FeedIcon.fromJson(
                      jsonDecode(utf8.decode(response.bodyBytes)));
                  feed.icon = feedIcon.getIcon();
                  feed.iconMimeType = feedIcon.iconMimeType;
                }
              }
            }
          }
          // add the feed list to the categorie object
          categorie.feeds = feedList;
        }
      }
    }
  }
  // return the new categories list
  Categories newCategories = Categories(categories: newCategorieList);
  return newCategories;
}

// fetch the feed icon from the miniflux server
Future<FeedIcon?> getFeedIcon(
    http.Client client, FluxNewsState appState, int feedID) async {
  http.Response response;
  FeedIcon? feedIcon;
  // first check if the miniflux url and api key is set
  if (appState.minifluxURL != null && appState.minifluxAPIKey != null) {
    appState.db ??= await appState.initializeDB();
    if (appState.db != null) {
      // then request the feed icon from the miniflux server
      final header = {
        FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
        FluxNewsState.httpMinifluxAcceptHeaderString:
            FluxNewsState.httpContentTypeString,
      };
      response = await client.get(
        Uri.parse('${appState.minifluxURL!}feeds/$feedID/icon'),
        headers: header,
      );
      if (response.statusCode != 200) {
        // if the response code is not 200, throw an error
        throw FluxNewsState.httpUnexpectedResponseErrorString;
      } else {
        // if the response code is 200, decode the response body and create a new FeedIcon object
        feedIcon =
            FeedIcon.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
      }
    }
  }
  // return the feed icon
  return feedIcon;
}

// check if the miniflux credentials are valid
Future<bool> checkMinifluxCredentials(
    http.Client client, String? miniFluxUrl, String? miniFluxApiKey) async {
  // first check if the miniflux url and api key is set
  if (miniFluxApiKey != null && miniFluxUrl != null) {
    final header = {
      FluxNewsState.httpMinifluxAuthHeaderString: miniFluxApiKey,
      FluxNewsState.httpMinifluxAcceptHeaderString:
          FluxNewsState.httpContentTypeString,
    };
    // then request the user information from the miniflux server
    final response =
        await client.get(Uri.parse('${miniFluxUrl}me'), headers: header);
    if (response.statusCode == 200) {
      // if the response code is 200, the credentials are valid
      return true;
    } else {
      // if the response code is not 200, the credentials are invalid
      return false;
    }
  } else {
    // if the miniflux url or api key is not set, the credentials are invalid
    return false;
  }
}
