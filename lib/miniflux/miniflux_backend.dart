import 'dart:convert';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flux_news/functions/logging.dart';
import 'package:flux_news/miniflux/miniflux_http_client.dart';
import 'package:http/http.dart';

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

class PagedNewsFetchResult {
  const PagedNewsFetchResult({
    required this.fetchedCount,
    required this.reportedCount,
    required this.complete,
  });

  final int fetchedCount;
  final int reportedCount;
  final bool complete;
}

typedef NewsPageConsumer = Future<int> Function(
    List<Map<String, dynamic>> entries);

/// Fetches entry pages without retaining parsed [News] objects between pages.
/// The consumer returns the number of newly staged IDs so duplicate pages
/// cannot accidentally satisfy the completeness check.
Future<PagedNewsFetchResult> fetchNewsPages(
  FluxNewsState appState, {
  required bool starred,
  required NewsPageConsumer consumePage,
  Client? httpClient,
}) async {
  if (appState.minifluxURL == null || appState.minifluxAPIKey == null) {
    return const PagedNewsFetchResult(
      fetchedCount: 0,
      reportedCount: 0,
      complete: true,
    );
  }

  final client = httpClient ?? createMinifluxHttpClient();
  final header = {
    FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
    FluxNewsState.httpMinifluxAcceptHeaderString:
        FluxNewsState.httpContentTypeString,
    ...appState.customHeaders,
  };
  final sortOrder =
      appState.sortOrder == FluxNewsState.sortOrderNewestFirstString
          ? FluxNewsState.minifluxDescString
          : FluxNewsState.minifluxAscString;
  final configuredCap = appState.amountOfSyncedNews;
  var offset = 0;
  var uniqueCount = 0;
  int? reportedCount;

  String statusQuery() {
    if (starred) return '&starred=true';
    if (!appState.syncReadNews) return '&status=unread';
    if (appState.syncReadNewsAfterDays <= 0) return '';
    final syncDate =
        DateTime.now().subtract(Duration(days: appState.syncReadNewsAfterDays));
    final timestamp = syncDate.toUtc().millisecondsSinceEpoch ~/ 1000;
    return '&after=$timestamp';
  }

  try {
    while (true) {
      if (appState.longSyncAborted) {
        throw const RemoteFetchAbortedException();
      }
      if (configuredCap > 0 && offset >= configuredCap) break;
      final limit = configuredCap > 0
          ? math.min(
              FluxNewsState.amountOfNewlyCaughtNews, configuredCap - offset)
          : FluxNewsState.amountOfNewlyCaughtNews;
      final uri = Uri.parse(
        '${appState.minifluxURL!}entries?order=published_at${statusQuery()}'
        '&direction=$sortOrder&limit=$limit&offset=$offset',
      );
      final response = await client.get(uri, headers: header);
      if (response.statusCode != 200) {
        logThis(
          'fetchNewsPages',
          'Got unexpected response ${response.statusCode} for '
              '${starred ? 'starred' : 'main'} news',
          LogLevel.ERROR,
        );
        throw FluxNewsState.httpUnexpectedResponseErrorString;
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic> ||
          decoded['total'] is! int ||
          decoded['entries'] is! List) {
        throw const FormatException('Invalid Miniflux entries response');
      }
      final pageReportedCount = decoded['total'] as int;
      reportedCount ??= pageReportedCount;
      if (reportedCount != pageReportedCount) {
        throw const FormatException(
            'Miniflux entry count changed during pagination');
      }
      final entries = (decoded['entries'] as List)
          .map((entry) => Map<String, dynamic>.from(entry as Map))
          .toList(growable: false);
      if (entries.isEmpty) {
        if (offset < reportedCount) {
          throw const FormatException(
              'Miniflux pagination ended before the reported total');
        }
        break;
      }

      uniqueCount += await consumePage(entries);
      offset += entries.length;
      if (offset >= reportedCount) break;
      if (entries.length < limit) {
        throw const FormatException(
            'Miniflux returned a short page before the reported total');
      }
    }

    final total = reportedCount ?? 0;
    final capped = configuredCap > 0 && configuredCap < total;
    if (!capped && uniqueCount != total) {
      throw FormatException(
          'Miniflux pagination staged $uniqueCount of $total unique entries');
    }
    return PagedNewsFetchResult(
      fetchedCount: uniqueCount,
      reportedCount: total,
      complete: !capped && uniqueCount == total,
    );
  } finally {
    if (httpClient == null) client.close();
  }
}

class RemoteFetchAbortedException implements Exception {
  const RemoteFetchAbortedException();
}

// fetch unread news from the miniflux backend
Future<NewsList> fetchNews(FluxNewsState appState, {Client? httpClient}) async {
  if (appState.debugMode) {
    logThis('fetchNews', 'Starting fetching news from miniflux server',
        LogLevel.INFO);
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
    final client = httpClient ?? createMinifluxHttpClient();
    try {
      // define the header for the request.
      // the header contains the api key and the accepted content type
      final header = {
        FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
        FluxNewsState.httpMinifluxAcceptHeaderString:
            FluxNewsState.httpContentTypeString,
      };
      if (appState.customHeaders.isNotEmpty) {
        header.addAll(appState.customHeaders);
      }
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
          DateTime syncDate = DateTime.now()
              .subtract(Duration(days: appState.syncReadNewsAfterDays));
          int syncDateTimestamp =
              (syncDate.toUtc().millisecondsSinceEpoch / 1000).round();
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
          final response =
              await client.get(Uri.parse(requestString), headers: header);
          // only the response code 200 ist ok
          if (response.statusCode == 200) {
            // parse the body to the temp news list
            tempNewsList =
                NewsList.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
            if (appState.debugMode) {
              logThis('fetchNews', '${tempNewsList.news.length} news fetched',
                  LogLevel.INFO);
            }
            // add the temp news list to the returning news list
            newsList.news.addAll(tempNewsList.news);
            // check if the execution time will took very long
            if (tempNewsList.newsCount > FluxNewsState.amountForLongNewsSync) {
              if (tempNewsList.newsCount > FluxNewsState.amountForTooManyNews &&
                  appState.amountOfSyncedNews == 0) {
                // remove the native splash after updating the list view
                FlutterNativeSplash.remove();
                appState.tooManyNews = true;
                appState.longSyncAborted = true;
                appState.refreshView();
              } else {
                if (appState.amountOfSyncedNews >
                        FluxNewsState.amountForLongNewsSync ||
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
                logThis(
                    'fetchNews',
                    '${tempNewsList.newsCount - offset} news remaining',
                    LogLevel.INFO);
              } else {
                logThis('fetchNews', '0 news remaining', LogLevel.INFO);
              }
            }
            if (offset >= appState.amountOfSyncedNews &&
                appState.amountOfSyncedNews != 0) {
              logThis(
                  'fetchNews', 'Reached limit of news to sync', LogLevel.INFO);
              break;
            }
          } else {
            logThis(
                'fetchNews',
                'Got unexpected response from miniflux server: ${response.statusCode} for unread news',
                LogLevel.ERROR);

            // if the status is not 200, throw a exception
            throw FluxNewsState.httpUnexpectedResponseErrorString;
          }
        } else {
          listSize = 0;
          if (appState.debugMode) {
            logThis('fetchNews', 'Aborted fetching news from miniflux server',
                LogLevel.INFO);
          }
        }
      }
      if (appState.debugMode) {
        logThis('fetchNews', 'Finished fetching news from miniflux server',
            LogLevel.INFO);
      }
      // return the news list
      return newsList;
    } finally {
      if (httpClient == null) client.close();
    }
  } else {
    if (appState.debugMode) {
      logThis('fetchNews', 'Finished fetching no new news from miniflux server',
          LogLevel.INFO);
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
Future<NewsList> fetchStarredNews(FluxNewsState appState,
    {Client? httpClient}) async {
  if (appState.debugMode) {
    logThis('fetchStarredNews',
        'Starting fetching starred news from miniflux server', LogLevel.INFO);
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
    final client = httpClient ?? createMinifluxHttpClient();
    try {
      final header = {
        FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
        FluxNewsState.httpMinifluxAcceptHeaderString:
            FluxNewsState.httpContentTypeString,
      };
      if (appState.customHeaders.isNotEmpty) {
        header.addAll(appState.customHeaders);
      }
      while (listSize == FluxNewsState.amountOfNewlyCaughtNews) {
        requestString =
            '${appState.minifluxURL!}entries?starred=true&order=published_at&direction=$sortOrder&limit=${FluxNewsState.amountOfNewlyCaughtNews}&offset=$offset';
        final response =
            await client.get(Uri.parse(requestString), headers: header);
        if (response.statusCode == 200) {
          tempNewsList =
              NewsList.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
          if (appState.debugMode) {
            logThis('fetchStarredNews',
                '${tempNewsList.news.length} news fetched', LogLevel.INFO);
          }
          newsList.news.addAll(tempNewsList.news);
          newsList.newsCount = tempNewsList.newsCount;
          listSize = tempNewsList.news.length;
          offset = FluxNewsState.amountOfNewlyCaughtNews * offsetCounter;
          offsetCounter++;
          if (appState.debugMode) {
            if (listSize == FluxNewsState.amountOfNewlyCaughtNews) {
              logThis(
                  'fetchStarredNews',
                  '${tempNewsList.newsCount - listSize} news remaining',
                  LogLevel.INFO);
            } else {
              logThis('fetchStarredNews', '0 news remaining', LogLevel.INFO);
            }
          }
          if (offset >= appState.amountOfSyncedNews &&
              appState.amountOfSyncedNews != 0) {
            logThis('fetchStarredNews', 'Reached limit of news to sync',
                LogLevel.INFO);
            break;
          }
        } else {
          logThis(
              'fetchStarredNews',
              'Got unexpected response from miniflux server: ${response.statusCode} for starred news',
              LogLevel.ERROR);

          throw FluxNewsState.httpUnexpectedResponseErrorString;
        }
      }
      if (appState.debugMode) {
        logThis(
            'fetchStarredNews',
            'Finished fetching starred news from miniflux server',
            LogLevel.INFO);
      }
      return newsList;
    } finally {
      if (httpClient == null) client.close();
    }
  } else {
    if (appState.debugMode) {
      logThis('fetchStarredNews',
          'Finished fetching starred news from miniflux server', LogLevel.INFO);
    }
    return newsList;
  }
}

// search news with the given search string on the miniflux server
// this is the same procedure as fetchNews
// the only difference is that the requested parameter is
// starred=true and not status=unread
// for details of the implementation see the comments above
Future<List<News>> fetchSearchedNews(
    FluxNewsState appState, String searchString) async {
  if (appState.debugMode) {
    logThis('fetchSearchedNews',
        'Starting fetching searched news from miniflux server', LogLevel.INFO);
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
    final client = createMinifluxHttpClient();
    try {
      // define the header for the request.
      // the header contains the api key and the accepted content type
      final header = {
        FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
        FluxNewsState.httpMinifluxAcceptHeaderString:
            FluxNewsState.httpContentTypeString,
      };
      if (appState.customHeaders.isNotEmpty) {
        header.addAll(appState.customHeaders);
      }
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
          final response =
              await client.get(Uri.parse(requestString), headers: header);
          // only the response code 200 ist ok
          if (response.statusCode == 200) {
            tempNewsList =
                NewsList.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
            if (appState.debugMode) {
              logThis('fetchSearchedNews',
                  '${tempNewsList.news.length} news fetched', LogLevel.INFO);
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
                logThis(
                    'fetchSearchedNews',
                    '${tempNewsList.newsCount - offset} news remaining',
                    LogLevel.INFO);
              } else {
                logThis('fetchSearchedNews', '0 news remaining', LogLevel.INFO);
              }
            }
            if (offset >= appState.amountOfSearchedNews &&
                appState.amountOfSearchedNews != 0) {
              logThis('fetchSearchedNews', 'Reached limit of news to search',
                  LogLevel.INFO);
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
            logThis(
                'fetchSearchedNews',
                'Aborted fetching searched news from miniflux server',
                LogLevel.INFO);
          }
        }
      }
      // read the feed icon
      // check if the database is initialized
      // if not, initialize the database
      appState.db ??= await appState.initializeDB();
      if (appState.db != null) {
        List<Feed> feedList = [];
        List<Map<String, Object?>> queryResult =
            await appState.db!.rawQuery('''SELECT feedID,
                    title,
                    site_url,
                    iconMimeType,
                    iconID,
                    newsCount,
                    crawler,
                    manualTruncate,
                    preferParagraph,
                    preferAttachmentImage,
                    manualAdaptLightModeToIcon,
                    manualAdaptDarkModeToIcon,
                    openMinifluxEntry,
                    expandedWithFulltext,
                    expandedFulltextLimit,
                    categoryID
               FROM feeds''');
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
          news.prepareListMetadata();

          if (appState.debugMode) {
            logThis(
                'fetchSearchedNews',
                'Got the feed icon from the database for feed ${news.feedID}',
                LogLevel.INFO);
          }
        }
      }
      if (appState.debugMode) {
        logThis(
            'fetchSearchedNews',
            'Finished fetching searched news from miniflux server',
            LogLevel.INFO);
      }
      // return the news list
      return newList;
    } finally {
      client.close();
    }
  } else {
    if (appState.debugMode) {
      logThis(
          'fetchSearchedNews',
          'Finished fetching searched news from miniflux server',
          LogLevel.INFO);
    }
    // if the miniflux url or api key is not set, return the empty news list
    return newList;
  }
}

// mark the news as read at the miniflux server
Future<void> toggleNewsAsRead(FluxNewsState appState,
    {Client? httpClient}) async {
  if (appState.debugMode) {
    logThis('toggleNewsAsRead',
        'Starting toggle news as read at miniflux server', LogLevel.INFO);
  }

  // check if the miniflux url and api key is set
  if (appState.minifluxURL != null && appState.minifluxAPIKey != null) {
    List<int> newsIds = [];
    appState.db ??= await appState.initializeDB();
    if (appState.db != null) {
      // query the database for all news with the status read and the sync status not synced
      final List<Map<String, Object?>> queryResult = await appState.db!
          .rawQuery('''SELECT newsID
             FROM news
             WHERE status = ? AND syncStatus = ?
             ORDER BY newsID''', [
        FluxNewsState.readNewsStatus,
        FluxNewsState.notSyncedSyncStatus
      ]);
      newsIds.addAll(queryResult.map((row) => row['newsID'] as int));
      // if the news id list is not empty, create a new ReadNewsList object
      if (newsIds.isNotEmpty) {
        final client = httpClient ?? createMinifluxHttpClient();
        try {
          final header = {
            FluxNewsState.httpMinifluxAuthHeaderString:
                appState.minifluxAPIKey!,
            FluxNewsState.httpMinifluxContentTypeHeaderString:
                FluxNewsState.httpContentTypeString,
          };
          if (appState.customHeaders.isNotEmpty) {
            header.addAll(appState.customHeaders);
          }
          const chunkSize = 500;
          for (var start = 0; start < newsIds.length; start += chunkSize) {
            final end = math.min(start + chunkSize, newsIds.length);
            final chunk = newsIds.sublist(start, end);
            final body = ReadNewsList(
              newsIds: chunk,
              status: FluxNewsState.readNewsStatus,
            );
            final response = await client.put(
              Uri.parse('${appState.minifluxURL!}entries'),
              headers: header,
              body: jsonEncode(body),
            );
            if (response.statusCode != 204) {
              logThis(
                  'toggleNewsAsRead',
                  'Got unexpected response from miniflux server: ${response.statusCode} for ${chunk.length} news',
                  LogLevel.ERROR);
              throw FluxNewsState.httpUnexpectedResponseErrorString;
            }
            final placeholders = List.filled(chunk.length, '?').join(',');
            await appState.db!.rawUpdate(
              'UPDATE news SET syncStatus = ? WHERE newsID IN ($placeholders)',
              [FluxNewsState.syncedSyncStatus, ...chunk],
            );
          }
        } finally {
          if (httpClient == null) client.close();
        }
      }
    }
  }
  if (appState.debugMode) {
    logThis('toggleNewsAsRead',
        'Finished toggle news as read at miniflux server', LogLevel.INFO);
  }
}

// mark one news directly as read at the miniflux server
Future<void> toggleOneNewsAsRead(FluxNewsState appState, News news) async {
  if (appState.debugMode) {
    logThis('toggleOneNewsAsRead',
        'Starting toggle one news as read at miniflux server', LogLevel.INFO);
  }

  // check if the miniflux url and api key is set
  if (appState.minifluxURL != null && appState.minifluxAPIKey != null) {
    final client = createMinifluxHttpClient();
    try {
      List<int> newsIds = [];

      newsIds.add(news.newsID);
      ReadNewsList newReadNewsList =
          ReadNewsList(newsIds: newsIds, status: news.status);
      final header = {
        FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
        FluxNewsState.httpMinifluxContentTypeHeaderString:
            FluxNewsState.httpContentTypeString,
      };
      if (appState.customHeaders.isNotEmpty) {
        header.addAll(appState.customHeaders);
      }
      // send the ReadNewsList object to the miniflux server to mark the news as read
      final response = await client.put(
          Uri.parse('${appState.minifluxURL!}entries'),
          headers: header,
          body: jsonEncode(newReadNewsList));
      if (response.statusCode != 204) {
        logThis(
            'toggleOneNewsAsRead',
            'Got unexpected response from miniflux server: ${response.statusCode} for news ${news.newsID}',
            LogLevel.ERROR);

        // if the response code is not 204, throw a error
        throw FluxNewsState.httpUnexpectedResponseErrorString;
      }
    } finally {
      client.close();
    }
  }
  if (appState.debugMode) {
    logThis('toggleOneNewsAsRead',
        'Finished toggle one news as read at miniflux server', LogLevel.INFO);
  }
}

/// Sends the read/unread status of the given [newsIDs] to the Miniflux server
/// in the background. Shows a snackbar via [scaffoldMessenger] on failure.
/// When [suppressAfterFirstError] is true (scroll-over path), the snackbar is
/// shown only on the first failure; subsequent failures are suppressed until a
/// successful full sync resets [FluxNewsState.scrolloverSyncFailed].
Future<void> pushNewsStatusToServer(
  List<int> newsIDs,
  String status,
  FluxNewsState appState,
  ScaffoldMessengerState? scaffoldMessenger,
  String errorMessage, {
  bool suppressAfterFirstError = false,
}) async {
  if (newsIDs.isEmpty) return;
  if (appState.minifluxURL == null || appState.minifluxAPIKey == null) return;

  void handleError() {
    if (suppressAfterFirstError) {
      if (!appState.scrolloverSyncFailed) {
        appState.scrolloverSyncFailed = true;
        scaffoldMessenger?.showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    } else {
      scaffoldMessenger?.showSnackBar(SnackBar(content: Text(errorMessage)));
    }
  }

  final client = createMinifluxHttpClient();
  try {
    final header = {
      FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
      FluxNewsState.httpMinifluxContentTypeHeaderString:
          FluxNewsState.httpContentTypeString,
    };
    if (appState.customHeaders.isNotEmpty) {
      header.addAll(appState.customHeaders);
    }
    final body = ReadNewsList(newsIds: newsIDs, status: status);
    final response = await client.put(
      Uri.parse('${appState.minifluxURL!}entries'),
      headers: header,
      body: jsonEncode(body),
    );
    if (response.statusCode != 204) {
      logThis(
          'pushNewsStatusToServer',
          'Unexpected response ${response.statusCode} for IDs $newsIDs',
          LogLevel.ERROR);
      handleError();
    }
  } catch (e) {
    logThis('pushNewsStatusToServer',
        'Error syncing status to server: ${e.toString()}', LogLevel.ERROR);
    handleError();
  } finally {
    client.close();
  }
}

// mark a news as bookmarked at the miniflux server
Future<void> toggleBookmark(FluxNewsState appState, News news) async {
  if (appState.debugMode) {
    logThis('toggleBookmark', 'Starting toggle bookmark at miniflux server',
        LogLevel.INFO);
  }

  // first check if the miniflux url and api key is set
  if (appState.minifluxURL != null && appState.minifluxAPIKey != null) {
    appState.db ??= await appState.initializeDB();
    if (appState.db != null) {
      final client = createMinifluxHttpClient();
      try {
        final header = {
          FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
        };
        if (appState.customHeaders.isNotEmpty) {
          header.addAll(appState.customHeaders);
        }
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
          await appState.db!.rawUpdate(
              'UPDATE news SET starred = ? WHERE newsId = ?',
              [news.starred ? 1 : 0, news.newsID]);
          if (appState.debugMode) {
            logThis(
                'toggleBookmark',
                'Updated bookmark status of news ${news.newsID} in database',
                LogLevel.INFO);
          }
        }
      } finally {
        client.close();
      }
    }
  }
  if (appState.debugMode) {
    logThis('toggleBookmark', 'Finished toggle bookmark at miniflux server',
        LogLevel.INFO);
  }
}

// save a news to a third party service at the miniflux server
Future<void> saveNewsToThirdPartyService(
    FluxNewsState appState, News news) async {
  if (appState.debugMode) {
    logThis(
        'saveNewsToThirdPartyService',
        'Starting saving news to third party service at miniflux server',
        LogLevel.INFO);
  }

  // first check if the miniflux url and api key is set
  if (appState.minifluxURL != null && appState.minifluxAPIKey != null) {
    appState.db ??= await appState.initializeDB();
    if (appState.db != null) {
      final client = createMinifluxHttpClient();
      try {
        final header = {
          FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
        };
        if (appState.customHeaders.isNotEmpty) {
          header.addAll(appState.customHeaders);
        }
        // saving news to third party service on miniflux server
        final response = await client.post(
          Uri.parse('${appState.minifluxURL!}entries/${news.newsID}/save'),
          headers: header,
        );
        if (response.statusCode != 202) {
          if (response.statusCode == 400) {
            final errorMessage =
                jsonDecode(response.body) as Map<String, dynamic>;
            if (errorMessage['error_message'] ==
                'no third-party integration enabled') {
              if (appState.debugMode) {
                logThis('saveNewsToThirdPartyService',
                    'no third-party integration enabled', LogLevel.INFO);
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
      } finally {
        client.close();
      }
    }
  }
  if (appState.debugMode) {
    logThis(
        'saveNewsToThirdPartyService',
        'Finished saving news to third party service at miniflux server',
        LogLevel.INFO);
  }
}

// check if there are no feeds at the miniflux server, to show a hint for the users to add feeds to their miniflux account
Future<bool> checkEmptyFeeds(FluxNewsState appState) async {
  if (appState.debugMode) {
    logThis('checkEmptyFeeds',
        'Starting checking empty feeds at miniflux server', LogLevel.INFO);
  }

  // first check if the miniflux url and api key is set
  if (appState.minifluxURL != null && appState.minifluxAPIKey != null) {
    appState.db ??= await appState.initializeDB();
    if (appState.db != null) {
      final client = createMinifluxHttpClient();
      try {
        final header = {
          FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
        };
        if (appState.customHeaders.isNotEmpty) {
          header.addAll(appState.customHeaders);
        }
        // checking empty miniflux account on miniflux server
        final response = await client.get(
          Uri.parse('${appState.minifluxURL!}feeds'),
          headers: header,
        );
        if (response.statusCode != 200) {
          logThis(
              'checkEmptyFeeds',
              'Got unexpected response from miniflux server: ${response.statusCode} while checking empty feeds.',
              LogLevel.ERROR);
          // if the response code is not 200, throw an error
          throw FluxNewsState.httpUnexpectedResponseErrorString;
        }
        if (response.body.isNotEmpty) {
          Iterable feedList = json.decode(utf8.decode(response.bodyBytes));
          return feedList.isEmpty;
        }
      } finally {
        client.close();
      }
    }
  }
  if (appState.debugMode) {
    logThis('checkEmptyFeeds',
        'Finished checking empty feeds at miniflux server', LogLevel.INFO);
  }
  return true;
}

// fetch the information about the categories from the miniflux server
Future<Categories> fetchCategoryInformation(FluxNewsState appState) async {
  if (appState.debugMode) {
    logThis(
        'fetchCategoryInformation',
        'Starting fetching category information from miniflux server',
        LogLevel.INFO);
  }

  List<Category> newCategoryList = [];
  Response response;
  // first check if the miniflux url and api key is set
  if (appState.minifluxURL != null && appState.minifluxAPIKey != null) {
    appState.db ??= await appState.initializeDB();
    if (appState.db != null) {
      final client = createMinifluxHttpClient();
      try {
        final header = {
          FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
          FluxNewsState.httpMinifluxAcceptHeaderString:
              FluxNewsState.httpContentTypeString,
        };
        if (appState.customHeaders.isNotEmpty) {
          header.addAll(appState.customHeaders);
        }
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
          newCategoryList =
              List<Category>.from(l.map((model) => Category.fromJson(model)));

          // iterate over the categories list and request the feeds for each category
          for (Category category in newCategoryList) {
            List<Feed> feedList = [];
            response = await client.get(
              Uri.parse(
                  '${appState.minifluxURL!}categories/${category.categoryID}/feeds'),
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
              feedList =
                  List<Feed>.from(l.map((model) => Feed.fromJson(model)));

              // iterate over the feeds list and query the database for the news count of the feed
              for (Feed feed in feedList) {
                int? count;
                List<Map<String, Object?>> result = await appState.db!.rawQuery(
                    'SELECT COUNT(*) FROM news WHERE feedID = ?',
                    [feed.feedID]);
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
                    result = await appState.db!.rawQuery(
                        '''SELECT DISTINCT(iconMimeType)
                                                      FROM feeds 
                                                      WHERE iconID = ?''',
                        [feed.feedIconID!]);
                    if (result.isNotEmpty) {
                      if (result.first.entries.isNotEmpty) {
                        feed.iconMimeType =
                            result.first.entries.first.value as String;
                        // read the feed icon from the file system
                        feed.icon = appState.readFeedIconFile(feed.feedIconID!);
                      }
                    }
                  } else {
                    response = await client.get(
                      Uri.parse(
                          '${appState.minifluxURL!}icons/${feed.feedIconID}'),
                      headers: header,
                    );
                    if (response.statusCode != 200) {
                      if (response.statusCode == 404) {
                        if (appState.debugMode) {
                          logThis(
                              'fetchCategoryInformation',
                              'No feed icon for feed with id ${feed.feedID}',
                              LogLevel.INFO);
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
                      FeedIcon feedIcon = FeedIcon.fromJson(
                          jsonDecode(utf8.decode(response.bodyBytes)));
                      feed.icon = feedIcon.getIcon();
                      feed.iconMimeType = feedIcon.iconMimeType;
                    }
                  }
                } else {
                  if (appState.debugMode) {
                    logThis(
                        'fetchCategoryInformation',
                        'No feed icon for feed with id ${feed.feedID}',
                        LogLevel.INFO);
                  }
                }
              }
            }
            // add the feed list to the category object
            category.feeds = feedList;
          }
        }
      } finally {
        client.close();
      }
    }
  }
  if (appState.debugMode) {
    logThis(
        'fetchCategoryInformation',
        'Finished fetching category information from miniflux server',
        LogLevel.INFO);
  }
  // return the new categories list
  Categories newCategories = Categories(categories: newCategoryList);
  return newCategories;
}

// fetch the feed icon from the miniflux server
Future<FeedIcon?> getFeedIcon(FluxNewsState appState, int feedIconID) async {
  if (appState.debugMode) {
    logThis('getFeedIcon', 'Starting getting feed icon from miniflux server',
        LogLevel.INFO);
  }

  Response response;
  FeedIcon? feedIcon;
  // first check if the miniflux url and api key is set
  if (appState.minifluxURL != null && appState.minifluxAPIKey != null) {
    appState.db ??= await appState.initializeDB();
    if (appState.db != null) {
      final client = createMinifluxHttpClient();
      try {
        // then request the feed icon from the miniflux server
        final header = {
          FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
          FluxNewsState.httpMinifluxAcceptHeaderString:
              FluxNewsState.httpContentTypeString,
        };
        if (appState.customHeaders.isNotEmpty) {
          header.addAll(appState.customHeaders);
        }
        response = await client.get(
          Uri.parse('${appState.minifluxURL!}icons/$feedIconID'),
          headers: header,
        );
        if (response.statusCode != 200) {
          if (response.statusCode == 404) {
            if (appState.debugMode) {
              logThis('getFeedIcon',
                  'No feed icon for icon with id $feedIconID', LogLevel.INFO);
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
          feedIcon =
              FeedIcon.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
        }
      } finally {
        client.close();
      }
    }
  }
  if (appState.debugMode) {
    logThis('getFeedIcon', 'Finished getting feed icon from miniflux server',
        LogLevel.INFO);
  }
  // return the feed icon
  return feedIcon;
}

Future<int?> _fetchCategoryIDByTitle(
  FluxNewsState appState,
  Client client,
  Map<String, String> header,
  String categoryTitle,
) async {
  final response = await client.get(
    Uri.parse('${appState.minifluxURL!}categories'),
    headers: header,
  );

  if (response.statusCode != 200) {
    logThis(
      'createOrGetCategory',
      'Got unexpected response from miniflux server: ${response.statusCode} while loading categories.',
      LogLevel.ERROR,
    );
    throw FluxNewsState.httpUnexpectedResponseErrorString;
  }

  Iterable categories = json.decode(utf8.decode(response.bodyBytes));
  for (final categoryJson in categories) {
    final category = Category.fromJson(categoryJson as Map<String, dynamic>);
    if (category.title == categoryTitle) {
      return category.categoryID;
    }
  }

  return null;
}

Future<int> createOrGetCategory(
    FluxNewsState appState, String categoryTitle) async {
  if (appState.minifluxURL == null || appState.minifluxAPIKey == null) {
    throw FluxNewsState.httpUnexpectedResponseErrorString;
  }

  final client = createMinifluxHttpClient();

  final header = {
    FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
    FluxNewsState.httpMinifluxAcceptHeaderString:
        FluxNewsState.httpContentTypeString,
    FluxNewsState.httpMinifluxContentTypeHeaderString:
        FluxNewsState.httpContentTypeString,
  };
  if (appState.customHeaders.isNotEmpty) {
    header.addAll(appState.customHeaders);
  }

  try {
    final existingCategoryID =
        await _fetchCategoryIDByTitle(appState, client, header, categoryTitle);
    if (existingCategoryID != null) {
      return existingCategoryID;
    }

    final response = await client.post(
      Uri.parse('${appState.minifluxURL!}categories'),
      headers: header,
      body: jsonEncode({'title': categoryTitle}),
    );

    if (response.statusCode == 201) {
      final categoryJson =
          json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final category = Category.fromJson(categoryJson);
      return category.categoryID;
    }

    final fallbackCategoryID =
        await _fetchCategoryIDByTitle(appState, client, header, categoryTitle);
    if (fallbackCategoryID != null) {
      return fallbackCategoryID;
    }

    logThis(
      'createOrGetCategory',
      'Got unexpected response from miniflux server: ${response.statusCode} while creating category.',
      LogLevel.ERROR,
    );
    throw FluxNewsState.httpUnexpectedResponseErrorString;
  } finally {
    client.close();
  }
}

Future<void> createFeedSubscription(
  FluxNewsState appState,
  String feedURL,
  int categoryID, {
  String? scraperRules,
  String? suggestedTitle,
}) async {
  if (appState.minifluxURL == null || appState.minifluxAPIKey == null) {
    throw FluxNewsState.httpUnexpectedResponseErrorString;
  }

  final client = createMinifluxHttpClient();

  final header = {
    FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
    FluxNewsState.httpMinifluxAcceptHeaderString:
        FluxNewsState.httpContentTypeString,
    FluxNewsState.httpMinifluxContentTypeHeaderString:
        FluxNewsState.httpContentTypeString,
  };
  if (appState.customHeaders.isNotEmpty) {
    header.addAll(appState.customHeaders);
  }

  try {
    int? targetFeedID;
    final Map<String, dynamic> requestBody = {
      'feed_url': feedURL,
      'category_id': categoryID,
    };
    if (scraperRules != null && scraperRules.trim().isNotEmpty) {
      requestBody['crawler'] = true;
      requestBody['scraper_rules'] = scraperRules.trim();
    }

    final response = await client.post(
      Uri.parse('${appState.minifluxURL!}feeds'),
      headers: header,
      body: jsonEncode(requestBody),
    );

    if (response.statusCode == 201) {
      if (response.body.isNotEmpty) {
        final createdFeed =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final createdFeedID = createdFeed['feed_id'];
        if (createdFeedID is int) {
          targetFeedID = createdFeedID;
        }
      }
    }

    if (response.statusCode == 400) {
      final errorBody =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final errorMessage =
          (errorBody['error_message'] ?? '').toString().toLowerCase();
      if (errorMessage.contains('already exists')) {
        targetFeedID =
            await _fetchFeedIDByFeedURL(appState, client, header, feedURL);
      } else {
        logThis(
          'createFeedSubscription',
          'Got unexpected response from miniflux server: ${response.statusCode} while creating feed $feedURL.',
          LogLevel.ERROR,
        );
        throw FluxNewsState.httpUnexpectedResponseErrorString;
      }
    } else if (response.statusCode != 201) {
      logThis(
        'createFeedSubscription',
        'Got unexpected response from miniflux server: ${response.statusCode} while creating feed $feedURL.',
        LogLevel.ERROR,
      );
      throw FluxNewsState.httpUnexpectedResponseErrorString;
    }

    if (suggestedTitle != null && suggestedTitle.trim().isNotEmpty) {
      if (targetFeedID == null) {
        logThis(
          'createFeedSubscription',
          'Could not determine feed id for $feedURL to set suggested title.',
          LogLevel.ERROR,
        );
        throw FluxNewsState.httpUnexpectedResponseErrorString;
      }
      await _updateFeedTitle(
          appState, client, header, targetFeedID, suggestedTitle.trim());
    }
  } finally {
    client.close();
  }
}

String _normalizeFeedURL(String url) {
  final parsed = Uri.tryParse(url.trim());
  if (parsed == null) {
    return url.trim();
  }

  String normalizedPath = parsed.path;
  if (normalizedPath.endsWith('/') && normalizedPath.length > 1) {
    normalizedPath = normalizedPath.substring(0, normalizedPath.length - 1);
  }

  return parsed
      .replace(
        path: normalizedPath,
        fragment: '',
      )
      .toString();
}

Future<int?> _fetchFeedIDByFeedURL(
  FluxNewsState appState,
  Client client,
  Map<String, String> header,
  String feedURL,
) async {
  final response = await client.get(
    Uri.parse('${appState.minifluxURL!}feeds'),
    headers: header,
  );

  if (response.statusCode != 200) {
    logThis(
      '_fetchFeedIDByFeedURL',
      'Got unexpected response from miniflux server: ${response.statusCode} while loading feeds.',
      LogLevel.ERROR,
    );
    throw FluxNewsState.httpUnexpectedResponseErrorString;
  }

  final normalizedTarget = _normalizeFeedURL(feedURL);
  final feedList = jsonDecode(utf8.decode(response.bodyBytes));
  if (feedList is! Iterable) {
    return null;
  }

  for (final item in feedList) {
    if (item is! Map<String, dynamic>) {
      continue;
    }

    final candidate = (item['feed_url'] ?? '').toString();
    if (_normalizeFeedURL(candidate) == normalizedTarget) {
      final id = item['id'];
      if (id is int) {
        return id;
      }
    }
  }

  return null;
}

Future<void> _updateFeedTitle(
  FluxNewsState appState,
  Client client,
  Map<String, String> header,
  int feedID,
  String title,
) async {
  final response = await client.put(
    Uri.parse('${appState.minifluxURL!}feeds/$feedID'),
    headers: header,
    body: jsonEncode({'title': title}),
  );

  if (response.statusCode != 204 && response.statusCode != 201) {
    logThis(
      '_updateFeedTitle',
      'Got unexpected response from miniflux server: ${response.statusCode} while updating feed title for $feedID.',
      LogLevel.ERROR,
    );
    throw FluxNewsState.httpUnexpectedResponseErrorString;
  }
}

Future<void> refreshAllFeeds(FluxNewsState appState) async {
  if (appState.debugMode) {
    logThis('refreshAllFeeds', 'Starting refresh all feeds at miniflux server',
        LogLevel.INFO);
  }

  if (appState.minifluxURL == null || appState.minifluxAPIKey == null) {
    throw FluxNewsState.httpUnexpectedResponseErrorString;
  }

  final client = createMinifluxHttpClient();

  final header = {
    FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
    FluxNewsState.httpMinifluxAcceptHeaderString:
        FluxNewsState.httpContentTypeString,
    FluxNewsState.httpMinifluxContentTypeHeaderString:
        FluxNewsState.httpContentTypeString,
  };
  if (appState.customHeaders.isNotEmpty) {
    header.addAll(appState.customHeaders);
  }

  try {
    final response = await client.put(
      Uri.parse('${appState.minifluxURL!}feeds/refresh'),
      headers: header,
    );

    if (response.statusCode != 204) {
      logThis(
        'refreshAllFeeds',
        'Got unexpected response from miniflux server: ${response.statusCode} while refreshing all feeds.',
        LogLevel.ERROR,
      );
      throw FluxNewsState.httpUnexpectedResponseErrorString;
    }
  } finally {
    client.close();
  }

  if (appState.debugMode) {
    logThis('refreshAllFeeds', 'Finished refresh all feeds at miniflux server',
        LogLevel.INFO);
  }
}

// check if the miniflux credentials are valid
Future<bool> checkMinifluxCredentials(
    String? miniFluxUrl, String? miniFluxApiKey, FluxNewsState appState) async {
  if (appState.debugMode) {
    logThis('checkMinifluxCredentials',
        'Starting checking miniflux credentials', LogLevel.INFO);
  }

  // first check if the miniflux url and api key is set
  if (miniFluxApiKey != null && miniFluxUrl != null) {
    final client = createMinifluxHttpClient();
    try {
      final header = {
        FluxNewsState.httpMinifluxAuthHeaderString: miniFluxApiKey,
        FluxNewsState.httpMinifluxAcceptHeaderString:
            FluxNewsState.httpContentTypeString,
      };
      if (appState.customHeaders.isNotEmpty) {
        header.addAll(appState.customHeaders);
      }
      // then request the user information from the miniflux server
      Response response =
          await client.get(Uri.parse('${miniFluxUrl}me'), headers: header);
      if (response.statusCode == 200) {
        // request the Version of the miniflux server
        response = await client.get(Uri.parse('${miniFluxUrl}version'),
            headers: header);
        if (response.statusCode == 200) {
          Version minifluxVersion =
              Version.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
          appState.minifluxVersionInt =
              int.parse(minifluxVersion.version.replaceAll(RegExp(r'\D'), ''));
          appState.minifluxVersionString = minifluxVersion.version;
          appState.storage.write(
              key: FluxNewsState.secureStorageMinifluxVersionKey,
              value: minifluxVersion.version);
          appState.refreshView();
          if (appState.debugMode) {
            logThis(
                'checkMinifluxCredentials',
                'Miniflux v1 API Version: ${minifluxVersion.version}',
                LogLevel.INFO);
          }
        } else {
          // need to remove the "v1/" part from the url to request the version api endpoint
          String minifluxBaseURL = "";
          if (miniFluxUrl.length >= 3) {
            minifluxBaseURL = miniFluxUrl.substring(0, miniFluxUrl.length - 3);
          }

          response = await client.get(Uri.parse('${minifluxBaseURL}version'),
              headers: header);
          if (response.statusCode == 200) {
            appState.minifluxVersionInt =
                int.parse(response.body.replaceAll(RegExp(r'\D'), ''));
            appState.minifluxVersionString = response.body;
            appState.storage.write(
                key: FluxNewsState.secureStorageMinifluxVersionKey,
                value: response.body);
            appState.refreshView();
            if (appState.debugMode) {
              logThis('checkMinifluxCredentials',
                  'Miniflux Version: ${response.body}', LogLevel.INFO);
            }
          } else {
            logThis(
                'checkMinifluxCredentials',
                'Got unexpected response from miniflux server: ${response.statusCode} for version',
                LogLevel.ERROR);
          }
        }
        if (appState.debugMode) {
          logThis('checkMinifluxCredentials',
              'Finished checking miniflux credentials', LogLevel.INFO);
        }
        // if the response code is 200, the credentials are valid
        return true;
      } else {
        if (appState.debugMode) {
          logThis('checkMinifluxCredentials',
              'Finished checking miniflux credentials', LogLevel.INFO);
        }
        logThis(
            'checkMinifluxCredentials',
            'Got unexpected response from miniflux server: ${response.statusCode} for checking credentials',
            LogLevel.ERROR);
        // if the response code is not 200, the credentials are invalid
        return false;
      }
    } finally {
      client.close();
    }
  } else {
    if (appState.debugMode) {
      logThis('checkMinifluxCredentials',
          'Finished checking miniflux credentials', LogLevel.INFO);
    }
    // if the miniflux url or api key is not set, the credentials are invalid
    return false;
  }
}

/// Fetches specific entries by their IDs via GET /v1/entries/{id}.
/// Returns entries regardless of read/starred status, including enclosures
/// with their current media_progression.
Future<NewsList> fetchEntriesProgressionByIds(
    FluxNewsState appState, List<int> entryIds) async {
  if (entryIds.isEmpty) return NewsList(news: [], newsCount: 0);
  if (appState.minifluxURL == null || appState.minifluxAPIKey == null) {
    return NewsList(news: [], newsCount: 0);
  }

  final client = createMinifluxHttpClient();

  final header = {
    FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
    FluxNewsState.httpMinifluxAcceptHeaderString:
        FluxNewsState.httpContentTypeString,
  };
  if (appState.customHeaders.isNotEmpty) {
    header.addAll(appState.customHeaders);
  }

  final allNews = <News>[];

  try {
    for (final entryId in entryIds) {
      final response = await client.get(
        Uri.parse('${appState.minifluxURL!}entries/$entryId'),
        headers: header,
      );
      if (response.statusCode == 200) {
        allNews.add(News.fromJson(jsonDecode(utf8.decode(response.bodyBytes))));
      } else if (response.statusCode != 404) {
        logThis(
            'fetchEntriesProgressionByIds',
            'Unexpected response ${response.statusCode} for entry $entryId',
            LogLevel.ERROR);
      }
    }
  } finally {
    client.close();
  }

  return NewsList(news: allNews, newsCount: allNews.length);
}

// sync the media progression of an enclosure with the miniflux server
bool _isMinifluxVersionAtLeast(String? versionString, List<int> minimum) {
  if (versionString == null || versionString.trim().isEmpty) {
    return false;
  }

  final parts = RegExp(r'\d+')
      .allMatches(versionString)
      .map((m) => int.parse(m.group(0)!))
      .toList();
  if (parts.isEmpty) {
    return false;
  }

  for (int i = 0; i < minimum.length; i++) {
    final currentPart = i < parts.length ? parts[i] : 0;
    final minPart = minimum[i];
    if (currentPart > minPart) return true;
    if (currentPart < minPart) return false;
  }

  return true;
}

Future<void> syncMediaProgression(FluxNewsState appState, int entryID,
    int attachmentID, int progressSeconds) async {
  if (appState.minifluxURL == null || appState.minifluxAPIKey == null) return;
  const List<int> minMediaProgressionApiVersion = [2, 2, 0]; // Miniflux 2.2.0
  if (!_isMinifluxVersionAtLeast(
      appState.minifluxVersionString, minMediaProgressionApiVersion)) {
    if (appState.debugMode) {
      logThis(
        'syncMediaProgression',
        'Skipping media progression sync. Miniflux version ${appState.minifluxVersionString ?? appState.minifluxVersionInt} is lower than 2.2.0.',
        LogLevel.INFO,
      );
    }
    return;
  }
  if (appState.debugMode) {
    logThis(
        'syncMediaProgression',
        'Syncing media progression for entry $entryID, enclosure $attachmentID: ${progressSeconds}s',
        LogLevel.INFO);
  }

  final client = createMinifluxHttpClient();

  final header = {
    FluxNewsState.httpMinifluxAuthHeaderString: appState.minifluxAPIKey!,
    FluxNewsState.httpMinifluxAcceptHeaderString:
        FluxNewsState.httpContentTypeString,
    FluxNewsState.httpMinifluxContentTypeHeaderString:
        FluxNewsState.httpContentTypeString,
  };
  if (appState.customHeaders.isNotEmpty) {
    header.addAll(appState.customHeaders);
  }

  try {
    final response = await client.put(
      Uri.parse('${appState.minifluxURL!}enclosures/$attachmentID'),
      headers: header,
      body: jsonEncode({'media_progression': progressSeconds}),
    );

    if (response.statusCode != 204) {
      logThis(
        'syncMediaProgression',
        'Got unexpected response from miniflux server: ${response.statusCode} for enclosure $attachmentID',
        LogLevel.ERROR,
      );
    }
  } finally {
    client.close();
  }

  if (appState.debugMode) {
    logThis('syncMediaProgression',
        'Finished syncing media progression for entry $entryID', LogLevel.INFO);
  }
}
