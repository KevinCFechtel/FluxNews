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
  String get amountOfSyncedNews =>
      'Amount of unread News which should be synced';

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
      'Use an extra button for additional functions';

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

  @override
  String get syncSettings => 'Sync Settings';

  @override
  String get newsItemSettings => 'News Item Settings';

  @override
  String get removeNewsFromListWhenRead =>
      'Remove the news from the list when marked as read';

  @override
  String get syncReadNews => 'Also synchronize read news';

  @override
  String get syncReadNewsAfterDays =>
      'Synchronize read news from the last days: ';

  @override
  String get skipLongSync => 'Skip long sync dialog';

  @override
  String get syncReadStatusImmediately =>
      'Immediately sync read status to server';

  @override
  String get headerSettings =>
      'Set additional custom headers for accessing Miniflux';

  @override
  String get headerKey => 'Header Name: ';

  @override
  String get headerValue => 'Header Value: ';

  @override
  String get delete => 'Delete';

  @override
  String get headers => 'Headers';

  @override
  String get scrolloverAppBar => 'The app bar is collapsible on scroll';

  @override
  String get syncNews => 'Sync News';

  @override
  String get floatingButtonAction => 'Select the action for the extra button';

  @override
  String get markNewsAsReadButton => 'Mark as read';

  @override
  String get glassAppBar => 'The app bar has a glass effect';

  @override
  String get normal => 'Normal';

  @override
  String get collapsible => 'Collapsible';

  @override
  String get glass => 'Glass Effect';

  @override
  String get appBarType => 'Select the App Bar Type';

  @override
  String get glassActionButton => 'Show the extra button with a glass effect';

  @override
  String get imageCacheDurationDays => 'Number of days to keep images in cache';

  @override
  String get login => 'Login';

  @override
  String get restoreSettings => 'Restore settings';

  @override
  String get backupSettings => 'Backup settings';

  @override
  String get backupSettingsDescription =>
      'Backup all settings including feed settings';

  @override
  String get backupError => 'Failed to create backup.';

  @override
  String get saveHeader => 'Save Header';

  @override
  String get confirmRestore => 'Confirm restore';

  @override
  String get confirmRestoreOverride =>
      'This will overwrite your current settings and feed configurations.';

  @override
  String get file => 'File';

  @override
  String get backupType => 'Backup-Type';

  @override
  String get createdAt => 'Created at';

  @override
  String get appVersion => 'App version';

  @override
  String get restore => 'Restore';

  @override
  String get backupCheckFailed => 'Backup check failed';

  @override
  String get invalidFile => 'The selected file is invalid.';

  @override
  String get fileSelectionFailed => 'The file selection failed';

  @override
  String get backupSuccessfullyRestored => 'Backup successfully restored';

  @override
  String get restoreFailed => 'Restore failed';

  @override
  String get selectZipBackupFile =>
      'Select a ZIP backup file to restore settings.';

  @override
  String get selectZipBackupFileButton => 'Select ZIP file and restore';

  @override
  String get minimumFeedSelection => 'Please select at least one feed.';

  @override
  String get feedCreationError => 'Creation failed.';

  @override
  String get feedSelection => 'Select feed';

  @override
  String get feedCreationDuration => 'Creating...';

  @override
  String get feedCreationDescription =>
      'Select multiple feeds. The selected feeds will be created in your Miniflux account.';

  @override
  String get feedSelectionSelectAll => 'Select all';

  @override
  String get feedSelectionDeleteSelection => 'Clear selection';

  @override
  String get downloadsManagerDeleteTitle => 'Delete Download?';

  @override
  String get downloadsManagerDeleteMessage =>
      'Are you sure you want to delete this download?';

  @override
  String get downloadsManagerDeletedSnackbar => 'Download deleted';

  @override
  String get downloadsManagerClearAllTitle => 'Delete all downloads?';

  @override
  String get downloadsManagerClearAllMessage =>
      'This will delete all downloaded audio files. This action cannot be undone.';

  @override
  String get downloadsManagerClearedSnackbar => 'All downloads deleted';

  @override
  String get downloadsManagerClearAll => 'Delete all downloads';

  @override
  String get audioDownloadsSettings => 'Podcasts';

  @override
  String get audioDownloadsSettingsDescription =>
      'View active downloads and downloaded data';

  @override
  String get deleteDownloadAfterFinishing =>
      'Automatically delete downloads after listening';

  @override
  String get downloadAudioWLAN => 'Download audio via Wi-Fi only';

  @override
  String get autoDownloadAudio => 'Auto-download audio after sync';

  @override
  String get audioDownloadRetentionDays =>
      'Number of days to keep audio downloads';

  @override
  String get chapterFrom => 'Chapter from';

  @override
  String get downloadWLANWarning =>
      'Downloads allowed via Wi-Fi only. Please enable Wi-Fi.';

  @override
  String get noAudioFileAvailable => 'No audio file available.';

  @override
  String get sleepTimerNotification =>
      'Sleep Timer: Playback stopped automatically.';

  @override
  String get sleepTimerOff => 'Sleep Timer: Off';

  @override
  String get sleepTimerEndingSoon => 'Sleep Timer: Ending soon';

  @override
  String get sleepTimerActive => 'Sleep Timer: active';

  @override
  String get sleepTimerRemaining => 'min remaining';

  @override
  String get downloaded => 'Downloaded';

  @override
  String get downloadAudio => 'Download Audio';

  @override
  String get speed => 'Speed';

  @override
  String get chapters => 'Chapters';

  @override
  String get interval => 'Interval';

  @override
  String get minutes => 'min';

  @override
  String get pause => 'Pause';

  @override
  String get play => 'Play';

  @override
  String get resume => 'Resume';

  @override
  String get stop => 'Stop';

  @override
  String get runningDownloads => 'Running downloads';

  @override
  String get noActiveDownloads => 'No active downloads.';

  @override
  String get from => 'from';

  @override
  String get loaded => 'loaded';

  @override
  String get downloadedData => 'Downloaded audio files';

  @override
  String get totalStorage => 'Total storage';

  @override
  String get loadDownloadedDataError => 'Failed to load downloaded files.';

  @override
  String get noAudioDownloads => 'No audio files downloaded yet.';

  @override
  String get fileList => 'Episodes';

  @override
  String get useAudioPlayer => 'Open audio items with audio player';

  @override
  String get showPlayerDetails => 'Show player details';

  @override
  String get hidePlayerDetails => 'Hide player details';

  @override
  String get advancedSettings => 'Advanced Settings';

  @override
  String get loadingChapters => 'Loading chapters ...';

  @override
  String get noChaptersFound => 'No chapters found.';

  @override
  String get autoDeleteDownloadAfterFinish =>
      'Automatically delete audio downloads when finished';

  @override
  String get downloadStarted => 'Download started';

  @override
  String get showLogs => 'Show Logs';

  @override
  String get reload => 'Reload';

  @override
  String get clearList => 'Clear list';

  @override
  String get loading => 'loading...';

  @override
  String get noEntries => 'No entries';

  @override
  String get copyClipboard => 'Copy to clipboard';

  @override
  String get last => 'last';

  @override
  String get cancelAll => 'Cancel all';
}
