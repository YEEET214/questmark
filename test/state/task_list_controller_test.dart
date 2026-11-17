import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/task.dart';
import 'package:questmark/state/task_list_controller.dart';

import '../helpers/fake_task_repository.dart';

void main() {
  final now = DateTime.utc(2026, 11, 14, 10);

  Task seed(int id, String title, {bool done = false, GeoPoint? at}) => Task(
        id: id,
        title: title,
        isDone: done,
        createdAt: DateTime.utc(2026, 1, id),
        location: at,
      );

  late FakeTaskRepository repo;
  late TaskListController controller;
  late int notifications;

  void build([List<Task> tasks = const []]) {
    repo = FakeTaskRepository(tasks);
    controller = TaskListController(repo, clock: () => now);
    notifications = 0;
    controller.addListener(() => notifications++);
  }

  group('load', () {
    test('starts empty and not loaded', () {
      build();
      expect(controller.hasLoaded, isFalse);
      expect(controller.tasks, isEmpty);
    });

    test('loads tasks and notifies (loading on, loading off)', () async {
      build([seed(1, 'a'), seed(2, 'b')]);
      final future = controller.load();
      expect(controller.isLoading, isTrue);
      await future;

      expect(controller.isLoading, isFalse);
      expect(controller.hasLoaded, isTrue);
      expect(controller.tasks.map((t) => t.title), ['b', 'a']);
      expect(notifications, 2);
    });

    test('records a load error instead of throwing, and can retry',
        () async {
      build([seed(1, 'a')]);
      repo.failNextLoad = Exception('disk on fire');

      await controller.load();
      expect(controller.loadError, isA<Exception>());
      expect(controller.hasLoaded, isTrue);

      await controller.load();
      expect(controller.loadError, isNull);
      expect(controller.tasks, hasLength(1));
    });
  });

  group('derived lists', () {
    test('split active/completed and pick out located tasks', () async {
      build([
        seed(1, 'open'),
        seed(2, 'done', done: true),
        seed(3, 'open on map', at: GeoPoint(1, 2)),
        seed(4, 'done on map', done: true, at: GeoPoint(3, 4)),
      ]);
      await controller.load();

      expect(controller.activeTasks.map((t) => t.title),
          unorderedEquals(['open', 'open on map']));
      expect(controller.completedTasks.map((t) => t.title),
          unorderedEquals(['done', 'done on map']));
      expect(controller.locatedTasks.map((t) => t.title),
          unorderedEquals(['open on map', 'done on map']));
      expect(controller.unlocatedTasks.map((t) => t.title),
          unorderedEquals(['open', 'done']));
    });
  });

  group('changes write through and refresh', () {
    setUp(() async {
      build([seed(1, 'existing')]);
      await controller.load();
      notifications = 0;
    });

    test('add stores a new task stamped with the clock', () async {
      final saved = await controller.add(
          title: 'New', description: 'desc', dueAt: DateTime.utc(2026, 12));

      expect(saved.id, isNotNull);
      expect(saved.createdAt, now);
      expect(await repo.getById(saved.id!), saved);
      expect(controller.tasks, contains(saved));
      expect(notifications, 1);
    });

    test('add can give the new task a location', () async {
      final saved =
          await controller.add(title: 'On the map', location: GeoPoint(1, 2));
      expect(saved.location, GeoPoint(1, 2));
      expect(controller.locatedTasks, contains(saved));
    });

    test('save updates an existing task', () async {
      final t = controller.tasks.single;
      await controller.save(t.copyWith(title: 'renamed'));
      expect(controller.tasks.single.title, 'renamed');
      expect((await repo.getById(t.id!))!.title, 'renamed');
    });

    test('setDone toggles completion', () async {
      final t = controller.tasks.single;
      await controller.setDone(t, true);
      expect(controller.completedTasks.single.id, t.id);

      await controller.setDone(controller.tasks.single, false);
      expect(controller.activeTasks.single.id, t.id);
    });

    test('setDone with the current value does not write', () async {
      final writesBefore = repo.writes;
      await controller.setDone(controller.tasks.single, false);
      expect(repo.writes, writesBefore);
      expect(notifications, 0);
    });

    test('delete removes the task and returns it', () async {
      final t = controller.tasks.single;
      final deleted = await controller.delete(t);
      expect(deleted, t);
      expect(controller.tasks, isEmpty);
    });

    test('restore puts a deleted task back with the same content', () async {
      final t = controller.tasks.single;
      final deleted = await controller.delete(t);
      final restored = await controller.restore(deleted);

      expect(controller.tasks, [restored]);
      // New row, so new id; everything else is identical.
      expect(restored.withoutId(), t.withoutId());
    });

    test('write failures are rethrown and the list stays unchanged',
        () async {
      final before = controller.tasks;
      repo.failNextWrite = Exception('nope');
      await expectLater(
          controller.save(before.single.copyWith(title: 'x')), throwsException);
      expect(controller.tasks, before);
      expect(notifications, 0);
    });
  });
}
