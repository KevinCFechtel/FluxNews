import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/flux_news_localizations.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flux_news/state_management/flux_news_counter_state.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/functions/news_widget_functions.dart';
import 'package:flux_news/state_management/flux_news_theme_state.dart';
import 'package:flux_news/ui/news_items.dart';
import 'package:provider/provider.dart';

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
    FluxNewsThemeState themeState = context.read<FluxNewsThemeState>();
    List<Widget> rightSwipeActions = [];
    List<Widget> leftSwipeActions = [];
    Widget bookmarkSlidableAction = Expanded(
      child: InkWell(
        child: Card(
          color: themeState.brightnessMode == FluxNewsState.brightnessModeSystemString
              ? MediaQuery.of(context).platformBrightness == Brightness.dark
                  ? const Color.fromARGB(200, 254, 180, 0)
                  : const Color.fromARGB(255, 255, 210, 95)
              : themeState.brightnessMode == FluxNewsState.brightnessModeDarkString
                  ? const Color.fromARGB(200, 254, 180, 0)
                  : const Color.fromARGB(255, 255, 210, 95),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                news.starred ? Icons.star_outline : Icons.star,
              ),
              Text(
                news.starred
                    ? AppLocalizations.of(context)!.deleteBookmarkShort
                    : AppLocalizations.of(context)!.addBookmarkShort,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
                overflow: TextOverflow.visible,
              ),
            ],
          ),
        ),
        onTap: () {
          bookmarkAction(news, appState, context, searchView);
        },
      ),
    );
    Widget readSlidableAction = Expanded(
      child: InkWell(
        child: Card(
          color: themeState.brightnessMode == FluxNewsState.brightnessModeSystemString
              ? MediaQuery.of(context).platformBrightness == Brightness.dark
                  ? const Color.fromARGB(255, 0, 100, 10)
                  : const Color.fromARGB(255, 92, 251, 172)
              : themeState.brightnessMode == FluxNewsState.brightnessModeDarkString
                  ? const Color.fromARGB(255, 0, 100, 10)
                  : const Color.fromARGB(255, 92, 251, 145),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                news.status == FluxNewsState.readNewsStatus ? Icons.fiber_new : Icons.check,
              ),
              Text(
                news.status == FluxNewsState.readNewsStatus
                    ? AppLocalizations.of(context)!.unreadShort
                    : AppLocalizations.of(context)!.readShort,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        onTap: () {
          if (news.status == FluxNewsState.readNewsStatus) {
            markNewsAsUnreadAction(news, appState, context, searchView, context.read<FluxNewsCounterState>());
          } else {
            markNewsAsReadAction(news, appState, context, searchView, context.read<FluxNewsCounterState>());
          }
        },
      ),
    );
    Widget saveSlidableAction = Expanded(
      child: InkWell(
        child: Card(
          color: themeState.brightnessMode == FluxNewsState.brightnessModeSystemString
              ? MediaQuery.of(context).platformBrightness == Brightness.dark
                  ? const Color.fromARGB(130, 0, 160, 235)
                  : const Color.fromARGB(197, 82, 200, 255)
              : themeState.brightnessMode == FluxNewsState.brightnessModeDarkString
                  ? const Color.fromARGB(130, 0, 160, 235)
                  : const Color.fromARGB(197, 82, 200, 255),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.save,
              ),
              Text(
                AppLocalizations.of(context)!.saveShort,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        onTap: () {
          saveToThirdPartyAction(news, appState, context);
        },
      ),
    );
    Widget openMinifluxAction = Expanded(
      child: InkWell(
        child: Card(
          color: themeState.brightnessMode == FluxNewsState.brightnessModeSystemString
              ? MediaQuery.of(context).platformBrightness == Brightness.dark
                  ? const Color.fromARGB(130, 133, 0, 235)
                  : const Color.fromARGB(130, 191, 120, 245)
              : themeState.brightnessMode == FluxNewsState.brightnessModeDarkString
                  ? const Color.fromARGB(130, 133, 0, 235)
                  : const Color.fromARGB(130, 191, 120, 245),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.open_in_browser,
              ),
              Text(
                AppLocalizations.of(context)!.openMinifluxShort,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        onTap: () {
          openNewsAction(news, appState, context, true);
        },
      ),
    );
    if (appState.rightSwipeAction == FluxNewsState.swipeActionReadUnreadString) {
      rightSwipeActions.add(readSlidableAction);
    } else if (appState.rightSwipeAction == FluxNewsState.swipeActionBookmarkString) {
      rightSwipeActions.add(bookmarkSlidableAction);
    } else if (appState.rightSwipeAction == FluxNewsState.swipeActionSaveString) {
      rightSwipeActions.add(saveSlidableAction);
    } else if (appState.rightSwipeAction == FluxNewsState.swipeActionOpenMinifluxString) {
      rightSwipeActions.add(openMinifluxAction);
    }

    if (appState.leftSwipeAction == FluxNewsState.swipeActionReadUnreadString) {
      leftSwipeActions.add(readSlidableAction);
    } else if (appState.leftSwipeAction == FluxNewsState.swipeActionBookmarkString) {
      leftSwipeActions.add(bookmarkSlidableAction);
    } else if (appState.leftSwipeAction == FluxNewsState.swipeActionSaveString) {
      leftSwipeActions.add(saveSlidableAction);
    } else if (appState.leftSwipeAction == FluxNewsState.swipeActionOpenMinifluxString) {
      leftSwipeActions.add(openMinifluxAction);
    }
    return ClipRect(
        clipBehavior: Clip.none,
        child: Slidable(
            // Specify a key if the Slidable is dismissible.
            key: UniqueKey(),
            enabled: appState.activateSwipeGestures,
            closeOnScroll: true,
            // The start action pane is the one at the left or the top side.
            startActionPane: ActionPane(
              extentRatio: 0.2,
              dragDismissible: true,
              dismissible: DismissiblePane(
                closeOnCancel: true,
                dismissThreshold: 0.4,
                confirmDismiss: () async {
                  if (appState.rightSwipeAction == FluxNewsState.swipeActionReadUnreadString) {
                    if (news.status == FluxNewsState.readNewsStatus) {
                      markNewsAsUnreadAction(news, appState, context, searchView, context.read<FluxNewsCounterState>());
                    } else {
                      markNewsAsReadAction(news, appState, context, searchView, context.read<FluxNewsCounterState>());
                    }
                  } else if (appState.rightSwipeAction == FluxNewsState.swipeActionBookmarkString) {
                    bookmarkAction(news, appState, context, searchView);
                  } else if (appState.rightSwipeAction == FluxNewsState.swipeActionSaveString) {
                    saveToThirdPartyAction(news, appState, context);
                  } else if (appState.rightSwipeAction == FluxNewsState.swipeActionOpenMinifluxString) {
                    openNewsAction(news, appState, context, true);
                  }
                  return false;
                },
                onDismissed: () {
                  // Never gets called back
                },
              ),
              // A motion is a widget used to control how the pane animates.
              motion: const ScrollMotion(),

              // All actions are defined in the children parameter.
              children: rightSwipeActions,
            ),

            // The end action pane is the one at the right or the bottom side.
            endActionPane: ActionPane(
              extentRatio: 0.2,
              dragDismissible: true,
              dismissible: DismissiblePane(
                closeOnCancel: true,
                dismissThreshold: 0.4,
                confirmDismiss: () async {
                  if (appState.leftSwipeAction == FluxNewsState.swipeActionReadUnreadString) {
                    if (news.status == FluxNewsState.readNewsStatus) {
                      markNewsAsUnreadAction(news, appState, context, searchView, context.read<FluxNewsCounterState>());
                    } else {
                      markNewsAsReadAction(news, appState, context, searchView, context.read<FluxNewsCounterState>());
                    }
                  } else if (appState.leftSwipeAction == FluxNewsState.swipeActionBookmarkString) {
                    bookmarkAction(news, appState, context, searchView);
                  } else if (appState.leftSwipeAction == FluxNewsState.swipeActionSaveString) {
                    saveToThirdPartyAction(news, appState, context);
                  } else if (appState.leftSwipeAction == FluxNewsState.swipeActionOpenMinifluxString) {
                    openNewsAction(news, appState, context, true);
                  }
                  return false;
                },
                onDismissed: () {
                  // Never gets called back
                },
              ),
              motion: const ScrollMotion(),
              children: leftSwipeActions,
            ),

            // The child of the Slidable is what the user sees when the
            // component is not dragged.
            child: Card(
              // inkwell is used for the onTab and onLongPress functions
              child: InkWell(
                splashFactory: NoSplash.splashFactory,
                onTap: () async {
                  if (appState.tabAction == FluxNewsState.tabActionOpenString) {
                    if (news.openMinifluxEntry != null && news.openMinifluxEntry!) {
                      openNewsAction(news, appState, context, true);
                    } else {
                      openNewsAction(news, appState, context, false);
                    }
                  } else {
                    if (news.expanded) {
                      news.expanded = false;
                    } else {
                      news.expanded = true;
                    }
                    appState.refreshView();
                  }
                },
                // on tap get the actual position of the list on tab
                // to place the context menu on this position
                onTapDown: (details) {
                  getTapPosition(details, context, appState);
                },
                onLongPress: () {
                  if (appState.longPressAction == FluxNewsState.longPressActionMenuString) {
                    showContextMenu(news, context, searchView, appState, context.read<FluxNewsCounterState>());
                  } else {
                    if (news.expanded) {
                      news.expanded = false;
                    } else {
                      news.expanded = true;
                    }
                    appState.refreshView();
                  }
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
                            NewsContent(
                              news: news,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )));
  }
}
