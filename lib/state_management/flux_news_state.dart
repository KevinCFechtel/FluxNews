import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as sec_store;
import 'package:flux_news/functions/logging.dart';
import 'package:flux_news/state_management/flux_news_theme_state.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path_package;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../models/news_model.dart';

// generate android options to usw with flutter secure storage
sec_store.AndroidOptions _getAndroidOptions() => const sec_store.AndroidOptions(
      keyCipherAlgorithm: sec_store.KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
      storageCipherAlgorithm: sec_store.StorageCipherAlgorithm.AES_GCM_NoPadding,
    );

class FluxNewsState extends ChangeNotifier {
  // init the persistent flutter secure storage
  final storage = sec_store.FlutterSecureStorage(
    aOptions: _getAndroidOptions(),
    iOptions: const sec_store.IOSOptions(
      accessibility: sec_store.KeychainAccessibility.first_unlock,
    ),
  );

  // define static const variables to replace text within code
  static const String applicationName = 'Flux News';
  static const String applicationVersion = '1.17.0';
  static const String applicationLegalese = '\u{a9} 2023 Kevin Fechtel';
  static const String applicationProjectUrl = ' https://github.com/KevinCFechtel/FluxNews';
  static const String miniFluxProjectUrl = ' https://miniflux.app';
  static const String databasePathString = 'news_database.db';
  static const String androidDatabaseDirectory = 'databases';
  static const String rootRouteString = '/';
  static const String welcomeRouteString = '/welcome';
  static const String loginRouteString = '/login';
  static const String feedOnboardingRouteString = '/feedOnboarding';
  static const String restoreSettingsRouteString = '/restoreSettings';
  static const String settingsRouteString = '/settings';
  static const String searchRouteString = '/search';
  static const String feedSettingsRouteString = '/feedSettings';
  static const String generalSettingsRouteString = '/generalSettings';
  static const String syncSettingsRouteString = '/syncSettings';
  static const String newsItemSettingsRouteString = '/newsItemSettings';
  static const String truncateSettingsRouteString = '/truncateSettings';
  static const String headerSettingsRouteString = '/headerSettings';
  static const int amountOfNewlyCaughtNews = 1000;
  static const String unreadNewsStatus = 'unread';
  static const String readNewsStatus = 'read';
  static const String syncedSyncStatus = 'synced';
  static const String notSyncedSyncStatus = 'notSynced';
  static const String allNewsString = 'all';
  static const String databaseAllString = '%';
  static const String databaseDescString = 'DESC';
  static const String databaseAscString = 'ASC';
  static const String minifluxDescString = 'desc';
  static const String minifluxAscString = 'asc';
  static const String brightnessModeSystemString = 'System';
  static const String brightnessModeDarkString = 'Dark';
  static const String brightnessModeLightString = 'Light';
  static const String sortOrderNewestFirstString = 'Newest first';
  static const String sortOrderOldestFirstString = 'Oldest first';
  static const String secureStorageMinifluxURLKey = 'minifluxURL';
  static const String secureStorageMinifluxAPIKey = 'minifluxAPIKey';
  static const String secureStorageMinifluxVersionKey = 'minifluxVersionKey';
  static const String secureStorageBrightnessModeKey = 'brightnessMode';
  static const String secureStorageAmountOfSyncedNewsKey = 'amountOfSyncedNews';
  static const String secureStorageAmountOfSearchedNewsKey = 'amountOfSearchedNews';
  static const String secureStorageSortOrderKey = 'sortOrder';
  static const String secureStorageSavedScrollPositionKey = 'savedScrollPosition';
  static const String secureStorageMarkAsReadOnScrollOverKey = 'markAsReadOnScrollOver';
  static const String secureStorageSyncOnStartKey = 'syncOnStart';
  static const String secureStorageNewsStatusKey = 'newsStatus';
  static const String secureStorageAmountOfSavedNewsKey = 'amountOfSavedNews';
  static const String secureStorageAmountOfSavedStarredNewsKey = 'amountOfSavedStarredNews';
  static const String secureStorageMultilineAppBarTextKey = 'multilineAppBarText';
  static const String secureStorageShowFeedIconsTextKey = 'showFeedIcons';
  static const String secureStorageActivateTruncateKey = 'activateTruncate';
  static const String secureStorageTruncateModeKey = 'truncateMode';
  static const String secureStorageCharactersToTruncateKey = 'charactersToTruncate';
  static const String secureStorageCharactersToTruncateLimitKey = 'charactersToTruncateLimit';
  static const String secureStorageSyncReadNewsKey = 'syncReadNews';
  static const String secureStorageAutoDownloadAudioAfterSyncKey = 'autoDownloadAudioAfterSync';
  static const String secureStorageDownloadAudioOnlyOnWifiKey = 'downloadAudioOnlyOnWifi';
  static const String secureStorageDeleteAudioAfterPlaybackKey = 'deleteAudioAfterPlayback';
  static const String secureStorageAudioDownloadRetentionDaysKey = 'audioDownloadRetentionDays';
  static const String secureStorageOpenAudioItemsInPlayerKey = 'openAudioItemsInPlayer';
  static const String secureStorageSyncReadNewsAfterDaysKey = 'syncReadNewsAfterDays';
  static const String secureStorageDebugModeKey = 'debugMode';
  static const String secureStorageActivateSwipeGesturesKey = 'activateSwiping';
  static const String secureStorageLeftSwipeActionKey = 'leftSwipeAction';
  static const String secureStorageRightSwipeActionKey = 'rightSwipeAction';
  static const String secureStorageSecondLeftSwipeActionKey = 'secondLeftSwipeAction';
  static const String secureStorageSecondRightSwipeActionKey = 'secondRightSwipeAction';
  static const String secureStorageFloatingButtonVisibleKey = 'floatingButtonVisible';
  static const String secureStorageUseBlackModeKey = 'useBlackMode';
  static const String secureStorageTabActionKey = 'tabAction';
  static const String secureStorageLongPressActionKey = 'LongPressAction';
  static const String secureStorageShowHeadlineOnTopKey = 'showHeadlineOnTop';
  static const String secureStorageShowOnlyFeedCategoriesWithNewNeKey = 'showOnlyFeedCategoriesWithNewNews';
  static const String secureStorageStartupCategorieKey = 'startupCategorie';
  static const String secureStorageStartupCategorieSelectionKey = 'startupCategorieSelection';
  static const String secureStorageStartupFeedSelectionKey = 'startupFeedSelection';
  static const String secureStorageRemoveNewsFromListWhenReadKey = 'removeNewsFromListWhenRead';
  static const String secureStorageSkipLongSyncKey = 'skipLongSync';
  static const String secureStorageSyncReadStatusImmediatelyKey = 'syncReadStatusImmediately';
  static const String secureStorageCustomHeadersKeyPrefixKey = 'customHeadersKey_';
  static const String secureStorageCustomHeadersValuePrefixKey = 'customHeadersValue_';
  static const String secureStorageScrolloverAppBarKey = 'scrolloverAppBar';
  static const String secureStorageGlassAppBarKey = 'glassAppBar';
  static const String secureStorageUseSliverAppBarKey = 'useSliverAppBar';
  static const String secureStorageFloatingButtonKey = 'floatingButtonAction';
  static const String secureStorageAppBarTypeKey = 'appBarType';
  static const String secureStorageGlassActionButtonKey = 'glassActionButton';
  static const String secureStorageNetworkImageCacheMigratedKey = 'networkImageCacheMigrated';
  static const String secureStorageImageCacheDurationDaysKey = 'imageCacheDurationDays';
  static const String secureStorageTrueString = 'true';
  static const String secureStorageFalseString = 'false';
  static const String httpUnexpectedResponseErrorString = 'Unexpected response';
  static const String httpContentTypeString = 'application/json; charset=UTF-8';
  static const String httpMinifluxAuthHeaderString = 'X-Auth-Token';
  static const String httpMinifluxAcceptHeaderString = 'Accept';
  static const String httpMinifluxContentTypeHeaderString = 'Content-Type';
  static const String noImageUrlString = 'NoImageUrl';
  static const String contextMenuBookmarkString = 'bookmark';
  static const String contextMenuSaveString = 'saveToThirdParty';
  static const String contextMenuOpenMinifluxString = 'openMiniflux';
  static const String contextMenuOpenString = 'open';
  static const String swipeActionOpenCommentsString = 'openComments';
  static const String swipeActionSaveString = 'saveToThirdParty';
  static const String swipeActionBookmarkString = 'bookmark';
  static const String swipeActionReadUnreadString = 'readUnread';
  static const String swipeActionOpenMinifluxString = 'openMiniflux';
  static const String swipeActionShareString = 'share';
  static const String swipeActionOpenString = 'open';
  static const String swipeActionDownloadString = 'downloadAudio';
  static const String swipeActionNoneString = 'none';
  static const String tabActionOpenString = 'open';
  static const String tabActionExpandString = 'expand';
  static const String tabActionSplittedString = 'splitted';
  static const String longPressActionMenuString = 'menu';
  static const String longPressActionExpandString = 'expand';
  static const String longPressActionNoneString = 'none';
  static const String floatingButtonSyncAction = 'sync';
  static const String floatingButtonMarkAsReadAction = 'markAsRead';
  static const String appBarNormalType = 'normal';
  static const String appBarCollapsedType = 'collapsed';
  static const String appBarGlassType = 'glass';
  static const String cancelContextString = 'Cancel';
  static const String logTag = 'FluxNews';
  static const String logsWriteDirectoryName = "FluxNewsLogs";
  static const String logsExportDirectoryName = "FluxNewsLogs/Exported";
  static const String feedIconFilePath = "/FeedIcons/icon_";
  static const int minifluxSaveMinVersion = 2047;
  static const int amountForTooManyNews = 10000;
  static const int amountForLongNewsSync = 2000;
  static const String apiVersionPath = "v1/";
  static const String minifluxEntryPathPrefix = "unread/feed/";
  static const String minifluxEntryPathSuffix = "/entry/";
  static const String audioProgressKeyPrefix = "audio_progress_";
  static const String androidNotificationChannelId = 'de.kevincfechtel.flux_news.audio';
  static const String androidNotificationChannelName = 'Flux News Audio';
  static const String androidNotificationIcon = 'mipmap/ic_appicon';
  static const String downloadPathKeyPrefix = 'audio_download_path_';
  static const String downloadTimestampKeyPrefix = 'audio_download_ts_';
  static const String defaultArtworkAssetPath = 'assets/Flux_News_Starticon_Blue_IOS.png';
  static const String defaultArtworkFileName = 'default_audio_artwork.png';
  static const String audioCachePath = 'audio_cache';
  static const String audioFilePrefix = 'audio_';
  static const String artworkCacheDirectoryName = 'audio_artwork_cache';
  static const String artworkFilePrefix = 'artwork_';
  static const String downloadPathByUrlKeyPrefix = 'audio_download_path_url_';
  static const String androidDefaultArtworkProviderAuthority = 'de.circle_dev.flux_news.defaultart';
  static const String downloadTitleKeyPrefix = 'flux_download_title_';
  static const String downloadFeedTitleKeyPrefix = 'flux_download_feed_title_';
  static const String urlValidationRegex =
      r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,256}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)';
  /*
  static const String urlValidationRegex =
      r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,256}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)\/v1\/';

  */
  static const String feedElementType = 'feed';
  static const String categoryElementType = 'category';
  static const String allNewsElementType = 'all';
  static const String bookmarkedNewsElementType = 'bookmarked';

  // vars for lists of main view
  late Future<List<News>> newsList;
  late Future<Categories> categoryList;
  late Future<List<Feed>> feedSettingsList;
  List<int>? feedIDs;
  String selectedCategoryElementType = 'all';
  Categories? actualCategoryList;
  bool showOnlyFeedCategoriesWithNewNews = false;

  // vars for main view
  bool syncProcess = false;
  late Offset tapPosition;
  int scrollPosition = 0;
  final ScrollController scrollController = ScrollController();
  final ListController listController = ListController();
  bool floatingButtonVisible = false;
  String floatingButtonAction = FluxNewsState.floatingButtonMarkAsReadAction;
  bool syncNow = false;
  bool startUp = false;

  // vars for search view
  Future<List<News>> searchNewsList = Future<List<News>>.value([]);
  final TextEditingController searchController = TextEditingController();

  // var for formatting the date depending on locale settings
  DateFormat dateFormat = DateFormat('M/d/yy HH:mm');

  // vars for error handling
  String errorString = '';
  bool newError = false;
  bool errorOnMinifluxAuth = false;
  bool tooManyNews = false;
  bool longSync = false;
  bool longSyncAlerted = false;
  bool longSyncAborted = false;

  // vars for debugging
  bool debugMode = false;

  // the initial news status which should be fetched
  String newsStatus = FluxNewsState.unreadNewsStatus;

  // vars for miniflux server connection
  String? minifluxURL;
  String? minifluxAPIKey;
  String? minifluxVersionString;
  int minifluxVersionInt = 0;
  bool insecureMinifluxURL = false;

  // vars for settings
  Map<String, String> storageValues = {};
  KeyValueRecordType? brightnessModeSelection;
  KeyValueRecordType? amontOfSyncedNewsSelection;
  KeyValueRecordType? amontOfSearchedNewsSelection;
  KeyValueRecordType? amountOfCharactersToTruncateLimitSelection;
  KeyValueRecordType? leftSwipeActionSelection;
  KeyValueRecordType? rightSwipeActionSelection;
  KeyValueRecordType? secondLeftSwipeActionSelection;
  KeyValueRecordType? secondRightSwipeActionSelection;
  KeyValueRecordType? tabActionSelection;
  KeyValueRecordType? longPressActionSelection;
  KeyValueRecordType? floatingButtonActionSelection;
  KeyValueRecordType? appBarTypeSelection;
  String? sortOrder = FluxNewsState.sortOrderNewestFirstString;
  int savedScrollPosition = 0;
  int amountOfSavedNews = 1000;
  int amountOfSavedStarredNews = 1000;
  int amountOfSyncedNews = 0;
  int amountOfSearchedNews = 0;
  bool markAsReadOnScrollOver = false;
  bool syncOnStart = false;
  bool multilineAppBarText = false;
  bool showFeedIcons = Platform.isIOS ? true : false;
  List<KeyValueRecordType>? recordTypesBrightnessMode;
  List<KeyValueRecordType>? recordTypesAmountOfSyncedNews;
  List<KeyValueRecordType>? recordTypesAmountOfSearchedNews;
  List<KeyValueRecordType>? recordTypesAmountOfCharactersToTruncateLimit;
  List<KeyValueRecordType>? recordTypesSwipeActions;
  List<KeyValueRecordType>? recordTypesSecondSwipeActions;
  List<KeyValueRecordType>? recordTypesTabActions;
  List<KeyValueRecordType>? recordTypesLongPressActions;
  List<KeyValueRecordType>? recordTypesSyncReadNewsAfterDays;
  List<KeyValueRecordType>? recordTypesFloatingButtonActions;
  List<KeyValueRecordType>? recordTypesAppBarType;
  bool activateTruncate = Platform.isIOS ? true : false;
  int truncateMode = 0;
  int charactersToTruncate = Platform.isIOS ? 300 : 100;
  int charactersToTruncateLimit = 0;
  bool activateSwipeGestures = true;
  String leftSwipeAction = FluxNewsState.swipeActionReadUnreadString;
  String rightSwipeAction = FluxNewsState.swipeActionBookmarkString;
  String secondLeftSwipeAction =
      Platform.isIOS ? FluxNewsState.swipeActionSaveString : FluxNewsState.swipeActionNoneString;
  String secondRightSwipeAction =
      Platform.isIOS ? FluxNewsState.swipeActionShareString : FluxNewsState.swipeActionNoneString;
  String tabAction = Platform.isIOS ? FluxNewsState.tabActionSplittedString : FluxNewsState.tabActionOpenString;
  String longPressAction = FluxNewsState.longPressActionMenuString;
  bool showHeadlineOnTop = false;
  int startupCategorie = 0;
  List<KeyValueRecordType>? recordTypesStartupCategories;
  List<KeyValueRecordType>? recordTypesStartupFeeds;
  KeyValueRecordType? startupCategorieSelection;
  KeyValueRecordType? startupFeedSelection;
  int? startupCategorieSelectionKey;
  int? startupFeedSelectionKey;
  bool categorieStartup = false;
  bool removeNewsFromListWhenRead = false;
  bool openAudioItemsInPlayer = true;
  bool syncReadNews = false;
  bool autoDownloadAudioAfterSync = false;
  bool downloadAudioOnlyOnWifi = false;
  bool deleteAudioAfterPlayback = false;
  int audioDownloadRetentionDays = 30;
  int syncReadNewsAfterDays = 0;
  KeyValueRecordType? syncReadNewsAfterDaysSelection;
  bool skipLongSync = false;
  bool syncReadStatusImmediately = false;
  bool scrolloverSyncFailed = false;
  Map<String, String> customHeaders = {};
  bool scrolloverAppBar = false;
  bool glassAppBar = Platform.isIOS ? true : false;
  bool useSliverAppBar = Platform.isIOS ? true : false;
  String appBarType = Platform.isIOS ? FluxNewsState.appBarGlassType : FluxNewsState.appBarNormalType;
  bool glassActionButton = Platform.isIOS ? true : false;
  bool networkImageCacheMigrated = false;
  int imageCacheDurationDays = 30;

  // vars for app bar text
  String appBarText = '';
  int? selectedID;
  News? activeAudioNews;

  // vars for detecting device orientation and device type
  bool isTablet = false;
  Orientation orientation = Orientation.portrait;

  // the directory for Saving pictures
  Directory? externalDirectory;

  // the database connection as a variable
  Database? db;

  // init the database connection
  Future<Database> initializeDB() async {
    logThis('initializeDB', 'Starting initializeDB', LogLevel.INFO);
    String databasePath = "/";
    databaseFactory = databaseFactoryFfi;
    if (Platform.isIOS) {
      externalDirectory = await getApplicationDocumentsDirectory();
      Directory rootPath = await getLibraryDirectory();
      databasePath = rootPath.path;
    } else if (Platform.isAndroid) {
      externalDirectory = await getExternalStorageDirectory();
      Directory rootPath = await getApplicationSupportDirectory();
      List<String> rootPathElements = rootPath.path.split('/');
      for (int i = 0; i < rootPathElements.length - 1; i++) {
        if (rootPathElements[i].isNotEmpty) {
          databasePath = path_package.join(databasePath, rootPathElements[i]);
        }
      }
      databasePath = path_package.join(databasePath, FluxNewsState.androidDatabaseDirectory);
    }
    logThis('initializeDB', 'Finished initializeDB', LogLevel.INFO);
    return openDatabase(
      path_package.join(databasePath, FluxNewsState.databasePathString),
      onCreate: (db, version) async {
        logThis('initializeDB', 'Starting creating DB', LogLevel.INFO);
        // create the table news
        await db.execute('DROP TABLE IF EXISTS news');
        await db.execute(
          '''CREATE TABLE news(newsID INTEGER PRIMARY KEY, 
                          feedID INTEGER, 
                          title TEXT, 
                          url TEXT,
                          commentsUrl TEXT,
                          shareCode TEXT, 
                          content TEXT, 
                          hash TEXT, 
                          publishedAt TEXT, 
                          createdAt TEXT, 
                          status TEXT, 
                          readingTime INTEGER, 
                          starred INTEGER, 
                          feedTitle TEXT, 
                          syncStatus TEXT)''',
        );
        // create the table categories
        await db.execute('DROP TABLE IF EXISTS categories');
        await db.execute(
          '''CREATE TABLE categories(categoryID INTEGER PRIMARY KEY, 
                          title TEXT)''',
        );
        // create the table feeds
        await db.execute('DROP TABLE IF EXISTS feeds');
        await db.execute(
          '''CREATE TABLE feeds(feedID INTEGER PRIMARY KEY, 
                          title TEXT, 
                          site_url TEXT, 
                          iconMimeType TEXT,
                          iconID INTEGER,
                          newsCount INTEGER,
                          crawler INTEGER,
                          manualTruncate INTEGER,
                          preferParagraph INTEGER,
                          preferAttachmentImage INTEGER,
                          manualAdaptLightModeToIcon INTEGER,
                          manualAdaptDarkModeToIcon INTEGER,
                          openMinifluxEntry INTEGER,
                          expandedWithFulltext INTEGER,
                          expandedFulltextLimit INTEGER,
                          categoryID INTEGER)''',
        );
        // create the table attachments
        await db.execute('DROP TABLE IF EXISTS attachments');
        await db.execute(
          '''CREATE TABLE attachments(attachmentID INTEGER PRIMARY KEY, 
                          newsID INTEGER, 
                          attachmentURL TEXT, 
                          attachmentMimeType TEXT,
                          mediaProgression INTEGER NOT NULL DEFAULT 0)''',
        );

        logThis('initializeDB', 'Finished creating DB', LogLevel.INFO);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        logThis('upgradeDB', 'Starting upgrading DB', LogLevel.INFO);
        if (oldVersion == 1) {
          logThis('upgradeDB', 'Upgrading DB from version 1', LogLevel.INFO);

          // create the table attachments
          await db.execute('DROP TABLE IF EXISTS attachments');
          await db.execute(
            '''CREATE TABLE attachments(attachmentID INTEGER PRIMARY KEY, 
                          newsID INTEGER, 
                          attachmentURL TEXT, 
                          attachmentMimeType TEXT,
                          mediaProgression INTEGER NOT NULL DEFAULT 0)''',
          );
          await db.execute(
            '''ALTER TABLE "categories" 
                     RENAME COLUMN "categorieID" TO "categoryID";''',
          );
          await db.execute(
            '''ALTER TABLE "feeds" 
                     RENAME COLUMN "categorieID" TO "categoryID";''',
          );
        } else if (oldVersion == 2) {
          logThis('upgradeDB', 'Upgrading DB from version 2', LogLevel.INFO);

          await db.execute(
            '''ALTER TABLE "categories" 
                     RENAME COLUMN "categorieID" TO "categoryID";''',
          );
          await db.execute(
            '''ALTER TABLE "feeds" 
                     RENAME COLUMN "categorieID" TO "categoryID";''',
          );
        } else if (oldVersion == 3) {
          logThis('upgradeDB', 'Upgrading DB from version 3', LogLevel.INFO);

          // create the table feeds
          await db.execute('DROP TABLE IF EXISTS feeds');
          await db.execute(
            '''CREATE TABLE feeds(feedID INTEGER PRIMARY KEY, 
                          title TEXT, 
                          site_url TEXT, 
                          iconMimeType TEXT,
                          newsCount INTEGER,
                          crawler INTEGER,
                          manualTruncate INTEGER,
                          categoryID INTEGER)''',
          );
        } else if (oldVersion == 4) {
          logThis('upgradeDB', 'Upgrading DB from version 4', LogLevel.INFO);

          await db.execute(
            '''CREATE TABLE tempFeeds(feedID INTEGER PRIMARY KEY, 
                          title TEXT, 
                          site_url TEXT, 
                          iconMimeType TEXT,
                          newsCount INTEGER,
                          crawler INTEGER,
                          manualTruncate INTEGER,
                          preferParagraph INTEGER,
                          preferAttachmentImage INTEGER,
                          manualAdaptLightModeToIcon INTEGER,
                          manualAdaptDarkModeToIcon INTEGER,
                          openMinifluxEntry INTEGER,
                          categoryID INTEGER)''',
          );

          await db.execute('''insert into tempFeeds (feedID, 
                                        title,
                                        site_url, 
                                        iconMimeType,
                                        newsCount,
                                        crawler,
                                        manualTruncate,
                                        preferParagraph,
                                        preferAttachmentImage,
                                        manualAdaptLightModeToIcon,
                                        manualAdaptDarkModeToIcon,
                                        openMinifluxEntry,
                                        categoryID) 
                 select feedID, 
                        title,
                        site_url, 
                        iconMimeType,
                        newsCount,
                        crawler,
                        manualTruncate,
                        0 AS preferParagraph,
                        0 AS preferAttachmentImage,
                        0 AS manualAdaptLightModeToIcon,
                        0 AS manualAdaptDarkModeToIcon,
                        0 AS openMinifluxEntry,
                        categoryID  
                  from feeds;''');

          // create the table feeds
          await db.execute('DROP TABLE IF EXISTS feeds');
          await db.execute(
            '''CREATE TABLE feeds(feedID INTEGER PRIMARY KEY, 
                          title TEXT, 
                          site_url TEXT, 
                          iconMimeType TEXT,
                          newsCount INTEGER,
                          crawler INTEGER,
                          manualTruncate INTEGER,
                          preferParagraph INTEGER,
                          preferAttachmentImage INTEGER,
                          manualAdaptLightModeToIcon INTEGER,
                          manualAdaptDarkModeToIcon INTEGER,
                          openMinifluxEntry INTEGER,
                          categoryID INTEGER)''',
          );

          await db.execute('''insert into feeds (feedID, 
                                        title,
                                        site_url, 
                                        iconMimeType,
                                        newsCount,
                                        crawler,
                                        manualTruncate,
                                        preferParagraph,
                                        preferAttachmentImage,
                                        manualAdaptLightModeToIcon,
                                        manualAdaptDarkModeToIcon,
                                        openMinifluxEntry,
                                        categoryID) 
                 select feedID, 
                        title,
                        site_url, 
                        iconMimeType,
                        newsCount,
                        crawler,
                        manualTruncate,
                        preferParagraph,
                        preferAttachmentImage,
                        manualAdaptLightModeToIcon,
                        manualAdaptDarkModeToIcon,
                        openMinifluxEntry,
                        categoryID  
                  from tempFeeds;''');
          await db.execute('DROP TABLE IF EXISTS tempFeeds');

          await db.execute(
            '''CREATE TABLE tempNews(newsID INTEGER PRIMARY KEY, 
                            feedID INTEGER, 
                            title TEXT, 
                            url TEXT,
                            commentsUrl TEXT,
                            shareCode TEXT, 
                            content TEXT, 
                            hash TEXT, 
                            publishedAt TEXT, 
                            createdAt TEXT, 
                            status TEXT, 
                            readingTime INTEGER, 
                            starred INTEGER, 
                            feedTitle TEXT, 
                            syncStatus TEXT)''',
          );

          await db.execute('''insert into tempNews (newsID, 
                                                    feedID, 
                                                    title, 
                                                    url,
                                                    commentsUrl,
                                                    shareCode, 
                                                    content, 
                                                    hash, 
                                                    publishedAt, 
                                                    createdAt, 
                                                    status, 
                                                    readingTime, 
                                                    starred, 
                                                    feedTitle, 
                                                    syncStatus) 
                 select newsID, 
                            feedID, 
                            title, 
                            url,
                            '' AS commentsUrl,
                            '' AS shareCode, 
                            content, 
                            hash, 
                            publishedAt, 
                            createdAt, 
                            status, 
                            readingTime, 
                            starred, 
                            feedTitle, 
                            syncStatus  
                  from news;''');

          // create the table feeds
          await db.execute('DROP TABLE IF EXISTS news');
          await db.execute(
            '''CREATE TABLE news(newsID INTEGER PRIMARY KEY, 
                            feedID INTEGER, 
                            title TEXT, 
                            url TEXT,
                            commentsUrl TEXT,
                            shareCode TEXT, 
                            content TEXT, 
                            hash TEXT, 
                            publishedAt TEXT, 
                            createdAt TEXT, 
                            status TEXT, 
                            readingTime INTEGER, 
                            starred INTEGER, 
                            feedTitle TEXT, 
                            syncStatus TEXT)''',
          );

          await db.execute('''insert into news (newsID, 
                                                feedID, 
                                                title, 
                                                url,
                                                commentsUrl,
                                                shareCode, 
                                                content, 
                                                hash, 
                                                publishedAt, 
                                                createdAt, 
                                                status, 
                                                readingTime, 
                                                starred, 
                                                feedTitle, 
                                                syncStatus) 
                 select newsID, 
                        feedID, 
                        title, 
                        url,
                        commentsUrl,
                        shareCode, 
                        content, 
                        hash, 
                        publishedAt, 
                        createdAt, 
                        status, 
                        readingTime, 
                        starred, 
                        feedTitle, 
                        syncStatus 
                  from tempNews;''');
          await db.execute('DROP TABLE IF EXISTS tempNews');
          await db.execute(
            '''ALTER TABLE attachments ADD COLUMN mediaProgression INTEGER NOT NULL DEFAULT 0''',
          );
        } else if (oldVersion == 5) {
          logThis('upgradeDB', 'Upgrading DB from version 5', LogLevel.INFO);

          await db.execute(
            '''CREATE TABLE tempFeeds(feedID INTEGER PRIMARY KEY, 
                          title TEXT, 
                          site_url TEXT, 
                          iconMimeType TEXT,
                          iconID INTEGER,
                          newsCount INTEGER,
                          crawler INTEGER,
                          manualTruncate INTEGER,
                          preferParagraph INTEGER,
                          preferAttachmentImage INTEGER,
                          manualAdaptLightModeToIcon INTEGER,
                          manualAdaptDarkModeToIcon INTEGER,
                          openMinifluxEntry INTEGER,
                          expandedWithFulltext INTEGER,
                          expandedFulltextLimit INTEGER,
                          categoryID INTEGER)''',
          );

          await db.execute('''insert into tempFeeds (feedID, 
                                        title,
                                        site_url, 
                                        iconMimeType,
                                        iconID,
                                        newsCount,
                                        crawler,
                                        manualTruncate,
                                        preferParagraph,
                                        preferAttachmentImage,
                                        manualAdaptLightModeToIcon,
                                        manualAdaptDarkModeToIcon,
                                        openMinifluxEntry,
                                        expandedWithFulltext,
                                        expandedFulltextLimit,
                                        categoryID) 
                 select feedID, 
                        title,
                        site_url, 
                        iconMimeType,
                        0 AS iconID,
                        newsCount,
                        crawler,
                        manualTruncate,
                        preferParagraph,
                        preferAttachmentImage,
                        manualAdaptLightModeToIcon,
                        manualAdaptDarkModeToIcon,
                        openMinifluxEntry,
                        0 AS expandedWithFulltext,
                        0 AS expandedFulltextLimit,
                        categoryID  
                  from feeds;''');

          // create the table feeds
          await db.execute('DROP TABLE IF EXISTS feeds');
          await db.execute(
            '''CREATE TABLE feeds(feedID INTEGER PRIMARY KEY, 
                          title TEXT, 
                          site_url TEXT, 
                          iconMimeType TEXT,
                          iconID INTEGER,
                          newsCount INTEGER,
                          crawler INTEGER,
                          manualTruncate INTEGER,
                          preferParagraph INTEGER,
                          preferAttachmentImage INTEGER,
                          manualAdaptLightModeToIcon INTEGER,
                          manualAdaptDarkModeToIcon INTEGER,
                          openMinifluxEntry INTEGER,
                          expandedWithFulltext INTEGER,
                          expandedFulltextLimit INTEGER,
                          categoryID INTEGER)''',
          );

          await db.execute('''insert into feeds (feedID, 
                                        title,
                                        site_url, 
                                        iconMimeType,
                                        iconID,
                                        newsCount,
                                        crawler,
                                        manualTruncate,
                                        preferParagraph,
                                        preferAttachmentImage,
                                        manualAdaptLightModeToIcon,
                                        manualAdaptDarkModeToIcon,
                                        openMinifluxEntry,
                                        expandedWithFulltext,
                                        expandedFulltextLimit,
                                        categoryID) 
                 select feedID, 
                        title,
                        site_url, 
                        iconMimeType,
                        iconID,
                        newsCount,
                        crawler,
                        manualTruncate,
                        preferParagraph,
                        preferAttachmentImage,
                        manualAdaptLightModeToIcon,
                        manualAdaptDarkModeToIcon,
                        openMinifluxEntry,
                        expandedWithFulltext,
                        expandedFulltextLimit,
                        categoryID  
                  from tempFeeds;''');
          await db.execute('DROP TABLE IF EXISTS tempFeeds');

          await db.execute(
            '''CREATE TABLE tempNews(newsID INTEGER PRIMARY KEY, 
                            feedID INTEGER, 
                            title TEXT, 
                            url TEXT,
                            commentsUrl TEXT,
                            shareCode TEXT, 
                            content TEXT, 
                            hash TEXT, 
                            publishedAt TEXT, 
                            createdAt TEXT, 
                            status TEXT, 
                            readingTime INTEGER, 
                            starred INTEGER, 
                            feedTitle TEXT, 
                            syncStatus TEXT)''',
          );

          await db.execute('''insert into tempNews (newsID, 
                                                    feedID, 
                                                    title, 
                                                    url,
                                                    commentsUrl,
                                                    shareCode, 
                                                    content, 
                                                    hash, 
                                                    publishedAt, 
                                                    createdAt, 
                                                    status, 
                                                    readingTime, 
                                                    starred, 
                                                    feedTitle, 
                                                    syncStatus) 
                 select newsID, 
                            feedID, 
                            title, 
                            url,
                            '' AS commentsUrl,
                            '' AS shareCode, 
                            content, 
                            hash, 
                            publishedAt, 
                            createdAt, 
                            status, 
                            readingTime, 
                            starred, 
                            feedTitle, 
                            syncStatus  
                  from news;''');

          // create the table feeds
          await db.execute('DROP TABLE IF EXISTS news');
          await db.execute(
            '''CREATE TABLE news(newsID INTEGER PRIMARY KEY, 
                            feedID INTEGER, 
                            title TEXT, 
                            url TEXT,
                            commentsUrl TEXT,
                            shareCode TEXT, 
                            content TEXT, 
                            hash TEXT, 
                            publishedAt TEXT, 
                            createdAt TEXT, 
                            status TEXT, 
                            readingTime INTEGER, 
                            starred INTEGER, 
                            feedTitle TEXT, 
                            syncStatus TEXT)''',
          );

          await db.execute('''insert into news (newsID, 
                                                feedID, 
                                                title, 
                                                url,
                                                commentsUrl,
                                                shareCode, 
                                                content, 
                                                hash, 
                                                publishedAt, 
                                                createdAt, 
                                                status, 
                                                readingTime, 
                                                starred, 
                                                feedTitle, 
                                                syncStatus) 
                 select newsID, 
                        feedID, 
                        title, 
                        url,
                        commentsUrl,
                        shareCode, 
                        content, 
                        hash, 
                        publishedAt, 
                        createdAt, 
                        status, 
                        readingTime, 
                        starred, 
                        feedTitle, 
                        syncStatus 
                  from tempNews;''');
          await db.execute('DROP TABLE IF EXISTS tempNews');
          await db.execute(
            '''ALTER TABLE attachments ADD COLUMN mediaProgression INTEGER NOT NULL DEFAULT 0''',
          );
        } else if (oldVersion == 6) {
          logThis('upgradeDB', 'Upgrading DB from version 6', LogLevel.INFO);

          await db.execute(
            '''CREATE TABLE tempFeeds(feedID INTEGER PRIMARY KEY, 
                          title TEXT, 
                          site_url TEXT, 
                          iconMimeType TEXT,
                          iconID INTEGER,
                          newsCount INTEGER,
                          crawler INTEGER,
                          manualTruncate INTEGER,
                          preferParagraph INTEGER,
                          preferAttachmentImage INTEGER,
                          manualAdaptLightModeToIcon INTEGER,
                          manualAdaptDarkModeToIcon INTEGER,
                          openMinifluxEntry INTEGER,
                          expandedWithFulltext INTEGER,
                          expandedFulltextLimit INTEGER,
                          categoryID INTEGER)''',
          );

          await db.execute('''insert into tempFeeds (feedID, 
                                        title,
                                        site_url, 
                                        iconMimeType,
                                        iconID,
                                        newsCount,
                                        crawler,
                                        manualTruncate,
                                        preferParagraph,
                                        preferAttachmentImage,
                                        manualAdaptLightModeToIcon,
                                        manualAdaptDarkModeToIcon,
                                        openMinifluxEntry,
                                        expandedWithFulltext,
                                        expandedFulltextLimit,
                                        categoryID) 
                 select feedID, 
                        title,
                        site_url, 
                        iconMimeType,
                        0 AS iconID,
                        newsCount,
                        crawler,
                        manualTruncate,
                        preferParagraph,
                        preferAttachmentImage,
                        manualAdaptLightModeToIcon,
                        manualAdaptDarkModeToIcon,
                        openMinifluxEntry,
                        0 AS expandedWithFulltext,
                        0 AS expandedFulltextLimit,
                        categoryID  
                  from feeds;''');

          // create the table feeds
          await db.execute('DROP TABLE IF EXISTS feeds');
          await db.execute(
            '''CREATE TABLE feeds(feedID INTEGER PRIMARY KEY, 
                          title TEXT, 
                          site_url TEXT, 
                          iconMimeType TEXT,
                          iconID INTEGER,
                          newsCount INTEGER,
                          crawler INTEGER,
                          manualTruncate INTEGER,
                          preferParagraph INTEGER,
                          preferAttachmentImage INTEGER,
                          manualAdaptLightModeToIcon INTEGER,
                          manualAdaptDarkModeToIcon INTEGER,
                          openMinifluxEntry INTEGER,
                          expandedWithFulltext INTEGER,
                          expandedFulltextLimit INTEGER,
                          categoryID INTEGER)''',
          );

          await db.execute('''insert into feeds (feedID, 
                                        title,
                                        site_url, 
                                        iconMimeType,
                                        iconID,
                                        newsCount,
                                        crawler,
                                        manualTruncate,
                                        preferParagraph,
                                        preferAttachmentImage,
                                        manualAdaptLightModeToIcon,
                                        manualAdaptDarkModeToIcon,
                                        openMinifluxEntry,
                                        expandedWithFulltext,
                                        expandedFulltextLimit,
                                        categoryID) 
                 select feedID, 
                        title,
                        site_url, 
                        iconMimeType,
                        iconID,
                        newsCount,
                        crawler,
                        manualTruncate,
                        preferParagraph,
                        preferAttachmentImage,
                        manualAdaptLightModeToIcon,
                        manualAdaptDarkModeToIcon,
                        openMinifluxEntry,
                        expandedWithFulltext,
                        expandedFulltextLimit,
                        categoryID  
                  from tempFeeds;''');
          await db.execute('DROP TABLE IF EXISTS tempFeeds');

          await db.execute(
            '''CREATE TABLE tempNews(newsID INTEGER PRIMARY KEY, 
                            feedID INTEGER, 
                            title TEXT, 
                            url TEXT,
                            commentsUrl TEXT,
                            shareCode TEXT, 
                            content TEXT, 
                            hash TEXT, 
                            publishedAt TEXT, 
                            createdAt TEXT, 
                            status TEXT, 
                            readingTime INTEGER, 
                            starred INTEGER, 
                            feedTitle TEXT, 
                            syncStatus TEXT)''',
          );

          await db.execute('''insert into tempNews (newsID, 
                                                    feedID, 
                                                    title, 
                                                    url,
                                                    commentsUrl,
                                                    shareCode, 
                                                    content, 
                                                    hash, 
                                                    publishedAt, 
                                                    createdAt, 
                                                    status, 
                                                    readingTime, 
                                                    starred, 
                                                    feedTitle, 
                                                    syncStatus) 
                 select newsID, 
                            feedID, 
                            title, 
                            url,
                            '' AS commentsUrl,
                            '' AS shareCode, 
                            content, 
                            hash, 
                            publishedAt, 
                            createdAt, 
                            status, 
                            readingTime, 
                            starred, 
                            feedTitle, 
                            syncStatus  
                  from news;''');

          // create the table feeds
          await db.execute('DROP TABLE IF EXISTS news');
          await db.execute(
            '''CREATE TABLE news(newsID INTEGER PRIMARY KEY, 
                            feedID INTEGER, 
                            title TEXT, 
                            url TEXT,
                            commentsUrl TEXT,
                            shareCode TEXT, 
                            content TEXT, 
                            hash TEXT, 
                            publishedAt TEXT, 
                            createdAt TEXT, 
                            status TEXT, 
                            readingTime INTEGER, 
                            starred INTEGER, 
                            feedTitle TEXT, 
                            syncStatus TEXT)''',
          );

          await db.execute('''insert into news (newsID, 
                                                feedID, 
                                                title, 
                                                url,
                                                commentsUrl,
                                                shareCode, 
                                                content, 
                                                hash, 
                                                publishedAt, 
                                                createdAt, 
                                                status, 
                                                readingTime, 
                                                starred, 
                                                feedTitle, 
                                                syncStatus) 
                 select newsID, 
                        feedID, 
                        title, 
                        url,
                        commentsUrl,
                        shareCode, 
                        content, 
                        hash, 
                        publishedAt, 
                        createdAt, 
                        status, 
                        readingTime, 
                        starred, 
                        feedTitle, 
                        syncStatus 
                  from tempNews;''');
          await db.execute('DROP TABLE IF EXISTS tempNews');
          await db.execute(
            '''ALTER TABLE attachments ADD COLUMN mediaProgression INTEGER NOT NULL DEFAULT 0''',
          );
        } else if (oldVersion == 7) {
          logThis('upgradeDB', 'Upgrading DB from version 7', LogLevel.INFO);

          await db.execute(
            '''CREATE TABLE tempFeeds(feedID INTEGER PRIMARY KEY, 
                          title TEXT, 
                          site_url TEXT, 
                          iconMimeType TEXT,
                          iconID INTEGER,
                          newsCount INTEGER,
                          crawler INTEGER,
                          manualTruncate INTEGER,
                          preferParagraph INTEGER,
                          preferAttachmentImage INTEGER,
                          manualAdaptLightModeToIcon INTEGER,
                          manualAdaptDarkModeToIcon INTEGER,
                          openMinifluxEntry INTEGER,
                          expandedWithFulltext INTEGER,
                          expandedFulltextLimit INTEGER,
                          categoryID INTEGER)''',
          );

          await db.execute('''insert into tempFeeds (feedID, 
                                        title,
                                        site_url, 
                                        iconMimeType,
                                        iconID,
                                        newsCount,
                                        crawler,
                                        manualTruncate,
                                        preferParagraph,
                                        preferAttachmentImage,
                                        manualAdaptLightModeToIcon,
                                        manualAdaptDarkModeToIcon,
                                        openMinifluxEntry,
                                        expandedWithFulltext,
                                        expandedFulltextLimit,
                                        categoryID) 
                 select feedID, 
                        title,
                        site_url, 
                        iconMimeType,
                        iconID,
                        newsCount,
                        crawler,
                        manualTruncate,
                        preferParagraph,
                        preferAttachmentImage,
                        manualAdaptLightModeToIcon,
                        manualAdaptDarkModeToIcon,
                        openMinifluxEntry,
                        expandedWithFulltext,
                        0 AS expandedFulltextLimit,
                        categoryID  
                  from feeds;''');

          // create the table feeds
          await db.execute('DROP TABLE IF EXISTS feeds');
          await db.execute(
            '''CREATE TABLE feeds(feedID INTEGER PRIMARY KEY, 
                          title TEXT, 
                          site_url TEXT, 
                          iconMimeType TEXT,
                          iconID INTEGER,
                          newsCount INTEGER,
                          crawler INTEGER,
                          manualTruncate INTEGER,
                          preferParagraph INTEGER,
                          preferAttachmentImage INTEGER,
                          manualAdaptLightModeToIcon INTEGER,
                          manualAdaptDarkModeToIcon INTEGER,
                          openMinifluxEntry INTEGER,
                          expandedWithFulltext INTEGER,
                          expandedFulltextLimit INTEGER,
                          categoryID INTEGER)''',
          );

          await db.execute('''insert into feeds (feedID, 
                                        title,
                                        site_url, 
                                        iconMimeType,
                                        iconID,
                                        newsCount,
                                        crawler,
                                        manualTruncate,
                                        preferParagraph,
                                        preferAttachmentImage,
                                        manualAdaptLightModeToIcon,
                                        manualAdaptDarkModeToIcon,
                                        openMinifluxEntry,
                                        expandedWithFulltext,
                                        expandedFulltextLimit,
                                        categoryID) 
                 select feedID, 
                        title,
                        site_url, 
                        iconMimeType,
                        iconID,
                        newsCount,
                        crawler,
                        manualTruncate,
                        preferParagraph,
                        preferAttachmentImage,
                        manualAdaptLightModeToIcon,
                        manualAdaptDarkModeToIcon,
                        openMinifluxEntry,
                        expandedWithFulltext,
                        expandedFulltextLimit,
                        categoryID  
                  from tempFeeds;''');
          await db.execute('DROP TABLE IF EXISTS tempFeeds');

          await db.execute(
            '''CREATE TABLE tempNews(newsID INTEGER PRIMARY KEY, 
                            feedID INTEGER, 
                            title TEXT, 
                            url TEXT,
                            commentsUrl TEXT,
                            shareCode TEXT, 
                            content TEXT, 
                            hash TEXT, 
                            publishedAt TEXT, 
                            createdAt TEXT, 
                            status TEXT, 
                            readingTime INTEGER, 
                            starred INTEGER, 
                            feedTitle TEXT, 
                            syncStatus TEXT)''',
          );

          await db.execute('''insert into tempNews (newsID, 
                                                    feedID, 
                                                    title, 
                                                    url,
                                                    commentsUrl,
                                                    shareCode, 
                                                    content, 
                                                    hash, 
                                                    publishedAt, 
                                                    createdAt, 
                                                    status, 
                                                    readingTime, 
                                                    starred, 
                                                    feedTitle, 
                                                    syncStatus) 
                 select newsID, 
                            feedID, 
                            title, 
                            url,
                            '' AS commentsUrl,
                            '' AS shareCode, 
                            content, 
                            hash, 
                            publishedAt, 
                            createdAt, 
                            status, 
                            readingTime, 
                            starred, 
                            feedTitle, 
                            syncStatus  
                  from news;''');

          // create the table news
          await db.execute('DROP TABLE IF EXISTS news');
          await db.execute(
            '''CREATE TABLE news(newsID INTEGER PRIMARY KEY, 
                            feedID INTEGER, 
                            title TEXT, 
                            url TEXT,
                            commentsUrl TEXT,
                            shareCode TEXT, 
                            content TEXT, 
                            hash TEXT, 
                            publishedAt TEXT, 
                            createdAt TEXT, 
                            status TEXT, 
                            readingTime INTEGER, 
                            starred INTEGER, 
                            feedTitle TEXT, 
                            syncStatus TEXT)''',
          );

          await db.execute('''insert into news (newsID, 
                                                feedID, 
                                                title, 
                                                url,
                                                commentsUrl,
                                                shareCode, 
                                                content, 
                                                hash, 
                                                publishedAt, 
                                                createdAt, 
                                                status, 
                                                readingTime, 
                                                starred, 
                                                feedTitle, 
                                                syncStatus) 
                 select newsID, 
                        feedID, 
                        title, 
                        url,
                        commentsUrl,
                        shareCode, 
                        content, 
                        hash, 
                        publishedAt, 
                        createdAt, 
                        status, 
                        readingTime, 
                        starred, 
                        feedTitle, 
                        syncStatus 
                  from tempNews;''');
          await db.execute('DROP TABLE IF EXISTS tempNews');
          await db.execute(
            '''ALTER TABLE attachments ADD COLUMN mediaProgression INTEGER NOT NULL DEFAULT 0''',
          );
        } else if (oldVersion == 8) {
          logThis('upgradeDB', 'Upgrading DB from version 8', LogLevel.INFO);

          await db.execute(
            '''CREATE TABLE tempFeeds(feedID INTEGER PRIMARY KEY, 
                          title TEXT, 
                          site_url TEXT, 
                          iconMimeType TEXT,
                          iconID INTEGER,
                          newsCount INTEGER,
                          crawler INTEGER,
                          manualTruncate INTEGER,
                          preferParagraph INTEGER,
                          preferAttachmentImage INTEGER,
                          manualAdaptLightModeToIcon INTEGER,
                          manualAdaptDarkModeToIcon INTEGER,
                          openMinifluxEntry INTEGER,
                          expandedWithFulltext INTEGER,
                          expandedFulltextLimit INTEGER,
                          categoryID INTEGER)''',
          );

          await db.execute('''insert into tempFeeds (feedID, 
                                        title,
                                        site_url, 
                                        iconMimeType,
                                        iconID,
                                        newsCount,
                                        crawler,
                                        manualTruncate,
                                        preferParagraph,
                                        preferAttachmentImage,
                                        manualAdaptLightModeToIcon,
                                        manualAdaptDarkModeToIcon,
                                        openMinifluxEntry,
                                        expandedWithFulltext,
                                        expandedFulltextLimit,
                                        categoryID) 
                 select feedID, 
                        title,
                        site_url, 
                        iconMimeType,
                        iconID,
                        newsCount,
                        crawler,
                        manualTruncate,
                        preferParagraph,
                        preferAttachmentImage,
                        manualAdaptLightModeToIcon,
                        manualAdaptDarkModeToIcon,
                        openMinifluxEntry,
                        expandedWithFulltext,
                        0 AS expandedFulltextLimit,
                        categoryID  
                  from feeds;''');

          // create the table feeds
          await db.execute('DROP TABLE IF EXISTS feeds');
          await db.execute(
            '''CREATE TABLE feeds(feedID INTEGER PRIMARY KEY, 
                          title TEXT, 
                          site_url TEXT, 
                          iconMimeType TEXT,
                          iconID INTEGER,
                          newsCount INTEGER,
                          crawler INTEGER,
                          manualTruncate INTEGER,
                          preferParagraph INTEGER,
                          preferAttachmentImage INTEGER,
                          manualAdaptLightModeToIcon INTEGER,
                          manualAdaptDarkModeToIcon INTEGER,
                          openMinifluxEntry INTEGER,
                          expandedWithFulltext INTEGER,
                          expandedFulltextLimit INTEGER,
                          categoryID INTEGER)''',
          );

          await db.execute('''insert into feeds (feedID, 
                                        title,
                                        site_url, 
                                        iconMimeType,
                                        iconID,
                                        newsCount,
                                        crawler,
                                        manualTruncate,
                                        preferParagraph,
                                        preferAttachmentImage,
                                        manualAdaptLightModeToIcon,
                                        manualAdaptDarkModeToIcon,
                                        openMinifluxEntry,
                                        expandedWithFulltext,
                                        expandedFulltextLimit,
                                        categoryID) 
                 select feedID, 
                        title,
                        site_url, 
                        iconMimeType,
                        iconID,
                        newsCount,
                        crawler,
                        manualTruncate,
                        preferParagraph,
                        preferAttachmentImage,
                        manualAdaptLightModeToIcon,
                        manualAdaptDarkModeToIcon,
                        openMinifluxEntry,
                        expandedWithFulltext,
                        expandedFulltextLimit,
                        categoryID  
                  from tempFeeds;''');
          await db.execute('DROP TABLE IF EXISTS tempFeeds');
          await db.execute(
            '''ALTER TABLE attachments ADD COLUMN mediaProgression INTEGER NOT NULL DEFAULT 0''',
          );
        } else if (oldVersion == 9) {
          logThis('upgradeDB', 'Upgrading DB from version 9', LogLevel.INFO);

          await db.execute(
            '''ALTER TABLE attachments ADD COLUMN mediaProgression INTEGER NOT NULL DEFAULT 0''',
          );
        }

        logThis('upgradeDB', 'Finished upgrading DB', LogLevel.INFO);
      },
      version: 10,
    );
  }

  // read the persistent saved configuration
  Future<bool> readConfigValues() async {
    logThis('readConfigValues', 'Starting read config values', LogLevel.INFO);

    try {
      // Timeout guards against the headless CarPlay case: if the device was
      // never unlocked since boot, pre-migration WhenUnlocked Keychain items
      // would make readAll() hang indefinitely.
      storageValues = await storage.readAll().timeout(const Duration(seconds: 5));
    } catch (e) {
      logThis('readConfigValues', 'readAll failed or timed out: $e — using empty config', LogLevel.WARNING);
      storageValues = {};
    }

    logThis('readConfigValues', 'Finished read config values', LogLevel.INFO);

    return true;
  }

  // One-time migration: rewrite every Keychain item so iOS updates the
  // kSecAttrAccessible attribute from WhenUnlocked to first_unlock. After this
  // runs once, readAll() no longer fails with -25308 during headless CarPlay
  // launches (screen locked). Safe to call multiple times — writes are idempotent.
  Future<void> migrateKeychainAccessibility() async {
    const migrationKey = '_keychain_migrated_first_unlock_v1';
    final alreadyDone = storageValues[migrationKey];
    if (alreadyDone == 'true') return;
    logThis('migrateKeychainAccessibility', 'Starting Keychain first_unlock migration', LogLevel.INFO);
    try {
      for (final entry in storageValues.entries) {
        if (entry.key == migrationKey) continue;
        await storage.write(key: entry.key, value: entry.value);
      }
      await storage.write(key: migrationKey, value: 'true');
      storageValues[migrationKey] = 'true';
      logThis('migrateKeychainAccessibility', 'Migration complete — ${storageValues.length} items updated', LogLevel.INFO);
    } catch (e) {
      logThis('migrateKeychainAccessibility', 'Migration error: $e', LogLevel.WARNING);
    }
  }

  // read the some persistent saved configuration
  Future<bool> readThemeConfigValues(BuildContext context) async {
    logThis('readThemeConfigValues', 'Starting read config values', LogLevel.INFO);
    FluxNewsThemeState themeState = context.read<FluxNewsThemeState>();

    var useBlackModeStoredValue = await storage.read(key: FluxNewsState.secureStorageUseBlackModeKey);
    if (useBlackModeStoredValue != '') {
      if (useBlackModeStoredValue == FluxNewsState.secureStorageTrueString) {
        themeState.useBlackMode = true;
      } else {
        themeState.useBlackMode = false;
      }
    }
    var brightnessModeStoredValue = await storage.read(key: FluxNewsState.secureStorageBrightnessModeKey);
    if (brightnessModeStoredValue != '' && brightnessModeStoredValue != null) {
      themeState.brightnessMode = brightnessModeStoredValue;
    }
    themeState.refreshView();

    logThis('readThemeConfigValues', 'Finished read config values', LogLevel.INFO);

    return true;
  }

  // init the persistent saved configuration
  bool readConfig(BuildContext context) {
    logThis('readConfig', 'Starting read config', LogLevel.INFO);
    FluxNewsThemeState themeState = context.read<FluxNewsThemeState>();

    // init the maps for the brightness mode list
    // this maps use the key as the technical string and the value as the display name
    if (context.mounted) {
      if (AppLocalizations.of(context) != null) {
        recordTypesAmountOfSyncedNews = <KeyValueRecordType>[
          KeyValueRecordType(key: "0", value: AppLocalizations.of(context)!.all),
          const KeyValueRecordType(key: "1000", value: "1000"),
          const KeyValueRecordType(key: "2000", value: "2000"),
          const KeyValueRecordType(key: "5000", value: "5000"),
          const KeyValueRecordType(key: "10000", value: "10000"),
        ];
        recordTypesAmountOfSearchedNews = <KeyValueRecordType>[
          KeyValueRecordType(key: "0", value: AppLocalizations.of(context)!.all),
          const KeyValueRecordType(key: "1000", value: "1000"),
          const KeyValueRecordType(key: "2000", value: "2000"),
          const KeyValueRecordType(key: "5000", value: "5000"),
          const KeyValueRecordType(key: "10000", value: "10000"),
        ];
        recordTypesAmountOfCharactersToTruncateLimit = <KeyValueRecordType>[
          KeyValueRecordType(key: "0", value: AppLocalizations.of(context)!.always),
          const KeyValueRecordType(key: "100", value: "100"),
          const KeyValueRecordType(key: "200", value: "200"),
          const KeyValueRecordType(key: "300", value: "300"),
          const KeyValueRecordType(key: "400", value: "400"),
          const KeyValueRecordType(key: "500", value: "500"),
          const KeyValueRecordType(key: "600", value: "600"),
          const KeyValueRecordType(key: "700", value: "700"),
          const KeyValueRecordType(key: "800", value: "800"),
          const KeyValueRecordType(key: "900", value: "900"),
          const KeyValueRecordType(key: "1000", value: "1000"),
        ];
        recordTypesSyncReadNewsAfterDays = <KeyValueRecordType>[
          KeyValueRecordType(key: "0", value: AppLocalizations.of(context)!.all),
          const KeyValueRecordType(key: "7", value: "7"),
          const KeyValueRecordType(key: "14", value: "14"),
          const KeyValueRecordType(key: "30", value: "30"),
          const KeyValueRecordType(key: "60", value: "60"),
          const KeyValueRecordType(key: "90", value: "90"),
          const KeyValueRecordType(key: "180", value: "180"),
          const KeyValueRecordType(key: "365", value: "365"),
        ];
        recordTypesBrightnessMode = <KeyValueRecordType>[
          KeyValueRecordType(
              key: FluxNewsState.brightnessModeSystemString, value: AppLocalizations.of(context)!.system),
          KeyValueRecordType(key: FluxNewsState.brightnessModeDarkString, value: AppLocalizations.of(context)!.dark),
          KeyValueRecordType(key: FluxNewsState.brightnessModeLightString, value: AppLocalizations.of(context)!.light),
        ];
        recordTypesSwipeActions = <KeyValueRecordType>[
          KeyValueRecordType(
              key: FluxNewsState.swipeActionReadUnreadString, value: AppLocalizations.of(context)!.readShort),
          KeyValueRecordType(
              key: FluxNewsState.swipeActionBookmarkString, value: AppLocalizations.of(context)!.bookmarkShort),
          KeyValueRecordType(key: FluxNewsState.swipeActionSaveString, value: AppLocalizations.of(context)!.saveShort),
          KeyValueRecordType(
              key: FluxNewsState.swipeActionOpenMinifluxString, value: AppLocalizations.of(context)!.openMinifluxShort),
          KeyValueRecordType(key: FluxNewsState.swipeActionShareString, value: AppLocalizations.of(context)!.share),
          KeyValueRecordType(key: FluxNewsState.swipeActionOpenString, value: AppLocalizations.of(context)!.open),
          KeyValueRecordType(
              key: FluxNewsState.swipeActionDownloadString, value: AppLocalizations.of(context)!.downloadAudio),
          KeyValueRecordType(
              key: FluxNewsState.swipeActionOpenCommentsString, value: AppLocalizations.of(context)!.openComments),
        ];
        recordTypesSecondSwipeActions = <KeyValueRecordType>[
          KeyValueRecordType(key: FluxNewsState.swipeActionNoneString, value: AppLocalizations.of(context)!.none),
          KeyValueRecordType(
              key: FluxNewsState.swipeActionReadUnreadString, value: AppLocalizations.of(context)!.readShort),
          KeyValueRecordType(
              key: FluxNewsState.swipeActionBookmarkString, value: AppLocalizations.of(context)!.bookmarkShort),
          KeyValueRecordType(key: FluxNewsState.swipeActionSaveString, value: AppLocalizations.of(context)!.saveShort),
          KeyValueRecordType(
              key: FluxNewsState.swipeActionOpenMinifluxString, value: AppLocalizations.of(context)!.openMinifluxShort),
          KeyValueRecordType(key: FluxNewsState.swipeActionShareString, value: AppLocalizations.of(context)!.share),
          KeyValueRecordType(key: FluxNewsState.swipeActionOpenString, value: AppLocalizations.of(context)!.open),
          KeyValueRecordType(
              key: FluxNewsState.swipeActionDownloadString, value: AppLocalizations.of(context)!.downloadAudio),
          KeyValueRecordType(
              key: FluxNewsState.swipeActionOpenCommentsString, value: AppLocalizations.of(context)!.openComments),
        ];
        recordTypesTabActions = <KeyValueRecordType>[
          KeyValueRecordType(key: FluxNewsState.tabActionOpenString, value: AppLocalizations.of(context)!.open),
          KeyValueRecordType(key: FluxNewsState.tabActionExpandString, value: AppLocalizations.of(context)!.expand),
          KeyValueRecordType(key: FluxNewsState.tabActionSplittedString, value: AppLocalizations.of(context)!.splitted),
        ];
        recordTypesLongPressActions = <KeyValueRecordType>[
          KeyValueRecordType(key: FluxNewsState.longPressActionMenuString, value: AppLocalizations.of(context)!.menu),
          KeyValueRecordType(
              key: FluxNewsState.longPressActionExpandString, value: AppLocalizations.of(context)!.expand),
          KeyValueRecordType(key: FluxNewsState.longPressActionNoneString, value: AppLocalizations.of(context)!.none),
        ];
        recordTypesFloatingButtonActions = <KeyValueRecordType>[
          KeyValueRecordType(
              key: FluxNewsState.floatingButtonMarkAsReadAction,
              value: AppLocalizations.of(context)!.markNewsAsReadButton),
          KeyValueRecordType(
              key: FluxNewsState.floatingButtonSyncAction, value: AppLocalizations.of(context)!.syncNews),
        ];
        recordTypesAppBarType = <KeyValueRecordType>[
          KeyValueRecordType(key: FluxNewsState.appBarNormalType, value: AppLocalizations.of(context)!.normal),
          KeyValueRecordType(key: FluxNewsState.appBarCollapsedType, value: AppLocalizations.of(context)!.collapsible),
          KeyValueRecordType(key: FluxNewsState.appBarGlassType, value: AppLocalizations.of(context)!.glass),
        ];
      } else {
        recordTypesAmountOfSyncedNews = <KeyValueRecordType>[];
        recordTypesAmountOfSearchedNews = <KeyValueRecordType>[];
        recordTypesAmountOfCharactersToTruncateLimit = <KeyValueRecordType>[];
        recordTypesBrightnessMode = <KeyValueRecordType>[];
        recordTypesSwipeActions = <KeyValueRecordType>[];
        recordTypesSecondSwipeActions = <KeyValueRecordType>[];
        recordTypesTabActions = <KeyValueRecordType>[];
        recordTypesLongPressActions = <KeyValueRecordType>[];
        recordTypesSyncReadNewsAfterDays = <KeyValueRecordType>[];
        recordTypesFloatingButtonActions = <KeyValueRecordType>[];
        recordTypesAppBarType = <KeyValueRecordType>[];
      }
    } else {
      recordTypesAmountOfSyncedNews = <KeyValueRecordType>[];
      recordTypesAmountOfSearchedNews = <KeyValueRecordType>[];
      recordTypesAmountOfCharactersToTruncateLimit = <KeyValueRecordType>[];
      recordTypesBrightnessMode = <KeyValueRecordType>[];
      recordTypesSwipeActions = <KeyValueRecordType>[];
      recordTypesSecondSwipeActions = <KeyValueRecordType>[];
      recordTypesTabActions = <KeyValueRecordType>[];
      recordTypesLongPressActions = <KeyValueRecordType>[];
      recordTypesSyncReadNewsAfterDays = <KeyValueRecordType>[];
      recordTypesFloatingButtonActions = <KeyValueRecordType>[];
      recordTypesAppBarType = <KeyValueRecordType>[];
    }

    // init the brightness mode selection with the first value of the above generated maps
    if (recordTypesBrightnessMode != null) {
      if (recordTypesBrightnessMode!.isNotEmpty) {
        brightnessModeSelection = recordTypesBrightnessMode![0];
      }
    }

    // init the amount of synced news selection with the first value of the above generated maps
    if (recordTypesAmountOfSyncedNews != null) {
      if (recordTypesAmountOfSyncedNews!.isNotEmpty) {
        amontOfSyncedNewsSelection = recordTypesAmountOfSyncedNews![0];
      }
    }

    // init the amount of searched news selection with the first value of the above generated maps
    if (recordTypesAmountOfSearchedNews != null) {
      if (recordTypesAmountOfSearchedNews!.isNotEmpty) {
        amontOfSearchedNewsSelection = recordTypesAmountOfSearchedNews![0];
      }
    }

    // init the amount of characters to truncate limit selection with the first value of the above generated maps
    if (recordTypesAmountOfCharactersToTruncateLimit != null) {
      if (recordTypesAmountOfCharactersToTruncateLimit!.isNotEmpty) {
        amountOfCharactersToTruncateLimitSelection = recordTypesAmountOfCharactersToTruncateLimit![0];
      }
    }

    // init the left Swipe action selection with the first value of the above generated maps
    if (recordTypesSwipeActions != null) {
      if (recordTypesSwipeActions!.isNotEmpty) {
        leftSwipeActionSelection = recordTypesSwipeActions![0];
      }
    }

    // init the right Swipe action selection with the first value of the above generated maps
    if (recordTypesSwipeActions != null) {
      if (recordTypesSwipeActions!.isNotEmpty) {
        rightSwipeActionSelection = recordTypesSwipeActions![1];
      }
    }

    // init the second left Swipe action selection with the first value of the above generated maps
    if (recordTypesSecondSwipeActions != null) {
      if (recordTypesSecondSwipeActions!.isNotEmpty) {
        if (Platform.isIOS) {
          secondLeftSwipeActionSelection = recordTypesSecondSwipeActions![3];
        } else {
          secondLeftSwipeActionSelection = recordTypesSecondSwipeActions![0];
        }
      }
    }

    // init the second right Swipe action selection with the first value of the above generated maps
    if (recordTypesSecondSwipeActions != null) {
      if (recordTypesSecondSwipeActions!.isNotEmpty) {
        if (Platform.isIOS) {
          secondRightSwipeActionSelection = recordTypesSecondSwipeActions![5];
        } else {
          secondRightSwipeActionSelection = recordTypesSecondSwipeActions![0];
        }
      }
    }

    // init the tab action selection with the first value of the above generated maps
    if (recordTypesTabActions != null) {
      if (recordTypesTabActions!.isNotEmpty) {
        if (Platform.isIOS) {
          tabActionSelection = recordTypesTabActions![2];
        } else {
          tabActionSelection = recordTypesTabActions![0];
        }
      }
    }

    // init the right Swipe action selection with the first value of the above generated maps
    if (recordTypesLongPressActions != null) {
      if (recordTypesLongPressActions!.isNotEmpty) {
        longPressActionSelection = recordTypesLongPressActions![0];
      }
    }

    // init the amount of characters to truncate limit selection with the first value of the above generated maps
    if (recordTypesSyncReadNewsAfterDays != null) {
      if (recordTypesSyncReadNewsAfterDays!.isNotEmpty) {
        syncReadNewsAfterDaysSelection = recordTypesSyncReadNewsAfterDays![0];
      }
    }

    // init the floating button action selection with the first value of the above generated maps
    if (recordTypesFloatingButtonActions != null) {
      if (recordTypesFloatingButtonActions!.isNotEmpty) {
        floatingButtonActionSelection = recordTypesFloatingButtonActions![0];
      }
    }

    // init the app bar type selection with the first value of the above generated maps
    if (recordTypesAppBarType != null) {
      if (recordTypesAppBarType!.isNotEmpty) {
        if (Platform.isIOS) {
          appBarTypeSelection = recordTypesAppBarType![2];
        } else {
          appBarTypeSelection = recordTypesAppBarType![0];
        }
      }
    }

    // init the miniflux server config with null
    minifluxURL = null;
    minifluxAPIKey = null;

    // iterate through all persistent saved values to assign the saved config
    storageValues.forEach((key, value) {
      // assign the miniflux server url from persistent saved config
      if (key == FluxNewsState.secureStorageMinifluxURLKey) {
        minifluxURL = value;
        if (minifluxURL != null) {
          insecureMinifluxURL = !minifluxURL!.toLowerCase().startsWith('https');
        }
      }

      // assign the miniflux server api key from persistent saved config
      if (key == FluxNewsState.secureStorageMinifluxAPIKey) {
        minifluxAPIKey = value;
      }

      // assign the miniflux server version from persistent saved config
      if (key == FluxNewsState.secureStorageMinifluxVersionKey) {
        if (value != '') {
          minifluxVersionInt = int.parse(value.replaceAll(RegExp(r'\D'), ''));
          minifluxVersionString = value;
        }
      }

      // assign the brightness mode selection from persistent saved config
      if (key == FluxNewsState.secureStorageBrightnessModeKey) {
        if (value != '') {
          themeState.brightnessMode = value;
          for (KeyValueRecordType recordSet in recordTypesBrightnessMode!) {
            if (value == recordSet.key) {
              brightnessModeSelection = recordSet;
            }
          }
          themeState.refreshView();
        }
      }

      // assign the amount of synced news selection from persistent saved config
      if (key == FluxNewsState.secureStorageAmountOfSyncedNewsKey) {
        if (value != '') {
          if (int.tryParse(value) != null) {
            amountOfSyncedNews = int.parse(value);
          } else {
            amountOfSyncedNews = 0;
          }

          for (KeyValueRecordType recordSet in recordTypesAmountOfSyncedNews!) {
            if (value == recordSet.key) {
              amontOfSyncedNewsSelection = recordSet;
            }
          }
        }
      }

      // assign the amount of searched news selection from persistent saved config
      if (key == FluxNewsState.secureStorageAmountOfSearchedNewsKey) {
        if (value != '') {
          if (int.tryParse(value) != null) {
            amountOfSearchedNews = int.parse(value);
          } else {
            amountOfSearchedNews = 0;
          }

          for (KeyValueRecordType recordSet in recordTypesAmountOfSearchedNews!) {
            if (value == recordSet.key) {
              amontOfSearchedNewsSelection = recordSet;
            }
          }
        }
      }

      // assign the sort order of the news list from persistent saved config
      if (key == FluxNewsState.secureStorageSortOrderKey) {
        if (value != '') {
          sortOrder = value;
        }
      }

      // assign the scroll position from persistent saved config
      if (key == FluxNewsState.secureStorageSavedScrollPositionKey) {
        if (value != '') {
          savedScrollPosition = int.parse(value);
        }
      }

      // assign the mark as read on scroll over selection from persistent saved config
      if (key == FluxNewsState.secureStorageMarkAsReadOnScrollOverKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            markAsReadOnScrollOver = true;
          } else {
            markAsReadOnScrollOver = false;
          }
        }
      }

      // assign the sync on startup selection from persistent saved config
      if (key == FluxNewsState.secureStorageSyncOnStartKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            syncOnStart = true;
          } else {
            syncOnStart = false;
          }
        }
      }

      // assign the multiline app bar title selection from persistent saved config
      if (key == FluxNewsState.secureStorageMultilineAppBarTextKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            multilineAppBarText = true;
          } else {
            multilineAppBarText = false;
          }
        }
      }

      // assign the show feed icon selection from persistent saved config
      if (key == FluxNewsState.secureStorageShowFeedIconsTextKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            showFeedIcons = true;
          } else {
            showFeedIcons = false;
          }
        }
      }

      // assign the shown news status selection (all news or only unread)
      // from persistent saved config
      if (key == FluxNewsState.secureStorageNewsStatusKey) {
        if (value != '') {
          newsStatus = value;
        }
      }

      // assign the amount of saves news selection from persistent saved config
      if (key == FluxNewsState.secureStorageAmountOfSavedNewsKey) {
        if (value != '') {
          amountOfSavedNews = int.parse(value);
        }
      }

      // assign the amount of saved bookmarked news selection from persistent saved config
      if (key == FluxNewsState.secureStorageAmountOfSavedStarredNewsKey) {
        if (value != '') {
          amountOfSavedStarredNews = int.parse(value);
        }
      }

      // assign the truncate mode from persistent saved config
      if (key == FluxNewsState.secureStorageTruncateModeKey) {
        if (value != '') {
          truncateMode = int.parse(value);
        }
      }

      // assign the truncate mode from persistent saved config
      if (key == FluxNewsState.secureStorageCharactersToTruncateKey) {
        if (value != '') {
          charactersToTruncate = int.parse(value);
        }
      }

      // assign the truncate mode from persistent saved config
      if (key == FluxNewsState.secureStorageCharactersToTruncateLimitKey) {
        if (value != '') {
          if (int.tryParse(value) != null) {
            charactersToTruncateLimit = int.parse(value);
          } else {
            charactersToTruncateLimit = 0;
          }

          for (KeyValueRecordType recordSet in recordTypesAmountOfCharactersToTruncateLimit!) {
            if (value == recordSet.key) {
              amountOfCharactersToTruncateLimitSelection = recordSet;
            }
          }
        }
      }

      // assign the truncate mode from persistent saved config
      if (key == FluxNewsState.secureStorageSyncReadNewsAfterDaysKey) {
        if (value != '') {
          if (int.tryParse(value) != null) {
            syncReadNewsAfterDays = int.parse(value);
          } else {
            syncReadNewsAfterDays = 0;
          }

          for (KeyValueRecordType recordSet in recordTypesSyncReadNewsAfterDays!) {
            if (value == recordSet.key) {
              syncReadNewsAfterDaysSelection = recordSet;
            }
          }
        }
      }

      // assign the mark as read on scroll over selection from persistent saved config
      if (key == FluxNewsState.secureStorageActivateTruncateKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            activateTruncate = true;
          } else {
            activateTruncate = false;
          }
        }
      }

      // assign the debug mode selection from persistent saved config
      if (key == FluxNewsState.secureStorageDebugModeKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            debugMode = true;
          } else {
            debugMode = false;
          }
        }
      }

      // assign the activate swiping gestures selection from persistent saved config
      if (key == FluxNewsState.secureStorageActivateSwipeGesturesKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            activateSwipeGestures = true;
          } else {
            activateSwipeGestures = false;
          }
        }
      }

      // assign the left Swipe Action selection from persistent saved config
      if (key == FluxNewsState.secureStorageLeftSwipeActionKey) {
        if (value != '') {
          leftSwipeAction = value;
          for (KeyValueRecordType recordSet in recordTypesSwipeActions!) {
            if (value == recordSet.key) {
              leftSwipeActionSelection = recordSet;
            }
          }
        }
      }

      // assign the right Swipe Action selection from persistent saved config
      if (key == FluxNewsState.secureStorageRightSwipeActionKey) {
        if (value != '') {
          rightSwipeAction = value;
          for (KeyValueRecordType recordSet in recordTypesSwipeActions!) {
            if (value == recordSet.key) {
              rightSwipeActionSelection = recordSet;
            }
          }
        }
      }

      // assign the second left Swipe Action selection from persistent saved config
      if (key == FluxNewsState.secureStorageSecondLeftSwipeActionKey) {
        if (value != '') {
          secondLeftSwipeAction = value;
          for (KeyValueRecordType recordSet in recordTypesSecondSwipeActions!) {
            if (value == recordSet.key) {
              secondLeftSwipeActionSelection = recordSet;
            }
          }
        }
      }

      // assign the second right Swipe Action selection from persistent saved config
      if (key == FluxNewsState.secureStorageSecondRightSwipeActionKey) {
        if (value != '') {
          secondRightSwipeAction = value;
          for (KeyValueRecordType recordSet in recordTypesSecondSwipeActions!) {
            if (value == recordSet.key) {
              secondRightSwipeActionSelection = recordSet;
            }
          }
        }
      }

      // assign the floating action Button visibility selection from persistent saved config
      if (key == FluxNewsState.secureStorageFloatingButtonVisibleKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            floatingButtonVisible = true;
          } else {
            floatingButtonVisible = false;
          }
        }
      }

      // assign the Tab Action selection from persistent saved config
      if (key == FluxNewsState.secureStorageTabActionKey) {
        if (value != '') {
          tabAction = value;
          for (KeyValueRecordType recordSet in recordTypesTabActions!) {
            if (value == recordSet.key) {
              tabActionSelection = recordSet;
            }
          }
        }
      }

      // assign the Tab Action selection from persistent saved config
      if (key == FluxNewsState.secureStorageLongPressActionKey) {
        if (value != '') {
          longPressAction = value;
          for (KeyValueRecordType recordSet in recordTypesLongPressActions!) {
            if (value == recordSet.key) {
              longPressActionSelection = recordSet;
            }
          }
        }
      }

      // assign the show headline on top selection from persistent saved config
      if (key == FluxNewsState.secureStorageShowHeadlineOnTopKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            showHeadlineOnTop = true;
          } else {
            showHeadlineOnTop = false;
          }
        }
      }

      // assign the show headline on top selection from persistent saved config
      if (key == FluxNewsState.secureStorageShowOnlyFeedCategoriesWithNewNeKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            showOnlyFeedCategoriesWithNewNews = true;
          } else {
            showOnlyFeedCategoriesWithNewNews = false;
          }
        }
      }

      // assign the startup categorie from persistent saved config
      if (key == FluxNewsState.secureStorageStartupCategorieKey) {
        if (value != '') {
          startupCategorie = int.parse(value);
        }
      }

      // assign the startup categorie selection from persistent saved config
      if (key == FluxNewsState.secureStorageStartupCategorieSelectionKey) {
        if (value != '') {
          startupCategorieSelectionKey = int.parse(value);
        }
      }

      // assign the startup feed selection from persistent saved config
      if (key == FluxNewsState.secureStorageStartupFeedSelectionKey) {
        if (value != '') {
          startupFeedSelectionKey = int.parse(value);
        }
      }

      // assign the remove news from list on read selection from persistent saved config
      if (key == FluxNewsState.secureStorageRemoveNewsFromListWhenReadKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            removeNewsFromListWhenRead = true;
          } else {
            removeNewsFromListWhenRead = false;
          }
        }
      }

      // assign the sync read news selection from persistent saved config
      if (key == FluxNewsState.secureStorageSyncReadNewsKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            syncReadNews = true;
          } else {
            syncReadNews = false;
          }
        }
      }

      // assign the auto-download audio after sync selection from persistent saved config
      if (key == FluxNewsState.secureStorageAutoDownloadAudioAfterSyncKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            autoDownloadAudioAfterSync = true;
          } else {
            autoDownloadAudioAfterSync = false;
          }
        }
      }

      // assign the download audio only on wifi selection from persistent saved config
      if (key == FluxNewsState.secureStorageDownloadAudioOnlyOnWifiKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            downloadAudioOnlyOnWifi = true;
          } else {
            downloadAudioOnlyOnWifi = false;
          }
        }
      }

      // assign the delete downloaded audio after playback selection from persistent saved config
      if (key == FluxNewsState.secureStorageDeleteAudioAfterPlaybackKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            deleteAudioAfterPlayback = true;
          } else {
            deleteAudioAfterPlayback = false;
          }
        }
      }

      // assign the audio download retention duration from persistent saved config
      if (key == FluxNewsState.secureStorageAudioDownloadRetentionDaysKey) {
        if (value != '') {
          audioDownloadRetentionDays = int.parse(value);
        }
      }

      // assign the open audio items in player selection from persistent saved config
      if (key == FluxNewsState.secureStorageOpenAudioItemsInPlayerKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            openAudioItemsInPlayer = true;
          } else {
            openAudioItemsInPlayer = false;
          }
        }
      }

      // assign the skip long sync selection from persistent saved config
      if (key == FluxNewsState.secureStorageSkipLongSyncKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            skipLongSync = true;
          } else {
            skipLongSync = false;
          }
        }
      }

      // assign the sync read status immediately selection from persistent saved config
      if (key == FluxNewsState.secureStorageSyncReadStatusImmediatelyKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            syncReadStatusImmediately = true;
          } else {
            syncReadStatusImmediately = false;
          }
        }
      }

      // assign the scrollover app bar selection from persistent saved config
      if (key == FluxNewsState.secureStorageScrolloverAppBarKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            scrolloverAppBar = true;
          } else {
            scrolloverAppBar = false;
          }
        }
      }

      // assign the scrollover app bar selection from persistent saved config
      if (key == FluxNewsState.secureStorageGlassAppBarKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            glassAppBar = true;
          } else {
            glassAppBar = false;
          }
        }
      }

      // assign the scrollover app bar selection from persistent saved config
      if (key == FluxNewsState.secureStorageUseSliverAppBarKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            useSliverAppBar = true;
          } else {
            useSliverAppBar = false;
          }
        }
      }

      // assign the scrollover app bar selection from persistent saved config
      if (key == FluxNewsState.secureStorageGlassActionButtonKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            glassActionButton = true;
          } else {
            glassActionButton = false;
          }
        }
      }

      // assign the floating button action selection from persistent saved config
      if (key == FluxNewsState.secureStorageAppBarTypeKey) {
        if (value != '') {
          appBarType = value;
          for (KeyValueRecordType recordSet in recordTypesAppBarType!) {
            if (value == recordSet.key) {
              appBarTypeSelection = recordSet;
            }
          }
        }
      }

      // assign the floating button action selection from persistent saved config
      if (key == FluxNewsState.secureStorageFloatingButtonKey) {
        if (value != '') {
          floatingButtonAction = value;
          for (KeyValueRecordType recordSet in recordTypesFloatingButtonActions!) {
            if (value == recordSet.key) {
              floatingButtonActionSelection = recordSet;
            }
          }
        }
      }

      // assign the network image cache migrated selection from persistent saved config
      if (key == FluxNewsState.secureStorageNetworkImageCacheMigratedKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            networkImageCacheMigrated = true;
          } else {
            networkImageCacheMigrated = false;
          }
        }
      }

      // assign the image cache duration from persistent saved config
      if (key == FluxNewsState.secureStorageImageCacheDurationDaysKey) {
        if (value != '') {
          imageCacheDurationDays = int.parse(value);
        }
      }
    });

    // iterate through all persistent saved values to assign the saved headers
    var headerCounter = 0;
    var headerFound = true;
    var noKeyFound = true;
    do {
      noKeyFound = true;
      storageValues.forEach((key, value) {
        if (key == '${FluxNewsState.secureStorageCustomHeadersKeyPrefixKey}$headerCounter') {
          var headerName = value;
          var headerValue = storageValues['${FluxNewsState.secureStorageCustomHeadersValuePrefixKey}$headerCounter'];
          headerValue ??= '';
          var header = {
            headerName: headerValue,
          };
          customHeaders.addAll(header);
          noKeyFound = false;
          headerCounter++;
        }
      });
      if (noKeyFound) {
        headerFound = false;
      }
    } while (headerFound);

    logThis('readConfig', 'Finished read config', LogLevel.INFO);

    // return true if everything was read
    return true;
  }

  Future<void> saveFeedIconFile(int feedIconID, Uint8List? bytes) async {
    String filename = "${FluxNewsState.feedIconFilePath}$feedIconID";
    await saveFile(filename, bytes);
  }

  Uint8List? readFeedIconFile(int feedIconID) {
    String filename = "${FluxNewsState.feedIconFilePath}$feedIconID";
    return readFile(filename);
  }

  bool checkIfFeedIconFileExists(int feedIconID) {
    String filename = "${FluxNewsState.feedIconFilePath}$feedIconID";
    String filePath = externalDirectory!.path + filename;
    final file = File(filePath);
    return file.existsSync();
  }

  void deleteFeedIconFile(int feedIconID) {
    String filename = "${FluxNewsState.feedIconFilePath}$feedIconID";
    deleteFile(filename);
  }

  Future<void> deleteAllFeedIconFiles() async {
    if (externalDirectory != null) {
      final fileIconPath = FluxNewsState.feedIconFilePath.substring(0, FluxNewsState.feedIconFilePath.lastIndexOf('/'));
      final dir = Directory(externalDirectory!.path + fileIconPath);
      final List<FileSystemEntity> entities = await dir.list().toList();
      final Iterable<File> files = entities.whereType<File>();
      for (final file in files) {
        file.deleteSync();
      }
    }
  }

  Future<void> saveFile(String filename, Uint8List? bytes) async {
    if (externalDirectory != null && bytes != null) {
      // Create an image name
      var filePath = externalDirectory!.path + filename;

      // Save to filesystem
      final file = File(filePath);
      await file.create(recursive: true);
      await file.writeAsBytes(bytes);
    }
  }

  Uint8List? readFile(String filename) {
    if (externalDirectory != null) {
      // Create an image name
      var filePath = externalDirectory!.path + filename;

      // Save to filesystem
      final file = File(filePath);
      if (file.existsSync()) {
        return file.readAsBytesSync();
      } else {
        return null;
      }
    } else {
      return null;
    }
  }

  void deleteFile(String filename) {
    if (externalDirectory != null) {
      // Create an image name
      var filePath = externalDirectory!.path + filename;

      // Save to filesystem
      final file = File(filePath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }

  void jumpToItem(int index) {
    waitUntilNewsListBuild().whenComplete(
      () {
        listController.jumpToItem(index: index, scrollController: scrollController, alignment: 0.0);
      },
    );
  }

  // this function is needed because after the news are fetched from the database,
  // the list of news need some time to be generated.
  // only after the list is generated, we can set the scroll position of the list
  // we can check that the list is generated if the scroll controller is attached to the list.
  // so the function checks the scroll controller and if it's not attached it waits 1 millisecond
  // and check then again if the scroll controller is attached.
  // With calling this function as await, we can wait with the further processing
  // on finishing with the list build.
  Future<void> waitUntilNewsListBuild() async {
    final completer = Completer();
    if (scrollController.positions.isNotEmpty) {
      completer.complete();
    } else {
      await Future.delayed(const Duration(milliseconds: 1));
      return waitUntilNewsListBuild();
    }

    return completer.future;
  }

  void saveCustomHeadersToStorage() {
    // first delete all existing headers in the storage
    var headerCounter = 0;
    var headerFound = true;
    var noKeyFound = true;
    do {
      noKeyFound = true;
      storageValues.forEach((key, value) {
        if (key == '${FluxNewsState.secureStorageCustomHeadersKeyPrefixKey}$headerCounter') {
          storage.delete(key: key);
          storage.delete(key: '${FluxNewsState.secureStorageCustomHeadersValuePrefixKey}$headerCounter');
          noKeyFound = false;
          headerCounter++;
        }
      });
      if (noKeyFound) {
        headerFound = false;
      }
    } while (headerFound);

    // now save all current headers to the storage
    headerCounter = 0;
    customHeaders.forEach((key, value) {
      storage.write(key: '${FluxNewsState.secureStorageCustomHeadersKeyPrefixKey}$headerCounter', value: key);
      storage.write(key: '${FluxNewsState.secureStorageCustomHeadersValuePrefixKey}$headerCounter', value: value);
      headerCounter++;
    });
  }

  // this function is needed to clean the legacy cache of the cached_network_image package which was used before
  Future<void> cleanLegacyCache() async {
    logThis('cleanLegacyCache', 'Starting cleaning of legacy cache', LogLevel.INFO);
    final temp = await getTemporaryDirectory();
    final dir = Directory('${temp.path}/libCachedImageData');
    if (await dir.exists()) await dir.delete(recursive: true);
    storage.write(
        key: FluxNewsState.secureStorageNetworkImageCacheMigratedKey, value: FluxNewsState.secureStorageTrueString);
    logThis('cleanLegacyCache', 'Finished cleaning of legacy cache', LogLevel.INFO);
  }

  // notify the listeners of FluxNewsState to refresh views
  void refreshView() {
    notifyListeners();
  }

  void setActiveAudioNews(News news) {
    activeAudioNews = news;
    notifyListeners();
  }
}

// helper class to generate the drop down lists in options
// the key is the technical name which is used internal
// the value is the display name of the option
class KeyValueRecordType extends Equatable {
  final String key;
  final String value;

  const KeyValueRecordType({required this.key, required this.value});

  @override
  List<Object> get props => [key, value];
}
