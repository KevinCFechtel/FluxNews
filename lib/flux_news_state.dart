import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    as sec_store;

import 'package:path/path.dart' as path_package;
import 'package:flutter_gen/gen_l10n/flux_news_localizations.dart';

import 'news_model.dart';

// generate android options to usw with flutter secure storage
sec_store.AndroidOptions _getAndroidOptions() => const sec_store.AndroidOptions(
      encryptedSharedPreferences: true,
      keyCipherAlgorithm:
          sec_store.KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
      storageCipherAlgorithm:
          sec_store.StorageCipherAlgorithm.AES_GCM_NoPadding,
    );

class FluxNewsState extends ChangeNotifier {
  // init the persistant flutter secure storage
  final storage =
      sec_store.FlutterSecureStorage(aOptions: _getAndroidOptions());

  // define static const variables to replace text within code
  static const String applicationName = 'Flux News';
  static const String applicationVersion = '1.1.0';
  static const String applicationLegalese = '\u{a9} 2023 Kevin Fechtel';
  static const String applicationProjectUrl =
      ' https://github.com/KevinCFechtel/FluxNews';
  static const String miniFluxProjectUrl = ' https://miniflux.app';
  static const String databasePathString = 'news_database.db';
  static const String rootRouteString = '/';
  static const String settingsRouteString = '/settings';
  static const String searchRouteString = '/search';
  static const int amountOfNewlyCatchedNews = 100;
  static const String unreadNewsStatus = 'unread';
  static const String readNewsStatus = 'read';
  static const String syncedSyncStatus = 'synced';
  static const String notSyncedSyncStatus = 'notSynced';
  static const String allNewsString = 'all';
  static const String databaseAllString = '%';
  static const String databaseDescString = 'DESC';
  static const String databaseAscString = 'ASC';
  static const String brightnessModeSystemString = 'System';
  static const String brightnessModeDarkString = 'Dark';
  static const String brightnessModeLightString = 'Light';
  static const String sortOrderNewestFirstString = 'Newest first';
  static const String sortOrderOldestFirstString = 'Oldest first';
  static const String secureStorageMinifluxURLKey = 'minifluxURL';
  static const String secureStorageMinifluxAPIKey = 'minifluxAPIKey';
  static const String secureStorageBrightnessModeKey = 'brightnessMode';
  static const String secureStorageSortOrderKey = 'sortOrder';
  static const String secureStorageSavedScrollPositionKey =
      'savedScrollPosition';
  static const String secureStorageMarkAsReadOnScrollOverKey =
      'markAsReadOnScrollOver';
  static const String secureStorageSyncOnStartKey = 'syncOnStart';
  static const String secureStorageNewsStatusKey = 'newsStatus';
  static const String secureStorageAmountOfSavedNewsKey = 'amountOfSavedNews';
  static const String secureStorageAmountOfSavedStarredNewsKey =
      'amountOfSavedStarredNews';
  static const String secureStorageMultilineAppBarTextKey =
      'multilineAppBarText';
  static const String secureStorageShowFeedIconsTextKey = 'showFeedIcons';
  static const String secureStorageTrueString = 'true';
  static const String secureStorageFalseString = 'false';
  static const String httpUnexpectedResponseErrorString = 'Unexpected response';
  static const String httpContentTypeString = 'application/json; charset=UTF-8';
  static const String httpMinifluxAuthHeaderString = 'X-Auth-Token';
  static const String httpMinifluxAcceptHeaderString = 'Accept';
  static const String httpMinifluxContentTypeHeaderString = 'Content-Type';
  static const String noImageUrlString = 'NoImageUrl';
  static const String contextMenueBookmarkString = 'bookmark';
  static const String cancelContextString = 'Cancel';

  // vars for lists of main view
  late Future<List<News>> newsList;
  late Future<Categories> categorieList;
  List<int>? feedIDs;

  // var for formatting the date depending on locale settings
  DateFormat dateFormat = DateFormat('M/d/yy HH:mm');

  // vars for error handling
  String errorString = '';
  bool newError = false;
  bool errorOnMicrofluxAuth = false;

  // the initial news status which should be fetched
  String newsStatus = FluxNewsState.unreadNewsStatus;

  // vars for miniflux server connection
  String? minifluxURL;
  String? minifluxAPIKey;

  // vars for settings
  Map<String, String> storageValues = {};
  String brightnessMode = FluxNewsState.brightnessModeSystemString;
  KeyValueRecordType? brightnessModeSelection;
  String? sortOrder = FluxNewsState.sortOrderNewestFirstString;
  int savedScrollPosition = 0;
  int amountOfSavedNews = 1000;
  int amountOfSavedStarredNews = 1000;
  bool markAsReadOnScrollOver = false;
  bool syncOnStart = false;
  bool multilineAppBarText = false;
  bool showFeedIcons = false;
  List<KeyValueRecordType>? recordTypesBrightnessMode;

  // vars for counter
  int starredCount = 0;
  int allNewsCount = 0;
  int appBarNewsCount = 0;

  // vars for app bar text
  String appBarText = '';

  // vars for detectiing device orientation and device type
  bool isTablet = false;
  Orientation orientation = Orientation.portrait;

  // the database connection as a variable
  Database? db;

  // init the database connection
  Future<Database> initializeDB() async {
    String path = await getDatabasesPath();
    return openDatabase(
      path_package.join(path, FluxNewsState.databasePathString),
      onCreate: (db, version) async {
        // create the table news
        await db.execute('DROP TABLE IF EXISTS news');
        await db.execute(
          '''CREATE TABLE news(newsID INTEGER PRIMARY KEY, 
                          feedID INTEGER, 
                          title TEXT, 
                          url TEXT, 
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
          '''CREATE TABLE categories(categorieID INTEGER PRIMARY KEY, 
                          title TEXT)''',
        );
        // create the table feeds
        await db.execute('DROP TABLE IF EXISTS feeds');
        await db.execute(
          '''CREATE TABLE feeds(feedID INTEGER PRIMARY KEY, 
                          title TEXT, 
                          site_url TEXT, 
                          icon BLOB,
                          iconMimeType TEXT,
                          newsCount INTEGER,
                          categorieID INTEGER)''',
        );
      },
      version: 1,
    );
  }

  // read the persistant saved configuration
  Future<bool> readConfigValues(BuildContext context) async {
    storageValues = await storage.readAll();
    return true;
  }

  // init the persistant saved configuration
  bool readConfig(BuildContext context) {
    // init the maps for the brightness mode list
    // this maps use the key as the technical string and the value as the displey name
    if (context.mounted) {
      recordTypesBrightnessMode = <KeyValueRecordType>[
        KeyValueRecordType(
            key: FluxNewsState.brightnessModeSystemString,
            value: AppLocalizations.of(context)!.system),
        KeyValueRecordType(
            key: FluxNewsState.brightnessModeDarkString,
            value: AppLocalizations.of(context)!.dark),
        KeyValueRecordType(
            key: FluxNewsState.brightnessModeLightString,
            value: AppLocalizations.of(context)!.light),
      ];
    } else {
      recordTypesBrightnessMode = <KeyValueRecordType>[];
    }

    // init the brightness mode selection with the first value of the above generated maps
    if (recordTypesBrightnessMode != null) {
      if (recordTypesBrightnessMode!.isNotEmpty) {
        brightnessModeSelection = recordTypesBrightnessMode![0];
      }
    }

    // init the miniflux server config with null
    minifluxURL = null;
    minifluxAPIKey = null;

    // iterate through all persistant saved values to assign the saved config
    storageValues.forEach((key, value) {
      // assign the miniflux server url from persistant saved config
      if (key == FluxNewsState.secureStorageMinifluxURLKey) {
        minifluxURL = value;
      }

      // assign the miniflux server api key from persistant saved config
      if (key == FluxNewsState.secureStorageMinifluxAPIKey) {
        minifluxAPIKey = value;
      }

      // assign the brightness mode selection from persistant saved config
      if (key == FluxNewsState.secureStorageBrightnessModeKey) {
        if (value != '') {
          brightnessMode = value;
          for (KeyValueRecordType recordSet in recordTypesBrightnessMode!) {
            if (value == recordSet.key) {
              brightnessModeSelection = recordSet;
            }
          }
        }
      }

      // assign the sort order of the news list from persistant saved config
      if (key == FluxNewsState.secureStorageSortOrderKey) {
        if (value != '') {
          sortOrder = value;
        }
      }

      // assign the scroll position from persistant saved config
      if (key == FluxNewsState.secureStorageSavedScrollPositionKey) {
        if (value != '') {
          savedScrollPosition = int.parse(value);
        }
      }

      // assign the mark as read on scrollover selection from persistant saved config
      if (key == FluxNewsState.secureStorageMarkAsReadOnScrollOverKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            markAsReadOnScrollOver = true;
          } else {
            markAsReadOnScrollOver = false;
          }
        }
      }

      // assign the sync on startup selection from persistant saved config
      if (key == FluxNewsState.secureStorageSyncOnStartKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            syncOnStart = true;
          } else {
            syncOnStart = false;
          }
        }
      }

      // assign the multiline app bar title selection from persistant saved config
      if (key == FluxNewsState.secureStorageMultilineAppBarTextKey) {
        if (value != '') {
          if (value == FluxNewsState.secureStorageTrueString) {
            multilineAppBarText = true;
          } else {
            multilineAppBarText = false;
          }
        }
      }

      // assign the show feed icon selection from persistant saved config
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
      // from persistant saved config
      if (key == FluxNewsState.secureStorageNewsStatusKey) {
        if (value != '') {
          newsStatus = value;
        }
      }

      // assign the amount of saves news selection from persistant saved config
      if (key == FluxNewsState.secureStorageAmountOfSavedNewsKey) {
        if (value != '') {
          amountOfSavedNews = int.parse(value);
        }
      }

      // assign the amount of saved bookmarked news selection from persistant saved config
      if (key == FluxNewsState.secureStorageAmountOfSavedStarredNewsKey) {
        if (value != '') {
          amountOfSavedStarredNews = int.parse(value);
        }
      }
    });
    // return true if everything was read
    return true;
  }

  // notify the listeners of FluxNewsState to refresh views
  void refreshView() {
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
