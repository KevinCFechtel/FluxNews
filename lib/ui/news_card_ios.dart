import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flux_news/functions/news_widget_functions.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/state_management/flux_news_counter_state.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:flux_news/ui/news_items.dart';
import 'package:provider/provider.dart';

class NewsCardIOS extends StatelessWidget {
  const NewsCardIOS({
    super.key,
    required this.news,
    required this.context,
    required this.searchView,
    required this.itemIndex,
    required this.newsList,
  });
  final News news;
  final BuildContext context;
  final bool searchView;
  final int itemIndex;
  final List<News>? newsList;

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    if (appState.longPressAction == FluxNewsState.longPressActionExpandString) {
      return InkWell(
          splashFactory: NoSplash.splashFactory,
          onTap: () async {
            onTabAction(appState, context, news, searchView, itemIndex, newsList);
          },
          onLongPress: () {
            if (news.expanded) {
              news.expanded = false;
            } else {
              news.expanded = true;
            }
            markNewsAsReadAction(news, appState, context, searchView, context.read<FluxNewsCounterState>());
          },
          child: newsCard(appState, AlwaysStoppedAnimation(1)));
    } else {
      return CupertinoContextMenu.builder(
          enableHapticFeedback: true,
          actions: getIOSContextMenuActions(appState, news, context, searchView, itemIndex, newsList),
          builder: (context, animation) {
            if (animation.status == AnimationStatus.completed) {
              return Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                  ),
                  child: newsCard(appState, animation));
            } else {
              return newsCard(appState, animation);
            }
          });
    }
  }

  Widget newsCard(FluxNewsState appState, Animation<double> animation) {
    return Card(
        // inkwell is used for the onTab and onLongPress functions
        child: InkWell(
            splashFactory: NoSplash.splashFactory,
            onTap: () async {
              if (animation.status != AnimationStatus.completed) {
                onTabAction(appState, context, news, searchView, itemIndex, newsList);
              }
            },
            child: animation.status != AnimationStatus.dismissed
                ? SingleChildScrollView(
                    child: newsCardContent(appState, animation),
                  )
                : newsCardContent(appState, animation)));
  }

  Widget newsCardContent(FluxNewsState appState, Animation<double> animation) {
    return Column(
      children: [
        appState.showHeadlineOnTop ? NewsTopHeadline(news: news) : SizedBox.shrink(),
        // load the news image if present
        news.getImageURL() != FluxNewsState.noImageUrlString
            ?
            // the CachedNetworkImage is used to load the images
            CachedNetworkImage(
                imageUrl: news.getImageURL(),
                height: appState.isTablet ? 250 : 175,
                width: MediaQuery.sizeOf(context).width,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => const Icon(
                  Icons.error,
                ),
              )
            // if no image is available, shrink this widget
            : const SizedBox.shrink(),
        // the title and additional info's are presented within a ListTile
        // the Opacity decide between read and unread news
        SizedBox(
            width: MediaQuery.sizeOf(context).width,
            child: ListTile(
                title: !appState.showHeadlineOnTop
                    ? Text(
                        news.title,
                        style: news.status == FluxNewsState.unreadNewsStatus
                            ? Theme.of(context).textTheme.titleLarge
                            : Theme.of(context).textTheme.titleLarge!.copyWith(color: Theme.of(context).disabledColor),
                      )
                    : const SizedBox.shrink(),
                subtitle: Column(
                  children: [
                    !appState.showHeadlineOnTop
                        ? Padding(
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
                          )
                        : const SizedBox.shrink(),
                    // here is the news text, the Opacity decide between read and unread
                    InkWell(
                      splashFactory: NoSplash.splashFactory,
                      onTap: () {
                        if (animation.status != AnimationStatus.completed) {
                          onTabContentAction(appState, context, news, searchView, itemIndex, newsList);
                        }
                      },
                      child: NewsContent(
                        news: news,
                      ),
                    ),
                  ],
                )))
      ],
    );
  }
}
