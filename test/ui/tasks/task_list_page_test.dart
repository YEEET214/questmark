import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/task.dart';
import 'package:questmark/state/task_list_controller.dart';
import 'package:questmark/ui/tasks/task_editor_page.dart';
import 'package:questmark/ui/tasks/task_list_page.dart';

import '../../helpers/fake_task_repository.dart';

void main() {
  final now = DateTime(2026, 11, 14, 10);

  Task seed(int id, String title,
          {bool done = false, DateTime? due, String? description,
          GeoPoint? at}) =>
      Task(
        id: id,
        title: title,
        isDone: done,
        dueAt: due,
        description: description,
        createdAt: DateTime.utc(2026, 1, id),
        location: at,
      );

  /// Pumps the list page backed by a fake repository and waits for the
  /// first load to finish.
  Future<FakeTaskRepository> pumpList(
    WidgetTester tester, [
    List<Task> tasks = const [],
    void Function(FakeTaskRepository repo)? beforeLoad,
  ]) async {
    final repo = FakeTaskRepository(tasks);
    beforeLoad?.call(repo);
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => TaskListController(repo, clock: () => now)..load(),
      child: MaterialApp(home: TaskListPage(clock: () => now)),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  group('states', () {
    testWidgets('empty state when there are no quests', (tester) async {
      await pumpList(tester);
      expect(find.text('No quests yet'), findsOneWidget);
      expect(find.text('New quest'), findsOneWidget);
    });

    testWidgets('load error shows a retry button that works', (tester) async {
      await pumpList(tester, [seed(1, 'a')],
          (repo) => repo.failNextLoad = Exception('boom'));
      expect(find.text("Couldn't load your quests"), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('a'), findsOneWidget);
    });
  });

  group('list content', () {
    testWidgets('active quests first, then a Completed section',
        (tester) async {
      await pumpList(tester, [
        seed(1, 'open one'),
        seed(2, 'finished', done: true),
        seed(3, 'open two'),
      ]);

      expect(find.text('Completed (1)'), findsOneWidget);
      double y(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(y('open two'), lessThan(y('open one'))); // newest first
      expect(y('open one'), lessThan(y('Completed (1)')));
      expect(y('Completed (1)'), lessThan(y('finished')));
    });

    testWidgets('no Completed header when nothing is completed',
        (tester) async {
      await pumpList(tester, [seed(1, 'a')]);
      expect(find.textContaining('Completed'), findsNothing);
    });

    testWidgets('shows due dates, highlights overdue, shows description',
        (tester) async {
      await pumpList(tester, [
        seed(1, 'late', due: DateTime(2026, 11, 1)),
        seed(2, 'soon', due: DateTime(2026, 11, 30), description: 'details'),
        seed(3, 'today', due: DateTime(2026, 11, 14)),
      ]);
      expect(find.textContaining('Overdue · Nov 1, 2026'), findsOneWidget);
      expect(find.textContaining('Due Nov 30, 2026'), findsOneWidget);
      expect(find.textContaining('details'), findsOneWidget);
      // Due today is not overdue.
      expect(find.textContaining('Due Nov 14, 2026'), findsOneWidget);
    });
  });

  group('actions', () {
    testWidgets('ticking the checkbox completes the quest', (tester) async {
      final repo = await pumpList(tester, [seed(1, 'a')]);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      expect(find.text('Completed (1)'), findsOneWidget);
      expect((await repo.getById(1))!.isDone, isTrue);
    });

    testWidgets('a failed save shows an error snackbar', (tester) async {
      final repo = await pumpList(tester, [seed(1, 'a')]);
      repo.failNextWrite = Exception('disk full');

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      expect(find.textContaining('Something went wrong'), findsOneWidget);
      expect((await repo.getById(1))!.isDone, isFalse);
    });

    testWidgets('swipe deletes, Undo brings it back', (tester) async {
      final repo = await pumpList(tester, [seed(1, 'swipe me'), seed(2, 'b')]);

      await tester.drag(find.text('swipe me'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('swipe me'), findsNothing);
      expect(find.text('Deleted "swipe me"'), findsOneWidget);
      expect((await repo.getAll()).map((t) => t.title), ['b']);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('swipe me'), findsOneWidget);
      expect((await repo.getAll()).map((t) => t.title),
          containsAll(['swipe me', 'b']));
    });

    testWidgets('New quest: create via the editor', (tester) async {
      final repo = await pumpList(tester);

      await tester.tap(find.text('New quest'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskEditorPage), findsOneWidget);

      await tester.enterText(find.byKey(const Key('titleField')), 'Buy milk');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.byType(TaskEditorPage), findsNothing);
      expect(find.text('Buy milk'), findsOneWidget);
      final saved = (await repo.getAll()).single;
      expect(saved.title, 'Buy milk');
      expect(saved.createdAt, now.toUtc());
    });

    testWidgets('tap a quest to edit it; its location is kept',
        (tester) async {
      final repo = await pumpList(
          tester, [seed(1, 'old title', at: GeoPoint(60.17, 24.94))]);

      await tester.tap(find.text('old title'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('titleField')), 'new title');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('new title'), findsOneWidget);
      final edited = (await repo.getById(1))!;
      expect(edited.title, 'new title');
      expect(edited.location, GeoPoint(60.17, 24.94));
    });

    testWidgets('closing the editor with back changes nothing',
        (tester) async {
      final repo = await pumpList(tester, [seed(1, 'a')]);
      final writes = repo.writes;

      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(repo.writes, writes);
    });

    testWidgets('delete from the editor removes it, with Undo',
        (tester) async {
      await pumpList(tester, [seed(1, 'doomed')]);

      await tester.tap(find.text('doomed'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.byType(TaskEditorPage), findsNothing);
      expect(find.text('doomed'), findsNothing);
      expect(find.text('Undo'), findsOneWidget);
    });
  });
}
