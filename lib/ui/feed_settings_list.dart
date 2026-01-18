// the list view widget with search result
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flux_news/database/database_backend.dart';
import 'package:flux_news/state_management/flux_news_state.dart';
import 'package:flux_news/models/news_model.dart';
import 'package:provider/provider.dart';

class FeedSettingsList extends StatelessWidget {
  const FeedSettingsList({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    var getData = FutureBuilder<List<Feed>>(
      future: appState.feedSettingsList,
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
                      AppLocalizations.of(context)!.emptyFeedList,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ))
                  // show empty dialog if list is empty
                  : snapshot.data!.isEmpty
                      ? Center(
                          child: Text(
                          AppLocalizations.of(context)!.emptyFeedList,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ))
                      // otherwise create list view with the news of the search result
                      : ListView(children: [
                          for (Feed feed in snapshot.data!) showFeed(feed, context),
                        ]);
            }
        }
      },
    );
    return getData;
  }

  // here we style the category ExpansionTile
  // we use a ExpansionTile because we want to show the according feeds
  // of this category in the expanded state.
  Widget showFeed(Feed feed, BuildContext context) {
    FluxNewsState appState = context.read<FluxNewsState>();
    return ExpansionTile(
      leading: feed.getFeedIcon(16.0, context),
      // make the title clickable to select this category as the news view
      title: Text(
        feed.title,
        style: Theme.of(context).textTheme.labelLarge,
        overflow: TextOverflow.ellipsis,
      ),
      // iterate over the according feeds of the category
      children: [
        appState.truncateMode == 2
            ? Row(
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
                    child: const Icon(
                      Icons.cut,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.manualTruncate,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                  Switch.adaptive(
                    value: feed.manualTruncate == null ? false : feed.manualTruncate!,
                    onChanged: (bool value) async {
                      feed.manualTruncate = value;
                      await updateManualTruncateStatusOfFeedInDB(feed.feedID, value, appState);
                      // reload the news list with the new filter
                      appState.newsList = queryNewsFromDB(appState).whenComplete(() {
                        appState.jumpToItem(0);
                      });
                      appState.refreshView();
                    },
                  ),
                ],
              )
            : const SizedBox.shrink(),
        appState.truncateMode == 2 ? const Divider() : const SizedBox.shrink(),
        Row(
          children: [
            Padding(
              padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
              child: const Icon(
                Icons.html,
              ),
            ),
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.preferParagraph,
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.visible,
              ),
            ),
            Switch.adaptive(
              value: feed.preferParagraph == null ? false : feed.preferParagraph!,
              onChanged: (bool value) async {
                feed.preferParagraph = value;
                await updatePreferParagraphStatusOfFeedInDB(feed.feedID, value, appState);
                // reload the news list with the new filter
                appState.newsList = queryNewsFromDB(appState).whenComplete(() {
                  appState.jumpToItem(0);
                });
                appState.refreshView();
              },
            ),
          ],
        ),
        const Divider(),
        Row(
          children: [
            Padding(
              padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
              child: const Icon(
                Icons.image,
              ),
            ),
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.preferAttachmentImage,
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.visible,
              ),
            ),
            Switch.adaptive(
              value: feed.preferAttachmentImage == null ? false : feed.preferAttachmentImage!,
              onChanged: (bool value) async {
                feed.preferAttachmentImage = value;
                await updatePreferAttachmentImageStatusOfFeedInDB(feed.feedID, value, appState);
                // reload the news list with the new filter
                appState.newsList = queryNewsFromDB(appState).whenComplete(() {
                  appState.jumpToItem(0);
                });
                appState.refreshView();
              },
            ),
          ],
        ),
        const Divider(),
        Row(
          children: [
            Padding(
              padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
              child: const Icon(
                Icons.light_mode,
              ),
            ),
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.manualAdaptLightModeToIcon,
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.visible,
              ),
            ),
            Switch.adaptive(
              value: feed.manualAdaptLightModeToIcon == null ? false : feed.manualAdaptLightModeToIcon!,
              onChanged: (bool value) async {
                feed.manualAdaptLightModeToIcon = value;
                await updateManualAdaptLightModeToIconStatusOfFeedInDB(feed.feedID, value, appState);
                if (context.mounted) {
                  appState.categoryList = queryCategoriesFromDB(appState, context);
                }

                // reload the news list with the new filter
                appState.newsList = queryNewsFromDB(appState).whenComplete(() {
                  appState.jumpToItem(0);
                });
                appState.refreshView();
              },
            ),
          ],
        ),
        const Divider(),
        Row(
          children: [
            Padding(
              padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
              child: const Icon(
                Icons.dark_mode,
              ),
            ),
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.manualAdaptDarkModeToIcon,
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.visible,
              ),
            ),
            Switch.adaptive(
              value: feed.manualAdaptDarkModeToIcon == null ? false : feed.manualAdaptDarkModeToIcon!,
              onChanged: (bool value) async {
                feed.manualAdaptDarkModeToIcon = value;
                await updateManualAdaptDarkModeToIconStatusOfFeedInDB(feed.feedID, value, appState);
                if (context.mounted) {
                  appState.categoryList = queryCategoriesFromDB(appState, context);
                }

                // reload the news list with the new filter
                appState.newsList = queryNewsFromDB(appState).whenComplete(() {
                  appState.jumpToItem(0);
                });
                appState.refreshView();
              },
            ),
          ],
        ),
        const Divider(),
        Row(
          children: [
            Padding(
              padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
              child: const Icon(
                Icons.open_in_browser,
              ),
            ),
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.openMinifluxEntry,
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.visible,
              ),
            ),
            Switch.adaptive(
              value: feed.openMinifluxEntry == null ? false : feed.openMinifluxEntry!,
              onChanged: (bool value) async {
                feed.openMinifluxEntry = value;
                await updateOpenMinifluxEntryStatusOfFeedInDB(feed.feedID, value, appState);

                // reload the news list with the new filter
                appState.newsList = queryNewsFromDB(appState).whenComplete(() {
                  appState.jumpToItem(0);
                });
                appState.refreshView();
              },
            ),
          ],
        ),
        const Divider(),
        Row(
          children: [
            Padding(
              padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
              child: const Icon(
                Icons.text_snippet,
              ),
            ),
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.expandedWithFulltext,
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.visible,
              ),
            ),
            Switch.adaptive(
              value: feed.expandedWithFulltext == null ? false : feed.expandedWithFulltext!,
              onChanged: (bool value) async {
                feed.expandedWithFulltext = value;
                await updateExpandedWithFulltextStatusOfFeedInDB(feed.feedID, value, appState);

                // reload the news list with the new filter
                appState.newsList = queryNewsFromDB(appState).whenComplete(() {
                  appState.jumpToItem(0);
                });
                appState.refreshView();
              },
            ),
          ],
        ),
        const Divider(),
        // this row contains the selection of the amount of searched news
        // there are the choices of all, 1000, 2000, 5000 and 10000
        Row(
          children: [
            Padding(
              padding: EdgeInsets.only(left: 17.0, right: Platform.isIOS ? 15.0 : 30.0),
              child: const Icon(
                Icons.cut_outlined,
              ),
            ),
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.amountOfCharactersToTruncateExpand,
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.visible,
              ),
            ),
            DropdownButton<KeyValueRecordType>(
              value: feed.getAmountOfCharactersToTruncateExpandSelection(context),
              elevation: 16,
              underline: Container(
                height: 2,
              ),
              alignment: AlignmentDirectional.centerEnd,
              onChanged: (KeyValueRecordType? value) async {
                if (value != null) {
                  feed.expandedFulltextLimit = int.parse(value.key);
                  await updateExpandedFulltextLimitOfFeedInDB(feed.feedID, int.parse(value.key), appState);

                  // reload the news list with the new filter
                  appState.newsList = queryNewsFromDB(appState).whenComplete(() {
                    appState.jumpToItem(0);
                  });
                  appState.refreshView();
                }
              },
              items: feed
                  .getAmountOfCharactersToTruncateExpandRecordTypes(context)
                  .map<DropdownMenuItem<KeyValueRecordType>>((recordType) => DropdownMenuItem<KeyValueRecordType>(
                        value: recordType,
                        child: Text(
                          recordType.value,
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
      ],
    );
  }
}
