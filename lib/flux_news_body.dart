import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flux_news/news_list.dart';
import 'package:flux_news/sync_news.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gen/gen_l10n/flux_news_localizations.dart';

import 'database_backend.dart';
import 'flux_news_state.dart';
import 'news_model.dart';

class FluxNewsBody extends StatelessWidget with WidgetsBindingObserver {
  const FluxNewsBody({super.key});

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();

    if (MediaQuery.of(context).size.shortestSide >= 550) {
      appState.isTablet = true;
    } else {
      appState.isTablet = false;
    }

    return FluxNewsBodyStatefulWrapper(onInit: () {
      FluxNewsState appState = context.read<FluxNewsState>();
      initConfig(context);
      appState.categorieList = queryCategoriesFromDB(appState, context);
      appState.newsList = Future<List<News>>.value([]);
      WidgetsBinding.instance.addObserver(this);
    }, child: OrientationBuilder(
      builder: (context, orientation) {
        appState.orientation = orientation;

        if (appState.isTablet) {
          return tabletLayout(appState, context);
        } else {
          return smartphoneLayout(appState, context);
        }
      },
    ));
  }

  // helper function for the initState() to use async function on init
  Future<void> initConfig(BuildContext context) async {
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
          if (Platform.isAndroid || Platform.isIOS) {
            FlutterLogs.logThis(
                tag: FluxNewsState.logTag,
                subTag: 'initConfig',
                logMessage: 'Caught an error in initConfig function!',
                errorMessage: e.toString(),
                level: LogLevel.ERROR);
          }
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
        appState.scrollPosition = appState.savedScrollPosition;
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

  Scaffold smartphoneLayout(FluxNewsState appState, BuildContext context) {
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
        title: appBarTitle(appState, context),
        actions: appBarButtons(appState, context),
      ),
      drawer: getDrawer(context, appState),
      body: Container(
        child: getBody(context, appState),
      ),
    );
  }

  Scaffold tabletLayout(FluxNewsState appState, BuildContext context) {
    // start the main view in landscape mode, replace the drawer with a fixed list view on the left side
    return Scaffold(
      appBar: AppBar(
        title: appBarTitle(appState, context),
        actions: appBarButtons(appState, context),
      ),
      body: Row(
        children: [
          Expanded(
            flex: 4,
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
      if (appState.orientation == Orientation.landscape) {
        return landscapeNewsListWidget(context, appState);
      } else {
        return portraitNewsListWidget(context, appState);
      }
    }
  }

  Drawer getDrawer(BuildContext context, FluxNewsState appState) {
    // update the categories, feeds and news counter, if there were updates to the list view
    if (appState.listUpdated) {
      appState.categorieList = queryCategoriesFromDB(appState, context);
      appState.listUpdated = false;
    }
    // return the drawer
    return Drawer(
        child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
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
            )));
  }

  Widget appBarTitle(FluxNewsState appState, BuildContext context) {
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
        icon: appState.syncProcess
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
                  waitUntilNewsListBuild(appState).whenComplete(
                    () {
                      appState.itemScrollController.jumpTo(index: 0);
                    },
                  );
                });

                // notify the categoires to update the news count
                appState.listUpdated = true;
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
                  waitUntilNewsListBuild(appState).whenComplete(
                    () {
                      appState.itemScrollController.jumpTo(index: 0);
                    },
                  );
                });

                // notify the categoires to update the news count
                appState.listUpdated = true;
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
                  waitUntilNewsListBuild(appState).whenComplete(
                    () {
                      appState.itemScrollController.jumpTo(index: 0);
                    },
                  );
                });

                // notify the categoires to update the news count
                appState.listUpdated = true;
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
                  waitUntilNewsListBuild(appState).whenComplete(
                    () {
                      appState.itemScrollController.jumpTo(index: 0);
                    },
                  );
                });

                // notify the categoires to update the news count
                appState.listUpdated = true;
                appState.refreshView();
              }
            } else if (value == 3) {
              // navigate to the settings page
              Navigator.pushNamed(context, FluxNewsState.settingsRouteString);
            }
          }),
    ];
  }

  // this is the categorie list widget, it is shown in the drawer
  // or on the left side in landscape or tablet mode.
  Widget categorieListWidget(BuildContext context, FluxNewsState appState) {
    var getData = FutureBuilder<Categories>(
        future: appState.categorieList,
        builder: (context, snapshot) {
          if (appState.listUpdated) {
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
                                allNewsOnClick(appState, context);
                              },
                            ),
                            // we iterate over the categorie list
                            for (Categorie categorie
                                in snapshot.data!.categories)
                              showCategorie(
                                  categorie, appState, snapshot.data!, context),
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
                                bookmarkedOnClick(appState, context);
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
  Widget showCategorie(Categorie categorie, FluxNewsState appState,
      Categories categories, BuildContext context) {
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
          categorieOnClick(categorie, appState, categories, context);
        },
      ),
      // show the news count of this categorie
      trailing: InkWell(
        child: Text(
          '${categorie.newsCount}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        onTap: () {
          categorieOnClick(categorie, appState, categories, context);
        },
      ),
      // iterate over the according feeds of the categorie
      children: [
        for (Feed feed in categorie.feeds)
          showFeed(feed, appState, categories, context)
      ],
    );
  }

  // if the title of the categorie is clicked,
  // we want all the news of this categorie in the news view.
  Future<void> categorieOnClick(Categorie categorie, FluxNewsState appState,
      Categories categories, BuildContext context) async {
    // add the according feeds of this categorie as a filter
    appState.feedIDs = categorie.getFeedIDs();
    // reload the news list with the new filter
    appState.newsList =
        queryNewsFromDB(appState, appState.feedIDs).whenComplete(() {
      waitUntilNewsListBuild(appState).whenComplete(
        () {
          appState.itemScrollController.jumpTo(index: 0);
        },
      );
    });
    // set the categorie title as app bar title
    // and update the newscount in the app bar, if the function is activated.
    appState.appBarText = categorie.title;
    categories.renewNewsCount(appState);
    // update the view after changing the values
    appState.refreshView();

    // if the device is a smartphone, close the drawer after selecting a category or feed
    // if the device is a tablet, no drawer is used.
    if (!appState.isTablet) {
      Navigator.pop(context);
    }
  }

  // if the "All News" ListTile is clicked,
  // we want all the news in the news view.
  Future<void> allNewsOnClick(
      FluxNewsState appState, BuildContext context) async {
    // empty the feedIds which are used as a filter if a specific categorie is selected
    appState.feedIDs = null;
    // reload the news list with the new filter (empty)
    appState.newsList =
        queryNewsFromDB(appState, appState.feedIDs).whenComplete(() {
      waitUntilNewsListBuild(appState).whenComplete(
        () {
          appState.itemScrollController.jumpTo(index: 0);
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

    // if the device is a smartphone, close the drawer after selecting a category or feed
    // if the device is a tablet, no drawer is used.
    if (!appState.isTablet) {
      Navigator.pop(context);
    }
  }

  // if the "Bokkmarked" ListTile is clicked,
  // we want all the bokkmakred news in the news view.
  Future<void> bookmarkedOnClick(
      FluxNewsState appState, BuildContext context) async {
    // set the feedIDs filter to -1 to only load bookmarked news
    // -1 is a impossible feed id of a regular miniflux feed,
    // so we use it to decide between all news (feedIds = null)
    // and bookmarked news (feedIds = -1).
    appState.feedIDs = [-1];
    // reload the news list with the new filter (-1 only bookmarked news)
    appState.newsList =
        queryNewsFromDB(appState, appState.feedIDs).whenComplete(() {
      waitUntilNewsListBuild(appState).whenComplete(
        () {
          appState.itemScrollController.jumpTo(index: 0);
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

    // if the device is a smartphone, close the drawer after selecting a category or feed
    // if the device is a tablet, no drawer is used.
    if (!appState.isTablet) {
      Navigator.pop(context);
    }
  }

  // here we style the ListTile of the feeds which are subordinate to the categories
  Widget showFeed(Feed feed, FluxNewsState appState, Categories categories,
      BuildContext context) {
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
          waitUntilNewsListBuild(appState).whenComplete(
            () {
              appState.itemScrollController.jumpTo(index: 0);
            },
          );
        });
        // set the feed title as app bar title
        // and update the newscount in the app bar, if the function is activated.
        appState.appBarText = feed.title;
        categories.renewNewsCount(appState);
        // update the view after changing the values
        appState.refreshView();

        // if the device is a smartphone, close the drawer after selecting a category or feed
        // if the device is a tablet, no drawer is used.
        if (!appState.isTablet) {
          Navigator.pop(context);
        }
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
    if (appState.orientation == Orientation.landscape) {
      return landscapeNewsListWidget(context, appState);
    } else {
      return portraitNewsListWidget(context, appState);
    }
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
}

class FluxNewsBodyStatefulWrapper extends StatefulWidget {
  final Function onInit;
  final Widget child;
  const FluxNewsBodyStatefulWrapper(
      {super.key, required this.onInit, required this.child});
  @override
  FluxNewsBodyState createState() => FluxNewsBodyState();
}

// extend class to save acutal scroll state of the list view
class FluxNewsBodyState extends State<FluxNewsBodyStatefulWrapper>
    with AutomaticKeepAliveClientMixin<FluxNewsBodyStatefulWrapper> {
  // init the state of FluxNewsBody to load the config and the data on startup
  @override
  void initState() {
    widget.onInit();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }

  @override
  bool get wantKeepAlive => true;
}
