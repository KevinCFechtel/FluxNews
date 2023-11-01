import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flux_news/android_url_launcher.dart';
import 'package:flux_news/database_backend.dart';
import 'package:flux_news/flux_news_state.dart';
import 'package:flux_news/news_model.dart';
import 'package:flux_news/news_widget_functions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_gen/gen_l10n/flux_news_localizations.dart';

// here we define the appearance of the news cards
Widget showNewsCard(
    News news, FluxNewsState appState, BuildContext context, bool searchView) {
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
          if (Platform.isAndroid || Platform.isIOS) {
            FlutterLogs.logThis(
                tag: FluxNewsState.logTag,
                subTag: 'updateNewsStatusInDB',
                logMessage: 'Caught an error in updateNewsStatusInDB function!',
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
        // update the status to read on the news list and notify the categories
        // to recalculate the news count
        news.status = FluxNewsState.readNewsStatus;
        appState.listUpdated = true;
        appState.refreshView();

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
        getTapPosition(details, context, appState);
      },
      // after tab on longpress, open the context menu on the tab position
      onLongPress: () {
        showContextMenu(news, context, appState, searchView);
      },
      child: Column(
        children: [
          // load the news image if present
          news.getImageURL() != FluxNewsState.noImageUrlString
              ?
              // the CachedNetworkImage is used to load the images
              CachedNetworkImage(
                  imageUrl: news.getImageURL(),
                  height: appState.isTablet ? 250 : 175,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => const Icon(
                    Icons.error,
                  ),
                )
              // if no image is available, shrink this widget
              : const SizedBox.shrink(),
          // the title and additional infos are presented within a ListTile
          // the Opacity decide between read and unread news
          ListTile(
              title: Text(
                news.title,
                style: news.status == FluxNewsState.unreadNewsStatus
                    ? Theme.of(context).textTheme.titleLarge
                    : Theme.of(context)
                        .textTheme
                        .titleLarge!
                        .copyWith(color: Theme.of(context).disabledColor),
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
                          child: Text(
                            news.feedTitel,
                            style: news.status == FluxNewsState.unreadNewsStatus
                                ? Theme.of(context).textTheme.bodyMedium
                                : Theme.of(context)
                                    .textTheme
                                    .bodyMedium!
                                    .copyWith(
                                        color: Theme.of(context).disabledColor),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Text(
                            appState.dateFormat
                                .format(news.getPublishingDate()),
                            style: news.status == FluxNewsState.unreadNewsStatus
                                ? Theme.of(context).textTheme.bodyMedium
                                : Theme.of(context)
                                    .textTheme
                                    .bodyMedium!
                                    .copyWith(
                                        color: Theme.of(context).disabledColor),
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          height: 35,
                          child: news.starred
                              ? Icon(
                                  Icons.star,
                                  color: news.status ==
                                          FluxNewsState.unreadNewsStatus
                                      ? Theme.of(context).primaryIconTheme.color
                                      : Theme.of(context).disabledColor,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                  // here is the news text, the Opacity decide between read and unread
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0, bottom: 10),
                    child: Text(
                      news.getText(),
                      style: news.status == FluxNewsState.unreadNewsStatus
                          ? Theme.of(context).textTheme.bodyMedium
                          : Theme.of(context)
                              .textTheme
                              .bodyMedium!
                              .copyWith(color: Theme.of(context).disabledColor),
                    ),
                  ),
                ],
              )),
        ],
      ),
    ),
  );
}