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

  group('recycle bin (schema v3)', () {
    final binTime = DateTime.utc(2026, 11, 20, 12);

    test('moveToBin hides the task from getAll and getWithLocation', () async {
      final a = await repo.insert(newTask('a', at: GeoPoint(1, 2)));
      final b = await repo.insert(newTask('b'));

      expect(await repo.moveToBin(a.id!, binTime), isTrue);

      expect(await repo.getAll(), [b]);
      expect(await repo.getWithLocation(), isEmpty);
      final inBin = (await repo.getBin()).single;
      expect(inBin.id, a.id);
      expect(inBin.deletedAt, binTime);
      expect(inBin.withoutId().copyWith(deletedAt: () => null),
          a.withoutId(), reason: 'nothing else changes');
    });

    test('getById still finds a task in the bin', () async {
      final a = await repo.insert(newTask('a'));
      await repo.moveToBin(a.id!, binTime);
      expect((await repo.getById(a.id!))!.isInBin, isTrue);
    });

    test('moveToBin is false for unknown or already-binned tasks', () async {
      final a = await repo.insert(newTask('a'));
      expect(await repo.moveToBin(999, binTime), isFalse);
      await repo.moveToBin(a.id!, binTime);
      expect(await repo.moveToBin(a.id!, binTime.add(const Duration(days: 1))),
          isFalse);
      expect((await repo.getById(a.id!))!.deletedAt, binTime,
          reason: 'the original deletion time is kept');
    });

    test('restoreFromBin brings it back with the same id', () async {
      final a = await repo.insert(newTask('a'));
      await repo.moveToBin(a.id!, binTime);

      expect(await repo.restoreFromBin(a.id!), isTrue);
      expect(await repo.getAll(), [a]);
      expect(await repo.getBin(), isEmpty);
      expect(await repo.restoreFromBin(a.id!), isFalse,
          reason: 'not in the bin any more');
    });

    test('bin is ordered most recently deleted first', () async {
      final a = await repo.insert(newTask('a'));
      final b = await repo.insert(newTask('b'));
      await repo.moveToBin(b.id!, DateTime.utc(2026, 11, 1));
      await repo.moveToBin(a.id!, DateTime.utc(2026, 11, 5));
      expect((await repo.getBin()).map((t) => t.title), ['a', 'b']);
    });

    test('moveCompletedToBin moves only completed tasks and counts them',
        () async {
      await repo.insert(newTask('open'));
      await repo.insert(newTask('done 1', done: true));
      await repo.insert(newTask('done 2', done: true));

      expect(await repo.moveCompletedToBin(binTime), 2);
      expect((await repo.getAll()).map((t) => t.title), ['open']);
      expect((await repo.getBin()).map((t) => t.title).toSet(),
          {'done 1', 'done 2'});
      expect(await repo.moveCompletedToBin(binTime), 0);
    });

    test('deletePermanently removes the row for good', () async {
      final a = await repo.insert(newTask('a'));
      final b = await repo.insert(newTask('b'));
      expect(await repo.deletePermanently(a.id!), isTrue);
      expect(await repo.getById(a.id!), isNull);
      expect(await repo.getAll(), [b]);
      expect(await repo.deletePermanently(123), isFalse);
    });

    test('emptyBin removes only binned tasks', () async {
      final a = await repo.insert(newTask('a'));
      final b = await repo.insert(newTask('b'));
      await repo.moveToBin(a.id!, binTime);
      expect(await repo.emptyBin(), 1);
      expect(await repo.getAll(), [b]);
      expect(await repo.getBin(), isEmpty);
    });

    test('purgeBin removes only bin tasks deleted before the cutoff',
        () async {
      final old = await repo.insert(newTask('old'));
      final recent = await repo.insert(newTask('recent'));
      final live = await repo.insert(newTask('live'));
      await repo.moveToBin(old.id!, DateTime.utc(2026, 10, 1));
      await repo.moveToBin(recent.id!, DateTime.utc(2026, 11, 10));

      final removed =
          await repo.purgeBin(deletedBefore: DateTime.utc(2026, 10, 15));

      expect(removed, 1);
      expect(await repo.getById(old.id!), isNull);
      expect((await repo.getBin()).single.id, recent.id);
      expect(await repo.getAll(), [live]);
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
