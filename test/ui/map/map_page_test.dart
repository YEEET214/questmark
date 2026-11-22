import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/task.dart';
import 'package:questmark/services/location_service.dart';
import 'package:questmark/state/location_controller.dart';
import 'package:questmark/state/map_focus_controller.dart';
import 'package:questmark/state/task_list_controller.dart';
import 'package:questmark/ui/map/map_config.dart';
import 'package:questmark/ui/map/map_controls.dart';
import 'package:questmark/ui/map/map_page.dart';
import 'package:questmark/ui/map/quest_details_sheet.dart';
import 'package:questmark/ui/map/quest_marker.dart';
import 'package:questmark/ui/tasks/task_editor_page.dart';

import '../../helpers/fake_location_service.dart';
import '../../helpers/fake_task_repository.dart';

void main() {
  final now = DateTime(2026, 11, 14, 10);

  Task seed(int id, String title,
          {GeoPoint? at, bool done = false, DateTime? due}) =>
      Task(
        id: id,
        title: title,
        location: at,
        isDone: done,
        dueAt: due,
        createdAt: DateTime.utc(2026, 1, id),
      );

  final helsinki = GeoPoint(60.17, 24.94);
  // Close enough to Helsinki to stay on screen at quest zoom: flutter_map
  // doesn't build markers that are off screen.
  final nearby = GeoPoint(60.172, 24.946);

  late MapFocusController focus;
  late MapController mapController;
  late FakeLocationService gps;
  late FakeLastLocationRepository savedLocation;
  late LocationController location;

  /// Pumps the map page with an empty base layer (no network). Animations
  /// are switched off, so pumpAndSettle can finish despite the bobbing
  /// markers (and camera moves are instant). [before] runs before the map
  /// is built, e.g. to queue a focus request.
  ///
  /// Location defaults to "allowed and on, no fix yet". Pass [gpsService]
  /// / [saved] to change that.
  Future<FakeTaskRepository> pumpMap(
    WidgetTester tester,
    List<Task> tasks, {
    void Function()? before,
    FakeLocationService? gpsService,
    FakeLastLocationRepository? saved,
  }) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final repo = FakeTaskRepository(tasks);
    focus = MapFocusController();
    mapController = MapController();
    gps = gpsService ?? FakeLocationService();
    savedLocation = saved ?? FakeLastLocationRepository();
    location = LocationController(gps, savedLocation, clock: () => now);
    before?.call();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(
            create: (_) => TaskListController(repo, clock: () => now)..load()),
        ChangeNotifierProvider.value(value: focus),
        ChangeNotifierProvider(create: (_) => location..start()),
      ],
      child: MaterialApp(
        home: MapPage(
          baseLayer: const SizedBox.shrink(),
          clock: () => now,
          mapController: mapController,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  Future<void> tapByKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  Future<void> showCompleted(WidgetTester tester) =>
      tapByKey(tester, 'toggleCompletedButton');

  Finder markerFor(int id) => find.byKey(ValueKey('quest-marker-$id'));

  testWidgets('shows the map with attribution even without quests',
      (tester) async {
    await pumpMap(tester, []);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byType(QuestMarker), findsNothing);
    expect(find.byType(RichAttributionWidget), findsOneWidget);
  });

  testWidgets('one marker per located quest; list-only quests are skipped',
      (tester) async {
    await pumpMap(tester, [
      seed(1, 'Buy milk', at: helsinki),
      seed(2, 'Call mum'), // no location
      seed(3, 'Return books', at: nearby, done: true),
    ]);

    // The completed quest (3) is hidden by default (PLAN.md D17).
    expect(find.byType(QuestMarker), findsOneWidget);
    expect(markerFor(1), findsOneWidget);
    expect(markerFor(2), findsNothing);
    expect(markerFor(3), findsNothing);

    await showCompleted(tester);
    expect(find.byType(QuestMarker), findsNWidgets(2));
    expect(markerFor(3), findsOneWidget);
  });

  testWidgets('bottom-left badge counts tasks without a location',
      (tester) async {
    await pumpMap(tester, [
      seed(1, 'on map', at: helsinki),
      seed(2, 'list only'),
      seed(3, 'also list only', done: true),
    ]);

    final badge = find.byKey(const Key('missingLocationBadge'));
    expect(badge, findsOneWidget);
    await tester.tap(badge);
    await tester.pumpAndSettle();
    expect(find.text('2 tasks without locations'), findsOneWidget);

    // It sits in the bottom-left corner of the map.
    final mapRect = tester.getRect(find.byType(FlutterMap));
    final badgeRect = tester.getRect(badge);
    expect(badgeRect.left - mapRect.left, lessThan(24));
    expect(mapRect.bottom - badgeRect.bottom, lessThan(24));
  });

  testWidgets('no badge when every task is on the map', (tester) async {
    await pumpMap(tester, [seed(1, 'on map', at: helsinki)]);
    expect(find.byKey(const Key('missingLocationBadge')), findsNothing);
  });

  testWidgets('marker state follows the task (overdue, done)', (tester) async {
    await pumpMap(tester, [
      seed(1, 'late', at: helsinki, due: DateTime(2026, 11, 1)),
      seed(2, 'finished', at: nearby, done: true),
    ]);
    await showCompleted(tester);

    QuestMarker marker(String title) => tester.widget<QuestMarker>(
        find.byWidgetPredicate((w) => w is QuestMarker && w.task.title == title));
    expect(marker('late').kind, QuestMarkerKind.overdue);
    expect(marker('finished').kind, QuestMarkerKind.done);
  });

  testWidgets('tapping a marker opens the quest details', (tester) async {
    await pumpMap(tester, [
      seed(1, 'Buy milk', at: helsinki, due: DateTime(2026, 11, 20)),
    ]);

    await tester.tap(find.byType(QuestMarker));
    await tester.pumpAndSettle();

    expect(find.byType(QuestDetailsSheet), findsOneWidget);
    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.text('Due 20-11-2026'), findsOneWidget);
    expect(find.text('Complete'), findsOneWidget);
  });

  testWidgets('Complete in the sheet completes the quest and updates the marker',
      (tester) async {
    final repo = await pumpMap(tester, [seed(1, 'Buy milk', at: helsinki)]);

    await tester.tap(find.byType(QuestMarker));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle();

    expect(find.byType(QuestDetailsSheet), findsNothing);
    expect((await repo.getById(1))!.isDone, isTrue);
    // Now completed, so hidden by default; visible again with the toggle.
    expect(find.byType(QuestMarker), findsNothing);
    await showCompleted(tester);
    expect(tester.widget<QuestMarker>(find.byType(QuestMarker)).kind,
        QuestMarkerKind.done);
  });

  testWidgets('Reopen is offered for a completed quest', (tester) async {
    final repo =
        await pumpMap(tester, [seed(1, 'Buy milk', at: helsinki, done: true)]);
    await showCompleted(tester);

    await tester.tap(find.byType(QuestMarker));
    await tester.pumpAndSettle();
    expect(find.text('Completed'), findsOneWidget);
    await tester.tap(find.text('Reopen'));
    await tester.pumpAndSettle();

    expect((await repo.getById(1))!.isDone, isFalse);
  });

  testWidgets('Edit in the sheet opens the editor and saves changes',
      (tester) async {
    final repo = await pumpMap(tester, [seed(1, 'Buy milk', at: helsinki)]);

    await tester.tap(find.byType(QuestMarker));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.byType(TaskEditorPage), findsOneWidget);
    await tester.enterText(find.byKey(const Key('titleField')), 'Buy oat milk');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final edited = (await repo.getById(1))!;
    expect(edited.title, 'Buy oat milk');
    expect(edited.location, helsinki, reason: 'editing must keep the location');
  });

  group('completed-quests toggle', () {
    testWidgets('hidden by default; the toggle shows and hides them',
        (tester) async {
      await pumpMap(tester, [
        seed(1, 'open', at: helsinki),
        seed(2, 'done', at: nearby, done: true),
      ]);
      expect(find.byTooltip('Show completed'), findsOneWidget);
      expect(markerFor(2), findsNothing);

      await showCompleted(tester);
      expect(markerFor(2), findsOneWidget);
      expect(find.byTooltip('Hide completed'), findsOneWidget);

      await showCompleted(tester); // toggles back
      expect(markerFor(2), findsNothing);
    });

    testWidgets('the starting view ignores hidden completed quests',
        (tester) async {
      // One open quest + a far-away completed one: the map centres on the
      // open quest instead of fitting both.
      await pumpMap(tester, [
        seed(1, 'open', at: helsinki),
        seed(2, 'done far away', at: GeoPoint(-33.86, 151.21), done: true),
      ]);
      expect(mapController.camera.center.latitude, closeTo(60.17, 0.01));
      expect(mapController.camera.zoom, MapConfig.questZoom);
    });
  });

  group('zoom buttons', () {
    testWidgets('+ and - change the zoom by one level', (tester) async {
      await pumpMap(tester, [seed(1, 'a', at: helsinki)]);
      final start = mapController.camera.zoom;

      await tapByKey(tester, 'zoomInButton');
      expect(mapController.camera.zoom, closeTo(start + 1, 0.001));

      await tapByKey(tester, 'zoomOutButton');
      await tapByKey(tester, 'zoomOutButton');
      expect(mapController.camera.zoom, closeTo(start - 1, 0.001));
    });

    testWidgets('+ is disabled at the maximum zoom, - at the minimum',
        (tester) async {
      await pumpMap(tester, [seed(1, 'a', at: helsinki)]);

      mapController.move(mapController.camera.center, MapConfig.maxZoom);
      await tester.pumpAndSettle();
      await tapByKey(tester, 'zoomInButton');
      expect(mapController.camera.zoom, MapConfig.maxZoom);

      mapController.move(mapController.camera.center, MapConfig.minZoom);
      await tester.pumpAndSettle();
      await tapByKey(tester, 'zoomOutButton');
      expect(mapController.camera.zoom, MapConfig.minZoom);
    });

    testWidgets('controls sit bottom-right, the badge bottom-left',
        (tester) async {
      await pumpMap(tester, [seed(1, 'on map', at: helsinki), seed(2, 'x')]);
      final map = tester.getRect(find.byType(FlutterMap));
      final zoomIn = tester.getRect(find.byKey(const Key('zoomInButton')));
      final badge =
          tester.getRect(find.byKey(const Key('missingLocationBadge')));
      expect(map.right - zoomIn.right, lessThan(24));
      expect(zoomIn.center.dy, greaterThan(map.center.dy));
      expect(badge.left - map.left, lessThan(24));
      expect(zoomIn.width, MapControls.buttonSize);
    });
  });

  group('Show on map (MapFocusController)', () {
    final tampere = GeoPoint(61.50, 23.76);

    testWidgets('a request centres the camera on the quest and highlights it',
        (tester) async {
      await pumpMap(tester, [
        seed(1, 'Helsinki quest', at: helsinki),
        seed(2, 'Tampere quest', at: tampere),
      ]);

      focus.focusOn(seed(2, 'Tampere quest', at: tampere));
      await tester.pumpAndSettle();

      expect(mapController.camera.center.latitude, closeTo(61.50, 0.001));
      expect(mapController.camera.center.longitude, closeTo(23.76, 0.001));
      expect(mapController.camera.zoom, MapConfig.questZoom);
      expect(focus.pendingRequest, isNull, reason: 'request consumed once');

      QuestMarker marker(int id) => tester.widget<QuestMarker>(find.descendant(
          of: markerFor(id), matching: find.byType(QuestMarker)));
      expect(marker(2).highlighted, isTrue);
    });

    testWidgets('a request made before the map exists sets the start view',
        (tester) async {
      await pumpMap(
        tester,
        [seed(1, 'a', at: helsinki), seed(2, 'b', at: tampere)],
        before: () => focus.focusOn(seed(2, 'b', at: tampere)),
      );
      expect(mapController.camera.center.latitude, closeTo(61.50, 0.001));
      expect(focus.pendingRequest, isNull);
    });

    testWidgets('a completed quest is shown when focused, even while hidden',
        (tester) async {
      final done = seed(2, 'done', at: tampere, done: true);
      await pumpMap(tester, [seed(1, 'a', at: helsinki), done]);
      expect(markerFor(2), findsNothing);

      focus.focusOn(done);
      await tester.pumpAndSettle();
      expect(markerFor(2), findsOneWidget);
    });

    testWidgets('tapping empty map clears the highlight', (tester) async {
      await pumpMap(tester, [seed(1, 'a', at: helsinki)]);
      focus.focusOn(seed(1, 'a', at: helsinki));
      await tester.pumpAndSettle();
      expect(focus.highlightedTaskId, 1);

      // Tap well away from the marker (top-left of the map).
      final map = tester.getRect(find.byType(FlutterMap));
      await tester.tapAt(map.topLeft + const Offset(40, 40));
      // flutter_map reports a single tap only after the double-tap window.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(focus.highlightedTaskId, isNull);
    });
  });
  group('player position (Phase 5, D8 / D19)', () {
    final tampere = GeoPoint(61.50, 23.76);
    final player = find.byKey(const ValueKey('player-marker'));

    void expectCameraAt(double lat, double lng) {
      expect(mapController.camera.center.latitude, closeTo(lat, 0.0001));
      expect(mapController.camera.center.longitude, closeTo(lng, 0.0001));
    }

    Future<void> emit(WidgetTester tester, double lat, double lng) async {
      gps.emit(fixAt(lat, lng));
      await tester.pumpAndSettle();
    }

    Icon myLocationIcon(WidgetTester tester) => tester.widget<Icon>(
        find.descendant(
            of: find.byKey(const Key('myLocationButton')),
            matching: find.byType(Icon)));

    testWidgets('the blue dot appears with the first fix and moves with the '
        'next ones', (tester) async {
      await pumpMap(tester, [seed(1, 'a', at: helsinki)]);
      expect(player, findsNothing, reason: 'no fix yet');

      await emit(tester, 60.171, 24.941);
      expect(player, findsOneWidget);
      final first = tester.getCenter(player);

      await emit(tester, 60.172, 24.946);
      expect(tester.getCenter(player), isNot(first));
      expect(
          find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.label == 'Your location'),
          findsOneWidget,
          reason: 'screen readers announce the dot');
    });

    testWidgets('the dot disappears when location is switched off',
        (tester) async {
      await pumpMap(tester, []);
      await emit(tester, 60.17, 24.94);
      expect(player, findsOneWidget);

      gps.setServiceEnabled(false);
      await tester.pumpAndSettle();
      expect(player, findsNothing);
      expect(myLocationIcon(tester).icon, Icons.location_disabled);
    });

    group('starting view', () {
      testWidgets('starts at the saved last-known position, ahead of the '
          'quests', (tester) async {
        await pumpMap(
          tester,
          [seed(1, 'a', at: helsinki), seed(2, 'b', at: tampere)],
          saved: FakeLastLocationRepository(fixAt(51.5, -0.12)),
        );
        expectCameraAt(51.5, -0.12);
        expect(mapController.camera.zoom, MapConfig.playerZoom);
      });

      testWidgets('without a saved position it fits the quests (as before)',
          (tester) async {
        await pumpMap(tester, [seed(1, 'a', at: helsinki)]);
        expectCameraAt(helsinki.latitude, helsinki.longitude);
      });

      testWidgets('the first fix glides the camera to the user if the map '
          'was not touched', (tester) async {
        await pumpMap(tester, [seed(1, 'a', at: helsinki)]);
        await emit(tester, 61.0, 25.0);
        expectCameraAt(61.0, 25.0);
        expect(mapController.camera.zoom, MapConfig.playerZoom);

        // Later fixes don't move the camera (no follow mode yet).
        await emit(tester, 61.01, 25.0);
        expectCameraAt(61.0, 25.0);
      });

      testWidgets('...but not after the user has dragged the map',
          (tester) async {
        await pumpMap(tester, [seed(1, 'a', at: helsinki)]);
        await tester.drag(find.byType(FlutterMap), const Offset(120, 0));
        await tester.pumpAndSettle();
        final before = mapController.camera.center;

        await emit(tester, 61.0, 25.0);
        expect(mapController.camera.center, before);
      });

      testWidgets('...and not when the map opened on a "Show on map" quest',
          (tester) async {
        await pumpMap(
          tester,
          [seed(1, 'a', at: helsinki), seed(2, 'b', at: tampere)],
          before: () => focus.focusOn(seed(2, 'b', at: tampere)),
        );
        await emit(tester, 61.0, 25.0);
        expectCameraAt(61.50, 23.76);
      });

      testWidgets('...and not when a zoom button was used', (tester) async {
        await pumpMap(tester, [seed(1, 'a', at: helsinki)]);
        await tapByKey(tester, 'zoomOutButton');
        await emit(tester, 61.0, 25.0);
        expectCameraAt(helsinki.latitude, helsinki.longitude);
      });
    });

    group('my-location button', () {
      testWidgets('centres on the user and follows until the map is dragged',
          (tester) async {
        await pumpMap(tester, [seed(1, 'a', at: helsinki)]);
        await tester.drag(find.byType(FlutterMap), const Offset(120, 0));
        await tester.pumpAndSettle();
        await emit(tester, 61.0, 25.0); // touched: camera stays
        expect(myLocationIcon(tester).icon, Icons.location_searching);

        await tapByKey(tester, 'myLocationButton');
        expectCameraAt(61.0, 25.0);
        expect(myLocationIcon(tester).icon, Icons.my_location);

        await emit(tester, 61.2, 25.3);
        expectCameraAt(61.2, 25.3);

        await tester.drag(find.byType(FlutterMap), const Offset(0, 120));
        await tester.pumpAndSettle();
        expect(myLocationIcon(tester).icon, Icons.location_searching);
        final before = mapController.camera.center;
        await emit(tester, 61.4, 25.5);
        expect(mapController.camera.center, before, reason: 'not following');
      });

      testWidgets('zooming with the buttons keeps following', (tester) async {
        await pumpMap(tester, []);
        await emit(tester, 61.0, 25.0);
        await tapByKey(tester, 'myLocationButton');
        await tapByKey(tester, 'zoomInButton');
        expect(myLocationIcon(tester).icon, Icons.my_location);
        await emit(tester, 61.1, 25.1);
        expectCameraAt(61.1, 25.1);
      });

      testWidgets('keeps a closer zoom instead of zooming out to street level',
          (tester) async {
        await pumpMap(tester, []);
        await emit(tester, 61.0, 25.0);
        mapController.move(mapController.camera.center, 18);
        await tester.pumpAndSettle();
        await tapByKey(tester, 'myLocationButton');
        expect(mapController.camera.zoom, 18);
      });

      testWidgets('before the first fix: says it is looking, then centres '
          'when the fix arrives', (tester) async {
        await pumpMap(tester, [seed(1, 'a', at: helsinki)]);
        await tapByKey(tester, 'myLocationButton');
        expect(find.text('Finding your location…'), findsOneWidget);

        await emit(tester, 61.0, 25.0);
        expectCameraAt(61.0, 25.0);
      });

      testWidgets('when blocked: explains and offers the app settings',
          (tester) async {
        await pumpMap(tester, [],
            gpsService: FakeLocationService(
                permission: LocationPermissionState.deniedForever));
        expect(find.byKey(const Key('locationPrompt')), findsNothing,
            reason: 'the OS would not show its dialog anyway');
        expect(myLocationIcon(tester).icon, Icons.location_disabled);

        await tapByKey(tester, 'myLocationButton');
        expect(find.text('Location access is blocked'), findsOneWidget);
        await tester.tap(find.text('Open settings'));
        await tester.pumpAndSettle();
        expect(gps.openedAppSettings, 1);
        expect(gps.requestCount, 0);
      });

      testWidgets('when location is off: offers the location settings',
          (tester) async {
        await pumpMap(tester, [],
            gpsService: FakeLocationService(serviceEnabled: false));
        await tapByKey(tester, 'myLocationButton');
        expect(find.text('Location is turned off'), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(gps.openedLocationSettings, 0);

        await tapByKey(tester, 'myLocationButton');
        await tester.tap(find.text('Open settings'));
        await tester.pumpAndSettle();
        expect(gps.openedLocationSettings, 1);
      });

      testWidgets('when not allowed yet: asks, then follows', (tester) async {
        await pumpMap(tester, [],
            gpsService: FakeLocationService(
                permission: LocationPermissionState.denied));
        await tapByKey(tester, 'myLocationButton');
        expect(gps.requestCount, 1);
        expect(location.status, LocationStatus.on);

        await emit(tester, 61.0, 25.0);
        expectCameraAt(61.0, 25.0);
        expect(myLocationIcon(tester).icon, Icons.my_location);
      });
    });

    group('permission prompt (explain before asking)', () {
      Future<void> pumpDenied(WidgetTester tester,
          {LocationPermissionState answer = LocationPermissionState.granted}) {
        return pumpMap(tester, [],
            gpsService: FakeLocationService(
                permission: LocationPermissionState.denied,
                permissionAfterRequest: answer));
      }

      final prompt = find.byKey(const Key('locationPrompt'));

      testWidgets('is shown while not allowed, without asking the OS yet',
          (tester) async {
        await pumpDenied(tester);
        expect(prompt, findsOneWidget);
        expect(
            find.text('See where you are among your quests'), findsOneWidget);
        expect(gps.requestCount, 0);
      });

      testWidgets('"Allow" shows the OS dialog; granting hides the prompt',
          (tester) async {
        await pumpDenied(tester);
        await tester.tap(find.text('Allow'));
        await tester.pumpAndSettle();
        expect(gps.requestCount, 1);
        expect(prompt, findsNothing);
        expect(gps.isListening, isTrue);
      });

      testWidgets('refusing in the OS dialog also hides it for this session',
          (tester) async {
        await pumpDenied(tester, answer: LocationPermissionState.denied);
        await tester.tap(find.text('Allow'));
        await tester.pumpAndSettle();
        expect(prompt, findsNothing);
        expect(location.status, LocationStatus.denied);
      });

      testWidgets('"Not now" hides it without asking', (tester) async {
        await pumpDenied(tester);
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
        expect(prompt, findsNothing);
        expect(gps.requestCount, 0);
      });
    });
  });
}
