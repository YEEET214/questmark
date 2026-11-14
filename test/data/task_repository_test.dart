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

    test('active before done, due-dated first (earliest first), then newest',
        () async {
      await repo.insert(newTask('done, due soon',
          done: true, due: DateTime.utc(2026, 1, 2)));
      await repo.insert(
          newTask('old, no due', created: DateTime.utc(2026, 1, 1)));
      await repo.insert(
          newTask('new, no due', created: DateTime.utc(2026, 1, 5)));
      await repo.insert(newTask('due later', due: DateTime.utc(2026, 3)));
      await repo.insert(newTask('due sooner', due: DateTime.utc(2026, 2)));

      expect((await repo.getAll()).map((t) => t.title), [
        'due sooner',
        'due later',
        'new, no due',
        'old, no due',
        'done, due soon',
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

      expect(await repo.getWithLocation(), [located, locatedDone]);
    });
  });
}
