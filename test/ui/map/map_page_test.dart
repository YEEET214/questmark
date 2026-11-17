import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/task.dart';
import 'package:questmark/state/map_focus_controller.dart';
import 'package:questmark/state/task_list_controller.dart';
import 'package:questmark/ui/map/map_config.dart';
import 'package:questmark/ui/map/map_controls.dart';
import 'package:questmark/ui/map/map_page.dart';
import 'package:questmark/ui/map/quest_details_sheet.dart';
import 'package:questmark/ui/map/quest_marker.dart';
import 'package:questmark/ui/tasks/task_editor_page.dart';

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

  /// Pumps the map page with an empty base layer (no network). Animations
  /// are switched off, so pumpAndSettle can finish despite the bobbing
  /// markers (and camera moves are instant). [before] runs before the map
  /// is built, e.g. to queue a focus request.
  Future<FakeTaskRepository> pumpMap(
    WidgetTester tester,
    List<Task> tasks, {
    void Function()? before,
  }) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final repo = FakeTaskRepository(tasks);
    focus = MapFocusController();
    mapController = MapController();
    before?.call();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(
            create: (_) => TaskListController(repo, clock: () => now)..load()),
        ChangeNotifierProvider.value(value: focus),
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
}
