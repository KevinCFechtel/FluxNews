import 'dart:async';
import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flux_news/l10n/flux_news_localizations.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flux_news/state_management/flux_news_counter_state.dart';
import 'package:flux_news/state_management/flux_news_theme_state.dart';
import 'package:flux_news/ui/settings/feed_settings.dart';
import 'package:flux_news/ui/settings/general_settings.dart';
import 'package:flux_news/ui/settings/news_item_settings.dart';
import 'package:flux_news/ui/settings/sync_settings.dart';
import 'package:flux_news/ui/settings/truncate_settings.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:system_date_time_format/system_date_time_format.dart';

import 'ui/flux_news_body.dart';
import 'state_management/flux_news_state.dart';
import 'ui/search.dart';
import 'ui/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

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
        isDebuggable: kDebugMode ? true : false);

    // clear the logs on startup
    FlutterLogs.clearLogs();
  }

  runApp(const SDTFScope(child: FluxNews()));
}

class FluxNews extends StatelessWidget {
  const FluxNews({super.key});

  @override
  Widget build(BuildContext context) {
    // init the log export channel to receive the exported log file name and share the file
    FlutterLogs.channel.setMethodCallHandler((call) async {
      if (call.method == 'logsExported') {
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
                  sharePositionOrigin: box!.localToGlobal(Offset.zero) & const Size(100, 100)));
              //Share.shareXFiles([XFile("${externalDirectory.path}/$zipName")],
              //    sharePositionOrigin: box!.localToGlobal(Offset.zero) & const Size(100, 100));
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
                  systemNavigationBarColor: Colors.white10,
                  statusBarColor: Colors.white.withValues(alpha: 0.0),
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
              bodyMedium: TextStyle(color: Colors.black54),
              bodyLarge: TextStyle(color: Colors.black54),
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
                  systemNavigationBarColor: Colors.black.withValues(alpha: 0.1),
                  statusBarColor: Colors.black.withValues(alpha: 0.0),
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
              bodyMedium: TextStyle(color: Colors.white70),
              bodyLarge: TextStyle(color: Colors.white70),
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
          FluxNewsState.settingsRouteString: (context) => const Settings(),
          FluxNewsState.searchRouteString: (context) => const Search(),
          FluxNewsState.feedSettingsRouteString: (context) => const FeedSettings(),
          FluxNewsState.generalSettingsRouteString: (context) => const GeneralSettings(),
          FluxNewsState.syncSettingsRouteString: (context) => const SyncSettings(),
          FluxNewsState.newsItemSettingsRouteString: (context) => const NewsItemSettings(),
          FluxNewsState.truncateSettingsRouteString: (context) => const TruncateSettings(),
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
