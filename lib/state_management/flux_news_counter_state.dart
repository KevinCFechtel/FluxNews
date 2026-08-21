import 'package:material_ui/material_ui.dart';

class FluxNewsCounterState extends ChangeNotifier {
  // vars for counter
  int _starredCount = 0;
  int _allNewsCount = 0;
  int _appBarNewsCount = 0;
  bool listUpdated = false;

  final ValueNotifier<int> starredCountListenable = ValueNotifier(0);
  final ValueNotifier<int> allNewsCountListenable = ValueNotifier(0);
  final ValueNotifier<int> appBarNewsCountListenable = ValueNotifier(0);

  int get starredCount => _starredCount;
  set starredCount(int value) {
    _starredCount = value;
    starredCountListenable.value = value;
  }

  int get allNewsCount => _allNewsCount;
  set allNewsCount(int value) {
    _allNewsCount = value;
    allNewsCountListenable.value = value;
  }

  int get appBarNewsCount => _appBarNewsCount;
  set appBarNewsCount(int value) {
    _appBarNewsCount = value;
    appBarNewsCountListenable.value = value;
  }

  // notify the listeners of FluxNewsState to refresh views
  void refreshView() {
    notifyListeners();
  }

  @override
  void dispose() {
    starredCountListenable.dispose();
    allNewsCountListenable.dispose();
    appBarNewsCountListenable.dispose();
    super.dispose();
  }
}
