import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flux_news/functions/audio_download_service.dart';
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/functions/android_url_launcher.dart';
import 'package:flux_news/state_management/flux_news_counter_state.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:flux_news/functions/logging.dart';
import 'package:flux_news/miniflux/miniflux_backend.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/ui/audioplayer.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

// this is a helper function to get the actual tab position
// this position is used to open the context menu of the news card here
void getTapPosition(TapDownDetails details, BuildContext context, FluxNewsState appState) {
  appState.tapPosition = details.globalPosition;
}

// here is the function to show the context menu
// this menu give the option to mark a news as read or unread and to bookmark a news
void showContextMenu(News news, BuildContext context, bool searchView, FluxNewsState appState,
    FluxNewsCounterState appCounterState, int itemIndex, List<News>? newsList) async {
  //Offset offset = details.globalPosition;
  final RenderObject overlay = Overlay.of(context).context.findRenderObject()!;

  final result = await showMenu(
      context: context,
      // open the menu on the previous recognized position
      position: RelativeRect.fromRect(Rect.fromLTWH(appState.tapPosition.dx, appState.tapPosition.dy, 100, 100),
          Rect.fromLTWH(0, 0, overlay.paintBounds.size.width, overlay.paintBounds.size.height)),
      items: [
        // bookmark the news
        PopupMenuItem(
          value: FluxNewsState.contextMenuBookmarkString,
          child: Row(children: [
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Icon(
                news.starred ? Icons.star_outline : Icons.star,
              ),
            ),
            Expanded(
              child: news.starred
                  ? Text(
                      AppLocalizations.of(context)!.deleteBookmark,
                      overflow: TextOverflow.visible,
                    )
                  : Text(
                      AppLocalizations.of(context)!.addBookmark,
                      overflow: TextOverflow.visible,
                    ),
            )
          ]),
        ),
        // mark the news as unread or read
        PopupMenuItem(
          value: news.status == FluxNewsState.readNewsStatus
              ? FluxNewsState.unreadNewsStatus
              : FluxNewsState.readNewsStatus,
          child: Row(children: [
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Icon(
                news.status == FluxNewsState.readNewsStatus ? Icons.fiber_new : Icons.check,
              ),
            ),
            Expanded(
                child: news.status == FluxNewsState.readNewsStatus
                    ? Text(
                        AppLocalizations.of(context)!.markAsUnread,
                        overflow: TextOverflow.visible,
                      )
                    : Text(
                        AppLocalizations.of(context)!.markAsRead,
                        overflow: TextOverflow.visible,
                      )),
          ]),
        ),
        // save the news to third party service
        PopupMenuItem(
            enabled: appState.minifluxVersionString!.startsWith(RegExp(r'[01]|2\.0'))
                ? appState.minifluxVersionInt >= FluxNewsState.minifluxSaveMinVersion
                : true,
            value: FluxNewsState.contextMenuSaveString,
            child: Row(children: [
              const Padding(
                padding: EdgeInsets.only(right: 5),
                child: Icon(
                  Icons.save,
                ),
              ),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.contextSaveButton,
                  overflow: TextOverflow.visible,
                ),
              )
            ])),
        // save the news to third party service
        PopupMenuItem(
            value: FluxNewsState.contextMenuOpenMinifluxString,
            child: Row(children: [
              const Padding(
                padding: EdgeInsets.only(right: 5),
                child: Icon(
                  Icons.open_in_browser,
                ),
              ),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.openMinifluxShort,
                  overflow: TextOverflow.visible,
                ),
              )
            ])),
        // open News
        PopupMenuItem(
            value: FluxNewsState.contextMenuOpenString,
            child: Row(children: [
              const Padding(
                padding: EdgeInsets.only(right: 5),
                child: Icon(
                  Icons.open_in_browser,
                ),
              ),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.open,
                  overflow: TextOverflow.visible,
                ),
              )
            ])),
        // open News Comments
        PopupMenuItem(
            value: FluxNewsState.swipeActionOpenCommentsString,
            enabled: news.commentsUrl.isNotEmpty,
            child: Row(children: [
              const Padding(
                padding: EdgeInsets.only(right: 5),
                child: Icon(
                  Icons.comment,
                ),
              ),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.openComments,
                  overflow: TextOverflow.visible,
                ),
              )
            ])),
        // share the news link
        PopupMenuItem(
            value: FluxNewsState.swipeActionShareString,
            child: Row(children: [
              const Padding(
                padding: EdgeInsets.only(right: 5),
                child: Icon(
                  Icons.share,
                ),
              ),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.share,
                  overflow: TextOverflow.visible,
                ),
              )
            ])),
        // download audio
        if (news.getAudioAttachments().isNotEmpty)
          PopupMenuItem(
              value: FluxNewsState.swipeActionDownloadString,
              child: Row(children: [
                const Padding(
                  padding: EdgeInsets.only(right: 5),
                  child: Icon(
                    Icons.download,
                  ),
                ),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.downloadAudio,
                    overflow: TextOverflow.visible,
                  ),
                )
              ])),
      ]);
  switch (result) {
    case FluxNewsState.contextMenuBookmarkString:
      if (context.mounted) {
        bookmarkAction(news, appState, context, searchView);
      }
      break;
    case FluxNewsState.unreadNewsStatus:
      if (context.mounted) {
        markNewsAsUnreadAction(news, appState, context, searchView, appCounterState);
      }
      break;
    case FluxNewsState.readNewsStatus:
      if (context.mounted) {
        markNewsAsReadAction(news, appState, context, searchView, appCounterState);
      }
      if (appState.removeNewsFromListWhenRead && !searchView) {
        newsList?.removeAt(itemIndex);
      }
      break;
    case FluxNewsState.contextMenuSaveString:
      if (context.mounted) {
        saveToThirdPartyAction(news, appState, context);
      }
      break;
    case FluxNewsState.contextMenuOpenMinifluxString:
      if (news.status == FluxNewsState.unreadNewsStatus) {
        if (context.mounted) {
          openNewsAction(news, appState, context, true);
        }
        if (appState.removeNewsFromListWhenRead && !searchView) {
          newsList?.removeAt(itemIndex);
        }
      } else {
        if (context.mounted) {
          openNewsAction(news, appState, context, true);
        }
      }
      break;
    case FluxNewsState.contextMenuOpenString:
      if (news.status == FluxNewsState.unreadNewsStatus) {
        if (context.mounted) {
          openNewsAction(news, appState, context, false);
        }
        if (appState.removeNewsFromListWhenRead && !searchView) {
          newsList?.removeAt(itemIndex);
        }
      } else {
        if (context.mounted) {
          openNewsAction(news, appState, context, false);
        }
      }
      break;
    case FluxNewsState.swipeActionOpenCommentsString:
      if (context.mounted) {
        openNewsCommentsAction(news, context);
      }
      break;
    case FluxNewsState.swipeActionShareString:
      if (Platform.isAndroid) {
        SharePlus.instance.share(ShareParams(
          uri: Uri.parse(news.url),
        ));
      } else {
        if (context.mounted) {
          final box = context.findRenderObject() as RenderBox?;
          SharePlus.instance.share(ShareParams(
              uri: Uri.parse(news.url), sharePositionOrigin: box!.localToGlobal(Offset.zero) & const Size(100, 100)));
        }
      }
      break;
    case FluxNewsState.swipeActionDownloadString:
      if (context.mounted) {
        downloadAudioAction(news, appState, context);
      }
      break;
  }
}

Future<void> bookmarkAction(News news, FluxNewsState appState, BuildContext context, bool searchView) async {
// switch between bookmarked or not bookmarked depending on the previous status
  if (news.starred) {
    news.starred = false;
  } else {
    news.starred = true;
  }

  // toggle the news as bookmarked or not bookmarked at the miniflux server
  await toggleBookmark(appState, news).onError((error, stackTrace) {
    logThis('toggleBookmark', 'Caught an error in toggleBookmark function! : ${error.toString()}', LogLevel.ERROR);
    if (context.mounted) {
      if (appState.errorString != AppLocalizations.of(context)!.communicateionMinifluxError) {
        appState.errorString = AppLocalizations.of(context)!.communicateionMinifluxError;
        appState.newError = true;
        appState.refreshView();
      }
    }
  });

  // update the bookmarked status in the database
  try {
    updateNewsStarredStatusInDB(news.newsID, news.starred, appState);
    if (context.mounted) {
      updateStarredCounter(appState, context);
    }
  } catch (e) {
    logThis('updateNewsStarredStatusInDB', 'Caught an error in updateNewsStarredStatusInDB function! : ${e.toString()}',
        LogLevel.ERROR);

    if (context.mounted) {
      if (appState.errorString != AppLocalizations.of(context)!.databaseError) {
        appState.errorString = AppLocalizations.of(context)!.databaseError;
        appState.newError = true;
        appState.refreshView();
      }
    }
  }

  // if we are in the bookmarked category, reload the list of bookmarked news
  // after the previous change, because there happened changes to this list.
  if (context.mounted) {
    if (appState.appBarText == AppLocalizations.of(context)!.bookmarked) {
      appState.feedIDs = [-1];
      appState.newsList = queryNewsFromDB(appState).whenComplete(() {
        appState.jumpToItem(0);
      });
      appState.refreshView();
    } else {
      if (searchView) {
        // update the news list of the main view
        appState.newsList = queryNewsFromDB(appState).onError((error, stackTrace) {
          logThis(
              'queryNewsFromDB', 'Caught an error in queryNewsFromDB function! : ${error.toString()}', LogLevel.ERROR);
          if (context.mounted) {
            appState.errorString = AppLocalizations.of(context)!.databaseError;
          }
          return [];
        });
      }
      appState.refreshView();
    }
  }
}

Future<void> saveToThirdPartyAction(News news, FluxNewsState appState, BuildContext context) async {
  await saveNewsToThirdPartyService(appState, news).onError((error, stackTrace) {
    logThis('saveNewsToThirdPartyService',
        'Caught an error in saveNewsToThirdPartyService function! : ${error.toString()}', LogLevel.ERROR);

    if (!appState.newError) {
      if (context.mounted) {
        appState.errorString = AppLocalizations.of(context)!.communicateionMinifluxError;
      }
      appState.newError = true;
      appState.refreshView();
    }
  });

  if (context.mounted) {
    if (!appState.newError) {
      var successflulSaveSnackBar = SnackBar(
        content: Text(AppLocalizations.of(context)!.successfullSaveToThirdParty),
      );
      ScaffoldMessenger.of(context).showSnackBar(successflulSaveSnackBar);
    }
  }
}

Future<bool> _isAudioAlreadyDownloaded(Attachment attachment, FluxNewsState appState) async {
  final downloadedPaths = await AudioDownloadService.loadDownloadedPathsForAttachments(
    [attachment],
    appState.audioDownloadRetentionDays,
  );
  return downloadedPaths[attachment.attachmentID] != null;
}

Future<void> downloadAudioAction(News news, FluxNewsState appState, BuildContext context) async {
  final audioAttachments = news.getAudioAttachments();
  if (audioAttachments.isEmpty) return;

  final attachment = audioAttachments.first;
  final storageAttachmentId = AudioDownloadService.resolveStorageAttachmentId(attachment);

  // Already downloading or already on disk — nothing to do.
  final isAlreadyDownloading =
      AudioDownloadService.getActiveDownloadsSnapshot().any((p) => p.attachmentID == storageAttachmentId);
  if (isAlreadyDownloading) return;

  AudioDownloadService.cacheDownloadTitle(storageAttachmentId, news.title);
  AudioDownloadService.cacheDownloadFeedTitle(storageAttachmentId, news.feedTitle);
  // Manual download always works — clear any previous user-skipped flag.
  await AudioDownloadService.clearUserSkipped(storageAttachmentId);

  if (await _isAudioAlreadyDownloaded(attachment, appState)) return;

  if (appState.downloadAudioOnlyOnWifi) {
    final isWifiConnected = await AudioDownloadService.isWifiConnected();
    if (!isWifiConnected) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.downloadWLANWarning)),
        );
      }
      return;
    }
  }

  unawaited(() async {
    try {
      await AudioDownloadService.downloadAttachment(
        attachment,
        onlyOnWifi: appState.downloadAudioOnlyOnWifi,
        news: news,
      );
    } catch (error) {
      // Consume the cancellation flag — if the user pressed cancel, no snackbar.
      final wasCancelled = AudioDownloadService.consumeCancelledByUser(storageAttachmentId);
      if (wasCancelled) return;

      logThis('downloadAudioAction', 'Caught an error in downloadAudioAction function! : ${error.toString()}',
          LogLevel.ERROR);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.loadDownloadedDataError)),
        );
      }
    }
  }());
}

Future<void> markNewsAsReadAction(News news, FluxNewsState appState, BuildContext context, bool searchView,
    FluxNewsCounterState appCounterState) async {
  // mark a news as read, update the news read status in database
  try {
    updateNewsStatusInDB(news.newsID, FluxNewsState.readNewsStatus, appState);
  } catch (e) {
    logThis(
        'updateNewsStatusInDB', 'Caught an error in updateNewsStatusInDB function! : ${e.toString()}', LogLevel.ERROR);

    if (context.mounted) {
      if (appState.errorString != AppLocalizations.of(context)!.databaseError) {
        appState.errorString = AppLocalizations.of(context)!.databaseError;
        appState.newError = true;
        appState.refreshView();
      }
    }
  }
  // set the new read status to the news object and toggle the recalculation
  // of the news counter
  news.status = FluxNewsState.readNewsStatus;

  if (appState.syncReadStatusImmediately) {
    unawaited(pushNewsStatusToServer(
      [news.newsID],
      FluxNewsState.readNewsStatus,
      appState,
      context.mounted ? ScaffoldMessenger.of(context) : null,
      context.mounted ? AppLocalizations.of(context)!.communicateionMinifluxError : '',
    ));
  }
  if (searchView) {
    // update the news status at the miniflux server (search view always syncs immediately)
    if (!appState.syncReadStatusImmediately) {
      try {
        toggleOneNewsAsRead(appState, news);
      } catch (e) {
        logThis(
            'toggleOneNewsAsRead', 'Caught an error in toggleOneNewsAsRead function! : ${e.toString()}', LogLevel.ERROR);
      }
    }
    // update the news list of the main view
    appState.newsList = queryNewsFromDB(appState).onError((error, stackTrace) {
      logThis('queryNewsFromDB', 'Caught an error in queryNewsFromDB function! : ${error.toString()}', LogLevel.ERROR);
      if (context.mounted) {
        appState.errorString = AppLocalizations.of(context)!.databaseError;
      }
      return [];
    });
    appState.refreshView();
    appCounterState.listUpdated = true;
    appCounterState.refreshView();
  } else {
    appCounterState.listUpdated = true;
    appCounterState.refreshView();
    appState.refreshView();
  }
}

Future<void> markNewsAsUnreadAction(News news, FluxNewsState appState, BuildContext context, bool searchView,
    FluxNewsCounterState appCounterState) async {
  // mark a news as unread, update the news unread status in database
  try {
    updateNewsStatusInDB(news.newsID, FluxNewsState.unreadNewsStatus, appState);
  } catch (e) {
    logThis(
        'updateNewsStatusInDB', 'Caught an error in updateNewsStatusInDB function! : ${e.toString()}', LogLevel.ERROR);

    if (context.mounted) {
      if (appState.errorString != AppLocalizations.of(context)!.databaseError) {
        appState.errorString = AppLocalizations.of(context)!.databaseError;
        appState.newError = true;
        appState.refreshView();
      }
    }
  }
  // set the new unread status to the news object and toggle the recalculation
  // of the news counter
  news.status = FluxNewsState.unreadNewsStatus;
  if (appState.syncReadStatusImmediately) {
    unawaited(pushNewsStatusToServer(
      [news.newsID],
      FluxNewsState.unreadNewsStatus,
      appState,
      context.mounted ? ScaffoldMessenger.of(context) : null,
      context.mounted ? AppLocalizations.of(context)!.communicateionMinifluxError : '',
    ));
  }
  if (searchView) {
    // update the news status at the miniflux server (search view always syncs immediately)
    if (!appState.syncReadStatusImmediately) {
      try {
        toggleOneNewsAsRead(appState, news);
      } catch (e) {
        logThis(
            'toggleOneNewsAsRead', 'Caught an error in toggleOneNewsAsRead function! : ${e.toString()}', LogLevel.ERROR);
      }
    }
    // update the news list of the main view
    appState.newsList = queryNewsFromDB(appState).onError((error, stackTrace) {
      logThis('queryNewsFromDB', 'Caught an error in queryNewsFromDB function! : ${error.toString()}', LogLevel.ERROR);
      if (context.mounted) {
        appState.errorString = AppLocalizations.of(context)!.databaseError;
      }
      return [];
    });
    appState.refreshView();
    appCounterState.listUpdated = true;
    appCounterState.refreshView();
  } else {
    appCounterState.listUpdated = true;
    appCounterState.refreshView();
    appState.refreshView();
  }
}

Future<void> openNewsAction(
    News news, FluxNewsState appState, BuildContext context, bool overwriteOpenInMiniflux) async {
  // on tab we update the status of the news to read and open the news
  try {
    updateNewsStatusInDB(news.newsID, FluxNewsState.readNewsStatus, appState);
  } catch (e) {
    logThis(
        'updateNewsStatusInDB', 'Caught an error in updateNewsStatusInDB function! : ${e.toString()}', LogLevel.ERROR);

    if (context.mounted) {
      if (appState.errorString != AppLocalizations.of(context)!.databaseError) {
        appState.errorString = AppLocalizations.of(context)!.databaseError;
        appState.newError = true;
        appState.refreshView();
      }
    }
  }
  if (appState.syncReadStatusImmediately && context.mounted) {
    unawaited(pushNewsStatusToServer(
      [news.newsID],
      FluxNewsState.readNewsStatus,
      appState,
      ScaffoldMessenger.of(context),
      AppLocalizations.of(context)!.communicateionMinifluxError,
    ));
  }
  // update the status to read on the news list and notify the categories
  // to recalculate the news count
  news.status = FluxNewsState.readNewsStatus;
  context.read<FluxNewsCounterState>().listUpdated = true;
  context.read<FluxNewsCounterState>().refreshView();
  appState.refreshView();

  // there are difference on launching the news url between the platforms
  // on android and ios it's preferred to check first if the link can be opened
  // by an installed app, if not then the link is opened in a web-view within the app.
  String url = news.url;
  if (overwriteOpenInMiniflux) {
    if (appState.minifluxURL != null) {
      String minifluxBaseURL = appState.minifluxURL!;
      if (minifluxBaseURL.endsWith('/v1/')) {
        minifluxBaseURL = minifluxBaseURL.substring(0, minifluxBaseURL.length - 3);
      }
      url = minifluxBaseURL +
          FluxNewsState.minifluxEntryPathPrefix +
          news.feedID.toString() +
          FluxNewsState.minifluxEntryPathSuffix +
          news.newsID.toString();
    }
  }

  if (Platform.isAndroid) {
    AndroidUrlLauncher.launchUrl(context, url);
  } else {
    // catch exception if no app is installed to handle the url
    final bool nativeAppLaunchSucceeded = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalNonBrowserApplication,
    );
    //if exception is caught, open the app in web-view
    if (!nativeAppLaunchSucceeded) {
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.inAppWebView,
      );
    }
  }
}

Future<void> openNewsCommentsAction(News news, BuildContext context) async {
  // there are difference on launching the news url between the platforms
  // on android and ios it's preferred to check first if the link can be opened
  // by an installed app, if not then the link is opened in a web-view within the app.
  if (news.commentsUrl.isNotEmpty) {
    if (Platform.isAndroid) {
      AndroidUrlLauncher.launchUrl(context, news.commentsUrl);
    } else {
      // catch exception if no app is installed to handle the url
      final bool nativeAppLaunchSucceeded = await launchUrl(
        Uri.parse(news.commentsUrl),
        mode: LaunchMode.externalNonBrowserApplication,
      );
      //if exception is caught, open the app in web-view
      if (!nativeAppLaunchSucceeded) {
        await launchUrl(
          Uri.parse(news.commentsUrl),
          mode: LaunchMode.inAppWebView,
        );
      }
    }
  }
}

Future<bool> openUrlAction(String url, BuildContext context) async {
  if (Platform.isAndroid) {
    AndroidUrlLauncher.launchUrl(context, url);
  } else {
    // catch exception if no app is installed to handle the url
    final bool nativeAppLaunchSucceeded = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalNonBrowserApplication,
    );
    //if exception is caught, open the app in web-view
    if (!nativeAppLaunchSucceeded) {
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.inAppWebView,
      );
    }
  }
  return true;
}

void showDeleteAllDialog(BuildContext context, FluxNewsState appState, FluxNewsCounterState appCounterState) {
  showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog.adaptive(
            title: Text(AppLocalizations.of(context)!.markAsRead),
            content: Text('${AppLocalizations.of(context)!.markAllAsRead}?'),
            actions: <Widget>[
              TextButton(
                child: Text(AppLocalizations.of(context)!.ok),
                onPressed: () async {
                  // capture context-dependent values before async gap
                  final messenger = appState.syncReadStatusImmediately
                      ? ScaffoldMessenger.of(context)
                      : null;
                  final errorMsg = appState.syncReadStatusImmediately
                      ? AppLocalizations.of(context)!.communicateionMinifluxError
                      : '';
                  // collect IDs before marking so we can push to server
                  final List<int> idsToSync = appState.syncReadStatusImmediately
                      ? await queryUnreadNewsIDsForCurrentView(appState)
                      : <int>[];
                  // mark news as read
                  markNewsAsReadInDB(appState);
                  if (appState.syncReadStatusImmediately && idsToSync.isNotEmpty) {
                    unawaited(pushNewsStatusToServer(
                      idsToSync,
                      FluxNewsState.readNewsStatus,
                      appState,
                      messenger,
                      errorMsg,
                    ));
                  }
                  if (!context.mounted) return;
                  if (appState.selectedCategoryElementType == FluxNewsState.categoryElementType) {
                    await queryNextCategoryFromDB(appState, context).then((value) {
                      if (context.mounted) {
                        setNextCategory(value, appState, context);
                      }
                    });
                  } else if (appState.selectedCategoryElementType == FluxNewsState.feedElementType) {
                    await queryNextFeedFromDB(appState, context).then((value) {
                      if (context.mounted) {
                        setNextFeed(value, appState, context);
                      }
                    });
                  } else {
                    // refresh news list with the all news state
                    appState.newsList = queryNewsFromDB(appState).whenComplete(() {
                      appState.jumpToItem(0);
                    });

                    // notify the categories to update the news count
                    appCounterState.listUpdated = true;
                    appCounterState.refreshView();
                    appState.refreshView();
                  }
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
              ),
              TextButton(
                child: Text(AppLocalizations.of(context)!.cancel),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          ));
}

// if the title of the category is clicked,
// we want all the news of this category in the news view.
Future<void> setNextCategory(Category? category, FluxNewsState appState, BuildContext context) async {
  if (category != null) {
    // add the according feeds of this category as a filter
    appState.feedIDs = category.getFeedIDs();
    appState.selectedCategoryElementType = FluxNewsState.categoryElementType;
    // reload the news list with the new filter
    appState.newsList = queryNewsFromDB(appState).whenComplete(() {
      appState.jumpToItem(0);
    });
    // set the category title as app bar title
    // and update the news count in the app bar, if the function is activated.
    appState.appBarText = category.title;
    appState.selectedID = category.categoryID;
    if (appState.actualCategoryList != null) {
      appState.actualCategoryList!.renewNewsCount(appState, context);
    }
    // update the view after changing the values
    appState.refreshView();
  }
}

Future<void> setNextFeed(Feed? feed, FluxNewsState appState, BuildContext context) async {
  if (feed != null) {
    // if the title of the feed is clicked,
    // we want all the news of this feed in the news view.
    // on tab we want to show only the news of this feed in the news list.
    // set the feed id of the selected feed in the feedIDs filter
    appState.feedIDs = [feed.feedID];
    appState.selectedCategoryElementType = FluxNewsState.feedElementType;
    // reload the news list with the new filter
    appState.newsList = queryNewsFromDB(appState).whenComplete(() {
      appState.jumpToItem(0);
    });
    // set the feed title as app bar title
    // and update the news count in the app bar, if the function is activated.
    appState.appBarText = feed.title;
    appState.selectedID = feed.feedID;
    if (appState.actualCategoryList != null) {
      appState.actualCategoryList!.renewNewsCount(appState, context);
    }
    // update the view after changing the values
    appState.refreshView();
  }
}

void onTabAction(
    FluxNewsState appState, BuildContext context, News news, bool searchView, int itemIndex, List<News>? newsList) {
  if (_openAudioPlayerIfAvailable(news, appState, context, searchView, itemIndex, newsList)) {
    return;
  }

  if (appState.tabAction != FluxNewsState.tabActionExpandString) {
    if (news.status == FluxNewsState.unreadNewsStatus) {
      if (news.openMinifluxEntry != null) {
        if (news.openMinifluxEntry!) {
          openNewsAction(news, appState, context, true);
        } else {
          openNewsAction(news, appState, context, false);
        }
      } else {
        openNewsAction(news, appState, context, false);
      }
      if (appState.removeNewsFromListWhenRead && !searchView) {
        newsList?.removeAt(itemIndex);
      }
    } else {
      if (news.openMinifluxEntry != null) {
        if (news.openMinifluxEntry!) {
          openNewsAction(news, appState, context, true);
        } else {
          openNewsAction(news, appState, context, false);
        }
      } else {
        openNewsAction(news, appState, context, false);
      }
    }
  } else {
    if (news.expanded) {
      news.expanded = false;
    } else {
      news.expanded = true;
    }
    markNewsAsReadAction(news, appState, context, searchView, context.read<FluxNewsCounterState>());
  }
}

void onTabContentAction(
    FluxNewsState appState, BuildContext context, News news, bool searchView, int itemIndex, List<News>? newsList) {
  if (_openAudioPlayerIfAvailable(news, appState, context, searchView, itemIndex, newsList)) {
    return;
  }

  if (appState.tabAction == FluxNewsState.tabActionOpenString) {
    if (news.status == FluxNewsState.unreadNewsStatus) {
      if (news.openMinifluxEntry != null) {
        if (news.openMinifluxEntry!) {
          openNewsAction(news, appState, context, true);
        } else {
          openNewsAction(news, appState, context, false);
        }
      } else {
        openNewsAction(news, appState, context, false);
      }
      if (appState.removeNewsFromListWhenRead && !searchView) {
        newsList?.removeAt(itemIndex);
      }
    } else {
      if (news.openMinifluxEntry != null) {
        if (news.openMinifluxEntry!) {
          openNewsAction(news, appState, context, true);
        } else {
          openNewsAction(news, appState, context, false);
        }
      } else {
        openNewsAction(news, appState, context, false);
      }
    }
  } else {
    if (news.expanded) {
      news.expanded = false;
    } else {
      news.expanded = true;
    }
    markNewsAsReadAction(news, appState, context, searchView, context.read<FluxNewsCounterState>());
  }
}

bool _openAudioPlayerIfAvailable(
  News news,
  FluxNewsState appState,
  BuildContext context,
  bool searchView,
  int itemIndex,
  List<News>? newsList,
) {
  if (!appState.openAudioItemsInPlayer) {
    return false;
  }

  final hasAudio = news.getAudioAttachments().isNotEmpty;
  if (!hasAudio) {
    return false;
  }

  if (news.status == FluxNewsState.unreadNewsStatus) {
    markNewsAsReadAction(news, appState, context, searchView, context.read<FluxNewsCounterState>());
    if (appState.removeNewsFromListWhenRead && !searchView) {
      newsList?.removeAt(itemIndex);
    }
  }

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => NewsAudioPlayerScreen(news: news),
    ),
  );

  return true;
}

List<Widget> getIOSContextMenuActions(
    FluxNewsState appState, News news, BuildContext context, bool searchView, int itemIndex, List<News>? newsList) {
  return [
    CupertinoContextMenuAction(
      onPressed: () {
        bookmarkAction(news, appState, context, searchView);
        Navigator.pop(context);
      },
      trailingIcon: news.starred ? Icons.star_outline : Icons.star,
      child: news.starred
          ? Text(
              AppLocalizations.of(context)!.deleteBookmark,
              overflow: TextOverflow.visible,
            )
          : Text(
              AppLocalizations.of(context)!.addBookmark,
              overflow: TextOverflow.visible,
            ),
    ),
    CupertinoContextMenuAction(
      onPressed: () {
        if (news.status == FluxNewsState.readNewsStatus) {
          markNewsAsUnreadAction(
              news, context.read<FluxNewsState>(), context, searchView, context.read<FluxNewsCounterState>());
        } else {
          markNewsAsReadAction(
              news, context.read<FluxNewsState>(), context, searchView, context.read<FluxNewsCounterState>());
          if (context.read<FluxNewsState>().removeNewsFromListWhenRead && !searchView) {
            newsList?.removeAt(itemIndex);
          }
        }
        Navigator.pop(context);
      },
      trailingIcon: news.status == FluxNewsState.readNewsStatus ? Icons.fiber_new : Icons.check,
      child: news.status == FluxNewsState.readNewsStatus
          ? Text(
              AppLocalizations.of(context)!.markAsUnread,
              overflow: TextOverflow.visible,
            )
          : Text(
              AppLocalizations.of(context)!.markAsRead,
              overflow: TextOverflow.visible,
            ),
    ),
    appState.minifluxVersionString!.startsWith(RegExp(r'[01]|2\.0'))
        ? appState.minifluxVersionInt >= FluxNewsState.minifluxSaveMinVersion
            ? CupertinoContextMenuAction(
                onPressed: () {
                  saveToThirdPartyAction(news, context.read<FluxNewsState>(), context);
                  Navigator.pop(context);
                },
                trailingIcon: Icons.save,
                child: Text(
                  AppLocalizations.of(context)!.contextSaveButton,
                  overflow: TextOverflow.visible,
                ))
            : SizedBox.shrink()
        : CupertinoContextMenuAction(
            onPressed: () {
              saveToThirdPartyAction(news, context.read<FluxNewsState>(), context);
              Navigator.pop(context);
            },
            trailingIcon: Icons.save,
            child: Text(
              AppLocalizations.of(context)!.contextSaveButton,
              overflow: TextOverflow.visible,
            )),
    CupertinoContextMenuAction(
        onPressed: () {
          if (news.status == FluxNewsState.unreadNewsStatus) {
            openNewsAction(news, appState, context, true);
            if (appState.removeNewsFromListWhenRead && !searchView) {
              newsList?.removeAt(itemIndex);
            }
          } else {
            openNewsAction(news, appState, context, true);
          }
          Navigator.pop(context);
        },
        trailingIcon: Icons.open_in_browser,
        child: Text(
          AppLocalizations.of(context)!.openMinifluxShort,
          overflow: TextOverflow.visible,
        )),
    CupertinoContextMenuAction(
        onPressed: () {
          if (news.status == FluxNewsState.unreadNewsStatus) {
            openNewsAction(news, appState, context, false);
            if (appState.removeNewsFromListWhenRead && !searchView) {
              newsList?.removeAt(itemIndex);
            }
          } else {
            openNewsAction(news, appState, context, false);
          }
          Navigator.pop(context);
        },
        trailingIcon: Icons.open_in_browser,
        child: Text(
          AppLocalizations.of(context)!.open,
          overflow: TextOverflow.visible,
        )),
    news.getAudioAttachments().isNotEmpty
        ? CupertinoContextMenuAction(
            onPressed: () async {
              Navigator.pop(context);
              await downloadAudioAction(news, appState, context);
            },
            trailingIcon: Icons.download,
            child: Text(
              AppLocalizations.of(context)!.downloadAudio,
              overflow: TextOverflow.visible,
            ))
        : SizedBox.shrink(),
    news.commentsUrl.isNotEmpty
        ? CupertinoContextMenuAction(
            onPressed: () {
              openNewsCommentsAction(news, context);
              Navigator.pop(context);
            },
            trailingIcon: Icons.comment,
            child: Text(
              AppLocalizations.of(context)!.openComments,
              overflow: TextOverflow.visible,
            ))
        : SizedBox.shrink(),
    CupertinoContextMenuAction(
        onPressed: () {
          if (Platform.isAndroid) {
            SharePlus.instance.share(ShareParams(
              uri: Uri.parse(news.url),
            ));
          } else {
            if (context.mounted) {
              final box = context.findRenderObject() as RenderBox?;
              SharePlus.instance.share(ShareParams(
                  uri: Uri.parse(news.url),
                  sharePositionOrigin: box!.localToGlobal(Offset.zero) & const Size(100, 100)));
            }
          }
          Navigator.pop(context);
        },
        trailingIcon: Icons.share,
        child: Text(
          AppLocalizations.of(context)!.share,
          overflow: TextOverflow.visible,
        )),
  ];
}
