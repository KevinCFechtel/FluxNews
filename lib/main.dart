import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gen/gen_l10n/flux_news_localizations.dart';
import 'package:system_date_time_format/system_date_time_format.dart';

import 'flux_news_body.dart';
import 'flux_news_state.dart';
import 'settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  runApp(const SDTFScope(child: FluxNews()));
}

class FluxNews extends StatelessWidget {
  const FluxNews({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => FluxNewsState(),
      builder: (context, child) {
        return getMaterialApp(context);
      },
    );
  }

  Widget getMaterialApp(BuildContext context) {
    FluxNewsState appState = context.watch<FluxNewsState>();
    // init the dynamic color selection.
    // if the device is capable, we read the configured color scheme of the device
    // and add it as the seed of the app color scheme.
    return DynamicColorBuilder(
        builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
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
        themeMode: appState.brightnessMode ==
                FluxNewsState.brightnessModeSystemString
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
            expansionTileTheme:
                const ExpansionTileThemeData(iconColor: Colors.black54),
            primaryIconTheme: const IconThemeData(
              color: Colors.black54,
            ),
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
              titleLarge: TextStyle(
                  color: Colors.black54,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
              labelLarge: TextStyle(color: Colors.black54, fontSize: 16),
              labelMedium: TextStyle(color: Colors.black54),
              titleMedium: TextStyle(
                  color: Colors.black54, fontWeight: FontWeight.normal),
            )),
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
            expansionTileTheme:
                const ExpansionTileThemeData(iconColor: Colors.white70),
            primaryIconTheme: const IconThemeData(
              color: Colors.white70,
            ),
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
              titleLarge: TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
              labelLarge: TextStyle(color: Colors.white70, fontSize: 16),
              labelMedium: TextStyle(color: Colors.white70),
              titleMedium: TextStyle(
                  color: Colors.white70, fontWeight: FontWeight.normal),
            )),
        // define routes for main view (FluxNewsBody) and settings view
        routes: {
          FluxNewsState.rootRouteString: (context) => const FluxNewsBody(),
          FluxNewsState.settingsRouteString: (context) => const Settings(),
        },
        // define localization with english as fallback
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [
          Locale('en', ''),
          Locale('de', ''),
        ],
      );
    });
  }
}
