import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/app.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/task.dart';
import 'package:questmark/models/geocode_result.dart';
import 'package:questmark/state/navigation_controller.dart';
import 'package:questmark/state/settings_controller.dart';

import '../helpers/fake_geocoding_service.dart';
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
        geocodingService: FakeGeocodingService(),
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
        geocodingService: FakeGeocodingService(),
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
        geocodingService: FakeGeocodingService(),
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
        geocodingService: FakeGeocodingService(),
        mapBaseLayer: const SizedBox.shrink(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New quest'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('titleField')), 'Pinned');
      await tester.tap(find.byKey(const Key('pickLocationButton')));
      await tester.pumpAndSettle();
      expect(find.text('Choose location'), findsOneWidget);

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
  group('address search and lookup (full app, Phase 7)', () {
    final oodi = GeocodeResult(
      label: 'Oodi, Töölönlahdenkatu 4, Helsinki',
      fullName: 'Oodi, 4, Töölönlahdenkatu, Helsinki, Suomi',
      point: GeoPoint(60.17378, 24.93795),
    );

    Future<FakeTaskRepository> pumpApp(
        WidgetTester tester, FakeGeocodingService geo) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final repo = FakeTaskRepository();
      await tester.pumpWidget(QuestMarkApp(
        taskRepository: repo,
        locationService: FakeLocationService(),
        lastLocationRepository:
            FakeLastLocationRepository(fixAt(60.17, 24.94)),
        geocodingService: geo,
        mapBaseLayer: const SizedBox.shrink(),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New quest'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('titleField')), 'Return books');
      await tester.tap(find.byKey(const Key('pickLocationButton')));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('search -> choose a result -> Save: the quest gets that '
        'place and its address, with no extra lookup', (tester) async {
      final geo = FakeGeocodingService(searches: {'oodi': [oodi]});
      final repo = await pumpApp(tester, geo);

      await tester.enterText(
          find.byKey(const Key('addressSearchField')), 'oodi');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addressResult-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('useLocationButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = (await repo.getAll()).single;
      expect(saved.address, oodi.label);
      expect(saved.location!.latitude, closeTo(oodi.point.latitude, 1e-6));
      expect(geo.reverseCalls, isEmpty, reason: 'it already has an address');
    });

    testWidgets('placing by moving the map -> Save: the address is looked '
        'up afterwards', (tester) async {
      final geo = FakeGeocodingService(
          addresses: {GeoPoint(60.17, 24.94): 'Kaivokatu, Helsinki'});
      final repo = await pumpApp(tester, geo);

      await tester.tap(find.byKey(const Key('useLocationButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(geo.reverseCalls, [GeoPoint(60.17, 24.94)]);
      expect((await repo.getAll()).single.address, 'Kaivokatu, Helsinki');
    });
  });
  group('Settings (Phase 9a, D28)', () {
    late SettingsController settings;

    Future<void> pumpWithSettings(WidgetTester tester) async {
      settings = SettingsController();
      await tester.pumpWidget(QuestMarkApp(
        taskRepository: FakeTaskRepository(),
        locationService: FakeLocationService(),
        lastLocationRepository: FakeLastLocationRepository(),
        geocodingService: FakeGeocodingService(),
        settings: settings,
        mapBaseLayer: const SizedBox.shrink(),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> openSettings(WidgetTester tester) async {
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settingsMenuItem')));
      await tester.pumpAndSettle();
    }

    testWidgets('a gear item below "Recycle bin" in the ⋮ menu',
        (tester) async {
      await pumpWithSettings(tester);
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      final bin = tester.getTopLeft(find.text('Recycle bin'));
      final item = find.byKey(const Key('settingsMenuItem'));
      expect(tester.getTopLeft(item).dy, greaterThan(bin.dy));
      expect(
          find.descendant(
              of: item, matching: find.byIcon(Icons.settings_outlined)),
          findsOneWidget);
    });

    testWidgets('opens Settings; dark mode changes the whole app',
        (tester) async {
      await pumpWithSettings(tester);
      await openSettings(tester);
      expect(find.text('High contrast mode'), findsOneWidget);

      await tester.tap(find.byKey(const Key('themeMode-dark')));
      await tester.pumpAndSettle();
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);
      expect(Theme.of(tester.element(find.text('Settings'))).brightness,
          Brightness.dark);
    });

    testWidgets('high contrast changes the colours at once', (tester) async {
      await pumpWithSettings(tester);
      await openSettings(tester);
      await tester.tap(find.byKey(const Key('themeMode-light')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('highContrastSwitch')));
      await tester.pumpAndSettle();
      final scheme =
          Theme.of(tester.element(find.text('Settings'))).colorScheme;
      expect(scheme.surface, Colors.white);
      expect(scheme.onSurfaceVariant, Colors.black);
    });

    testWidgets('the phone\'s own high-contrast setting is honoured too',
        (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpWithSettings(tester);
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      final scheme =
          Theme.of(tester.element(find.text('Recycle bin'))).colorScheme;
      expect(scheme.onSurfaceVariant, scheme.onSurface);
    });
  });
}
