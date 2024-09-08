import 'dart:async';
import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/flux_news_localizations.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flux_news/state_management/flux_news_counter_state.dart';
import 'package:flux_news/ui/feed_settings.dart';
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
            Share.shareXFiles([XFile("${externalDirectory.path}/$zipName")]);
          } else {
            if (context.mounted) {
              final box = context.findRenderObject() as RenderBox?;
              Share.shareXFiles([XFile("${externalDirectory.path}/$zipName")],
                  sharePositionOrigin: box!.localToGlobal(Offset.zero) & const Size(100, 100));
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
            return getMaterialApp(context);
          },
        );
      },
    );
  }

  Widget getMaterialApp(BuildContext context) {
    FluxNewsState appState = context.read<FluxNewsState>();
    // read the date format of the system and assign it to the date format variable
    final mediumDatePattern = SystemDateTimeFormat.of(context).mediumDatePattern;
    final timePattern = SystemDateTimeFormat.of(context).timePattern;
    final dateFormatString = '$mediumDatePattern $timePattern';
    appState.dateFormat = DateFormat(dateFormatString);

    // init the dynamic color selection.
    // if the device is capable, we read the configured color scheme of the device
    // and add it as the seed of the app color scheme.
    return DynamicColorBuilder(builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
      ColorScheme lightColorScheme;
      ColorScheme darkColorScheme;

      if (lightDynamic != null && darkDynamic != null) {
        // On Android S+ devices, use the provided dynamic color scheme.
        lightColorScheme = lightDynamic.harmonized();

        // Repeat for the dark color scheme.
        darkColorScheme = darkDynamic.harmonized();
      } else {
        // Otherwise, use fallback schemes.
        lightColorScheme = ColorScheme.fromSeed(
          seedColor: Colors.lightBlue,
        );
        darkColorScheme = ColorScheme.fromSeed(
          seedColor: Colors.lightBlue,
          brightness: Brightness.dark,
        );
      }
      return MaterialApp(
        // setting theme mode depending on the settings
        themeMode: appState.brightnessMode == FluxNewsState.brightnessModeSystemString
            ? ThemeMode.system
            : appState.brightnessMode == FluxNewsState.brightnessModeDarkString
                ? ThemeMode.dark
                : ThemeMode.light,
        // define the theme for the light theme
        theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: lightColorScheme,
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
                  statusBarColor: Colors.white.withOpacity(0.0),
                  statusBarIconBrightness: Brightness.dark,
                  systemNavigationBarIconBrightness: Brightness.dark),
              iconTheme: const IconThemeData(
                color: Colors.black54,
              ),
            ),
            cardTheme: CardTheme(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15.0),
                ),
                clipBehavior: Clip.antiAlias,
                elevation: 5),
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
            colorScheme: darkColorScheme,
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
            appBarTheme: AppBarTheme(
              systemOverlayStyle: SystemUiOverlayStyle(
                  systemNavigationBarColor: Colors.black.withOpacity(0.1),
                  statusBarColor: Colors.black.withOpacity(0.0),
                  statusBarIconBrightness: Brightness.light,
                  systemNavigationBarIconBrightness: Brightness.light),
              iconTheme: const IconThemeData(
                color: Colors.white70,
              ),
              foregroundColor: Colors.white70,
            ),
            cardTheme: CardTheme(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15.0),
              ),
              clipBehavior: Clip.antiAlias,
              elevation: 5,
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
            disabledColor: Colors.white30),
        // define routes for main view (FluxNewsBody), settings view and search view
        routes: {
          FluxNewsState.rootRouteString: (context) => const FluxNewsBody(),
          FluxNewsState.settingsRouteString: (context) => const Settings(),
          FluxNewsState.searchRouteString: (context) => const Search(),
          FluxNewsState.feedSettingsRouteString: (context) => const FeedSettings(),
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
