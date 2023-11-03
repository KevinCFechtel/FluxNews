import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flux_news/flux_news_counter_state.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_gen/gen_l10n/flux_news_localizations.dart';

import 'flux_news_state.dart';
import 'miniflux_backend.dart';
import 'news_model.dart';

// function to insert news in database which are located in the newsList parameter
Future<int> insertNewsInDB(NewsList newsList, FluxNewsState appState) async {
  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'insertNewsInDB',
          logMessage: 'Starting inserting news in DB',
          level: LogLevel.INFO);
    }
  }
  // init the return value of the function
  int result = 0;
  // if not already initialized, init the database
  appState.db ??= await appState.initializeDB();
  // init resultset to check the existance of the news
  List<Map<String, Object?>> resultSelect = [];
  // prevent a uninitialized database
  if (appState.db != null) {
    // iterate over the new news
    for (News news in newsList.news) {
      // check if news already present in the database
      resultSelect = await appState.db!
          .rawQuery('SELECT * FROM news WHERE newsID = ?', [news.newsID]);
      // if the news is not present, insert the news
      if (resultSelect.isEmpty) {
        result = await appState.db!.insert('news', news.toMap());

        // insert the first image attachment of the news in the attachments db
        Attachment immageAttachment = news.getFirstImmageAttachment();
        if (immageAttachment.attachmentID != -1) {
          result = await appState.db!
              .insert('attachments', immageAttachment.toMap());
        }

        if (appState.debugMode) {
          if (Platform.isAndroid || Platform.isIOS) {
            FlutterLogs.logThis(
                tag: FluxNewsState.logTag,
                subTag: 'insertNewsInDB',
                logMessage: 'Inserted news with id ${news.newsID} in DB',
                level: LogLevel.INFO);
          }
        }
      } else {
        // if the news is present, update the status of the news
        result = await appState.db!.rawUpdate(
            'UPDATE news SET status = ?, syncStatus = ? WHERE newsId = ?',
            [news.status, FluxNewsState.notSyncedSyncStatus, news.newsID]);
        if (appState.debugMode) {
          if (Platform.isAndroid || Platform.isIOS) {
            FlutterLogs.logThis(
                tag: FluxNewsState.logTag,
                subTag: 'insertNewsInDB',
                logMessage: 'Updated news with id ${news.newsID} in DB',
                level: LogLevel.INFO);
          }
        }
      }
      // check if the feed of the news already contains an icon
      resultSelect = await appState.db!
          .rawQuery('SELECT icon FROM feeds WHERE feedID = ?', [news.feedID]);
      if (resultSelect.isEmpty) {
        // if the feed doesn't contain a icon, fetch the icon from the miniflux server
        FeedIcon? icon =
            await getFeedIcon(http.Client(), appState, news.feedID);
        if (icon != null) {
          // if the icon is successflully fetched, insert the icon into the database
          result = await appState.db!.rawInsert(
              'INSERT INTO feeds (feedID, title, icon, iconMimeType) VALUES(?,?,?,?)',
              [news.feedID, news.feedTitel, icon.getIcon(), icon.iconMimeType]);
          if (appState.debugMode) {
            if (Platform.isAndroid || Platform.isIOS) {
              FlutterLogs.logThis(
                  tag: FluxNewsState.logTag,
                  subTag: 'insertNewsInDB',
                  logMessage:
                      'Inserted Feed icon for feed with id ${news.feedID} in DB',
                  level: LogLevel.INFO);
            }
          }
        }
      }
    }
  }
  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'insertNewsInDB',
          logMessage: 'Finished inserting news in DB',
          level: LogLevel.INFO);
    }
  }
  // return the result from the inserts into the database
  return result;
}

// update the bookmarked news in the database which are located in the newsList parameter
Future<int> updateStarredNewsInDB(
    NewsList newsList, FluxNewsState appState) async {
  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'updateStarredNewsInDB',
          logMessage: 'Starting updating starred news in DB',
          level: LogLevel.INFO);
    }
  }
  int result = 0;
  appState.db ??= await appState.initializeDB();
  if (appState.db != null) {
    List<Map<String, Object?>> resultSelect = [];
    for (News news in newsList.news) {
      // check if the news is already marked as bookmarked
      resultSelect = await appState.db!.rawQuery(
          'SELECT * FROM news WHERE newsID = ? AND starred = ?',
          [news.newsID, 1]);
      if (resultSelect.isEmpty) {
        // if the news is not already marked, mark it as bookmarked
        result = await appState.db!.rawUpdate(
            'UPDATE news SET starred = ? WHERE newsId = ?', [1, news.newsID]);
        if (appState.debugMode) {
          if (Platform.isAndroid || Platform.isIOS) {
            FlutterLogs.logThis(
                tag: FluxNewsState.logTag,
                subTag: 'updateStarredNewsInDB',
                logMessage:
                    'Marked news with id ${news.newsID} as bookmarked in DB',
                level: LogLevel.INFO);
          }
        }
      }
    }
    // check if the existing bookmarks also exist in the given list.
    // if not, delete the bookmark flag at the news
    List<News> existingNotStarredNews = [];
    resultSelect = await appState.db!
        .rawQuery('SELECT * FROM news WHERE starred = ?', [1]);
    if (resultSelect.isNotEmpty) {
      existingNotStarredNews =
          resultSelect.map((e) => News.fromMap(e)).toList();
    }
    for (News news in existingNotStarredNews) {
      if (!newsList.news.any((item) => item.newsID == news.newsID)) {
        result = await appState.db!.rawUpdate(
            'UPDATE news SET starred = ? WHERE newsId = ?', [0, news.newsID]);
        if (appState.debugMode) {
          if (Platform.isAndroid || Platform.isIOS) {
            FlutterLogs.logThis(
                tag: FluxNewsState.logTag,
                subTag: 'updateStarredNewsInDB',
                logMessage:
                    'Deleted starred status for news with id ${news.newsID} in DB',
                level: LogLevel.INFO);
          }
        }
      }
    }
  }
  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'updateStarredNewsInDB',
          logMessage: 'Finished updating starred news in DB',
          level: LogLevel.INFO);
    }
  }
  return result;
}

// chek if the local unread news exists in the list of new fetched unread news.
// if the news doesn't exists, it means that this news was marked by another app as read.
// so we mark the news also as read.
Future<int> markNotFetchedNewsAsRead(
    NewsList newNewsList, FluxNewsState appState) async {
  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'markNotFetchedNewsAsRead',
          logMessage: 'Starting marking not fetched news as read',
          level: LogLevel.INFO);
    }
  }
  int result = 0;
  appState.db ??= await appState.initializeDB();
  if (appState.db != null) {
    List<Map<String, Object?>> resultSelect = [];
    List<News> existingNews = [];
    // get the local unread news
    resultSelect = await appState.db!.rawQuery(
        'SELECT * FROM news WHERE status = ? AND syncStatus = ?',
        [FluxNewsState.unreadNewsStatus, FluxNewsState.notSyncedSyncStatus]);
    if (resultSelect.isNotEmpty) {
      existingNews = resultSelect.map((e) => News.fromMap(e)).toList();
    }

    for (News news in existingNews) {
      // check if the news exists in the unread news list which was fetched.
      if (!newNewsList.news.any((item) => item.newsID == news.newsID)) {
        // if not, mark the news as read
        result = await appState.db!.rawUpdate(
            'UPDATE news SET status = ?, syncStatus = ? WHERE newsId = ?', [
          FluxNewsState.readNewsStatus,
          FluxNewsState.syncedSyncStatus,
          news.newsID
        ]);
        if (appState.debugMode) {
          if (Platform.isAndroid || Platform.isIOS) {
            FlutterLogs.logThis(
                tag: FluxNewsState.logTag,
                subTag: 'markNotFetchedNewsAsRead',
                logMessage:
                    'Marked the news with id ${news.newsID} as read in DB',
                level: LogLevel.INFO);
          }
        }
      }
    }
  }
  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'markNotFetchedNewsAsRead',
          logMessage: 'Finished marking not fetched news as read',
          level: LogLevel.INFO);
    }
  }
  return result;
}

// get the local saved news from the database
Future<List<News>> queryNewsFromDB(
    FluxNewsState appState, List<int>? feedIDs) async {
  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'queryNewsFromDB',
          logMessage: 'Starting querying news from DB',
          level: LogLevel.INFO);
    }
  }
  List<News> newList = [];
  appState.db ??= await appState.initializeDB();
  if (appState.db != null) {
    String status = '';
    // decide if the news status is set to diyplay all news or only the unread
    if (appState.newsStatus == FluxNewsState.allNewsString) {
      status = FluxNewsState.databaseAllString;
    } else {
      status = appState.newsStatus;
    }

    // decide if the sort order is ascending or descending
    String sortOrder = FluxNewsState.databaseDescString;
    if (appState.sortOrder != null) {
      if (appState.sortOrder == FluxNewsState.sortOrderNewestFirstString) {
        sortOrder = FluxNewsState.databaseDescString;
      } else {
        sortOrder = FluxNewsState.databaseAscString;
      }
    }

    if (feedIDs != null) {
      // if the feed id is not null a categorie, a feed or the bookmarked news ar selected
      if (appState.feedIDs?.first == -1) {
        // if the feed id is -1 the bookmarked news are selected
        List<Map<String, Object?>> queryResult =
            await appState.db!.rawQuery('''SELECT news.newsID, 
                      news.feedID, 
                      news.title, 
                      news.url, 
                      news.content, 
                      news.hash, 
                      news.publishedAt, 
                      news.createdAt, 
                      news.status, 
                      news.readingTime, 
                      news.starred, 
                      news.feedTitle, 
                      news.syncStatus,
                      feeds.icon,
                      feeds.iconMimeType,
                      attachments.attachmentURL,
                      attachments.attachmentMimeType
                FROM news 
                LEFT OUTER JOIN feeds ON news.feedID = feeds.feedID
                LEFT OUTER JOIN attachments ON news.newsID = attachments.newsID
                WHERE news.starred = ? 
                ORDER BY news.publishedAt $sortOrder''', [1]);
        newList.addAll(queryResult.map((e) => News.fromMap(e)).toList());
      } else {
        // if the feed id is not -1 a feed or a categorie with multiple feeds is selected
        for (int feedID in feedIDs) {
          List<Map<String, Object?>> queryResult =
              await appState.db!.rawQuery('''SELECT news.newsID, 
                      news.feedID, 
                      news.title, 
                      news.url, 
                      news.content, 
                      news.hash, 
                      news.publishedAt, 
                      news.createdAt, 
                      news.status, 
                      news.readingTime, 
                      news.starred, 
                      news.feedTitle, 
                      news.syncStatus,
                      feeds.icon,
                      feeds.iconMimeType,
                      attachments.attachmentURL,
                      attachments.attachmentMimeType 
                  FROM news 
                  LEFT OUTER JOIN feeds ON news.feedID = feeds.feedID
                  LEFT OUTER JOIN attachments ON news.newsID = attachments.newsID
                  WHERE (news.status LIKE ?) 
                    AND news.feedID LIKE ? 
                  ORDER BY news.publishedAt $sortOrder''', [status, feedID]);
          newList.addAll(queryResult.map((e) => News.fromMap(e)).toList());
        }
      }
    } else {
      // if the feed id is null, "all news" are selected
      List<Map<String, Object?>> queryResult =
          await appState.db!.rawQuery('''SELECT news.newsID, 
                      news.feedID, 
                      news.title, 
                      news.url, 
                      news.content, 
                      news.hash, 
                      news.publishedAt, 
                      news.createdAt, 
                      news.status, 
                      news.readingTime, 
                      news.starred, 
                      news.feedTitle, 
                      news.syncStatus,
                      feeds.icon,
                      feeds.iconMimeType,
                      attachments.attachmentURL,
                      attachments.attachmentMimeType
              FROM news 
              LEFT OUTER JOIN feeds ON news.feedID = feeds.feedID
              LEFT OUTER JOIN attachments ON news.newsID = attachments.newsID
              WHERE (news.status LIKE ?) 
              ORDER BY news.publishedAt $sortOrder''', [status]);
      newList.addAll(queryResult.map((e) => News.fromMap(e)).toList());
    }
  }
  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'queryNewsFromDB',
          logMessage: 'Finished querying news from DB',
          level: LogLevel.INFO);
    }
  }
  return newList;
}

// update the status (read or unread) of the news in the database
void updateNewsStatusInDB(
    int newsID, String status, FluxNewsState appState) async {
  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'updateNewsStatusInDB',
          logMessage: 'Starting updating news status in DB',
          level: LogLevel.INFO);
    }
  }
  appState.db ??= await appState.initializeDB();
  if (appState.db != null) {
    await appState.db!.rawUpdate(
        'UPDATE news SET status = ? WHERE newsId = ?', [status, newsID]);
  }
  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'updateNewsStatusInDB',
          logMessage: 'Finished updating news status in DB',
          level: LogLevel.INFO);
    }
  }
}

// update the counter of the bookmarked news
void updateStarredCounter(FluxNewsState appState, BuildContext context) async {
  FluxNewsCounterState appCounterState = context.read<FluxNewsCounterState>();
  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'updateNewsStatusInDB',
          logMessage: 'Starting updating starred counter',
          level: LogLevel.INFO);
    }
  }

  int? starredNewsCount;
  appState.db ??= await appState.initializeDB();
  if (appState.db != null) {
    starredNewsCount = Sqflite.firstIntValue(await appState.db!
        .rawQuery('SELECT COUNT(*) FROM news WHERE starred = ?', [1]));
  }
  starredNewsCount ??= 0;
  // assign the count of bookmarked news to the app state variable
  appCounterState.starredCount = starredNewsCount;
  if (context.mounted) {
    if (appState.appBarText == AppLocalizations.of(context)!.bookmarked) {
      // if the bookmarked news are selected to display, assign the count
      // also to the app bar counter variable.
      appCounterState.appBarNewsCount = starredNewsCount;
    }
  }

  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'updateNewsStatusInDB',
          logMessage: 'Finished updating starred counter',
          level: LogLevel.INFO);
    }
  }
  appCounterState.refreshView();
}

// update the bookmarked flag in the database
void updateNewsStarredStatusInDB(
    int newsID, bool starred, FluxNewsState appState) async {
  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'updateNewsStarredStatusInDB',
          logMessage: 'Starting updating news starred status in DB',
          level: LogLevel.INFO);
    }
  }

  int starredStatus = 0;
  if (starred) {
    starredStatus = 1;
  }
  appState.db ??= await appState.initializeDB();
  if (appState.db != null) {
    await appState.db!.rawUpdate('UPDATE news SET starred = ? WHERE newsId = ?',
        [starredStatus, newsID]);
  }

  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'updateNewsStarredStatusInDB',
          logMessage: 'Finished updating news starred status in DB',
          level: LogLevel.INFO);
    }
  }
}

// delete the not bookmarked news, which are beyond the limit of news
// which should be saved locally.
// this limit can be changed in the settings.
Future<void> cleanUnstarredNews(FluxNewsState appState) async {
  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'cleanUnstarredNews',
          logMessage: 'Starting cleaning unstarred news',
          level: LogLevel.INFO);
    }
  }

  appState.db ??= await appState.initializeDB();
  if (appState.db != null) {
    await appState.db!.rawDelete('''DELETE FROM news 
                        WHERE starred = 0 AND newsID NOT IN 
                          (SELECT newsID 
                            FROM news 
                            WHERE starred = 0
                            ORDER BY publishedAt DESC
                            LIMIT ${appState.amountOfSavedNews})''');
  }

  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'cleanUnstarredNews',
          logMessage: 'Finished cleaning unstarred news',
          level: LogLevel.INFO);
    }
  }
}

// delete the bookmarked news, which are beyond the limit of news
// which should be saved locally.
// this limit can be changed in the settings.
// maybe the bookmarked news should have another limit as the not bookmarked news
Future<void> cleanStarredNews(FluxNewsState appState) async {
  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'cleanStarredNews',
          logMessage: 'Starting cleaning starred news',
          level: LogLevel.INFO);
    }
  }

  appState.db ??= await appState.initializeDB();
  if (appState.db != null) {
    await appState.db!.rawDelete('''DELETE FROM news 
                        WHERE starred = 1 AND newsID NOT IN 
                          (SELECT newsID 
                            FROM news 
                            WHERE starred = 1
                            ORDER BY publishedAt DESC
                            LIMIT ${appState.amountOfSavedStarredNews})''');
  }

  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'cleanStarredNews',
          logMessage: 'Finished cleaning starred news',
          level: LogLevel.INFO);
    }
  }
}

// insert the fetched categories in the database
Future<int> insertCategoriesInDB(
    Categories categorieList, FluxNewsState appState) async {
  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'insertCategoriesInDB',
          logMessage: 'Starting inserting categories in DB',
          level: LogLevel.INFO);
    }
  }

  int result = 0;
  appState.db ??= await appState.initializeDB();
  if (appState.db != null) {
    List<Map<String, Object?>> resultSelect = [];
    for (Categorie categorie in categorieList.categories) {
      // iterate over the categories and check if they already exists locally.
      resultSelect = await appState.db!.rawQuery(
          'SELECT * FROM categories WHERE categorieID = ?',
          [categorie.categorieID]);
      if (resultSelect.isEmpty) {
        // if they don't exists locally, insert the categorie
        result = await appState.db!.insert('categories', categorie.toMap());
        if (appState.debugMode) {
          if (Platform.isAndroid || Platform.isIOS) {
            FlutterLogs.logThis(
                tag: FluxNewsState.logTag,
                subTag: 'insertCategoriesInDB',
                logMessage:
                    'Inserted categorie with id ${categorie.categorieID} in DB',
                level: LogLevel.INFO);
          }
        }
      } else {
        // if they exists locally, update the categorie
        result = await appState.db!.rawUpdate(
            'UPDATE categories SET title = ? WHERE categorieID = ?',
            [categorie.title, categorie.categorieID]);
        if (appState.debugMode) {
          if (Platform.isAndroid || Platform.isIOS) {
            FlutterLogs.logThis(
                tag: FluxNewsState.logTag,
                subTag: 'insertCategoriesInDB',
                logMessage:
                    'Updated categorie with id ${categorie.categorieID} in DB',
                level: LogLevel.INFO);
          }
        }
      }
      for (Feed feed in categorie.feeds) {
        // iterate over the feeds of the categorie and check if they already exists locally
        resultSelect = await appState.db!
            .rawQuery('SELECT * FROM feeds WHERE feedID = ?', [feed.feedID]);
        if (resultSelect.isEmpty) {
          // if they don't exists locally, insert the feed
          result = await appState.db!.rawInsert(
              'INSERT INTO feeds (feedID, title, site_url, icon, iconMimeType, newsCount, categorieID) VALUES(?,?,?,?,?,?,?)',
              [
                feed.feedID,
                feed.title,
                feed.siteUrl,
                feed.icon,
                feed.iconMimeType,
                feed.newsCount,
                categorie.categorieID
              ]);
          if (appState.debugMode) {
            if (Platform.isAndroid || Platform.isIOS) {
              FlutterLogs.logThis(
                  tag: FluxNewsState.logTag,
                  subTag: 'insertCategoriesInDB',
                  logMessage: 'Inserted feed with id ${feed.feedID} in DB',
                  level: LogLevel.INFO);
            }
          }
        } else {
          // if they exists locally, update the feed
          result = await appState.db!.rawUpdate(
              'UPDATE feeds SET title = ?, site_url = ?, icon = ?, iconMimeType = ?, newsCount = ?, categorieID = ? WHERE feedID = ?',
              [
                feed.title,
                feed.siteUrl,
                feed.icon,
                feed.iconMimeType,
                feed.newsCount,
                categorie.categorieID,
                feed.feedID
              ]);
          if (appState.debugMode) {
            if (Platform.isAndroid || Platform.isIOS) {
              FlutterLogs.logThis(
                  tag: FluxNewsState.logTag,
                  subTag: 'insertCategoriesInDB',
                  logMessage: 'Updated feed with id ${feed.feedID} in DB',
                  level: LogLevel.INFO);
            }
          }
        }
      }
    }

    // check if the local categories exists in the fetched categories.
    // if they don't exists, the categorie is deleted and needs also to be deleted locally
    List<Categorie> existingCategories = [];
    // get a list of the local categories
    resultSelect = await appState.db!.rawQuery('SELECT * FROM categories');
    if (resultSelect.isNotEmpty) {
      existingCategories =
          resultSelect.map((e) => Categorie.fromMap(e)).toList();
    }

    for (Categorie categorie in existingCategories) {
      // check if the local categoires exists in the fetched list of categories
      if (!categorieList.categories
          .any((item) => item.categorieID == categorie.categorieID)) {
        result = await appState.db!.rawDelete(
            'DELETE FROM categories WHERE categorieID = ?',
            [categorie.categorieID]);
        if (appState.debugMode) {
          if (Platform.isAndroid || Platform.isIOS) {
            FlutterLogs.logThis(
                tag: FluxNewsState.logTag,
                subTag: 'insertCategoriesInDB',
                logMessage:
                    'Deleted categorie with id ${categorie.categorieID} in DB',
                level: LogLevel.INFO);
          }
        }
      }
    }

    // check if the local feeds exists in the fetched feeds.
    // if they don't exists, the feed is deleted and needs also to be deleted locally
    List<Feed> existingFeeds = [];
    bool feedFound = false;
    // get a list of the local feeds
    resultSelect = await appState.db!.rawQuery('SELECT * FROM feeds');
    if (resultSelect.isNotEmpty) {
      existingFeeds = resultSelect.map((e) => Feed.fromMap(e)).toList();
    }

    for (Feed feed in existingFeeds) {
      feedFound = false;
      for (Categorie categorie in categorieList.categories) {
        // check if the local feed exists in the fetched list of feeds
        if (categorie.feeds.any((item) => item.feedID == feed.feedID)) {
          feedFound = true;
        }
      }
      if (feedFound == false) {
        // if the feed doesn't exists, delete the feed and all the news of the feed.
        // this is because the feed seems to be deleted on the miniflux server.
        result = await appState.db!
            .rawDelete('DELETE FROM feeds WHERE feedID = ?', [feed.feedID]);
        result = await appState.db!
            .rawDelete('DELETE FROM news WHERE feedID = ?', [feed.feedID]);
        if (appState.debugMode) {
          if (Platform.isAndroid || Platform.isIOS) {
            FlutterLogs.logThis(
                tag: FluxNewsState.logTag,
                subTag: 'insertCategoriesInDB',
                logMessage:
                    'Deleted news and feed with id ${feed.feedID} in DB',
                level: LogLevel.INFO);
          }
        }
      }
    }
  }
  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'insertCategoriesInDB',
          logMessage: 'Finished inserting categories in DB',
          level: LogLevel.INFO);
    }
  }
  return result;
}

// get the categories from the database and calculate the news count of this categories
Future<Categories> queryCategoriesFromDB(
    FluxNewsState appState, BuildContext context) async {
  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'queryCategoriesFromDB',
          logMessage: 'Starting querying categories from DB',
          level: LogLevel.INFO);
    }
  }

  List<Categorie> categorieList = [];
  appState.db ??= await appState.initializeDB();
  if (appState.db != null) {
    // get the categories from the database
    List<Map<String, Object?>> queryResult =
        await appState.db!.rawQuery('SELECT * FROM categories');
    categorieList = queryResult.map((e) => Categorie.fromMap(e)).toList();
    for (Categorie categorie in categorieList) {
      List<Feed> feedlist = [];
      queryResult = await appState.db!.rawQuery(
          'SELECT * FROM feeds WHERE categorieID = ?', [categorie.categorieID]);
      feedlist = queryResult.map((e) => Feed.fromMap(e)).toList();
      categorie.feeds = feedlist;
    }
  }
  Categories categories = Categories(categories: categorieList);
  // calculate the news count of the cagegories and feeds

  if (context.mounted) {
    categories.renewNewsCount(appState, context);
    // calculate the news count of the "all news" section
    renewAllNewsCount(appState, context);
  }
  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'queryCategoriesFromDB',
          logMessage: 'Finished querying categories from DB',
          level: LogLevel.INFO);
    }
  }
  return categories;
}

// calculate the news count of the "all news" section
Future<void> renewAllNewsCount(
    FluxNewsState appState, BuildContext context) async {
  FluxNewsCounterState appCounterState = context.read<FluxNewsCounterState>();
  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'renewAllNewsCount',
          logMessage: 'Starting renewing all news count',
          level: LogLevel.INFO);
    }
  }
  appState.db ??= await appState.initializeDB();
  int? allNewsCount = 0;
  if (appState.db != null) {
    // decide if the news count should be calculated over all news
    // or only over the unread news.
    String status = '';
    if (appState.newsStatus == FluxNewsState.allNewsString) {
      status = FluxNewsState.databaseAllString;
    } else {
      status = appState.newsStatus;
    }
    allNewsCount = Sqflite.firstIntValue(await appState.db!
        .rawQuery('SELECT COUNT(*) FROM news WHERE status LIKE ?', [status]));
    allNewsCount ??= 0;
  }

  // assign the count of all news to the app state variable
  appCounterState.allNewsCount = allNewsCount;
  if (context.mounted) {
    if (appState.appBarText == AppLocalizations.of(context)!.allNews) {
      // if "all news" are selected to display, assign the count
      // also to the app bar counter variable.
      appCounterState.appBarNewsCount = allNewsCount;
    }
  }
  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'renewAllNewsCount',
          logMessage: 'Finished renewing all news count',
          level: LogLevel.INFO);
    }
  }

  // notify the app about the updated count of news
  appCounterState.refreshView();
}

// calculate the news count of the "all news" section
Future<void> deleteLocalNewsCache(
    FluxNewsState appState, BuildContext context) async {
  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'deleteLocalNewsCache',
          logMessage: 'Starting deleting the local news cache',
          level: LogLevel.INFO);
    }
  }
  appState.db ??= await appState.initializeDB();
  if (appState.db != null) {
    // create the table news
    await appState.db!.execute('DROP TABLE IF EXISTS news');
    await appState.db!.execute(
      '''CREATE TABLE news(newsID INTEGER PRIMARY KEY, 
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
                          syncStatus TEXT)''',
    );
    // create the table categories
    await appState.db!.execute('DROP TABLE IF EXISTS categories');
    await appState.db!.execute(
      '''CREATE TABLE categories(categorieID INTEGER PRIMARY KEY, 
                          title TEXT)''',
    );
    // create the table feeds
    await appState.db!.execute('DROP TABLE IF EXISTS feeds');
    await appState.db!.execute(
      '''CREATE TABLE feeds(feedID INTEGER PRIMARY KEY, 
                          title TEXT, 
                          site_url TEXT, 
                          icon BLOB,
                          iconMimeType TEXT,
                          newsCount INTEGER,
                          categorieID INTEGER)''',
    );
    // create the table attachments
    await appState.db!.execute('DROP TABLE IF EXISTS attachments');
    await appState.db!.execute(
      '''CREATE TABLE attachments(attachmentID INTEGER PRIMARY KEY, 
                          newsID INTEGER, 
                          attachmentURL TEXT, 
                          attachmentMimeType TEXT)''',
    );
  }
  if (appState.debugMode) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'deleteLocalNewsCache',
          logMessage: 'Finished deleting the local news cache',
          level: LogLevel.INFO);
    }
  }
}
