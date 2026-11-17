import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/task.dart';
import 'package:questmark/state/task_list_controller.dart';
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
  final espoo = GeoPoint(60.21, 24.66);

  /// Pumps the map page with an empty base layer (no network). Animations
  /// are switched off, so pumpAndSettle can finish despite the bobbing
  /// markers.
  Future<FakeTaskRepository> pumpMap(WidgetTester tester, List<Task> tasks) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final repo = FakeTaskRepository(tasks);
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => TaskListController(repo, clock: () => now)..load(),
      child: MaterialApp(
        home: MapPage(baseLayer: const SizedBox.shrink(), clock: () => now),
      ),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

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
      seed(3, 'Return books', at: espoo, done: true),
    ]);

    expect(find.byType(QuestMarker), findsNWidgets(2));
    expect(markerFor(1), findsOneWidget);
    expect(markerFor(2), findsNothing);
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
      seed(2, 'finished', at: espoo, done: true),
    ]);

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
    expect(tester.widget<QuestMarker>(find.byType(QuestMarker)).kind,
        QuestMarkerKind.done);
  });

  testWidgets('Reopen is offered for a completed quest', (tester) async {
    final repo =
        await pumpMap(tester, [seed(1, 'Buy milk', at: helsinki, done: true)]);

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
}
