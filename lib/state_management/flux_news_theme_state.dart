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
    return lightColorScheme;
  }

  ColorScheme getDarkColorScheme(ColorScheme? dynamic) {
    if (dynamic != null) {
      darkColorScheme = dynamic.harmonized();
    }
    if (useBlackMode) {
      darkColorScheme = darkColorScheme.copyWith(surface: Colors.black);
    }
    return darkColorScheme;
  }

  // notify the listeners of FluxNewsState to refresh views
  void refreshView() {
    notifyListeners();
  }
}
