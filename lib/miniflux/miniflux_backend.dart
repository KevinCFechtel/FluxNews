import 'dart:convert';
import 'dart:io';

import 'package:cronet_http/cronet_http.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flux_news/functions/logging.dart';
import 'package:http/http.dart';
import 'package:http/io_client.dart';

import '../state_management/flux_news_state.dart';
import '../models/news_model.dart';

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

// fetch unread news from the miniflux backend
Future<NewsList> fetchNews(FluxNewsState appState) async {
  if (appState.debugMode) {
    logThis('fetchNews', 'Starting fetching news from miniflux server', LogLevel.INFO);
  }

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
  int listSize = FluxNewsState.amountOfNewlyCaughtNews;
  // set the offset (the amount of news, which should be skipped in the next response)
  // to zero for the first request.
  int offset = 0;
  // set the offset counter (multiplier) to 1 for the first request.
  int offsetCounter = 1;
  // init the string for the request
  String requestString = '';
  // decide if the sort order is ascending or descending
  String sortOrder = FluxNewsState.minifluxAscString;
  if (appState.sortOrder != null) {
    if (appState.sortOrder == FluxNewsState.sortOrderNewestFirstString) {
      sortOrder = FluxNewsState.minifluxDescString;
    } else {
      sortOrder = FluxNewsState.minifluxAscString;
    }
  }
  // check if the miniflux url and api key is set.
  if (appState.minifluxURL != null && appState.minifluxAPIKey != null) {
    final Client client;
    if (Platform.isAndroid) {
      final engine = CronetEngine.build(cacheMode: CacheMode.memory, cacheMaxSize: 2 * 1024 * 1024);
      client = CronetClient.fromCronetEngine(engine, closeEngine: true);
    } else {
      client = IOClient(HttpClient());
    }
    // define the header for the request.
    // the header contains the api key and the accepted content type
    final header = {
      FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
      FluxNewsState.httpMinifluxAcceptHeaderString: FluxNewsState.httpContentTypeString,
    };
    // while the list size of the response is equal the defined maximum of news
    // which will be provided by a response, there are more unread news at the
    // miniflux server.
    // so we need to update the offset, to skip the already transferred amount of news
    // and to request the unread news again until the list size is lower as the maximum
    // of news provided by a response.
    // this is a kind of pagination.
    String newsStatusToSync = '&status=unread';
    if (appState.syncReadNews) {
      newsStatusToSync = '';
      if (appState.syncReadNewsAfterDays > 0) {
        DateTime syncDate = DateTime.now().subtract(Duration(days: appState.syncReadNewsAfterDays));
        int syncDateTimestamp = (syncDate.toUtc().millisecondsSinceEpoch / 1000).round();
        newsStatusToSync = '$newsStatusToSync&after=$syncDateTimestamp';
      }
    }
    while (listSize == FluxNewsState.amountOfNewlyCaughtNews) {
      if (!appState.longSyncAborted) {
        requestString =
            '${appState.minifluxURL!}entries?order=published_at$newsStatusToSync&direction=$sortOrder&limit=${FluxNewsState.amountOfNewlyCaughtNews}&offset=$offset';
        // request the unread news with the parameter, how many news should be provided by
        // one response (limit) and the amount of news which should be skipped, because
        // they were already transferred (offset).
        final response = await client.get(Uri.parse(requestString), headers: header);
        // only the response code 200 ist ok
        if (response.statusCode == 200) {
          // parse the body to the temp news list
          tempNewsList = NewsList.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
          if (appState.debugMode) {
            logThis('fetchNews', '${tempNewsList.news.length} news fetched', LogLevel.INFO);
          }
          // add the temp news list to the returning news list
          newsList.news.addAll(tempNewsList.news);
          // check if the execution time will took very long
          if (tempNewsList.newsCount > FluxNewsState.amountForLongNewsSync) {
            if (tempNewsList.newsCount > FluxNewsState.amountForTooManyNews && appState.amountOfSyncedNews == 0) {
              // remove the native splash after updating the list view
              FlutterNativeSplash.remove();
              appState.tooManyNews = true;
              appState.longSyncAborted = true;
              appState.refreshView();
            } else {
              if (appState.amountOfSyncedNews > FluxNewsState.amountForLongNewsSync ||
                  appState.amountOfSyncedNews == 0) {
                if (!appState.longSync && !appState.longSyncAlerted) {
                  // remove the native splash after updating the list view
                  FlutterNativeSplash.remove();
                  if (!appState.skipLongSync) {
                    appState.longSync = true;
                  }
                  appState.refreshView();
                }
              }
            }
          }
          // add the news count to the returning news list (this is the same count for every iteration)
          newsList.newsCount = tempNewsList.newsCount;
          // update the list size to the count of the provided news
          listSize = tempNewsList.news.length;
          // update the offset to the maximum of provided news for each request,
          // multiplied by a incrementing counter
          offset = FluxNewsState.amountOfNewlyCaughtNews * offsetCounter;
          // increment the offset counter for the next run
          offsetCounter++;
          if (appState.debugMode) {
            if (listSize == FluxNewsState.amountOfNewlyCaughtNews) {
              logThis('fetchNews', '${tempNewsList.newsCount - offset} news remaining', LogLevel.INFO);
            } else {
              logThis('fetchNews', '0 news remaining', LogLevel.INFO);
            }
          }
          if (offset >= appState.amountOfSyncedNews && appState.amountOfSyncedNews != 0) {
            logThis('fetchNews', 'Reached limit of news to sync', LogLevel.INFO);
            break;
          }
        } else {
          logThis('fetchNews', 'Got unexpected response from miniflux server: ${response.statusCode} for unread news',
              LogLevel.ERROR);

          // if the status is not 200, throw a exception
          throw FluxNewsState.httpUnexpectedResponseErrorString;
        }
      } else {
        listSize = 0;
        if (appState.debugMode) {
          logThis('fetchNews', 'Aborted fetching news from miniflux server', LogLevel.INFO);
        }
      }
    }
    client.close();
    if (appState.debugMode) {
      logThis('fetchNews', 'Finished fetching news from miniflux server', LogLevel.INFO);
    }
    // return the news list
    return newsList;
  } else {
    if (appState.debugMode) {
      logThis('fetchNews', 'Finished fetching no new news from miniflux server', LogLevel.INFO);
    }
    // return an empty news list
    return newsList;
  }
}

// fetch the bookmarked news from the miniflux server
// this is the same procedure as described above
// the only difference is that the requested parameter is
// starred=true and not status=unread
// for details of the implementation see the comments above
Future<NewsList> fetchStarredNews(FluxNewsState appState) async {
  if (appState.debugMode) {
    logThis('fetchStarredNews', 'Starting fetching starred news from miniflux server', LogLevel.INFO);
  }

  List<News> emptyList = [];
  NewsList newsList = NewsList(news: emptyList, newsCount: 0);
  NewsList tempNewsList = NewsList(news: emptyList, newsCount: 0);
  int listSize = FluxNewsState.amountOfNewlyCaughtNews;
  int offset = 0;
  int offsetCounter = 1;
  String requestString = '';
  String sortOrder = FluxNewsState.minifluxAscString;
  if (appState.sortOrder != null) {
    if (appState.sortOrder == FluxNewsState.sortOrderNewestFirstString) {
      sortOrder = FluxNewsState.minifluxDescString;
    } else {
      sortOrder = FluxNewsState.minifluxAscString;
    }
  }
  if (appState.minifluxURL != null && appState.minifluxAPIKey != null) {
    final Client client;
    if (Platform.isAndroid) {
      final engine = CronetEngine.build(cacheMode: CacheMode.memory, cacheMaxSize: 2 * 1024 * 1024);
      client = CronetClient.fromCronetEngine(engine, closeEngine: true);
    } else {
      client = IOClient(HttpClient());
    }
    final header = {
      FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
      FluxNewsState.httpMinifluxAcceptHeaderString: FluxNewsState.httpContentTypeString,
    };
    while (listSize == FluxNewsState.amountOfNewlyCaughtNews) {
      requestString =
          '${appState.minifluxURL!}entries?starred=true&order=published_at&direction=$sortOrder&limit=${FluxNewsState.amountOfNewlyCaughtNews}&offset=$offset';
      final response = await client.get(Uri.parse(requestString), headers: header);
      if (response.statusCode == 200) {
        tempNewsList = NewsList.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
        if (appState.debugMode) {
          logThis('fetchStarredNews', '${tempNewsList.news.length} news fetched', LogLevel.INFO);
        }
        newsList.news.addAll(tempNewsList.news);
        newsList.newsCount = tempNewsList.newsCount;
        listSize = tempNewsList.news.length;
        offset = FluxNewsState.amountOfNewlyCaughtNews * offsetCounter;
        offsetCounter++;
        if (appState.debugMode) {
          if (listSize == FluxNewsState.amountOfNewlyCaughtNews) {
            logThis('fetchStarredNews', '${tempNewsList.newsCount - listSize} news remaining', LogLevel.INFO);
          } else {
            logThis('fetchStarredNews', '0 news remaining', LogLevel.INFO);
          }
        }
        if (offset >= appState.amountOfSyncedNews && appState.amountOfSyncedNews != 0) {
          logThis('fetchStarredNews', 'Reached limit of news to sync', LogLevel.INFO);
          break;
        }
      } else {
        logThis('fetchStarredNews',
            'Got unexpected response from miniflux server: ${response.statusCode} for starred news', LogLevel.ERROR);

        throw FluxNewsState.httpUnexpectedResponseErrorString;
      }
    }
    client.close();
    if (appState.debugMode) {
      logThis('fetchStarredNews', 'Finished fetching starred news from miniflux server', LogLevel.INFO);
    }
    return newsList;
  } else {
    if (appState.debugMode) {
      logThis('fetchStarredNews', 'Finished fetching starred news from miniflux server', LogLevel.INFO);
    }
    return newsList;
  }
}

// search news with the given search string on the miniflux server
// this is the same procedure as fetchNews
// the only difference is that the requested parameter is
// starred=true and not status=unread
// for details of the implementation see the comments above
Future<List<News>> fetchSearchedNews(FluxNewsState appState, String searchString) async {
  if (appState.debugMode) {
    logThis('fetchSearchedNews', 'Starting fetching searched news from miniflux server', LogLevel.INFO);
  }

  // init a empty news list
  List<News> newList = [];
  // init a temporary news list, which will be parsed from every
  // response of the miniflux server and then added to the news list
  // which was initialized above.
  NewsList tempNewsList = NewsList(news: newList, newsCount: 0);
  // set the size of the returned news initially to the maximum of news,
  // which will be provided by a response.
  // this size is set to 100.
  int listSize = FluxNewsState.amountOfNewlyCaughtNews;
  // set the offset (the amount of news, which should be skipped in the next response)
  // to zero for the first request.
  int offset = 0;
  // set the offset counter (multiplier) to 1 for the first request.
  int offsetCounter = 1;
  // init the string for the request
  String requestString = '';
  // decide if the sort order is ascending or descending
  String sortOrder = FluxNewsState.minifluxAscString;
  if (appState.sortOrder != null) {
    if (appState.sortOrder == FluxNewsState.sortOrderNewestFirstString) {
      sortOrder = FluxNewsState.minifluxDescString;
    } else {
      sortOrder = FluxNewsState.minifluxAscString;
    }
  }
  // check if the miniflux url and api key is set.
  if (appState.minifluxURL != null && appState.minifluxAPIKey != null) {
    final Client client;
    if (Platform.isAndroid) {
      final engine = CronetEngine.build(cacheMode: CacheMode.memory, cacheMaxSize: 2 * 1024 * 1024);
      client = CronetClient.fromCronetEngine(engine, closeEngine: true);
    } else {
      client = IOClient(HttpClient());
    }
    // define the header for the request.
    // the header contains the api key and the accepted content type
    final header = {
      FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
      FluxNewsState.httpMinifluxAcceptHeaderString: FluxNewsState.httpContentTypeString,
    };
    // while the list size of the response is equal the defined maximum of news
    // which will be provided by a response, there are more unread news at the
    // miniflux server.
    // so we need to update the offset, to skip the already transferred amount of news
    // and to request the unread news again until the list size is lower as the maximum
    // of news provided by a response.
    // this is a kind of pagination.
    while (listSize == FluxNewsState.amountOfNewlyCaughtNews) {
      if (!appState.longSyncAborted) {
        // request the unread news with the parameter, how many news should be provided by
        // one response (limit) and the amount of news which should be skipped, because
        // they were already transferred (offset).
        requestString =
            '${appState.minifluxURL!}entries?search=$searchString&order=published_at&direction=$sortOrder&limit=${FluxNewsState.amountOfNewlyCaughtNews}&offset=$offset';
        final response = await client.get(Uri.parse(requestString), headers: header);
        // only the response code 200 ist ok
        if (response.statusCode == 200) {
          tempNewsList = NewsList.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
          if (appState.debugMode) {
            logThis('fetchSearchedNews', '${tempNewsList.news.length} news fetched', LogLevel.INFO);
          }
          // add the news of the response to the news list
          newList.addAll(tempNewsList.news);
          // check if the execution time will took very long
          if (tempNewsList.newsCount > FluxNewsState.amountForLongNewsSync) {
            if (tempNewsList.newsCount > FluxNewsState.amountForTooManyNews) {
              appState.tooManyNews = true;
              appState.longSyncAborted = true;
              appState.refreshView();
            }
          }
          // update the list size to the count of the provided news
          listSize = tempNewsList.news.length;
          // update the offset to the maximum of provided news for each request,
          // multiplied by a incrementing counter
          offset = FluxNewsState.amountOfNewlyCaughtNews * offsetCounter;
          // increment the offset counter for the next run
          offsetCounter++;
          if (appState.debugMode) {
            if (listSize == FluxNewsState.amountOfNewlyCaughtNews) {
              logThis('fetchSearchedNews', '${tempNewsList.newsCount - offset} news remaining', LogLevel.INFO);
            } else {
              logThis('fetchSearchedNews', '0 news remaining', LogLevel.INFO);
            }
          }
          if (offset >= appState.amountOfSearchedNews && appState.amountOfSearchedNews != 0) {
            logThis('fetchSearchedNews', 'Reached limit of news to search', LogLevel.INFO);
            break;
          }
        } else {
          logThis(
              'fetchSearchedNews',
              'Got unexpected response from miniflux server: ${response.statusCode} for search string $searchString',
              LogLevel.ERROR);
          // if the status is not 200, throw a exception
          throw FluxNewsState.httpUnexpectedResponseErrorString;
        }
      } else {
        listSize = 0;
        if (appState.debugMode) {
          logThis('fetchSearchedNews', 'Aborted fetching searched news from miniflux server', LogLevel.INFO);
        }
      }
    }
    // read the feed icon
    // check if the database is initialized
    // if not, initialize the database
    appState.db ??= await appState.initializeDB();
    if (appState.db != null) {
      List<Feed> feedList = [];
      List<Map<String, Object?>> queryResult = await appState.db!
          .rawQuery('SELECT feedID, title, site_url, iconMimeType, iconID, newsCount, categoryID FROM feeds');
      for (Feed feed in queryResult.map((e) => Feed.fromMap(e)).toList()) {
        if (feed.feedIconID != null && feed.feedIconID != 0) {
          feed.icon = appState.readFeedIconFile(feed.feedIconID!);
        }

        feedList.add(feed);
      }
      // for each news in the list, get the feed icon from the database
      for (News news in newList) {
        // get the feed icon and the feed icon mime type
        news.getFeedInfo(feedList);

        if (appState.debugMode) {
          logThis('fetchSearchedNews', 'Got the feed icon from the database for feed ${news.feedID}', LogLevel.INFO);
        }
      }
    }
    client.close();
    if (appState.debugMode) {
      logThis('fetchSearchedNews', 'Finished fetching searched news from miniflux server', LogLevel.INFO);
    }
    // return the news list
    return newList;
  } else {
    if (appState.debugMode) {
      logThis('fetchSearchedNews', 'Finished fetching searched news from miniflux server', LogLevel.INFO);
    }
    // if the miniflux url or api key is not set, return the empty news list
    return newList;
  }
}

// mark the news as read at the miniflux server
Future<void> toggleNewsAsRead(FluxNewsState appState) async {
  if (appState.debugMode) {
    logThis('toggleNewsAsRead', 'Starting toggle news as read at miniflux server', LogLevel.INFO);
  }

  // check if the miniflux url and api key is set
  if (appState.minifluxURL != null && appState.minifluxAPIKey != null) {
    List<int> newsIds = [];
    appState.db ??= await appState.initializeDB();
    if (appState.db != null) {
      // query the database for all news with the status read and the sync status not synced
      final List<Map<String, Object?>> queryResult = await appState.db!.rawQuery('''
             SELECT news.newsID, 
                    news.feedID, 
                    substr(news.title, 1, 1000000) as title, 
                    substr(news.url, 1, 1000000) as url, 
                    substr(news.commentsUrl, 1, 1000000) as commentsUrl,
                    substr(news.shareCode, 1, 1000000) as shareCode,
                    substr(news.content, 1, 1000000) as content, 
                    news.hash, 
                    news.publishedAt, 
                    news.createdAt, 
                    news.status, 
                    news.readingTime, 
                    news.starred, 
                    substr(news.feedTitle, 1, 1000000) as feedTitle,
                    news.syncStatus
             FROM news 
             WHERE status LIKE ? 
              AND syncStatus = ?''', [FluxNewsState.readNewsStatus, FluxNewsState.notSyncedSyncStatus]);
      List<News> newsList = queryResult.map((e) => News.fromMap(e)).toList();
      // iterate over the news list and add the news id to the news id list
      for (News news in newsList) {
        newsIds.add(news.newsID);
      }
      // if the news id list is not empty, create a new ReadNewsList object
      if (newsIds.isNotEmpty) {
        // add the news id list and the status to the ReadNewsList object
        ReadNewsList newReadNewsList = ReadNewsList(newsIds: newsIds, status: FluxNewsState.readNewsStatus);
        final Client client;
        if (Platform.isAndroid) {
          final engine = CronetEngine.build(cacheMode: CacheMode.memory, cacheMaxSize: 2 * 1024 * 1024);
          client = CronetClient.fromCronetEngine(engine, closeEngine: true);
        } else {
          client = IOClient(HttpClient());
        }
        final header = {
          FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
          FluxNewsState.httpMinifluxContentTypeHeaderString: FluxNewsState.httpContentTypeString,
        };
        // send the ReadNewsList object to the miniflux server to mark the news as read
        final response = await client.put(Uri.parse('${appState.minifluxURL!}entries'),
            headers: header, body: jsonEncode(newReadNewsList));
        if (response.statusCode != 204) {
          logThis(
              'toggleNewsAsRead',
              'Got unexpected response from miniflux server: ${response.statusCode} for news ${newsIds.toString()}',
              LogLevel.ERROR);

          // if the response code is not 204, throw a error
          throw FluxNewsState.httpUnexpectedResponseErrorString;
        } else {
          // if the response code is 204, update the sync status of the news in the database to synced
          for (News news in newsList) {
            await appState.db!.rawUpdate(
                'UPDATE news SET syncStatus = ? WHERE newsId = ?', [FluxNewsState.syncedSyncStatus, news.newsID]);
            if (appState.debugMode) {
              logThis('toggleNewsAsRead', 'Updated sync status of news ${news.newsID} in database', LogLevel.INFO);
            }
          }
        }
        client.close();
      }
    }
  }
  if (appState.debugMode) {
    logThis('toggleNewsAsRead', 'Finished toggle news as read at miniflux server', LogLevel.INFO);
  }
}

// mark one news directly as read at the miniflux server
Future<void> toggleOneNewsAsRead(FluxNewsState appState, News news) async {
  if (appState.debugMode) {
    logThis('toggleOneNewsAsRead', 'Starting toggle one news as read at miniflux server', LogLevel.INFO);
  }

  // check if the miniflux url and api key is set
  if (appState.minifluxURL != null && appState.minifluxAPIKey != null) {
    final Client client;
    if (Platform.isAndroid) {
      final engine = CronetEngine.build(cacheMode: CacheMode.memory, cacheMaxSize: 2 * 1024 * 1024);
      client = CronetClient.fromCronetEngine(engine, closeEngine: true);
    } else {
      client = IOClient(HttpClient());
    }
    List<int> newsIds = [];

    newsIds.add(news.newsID);
    ReadNewsList newReadNewsList = ReadNewsList(newsIds: newsIds, status: news.status);
    final header = {
      FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
      FluxNewsState.httpMinifluxContentTypeHeaderString: FluxNewsState.httpContentTypeString,
    };
    // send the ReadNewsList object to the miniflux server to mark the news as read
    final response = await client.put(Uri.parse('${appState.minifluxURL!}entries'),
        headers: header, body: jsonEncode(newReadNewsList));
    if (response.statusCode != 204) {
      logThis(
          'toggleOneNewsAsRead',
          'Got unexpected response from miniflux server: ${response.statusCode} for news ${news.newsID}',
          LogLevel.ERROR);

      // if the response code is not 204, throw a error
      throw FluxNewsState.httpUnexpectedResponseErrorString;
    }
    client.close();
  }
  if (appState.debugMode) {
    logThis('toggleOneNewsAsRead', 'Finished toggle one news as read at miniflux server', LogLevel.INFO);
  }
}

// mark a news as bookmarked at the miniflux server
Future<void> toggleBookmark(FluxNewsState appState, News news) async {
  if (appState.debugMode) {
    logThis('toggleBookmark', 'Starting toggle bookmark at miniflux server', LogLevel.INFO);
  }

  // first check if the miniflux url and api key is set
  if (appState.minifluxURL != null && appState.minifluxAPIKey != null) {
    appState.db ??= await appState.initializeDB();
    if (appState.db != null) {
      final Client client;
      if (Platform.isAndroid) {
        final engine = CronetEngine.build(cacheMode: CacheMode.memory, cacheMaxSize: 2 * 1024 * 1024);
        client = CronetClient.fromCronetEngine(engine, closeEngine: true);
      } else {
        client = IOClient(HttpClient());
      }
      final header = {
        FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
      };
      // toggle the bookmark status of the news at the miniflux server
      final response = await client.put(
        Uri.parse('${appState.minifluxURL!}entries/${news.newsID}/bookmark'),
        headers: header,
      );
      if (response.statusCode != 204) {
        logThis(
            'toggleBookmark',
            'Got unexpected response from miniflux server: ${response.statusCode} for news ${news.newsID}',
            LogLevel.ERROR);

        // if the response code is not 204, throw an error
        throw FluxNewsState.httpUnexpectedResponseErrorString;
      } else {
        // if the response code is 204, update the bookmark status of the news in the database
        await appState.db!
            .rawUpdate('UPDATE news SET starred = ? WHERE newsId = ?', [news.starred ? 1 : 0, news.newsID]);
        if (appState.debugMode) {
          logThis('toggleBookmark', 'Updated bookmark status of news ${news.newsID} in database', LogLevel.INFO);
        }
      }
      client.close();
    }
  }
  if (appState.debugMode) {
    logThis('toggleBookmark', 'Finished toggle bookmark at miniflux server', LogLevel.INFO);
  }
}

// mark a news as bookmarked at the miniflux server
Future<void> saveNewsToThirdPartyService(FluxNewsState appState, News news) async {
  if (appState.debugMode) {
    logThis(
        'saveNewsToThirdPartyService', 'Starting saving news to third party service at miniflux server', LogLevel.INFO);
  }

  // first check if the miniflux url and api key is set
  if (appState.minifluxURL != null && appState.minifluxAPIKey != null) {
    appState.db ??= await appState.initializeDB();
    if (appState.db != null) {
      final Client client;
      if (Platform.isAndroid) {
        final engine = CronetEngine.build(cacheMode: CacheMode.memory, cacheMaxSize: 2 * 1024 * 1024);
        client = CronetClient.fromCronetEngine(engine, closeEngine: true);
      } else {
        client = IOClient(HttpClient());
      }
      final header = {
        FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
      };
      // saving news to third party service on miniflux server
      final response = await client.post(
        Uri.parse('${appState.minifluxURL!}entries/${news.newsID}/save'),
        headers: header,
      );
      if (response.statusCode != 202) {
        if (response.statusCode == 400) {
          final errorMessage = jsonDecode(response.body) as Map<String, dynamic>;
          if (errorMessage['error_message'] == 'no third-party integration enabled') {
            if (appState.debugMode) {
              logThis('saveNewsToThirdPartyService', 'no third-party integration enabled', LogLevel.INFO);
            }
          } else {
            logThis(
                'saveNewsToThirdPartyService',
                'Got unexpected response from miniflux server: ${response.body} for news ${news.newsID}',
                LogLevel.ERROR);
            // if the response body is not 'no third-party integration enabled', throw an error
            throw FluxNewsState.httpUnexpectedResponseErrorString;
          }
        } else {
          logThis(
              'saveNewsToThirdPartyService',
              'Got unexpected response from miniflux server: ${response.statusCode} for news ${news.newsID}',
              LogLevel.ERROR);
          // if the response code is not 202, throw an error
          throw FluxNewsState.httpUnexpectedResponseErrorString;
        }
      }
      client.close();
    }
  }
  if (appState.debugMode) {
    logThis(
        'saveNewsToThirdPartyService', 'Finished saving news to third party service at miniflux server', LogLevel.INFO);
  }
}

// fetch the information about the categories from the miniflux server
Future<Categories> fetchCategoryInformation(FluxNewsState appState) async {
  if (appState.debugMode) {
    logThis('fetchCategoryInformation', 'Starting fetching category information from miniflux server', LogLevel.INFO);
  }

  List<Category> newCategoryList = [];
  Response response;
  // first check if the miniflux url and api key is set
  if (appState.minifluxURL != null && appState.minifluxAPIKey != null) {
    appState.db ??= await appState.initializeDB();
    if (appState.db != null) {
      final Client client;
      if (Platform.isAndroid) {
        final engine = CronetEngine.build(cacheMode: CacheMode.memory, cacheMaxSize: 2 * 1024 * 1024);
        client = CronetClient.fromCronetEngine(engine, closeEngine: true);
      } else {
        client = IOClient(HttpClient());
      }
      final header = {
        FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
        FluxNewsState.httpMinifluxAcceptHeaderString: FluxNewsState.httpContentTypeString,
      };
      // then request the categories from the miniflux server
      response = await client.get(
        Uri.parse('${appState.minifluxURL!}categories'),
        headers: header,
      );
      if (response.statusCode != 200) {
        logThis(
            'fetchCategoryInformation',
            'Got unexpected response from miniflux server: ${response.statusCode} while fetching categories',
            LogLevel.ERROR);

        // if the response code is not 200, throw an error
        throw FluxNewsState.httpUnexpectedResponseErrorString;
      } else {
        // if the response code is 200, decode the response body and create a new Categories list
        Iterable l = json.decode(utf8.decode(response.bodyBytes));
        newCategoryList = List<Category>.from(l.map((model) => Category.fromJson(model)));

        // iterate over the categories list and request the feeds for each category
        for (Category category in newCategoryList) {
          List<Feed> feedList = [];
          response = await client.get(
            Uri.parse('${appState.minifluxURL!}categories/${category.categoryID}/feeds'),
            headers: header,
          );
          if (response.statusCode != 200) {
            logThis(
                'fetchCategoryInformation',
                'Got unexpected response from miniflux server: ${response.statusCode} while fetching feeds for category ${category.categoryID}',
                LogLevel.ERROR);

            // if the response code is not 200, throw an error
            throw FluxNewsState.httpUnexpectedResponseErrorString;
          } else {
            // if the response code is 200, decode the response body and create a new Feeds list
            Iterable l = json.decode(utf8.decode(response.bodyBytes));
            feedList = List<Feed>.from(l.map((model) => Feed.fromJson(model)));

            // iterate over the feeds list and query the database for the news count of the feed
            for (Feed feed in feedList) {
              int? count;
              List<Map<String, Object?>> result =
                  await appState.db!.rawQuery('SELECT COUNT(*) FROM news WHERE feedID = ?', [feed.feedID]);
              if (result.isNotEmpty) {
                if (result.first.entries.isNotEmpty) {
                  count = result.first.entries.first.value as int?;
                }
              }

              count ??= 0;

              // add the news count to the feed object
              feed.newsCount = count;

              // if the feed icon id is not null and not 0, request the feed icon from the miniflux server
              if (feed.feedIconID != null && feed.feedIconID != 0) {
                if (appState.checkIfFeedIconFileExists(feed.feedIconID!)) {
                  result = await appState.db!.rawQuery('''SELECT DISTINCT(iconMimeType)
                                                      FROM feeds 
                                                      WHERE iconID = ?''', [feed.feedIconID!]);
                  if (result.isNotEmpty) {
                    if (result.first.entries.isNotEmpty) {
                      feed.iconMimeType = result.first.entries.first.value as String;
                      // read the feed icon from the file system
                      feed.icon = appState.readFeedIconFile(feed.feedIconID!);
                    }
                  }
                } else {
                  response = await client.get(
                    Uri.parse('${appState.minifluxURL!}icons/${feed.feedIconID}'),
                    headers: header,
                  );
                  if (response.statusCode != 200) {
                    if (response.statusCode == 404) {
                      if (appState.debugMode) {
                        logThis(
                            'fetchCategoryInformation', 'No feed icon for feed with id ${feed.feedID}', LogLevel.INFO);
                      }
                      // This feed has no feed icon, do nothing.
                    } else {
                      logThis(
                          'fetchCategoryInformation',
                          'Got unexpected response from miniflux server: ${response.statusCode} while fetching feeds icons for feed ${feed.feedID}',
                          LogLevel.ERROR);
                      // if the response code is not 200, throw an error
                      throw FluxNewsState.httpUnexpectedResponseErrorString;
                    }
                  } else {
                    FeedIcon feedIcon = FeedIcon.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
                    feed.icon = feedIcon.getIcon();
                    feed.iconMimeType = feedIcon.iconMimeType;
                  }
                }
              } else {
                if (appState.debugMode) {
                  logThis('fetchCategoryInformation', 'No feed icon for feed with id ${feed.feedID}', LogLevel.INFO);
                }
              }
            }
          }
          // add the feed list to the category object
          category.feeds = feedList;
        }
      }
      client.close();
    }
  }
  if (appState.debugMode) {
    logThis('fetchCategoryInformation', 'Finished fetching category information from miniflux server', LogLevel.INFO);
  }
  // return the new categories list
  Categories newCategories = Categories(categories: newCategoryList);
  return newCategories;
}

// fetch the feed icon from the miniflux server
Future<FeedIcon?> getFeedIcon(FluxNewsState appState, int feedIconID) async {
  if (appState.debugMode) {
    logThis('getFeedIcon', 'Starting getting feed icon from miniflux server', LogLevel.INFO);
  }

  Response response;
  FeedIcon? feedIcon;
  // first check if the miniflux url and api key is set
  if (appState.minifluxURL != null && appState.minifluxAPIKey != null) {
    appState.db ??= await appState.initializeDB();
    if (appState.db != null) {
      final Client client;
      if (Platform.isAndroid) {
        final engine = CronetEngine.build(cacheMode: CacheMode.memory, cacheMaxSize: 2 * 1024 * 1024);
        client = CronetClient.fromCronetEngine(engine, closeEngine: true);
      } else {
        client = IOClient(HttpClient());
      }
      // then request the feed icon from the miniflux server
      final header = {
        FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
        FluxNewsState.httpMinifluxAcceptHeaderString: FluxNewsState.httpContentTypeString,
      };
      response = await client.get(
        Uri.parse('${appState.minifluxURL!}icons/$feedIconID'),
        headers: header,
      );
      if (response.statusCode != 200) {
        if (response.statusCode == 404) {
          if (appState.debugMode) {
            logThis('getFeedIcon', 'No feed icon for icon with id $feedIconID', LogLevel.INFO);
          }
          // This feed has no feed icon, do nothing
        } else {
          logThis(
              'getFeedIcon',
              'Got unexpected response from miniflux server: ${response.statusCode} for feed icon $feedIconID',
              LogLevel.ERROR);

          // if the response code is not 200, throw an error
          throw FluxNewsState.httpUnexpectedResponseErrorString;
        }
      } else {
        // if the response code is 200, decode the response body and create a new FeedIcon object
        feedIcon = FeedIcon.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
      }
      client.close();
    }
  }
  if (appState.debugMode) {
    logThis('getFeedIcon', 'Finished getting feed icon from miniflux server', LogLevel.INFO);
  }
  // return the feed icon
  return feedIcon;
}

// check if the miniflux credentials are valid
Future<bool> checkMinifluxCredentials(String? miniFluxUrl, String? miniFluxApiKey, FluxNewsState appState) async {
  if (appState.debugMode) {
    logThis('checkMinifluxCredentials', 'Starting checking miniflux credentials', LogLevel.INFO);
  }

  // first check if the miniflux url and api key is set
  if (miniFluxApiKey != null && miniFluxUrl != null) {
    final Client client;
    if (Platform.isAndroid) {
      final engine = CronetEngine.build(cacheMode: CacheMode.memory, cacheMaxSize: 2 * 1024 * 1024);
      client = CronetClient.fromCronetEngine(engine, closeEngine: true);
    } else {
      client = IOClient(HttpClient());
    }
    final header = {
      FluxNewsState.httpMinifluxAuthHeaderString: miniFluxApiKey,
      FluxNewsState.httpMinifluxAcceptHeaderString: FluxNewsState.httpContentTypeString,
    };
    // then request the user information from the miniflux server
    Response response = await client.get(Uri.parse('${miniFluxUrl}me'), headers: header);
    if (response.statusCode == 200) {
      // request the Version of the miniflux server
      response = await client.get(Uri.parse('${miniFluxUrl}version'), headers: header);
      if (response.statusCode == 200) {
        Version minifluxVersion = Version.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
        appState.minifluxVersionInt = int.parse(minifluxVersion.version.replaceAll(RegExp(r'\D'), ''));
        appState.minifluxVersionString = minifluxVersion.version;
        appState.storage.write(key: FluxNewsState.secureStorageMinifluxVersionKey, value: minifluxVersion.version);
        appState.refreshView();
        if (appState.debugMode) {
          logThis('checkMinifluxCredentials', 'Miniflux v1 API Version: ${minifluxVersion.version}', LogLevel.INFO);
        }
      } else {
        // need to remove the "v1/" part from the url to request the version api endpoint
        String minifluxBaseURL = "";
        if (miniFluxUrl.length >= 3) {
          minifluxBaseURL = miniFluxUrl.substring(0, miniFluxUrl.length - 3);
        }

        response = await client.get(Uri.parse('${minifluxBaseURL}version'), headers: header);
        if (response.statusCode == 200) {
          appState.minifluxVersionInt = int.parse(response.body.replaceAll(RegExp(r'\D'), ''));
          appState.minifluxVersionString = response.body;
          appState.storage.write(key: FluxNewsState.secureStorageMinifluxVersionKey, value: response.body);
          appState.refreshView();
          if (appState.debugMode) {
            logThis('checkMinifluxCredentials', 'Miniflux Version: ${response.body}', LogLevel.INFO);
          }
        } else {
          logThis('checkMinifluxCredentials',
              'Got unexpected response from miniflux server: ${response.statusCode} for version', LogLevel.ERROR);
        }
      }
      if (appState.debugMode) {
        logThis('checkMinifluxCredentials', 'Finished checking miniflux credentials', LogLevel.INFO);
      }
      client.close();
      // if the response code is 200, the credentials are valid
      return true;
    } else {
      if (appState.debugMode) {
        logThis('checkMinifluxCredentials', 'Finished checking miniflux credentials', LogLevel.INFO);
      }
      logThis(
          'checkMinifluxCredentials',
          'Got unexpected response from miniflux server: ${response.statusCode} for checking credentials',
          LogLevel.ERROR);
      client.close();
      // if the response code is not 200, the credentials are invalid
      return false;
    }
  } else {
    if (appState.debugMode) {
      logThis('checkMinifluxCredentials', 'Finished checking miniflux credentials', LogLevel.INFO);
    }
    // if the miniflux url or api key is not set, the credentials are invalid
    return false;
  }
}
