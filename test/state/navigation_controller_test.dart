import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/state/navigation_controller.dart';

void main() {
  group('NavigationController', () {
    test('starts on the tasks tab by default', () {
      expect(NavigationController().current, AppTab.tasks);
    });

    test('can start on a given tab', () {
      final nav = NavigationController(initialTab: AppTab.map);
      expect(nav.current, AppTab.map);
    });

    test('select switches tab and notifies listeners once', () {
      final nav = NavigationController();
      var notifications = 0;
      nav.addListener(() => notifications++);

      nav.select(AppTab.map);

      expect(nav.current, AppTab.map);
      expect(notifications, 1);
    });

    test('selecting the current tab does not notify', () {
      final nav = NavigationController();
      var notifications = 0;
      nav.addListener(() => notifications++);

      nav.select(AppTab.tasks);

      expect(notifications, 0);
    });

    test('tab order matches bottom navigation order', () {
      // HomeShell maps NavigationBar indexes to AppTab.values, so this
      // order is part of the UI contract.
      expect(AppTab.values, [AppTab.tasks, AppTab.map]);
    });
  });
}
