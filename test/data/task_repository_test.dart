import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/data/task_repository.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/task.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_database.dart';

void main() {
  late Database db;
  late SqfliteTaskRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    repo = SqfliteTaskRepository(db);
  });
  tearDown(() async => db.close());

  Task newTask(
    String title, {
    DateTime? created,
    DateTime? due,
    bool done = false,
    GeoPoint? at,
  }) =>
      Task(
        title: title,
        createdAt: created ?? DateTime.utc(2026, 1, 1),
        dueAt: due,
        isDone: done,
        location: at,
      );

  group('insert', () {
    test('assigns an id and the task can be read back unchanged', () async {
      final saved = await repo.insert(newTask('Buy milk',
          due: DateTime.utc(2026, 2, 1), at: GeoPoint(60.17, 24.94)));
      expect(saved.id, isNotNull);
      expect(await repo.getById(saved.id!), saved);
    });

    test('assigns different ids to different tasks', () async {
      final a = await repo.insert(newTask('a'));
      final b = await repo.insert(newTask('b'));
      expect(a.id, isNot(b.id));
    });

    test('rejects a task that already has an id', () async {
      final saved = await repo.insert(newTask('a'));
      expect(() => repo.insert(saved), throwsArgumentError);
    });
  });

  group('completedAt (schema v2)', () {
    test('is stored and read back for a completed task', () async {
      final saved = await repo.insert(Task(
        title: 'done',
        createdAt: DateTime.utc(2026, 1, 1),
        isDone: true,
        completedAt: DateTime.utc(2026, 1, 3, 12),
      ));
      expect((await repo.getById(saved.id!))!.completedAt,
          DateTime.utc(2026, 1, 3, 12));
    });

    test('reopening clears it in the database', () async {
      final saved = await repo.insert(Task(
        title: 'done',
        createdAt: DateTime.utc(2026, 1, 1),
        isDone: true,
        completedAt: DateTime.utc(2026, 1, 3),
      ));
      await repo.update(saved.copyWith(isDone: false));
      expect((await repo.getById(saved.id!))!.completedAt, isNull);
    });
  });

  group('getById', () {
    test('returns null for an unknown id', () async {
      expect(await repo.getById(999), isNull);
    });
  });

  group('update', () {
    test('saves changed fields, including clearing the location', () async {
      final saved = await repo.insert(newTask('a', at: GeoPoint(1, 1)));
      final edited = saved.copyWith(
        title: 'a (edited)',
        isDone: true,
        location: () => null,
        address: () => 'Somewhere',
      );
      await repo.update(edited);
      expect(await repo.getById(saved.id!), edited);
    });

    test('rejects a task without an id', () async {
      expect(() => repo.update(newTask('a')), throwsArgumentError);
    });

    test('throws TaskNotFoundException for an unknown id', () async {
      final ghost = newTask('ghost').copyWith(id: 42);
      expect(
          () => repo.update(ghost), throwsA(isA<TaskNotFoundException>()));
    });
  });

  group('delete', () {
    test('removes the task and reports true', () async {
      final saved = await repo.insert(newTask('a'));
      expect(await repo.delete(saved.id!), isTrue);
      expect(await repo.getById(saved.id!), isNull);
    });

    test('reports false for an unknown id', () async {
      expect(await repo.delete(123), isFalse);
    });

    test('leaves other tasks alone', () async {
      final a = await repo.insert(newTask('a'));
      final b = await repo.insert(newTask('b'));
      await repo.delete(a.id!);
      expect(await repo.getAll(), [b]);
    });
  });

  group('getAll ordering', () {
    test('is empty for a new database', () async {
      expect(await repo.getAll(), isEmpty);
    });

    test('newest created first, ties by newest id; done state is ignored',
        () async {
      // Completing a task must never move it (PLAN.md D16), so the
      // repository's order doesn't depend on is_done or due dates. The
      // list page applies the user's chosen sort on top.
      await repo.insert(newTask('old', created: DateTime.utc(2026, 1, 1)));
      await repo.insert(newTask('newest, done',
          created: DateTime.utc(2026, 1, 9), done: true));
      await repo.insert(newTask('middle', created: DateTime.utc(2026, 1, 5)));
      await repo.insert(
          newTask('old, inserted later', created: DateTime.utc(2026, 1, 1)));

      expect((await repo.getAll()).map((t) => t.title), [
        'newest, done',
        'middle',
        'old, inserted later',
        'old',
      ]);
    });
  });

  group('getWithLocation', () {
    test('returns only tasks that have a location, done ones included',
        () async {
      await repo.insert(newTask('list only'));
      final located =
          await repo.insert(newTask('on map', at: GeoPoint(1, 2)));
      final locatedDone = await repo
          .insert(newTask('done on map', done: true, at: GeoPoint(3, 4)));

      // Same created date, so the newer row (higher id) comes first.
      expect(await repo.getWithLocation(), [locatedDone, located]);
    });
  });
}
