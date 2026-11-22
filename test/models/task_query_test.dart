import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/models/task.dart';
import 'package:questmark/models/task_query.dart';

void main() {
  final now = DateTime(2026, 11, 14, 10); // local

  Task t(
    int id,
    String title, {
    bool done = false,
    DateTime? created,
    DateTime? due,
    DateTime? completed,
    String? description,
  }) =>
      Task(
        id: id,
        title: title,
        isDone: done,
        createdAt: created ?? DateTime(2026, 1, id),
        dueAt: due,
        completedAt: completed,
        description: description,
      );

  List<String> titles(TaskQuery q, List<Task> tasks,
          {Set<int> keep = const {}}) =>
      q.apply(tasks, now: now, keepVisible: keep).map((t) => t.title).toList();

  group('DayRange', () {
    test('any contains everything', () {
      expect(const DayRange.any().isAny, isTrue);
      expect(const DayRange.any().contains(DateTime(1990)), isTrue);
    });

    test('from only = on or after that day (whole day included)', () {
      final r = DayRange(from: DateTime(2026, 12, 1, 15));
      expect(r.from, DateTime(2026, 12, 1), reason: 'time of day dropped');
      expect(r.contains(DateTime(2026, 12, 1, 0, 1)), isTrue);
      expect(r.contains(DateTime(2026, 11, 30, 23, 59)), isFalse);
    });

    test('to only = on or before that day (whole day included)', () {
      final r = DayRange(to: DateTime(2026, 12, 1));
      expect(r.contains(DateTime(2026, 12, 1, 23, 59)), isTrue);
      expect(r.contains(DateTime(2026, 12, 2)), isFalse);
    });

    test('between includes both ends', () {
      final r = DayRange(from: DateTime(2026, 12, 1), to: DateTime(2026, 12, 3));
      expect(r.contains(DateTime(2026, 12, 1)), isTrue);
      expect(r.contains(DateTime(2026, 12, 3, 22)), isTrue);
      expect(r.contains(DateTime(2026, 12, 4)), isFalse);
    });

    test('same day from and to is allowed; from after to is rejected', () {
      expect(() => DayRange(from: DateTime(2026, 1, 1), to: DateTime(2026, 1, 1)),
          returnsNormally);
      expect(() => DayRange(from: DateTime(2026, 1, 2), to: DateTime(2026, 1, 1)),
          throwsArgumentError);
    });

    test('uses local calendar days for UTC times', () {
      final local = DateTime(2026, 12, 1, 12);
      final r = DayRange(from: DateTime(2026, 12, 1), to: DateTime(2026, 12, 1));
      expect(r.contains(local.toUtc()), isTrue);
    });
  });

  group('status filter', () {
    final tasks = [
      t(1, 'open'),
      t(2, 'done', done: true),
      t(3, 'late', due: DateTime(2026, 11, 1)),
      t(4, 'late but done', done: true, due: DateTime(2026, 11, 1)),
    ];

    test('All (default) shows everything', () {
      expect(titles(const TaskQuery(), tasks), hasLength(4));
    });

    test('Completed', () {
      expect(titles(const TaskQuery(status: StatusFilter.completed), tasks).toSet(),
          {'done', 'late but done'});
    });

    test('Not completed', () {
      expect(
          titles(const TaskQuery(status: StatusFilter.notCompleted), tasks)
              .toSet(),
          {'open', 'late'});
    });

    test('Overdue excludes completed tasks', () {
      expect(titles(const TaskQuery(status: StatusFilter.overdue), tasks),
          ['late']);
    });

    test('keepVisible skips only the status check', () {
      const q = TaskQuery(status: StatusFilter.notCompleted, search: 'done');
      // 'done' is completed but kept visible; 'late but done' isn't kept.
      expect(titles(q, tasks, keep: {2}), ['done']);
      // Search still applies to kept tasks.
      expect(titles(q.copyWith(search: 'zzz'), tasks, keep: {2}), isEmpty);
    });
  });

  group('search', () {
    final tasks = [
      t(1, 'Buy milk', description: 'Oat milk, market'),
      t(2, 'Buy bread'),
      t(3, 'Call mum'),
    ];

    test('empty or whitespace search matches everything', () {
      expect(titles(const TaskQuery(search: '   '), tasks), hasLength(3));
    });

    test('case-insensitive, title or description', () {
      expect(titles(const TaskQuery(search: 'MARKET'), tasks), ['Buy milk']);
      expect(titles(const TaskQuery(search: 'buy'), tasks).toSet(),
          {'Buy milk', 'Buy bread'});
    });

    test('every word must match', () {
      expect(titles(const TaskQuery(search: 'buy oat'), tasks), ['Buy milk']);
      expect(titles(const TaskQuery(search: 'buy mum'), tasks), isEmpty);
    });
  });

  group('date filters', () {
    final tasks = [
      t(1, 'a', created: DateTime(2026, 1, 1), due: DateTime(2026, 2, 1)),
      t(2, 'b', created: DateTime(2026, 1, 10), due: DateTime(2026, 2, 10)),
      t(3, 'c', created: DateTime(2026, 1, 20)),
      t(4, 'd',
          created: DateTime(2026, 1, 5),
          done: true,
          completed: DateTime(2026, 3, 1)),
      t(5, 'e', created: DateTime(2026, 1, 6), done: true), // unknown date
    ];

    test('date created: before / after / between', () {
      Set<String> created(DayRange r) =>
          titles(TaskQuery(created: r), tasks).toSet();
      expect(created(DayRange(to: DateTime(2026, 1, 5))), {'a', 'd'});
      expect(created(DayRange(from: DateTime(2026, 1, 10))), {'b', 'c'});
      expect(created(DayRange(from: DateTime(2026, 1, 5), to: DateTime(2026, 1, 10))),
          {'b', 'd', 'e'});
    });

    test('due date: tasks without a due date are excluded', () {
      expect(
          titles(TaskQuery(due: DayRange(from: DateTime(2026, 1, 1))), tasks)
              .toSet(),
          {'a', 'b'});
      expect(
          titles(TaskQuery(due: DayRange(to: DateTime(2026, 2, 5))), tasks),
          ['a']);
    });

    test('date completed: unknown completion dates are excluded', () {
      expect(
          titles(TaskQuery(completed: DayRange(from: DateTime(2026, 1, 1))),
              tasks),
          ['d']);
    });

    test('filters combine with each other and with status', () {
      final q = TaskQuery(
        status: StatusFilter.notCompleted,
        created: DayRange(from: DateTime(2026, 1, 5)),
        due: DayRange(to: DateTime(2026, 3, 1)),
      );
      expect(titles(q, tasks), ['b']);
    });
  });

  group('sorting', () {
    final tasks = [
      t(1, 'banana', created: DateTime(2026, 1, 3), due: DateTime(2026, 5, 2)),
      t(2, 'Apple', created: DateTime(2026, 1, 1)),
      t(3, 'cherry',
          created: DateTime(2026, 1, 2),
          due: DateTime(2026, 5, 1),
          done: true,
          completed: DateTime(2026, 4, 1)),
      t(4, 'date',
          created: DateTime(2026, 1, 4),
          done: true,
          completed: DateTime(2026, 4, 9)),
    ];

    List<String> sorted(SortField f, bool asc) =>
        titles(TaskQuery(sortField: f, ascending: asc), tasks);

    test('default is due date ascending', () {
      expect(const TaskQuery().sortField, SortField.due);
      expect(const TaskQuery().ascending, isTrue);
    });

    test('alphabetical is case-insensitive, both directions', () {
      expect(sorted(SortField.title, true), ['Apple', 'banana', 'cherry', 'date']);
      expect(sorted(SortField.title, false), ['date', 'cherry', 'banana', 'Apple']);
    });

    test('date created, both directions', () {
      expect(sorted(SortField.created, true), ['Apple', 'cherry', 'banana', 'date']);
      expect(sorted(SortField.created, false), ['date', 'banana', 'cherry', 'Apple']);
    });

    test('due date: no due date goes last in both directions', () {
      expect(sorted(SortField.due, true).take(2), ['cherry', 'banana']);
      expect(sorted(SortField.due, false).take(2), ['banana', 'cherry']);
      // The undated ones follow, newest created first.
      expect(sorted(SortField.due, true).skip(2), ['date', 'Apple']);
      expect(sorted(SortField.due, false).skip(2), ['date', 'Apple']);
    });

    test('date completed: not completed goes last in both directions', () {
      expect(sorted(SortField.completed, true).take(2), ['cherry', 'date']);
      expect(sorted(SortField.completed, false).take(2), ['date', 'cherry']);
    });

    test('sorting ignores done state (no "done last")', () {
      expect(sorted(SortField.title, true).indexOf('cherry'), 2);
    });
  });

  group('helpers', () {
    test('hasFilters ignores the sort', () {
      expect(const TaskQuery().hasFilters, isFalse);
      expect(const TaskQuery(ascending: false, sortField: SortField.title)
          .hasFilters, isFalse);
      expect(const TaskQuery(search: 'x').hasFilters, isTrue);
      expect(const TaskQuery(status: StatusFilter.overdue).hasFilters, isTrue);
      expect(TaskQuery(due: DayRange(to: DateTime(2026))).hasDateFilters,
          isTrue);
    });

    test('clearFilters keeps the sort', () {
      final q = TaskQuery(
        search: 'x',
        status: StatusFilter.completed,
        due: DayRange(to: DateTime(2026)),
        sortField: SortField.title,
        ascending: false,
      ).clearFilters();
      expect(q, const TaskQuery(sortField: SortField.title, ascending: false));
    });

    test('value equality', () {
      expect(TaskQuery(due: DayRange(to: DateTime(2026, 1, 1))),
          TaskQuery(due: DayRange(to: DateTime(2026, 1, 1, 18))));
    });
  });
}
