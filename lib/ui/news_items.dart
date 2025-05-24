// here we define the appearance of the news cards
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:flux_news/functions/news_widget_functions.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:provider/provider.dart';

class NewsTopHeadline extends StatelessWidget {
  const NewsTopHeadline({
    super.key,
    required this.news,
  });
  final News news;

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    return ListTile(
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
                      ? Padding(padding: const EdgeInsets.only(right: 5.0), child: news.getFeedIcon(16.0, context))
                      : const SizedBox.shrink(),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 0.0),
                      child: Text(
                        news.feedTitle,
                        overflow: TextOverflow.ellipsis,
                        style: news.status == FluxNewsState.unreadNewsStatus
                            ? Theme.of(context).textTheme.bodyMedium
                            : Theme.of(context).textTheme.bodyMedium!.copyWith(color: Theme.of(context).disabledColor),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Text(
                      context.read<FluxNewsState>().dateFormat.format(news.getPublishingDate()),
                      style: news.status == FluxNewsState.unreadNewsStatus
                          ? Theme.of(context).textTheme.bodyMedium
                          : Theme.of(context).textTheme.bodyMedium!.copyWith(color: Theme.of(context).disabledColor),
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
          ],
        ));
  }
}

class NewsContent extends StatelessWidget {
  const NewsContent({
    super.key,
    required this.news,
  });
  final News news;

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    return Padding(
      padding: const EdgeInsets.only(top: 2.0, bottom: 10),
      child: news.expanded
          ? news.expandedWithFulltext != null
              ? news.expandedWithFulltext!
                  ? Text(
                      news.getFullText(appState),
                      style: news.status == FluxNewsState.unreadNewsStatus
                          ? Theme.of(context).textTheme.bodyMedium
                          : Theme.of(context).textTheme.bodyMedium!.copyWith(color: Theme.of(context).disabledColor),
                    )
                  : HtmlWidget(
                      news.content,
                      enableCaching: true,
                      textStyle: TextStyle(
                        fontSize: Theme.of(context).textTheme.bodyMedium!.fontSize,
                        color: news.status == FluxNewsState.unreadNewsStatus
                            ? Theme.of(context).textTheme.bodyMedium!.color
                            : Theme.of(context).disabledColor,
                      ),
                      onTapUrl: (url) async {
                        return await openUrlAction(url, context);
                      },
                    )
              : HtmlWidget(
                  news.content,
                  enableCaching: true,
                  textStyle: TextStyle(
                    fontSize: Theme.of(context).textTheme.bodyMedium!.fontSize,
                    color: news.status == FluxNewsState.unreadNewsStatus
                        ? Theme.of(context).textTheme.bodyMedium!.color
                        : Theme.of(context).disabledColor,
                  ),
                  onTapUrl: (url) async {
                    return await openUrlAction(url, context);
                  },
                )
          : Text(
              news.getText(appState),
              style: news.status == FluxNewsState.unreadNewsStatus
                  ? Theme.of(context).textTheme.bodyMedium
                  : Theme.of(context).textTheme.bodyMedium!.copyWith(color: Theme.of(context).disabledColor),
            ),
    );
  }
}
