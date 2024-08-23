import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/flux_news_localizations.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flux_news/functions/android_url_launcher.dart';
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/state_management/flux_news_counter_state.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:flux_news/functions/logging.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/functions/news_widget_functions.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

// here we define the appearance of the news cards
class NewsRow extends StatelessWidget {
  const NewsRow({
    super.key,
    required this.news,
    required this.context,
    required this.searchView,
  });
  final News news;
  final BuildContext context;
  final bool searchView;

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    List<Widget> rightSwipeActions = [];
    List<Widget> leftSwipeActions = [];
    SlidableAction bookmarkSlidableAction = SlidableAction(
      onPressed: (context) {
        bookmarkAction(news, appState, context, searchView);
      },
      backgroundColor: const Color.fromARGB(255, 254, 197, 73),
      foregroundColor: Colors.white,
      icon: Icons.star_outline,
      label: AppLocalizations.of(context)!.bookmarkShort,
    );
    SlidableAction readSlidableAction = SlidableAction(
      onPressed: (context) {
        if (news.status == FluxNewsState.readNewsStatus) {
          markNewsAsUnreadAction(news, appState, context, searchView, context.read<FluxNewsCounterState>());
        } else {
          markNewsAsReadAction(news, appState, context, searchView, context.read<FluxNewsCounterState>());
        }
      },
      backgroundColor: const Color(0xFF7BC043),
      foregroundColor: Colors.white,
      icon: news.status == FluxNewsState.readNewsStatus ? Icons.fiber_new : Icons.remove_red_eye_outlined,
      label: news.status == FluxNewsState.readNewsStatus
          ? AppLocalizations.of(context)!.unreadShort
          : AppLocalizations.of(context)!.readShort,
    );
    SlidableAction saveSlidableAction = SlidableAction(
      onPressed: (context) {
        saveToThirdPartyAction(news, appState, context);
      },
      backgroundColor: const Color(0xFF21B7CA),
      foregroundColor: Colors.white,
      icon: Icons.save,
      label: AppLocalizations.of(context)!.saveShort,
    );
    if (appState.rightSwipeAction == FluxNewsState.swipeActionReadUnreadString) {
      rightSwipeActions.add(readSlidableAction);
    } else if (appState.rightSwipeAction == FluxNewsState.swipeActionBookmarkString) {
      rightSwipeActions.add(bookmarkSlidableAction);
    } else if (appState.rightSwipeAction == FluxNewsState.swipeActionSaveString) {
      rightSwipeActions.add(saveSlidableAction);
    }

    if (appState.leftSwipeAction == FluxNewsState.swipeActionReadUnreadString) {
      leftSwipeActions.add(readSlidableAction);
    } else if (appState.leftSwipeAction == FluxNewsState.swipeActionBookmarkString) {
      leftSwipeActions.add(bookmarkSlidableAction);
    } else if (appState.leftSwipeAction == FluxNewsState.swipeActionSaveString) {
      leftSwipeActions.add(saveSlidableAction);
    }
    return Slidable(
        // Specify a key if the Slidable is dismissible.
        key: UniqueKey(),
        enabled: appState.activateSwipeGestures,
        // The start action pane is the one at the left or the top side.
        startActionPane: ActionPane(
          //dismissible: DismissiblePane(onDismissed: () {}),
          // A motion is a widget used to control how the pane animates.
          motion: const ScrollMotion(),

          // All actions are defined in the children parameter.
          children: rightSwipeActions,
        ),

        // The end action pane is the one at the right or the bottom side.
        endActionPane: ActionPane(
          motion: const ScrollMotion(),
          //dismissible: DismissiblePane(onDismissed: () {}),
          children: leftSwipeActions,
        ),

        // The child of the Slidable is what the user sees when the
        // component is not dragged.
        child: Card(
          // inkwell is used for the onTab and onLongPress functions
          child: InkWell(
            splashFactory: NoSplash.splashFactory,
            onTap: () async {
              // on tab we update the status of the news to read and open the news
              try {
                updateNewsStatusInDB(news.newsID, FluxNewsState.readNewsStatus, appState);
              } catch (e) {
                logThis('updateNewsStatusInDB', 'Caught an error in updateNewsStatusInDB function! : ${e.toString()}',
                    LogLevel.ERROR);

                if (context.mounted) {
                  if (appState.errorString != AppLocalizations.of(context)!.databaseError) {
                    appState.errorString = AppLocalizations.of(context)!.databaseError;
                    appState.newError = true;
                    appState.refreshView();
                  }
                }
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
              // on macos we open directly the web-view within the app.
              if (Platform.isAndroid) {
                AndroidUrlLauncher.launchUrl(context, news.url);
              } else if (Platform.isIOS) {
                // catch exception if no app is installed to handle the url
                final bool nativeAppLaunchSucceeded = await launchUrl(
                  Uri.parse(news.url),
                  mode: LaunchMode.externalNonBrowserApplication,
                );
                //if exception is caught, open the app in web-view
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
            /*
        onLongPressStart: (details) {
          // on tap get the actual position of the list on tab
          // to place the context menu on this position
          // after tab on long-press, open the context menu on the tab position
          showContextMenu(details, news, context, searchView, appState,
              context.read<FluxNewsCounterState>());
        },
        */
            // on tap get the actual position of the list on tab
            // to place the context menu on this position
            onTapDown: (details) {
              getTapPosition(details, context, appState);
            },
            onLongPress: () {
              showContextMenu(news, context, searchView, appState, context.read<FluxNewsCounterState>());
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                news.getImageURL() != FluxNewsState.noImageUrlString
                    ? Expanded(
                        flex: searchView
                            ? context.select((FluxNewsState model) => model.isTablet)
                                ? 4
                                : 5
                            : 5,
                        child: CachedNetworkImage(
                          imageUrl: news.getImageURL(),
                          height: 230,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          errorWidget: (context, url, error) => const Icon(
                            Icons.error,
                          ),
                        ),
                      )
                    // if no image is available, shrink this widget
                    : const SizedBox.shrink(),
                Expanded(
                  flex: searchView
                      ? context.select((FluxNewsState model) => model.isTablet)
                          ? 7
                          : 5
                      : 5,
                  child: ListTile(
                    title: Text(
                      news.title,
                      style: news.status == FluxNewsState.unreadNewsStatus
                          ? Theme.of(context).textTheme.titleLarge
                          : Theme.of(context).textTheme.titleLarge!.copyWith(color: Theme.of(context).disabledColor),
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
                                  : Padding(
                                      padding: const EdgeInsets.only(right: 15.0),
                                      child: SizedBox(
                                          width: 15,
                                          height: 35,
                                          child: Icon(
                                            Icons.check,
                                            color: Theme.of(context).disabledColor,
                                          ))),
                              appState.showFeedIcons
                                  ? Padding(
                                      padding: const EdgeInsets.only(right: 5.0),
                                      child: news.getFeedIcon(16.0, context))
                                  : const SizedBox.shrink(),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 0.0),
                                  child: Text(
                                    news.feedTitle,
                                    overflow: TextOverflow.ellipsis,
                                    style: news.status == FluxNewsState.unreadNewsStatus
                                        ? Theme.of(context).textTheme.bodyMedium
                                        : Theme.of(context)
                                            .textTheme
                                            .bodyMedium!
                                            .copyWith(color: Theme.of(context).disabledColor),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                child: Text(
                                  context.read<FluxNewsState>().dateFormat.format(news.getPublishingDate()),
                                  style: news.status == FluxNewsState.unreadNewsStatus
                                      ? Theme.of(context).textTheme.bodyMedium
                                      : Theme.of(context)
                                          .textTheme
                                          .bodyMedium!
                                          .copyWith(color: Theme.of(context).disabledColor),
                                ),
                              ),
                              SizedBox(
                                width: 40,
                                height: 35,
                                child: news.starred
                                    ? Icon(
                                        Icons.star,
                                        color: news.status == FluxNewsState.unreadNewsStatus
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
                            news.getText(appState),
                            style: news.status == FluxNewsState.unreadNewsStatus
                                ? Theme.of(context).textTheme.bodyMedium
                                : Theme.of(context)
                                    .textTheme
                                    .bodyMedium!
                                    .copyWith(color: Theme.of(context).disabledColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ));
  }
}
