import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:questmark/models/task.dart';
import 'package:questmark/state/task_list_controller.dart';
import 'package:questmark/ui/tasks/recycle_bin_page.dart';

import '../../helpers/fake_task_repository.dart';

void main() {
  final now = DateTime(2026, 11, 22, 10);

  Task binned(int id, String title, {required int daysAgo}) => Task(
        id: id,
        title: title,
        createdAt: DateTime.utc(2026, 1, 1),
        deletedAt: now.subtract(Duration(days: daysAgo)),
      );

  Task live(int id, String title) =>
      Task(id: id, title: title, createdAt: DateTime.utc(2026, 1, 1));

  late TaskListController controller;

  Future<FakeTaskRepository> pumpBin(WidgetTester tester, List<Task> tasks) async {
    final repo = FakeTaskRepository(tasks);
    controller = TaskListController(repo, clock: () => now);
    await controller.load();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(home: RecycleBinPage(clock: () => now)),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  group('binDaysLeft', () {
    final expires = DateTime(2026, 12, 1, 12);

    test('rounds up partial days', () {
      expect(binDaysLeft(expires, DateTime(2026, 11, 30, 12)), 1);
      expect(binDaysLeft(expires, DateTime(2026, 11, 30, 13)), 1);
      expect(binDaysLeft(expires, DateTime(2026, 11, 29, 11)), 3);
    });

    test('never negative', () {
      expect(binDaysLeft(expires, DateTime(2026, 12, 5)), 0);
    });
  });

  testWidgets('empty bin explains the 30-day rule; Empty is disabled',
      (tester) async {
    await pumpBin(tester, [live(1, 'not deleted')]);
    expect(find.text('The recycle bin is empty'), findsOneWidget);
    expect(find.text('Deleted quests are kept here for 30 days.'),
        findsOneWidget);
    expect(find.text('not deleted'), findsNothing);
    final empty = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_sweep_outlined));
    expect(empty.onPressed, isNull);
  });

  testWidgets('lists binned quests with deletion date and days left',
      (tester) async {
    await pumpBin(tester, [
      binned(1, 'old one', daysAgo: 29),
      binned(2, 'new one', daysAgo: 2),
    ]);
    expect(find.text('Deleted 20-11-2026 · 28 days left'), findsOneWidget);
    expect(find.text('Deleted 24-10-2026 · 1 day left'), findsOneWidget);
    // Most recently deleted first.
    expect(tester.getTopLeft(find.text('new one')).dy,
        lessThan(tester.getTopLeft(find.text('old one')).dy));
  });

  testWidgets('opening the bin removes quests older than 30 days',
      (tester) async {
    final repo = FakeTaskRepository([binned(1, 'fresh', daysAgo: 1)]);
    var clockNow = now;
    controller = TaskListController(repo, clock: () => clockNow);
    await controller.load();
    // Time passes while the app stays open...
    clockNow = now.add(const Duration(days: 30));
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(home: RecycleBinPage(clock: () => clockNow)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('fresh'), findsNothing);
    expect(await repo.getById(1), isNull);
  });

  testWidgets('Restore brings the quest back to the list, same id',
      (tester) async {
    final repo = await pumpBin(tester, [binned(7, 'oops', daysAgo: 1)]);
    await tester.tap(find.byTooltip('Restore'));
    await tester.pumpAndSettle();

    expect(find.text('Restored "oops"'), findsOneWidget);
    expect(find.text('The recycle bin is empty'), findsOneWidget);
    expect(controller.tasks.single.id, 7);
    expect((await repo.getById(7))!.isInBin, isFalse);
  });

  testWidgets('Delete permanently asks first; Cancel keeps it',
      (tester) async {
    final repo = await pumpBin(tester, [binned(1, 'x', daysAgo: 1)]);
    await tester.tap(find.byTooltip('Delete permanently'));
    await tester.pumpAndSettle();
    expect(find.text('Delete permanently?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('x'), findsOneWidget);
    expect(await repo.getById(1), isNotNull);
  });

  testWidgets('Delete permanently, confirmed, removes it for good',
      (tester) async {
    final repo = await pumpBin(tester, [binned(1, 'x', daysAgo: 1)]);
    await tester.tap(find.byTooltip('Delete permanently'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('x'), findsNothing);
    expect(await repo.getById(1), isNull);
  });

  testWidgets('Empty bin, confirmed, removes everything in the bin only',
      (tester) async {
    final repo = await pumpBin(tester, [
      binned(1, 'a', daysAgo: 1),
      binned(2, 'b', daysAgo: 3),
      live(3, 'still here'),
    ]);
    await tester.tap(find.byTooltip('Empty recycle bin'));
    await tester.pumpAndSettle();
    expect(find.text('2 quests will be deleted for good. '
        "This can't be undone."), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Empty bin'));
    await tester.pumpAndSettle();

    expect(find.text('The recycle bin is empty'), findsOneWidget);
    expect(find.text('Recycle bin emptied'), findsOneWidget);
    expect(await repo.getById(1), isNull);
    expect(await repo.getById(3), isNotNull);
  });
}
