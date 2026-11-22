import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/task.dart';
import 'package:questmark/models/task_query.dart';
import 'package:questmark/state/map_focus_controller.dart';
import 'package:questmark/state/navigation_controller.dart';
import 'package:questmark/state/task_list_controller.dart';
import 'package:questmark/state/task_list_view_controller.dart';
import 'package:questmark/ui/tasks/task_editor_page.dart';
import 'package:questmark/ui/tasks/task_filter_sheet.dart';
import 'package:questmark/ui/tasks/recycle_bin_page.dart';
import 'package:questmark/ui/tasks/task_list_page.dart';

import '../../helpers/fake_task_repository.dart';

void main() {
  final now = DateTime(2026, 11, 14, 10);

  Task seed(
    int id,
    String title, {
    bool done = false,
    DateTime? due,
    DateTime? completed,
    String? description,
    GeoPoint? at,
  }) =>
      Task(
        id: id,
        title: title,
        isDone: done,
        dueAt: due,
        completedAt: completed,
        description: description,
        createdAt: DateTime.utc(2026, 1, id),
        location: at,
      );

  late MapFocusController focus;
  late NavigationController nav;
  late TaskListViewController view;

  /// Pumps the list page backed by a fake repository and waits for the
  /// first load to finish.
  Future<FakeTaskRepository> pumpList(
    WidgetTester tester, [
    List<Task> tasks = const [],
    void Function(FakeTaskRepository repo)? beforeLoad,
  ]) async {
    final repo = FakeTaskRepository(tasks);
    beforeLoad?.call(repo);
    focus = MapFocusController();
    nav = NavigationController();
    view = TaskListViewController();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(
            create: (_) => TaskListController(repo, clock: () => now)..load()),
        ChangeNotifierProvider.value(value: focus),
        ChangeNotifierProvider.value(value: nav),
        ChangeNotifierProvider.value(value: view),
      ],
      child: MaterialApp(home: TaskListPage(clock: () => now)),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  /// Titles in on-screen order.
  List<String> shownTitles(WidgetTester tester, List<String> candidates) {
    final shown = candidates.where((t) => find.text(t).evaluate().isNotEmpty);
    final sorted = shown.toList()
      ..sort((a, b) => tester
          .getTopLeft(find.text(a))
          .dy
          .compareTo(tester.getTopLeft(find.text(b)).dy));
    return sorted;
  }

  group('states', () {
    testWidgets('empty state when there are no quests, without controls',
        (tester) async {
      await pumpList(tester);
      expect(find.text('No quests yet'), findsOneWidget);
      expect(find.text('New quest'), findsOneWidget);
      expect(find.byKey(const Key('searchField')), findsNothing);
    });

    testWidgets('load error shows a retry button that works', (tester) async {
      await pumpList(tester, [seed(1, 'a')],
          (repo) => repo.failNextLoad = Exception('boom'));
      expect(find.text("Couldn't load your quests"), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('a'), findsOneWidget);
    });

    testWidgets('no matches shows a message with "Clear filters"',
        (tester) async {
      await pumpList(tester, [seed(1, 'Buy milk')]);
      await tester.enterText(find.byKey(const Key('searchField')), 'zebra');
      await tester.pumpAndSettle();
      expect(find.text('No quests match'), findsOneWidget);

      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.text('Buy milk'), findsOneWidget);
      expect(view.query.hasFilters, isFalse);
    });
  });

  group('one list (no Completed section)', () {
    testWidgets('done and open quests are listed together; no section header',
        (tester) async {
      await pumpList(tester, [
        seed(1, 'open one'),
        seed(2, 'finished', done: true),
        seed(3, 'open two'),
      ]);
      expect(find.textContaining('Completed ('), findsNothing);
      // Default sort: due date ascending, no due dates here, so newest
      // created first.
      expect(shownTitles(tester, ['open one', 'finished', 'open two']),
          ['open two', 'finished', 'open one']);
    });

    testWidgets('shows due dates, overdue, completion date, description',
        (tester) async {
      await pumpList(tester, [
        seed(1, 'late', due: DateTime(2026, 11, 1)),
        seed(2, 'soon', due: DateTime(2026, 11, 30), description: 'details'),
        seed(3, 'today', due: DateTime(2026, 11, 14)),
        seed(4, 'did it', done: true, completed: DateTime(2026, 11, 12, 9)),
      ]);
      expect(find.textContaining('Overdue · 01-11-2026'), findsOneWidget);
      expect(find.textContaining('Due 30-11-2026'), findsOneWidget);
      expect(find.textContaining('details'), findsOneWidget);
      expect(find.textContaining('Due 14-11-2026'), findsOneWidget);
      expect(find.textContaining('Completed 12-11-2026'), findsOneWidget);
    });

    testWidgets('ticking strikes the quest through in place and offers Undo',
        (tester) async {
      final repo = await pumpList(tester, [seed(1, 'a'), seed(2, 'b')]);
      final before = shownTitles(tester, ['a', 'b']);

      await tester.tap(find.byType(Checkbox).last); // 'a' (older, lower)
      await tester.pumpAndSettle();

      expect(shownTitles(tester, ['a', 'b']), before, reason: 'no jumping');
      final saved = (await repo.getById(1))!;
      expect(saved.isDone, isTrue);
      expect(saved.completedAt, now.toUtc());
      expect(find.text('Completed "a"'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect((await repo.getById(1))!.isDone, isFalse);
      expect((await repo.getById(1))!.completedAt, isNull);
    });

    testWidgets('a failed save shows an error snackbar', (tester) async {
      final repo = await pumpList(tester, [seed(1, 'a')]);
      repo.failNextWrite = Exception('disk full');

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      expect(find.textContaining('Something went wrong'), findsOneWidget);
      expect((await repo.getById(1))!.isDone, isFalse);
    });
  });

  group('search', () {
    testWidgets('matches title and description, every word, any case',
        (tester) async {
      await pumpList(tester, [
        seed(1, 'Buy milk', description: 'Oat milk from the market'),
        seed(2, 'Buy bread'),
        seed(3, 'Call mum'),
      ]);
      await tester.enterText(find.byKey(const Key('searchField')), 'BUY oat');
      await tester.pumpAndSettle();
      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('Buy bread'), findsNothing);
      expect(find.text('Call mum'), findsNothing);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Call mum'), findsOneWidget);
    });
  });

  group('status filter chips', () {
    final tasks = [
      seed(1, 'open'),
      seed(2, 'done', done: true),
      seed(3, 'late', due: DateTime(2026, 11, 1)),
    ];

    testWidgets('All is selected by default and shows everything',
        (tester) async {
      await pumpList(tester, tasks);
      final all = tester.widget<ChoiceChip>(find.byKey(const Key('status-all')));
      expect(all.selected, isTrue);
      expect(shownTitles(tester, ['open', 'done', 'late']), hasLength(3));
    });

    testWidgets('Completed / Not completed / Overdue narrow the list',
        (tester) async {
      await pumpList(tester, tasks);

      await tester.tap(find.byKey(const Key('status-completed')));
      await tester.pumpAndSettle();
      expect(shownTitles(tester, ['open', 'done', 'late']), ['done']);

      await tester.tap(find.byKey(const Key('status-notCompleted')));
      await tester.pumpAndSettle();
      expect(shownTitles(tester, ['open', 'done', 'late']).toSet(),
          {'open', 'late'});

      await tester.tap(find.byKey(const Key('status-overdue')));
      await tester.pumpAndSettle();
      expect(shownTitles(tester, ['open', 'done', 'late']), ['late']);
    });

    testWidgets(
        'a quest ticked under "Not completed" stays visible until the '
        'filter changes', (tester) async {
      await pumpList(tester, [seed(1, 'a'), seed(2, 'b')]);
      await tester.tap(find.byKey(const Key('status-notCompleted')));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Checkbox).last); // tick 'a'
      await tester.pumpAndSettle();
      expect(find.text('a'), findsOneWidget, reason: 'kept visible');
      expect(tester.widget<Checkbox>(find.byType(Checkbox).last).value, isTrue);

      // Changing the filter releases it.
      await tester.tap(find.byKey(const Key('status-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('status-notCompleted')));
      await tester.pumpAndSettle();
      expect(find.text('a'), findsNothing);
    });

    testWidgets('leaving the page releases kept-visible quests',
        (tester) async {
      await pumpList(tester, [seed(1, 'a')]);
      await tester.tap(find.byKey(const Key('status-notCompleted')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(view.keepVisible, {1});

      nav.select(AppTab.map);
      await tester.pumpAndSettle();
      expect(view.keepVisible, isEmpty);
    });
  });

  group('sorting', () {
    final tasks = [
      seed(1, 'banana', due: DateTime(2026, 12, 3)),
      seed(2, 'Apple'),
      seed(3, 'cherry', due: DateTime(2026, 12, 1)),
    ];
    const titles = ['banana', 'Apple', 'cherry'];

    Future<void> pickSort(WidgetTester tester, String item) async {
      await tester.tap(find.byIcon(Icons.sort));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    testWidgets('default: due date ascending, no due date last',
        (tester) async {
      await pumpList(tester, tasks);
      expect(shownTitles(tester, titles), ['cherry', 'banana', 'Apple']);
      expect(find.byTooltip('Sort: Due date, ascending'), findsOneWidget);
    });

    testWidgets('due date descending still keeps "no due date" last',
        (tester) async {
      await pumpList(tester, tasks);
      await pickSort(tester, 'Descending');
      expect(shownTitles(tester, titles), ['banana', 'cherry', 'Apple']);
    });

    testWidgets('alphabetical, case-insensitive, both directions',
        (tester) async {
      await pumpList(tester, tasks);
      await pickSort(tester, 'Alphabetical');
      expect(shownTitles(tester, titles), ['Apple', 'banana', 'cherry']);
      await pickSort(tester, 'Descending');
      expect(shownTitles(tester, titles), ['cherry', 'banana', 'Apple']);
    });

    testWidgets('date created', (tester) async {
      await pumpList(tester, tasks);
      await pickSort(tester, 'Date created');
      expect(shownTitles(tester, titles), ['banana', 'Apple', 'cherry']);
    });
  });

  group('date filters', () {
    testWidgets('a due-date range set in the sheet filters the list and '
        'shows a removable chip', (tester) async {
      await pumpList(tester, [
        seed(1, 'early', due: DateTime(2026, 12, 1)),
        seed(2, 'late', due: DateTime(2026, 12, 20)),
        seed(3, 'no due'),
      ]);

      // Set the range directly on the sheet's result, the way "Apply"
      // does (the date pickers themselves are Flutter's).
      view.setQuery(view.query.copyWith(
          due: DayRange(from: DateTime(2026, 12, 1), to: DateTime(2026, 12, 10))));
      await tester.pumpAndSettle();

      expect(find.text('early'), findsOneWidget);
      expect(find.text('late'), findsNothing);
      expect(find.text('no due'), findsNothing);
      expect(find.text('Due: 01-12-2026 – 10-12-2026'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove filter'));
      await tester.pumpAndSettle();
      expect(find.text('late'), findsOneWidget);
      expect(view.query.due.isAny, isTrue);
    });

    testWidgets('the filter button opens the sheet; Apply returns the draft',
        (tester) async {
      await pumpList(tester, [seed(1, 'a')]);
      await tester.tap(find.byTooltip('Filter by date'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskFilterSheet), findsOneWidget);
      expect(find.text('Date created'), findsWidgets);
      expect(find.text('Due date'), findsWidgets);
      expect(find.text('Date completed'), findsWidgets);

      // Pick "From" for date created through the real date picker.
      await tester.tap(find.byKey(const Key('created-from')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('applyFiltersButton')));
      await tester.pumpAndSettle();

      expect(view.query.created.from, isNotNull);
      expect(view.query.created.to, isNull);
      expect(find.textContaining('Created: from'), findsOneWidget);
    });
  });

  group('actions', () {
    testWidgets('swipe deletes, Undo brings it back', (tester) async {
      final repo = await pumpList(tester, [seed(1, 'swipe me'), seed(2, 'b')]);

      await tester.drag(find.text('swipe me'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('swipe me'), findsNothing);
      expect(find.text('Moved "swipe me" to the recycle bin'),
          findsOneWidget);
      expect((await repo.getAll()).map((t) => t.title), ['b']);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('swipe me'), findsOneWidget);
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

  group('Show on map button', () {
    testWidgets('only tasks with a location have the button', (tester) async {
      await pumpList(tester, [
        seed(1, 'on map', at: GeoPoint(60.17, 24.94)),
        seed(2, 'list only'),
      ]);
      expect(find.byTooltip('Show on map'), findsOneWidget);
      final tile = find.ancestor(
          of: find.byTooltip('Show on map'), matching: find.byType(ListTile));
      expect(find.descendant(of: tile, matching: find.text('on map')),
          findsOneWidget);
    });

    testWidgets('tapping it focuses the task and switches to the Map tab',
        (tester) async {
      await pumpList(tester, [seed(1, 'on map', at: GeoPoint(60.17, 24.94))]);

      await tester.tap(find.byTooltip('Show on map'));
      await tester.pump();

      expect(nav.current, AppTab.map);
      expect(focus.pendingRequest!.taskId, 1);
      expect(focus.highlightedTaskId, 1);
    });

    testWidgets('the button appears once a task gets a location',
        (tester) async {
      final repo = await pumpList(tester, [seed(1, 'later on map')]);
      expect(find.byTooltip('Show on map'), findsNothing);

      final controller =
          tester.element(find.byType(TaskListPage)).read<TaskListController>();
      await controller.save(
          (await repo.getById(1))!.copyWith(location: () => GeoPoint(1, 2)));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Show on map'), findsOneWidget);
    });
  });

  group('emulator review fixes', () {
    testWidgets('filter (funnel) and sort icons are different',
        (tester) async {
      await pumpList(tester, [seed(1, 'a')]);
      expect(find.byIcon(Icons.sort), findsOneWidget);
      expect(find.byIcon(Icons.filter_alt_outlined), findsOneWidget);
      expect(find.byIcon(Icons.filter_list), findsNothing);
    });

    testWidgets('"New quest" is hidden while typing a search',
        (tester) async {
      await pumpList(tester, [seed(1, 'a')]);
      expect(find.text('New quest'), findsOneWidget);

      await tester.tap(find.byKey(const Key('searchField')));
      await tester.pumpAndSettle();
      expect(find.text('New quest'), findsNothing);

      await tester.tapAt(const Offset(400, 590)); // outside: keyboard closes
      await tester.pumpAndSettle();
      expect(find.text('New quest'), findsOneWidget);
    });

    testWidgets('tapping outside the search field removes its focus',
        (tester) async {
      await pumpList(tester, [seed(1, 'a')]);
      await tester.tap(find.byKey(const Key('searchField')));
      await tester.pumpAndSettle();
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isTrue);

      await tester.tapAt(const Offset(400, 590)); // empty list area
      await tester.pumpAndSettle();
      expect(field.focusNode.hasFocus, isFalse);
    });

    testWidgets('date filter chip is left-aligned under the status chips',
        (tester) async {
      await pumpList(tester, [seed(1, 'a', due: DateTime(2026, 11, 1))]);
      view.setQuery(view.query.copyWith(due: DayRange(to: DateTime(2026, 12))));
      await tester.pumpAndSettle();
      final chip = tester.getRect(find.byKey(const Key('dateChip-due')));
      final allChip = tester.getRect(find.byKey(const Key('status-all')));
      // Both rows start at the 16 px page margin, even on a wide screen
      // where they don't fill the width.
      expect(allChip.left, closeTo(16, 1));
      expect(chip.left, closeTo(16, 1));
    });

    testWidgets('a chosen date fits on one line in the sheet button',
        (tester) async {
      tester.view.physicalSize = const Size(720, 1280);
      tester.view.devicePixelRatio = 2; // a 360-wide phone, like the emulator
      addTearDown(tester.view.reset);
      await pumpList(tester, [seed(1, 'a')]);
      view.setQuery(view.query.copyWith(due: DayRange(to: DateTime(2026, 11, 22))));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Filter by date'));
      await tester.pumpAndSettle();
      final button = find.byKey(const Key('due-to'));
      final text = find.descendant(
          of: button, matching: find.text('To 22-11-2026'));
      expect(text, findsOneWidget);
      // One line: the text is no taller than a single line of the button.
      expect(tester.getSize(text).height, lessThan(30));
    });
  });

  group('menu: delete all completed / recycle bin (D18)', () {
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
    }

    testWidgets('the confirmation uses the exact wording, with Yes and No',
        (tester) async {
      await pumpList(tester, [seed(1, 'open'), seed(2, 'done', done: true)]);
      await openMenu(tester);
      await tester.tap(find.text('Delete all completed tasks'));
      await tester.pumpAndSettle();

      expect(
          find.text('Are you sure? This will move all completed tasks to '
              'the recycle bin.'),
          findsOneWidget);
      expect(find.widgetWithText(TextButton, 'No'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Yes'), findsOneWidget);
    });

    testWidgets('"No" quits without changing anything', (tester) async {
      final repo =
          await pumpList(tester, [seed(1, 'open'), seed(2, 'done', done: true)]);
      final writes = repo.writes;
      await openMenu(tester);
      await tester.tap(find.text('Delete all completed tasks'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'No'));
      await tester.pumpAndSettle();

      expect(repo.writes, writes);
      expect(find.text('done'), findsOneWidget);
    });

    testWidgets('"Yes" moves all completed tasks to the bin', (tester) async {
      final repo = await pumpList(tester, [
        seed(1, 'open'),
        seed(2, 'done a', done: true),
        seed(3, 'done b', done: true),
      ]);
      await openMenu(tester);
      await tester.tap(find.text('Delete all completed tasks'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Yes'));
      await tester.pumpAndSettle();

      expect(find.text('Moved 2 completed tasks to the recycle bin'),
          findsOneWidget);
      expect(find.text('done a'), findsNothing);
      expect(find.text('open'), findsOneWidget);
      expect((await repo.getBin()).map((t) => t.title).toSet(),
          {'done a', 'done b'});
    });

    testWidgets('disabled when there are no completed tasks', (tester) async {
      await pumpList(tester, [seed(1, 'open')]);
      await openMenu(tester);
      final item = tester.widget<PopupMenuItem<Object?>>(find.ancestor(
          of: find.text('Delete all completed tasks'),
          matching: find.byWidgetPredicate((w) => w is PopupMenuItem)));
      expect(item.enabled, isFalse);
    });

    testWidgets('"Recycle bin" opens the bin page, even with no quests',
        (tester) async {
      await pumpList(tester);
      await openMenu(tester);
      await tester.tap(find.text('Recycle bin'));
      await tester.pumpAndSettle();
      expect(find.byType(RecycleBinPage), findsOneWidget);
    });

    testWidgets('a swiped quest can be restored from the bin', (tester) async {
      await pumpList(tester, [seed(1, 'swiped')]);
      await tester.drag(find.text('swiped'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('swiped'), findsNothing);

      await openMenu(tester);
      await tester.tap(find.text('Recycle bin'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Restore'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('swiped'), findsOneWidget);
    });
  });
}
