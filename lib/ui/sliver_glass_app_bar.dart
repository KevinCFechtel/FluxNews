import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/functions/news_widget_functions.dart';
import 'package:flux_news/functions/sync_news.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/state_management/flux_news_counter_state.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:flux_news/state_management/flux_news_theme_state.dart';
import 'package:flux_news/ui/downloads_overview.dart';
import 'package:flux_news/ui/flux_news_body.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

class SliverGlassAppBar extends StatelessWidget {
  const SliverGlassAppBar({super.key, required this.emptyBody});

  final bool emptyBody;

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.read<FluxNewsState>();
    FluxNewsThemeState themeState = context.watch<FluxNewsThemeState>();
    if (appState.glassAppBar) {
      return SliverAppBar(
        backgroundColor: Colors.transparent,
        floating: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        forceElevated: true,
        pinned: true,
        leading: Builder(
          builder: (BuildContext context) {
            return IconButton(
              icon: const FaIcon(FontAwesomeIcons.bookOpen),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
              tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
            );
          },
        ),
        title: const AppBarTitle(),
        flexibleSpace: Stack(
          fit: StackFit.expand,
          children: [
            ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: FlexibleSpaceBar(
                  expandedTitleScale: 1.0,
                  background: Container(
                    decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor.withAlpha(90)),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            emptyBody
                ? SizedBox.shrink()
                : IgnorePointer(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: 1,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          boxShadow: [
                            themeState.brightnessMode == FluxNewsState.brightnessModeDarkString
                                ? BoxShadow(
                                    color: Colors.black,
                                    blurRadius: 2,
                                    spreadRadius: 0,
                                    offset: const Offset(0, 1),
                                    blurStyle: BlurStyle.normal,
                                  )
                                : themeState.brightnessMode == FluxNewsState.brightnessModeSystemString
                                    ? MediaQuery.of(context).platformBrightness == Brightness.light
                                        ? BoxShadow()
                                        : BoxShadow(
                                            color: Colors.black,
                                            blurRadius: 2,
                                            spreadRadius: 0,
                                            offset: const Offset(0, 1),
                                            blurStyle: BlurStyle.normal,
                                          )
                                    : BoxShadow(),
                            themeState.brightnessMode == FluxNewsState.brightnessModeDarkString
                                ? BoxShadow(
                                    color: Colors.black,
                                    blurRadius: 4,
                                    spreadRadius: 0.3,
                                    offset: const Offset(0, 4),
                                    blurStyle: BlurStyle.normal,
                                  )
                                : themeState.brightnessMode == FluxNewsState.brightnessModeSystemString
                                    ? MediaQuery.of(context).platformBrightness == Brightness.light
                                        ? BoxShadow(
                                            color: Colors.black,
                                            blurRadius: 4,
                                            spreadRadius: 0,
                                            offset: const Offset(0, 4),
                                            blurStyle: BlurStyle.normal,
                                          )
                                        : BoxShadow(
                                            color: Colors.black,
                                            blurRadius: 4,
                                            spreadRadius: 0.3,
                                            offset: const Offset(0, 4),
                                            blurStyle: BlurStyle.normal,
                                          )
                                    : BoxShadow(
                                        color: Colors.black,
                                        blurRadius: 4,
                                        spreadRadius: 0,
                                        offset: const Offset(0, 4),
                                        blurStyle: BlurStyle.normal,
                                      ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ],
        ),
        shape: emptyBody
            ? Border()
            : Border(bottom: BorderSide(color: Theme.of(context).scaffoldBackgroundColor, width: 1)),
        actions: appBarButtons(context),
      );
    } else if (appState.scrolloverAppBar) {
      return SliverAppBar(
        backgroundColor: Colors.transparent, //Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        floating: true,
        leading: Builder(
          builder: (BuildContext context) {
            return IconButton(
              icon: const FaIcon(FontAwesomeIcons.bookOpen),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
              tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
            );
          },
        ),
        title: const AppBarTitle(),
        actions: appBarButtons(context),
      );
    } else {
      return SliverToBoxAdapter(child: SizedBox.shrink());
    }
  }

  List<Widget> appBarButtons(BuildContext context) {
    FluxNewsCounterState appCounterState = context.read<FluxNewsCounterState>();
    FluxNewsState appState = context.read<FluxNewsState>();
    // define the app bar buttons to sync with miniflux,
    // search for news and switch between all and only unread news view
    // and the navigation to the settings
    return <Widget>[
      // here is the sync part
      IconButton(
        onPressed: () async {
          if (appState.syncProcess) {
            appState.longSyncAborted = true;
            appState.refreshView();
          } else {
            await syncNews(appState, context);
          }
        },
        icon: appState.syncProcess
            ? const SizedBox(height: 15.0, width: 15.0, child: CircularProgressIndicator.adaptive())
            : const Icon(Icons.refresh),
      ),
      // here is the popup menu where the user can search,
      // choose between all and only unread news view
      // and navigate to the settings
      PopupMenuButton(
        icon: const Icon(Icons.more_vert),
        color: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(8.0),
            bottomRight: Radius.circular(8.0),
            topLeft: Radius.circular(8.0),
            topRight: Radius.circular(8.0),
          ),
        ),
        itemBuilder: (context) {
          return [
            // the search button
            PopupMenuItem<int>(
              value: 0,
              child: Row(
                children: [
                  const Padding(padding: EdgeInsets.only(right: 5), child: Icon(Icons.search)),
                  Expanded(child: Text(AppLocalizations.of(context)!.search, overflow: TextOverflow.visible)),
                ],
              ),
            ),
            // the switch between all and only unread news view
            PopupMenuItem<int>(
              value: 1,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: Icon(
                      appState.newsStatus == FluxNewsState.unreadNewsStatus ? Icons.checklist : Icons.fiber_new,
                    ),
                  ),
                  Expanded(
                    child: appState.newsStatus == FluxNewsState.unreadNewsStatus
                        ? Text(AppLocalizations.of(context)!.showRead, overflow: TextOverflow.visible)
                        : Text(AppLocalizations.of(context)!.showUnread, overflow: TextOverflow.visible),
                  ),
                ],
              ),
            ),
            // the selection of the sort order of the news (newest first or oldest first)
            PopupMenuItem<int>(
              value: 2,
              child: Row(
                children: [
                  const Padding(padding: EdgeInsets.only(right: 5), child: Icon(Icons.sort)),
                  Expanded(
                    child: appState.sortOrder == FluxNewsState.sortOrderNewestFirstString
                        ? Text(AppLocalizations.of(context)!.oldestFirst, overflow: TextOverflow.visible)
                        : Text(AppLocalizations.of(context)!.newestFirst, overflow: TextOverflow.visible),
                  ),
                ],
              ),
            ),
            PopupMenuItem<int>(
              value: 3,
              child: Row(
                children: [
                  const Padding(padding: EdgeInsets.only(right: 5), child: Icon(Icons.check_circle_outline)),
                  Expanded(
                    child: appState.selectedCategoryElementType == FluxNewsState.feedElementType
                        ? Text(AppLocalizations.of(context)!.markFeedAsRead, overflow: TextOverflow.visible)
                        : appState.selectedCategoryElementType == FluxNewsState.categoryElementType
                            ? Text(AppLocalizations.of(context)!.markCategoryAsRead, overflow: TextOverflow.visible)
                            : appState.selectedCategoryElementType == FluxNewsState.bookmarkedNewsElementType
                                ? Text(AppLocalizations.of(context)!.markBookmarkedAsRead,
                                    overflow: TextOverflow.visible)
                                : Text(AppLocalizations.of(context)!.markAllAsRead, overflow: TextOverflow.visible),
                  ),
                ],
              ),
            ),
            PopupMenuItem<int>(
              value: 4,
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(right: 5),
                    child: Icon(Icons.download_for_offline_outlined),
                  ),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.audioDownloadsSettings,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                ],
              ),
            ),
            // the navigation to the settings
            PopupMenuItem<int>(
              value: 5,
              child: Row(
                children: [
                  const Padding(padding: EdgeInsets.only(right: 5), child: Icon(Icons.settings)),
                  Expanded(child: Text(AppLocalizations.of(context)!.settings, overflow: TextOverflow.visible)),
                ],
              ),
            ),
          ];
        },
        onSelected: (value) async {
          if (value == 0) {
            // navigate to the search page
            Navigator.pushNamed(context, FluxNewsState.searchRouteString);
          } else if (value == 1) {
            // switch between all and only unread news view
            // if the current view is unread news change to all news
            if (appState.newsStatus == FluxNewsState.unreadNewsStatus) {
              // switch the state to all news
              appState.newsStatus = FluxNewsState.allNewsString;

              // save the state persistent
              appState.storage.write(key: FluxNewsState.secureStorageNewsStatusKey, value: FluxNewsState.allNewsString);

              // refresh news list with the all news state
              appState.newsList = queryNewsFromDB(appState).whenComplete(() {
                appState.jumpToItem(0);
              });

              // notify the categories to update the news count
              appCounterState.listUpdated = true;
              appCounterState.refreshView();
              appState.refreshView();
              // if the current view is all news change to only unread news
            } else {
              // switch the state to show only unread news
              appState.newsStatus = FluxNewsState.unreadNewsStatus;

              // save the state persistent
              appState.storage.write(
                key: FluxNewsState.secureStorageNewsStatusKey,
                value: FluxNewsState.unreadNewsStatus,
              );

              // refresh news list with the only unread news state
              appState.newsList = queryNewsFromDB(appState).whenComplete(() {
                appState.jumpToItem(0);
              });

              // notify the categories to update the news count
              appCounterState.listUpdated = true;
              appCounterState.refreshView();
              appState.refreshView();
            }
          } else if (value == 2) {
            // switch between newest first and oldest first
            // if the current sort order is newest first change to oldest first
            if (appState.sortOrder == FluxNewsState.sortOrderNewestFirstString) {
              // switch the state to all news
              appState.sortOrder = FluxNewsState.sortOrderOldestFirstString;

              // save the state persistent
              appState.storage.write(
                key: FluxNewsState.secureStorageSortOrderKey,
                value: FluxNewsState.sortOrderOldestFirstString,
              );

              // refresh news list with the all news state
              appState.newsList = queryNewsFromDB(appState).whenComplete(() {
                appState.jumpToItem(0);
              });

              // notify the categories to update the news count
              appCounterState.listUpdated = true;
              appCounterState.refreshView();
              appState.refreshView();
              // if the current sort order is oldest first change to newest first
            } else {
              // switch the state to show only unread news
              appState.sortOrder = FluxNewsState.sortOrderNewestFirstString;

              // save the state persistent
              appState.storage.write(
                key: FluxNewsState.secureStorageSortOrderKey,
                value: FluxNewsState.sortOrderNewestFirstString,
              );

              // refresh news list with the only unread news state
              appState.newsList = queryNewsFromDB(appState).whenComplete(() {
                appState.jumpToItem(0);
              });

              // notify the categories to update the news count
              appCounterState.listUpdated = true;
              appCounterState.refreshView();
              appState.refreshView();
            }
          } else if (value == 3) {
            showDeleteAllDialog(context, appState, appCounterState);
          } else if (value == 4) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const DownloadsOverview(),
              ),
            );
          } else if (value == 5) {
            // navigate to the settings page
            Navigator.pushNamed(context, FluxNewsState.settingsRouteString);
          }
        },
      ),
    ];
  }
}
