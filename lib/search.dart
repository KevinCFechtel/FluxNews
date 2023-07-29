import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_gen/gen_l10n/flux_news_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import 'android_url_launcher.dart';
import 'database_backend.dart';
import 'flux_news_state.dart';
import 'miniflux_backend.dart';
import 'news_model.dart';

class Search extends StatefulWidget {
  const Search({super.key});

  @override
  State<Search> createState() => _SearchState();
}

class _SearchState extends State<Search> {
  Future<List<News>> searchNewsList = Future<List<News>>.value([]);
  final TextEditingController _searchController = TextEditingController();
  late Offset _tapPosition;

  @override
  void initState() {
    super.initState();
    initConfig();
  }

  // initConfig reads the config values from the persistant storage and sets the state
  // accordingly.
  // It also initializes the database connection.
  Future<void> initConfig() async {
    FluxNewsState appState = context.read<FluxNewsState>();
    await appState.readConfigValues(context);
    if (context.mounted) {
      appState.readConfig(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    return OrientationBuilder(builder: (context, orientation) {
      if (orientation == Orientation.landscape) {
        appState.orientation = Orientation.landscape;
      } else {
        appState.orientation = Orientation.portrait;
      }
      return searchLayout(context, appState);
    });
  }

  Scaffold searchLayout(BuildContext context, FluxNewsState appState) {
    return Scaffold(
        appBar: AppBar(
          // set the title of the search page to search text field
          title: TextField(
            controller: _searchController,
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context)!.searchHint,
              hintStyle: Theme.of(context).textTheme.bodyLarge,
              border:
                  UnderlineInputBorder(borderRadius: BorderRadius.circular(2)),
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() {
                    _searchController.clear();
                    searchNewsList = Future<List<News>>.value([]);
                  });
                },
                icon: const Icon(Icons.clear),
              ),
            ),

            // on change of the search text field, fetch the news list
            onSubmitted: (value) async {
              if (value != '') {
                // fetch the news list from the backend with the search text
                Future<List<News>> searchNewsListResult =
                    fetchSearchedNews(http.Client(), appState, value)
                        .onError((error, stackTrace) {
                  FlutterLogs.logThis(
                      tag: FluxNewsState.logTag,
                      subTag: 'fetchSearchedNews',
                      logMessage:
                          'Caught an error in fetchSearchedNews function!',
                      errorMessage: error.toString(),
                      level: LogLevel.ERROR);
                  if (appState.errorString !=
                      AppLocalizations.of(context)!
                          .communicateionMinifluxError) {
                    appState.errorString = AppLocalizations.of(context)!
                        .communicateionMinifluxError;
                    appState.newError = true;
                    appState.refreshView();
                  }
                  return [];
                });
                // set the state with the fetched news list
                setState(() {
                  searchNewsList = searchNewsListResult;
                });
              } else {
                // if search text is empty, set the state with an empty list
                setState(() {
                  searchNewsList = Future<List<News>>.value([]);
                });
              }
            },
          ),
        ),
        // show the news list
        body: newsListWidget(context, appState));
  }

  // the list view widget with search result
  Widget newsListWidget(BuildContext context, FluxNewsState appState) {
    var getData = FutureBuilder<List<News>>(
      future: searchNewsList,
      builder: (context, snapshot) {
        switch (snapshot.connectionState) {
          case ConnectionState.none:
          case ConnectionState.waiting:
            return const Center(child: CircularProgressIndicator.adaptive());
          default:
            if (snapshot.hasError) {
              return const SizedBox.shrink();
            } else {
              return snapshot.data == null
                  // show empty dialog if list is null
                  ? Center(
                      child: Text(
                      AppLocalizations.of(context)!.emptySearch,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ))
                  // show empty dialog if list is empty
                  : snapshot.data!.isEmpty
                      ? Center(
                          child: Text(
                          AppLocalizations.of(context)!.emptySearch,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ))
                      // otherwise create list view with the news of the search result
                      : ListView(
                          children: snapshot.data!
                              .map((news) => appState.orientation ==
                                      Orientation.landscape
                                  ? showNewsRow(news, appState, context)
                                  : appState.isTablet
                                      ? showNewsRow(news, appState, context)
                                      : showNewsCard(news, appState, context))
                              .toList(),
                        );
            }
        }
      },
    );
    return getData;
  }

  // here we define the appearance of the news cards
  Widget showNewsCard(News news, FluxNewsState appState, BuildContext context) {
    return Card(
      // inkwell is used for the onTab and onLongPress functions
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        onTap: () async {
          // there are difference on launching the news url between the platforms
          // on android and ios it's preferred to check first if the link can be opened
          // by an installed app, if not then the link is opened in a webview within the app.
          // on macos we open directly the webview within the app.
          if (Platform.isAndroid) {
            AndroidUrlLauncher.launchUrl(context, news.url);
          } else if (Platform.isIOS) {
            // catch exception if no app is installed to handle the url
            final bool nativeAppLaunchSucceeded = await launchUrl(
              Uri.parse(news.url),
              mode: LaunchMode.externalNonBrowserApplication,
            );
            //if exception is catched, open the app in webview
            if (!nativeAppLaunchSucceeded) {
              await launchUrl(
                Uri.parse(news.url),
                mode: LaunchMode.inAppWebView,
              );
            }
          } else if (Platform.isMacOS) {
            await launchUrl(
              Uri.parse(news.url),
              mode: LaunchMode.externalApplication,
            );
          }
        },
        // on tap get the actual position of the list on tab
        // to place the context menu on this position
        onTapDown: (details) {
          getTapPosition(details);
        },
        // after tab on longpress, open the context menu on the tab position
        onLongPress: () {
          showContextMenu(news);
        },
        child: Column(
          children: [
            // load the news image if present
            news.getImageURL() != FluxNewsState.noImageUrlString
                ? SizedBox(
                    // for tablets we need to restrict the width,
                    // becaus the fit of the image is set to cover
                    height: appState.isTablet ? 400 : 175,
                    width: double.infinity,
                    // the CachedNetworkImage is used to load the images
                    child: CachedNetworkImage(
                      imageUrl: news.getImageURL(),
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => const Icon(
                        Icons.error,
                      ),
                    ),
                  )
                // if no image is available, shrink this widget
                : const SizedBox.shrink(),
            // the title and additional infos are presented within a ListTile
            // the Opacity decide between read and unread news
            ListTile(
                title: Opacity(
                  opacity:
                      news.status == FluxNewsState.unreadNewsStatus ? 1.0 : 0.6,
                  child: Text(
                    news.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                subtitle: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                        top: 2.0,
                      ),
                      child: Row(
                        children: [
                          news.status == FluxNewsState.unreadNewsStatus
                              ? const Padding(
                                  padding: EdgeInsets.only(right: 15.0),
                                  child: SizedBox(
                                      width: 15,
                                      height: 35,
                                      child: Icon(
                                        Icons.fiber_new,
                                      )))
                              : const SizedBox.shrink(),
                          appState.showFeedIcons
                              ? Padding(
                                  padding: const EdgeInsets.only(right: 5.0),
                                  child:
                                      news.getFeedIcon(16.0, context, appState))
                              : const SizedBox.shrink(),
                          Padding(
                            padding: const EdgeInsets.only(left: 0.0),
                            child: Opacity(
                              opacity:
                                  news.status == FluxNewsState.unreadNewsStatus
                                      ? 1.0
                                      : 0.6,
                              child: Text(
                                news.feedTitel,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: Opacity(
                              opacity:
                                  news.status == FluxNewsState.unreadNewsStatus
                                      ? 1.0
                                      : 0.6,
                              child: Text(
                                appState.dateFormat
                                    .format(news.getPublishingDate()),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 40,
                            height: 35,
                            child: Opacity(
                              opacity:
                                  news.status == FluxNewsState.unreadNewsStatus
                                      ? 1.0
                                      : 0.6,
                              child: news.starred
                                  ? const Icon(
                                      Icons.star,
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // here is the news text, the Opacity decide between read and unread
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0, bottom: 10),
                      child: Opacity(
                        opacity: news.status == FluxNewsState.unreadNewsStatus
                            ? 1.0
                            : 0.6,
                        child: Text(
                          news.getText(),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ],
                )),
          ],
        ),
      ),
    );
  }

  Widget showNewsRow(News news, FluxNewsState appState, BuildContext context) {
    return Card(
      // inkwell is used for the onTab and onLongPress functions
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        onTap: () async {
          // there are difference on launching the news url between the platforms
          // on android and ios it's preferred to check first if the link can be opened
          // by an installed app, if not then the link is opened in a webview within the app.
          // on macos we open directly the webview within the app.
          if (Platform.isAndroid) {
            AndroidUrlLauncher.launchUrl(context, news.url);
          } else if (Platform.isIOS) {
            // catch exception if no app is installed to handle the url
            final bool nativeAppLaunchSucceeded = await launchUrl(
              Uri.parse(news.url),
              mode: LaunchMode.externalNonBrowserApplication,
            );
            //if exception is catched, open the app in webview
            if (!nativeAppLaunchSucceeded) {
              await launchUrl(
                Uri.parse(news.url),
                mode: LaunchMode.inAppWebView,
              );
            }
          } else if (Platform.isMacOS) {
            await launchUrl(
              Uri.parse(news.url),
              mode: LaunchMode.externalApplication,
            );
          }
        },
        // on tap get the actual position of the list on tab
        // to place the context menu on this position
        onTapDown: (details) {
          getTapPosition(details);
        },
        // after tab on longpress, open the context menu on the tab position
        onLongPress: () {
          showContextMenu(news);
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // load the news image if present
            news.getImageURL() != FluxNewsState.noImageUrlString
                ? Expanded(
                    flex: 5,
                    child: SizedBox(
                      // in the row view we have a fixed size of the image
                      height: 200,
                      width: 300,
                      // the CachedNetworkImage is used to load the images
                      child: CachedNetworkImage(
                        imageUrl: news.getImageURL(),
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        errorWidget: (context, url, error) => const Icon(
                          Icons.error,
                        ),
                      ),
                    ),
                  )
                // if no image is available, shrink this widget
                : const SizedBox.shrink(),
            // the title and additional infos are presented within a ListTile
            // the Opacity decide between read and unread news
            Expanded(
              flex: 5,
              child: ListTile(
                  title: Opacity(
                    opacity: news.status == FluxNewsState.unreadNewsStatus
                        ? 1.0
                        : 0.6,
                    child: Text(
                      news.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  subtitle: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          top: 2.0,
                        ),
                        child: Row(
                          children: [
                            news.status == FluxNewsState.unreadNewsStatus
                                ? const Padding(
                                    padding: EdgeInsets.only(right: 15.0),
                                    child: SizedBox(
                                        width: 15,
                                        height: 35,
                                        child: Icon(
                                          Icons.fiber_new,
                                        )))
                                : const SizedBox.shrink(),
                            appState.showFeedIcons
                                ? Padding(
                                    padding: const EdgeInsets.only(right: 5.0),
                                    child: news.getFeedIcon(
                                        16.0, context, appState))
                                : const SizedBox.shrink(),
                            Padding(
                              padding: const EdgeInsets.only(left: 0.0),
                              child: Opacity(
                                opacity: news.status ==
                                        FluxNewsState.unreadNewsStatus
                                    ? 1.0
                                    : 0.6,
                                child: Text(
                                  news.feedTitel,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Opacity(
                                opacity: news.status ==
                                        FluxNewsState.unreadNewsStatus
                                    ? 1.0
                                    : 0.6,
                                child: Text(
                                  appState.dateFormat
                                      .format(news.getPublishingDate()),
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 40,
                              height: 35,
                              child: Opacity(
                                opacity: news.status ==
                                        FluxNewsState.unreadNewsStatus
                                    ? 1.0
                                    : 0.6,
                                child: news.starred
                                    ? const Icon(
                                        Icons.star,
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // here is the news text, the Opacity decide between read and unread
                      Padding(
                        padding: const EdgeInsets.only(top: 2.0, bottom: 10),
                        child: Opacity(
                          opacity: news.status == FluxNewsState.unreadNewsStatus
                              ? 1.0
                              : 0.6,
                          child: Text(
                            news.getText(),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    ],
                  )),
            ),
          ],
        ),
      ),
    );
  }

  // this is a helper function to get the actual tab position
  // this position is used to open the context menue of the news card here
  void getTapPosition(TapDownDetails details) {
    final RenderBox referenceBox = context.findRenderObject() as RenderBox;
    setState(() {
      _tapPosition = referenceBox.globalToLocal(details.globalPosition);
    });
  }

  // here is the function to show the context menu
  // this menu give the option to mark a news as read or unread and to bookmark a news
  void showContextMenu(News news) async {
    final RenderObject? overlay =
        Overlay.of(context).context.findRenderObject();
    FluxNewsState appState = context.read<FluxNewsState>();

    final result = await showMenu(
        context: context,
        // open the menu on the prevoius recognized position
        position: RelativeRect.fromRect(
            Rect.fromLTWH(_tapPosition.dx, _tapPosition.dy, 100, 100),
            Rect.fromLTWH(0, 0, overlay!.paintBounds.size.width,
                overlay.paintBounds.size.height)),
        items: [
          // bokmark the news
          PopupMenuItem(
            value: FluxNewsState.contextMenueBookmarkString,
            child: news.starred
                ? Row(children: [
                    const Icon(
                      Icons.star_outline,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 5),
                      child: Text(AppLocalizations.of(context)!.deleteBookmark),
                    )
                  ])
                : Row(children: [
                    const Icon(
                      Icons.star,
                    ),
                    Padding(
                        padding: const EdgeInsets.only(left: 5),
                        child: Text(AppLocalizations.of(context)!.addBookmark)),
                  ]),
          ),
          // mark the news as unread or read
          PopupMenuItem(
            value: news.status == FluxNewsState.readNewsStatus
                ? FluxNewsState.unreadNewsStatus
                : FluxNewsState.readNewsStatus,
            child: Row(children: [
              Icon(
                news.status == FluxNewsState.readNewsStatus
                    ? Icons.fiber_new
                    : Icons.remove_red_eye_outlined,
              ),
              Padding(
                  padding: const EdgeInsets.only(left: 5),
                  child: news.status == FluxNewsState.readNewsStatus
                      ? Text(AppLocalizations.of(context)!.markAsUnread)
                      : Text(AppLocalizations.of(context)!.markAsRead)),
            ]),
          ),
        ]);
    switch (result) {
      case FluxNewsState.contextMenueBookmarkString:
        // switch between bookmarked or not bookmarked depending on the prevoius status
        if (news.starred) {
          setState(() {
            news.starred = false;
          });
        } else {
          setState(() {
            news.starred = true;
          });
        }

        // toggle the news as bookmarked or not bookmarked at the miniflux server
        await toggleBookmark(http.Client(), appState, news)
            .onError((error, stackTrace) {
          FlutterLogs.logThis(
              tag: FluxNewsState.logTag,
              subTag: 'toggleBookmark',
              logMessage: 'Caught an error in toggleBookmark function!',
              errorMessage: error.toString(),
              level: LogLevel.ERROR);
          if (appState.errorString !=
              AppLocalizations.of(context)!.communicateionMinifluxError) {
            appState.errorString =
                AppLocalizations.of(context)!.communicateionMinifluxError;
            appState.newError = true;
            appState.refreshView();
          }
        });

        // update the bookmarked status in the database
        try {
          updateNewsStarredStatusInDB(news.newsID, news.starred, appState);
          if (context.mounted) {
            updateStarredCounter(appState, context);
          }
        } catch (e) {
          FlutterLogs.logThis(
              tag: FluxNewsState.logTag,
              subTag: 'updateNewsStarredStatusInDB',
              logMessage:
                  'Caught an error in updateNewsStarredStatusInDB function!',
              errorMessage: e.toString(),
              level: LogLevel.ERROR);
          if (context.mounted) {
            if (appState.errorString !=
                AppLocalizations.of(context)!.databaseError) {
              appState.errorString =
                  AppLocalizations.of(context)!.databaseError;
              appState.newError = true;
              appState.refreshView();
            }
          }
        }
        // update the news list of the main view
        appState.newsList = queryNewsFromDB(appState, appState.feedIDs)
            .onError((error, stackTrace) {
          FlutterLogs.logThis(
              tag: FluxNewsState.logTag,
              subTag: 'queryNewsFromDB',
              logMessage: 'Caught an error in queryNewsFromDB function!',
              errorMessage: error.toString(),
              level: LogLevel.ERROR);
          appState.errorString = AppLocalizations.of(context)!.databaseError;
          return [];
        });
        break;
      case FluxNewsState.unreadNewsStatus:
        // mark a news as unread, update the news unread status in database
        try {
          updateNewsStatusInDB(
              news.newsID, FluxNewsState.unreadNewsStatus, appState);
        } catch (e) {
          FlutterLogs.logThis(
              tag: FluxNewsState.logTag,
              subTag: 'updateNewsStatusInDB',
              logMessage: 'Caught an error in updateNewsStatusInDB function!',
              errorMessage: e.toString(),
              level: LogLevel.ERROR);
          if (context.mounted) {
            if (appState.errorString !=
                AppLocalizations.of(context)!.databaseError) {
              appState.errorString =
                  AppLocalizations.of(context)!.databaseError;
              appState.newError = true;
              appState.refreshView();
            }
          }
        }
        // set the new unread status to the news object and toggle the recalculation
        // of the news counter
        setState(() {
          news.status = FluxNewsState.unreadNewsStatus;
        });
        // update the news status at the miniflux server
        try {
          toggleOneNewsAsRead(http.Client(), appState, news);
        } catch (e) {
          FlutterLogs.logThis(
              tag: FluxNewsState.logTag,
              subTag: 'toggleOneNewsAsRead',
              logMessage: 'Caught an error in toggleOneNewsAsRead function!',
              errorMessage: e.toString(),
              level: LogLevel.ERROR);
        }
        // update the news list of the main view
        appState.newsList = queryNewsFromDB(appState, appState.feedIDs)
            .onError((error, stackTrace) {
          FlutterLogs.logThis(
              tag: FluxNewsState.logTag,
              subTag: 'queryNewsFromDB',
              logMessage: 'Caught an error in queryNewsFromDB function!',
              errorMessage: error.toString(),
              level: LogLevel.ERROR);
          appState.errorString = AppLocalizations.of(context)!.databaseError;
          return [];
        });
        break;
      case FluxNewsState.readNewsStatus:
        // mark a news as read, update the news read status in database
        try {
          updateNewsStatusInDB(
              news.newsID, FluxNewsState.readNewsStatus, appState);
        } catch (e) {
          FlutterLogs.logThis(
              tag: FluxNewsState.logTag,
              subTag: 'updateNewsStatusInDB',
              logMessage: 'Caught an error in updateNewsStatusInDB function!',
              errorMessage: e.toString(),
              level: LogLevel.ERROR);
          if (context.mounted) {
            if (appState.errorString !=
                AppLocalizations.of(context)!.databaseError) {
              appState.errorString =
                  AppLocalizations.of(context)!.databaseError;
              appState.newError = true;
              appState.refreshView();
            }
          }
        }
        // set the new read status to the news object and toggle the recalculation
        // of the news counter
        setState(() {
          news.status = FluxNewsState.readNewsStatus;
        });
        // update the news status at the miniflux server
        try {
          toggleOneNewsAsRead(http.Client(), appState, news);
        } catch (e) {
          FlutterLogs.logThis(
              tag: FluxNewsState.logTag,
              subTag: 'toggleOneNewsAsRead',
              logMessage: 'Caught an error in toggleOneNewsAsRead function!',
              errorMessage: e.toString(),
              level: LogLevel.ERROR);
        }

        // update the news list of the main view
        appState.newsList = queryNewsFromDB(appState, appState.feedIDs)
            .onError((error, stackTrace) {
          FlutterLogs.logThis(
              tag: FluxNewsState.logTag,
              subTag: 'queryNewsFromDB',
              logMessage: 'Caught an error in queryNewsFromDB function!',
              errorMessage: error.toString(),
              level: LogLevel.ERROR);
          appState.errorString = AppLocalizations.of(context)!.databaseError;
          return [];
        });
        break;
    }
  }
}
