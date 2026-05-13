import 'dart:io';

import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flux_news/state_management/flux_news_state.dart';

class FluxNewsThemeState extends ChangeNotifier {
  String brightnessMode = FluxNewsState.brightnessModeSystemString;
  bool useBlackMode = false;
  ColorScheme lightColorScheme = ColorScheme.fromSeed(
    seedColor: Colors.lightBlue,
  );
  ColorScheme darkColorScheme = ColorScheme.fromSeed(
    seedColor: Colors.lightBlue,
    brightness: Brightness.dark,
  );

  ColorScheme getLightColorScheme(ColorScheme? dynamic) {
    if (dynamic != null) {
      lightColorScheme = dynamic.harmonized();
    }
    if (Platform.isIOS) {
      lightColorScheme = lightColorScheme.copyWith(
        tertiaryContainer: const Color(0xFFB2F0EC),
        onTertiaryContainer: const Color(0xFF002021),
      );
    }
    return lightColorScheme;
  }

  ColorScheme getDarkColorScheme(ColorScheme? dynamic) {
    if (dynamic != null) {
      darkColorScheme = dynamic.harmonized();
    }
    if (useBlackMode) {
      darkColorScheme = darkColorScheme.copyWith(surface: Colors.black);
    }
    if (Platform.isIOS) {
      darkColorScheme = darkColorScheme.copyWith(
        tertiaryContainer: const Color(0xFF004F4B),
        onTertiaryContainer: const Color(0xFFB2F0EC),
      );
    }
    return darkColorScheme;
  }

  // notify the listeners of FluxNewsState to refresh views
  void refreshView() {
    notifyListeners();
  }
}
