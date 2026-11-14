import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/app.dart';
import 'package:questmark/state/navigation_controller.dart';

import '../helpers/fake_task_repository.dart';

void main() {
  group('HomeShell', () {
    Future<void> pumpApp(WidgetTester tester,
        [NavigationController? nav]) async {
      await tester.pumpWidget(QuestMarkApp(
        taskRepository: FakeTaskRepository(),
        navigationController: nav,
      ));
      await tester.pumpAndSettle(); // let the task list finish loading
    }

    testWidgets('app boots on the quest list', (tester) async {
      await pumpApp(tester);

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('No quests yet'), findsOneWidget);
      // The map page is kept alive in the IndexedStack but is offstage.
      expect(find.text('Map coming soon'), findsNothing);
    });

    testWidgets('tapping Map shows the map page, tapping Quests goes back',
        (tester) async {
      final nav = NavigationController();
      await pumpApp(tester, nav);

      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();

      expect(nav.current, AppTab.map);
      expect(find.text('Map coming soon'), findsOneWidget);
      expect(find.text('No quests yet'), findsNothing);

      await tester.tap(find.text('Quests').last);
      await tester.pumpAndSettle();

      expect(nav.current, AppTab.tasks);
      expect(find.text('No quests yet'), findsOneWidget);
    });

    testWidgets('switching tabs from code updates the UI', (tester) async {
      // This is the mechanism phase 4 ("show on map") relies on.
      final nav = NavigationController();
      await pumpApp(tester, nav);

      nav.select(AppTab.map);
      await tester.pumpAndSettle();

      expect(find.text('Map coming soon'), findsOneWidget);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, AppTab.map.index);
    });

    testWidgets('both pages stay mounted when switching tabs',
        (tester) async {
      final nav = NavigationController();
      await pumpApp(tester, nav);

      nav.select(AppTab.map);
      await tester.pumpAndSettle();

      // skipOffstage: false also finds the hidden page. It must still be
      // in the tree, so its state (e.g. the map camera) survives.
      expect(find.text('No quests yet', skipOffstage: false), findsOneWidget);
    });
  });
}
