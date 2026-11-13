import 'package:flutter/foundation.dart';

/// The top-level destinations of the app, in bottom-navigation order.
enum AppTab { tasks, map }

/// Holds which top-level tab is currently shown.
///
/// The tab index lives in shared state rather than inside the shell
/// widget's `setState` so that other parts of the app can switch tabs.
/// For example, the "show on map" button in the task list (phase 4)
/// calls `select(AppTab.map)` without needing a reference to the shell.
class NavigationController extends ChangeNotifier {
  NavigationController({AppTab initialTab = AppTab.tasks})
      : _current = initialTab;

  AppTab _current;

  AppTab get current => _current;

  /// Switches to [tab]. Listeners are only notified when the tab actually
  /// changes, to avoid pointless rebuilds.
  void select(AppTab tab) {
    if (tab == _current) return;
    _current = tab;
    notifyListeners();
  }
}
