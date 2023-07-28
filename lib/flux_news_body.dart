import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_gen/gen_l10n/flux_news_localizations.dart';

import 'database_backend.dart';
import 'flux_news_state.dart';
import 'miniflux_backend.dart';
import 'news_model.dart';
import 'android_url_launcher.dart';

class FluxNewsBody extends StatefulWidget {
  const FluxNewsBody({Key? key}) : super(key: key);

  @override
  State<FluxNewsBody> createState() => FluxNewsBodyState();
}

// extend class to save acutal scroll state of the list view
class FluxNewsBodyState extends State<FluxNewsBody>
    with AutomaticKeepAliveClientMixin<FluxNewsBody>, WidgetsBindingObserver {
  // init the persistant scroll state controller
  final ItemScrollController itemScrollController = ItemScrollController();
  final ItemPositionsListener itemPositionsListener =
      ItemPositionsListener.create();

  // init variables used locally in this class
  bool syncProcess = false;
  bool listUpdated = false;
  late Offset _tapPosition;
  int scrollPosition = 0;

  // init the state of FluxNewsBody to load the config and the data on startup
  @override
  void initState() {
    super.initState();
    FluxNewsState appState = context.read<FluxNewsState>();
    initConfig();
    appState.categorieList = queryCategoriesFromDB(appState, context);
    appState.newsList = Future<List<News>>.value([]);
    WidgetsBinding.instance.addObserver(this);
  }

  // helper function for the initState() to use async function on init
  Future<void> initConfig() async {
    FluxNewsState appState = context.read<FluxNewsState>();

    // read persistant saved config
    bool completed = await appState.readConfigValues(context);

    // init the sqlite database in startup
    appState.db = await appState.initializeDB();

    if (completed) {
      if (context.mounted) {
        // set the app bar text to "All News"
        appState.appBarText = AppLocalizations.of(context)!.allNews;
        // read the saved config
        appState.readConfig(context);
      }

      if (appState.syncOnStart) {
        // sync on startup
        if (context.mounted) {
          await syncNews(appState, context);
        }
      } else {
        // normal startup, read existing news from database and generate list view
        try {
          appState.newsList = queryNewsFromDB(appState, null);
          if (context.mounted) {
            updateStarredCounter(appState, context);
            await renewAllNewsCount(appState, context);
          }
        } catch (e) {
          FlutterLogs.logThis(
              tag: FluxNewsState.logTag,
              subTag: 'initConfig',
              logMessage: 'Caught an error in initConfig function!',
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
        FlutterNativeSplash.remove();
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // set the scroll position to the persistant saved scroll position on normal startup
      // if sync on startup is enabled, the scroll position is set to the top of the list
      if (!appState.syncOnStart) {
        scrollPosition = appState.savedScrollPosition;
      }

      if (appState.minifluxURL == null ||
          appState.minifluxAPIKey == null ||
          appState.errorOnMicrofluxAuth) {
        // navigate to settings screen if there are problems with the miniflux config
        appState.refreshView();
        Navigator.pushNamed(context, FluxNewsState.settingsRouteString);
      } else {
        // if everything is fine with the settings, present the list view
        appState.refreshView();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    FluxNewsState appState = context.watch<FluxNewsState>();

    // detect if the device is a tablet
    double ratio =
        MediaQuery.of(context).size.width / MediaQuery.of(context).size.height;
    if ((ratio >= 0.70) && (ratio < 1.5)) {
      appState.isTablet = true;
    } else {
      appState.isTablet = false;
    }

    // decide between landscape or portrait mode (the drawer doesn't exists in landscape mode f.e.)
    return OrientationBuilder(
      builder: (context, orientation) {
        if (orientation == Orientation.landscape) {
          appState.orientation = Orientation.landscape;
          return landscapeLayout(appState, context);
        } else {
          appState.orientation = Orientation.portrait;
          if (appState.isTablet) {
            return landscapeLayout(appState, context);
          } else {
            return portraitLayout(appState, context);
          }
        }
      },
    );
  }

  Scaffold portraitLayout(FluxNewsState appState, BuildContext context) {
    // start the main view in portrait mode
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 65,
        leading: Builder(
          builder: (BuildContext context) {
            return IconButton(
              icon: const Icon(
                FontAwesomeIcons.bookOpen,
              ),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
              tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
            );
          },
        ),
        title: appBarTitle(appState),
        actions: appBarButtons(appState, context),
      ),
      drawer: getDrawer(context, appState),
      body: Container(
        child: getBody(context, appState),
      ),
    );
  }

  Scaffold landscapeLayout(FluxNewsState appState, BuildContext context) {
    // start the main view in landscape mode, replace the drawer with a fixed list view on the left side
    return Scaffold(
      appBar: AppBar(
        title: appBarTitle(appState),
        actions: appBarButtons(appState, context),
      ),
      body: Row(
        children: [
          Expanded(
            flex: appState.isTablet ? 4 : 5,
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 20.0),
                  child: ListTile(
                    title: Text(
                      AppLocalizations.of(context)!.minifluxServer,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    subtitle: appState.minifluxURL == null
                        ? const SizedBox.shrink()
                        : Text(appState.minifluxURL!),
                  ),
                ),
                categorieListWidget(context, appState),
              ],
            ),
          ),
          Expanded(
            flex: 10,
            child: Container(
              child: getBody(context, appState),
            ),
          ),
        ],
      ),
    );
  }

  Widget getBody(BuildContext context, FluxNewsState appState) {
    // return the body of the main view
    // if errors had occured, the error widget is returned
    // if the miniflux settings are incorrect a corresponding message is shown
    // otherwise the normal list view is returned
    if (appState.minifluxURL == null ||
        appState.minifluxAPIKey == null ||
        appState.errorOnMicrofluxAuth == true) {
      return noSettingsWidget(context, appState);
    } else if (appState.errorString != '' && appState.newError) {
      return errorWidget(context, appState);
    } else {
      return newsListWidget(context, appState);
    }
  }

  Drawer getDrawer(BuildContext context, FluxNewsState appState) {
    // update the categories, feeds and news counter, if there were updates to the list view
    if (listUpdated) {
      appState.categorieList = queryCategoriesFromDB(appState, context);
      listUpdated = false;
    }
    // return the drawer
    return Drawer(
        child: Column(
      children: [
        Padding(
            padding: const EdgeInsets.only(top: 75.0),
            child: Row(children: [
              const Padding(
                  padding: EdgeInsets.only(left: 30.0),
                  child: Icon(
                    FontAwesomeIcons.bookOpen,
                  )),
              Padding(
                  padding: const EdgeInsets.only(left: 20.0),
                  child: Text(
                    AppLocalizations.of(context)!.fluxNews,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ))
            ])),
        Padding(
          padding: const EdgeInsets.only(top: 20.0),
          child: ListTile(
            title: Text(
              AppLocalizations.of(context)!.minifluxServer,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            subtitle: appState.minifluxURL == null
                ? const SizedBox.shrink()
                : Text(
                    appState.minifluxURL!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
          ),
        ),
        categorieListWidget(context, appState),
      ],
    ));
  }

  Widget appBarTitle(FluxNewsState appState) {
    // set the app bar title depending on the choosen categorie to show in list view

    if (appState.multilineAppBarText) {
      // this is the part where the news count is added as an extra line to the app bar title
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appState.appBarText,
            maxLines: 2,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            '${AppLocalizations.of(context)!.itemCount}: ${appState.appBarNewsCount}',
            style: Theme.of(context).textTheme.labelMedium,
          )
        ],
      );
    } else {
      // this is the part without the news count as an extra line
      return Text(
        appState.appBarText,
        maxLines: 2,
        textAlign: TextAlign.start,
        style: Theme.of(context).textTheme.titleLarge,
      );
    }
  }

  List<Widget> appBarButtons(FluxNewsState appState, BuildContext context) {
    // define the app bar buttons to sync with miniflux,
    // search for news and switch between all and only unread news view
    // and the navigation to the settings
    return <Widget>[
      // here is the sync part
      IconButton(
        onPressed: () async {
          await syncNews(appState, context);
        },
        icon: syncProcess
            ? const SizedBox(
                height: 15.0,
                width: 15.0,
                child: CircularProgressIndicator.adaptive(),
              )
            : const Icon(
                Icons.refresh,
              ),
      ),
      // here is the popup menu where the user can search,
      // choose between all and only unread news view
      // and navigate to the settings
      PopupMenuButton(
          icon: const Icon(Icons.more_vert),
          itemBuilder: (context) {
            return [
              // the search button
              PopupMenuItem<int>(
                value: 0,
                child: Row(
                  children: [
                    const Icon(
                      Icons.search,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 5),
                      child: Text(AppLocalizations.of(context)!.search),
                    )
                  ],
                ),
              ),
              // the switch between all and only unread news view
              PopupMenuItem<int>(
                value: 1,
                child: Row(
                  children: [
                    Icon(
                      appState.newsStatus == FluxNewsState.unreadNewsStatus
                          ? Icons.remove_red_eye_outlined
                          : Icons.fiber_new,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 5),
                      child:
                          appState.newsStatus == FluxNewsState.unreadNewsStatus
                              ? Text(AppLocalizations.of(context)!.showRead)
                              : Text(AppLocalizations.of(context)!.showUnread),
                    )
                  ],
                ),
              ),
              // the selection of the sort order of the news (newest first or oldest first)
              PopupMenuItem<int>(
                value: 2,
                child: Row(
                  children: [
                    const Icon(
                      Icons.sort,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 5),
                      child: appState.sortOrder ==
                              FluxNewsState.sortOrderNewestFirstString
                          ? Text(AppLocalizations.of(context)!.oldestFirst)
                          : Text(AppLocalizations.of(context)!.newestFirst),
                    )
                  ],
                ),
              ),
              // the navigation to the settings
              PopupMenuItem<int>(
                value: 3,
                child: Row(
                  children: [
                    const Icon(
                      Icons.settings,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 5),
                      child: Text(AppLocalizations.of(context)!.settings),
                    )
                  ],
                ),
              ),
            ];
          },
          onSelected: (value) {
            if (value == 0) {
              // navigate to the search page
              Navigator.pushNamed(context, FluxNewsState.searchRouteString);
            } else if (value == 1) {
              // switch between all and only unread news view
              // if the current view is unread news change to all news
              if (appState.newsStatus == FluxNewsState.unreadNewsStatus) {
                // switch the state to all news
                appState.newsStatus = FluxNewsState.allNewsString;

                // save the state persistant
                appState.storage.write(
                    key: FluxNewsState.secureStorageNewsStatusKey,
                    value: FluxNewsState.allNewsString);

                // refresh news list with the all news state
                appState.newsList = queryNewsFromDB(appState, appState.feedIDs)
                    .whenComplete(() {
                  waitUntilNewsListBuild().whenComplete(
                    () {
                      setState(() {
                        itemScrollController.jumpTo(index: 0);
                      });
                    },
                  );
                });

                // notify the categoires to update the news count
                setState(() {
                  listUpdated = true;
                });
                appState.refreshView();
                // if the current view is all news change to only unread news
              } else {
                // switch the state to show only unread news
                appState.newsStatus = FluxNewsState.unreadNewsStatus;

                // save the state persistant
                appState.storage.write(
                    key: FluxNewsState.secureStorageNewsStatusKey,
                    value: FluxNewsState.unreadNewsStatus);

                // refresh news list with the only unread news state
                appState.newsList = queryNewsFromDB(appState, appState.feedIDs)
                    .whenComplete(() {
                  waitUntilNewsListBuild().whenComplete(
                    () {
                      setState(() {
                        itemScrollController.jumpTo(index: 0);
                      });
                    },
                  );
                });

                // notify the categoires to update the news count
                setState(() {
                  listUpdated = true;
                });
                appState.refreshView();
              }
            } else if (value == 2) {
              // switch between newest first and oldest first
              // if the current sort order is newest first change to oldest first
              if (appState.sortOrder ==
                  FluxNewsState.sortOrderNewestFirstString) {
                // switch the state to all news
                appState.sortOrder = FluxNewsState.sortOrderOldestFirstString;

                // save the state persistant
                appState.storage.write(
                    key: FluxNewsState.secureStorageSortOrderKey,
                    value: FluxNewsState.sortOrderOldestFirstString);

                // refresh news list with the all news state
                appState.newsList = queryNewsFromDB(appState, appState.feedIDs)
                    .whenComplete(() {
                  waitUntilNewsListBuild().whenComplete(
                    () {
                      setState(() {
                        itemScrollController.jumpTo(index: 0);
                      });
                    },
                  );
                });

                // notify the categoires to update the news count
                setState(() {
                  listUpdated = true;
                });
                appState.refreshView();
                // if the current sort order is oldest first change to newest first
              } else {
                // switch the state to show only unread news
                appState.sortOrder = FluxNewsState.sortOrderNewestFirstString;

                // save the state persistant
                appState.storage.write(
                    key: FluxNewsState.secureStorageSortOrderKey,
                    value: FluxNewsState.sortOrderNewestFirstString);

                // refresh news list with the only unread news state
                appState.newsList = queryNewsFromDB(appState, appState.feedIDs)
                    .whenComplete(() {
                  waitUntilNewsListBuild().whenComplete(
                    () {
                      setState(() {
                        itemScrollController.jumpTo(index: 0);
                      });
                    },
                  );
                });

                // notify the categoires to update the news count
                setState(() {
                  listUpdated = true;
                });
                appState.refreshView();
              }
            } else if (value == 3) {
              // navigate to the settings page
              Navigator.pushNamed(context, FluxNewsState.settingsRouteString);
            }
          }),
    ];
  }

  Future<void> syncNews(FluxNewsState appState, BuildContext context) async {
    FlutterLogs.logThis(
        tag: FluxNewsState.logTag,
        subTag: 'syncNews',
        logMessage: 'Start syncing with miniflux server.',
        level: LogLevel.INFO);
    // this is the part where the app syncs with the miniflux server
    // to reduce the appearence of error pop ups,
    // the error handling in all steps is to only through new errors,
    // if the new error is not already thrown by a previous step.
    setState(() {
      // set the state to sync
      // (needed for the processing cycle and the positioning of the list view)
      syncProcess = true;
    });
    // also resetting the error string for new errors occuring within this sync
    appState.errorString = '';

    // check the miniflux credentials to enable the sync
    bool authCheck = await checkMinifluxCredentials(http.Client(),
            appState.minifluxURL, appState.minifluxAPIKey, appState)
        .onError((error, stackTrace) {
      FlutterLogs.logThis(
          tag: FluxNewsState.logTag,
          subTag: 'authCheck',
          logMessage: 'Caught an error in authCheck function!',
          errorMessage: error.toString(),
          level: LogLevel.ERROR);
      if (appState.errorString !=
          AppLocalizations.of(context)!.communicateionMinifluxError) {
        appState.errorString =
            AppLocalizations.of(context)!.communicateionMinifluxError;
        appState.newError = true;
        appState.refreshView();
      }
      return false;
    });

    // if there is no new error (network error), set the errorOnMicrofluxAuth flag
    if (!appState.newError) {
      appState.errorOnMicrofluxAuth = !authCheck;
    }

    // check if there are no authentication errors before start syncing
    if (!appState.errorOnMicrofluxAuth && appState.errorString == '') {
      // at first toggle news as read so that this news don't show up in the next step
      await toggleNewsAsRead(http.Client(), appState)
          .onError((error, stackTrace) {
        FlutterLogs.logThis(
            tag: FluxNewsState.logTag,
            subTag: 'toggleNewsAsRead',
            logMessage: 'Caught an error in toggleNewsAsRead function!',
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

      // fetch only unread news from the miniflux server
      NewsList newNews =
          await fetchNews(http.Client(), appState).onError((error, stackTrace) {
        FlutterLogs.logThis(
            tag: FluxNewsState.logTag,
            subTag: 'fetchNews',
            logMessage: 'Caught an error in fetchNews function!',
            errorMessage: error.toString(),
            level: LogLevel.ERROR);
        if (appState.errorString !=
            AppLocalizations.of(context)!.communicateionMinifluxError) {
          appState.errorString =
              AppLocalizations.of(context)!.communicateionMinifluxError;
          appState.newError = true;
          appState.refreshView();
        }
        return NewsList(news: [], newsCount: 0);
      });

      // if news in this app are marked as unread, but don't exist in the list from
      // the previous step, this news must be marked as read by another app.
      // So this step mark news, which are not fetched privious as read in this app.
      await markNotFetchedNewsAsRead(newNews, appState)
          .onError((error, stackTrace) {
        FlutterLogs.logThis(
            tag: FluxNewsState.logTag,
            subTag: 'markNotFetchedNewsAsRead',
            logMessage: 'Caught an error in markNotFetchedNewsAsRead function!',
            errorMessage: error.toString(),
            level: LogLevel.ERROR);
        if (appState.errorString !=
            AppLocalizations.of(context)!.databaseError) {
          appState.errorString = AppLocalizations.of(context)!.databaseError;
          appState.newError = true;
          appState.refreshView();
        }
        return 0;
      });

      // insert or update the fetched news in the database
      await insertNewsInDB(newNews, appState).onError((error, stackTrace) {
        FlutterLogs.logThis(
            tag: FluxNewsState.logTag,
            subTag: 'insertNewsInDB',
            logMessage: 'Caught an error in insertNewsInDB function!',
            errorMessage: error.toString(),
            level: LogLevel.ERROR);
        if (appState.errorString !=
            AppLocalizations.of(context)!.databaseError) {
          appState.errorString = AppLocalizations.of(context)!.databaseError;
          appState.newError = true;
          appState.refreshView();
        }
        return 0;
      });

      // after inserting the news, renew the list view with the new news
      setState(() {
        scrollPosition = 0;
      });
      appState.storage.write(
          key: FluxNewsState.secureStorageSavedScrollPositionKey, value: '0');
      appState.newsList =
          queryNewsFromDB(appState, appState.feedIDs).whenComplete(() {
        waitUntilNewsListBuild().whenComplete(
          () {
            // set the view position to the top of the new list
            setState(() {
              itemScrollController.jumpTo(index: 0);
            });
          },
        );
      });

      // renew the news count of "All News"
      if (context.mounted) {
        await renewAllNewsCount(appState, context).onError(
            (error, stackTrace) => FlutterLogs.logThis(
                tag: FluxNewsState.logTag,
                subTag: 'renewAllNewsCount',
                logMessage: 'Caught an error in renewAllNewsCount function!',
                errorMessage: error.toString(),
                level: LogLevel.ERROR));
      }

      // remove the native spalsh after updating the list view
      FlutterNativeSplash.remove();

      // fetch the categories from the miniflux server
      Categories newCategories =
          await fetchCategorieInformation(http.Client(), appState)
              .onError((error, stackTrace) {
        FlutterLogs.logThis(
            tag: FluxNewsState.logTag,
            subTag: 'fetchCategorieInformation',
            logMessage:
                'Caught an error in fetchCategorieInformation function!',
            errorMessage: error.toString(),
            level: LogLevel.ERROR);
        if (appState.errorString !=
            AppLocalizations.of(context)!.communicateionMinifluxError) {
          appState.errorString =
              AppLocalizations.of(context)!.communicateionMinifluxError;
          appState.newError = true;
          appState.refreshView();
        }
        return Future<Categories>.value(Categories(categories: []));
      });

      // insert or update the fetched cateegories in the database
      await insertCategoriesInDB(newCategories, appState)
          .onError((error, stackTrace) {
        FlutterLogs.logThis(
            tag: FluxNewsState.logTag,
            subTag: 'insertCategoriesInDB',
            logMessage: 'Caught an error in insertCategoriesInDB function!',
            errorMessage: error.toString(),
            level: LogLevel.ERROR);
        if (appState.errorString !=
            AppLocalizations.of(context)!.databaseError) {
          appState.errorString = AppLocalizations.of(context)!.databaseError;
          appState.newError = true;
          appState.refreshView();
        }
        return 0;
      });

      // fetch the starred news (read or unread) from the miniflux server
      NewsList starredNews = await fetchStarredNews(http.Client(), appState)
          .onError((error, stackTrace) {
        FlutterLogs.logThis(
            tag: FluxNewsState.logTag,
            subTag: 'fetchStarredNews',
            logMessage: 'Caught an error in fetchStarredNews function!',
            errorMessage: error.toString(),
            level: LogLevel.ERROR);
        if (appState.errorString !=
            AppLocalizations.of(context)!.communicateionMinifluxError) {
          appState.errorString =
              AppLocalizations.of(context)!.communicateionMinifluxError;
          appState.newError = true;
          appState.refreshView();
        }
        return NewsList(news: [], newsCount: 0);
      });

      // update the previous fetched starred news in the database
      // maybe some other app has marked a news a starred
      await updateStarredNewsInDB(starredNews, appState)
          .onError((error, stackTrace) {
        FlutterLogs.logThis(
            tag: FluxNewsState.logTag,
            subTag: 'updateStarredNewsInDB',
            logMessage: 'Caught an error in updateStarredNewsInDB function!',
            errorMessage: error.toString(),
            level: LogLevel.ERROR);
        if (appState.errorString !=
            AppLocalizations.of(context)!.databaseError) {
          appState.errorString = AppLocalizations.of(context)!.databaseError;
          appState.newError = true;
          appState.refreshView();
        }
        return 0;
      });

      // delete all unstarred news depending the defined limit in the settings,
      await cleanUnstarredNews(appState).onError((error, stackTrace) {
        FlutterLogs.logThis(
            tag: FluxNewsState.logTag,
            subTag: 'cleanUnstarredNews',
            logMessage: 'Caught an error in cleanUnstarredNews function!',
            errorMessage: error.toString(),
            level: LogLevel.ERROR);
        if (appState.errorString !=
            AppLocalizations.of(context)!.databaseError) {
          appState.errorString = AppLocalizations.of(context)!.databaseError;
          appState.newError = true;
          appState.refreshView();
        }
      });

      // delete all starred news depending the defines limit in the settings
      await cleanStarredNews(appState).onError((error, stackTrace) {
        FlutterLogs.logThis(
            tag: FluxNewsState.logTag,
            subTag: 'cleanStarredNews',
            logMessage: 'Caught an error in cleanStarredNews function!',
            errorMessage: error.toString(),
            level: LogLevel.ERROR);
        if (appState.errorString !=
            AppLocalizations.of(context)!.databaseError) {
          appState.errorString = AppLocalizations.of(context)!.databaseError;
          appState.newError = true;
          appState.refreshView();
        }
      });

      // update the starred (bookmarked) counter of news
      try {
        if (context.mounted) {
          updateStarredCounter(appState, context);
        }
      } catch (e) {
        FlutterLogs.logThis(
            tag: FluxNewsState.logTag,
            subTag: 'updateStarredCounter',
            logMessage: 'Caught an error in updateStarredCounter function!',
            errorMessage: e.toString(),
            level: LogLevel.ERROR);
        if (context.mounted) {
          if (appState.errorString !=
              AppLocalizations.of(context)!.databaseError) {
            appState.errorString = AppLocalizations.of(context)!.databaseError;
            appState.newError = true;
            appState.refreshView();
          }
        }
      }

      // fetch the updated categories from the db and genereate the categorie view
      if (context.mounted) {
        appState.categorieList = queryCategoriesFromDB(appState, context);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (newNews.newsCount > 0 && appState.feedIDs == null) {
          // if new news exists and the "All News" categorie is selected,
          // set the list view position to the top
          itemScrollController.jumpTo(index: 0);
        } else if (starredNews.newsCount > 0 && appState.feedIDs != null) {
          if (appState.feedIDs?.first == -1) {
            // if new news exists and the "Bookmarked" categorie is selected,
            // set the list view position to the top
            itemScrollController.jumpTo(index: 0);
          }
        }
      });
      // end the sync process
      setState(() {
        syncProcess = false;
      });
    } else {
      // end the sync process
      setState(() {
        syncProcess = false;
      });
      // remove the native spalsh after updating the list view
      FlutterNativeSplash.remove();
    }
    FlutterLogs.logThis(
        tag: FluxNewsState.logTag,
        subTag: 'syncNews',
        logMessage: 'Finished syncing with miniflux server.',
        level: LogLevel.INFO);
  }

  // the list view widget with news (main view)
  Widget newsListWidget(BuildContext context, FluxNewsState appState) {
    var getData = FutureBuilder<List<News>>(
      future: appState.newsList,
      builder: (context, snapshot) {
        switch (snapshot.connectionState) {
          case ConnectionState.none:
          case ConnectionState.waiting:
          default:
            if (snapshot.hasError) {
              return const SizedBox.shrink();
            } else {
              return snapshot.data == null
                  // show empty dialog if list is null
                  ? Center(
                      child: Text(
                      AppLocalizations.of(context)!.noNewEntries,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ))
                  // show empty dialog if list is empty
                  : snapshot.data!.isEmpty
                      ? Center(
                          child: Text(
                          AppLocalizations.of(context)!.noNewEntries,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ))
                      // otherwise create list view with ScrollablePositionedList
                      // to save scroll position persistant
                      : Stack(children: [
                          NotificationListener<ScrollEndNotification>(
                            child: ScrollablePositionedList.builder(
                                key: const PageStorageKey<String>('NewsList'),
                                itemCount: snapshot.data!.length,
                                itemScrollController: itemScrollController,
                                itemPositionsListener: itemPositionsListener,
                                initialScrollIndex: scrollPosition,
                                itemBuilder: (context, i) {
                                  return appState.orientation ==
                                          Orientation.landscape
                                      ? appState.isTablet
                                          ? showNewsRow(snapshot.data![i],
                                              appState, context)
                                          : showNewsCard(snapshot.data![i],
                                              appState, context)
                                      : showNewsCard(
                                          snapshot.data![i], appState, context);
                                }),
                            // on ScrollNotification set news as read on scrollover if activated
                            onNotification: (ScrollNotification scrollInfo) {
                              final metrics = scrollInfo.metrics;
                              // check if set read on scrollover is activated in settings
                              if (appState.markAsReadOnScrollOver) {
                                // if the sync is in progress, no news should marked as read
                                if (syncProcess == false) {
                                  // set all news as read if the list reached the bottom (the edge)
                                  if (metrics.atEdge) {
                                    // to ensure that the list is at the bottom edge and not at the top edge
                                    // the amount of scrolled pixels must be greater 0
                                    if (metrics.pixels > 0) {
                                      // iterade through the whole news list and mark news as read
                                      for (int i = 0;
                                          i < snapshot.data!.length;
                                          i++) {
                                        try {
                                          updateNewsStatusInDB(
                                              snapshot.data![i].newsID,
                                              FluxNewsState.readNewsStatus,
                                              appState);
                                        } catch (e) {
                                          FlutterLogs.logThis(
                                              tag: FluxNewsState.logTag,
                                              subTag: 'updateNewsStatusInDB',
                                              logMessage:
                                                  'Caught an error in updateNewsStatusInDB function!',
                                              errorMessage: e.toString(),
                                              level: LogLevel.ERROR);
                                          if (appState.errorString !=
                                              AppLocalizations.of(context)!
                                                  .databaseError) {
                                            appState.errorString =
                                                AppLocalizations.of(context)!
                                                    .databaseError;
                                            appState.newError = true;
                                            appState.refreshView();
                                          }
                                        }
                                        setState(() {
                                          snapshot.data![i].status =
                                              FluxNewsState.readNewsStatus;
                                        });
                                      }
                                      // set the scroll position back to the top of the list
                                      setState(() {
                                        scrollPosition = 0;
                                      });
                                    }
                                  } else {
                                    // if the list doesn't reached the bottom,
                                    // mark the news which got scrolled over as read.
                                    // Iterate through the news list from start
                                    // to the actual position and mark them as read
                                    for (int i = 0; i < scrollPosition; i++) {
                                      try {
                                        updateNewsStatusInDB(
                                            snapshot.data![i].newsID,
                                            FluxNewsState.readNewsStatus,
                                            appState);
                                      } catch (e) {
                                        FlutterLogs.logThis(
                                            tag: FluxNewsState.logTag,
                                            subTag: 'updateNewsStatusInDB',
                                            logMessage:
                                                'Caught an error in updateNewsStatusInDB function!',
                                            errorMessage: e.toString(),
                                            level: LogLevel.ERROR);
                                        if (appState.errorString !=
                                            AppLocalizations.of(context)!
                                                .databaseError) {
                                          appState.errorString =
                                              AppLocalizations.of(context)!
                                                  .databaseError;
                                          appState.newError = true;
                                          appState.refreshView();
                                        }
                                      }
                                      setState(() {
                                        snapshot.data![i].status =
                                            FluxNewsState.readNewsStatus;
                                      });
                                    }
                                  }
                                }
                                // mark the list as updated to recalculate the news count
                                setState(() {
                                  listUpdated = true;
                                });
                              }
                              // return always false to ensure the processing of the notification
                              return false;
                            },
                          ),
                          // get the actual scroll position on stop scrolling
                          positionsView,
                        ]);
            }
        }
      },
    );
    return getData;
  }

  // this function is needed because after the news are fetched from the database,
  // the list of news need some time to be generated.
  // only after the list is generated, we can set the scroll position of the list
  // we can check that the list is generated if the scroll controller is attached to the list.
  // so the function checks the scroll controller and if it's not attached it waits 1 millisecond
  // and check then again if the scrol controller is attached.
  // With callaing this function as await, we can wait with the further processing
  // on finishing with the list build.
  Future<void> waitUntilNewsListBuild() async {
    final completer = Completer();
    if (!itemScrollController.isAttached) {
      await Future.delayed(const Duration(milliseconds: 1));
      return waitUntilNewsListBuild();
    } else {
      completer.complete();
    }
    return completer.future;
  }

  // here we define the appearance of the news cards
  Widget showNewsCard(News news, FluxNewsState appState, BuildContext context) {
    return Card(
      // inkwell is used for the onTab and onLongPress functions
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        onTap: () async {
          // on tab we update the status of the news to read and open the news
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
          // update the status to read on the news list and notify the categories
          // to recalculate the news count
          setState(() {
            news.status = FluxNewsState.readNewsStatus;
            listUpdated = true;
          });

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
                    height: appState.isTablet ? 250 : 175,
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
                subtitle: Padding(
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
                              child: news.getFeedIcon(16.0, context, appState))
                          : const SizedBox.shrink(),
                      Padding(
                        padding: const EdgeInsets.only(left: 0.0),
                        child: Opacity(
                          opacity: news.status == FluxNewsState.unreadNewsStatus
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
                          opacity: news.status == FluxNewsState.unreadNewsStatus
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
                          opacity: news.status == FluxNewsState.unreadNewsStatus
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
                )),
            // here is the news text, the Opacity decide between read and unread
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
              child: Opacity(
                opacity:
                    news.status == FluxNewsState.unreadNewsStatus ? 1.0 : 0.6,
                child: Text(
                  news.getText(),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // here we define the appearance of the news cards
  Widget showNewsRow(News news, FluxNewsState appState, BuildContext context) {
    return Card(
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        onTap: () async {
          // on tab we update the status of the news to read and open the news
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
          // update the status to read on the news list and notify the categories
          // to recalculate the news count
          setState(() {
            news.status = FluxNewsState.readNewsStatus;
            listUpdated = true;
          });

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
          children: [
            news.getImageURL() != FluxNewsState.noImageUrlString
                ? Expanded(
                    flex: 4,
                    child: SizedBox(
                      // in the row view we have a fixed size of the image
                      height: 250,
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
            Expanded(
              flex: 5,
              child: ListTile(
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
                      padding: const EdgeInsets.fromLTRB(0, 2, 16, 16),
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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // here is a helper function to get the first visible widget in the list view
  // this widget is used as the limit on marking prevoius news as read.
  // so every item of the list, which is prevoius to the first visible
  // will be marked as read.
  Widget get positionsView => ValueListenableBuilder<Iterable<ItemPosition>>(
        valueListenable: itemPositionsListener.itemPositions,
        builder: (context, positions, child) {
          FluxNewsState appState = context.watch<FluxNewsState>();
          int? firstItem;
          if (positions.isNotEmpty) {
            firstItem = positions
                .where((ItemPosition position) => position.itemTrailingEdge > 0)
                .reduce((ItemPosition first, ItemPosition position) =>
                    position.itemTrailingEdge < first.itemTrailingEdge
                        ? position
                        : first)
                .index;
          }
          if (firstItem == null) {
            scrollPosition = 0;
            appState.storage.write(
                key: FluxNewsState.secureStorageSavedScrollPositionKey,
                value: '0');
          } else {
            scrollPosition = firstItem;
            appState.storage.write(
                key: FluxNewsState.secureStorageSavedScrollPositionKey,
                value: firstItem.toString());
          }

          return const SizedBox.shrink();
        },
      );

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

        // if we are in the bookmarked categorie, reload the list of bookmarked news
        // after the prevoius change, because there happened changes to this list.
        if (context.mounted) {
          if (appState.appBarText == AppLocalizations.of(context)!.bookmarked) {
            appState.feedIDs = [-1];
            appState.newsList =
                queryNewsFromDB(appState, appState.feedIDs).whenComplete(() {
              waitUntilNewsListBuild().whenComplete(
                () {
                  setState(() {
                    itemScrollController.jumpTo(index: 0);
                  });
                },
              );
            });
            appState.refreshView();
          } else {
            appState.refreshView();
          }
        }
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
          listUpdated = true;
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
          listUpdated = true;
        });
        break;
    }
  }

  // this is the categorie list widget, it is shown in the drawer
  // or on the left side in landscape or tablet mode.
  Widget categorieListWidget(BuildContext context, FluxNewsState appState) {
    var getData = FutureBuilder<Categories>(
        future: appState.categorieList,
        builder: (context, snapshot) {
          if (listUpdated) {
            snapshot.data?.renewNewsCount(appState);
            renewAllNewsCount(appState, context);
          }
          switch (snapshot.connectionState) {
            case ConnectionState.none:
            case ConnectionState.waiting:
              // we add a static categorie of "All News" to the list of categories
              // while wating on the news list from the miniflux server
              return ListTile(
                leading: const Icon(
                  Icons.home,
                ),
                title: Text(
                  AppLocalizations.of(context)!.allNews,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              );
            default:
              if (snapshot.hasError) {
                return const SizedBox.shrink();
              } else {
                return snapshot.data != null
                    ? snapshot.data!.categories.isEmpty
                        ? const SizedBox.shrink()
                        // if the categorie list from the miniflux server is not null
                        // and not empty, we show the categorie list
                        : Column(children: [
                            // we add a static categorie of "All News" to the list of categories
                            ListTile(
                              leading: const Icon(
                                Icons.home,
                              ),
                              title: Text(
                                AppLocalizations.of(context)!.allNews,
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              trailing: Text(
                                '${appState.allNewsCount}',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              onTap: () {
                                allNewsOnClick(appState);
                              },
                            ),
                            // we iterate over the categorie list
                            for (Categorie categorie
                                in snapshot.data!.categories)
                              showCategorie(
                                  categorie, appState, snapshot.data!),
                            // we add a static categorie of "Bookmarked" to the list of categories
                            ListTile(
                              leading: const Icon(
                                Icons.star,
                              ),
                              title: Text(
                                AppLocalizations.of(context)!.bookmarked,
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              trailing: Text(
                                '${appState.starredCount}',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              onTap: () {
                                bookmarkedOnClick(appState);
                              },
                            ),
                          ])
                    : const SizedBox.shrink();
              }
          }
        });
    return getData;
  }

  // here we style the categorie ExpansionTile
  // we use a ExpansionTile because we want to show the according feeds
  // of this categorie in the expanded state.
  Widget showCategorie(
      Categorie categorie, FluxNewsState appState, Categories categories) {
    return ExpansionTile(
      // we want the expansion arrow at the beginning,
      // because we want to show the news count at the end of this row.
      controlAffinity: ListTileControlAffinity.leading,
      // make the title clickable to select this categorie as the news view
      title: InkWell(
        child: Text(
          categorie.title,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        onTap: () {
          categorieOnClick(categorie, appState, categories);
        },
      ),
      // show the news count of this categorie
      trailing: InkWell(
        child: Text(
          '${categorie.newsCount}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        onTap: () {
          categorieOnClick(categorie, appState, categories);
        },
      ),
      // iterate over the according feeds of the categorie
      children: [
        for (Feed feed in categorie.feeds) showFeed(feed, appState, categories)
      ],
    );
  }

  // if the title of the categorie is clicked,
  // we want all the news of this categorie in the news view.
  Future<void> categorieOnClick(Categorie categorie, FluxNewsState appState,
      Categories categories) async {
    // add the according feeds of this categorie as a filter
    appState.feedIDs = categorie.getFeedIDs();
    // reload the news list with the new filter
    appState.newsList =
        queryNewsFromDB(appState, appState.feedIDs).whenComplete(() {
      waitUntilNewsListBuild().whenComplete(
        () {
          setState(() {
            itemScrollController.jumpTo(index: 0);
          });
        },
      );
    });
    // set the categorie title as app bar title
    // and update the newscount in the app bar, if the function is activated.
    appState.appBarText = categorie.title;
    categories.renewNewsCount(appState);
    // update the view after changing the values
    appState.refreshView();
  }

  // if the "All News" ListTile is clicked,
  // we want all the news in the news view.
  Future<void> allNewsOnClick(FluxNewsState appState) async {
    // empty the feedIds which are used as a filter if a specific categorie is selected
    appState.feedIDs = null;
    // reload the news list with the new filter (empty)
    appState.newsList =
        queryNewsFromDB(appState, appState.feedIDs).whenComplete(() {
      waitUntilNewsListBuild().whenComplete(
        () {
          setState(() {
            itemScrollController.jumpTo(index: 0);
          });
        },
      );
    });
    // set the "All News" title as app bar title
    // and update the newscount in the app bar, if the function is activated.
    appState.appBarText = AppLocalizations.of(context)!.allNews;
    if (context.mounted) {
      renewAllNewsCount(appState, context);
    }
    // update the view after changing the values
    appState.refreshView();
  }

  // if the "Bokkmarked" ListTile is clicked,
  // we want all the bokkmakred news in the news view.
  Future<void> bookmarkedOnClick(FluxNewsState appState) async {
    // set the feedIDs filter to -1 to only load bookmarked news
    // -1 is a impossible feed id of a regular miniflux feed,
    // so we use it to decide between all news (feedIds = null)
    // and bookmarked news (feedIds = -1).
    appState.feedIDs = [-1];
    // reload the news list with the new filter (-1 only bookmarked news)
    appState.newsList =
        queryNewsFromDB(appState, appState.feedIDs).whenComplete(() {
      waitUntilNewsListBuild().whenComplete(
        () {
          setState(() {
            itemScrollController.jumpTo(index: 0);
          });
        },
      );
    });
    // set the "Bookmarked" title as app bar title
    // and update the newscount in the app bar, if the function is activated.
    appState.appBarText = AppLocalizations.of(context)!.bookmarked;
    if (context.mounted) {
      updateStarredCounter(appState, context);
    }
    // update the view after changing the values
    appState.refreshView();
  }

  // here we style the ListTile of the feeds which are subordinate to the categories
  Widget showFeed(Feed feed, FluxNewsState appState, Categories categories) {
    return ListTile(
      title: Padding(
        padding: const EdgeInsets.only(left: 8.0),
        child: Row(children: [
          // if the option is enabled, show the feed icon
          appState.showFeedIcons
              ? feed.getFeedIcon(16.0, context, appState)
              : const SizedBox.shrink(),
          Padding(
            padding: const EdgeInsets.only(left: 10.0),
            child: Text(
              feed.title,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          )
        ]),
      ),
      // show the news count of this feed
      trailing: Text(
        '${feed.newsCount}',
        style: Theme.of(context).textTheme.labelLarge,
      ),
      onTap: () {
        // on tab we want to show only the news of this feed in the news list.
        // set the feed id of the selected feed in the feedIDs filter
        appState.feedIDs = [feed.feedID];
        // reload the news list with the new filter
        appState.newsList =
            queryNewsFromDB(appState, appState.feedIDs).whenComplete(() {
          waitUntilNewsListBuild().whenComplete(
            () {
              setState(() {
                itemScrollController.jumpTo(index: 0);
              });
            },
          );
        });
        // set the feed title as app bar title
        // and update the newscount in the app bar, if the function is activated.
        appState.appBarText = feed.title;
        categories.renewNewsCount(appState);
        // update the view after changing the values
        appState.refreshView();
      },
    );
  }

  // this widget replace the news list view, if the miniflux server settings
  // are not set or not correct.
  Widget noSettingsWidget(BuildContext context, FluxNewsState appState) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            AppLocalizations.of(context)!.settingsNotSet,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 40, top: 20.0, right: 30),
            child: Text(
              AppLocalizations.of(context)!.provideMinifluxCredentials,
              style: const TextStyle(
                  color: Colors.red, fontSize: 20, fontWeight: FontWeight.bold),
            ),
          )
        ],
      ),
    );
  }

  // this widget replace the normal news list widget, if a error occurs
  // it will pop up an error dialog and then show the normal news list in the background.
  Widget errorWidget(BuildContext context, FluxNewsState appState) {
    Timer.run(() {
      showErrorDialog(context, appState).then((value) {
        appState.newError = false;
        appState.refreshView();
      });
    });
    return newsListWidget(context, appState);
  }

  // this is the error dialog which is shown, if a error occours.
  // to prevent the multi pop up (f.e. if the internet connection ist lost
  // not every function which require the connection should raise a pop up)
  // we check if the error which is shown is a new error.
  Future showErrorDialog(BuildContext context, FluxNewsState appState) async {
    if (appState.newError) {
      AlertDialog alertDialog = AlertDialog(
        title: Text(AppLocalizations.of(context)!.error),
        content: Text(appState.errorString),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: Text(AppLocalizations.of(context)!.ok),
          ),
        ],
      );
      showDialog(
          context: context,
          builder: (BuildContext context) {
            return alertDialog;
          });
    }
  }

  @override
  bool get wantKeepAlive => true;
}
