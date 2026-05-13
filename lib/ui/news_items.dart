// here we define the appearance of the news cards
import 'package:flutter/material.dart';
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
                  news.getAudioAttachments().isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(right: 5.0),
                          child: Icon(
                            Icons.headphones,
                            size: 16.0,
                            color: news.status == FluxNewsState.unreadNewsStatus
                                ? Theme.of(context).primaryIconTheme.color
                                : Theme.of(context).disabledColor,
                          ),
                        )
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
                  if (news.getAudioAttachments().isNotEmpty && news.getFormattedPlaybackTime().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Text(
                        news.getFormattedPlaybackTime(),
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

    // Prepare audio playback time if audio attachments exist
    String playbackPrefix = '';
    if (news.getAudioAttachments().isNotEmpty && news.getFormattedPlaybackTime().isNotEmpty) {
      playbackPrefix = '🎧 ${news.getFormattedPlaybackTime()} • ';
    }

    final Widget textContent = news.expanded
        ? news.expandedWithFulltext != null
            ? news.expandedWithFulltext!
                ? news.getFullTextWidget(appState)
                : news.getFullRenderedWidget(appState, context)
            : news.getFullRenderedWidget(appState, context)
        : Text(
            playbackPrefix + news.getText(appState),
            style: news.status == FluxNewsState.unreadNewsStatus
                ? Theme.of(context).textTheme.bodyMedium
                : Theme.of(context).textTheme.bodyMedium!.copyWith(color: Theme.of(context).disabledColor),
          );

    return Padding(
      padding: const EdgeInsets.only(top: 2.0, bottom: 10),
      child: textContent,
    );
  }
}
