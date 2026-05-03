import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart' as sec_store;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flux_news/functions/flux_news_audio_handler.dart';
import 'package:flux_news/functions/flux_news_carplay_service.dart';
import 'package:flux_news/ui/log_viewer.dart';
import 'package:flux_news/state_management/flux_news_counter_state.dart';
import 'package:flux_news/state_management/flux_news_theme_state.dart';
import 'package:flux_news/ui/settings/feed_settings.dart';
import 'package:flux_news/ui/settings/general_settings.dart';
import 'package:flux_news/ui/settings/header_settings.dart';
import 'package:flux_news/ui/settings/news_item_settings.dart';
import 'package:flux_news/ui/settings/sync_settings.dart';
import 'package:flux_news/ui/settings/truncate_settings.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:system_date_time_format/system_date_time_format.dart';

import 'ui/flux_news_body.dart';
import 'ui/feed_onboarding.dart';
import 'ui/login.dart';
import 'state_management/flux_news_state.dart';
import 'ui/search.dart';
import 'ui/settings.dart';
import 'ui/welcome.dart';
import 'ui/restore_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isAndroid || Platform.isIOS) {
    // init the log system
    await FlutterLogs.initLogs(
        logLevelsEnabled: [LogLevel.INFO, LogLevel.WARNING, LogLevel.ERROR, LogLevel.SEVERE],
        timeStampFormat: TimeStampFormat.TIME_FORMAT_READABLE,
        directoryStructure: DirectoryStructure.FOR_DATE,
        logFileExtension: LogFileExtension.LOG,
        logsWriteDirectoryName: FluxNewsState.logsWriteDirectoryName,
        logsExportDirectoryName: FluxNewsState.logsExportDirectoryName,
        debugFileOperations: false,
        logsRetentionPeriodInDays: 14,
        zipsRetentionPeriodInDays: 3,
        isDebuggable: kDebugMode ? true : false);

    // On iOS the flutter_logs plugin ignores all initLogs parameters (initLogs
    // is a no-op in the Swift plugin), including logsRetentionPeriodInDays.
    // iOS also writes one file per month to Application Support/Logs/ using
    // the hardcoded directory name "Logs" — independent of logsWriteDirectoryName.
    // We therefore run our own cleanup on iOS at startup.
    if (Platform.isIOS) {
      await _cleanupIosLogs(retentionDays: 7);
    }
    if (Platform.isAndroid) {
      await _cleanupAndroidLogs(logRetentionDays: 7, zipRetentionDays: 1);
    }

  }

  // Clear all logs on start if the setting is enabled (default: true).
  // Scheduled as a post-frame callback so runApp() is never blocked —
  // calling FlutterLogs.clearLogs() before runApp() can deadlock on Android
  // because PLog holds an open write handle to the log file created by initLogs().
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      final storage = sec_store.FlutterSecureStorage(
        aOptions: const sec_store.AndroidOptions(
          keyCipherAlgorithm: sec_store.KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
          storageCipherAlgorithm: sec_store.StorageCipherAlgorithm.AES_GCM_NoPadding,
        ),
        iOptions: const sec_store.IOSOptions(
          accessibility: sec_store.KeychainAccessibility.first_unlock,
        ),
      );
      final clearValue = await storage.read(key: FluxNewsState.secureStorageClearLogsOnStartKey);
      final shouldClear = clearValue == null || clearValue == FluxNewsState.secureStorageTrueString;
      if (shouldClear) {
        await FlutterLogs.clearLogs();
      }
    } catch (_) {
      // Non-critical — swallow silently.
    }
  });

  if (Platform.isAndroid || Platform.isIOS) {
    FlutterLogs.logInfo(FluxNewsState.logTag, 'main', 'App starting - platform: ${Platform.operatingSystem}');
  }

  // Start audio handler init without blocking — on iOS, AudioService.init()
  // may hang in headless CarPlay launch (no UIWindowScene). The handler is
  // cached; any code that needs it calls initFluxNewsAudioHandler() and awaits.
  if (Platform.isAndroid || Platform.isIOS) {
    FlutterLogs.logInfo(FluxNewsState.logTag, 'main', 'Starting AudioService.init() asynchronously');
  }
  final audioHandlerFuture = initFluxNewsAudioHandler();
  audioHandlerFuture.then((_) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logInfo(FluxNewsState.logTag, 'main', 'AudioService.init() completed');
    }
  }).onError((e, _) {
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterLogs.logError(FluxNewsState.logTag, 'main', 'AudioService.init() failed: $e');
    }
  });

  if (Platform.isIOS) {
    FlutterLogs.logInfo(FluxNewsState.logTag, 'main', 'Initializing CarPlay service');
    initFluxNewsCarPlayService(audioHandlerFuture);
  }

  if (Platform.isAndroid || Platform.isIOS) {
    FlutterLogs.logInfo(FluxNewsState.logTag, 'main', 'Calling runApp()');
  }
  runApp(const SDTFScope(child: FluxNews()));
}

/// Deletes monthly iOS log files (Log-YYYY-MM.txt) whose entire month ended
/// more than [retentionDays] ago.  The iOS flutter_logs plugin writes one file
/// per calendar month into Application Support/Logs/ and ignores the
/// logsRetentionPeriodInDays parameter, so we handle cleanup ourselves.
Future<void> _cleanupIosLogs({required int retentionDays}) async {
  try {
    final appSupport = await getApplicationSupportDirectory();
    final logsDir = Directory('${appSupport.path}/Logs');
    if (!logsDir.existsSync()) return;

    final cutoff = DateTime.now().subtract(Duration(days: retentionDays));

    await for (final entity in logsDir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.path.split('/').last;

      // Match Log-YYYY-MM.txt or Log-YYYY-MM.log
      final match = RegExp(r'^Log-(\d{4})-(\d{2})\.\w+$').firstMatch(name);
      if (match == null) continue;

      final year = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);

      // Last day of that month: first day of next month minus one day.
      final lastDayOfMonth = (month < 12)
          ? DateTime(year, month + 1, 1).subtract(const Duration(days: 1))
          : DateTime(year + 1, 1, 1).subtract(const Duration(days: 1));

      if (lastDayOfMonth.isBefore(cutoff)) {
        await entity.delete();
      }
    }
  } catch (_) {
    // Non-critical — skip silently if the directory is inaccessible.
  }
}

/// Deletes Android log directories older than [logRetentionDays] and
/// exported ZIP files older than [zipRetentionDays].
/// flutter_logs' native retention logic is unreliable on Android — this
/// Dart-side cleanup runs at every startup instead.
///
/// PLog names date directories with the format ddMMyyyy (e.g. "03052026").
Future<void> _cleanupAndroidLogs({
  required int logRetentionDays,
  required int zipRetentionDays,
}) async {
  try {
    final extDir = await getExternalStorageDirectory();
    if (extDir == null) {
      FlutterLogs.logError(FluxNewsState.logTag, '_cleanupAndroidLogs', 'extDir is null — skipping cleanup');
      return;
    }

    final now = DateTime.now();
    final logCutoff = now.subtract(Duration(days: logRetentionDays));
    final zipCutoff = now.subtract(Duration(days: zipRetentionDays));

    final logsDir = Directory('${extDir.path}/${FluxNewsState.logsWriteDirectoryName}');
    FlutterLogs.logInfo(FluxNewsState.logTag, '_cleanupAndroidLogs',
        'logsDir: ${logsDir.path} | exists: ${logsDir.existsSync()} | cutoff: $logCutoff');

    if (logsDir.existsSync()) {
      await _deleteOldLogDirs(logsDir, logCutoff);
    }

    // Delete Dart-exported ZIP files (flux_news_logs_*.zip) at the extDir root
    // that are older than the ZIP retention window.
    for (final entity in extDir.listSync(followLinks: false)) {
      if (entity is File &&
          entity.path.split('/').last.startsWith('flux_news_logs_') &&
          entity.path.endsWith('.zip')) {
        if (entity.statSync().modified.isBefore(zipCutoff)) {
          await entity.delete();
        }
      }
    }
  } catch (e) {
    FlutterLogs.logError(FluxNewsState.logTag, '_cleanupAndroidLogs', 'Error: $e');
  }
}

/// Tries to parse a PLog date-directory name into a [DateTime].
/// Attempts all formats PLog is known to use across versions:
///   dd-MM-yyyy  (e.g. 03-05-2026)
///   ddMMyyyy    (e.g. 03052026)
///   MM-dd-yyyy  (e.g. 05-03-2026)
///   yyyy-MM-dd  (e.g. 2026-05-03)
/// Returns null when none of the patterns match.
DateTime? _parsePLogDirDate(String name) {
  // dd-MM-yyyy  (e.g. 03-05-2026) — most common PLog format
  var m = RegExp(r'^(\d{2})-(\d{2})-(\d{4})$').firstMatch(name);
  if (m != null) {
    return DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
  }
  // ddMMyyyy  (e.g. 03052026)
  m = RegExp(r'^(\d{2})(\d{2})(\d{4})$').firstMatch(name);
  if (m != null) {
    return DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
  }
  // yyyy-MM-dd  (e.g. 2026-05-03)
  m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(name);
  if (m != null) {
    return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }
  return null;
}

/// Scans [dir] for date-named subdirectories and deletes those older than
/// [cutoff]. If a subdirectory has no date name (e.g. "Logs") it descends
/// one level deeper, which handles PLog's FluxNewsLogs/Logs/ddMMyyyy/ layout.
/// The nested export directory (same name as [FluxNewsState.logsWriteDirectoryName])
/// is always skipped.
Future<void> _deleteOldLogDirs(Directory dir, DateTime cutoff) async {
  for (final entity in dir.listSync(followLinks: false)) {
    if (entity is! Directory) continue;
    final name = entity.path.split('/').last;
    if (name == FluxNewsState.logsWriteDirectoryName) continue;
    final dirDate = _parsePLogDirDate(name);
    if (dirDate != null) {
      final shouldDelete = dirDate.isBefore(cutoff);
      FlutterLogs.logInfo(FluxNewsState.logTag, '_cleanupAndroidLogs',
          'Dir "$name" → $dirDate | delete: $shouldDelete');
      if (shouldDelete) await entity.delete(recursive: true);
    } else {
      FlutterLogs.logInfo(FluxNewsState.logTag, '_cleanupAndroidLogs',
          'Dir "$name" — descending');
      await _deleteOldLogDirs(entity, cutoff);
    }
  }
}

class FluxNews extends StatelessWidget {
  const FluxNews({super.key});

  @override
  Widget build(BuildContext context) {
    // init the log export channel to receive the exported log file name and share the file
    FlutterLogs.channel.setMethodCallHandler((call) async {
      if (call.method == 'logsPrinted') {
        LogPrintedService.instance.addChunk(call.arguments.toString());
      } else if (call.method == 'logsExported') {
        String zipName = call.arguments.toString();
        Directory? externalDirectory;

        if (Platform.isIOS) {
          externalDirectory = await getApplicationDocumentsDirectory();
        } else {
          externalDirectory = await getExternalStorageDirectory();
        }

        File file = File("${externalDirectory!.path}/$zipName");
        if (file.existsSync()) {
          if (Platform.isAndroid) {
            //Share.shareXFiles([XFile("${externalDirectory.path}/$zipName")]);
            SharePlus.instance.share(ShareParams(files: [XFile("${externalDirectory.path}/$zipName")]));
          } else {
            if (context.mounted) {
              final box = context.findRenderObject() as RenderBox?;
              SharePlus.instance.share(ShareParams(
                  files: [XFile("${externalDirectory.path}/$zipName")],
                  sharePositionOrigin: box != null ? box.localToGlobal(Offset.zero) & const Size(100, 100) : null));
            }
          }
        } else {
          if (Platform.isAndroid || Platform.isIOS) {
            FlutterLogs.logError(FluxNewsState.logTag, "existsSync", "File not found in storage.");
          }
        }
      }
    });
    return ChangeNotifierProvider(
      create: (context) => FluxNewsState(),
      builder: (context, child) {
        return ChangeNotifierProvider(
          create: (context) => FluxNewsCounterState(),
          builder: (context, child) {
            return ChangeNotifierProvider(
              create: (context) => FluxNewsThemeState(),
              builder: (context, child) {
                return getMaterialApp(context);
              },
            );
          },
        );
      },
    );
  }

  Widget getMaterialApp(BuildContext context) {
    FluxNewsState appState = context.read<FluxNewsState>();
    FluxNewsThemeState themeState = context.watch<FluxNewsThemeState>();

    // read the date format of the system and assign it to the date format variable
    final mediumDatePattern = SystemDateTimeFormat.of(context).mediumDatePattern;
    final timePattern = SystemDateTimeFormat.of(context).timePattern;
    final dateFormatString = '$mediumDatePattern $timePattern';
    appState.dateFormat = DateFormat(dateFormatString);

    // init the dynamic color selection.
    // if the device is capable, we read the configured color scheme of the device
    // and add it as the seed of the app color scheme.
    return DynamicColorBuilder(builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        // setting theme mode depending on the settings
        themeMode: themeState.brightnessMode == FluxNewsState.brightnessModeSystemString
            ? ThemeMode.system
            : themeState.brightnessMode == FluxNewsState.brightnessModeDarkString
                ? ThemeMode.dark
                : ThemeMode.light,
        // define the theme for the light theme
        theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: themeState.getLightColorScheme(lightDynamic),
            iconTheme: const IconThemeData(
              color: Colors.black54,
            ),
            listTileTheme: const ListTileThemeData(
              iconColor: Colors.black54,
            ),
            expansionTileTheme: const ExpansionTileThemeData(iconColor: Colors.black54),
            primaryIconTheme: const IconThemeData(
              color: Colors.black54,
            ),
            textSelectionTheme: const TextSelectionThemeData(cursorColor: Colors.black54),
            appBarTheme: AppBarTheme(
              systemOverlayStyle: SystemUiOverlayStyle(
                  //systemNavigationBarColor: Colors.white10,
                  //statusBarColor: Colors.white.withValues(alpha: 0.0),
                  statusBarIconBrightness: Brightness.dark,
                  systemNavigationBarIconBrightness: Brightness.dark),
              iconTheme: const IconThemeData(
                color: Colors.black54,
              ),
            ),
            cardTheme: CardThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15.0),
              ),
              clipBehavior: Clip.antiAlias,
              elevation: 5,
            ),
            textTheme: const TextTheme(
              headlineMedium: TextStyle(color: Colors.black54),
              headlineSmall: TextStyle(color: Colors.black54),
              bodySmall: TextStyle(color: Colors.black54),
              bodyMedium: TextStyle(color: Colors.black54),
              bodyLarge: TextStyle(color: Colors.black54),
              titleSmall: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold),
              titleLarge: TextStyle(color: Colors.black54, fontSize: 18, fontWeight: FontWeight.bold),
              labelLarge: TextStyle(color: Colors.black54, fontSize: 16),
              labelMedium: TextStyle(color: Colors.black54),
              titleMedium: TextStyle(color: Colors.black54, fontWeight: FontWeight.normal),
            ),
            disabledColor: Colors.black26),
        // define the theme for the dark theme
        darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: themeState.getDarkColorScheme(darkDynamic),
            iconTheme: const IconThemeData(
              color: Colors.white70,
            ),
            listTileTheme: const ListTileThemeData(
              iconColor: Colors.white70,
            ),
            expansionTileTheme: const ExpansionTileThemeData(iconColor: Colors.white70),
            primaryIconTheme: const IconThemeData(
              color: Colors.white70,
            ),
            textSelectionTheme: const TextSelectionThemeData(cursorColor: Colors.white70),
            popupMenuTheme: PopupMenuThemeData(
              color: themeState.useBlackMode ? Colors.black : null,
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: themeState.useBlackMode ? Colors.black : null,
            ),
            appBarTheme: AppBarTheme(
              systemOverlayStyle: SystemUiOverlayStyle(
                  //systemNavigationBarColor: Colors.black.withValues(alpha: 0.1),
                  //statusBarColor: Colors.black.withValues(alpha: 0.0),
                  statusBarIconBrightness: Brightness.light,
                  systemNavigationBarIconBrightness: Brightness.light),
              iconTheme: const IconThemeData(
                color: Colors.white70,
              ),
              foregroundColor: Colors.white70,
            ),
            cardTheme: CardThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15.0),
              ),
              clipBehavior: Clip.antiAlias,
              elevation: 5,
              color: themeState.useBlackMode ? Colors.black : null,
            ),
            textTheme: const TextTheme(
              headlineMedium: TextStyle(color: Colors.white70),
              headlineSmall: TextStyle(color: Colors.white70),
              bodySmall: TextStyle(color: Colors.white70),
              bodyMedium: TextStyle(color: Colors.white70),
              bodyLarge: TextStyle(color: Colors.white70),
              titleSmall: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
              titleLarge: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold),
              labelLarge: TextStyle(color: Colors.white70, fontSize: 16),
              labelMedium: TextStyle(color: Colors.white70),
              titleMedium: TextStyle(color: Colors.white70, fontWeight: FontWeight.normal),
            ),
            disabledColor: Colors.white30,
            drawerTheme: DrawerThemeData(
              backgroundColor: themeState.useBlackMode ? Colors.black : null,
            )),
        // define routes for main view (FluxNewsBody), settings view and search view
        routes: {
          FluxNewsState.rootRouteString: (context) => const FluxNewsBody(),
          FluxNewsState.welcomeRouteString: (context) => const Welcome(),
          FluxNewsState.loginRouteString: (context) => const Login(),
          FluxNewsState.feedOnboardingRouteString: (context) => const FeedOnboarding(),
          FluxNewsState.restoreSettingsRouteString: (context) => const RestoreSettingsPage(),
          FluxNewsState.settingsRouteString: (context) => const Settings(),
          FluxNewsState.searchRouteString: (context) => const Search(),
          FluxNewsState.feedSettingsRouteString: (context) => const FeedSettings(),
          FluxNewsState.generalSettingsRouteString: (context) => const GeneralSettings(),
          FluxNewsState.syncSettingsRouteString: (context) => const SyncSettings(),
          FluxNewsState.newsItemSettingsRouteString: (context) => const NewsItemSettings(),
          FluxNewsState.truncateSettingsRouteString: (context) => const TruncateSettings(),
          FluxNewsState.headerSettingsRouteString: (context) => const HeaderSettings(),
        },
        // define localization with english as fallback
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [
          Locale('en', ''),
          Locale('de', ''),
          Locale('tr', ''),
          Locale('nl', ''),
        ],
      );
    });
  }
}
