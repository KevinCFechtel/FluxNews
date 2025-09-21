import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'flux_news_localizations_de.dart';
import 'flux_news_localizations_en.dart';
import 'flux_news_localizations_nl.dart';
import 'flux_news_localizations_tr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/flux_news_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('nl'),
    Locale('tr')
  ];

  /// No description provided for @fluxNews.
  ///
  /// In en, this message translates to:
  /// **'Flux News'**
  String get fluxNews;

  /// No description provided for @minifluxServer.
  ///
  /// In en, this message translates to:
  /// **'Miniflux Server'**
  String get minifluxServer;

  /// No description provided for @allNews.
  ///
  /// In en, this message translates to:
  /// **'All News'**
  String get allNews;

  /// No description provided for @noNewEntries.
  ///
  /// In en, this message translates to:
  /// **'No new news'**
  String get noNewEntries;

  /// No description provided for @deleteBookmark.
  ///
  /// In en, this message translates to:
  /// **'Delete Bookmark'**
  String get deleteBookmark;

  /// No description provided for @addBookmark.
  ///
  /// In en, this message translates to:
  /// **'Add Bookmark'**
  String get addBookmark;

  /// No description provided for @markAsRead.
  ///
  /// In en, this message translates to:
  /// **'Mark as read'**
  String get markAsRead;

  /// No description provided for @markAsUnread.
  ///
  /// In en, this message translates to:
  /// **'Mark as unread'**
  String get markAsUnread;

  /// No description provided for @showUnread.
  ///
  /// In en, this message translates to:
  /// **'Show unread news'**
  String get showUnread;

  /// No description provided for @showRead.
  ///
  /// In en, this message translates to:
  /// **'Show all news'**
  String get showRead;

  /// No description provided for @settingsNotSet.
  ///
  /// In en, this message translates to:
  /// **'Settings not set'**
  String get settingsNotSet;

  /// No description provided for @provideMinifluxCredentials.
  ///
  /// In en, this message translates to:
  /// **'Please provide miniflux URL and API-Key'**
  String get provideMinifluxCredentials;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'Ok'**
  String get ok;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @always.
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get always;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @minifluxSettings.
  ///
  /// In en, this message translates to:
  /// **'Miniflux Settings'**
  String get minifluxSettings;

  /// No description provided for @apiUrl.
  ///
  /// In en, this message translates to:
  /// **'API Url'**
  String get apiUrl;

  /// No description provided for @apiKey.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get apiKey;

  /// No description provided for @minifluxVersion.
  ///
  /// In en, this message translates to:
  /// **'Miniflux Version'**
  String get minifluxVersion;

  /// No description provided for @brightnesMode.
  ///
  /// In en, this message translates to:
  /// **'Brightness mode'**
  String get brightnesMode;

  /// No description provided for @sortOrderOfNews.
  ///
  /// In en, this message translates to:
  /// **'Sort order of News'**
  String get sortOrderOfNews;

  /// No description provided for @markAsReadOnScrollover.
  ///
  /// In en, this message translates to:
  /// **'Mark as read on scrollover'**
  String get markAsReadOnScrollover;

  /// No description provided for @amountSaved.
  ///
  /// In en, this message translates to:
  /// **'Amount of News which should be saved'**
  String get amountSaved;

  /// No description provided for @amountSavedStarred.
  ///
  /// In en, this message translates to:
  /// **'Amount of starred News which should be saved'**
  String get amountSavedStarred;

  /// No description provided for @titleURL.
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get titleURL;

  /// No description provided for @enterURL.
  ///
  /// In en, this message translates to:
  /// **'Enter the URL'**
  String get enterURL;

  /// No description provided for @enterValidURL.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid Miniflux URL with trailing slash'**
  String get enterValidURL;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @enterAPIKey.
  ///
  /// In en, this message translates to:
  /// **'Enter the API Key:'**
  String get enterAPIKey;

  /// No description provided for @titleAPIKey.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get titleAPIKey;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @newestFirst.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get newestFirst;

  /// No description provided for @oldestFirst.
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get oldestFirst;

  /// No description provided for @communicateionMinifluxError.
  ///
  /// In en, this message translates to:
  /// **'Error while communicating with the miniflux server'**
  String get communicateionMinifluxError;

  /// No description provided for @databaseError.
  ///
  /// In en, this message translates to:
  /// **'Error occurred while processing the data'**
  String get databaseError;

  /// No description provided for @authError.
  ///
  /// In en, this message translates to:
  /// **'Error authenticating against miniflux'**
  String get authError;

  /// No description provided for @generalSettings.
  ///
  /// In en, this message translates to:
  /// **'General Settings'**
  String get generalSettings;

  /// No description provided for @syncOnStart.
  ///
  /// In en, this message translates to:
  /// **'Sync News on startup'**
  String get syncOnStart;

  /// No description provided for @bookmarked.
  ///
  /// In en, this message translates to:
  /// **'Bookmarked'**
  String get bookmarked;

  /// No description provided for @itemCount.
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get itemCount;

  /// No description provided for @multilineAppBarTextSetting.
  ///
  /// In en, this message translates to:
  /// **'Show newscount in Appbar'**
  String get multilineAppBarTextSetting;

  /// No description provided for @showFeedIconsTextSettings.
  ///
  /// In en, this message translates to:
  /// **'Show feed icons'**
  String get showFeedIconsTextSettings;

  /// No description provided for @descriptionMinifluxApp.
  ///
  /// In en, this message translates to:
  /// **'This is a simple Newsreader to work with miniflux.\nFor more information about miniflux, visit the projekt page:'**
  String get descriptionMinifluxApp;

  /// No description provided for @descriptionMoreInformation.
  ///
  /// In en, this message translates to:
  /// **'For more information about this app, visit the project page:'**
  String get descriptionMoreInformation;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search...'**
  String get searchHint;

  /// No description provided for @emptySearch.
  ///
  /// In en, this message translates to:
  /// **'No News found'**
  String get emptySearch;

  /// No description provided for @exportLogs.
  ///
  /// In en, this message translates to:
  /// **'Export debug logs'**
  String get exportLogs;

  /// No description provided for @debugModeTextSettings.
  ///
  /// In en, this message translates to:
  /// **'Activate debug mode'**
  String get debugModeTextSettings;

  /// No description provided for @deleteLocalCache.
  ///
  /// In en, this message translates to:
  /// **'Clear local news storage'**
  String get deleteLocalCache;

  /// No description provided for @deleteLocalCacheDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete local cache'**
  String get deleteLocalCacheDialogTitle;

  /// No description provided for @deleteLocalCacheDialogContent.
  ///
  /// In en, this message translates to:
  /// **'Do you really want to delete the local news storage?'**
  String get deleteLocalCacheDialogContent;

  /// No description provided for @contextSaveButton.
  ///
  /// In en, this message translates to:
  /// **'Save news to third party'**
  String get contextSaveButton;

  /// No description provided for @insecureMinifluxURL.
  ///
  /// In en, this message translates to:
  /// **'An insecure connection to miniflux is used!'**
  String get insecureMinifluxURL;

  /// No description provided for @longSyncWarning.
  ///
  /// In en, this message translates to:
  /// **'The number of messages leads to slow synchronization!'**
  String get longSyncWarning;

  /// No description provided for @longSyncHeader.
  ///
  /// In en, this message translates to:
  /// **'Slow synchronization'**
  String get longSyncHeader;

  /// No description provided for @tooManyNews.
  ///
  /// In en, this message translates to:
  /// **'The number of messages exceeds the limit of 10,000, so synchronization is not possible.\nPlease reduce the amount of synced news.'**
  String get tooManyNews;

  /// No description provided for @markAllAsRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all news as read'**
  String get markAllAsRead;

  /// No description provided for @markBookmarkedAsRead.
  ///
  /// In en, this message translates to:
  /// **'Mark bookmarked news as read'**
  String get markBookmarkedAsRead;

  /// No description provided for @markCategoryAsRead.
  ///
  /// In en, this message translates to:
  /// **'Mark category as read'**
  String get markCategoryAsRead;

  /// No description provided for @markFeedAsRead.
  ///
  /// In en, this message translates to:
  /// **'Mark feed as read'**
  String get markFeedAsRead;

  /// No description provided for @amountOfSyncedNews.
  ///
  /// In en, this message translates to:
  /// **'Amount of News which should be synced'**
  String get amountOfSyncedNews;

  /// No description provided for @amountOfSearchedNews.
  ///
  /// In en, this message translates to:
  /// **'Amount of News which should be searched'**
  String get amountOfSearchedNews;

  /// No description provided for @debugSettings.
  ///
  /// In en, this message translates to:
  /// **'Debug Settings'**
  String get debugSettings;

  /// No description provided for @truncateSettings.
  ///
  /// In en, this message translates to:
  /// **'Truncate Settings'**
  String get truncateSettings;

  /// No description provided for @activateTruncate.
  ///
  /// In en, this message translates to:
  /// **'Truncate news text'**
  String get activateTruncate;

  /// No description provided for @truncateMode.
  ///
  /// In en, this message translates to:
  /// **'Truncate Mode'**
  String get truncateMode;

  /// No description provided for @truncateModeAll.
  ///
  /// In en, this message translates to:
  /// **'Truncate all news'**
  String get truncateModeAll;

  /// No description provided for @truncateModeScraper.
  ///
  /// In en, this message translates to:
  /// **'Truncate all news from feeds with original content fetched'**
  String get truncateModeScraper;

  /// No description provided for @truncateModeManual.
  ///
  /// In en, this message translates to:
  /// **'Truncate all news from feeds which has been selected manually in the feed settings'**
  String get truncateModeManual;

  /// No description provided for @charactersToTruncate.
  ///
  /// In en, this message translates to:
  /// **'Amount of characters to which the text is truncated'**
  String get charactersToTruncate;

  /// No description provided for @charactersToTruncateLimit.
  ///
  /// In en, this message translates to:
  /// **'Amount of characters from which the text is truncated'**
  String get charactersToTruncateLimit;

  /// No description provided for @manualTruncate.
  ///
  /// In en, this message translates to:
  /// **'Truncate news'**
  String get manualTruncate;

  /// No description provided for @successfullSaveToThirdParty.
  ///
  /// In en, this message translates to:
  /// **'The news was successfully saved!'**
  String get successfullSaveToThirdParty;

  /// No description provided for @addBookmarkShort.
  ///
  /// In en, this message translates to:
  /// **'Add Bookmark'**
  String get addBookmarkShort;

  /// No description provided for @bookmarkShort.
  ///
  /// In en, this message translates to:
  /// **'Bookmark'**
  String get bookmarkShort;

  /// No description provided for @saveShort.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveShort;

  /// No description provided for @readShort.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get readShort;

  /// No description provided for @unreadShort.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get unreadShort;

  /// No description provided for @leftSwipeSelectionOption.
  ///
  /// In en, this message translates to:
  /// **'Select action for swiping to the left'**
  String get leftSwipeSelectionOption;

  /// No description provided for @rightSwipeSelectionOption.
  ///
  /// In en, this message translates to:
  /// **'Select action for swiping to the right'**
  String get rightSwipeSelectionOption;

  /// No description provided for @secondLeftSwipeSelectionOption.
  ///
  /// In en, this message translates to:
  /// **'Select second action for swiping to the left'**
  String get secondLeftSwipeSelectionOption;

  /// No description provided for @secondRightSwipeSelectionOption.
  ///
  /// In en, this message translates to:
  /// **'Select second action for swiping to the right'**
  String get secondRightSwipeSelectionOption;

  /// No description provided for @deleteBookmarkShort.
  ///
  /// In en, this message translates to:
  /// **'Delete bookmark'**
  String get deleteBookmarkShort;

  /// No description provided for @activateSwiping.
  ///
  /// In en, this message translates to:
  /// **'Activate swipe gestures'**
  String get activateSwiping;

  /// No description provided for @feedSettings.
  ///
  /// In en, this message translates to:
  /// **'Feed settings'**
  String get feedSettings;

  /// No description provided for @emptyFeedList.
  ///
  /// In en, this message translates to:
  /// **'No Feeds fetched'**
  String get emptyFeedList;

  /// No description provided for @preferParagraph.
  ///
  /// In en, this message translates to:
  /// **'Prefer first HTML paragraph as news text'**
  String get preferParagraph;

  /// No description provided for @preferAttachmentImage.
  ///
  /// In en, this message translates to:
  /// **'Prefer attachment image as news picture'**
  String get preferAttachmentImage;

  /// No description provided for @manualAdaptLightModeToIcon.
  ///
  /// In en, this message translates to:
  /// **'Manual adapt the light mode to a transparent feed icon'**
  String get manualAdaptLightModeToIcon;

  /// No description provided for @manualAdaptDarkModeToIcon.
  ///
  /// In en, this message translates to:
  /// **'Manual adapt the dark mode to a transparent feed icon'**
  String get manualAdaptDarkModeToIcon;

  /// No description provided for @openMinifluxEntry.
  ///
  /// In en, this message translates to:
  /// **'Open news in miniflux webinterface'**
  String get openMinifluxEntry;

  /// No description provided for @openMinifluxShort.
  ///
  /// In en, this message translates to:
  /// **'Open in miniflux'**
  String get openMinifluxShort;

  /// No description provided for @scrollHorizontal.
  ///
  /// In en, this message translates to:
  /// **'Scroll horizontal'**
  String get scrollHorizontal;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @floatingActionButton.
  ///
  /// In en, this message translates to:
  /// **'Use an extra button to mark all messages as read'**
  String get floatingActionButton;

  /// No description provided for @useBlackMode.
  ///
  /// In en, this message translates to:
  /// **'Enable black mode specifically for OLED displays'**
  String get useBlackMode;

  /// No description provided for @expand.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get expand;

  /// No description provided for @menu.
  ///
  /// In en, this message translates to:
  /// **'Action Menu'**
  String get menu;

  /// No description provided for @tabActionSettings.
  ///
  /// In en, this message translates to:
  /// **'Select action for tapping on a news item'**
  String get tabActionSettings;

  /// No description provided for @longPressActionSettings.
  ///
  /// In en, this message translates to:
  /// **'Select action for long press on a news item'**
  String get longPressActionSettings;

  /// No description provided for @expandedWithFulltext.
  ///
  /// In en, this message translates to:
  /// **'Show only text instead of HTML when expanding the news content'**
  String get expandedWithFulltext;

  /// No description provided for @showHeadlineOnTop.
  ///
  /// In en, this message translates to:
  /// **'Show the headline of the news above the image'**
  String get showHeadlineOnTop;

  /// No description provided for @showOnlyFeedCategoriesWithNewNews.
  ///
  /// In en, this message translates to:
  /// **'Only show the categories and feeds that have new messages'**
  String get showOnlyFeedCategoriesWithNewNews;

  /// No description provided for @none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// No description provided for @syncInProgress.
  ///
  /// In en, this message translates to:
  /// **'Sync in progress...'**
  String get syncInProgress;

  /// No description provided for @startupCategorie.
  ///
  /// In en, this message translates to:
  /// **'Choose Categorie for startup'**
  String get startupCategorie;

  /// No description provided for @startupCategorieAll.
  ///
  /// In en, this message translates to:
  /// **'Show all news on startup'**
  String get startupCategorieAll;

  /// No description provided for @startupCategorieBookmarks.
  ///
  /// In en, this message translates to:
  /// **'Show the bookmark categorie on startup'**
  String get startupCategorieBookmarks;

  /// No description provided for @startupCategorieCategorie.
  ///
  /// In en, this message translates to:
  /// **'Choose a Categorie as default for startup'**
  String get startupCategorieCategorie;

  /// No description provided for @startupCategorieFeed.
  ///
  /// In en, this message translates to:
  /// **'Choose a feed as default for startup'**
  String get startupCategorieFeed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en', 'nl', 'tr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'nl':
      return AppLocalizationsNl();
    case 'tr':
      return AppLocalizationsTr();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
