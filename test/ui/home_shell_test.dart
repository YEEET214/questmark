import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/app.dart';
import 'package:questmark/models/task.dart';
import 'package:questmark/state/navigation_controller.dart';

import '../helpers/fake_location_service.dart';
import '../helpers/fake_task_repository.dart';

void main() {
  group('HomeShell', () {
    Future<void> pumpApp(WidgetTester tester,
        [NavigationController? nav]) async {
      await tester.pumpWidget(QuestMarkApp(
        taskRepository: FakeTaskRepository(),
        locationService: FakeLocationService(),
        lastLocationRepository: FakeLastLocationRepository(),
        navigationController: nav,
        // No real map tiles in tests.
        mapBaseLayer: const SizedBox.shrink(),
      ));
      await tester.pumpAndSettle(); // let the task list finish loading
    }

    testWidgets('app boots on the quest list', (tester) async {
      await pumpApp(tester);

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('No quests yet'), findsOneWidget);
      // The map page is kept alive in the IndexedStack but is offstage.
      expect(find.text('World Map'), findsNothing);
    });

    testWidgets('tapping Map shows the map page, tapping Quests goes back',
        (tester) async {
      final nav = NavigationController();
      await pumpApp(tester, nav);

      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();

      expect(nav.current, AppTab.map);
      expect(find.text('World Map'), findsOneWidget);
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

      expect(find.text('World Map'), findsOneWidget);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, AppTab.map.index);
    });

    testWidgets('the hidden tab has its animations paused', (tester) async {
      final nav = NavigationController();
      await pumpApp(tester, nav);

      bool tickersOn(String pageText) => TickerMode.valuesOf(tester.element(
              find.text(pageText, skipOffstage: false)))
          .enabled;

      expect(tickersOn('No quests yet'), isTrue);
      expect(tickersOn('World Map'), isFalse);

      nav.select(AppTab.map);
      await tester.pumpAndSettle();
      expect(tickersOn('No quests yet'), isFalse);
      expect(tickersOn('World Map'), isTrue);
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

  group('snackbars and the "New quest" button (full app)', () {
    // In the real app the Quests page is nested inside the shell's
    // Scaffold. Snackbars used to go to that outer Scaffold and cover the
    // button; this checks the fix in the real nesting.
    Future<void> pumpWithTasks(WidgetTester tester) async {
      await tester.pumpWidget(QuestMarkApp(
        taskRepository: FakeTaskRepository([
          Task(id: 1, title: 'swipe me', createdAt: DateTime.utc(2026, 1, 2)),
          Task(id: 2, title: 'other', createdAt: DateTime.utc(2026, 1, 1)),
        ]),
        locationService: FakeLocationService(),
        lastLocationRepository: FakeLastLocationRepository(),
        mapBaseLayer: const SizedBox.shrink(),
      ));
      await tester.pumpAndSettle();
    }

    double fabBottom(WidgetTester tester) =>
        tester.getRect(find.byType(FloatingActionButton)).bottom;

    testWidgets('the button moves up above the snackbar, and back down when '
        'it disappears after 4 seconds', (tester) async {
      await pumpWithTasks(tester);
      final resting = fabBottom(tester);

      await tester.drag(find.text('swipe me'), const Offset(-600, 0));
      await tester.pumpAndSettle();

      final snack = find.byType(SnackBar);
      expect(snack, findsOneWidget);
      expect(fabBottom(tester), lessThan(resting), reason: 'moved up');
      expect(fabBottom(tester),
          lessThanOrEqualTo(tester.getRect(snack).top + 0.5),
          reason: 'not covered by the snackbar');

      await tester.pump(const Duration(seconds: 4, milliseconds: 100));
      await tester.pumpAndSettle();
      expect(snack, findsNothing);
      expect(fabBottom(tester), closeTo(resting, 0.5), reason: 'back down');
    });

    testWidgets('the "Completed" Undo snackbar also lifts the button',
        (tester) async {
      await pumpWithTasks(tester);
      final resting = fabBottom(tester);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Completed "'), findsOneWidget);
      expect(fabBottom(tester), lessThan(resting));

      await tester.pump(const Duration(seconds: 4, milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(fabBottom(tester), closeTo(resting, 0.5));
    });
  });
  group('GPS only while the app is in the foreground (D8)', () {
    testWidgets('going to the background stops the GPS; coming back '
        'restarts it', (tester) async {
      final gps = FakeLocationService();
      await tester.pumpWidget(QuestMarkApp(
        taskRepository: FakeTaskRepository(),
        locationService: gps,
        lastLocationRepository: FakeLastLocationRepository(),
        mapBaseLayer: const SizedBox.shrink(),
      ));
      await tester.pumpAndSettle();
      expect(gps.isListening, isTrue);

      for (final s in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pumpAndSettle();
      expect(gps.isListening, isFalse);

      for (final s in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pumpAndSettle();
      expect(gps.isListening, isTrue);
    });
  });
  group('placing a quest with the picker (full app, Phase 6)', () {
    testWidgets('New quest -> Pick on map -> Use this location -> Save: the '
        'quest gets that location and can be shown on the map',
        (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final repo = FakeTaskRepository();
      await tester.pumpWidget(QuestMarkApp(
        taskRepository: repo,
        locationService: FakeLocationService(),
        // The picker starts at the last known position.
        lastLocationRepository:
            FakeLastLocationRepository(fixAt(60.17, 24.94)),
        mapBaseLayer: const SizedBox.shrink(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New quest'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('titleField')), 'Pinned');
      await tester.tap(find.byKey(const Key('pickLocationButton')));
      await tester.pumpAndSettle();
      expect(find.text('Pick location'), findsOneWidget);

      await tester.tap(find.byKey(const Key('useLocationButton')));
      await tester.pumpAndSettle();
      expect(find.text('60.17000, 24.94000'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = (await repo.getAll()).single;
      expect(saved.location!.latitude, closeTo(60.17, 1e-6));
      expect(saved.location!.longitude, closeTo(24.94, 1e-6));
      expect(find.byTooltip('Show on map'), findsOneWidget);
    });
  });
}
