import 'package:flutter/material.dart';

class FluxNewsCounterState extends ChangeNotifier {
  // vars for counter
  int starredCount = 0;
  int allNewsCount = 0;
  int appBarNewsCount = 0;
  bool listUpdated = false;

  // notify the listeners of FluxNewsState to refresh views
  void refreshView() {
    notifyListeners();
  }
}
