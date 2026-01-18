// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'flux_news_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get fluxNews => 'Flux News';

  @override
  String get minifluxServer => 'Miniflux Server';

  @override
  String get allNews => 'All News';

  @override
  String get noNewEntries => 'No new news';

  @override
  String get deleteBookmark => 'Delete Bookmark';

  @override
  String get addBookmark => 'Add Bookmark';

  @override
  String get markAsRead => 'Mark as read';

  @override
  String get markAsUnread => 'Mark as unread';

  @override
  String get showUnread => 'Show unread news';

  @override
  String get showRead => 'Show all news';

  @override
  String get settingsNotSet => 'Settings not set';

  @override
  String get provideMinifluxCredentials =>
      'Please provide miniflux URL and API-Key';

  @override
  String get error => 'Error';

  @override
  String get ok => 'Ok';

  @override
  String get all => 'All';

  @override
  String get always => 'Always';

  @override
  String get settings => 'Settings';

  @override
  String get minifluxSettings => 'Miniflux Settings';

  @override
  String get apiUrl => 'API Url';

  @override
  String get apiKey => 'API Key';

  @override
  String get minifluxVersion => 'Miniflux Version';

  @override
  String get brightnesMode => 'Brightness mode';

  @override
  String get sortOrderOfNews => 'Sort order of News';

  @override
  String get markAsReadOnScrollover => 'Mark as read on scrollover';

  @override
  String get amountSaved => 'Amount of News which should be saved';

  @override
  String get amountSavedStarred =>
      'Amount of starred News which should be saved';

  @override
  String get titleURL => 'URL';

  @override
  String get enterURL => 'Enter the URL';

  @override
  String get enterValidURL => 'Enter a valid Miniflux URL with trailing slash';

  @override
  String get cancel => 'Cancel';

  @override
  String get enterAPIKey => 'Enter the API Key:';

  @override
  String get titleAPIKey => 'API Key';

  @override
  String get save => 'Save';

  @override
  String get system => 'System';

  @override
  String get dark => 'Dark';

  @override
  String get light => 'Light';

  @override
  String get newestFirst => 'Newest first';

  @override
  String get oldestFirst => 'Oldest first';

  @override
  String get communicateionMinifluxError =>
      'Error while communicating with the miniflux server';

  @override
  String get databaseError => 'Error occurred while processing the data';

  @override
  String get authError => 'Error authenticating against miniflux';

  @override
  String get generalSettings => 'General Settings';

  @override
  String get syncOnStart => 'Sync News on startup';

  @override
  String get bookmarked => 'Bookmarked';

  @override
  String get itemCount => 'Count';

  @override
  String get multilineAppBarTextSetting => 'Show newscount in Appbar';

  @override
  String get showFeedIconsTextSettings => 'Show feed icons';

  @override
  String get descriptionMinifluxApp =>
      'This is a simple Newsreader to work with miniflux.\nFor more information about miniflux, visit the projekt page:';

  @override
  String get descriptionMoreInformation =>
      'For more information about this app, visit the project page:';

  @override
  String get search => 'Search';

  @override
  String get searchHint => 'Search...';

  @override
  String get emptySearch => 'No News found';

  @override
  String get exportLogs => 'Export debug logs';

  @override
  String get debugModeTextSettings => 'Activate debug mode';

  @override
  String get deleteLocalCache => 'Clear local news storage';

  @override
  String get deleteLocalCacheDialogTitle => 'Delete local cache';

  @override
  String get deleteLocalCacheDialogContent =>
      'Do you really want to delete the local news storage?';

  @override
  String get contextSaveButton => 'Save news to third party';

  @override
  String get insecureMinifluxURL =>
      'An insecure connection to miniflux is used!';

  @override
  String get longSyncWarning =>
      'The number of messages leads to slow synchronization!';

  @override
  String get longSyncHeader => 'Slow synchronization';

  @override
  String get tooManyNews =>
      'The number of messages exceeds the limit of 10,000, so synchronization is not possible.\nPlease reduce the amount of synced news.';

  @override
  String get markAllAsRead => 'Mark all news as read';

  @override
  String get markBookmarkedAsRead => 'Mark bookmarked news as read';

  @override
  String get markCategoryAsRead => 'Mark category as read';

  @override
  String get markFeedAsRead => 'Mark feed as read';

  @override
  String get amountOfSyncedNews => 'Amount of News which should be synced';

  @override
  String get amountOfSearchedNews => 'Amount of News which should be searched';

  @override
  String get debugSettings => 'Debug Settings';

  @override
  String get truncateSettings => 'Truncate Settings';

  @override
  String get activateTruncate => 'Truncate news text';

  @override
  String get truncateMode => 'Truncate Mode';

  @override
  String get truncateModeAll => 'Truncate all news';

  @override
  String get truncateModeScraper =>
      'Truncate all news from feeds with original content fetched';

  @override
  String get truncateModeManual =>
      'Truncate all news from feeds which has been selected manually in the feed settings';

  @override
  String get charactersToTruncate =>
      'Amount of characters to which the text is truncated';

  @override
  String get charactersToTruncateLimit =>
      'Amount of characters from which the text is truncated';

  @override
  String get manualTruncate => 'Truncate news';

  @override
  String get successfullSaveToThirdParty => 'The news was successfully saved!';

  @override
  String get addBookmarkShort => 'Add Bookmark';

  @override
  String get bookmarkShort => 'Bookmark';

  @override
  String get saveShort => 'Save';

  @override
  String get readShort => 'Read';

  @override
  String get unreadShort => 'Unread';

  @override
  String get leftSwipeSelectionOption =>
      'Select action for swiping to the left';

  @override
  String get rightSwipeSelectionOption =>
      'Select action for swiping to the right';

  @override
  String get secondLeftSwipeSelectionOption =>
      'Select second action for swiping to the left';

  @override
  String get secondRightSwipeSelectionOption =>
      'Select second action for swiping to the right';

  @override
  String get deleteBookmarkShort => 'Delete bookmark';

  @override
  String get activateSwiping => 'Activate swipe gestures';

  @override
  String get feedSettings => 'Feed settings';

  @override
  String get emptyFeedList => 'No Feeds fetched';

  @override
  String get preferParagraph => 'Prefer first HTML paragraph as news text';

  @override
  String get preferAttachmentImage => 'Prefer attachment image as news picture';

  @override
  String get manualAdaptLightModeToIcon =>
      'Manual adapt the light mode to a transparent feed icon';

  @override
  String get manualAdaptDarkModeToIcon =>
      'Manual adapt the dark mode to a transparent feed icon';

  @override
  String get openMinifluxEntry => 'Open news in miniflux webinterface';

  @override
  String get openMinifluxShort => 'Open in miniflux';

  @override
  String get scrollHorizontal => 'Scroll horizontal';

  @override
  String get open => 'Open';

  @override
  String get floatingActionButton =>
      'Use an extra button to mark all messages as read';

  @override
  String get useBlackMode => 'Enable black mode specifically for OLED displays';

  @override
  String get expand => 'Expand';

  @override
  String get menu => 'Action Menu';

  @override
  String get tabActionSettings => 'Select action for tapping on a news item';

  @override
  String get longPressActionSettings =>
      'Select action for long press on a news item';

  @override
  String get expandedWithFulltext =>
      'Show formatted text instead of full HTML when expanding the news content';

  @override
  String get showHeadlineOnTop =>
      'Show the headline of the news above the image';

  @override
  String get showOnlyFeedCategoriesWithNewNews =>
      'Only show the categories and feeds that have new messages';

  @override
  String get none => 'None';

  @override
  String get syncInProgress => 'Sync in progress...';

  @override
  String get startupCategorie => 'Choose Categorie for startup';

  @override
  String get startupCategorieAll => 'Show all news on startup';

  @override
  String get startupCategorieBookmarks =>
      'Show the bookmark categorie on startup';

  @override
  String get startupCategorieCategorie =>
      'Choose a categorie as default for startup';

  @override
  String get startupCategorieFeed => 'Choose a feed as default for startup';

  @override
  String get startupCategorieCategorieSelection =>
      'Select a categorie as default for startup';

  @override
  String get startupCategorieFeedSelection =>
      'Select a feed as default for startup';

  @override
  String get share => 'Share';

  @override
  String get openComments => 'Open Comments';

  @override
  String get splitted => 'Splitted';

  @override
  String get splittedDescription =>
      'Splitted means that clicking on the text expands the text, and clicking on the title or the image opens the link';

  @override
  String get amountOfCharactersToTruncateExpand =>
      'Amount of characters to which the expanded formatted text is truncated';
}
