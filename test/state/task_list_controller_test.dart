import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/task.dart';
import 'package:questmark/services/geocoding_service.dart';
import 'package:questmark/state/task_list_controller.dart';

import '../helpers/fake_task_repository.dart';
import '../helpers/fake_geocoding_service.dart';

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

  group('recycle bin purge (30 days)', () {
    Task binned(int id, DateTime deletedAt) => Task(
          id: id,
          title: 'binned $id',
          createdAt: DateTime.utc(2026, 1, 1),
          deletedAt: deletedAt,
        );

    test('load removes tasks deleted more than 30 days ago', () async {
      build([
        binned(1, now.subtract(const Duration(days: 31))),
        binned(2, now.subtract(const Duration(days: 29))),
        seed(3, 'live'),
      ]);
      await controller.load();

      expect(controller.binTasks.map((t) => t.id), [2]);
      expect(await repo.getById(1), isNull);
      expect(controller.tasks.map((t) => t.id), [3]);
    });

    test('purgeExpiredBin (bin opened) removes expired tasks and refreshes',
        () async {
      var clockNow = now;
      repo = FakeTaskRepository([binned(1, now)]);
      controller = TaskListController(repo, clock: () => clockNow);
      await controller.load();
      expect(controller.binTasks, hasLength(1));

      clockNow = now.add(const Duration(days: 30, minutes: 1));
      expect(await controller.purgeExpiredBin(), 1);
      expect(controller.binTasks, isEmpty);
    });
  });

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

    test('add keeps an address that goes with the location', () async {
      final saved = await controller.add(
          title: 'Library', location: GeoPoint(1, 2), address: 'Main St 1');
      expect((await repo.getById(saved.id!))!.address, 'Main St 1');
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

    test('setDone records the completion time and clears it on reopen',
        () async {
      final t = controller.tasks.single;
      await controller.setDone(t, true);
      expect(controller.tasks.single.completedAt, now);

      await controller.setDone(controller.tasks.single, false);
      expect(controller.tasks.single.completedAt, isNull);
    });

    test('setDone with the current value does not write', () async {
      final writesBefore = repo.writes;
      await controller.setDone(controller.tasks.single, false);
      expect(repo.writes, writesBefore);
      expect(notifications, 0);
    });

    test('moveToBin moves the task to the bin, stamped with the clock',
        () async {
      final t = controller.tasks.single;
      final deleted = await controller.moveToBin(t);
      expect(deleted, t);
      expect(controller.tasks, isEmpty);
      expect(controller.binTasks.single.id, t.id);
      expect(controller.binTasks.single.deletedAt, now);
    });

    test('restoreFromBin brings it back unchanged, with the same id',
        () async {
      final t = controller.tasks.single;
      await controller.moveToBin(t);
      await controller.restoreFromBin(controller.binTasks.single);

      expect(controller.tasks, [t]);
      expect(controller.binTasks, isEmpty);
    });

    test('moveCompletedToBin moves only completed tasks and counts them',
        () async {
      await controller.add(title: 'done 1');
      await controller.setDone(
          controller.tasks.firstWhere((t) => t.title == 'done 1'), true);

      expect(await controller.moveCompletedToBin(), 1);
      expect(controller.tasks.map((t) => t.title), ['existing']);
      expect(controller.binTasks.map((t) => t.title), ['done 1']);
    });

    test('deletePermanently and emptyBin remove tasks for good', () async {
      await controller.add(title: 'b');
      await controller.moveToBin(controller.tasks.first);
      await controller.moveToBin(controller.tasks.first);
      expect(controller.binTasks, hasLength(2));

      await controller.deletePermanently(controller.binTasks.first);
      expect(controller.binTasks, hasLength(1));
      expect(await controller.emptyBin(), 1);
      expect(controller.binTasks, isEmpty);
      expect(controller.tasks, isEmpty);
    });

    test('expiresAt is 30 days after deletion', () async {
      await controller.moveToBin(controller.tasks.single);
      expect(controller.expiresAt(controller.binTasks.single),
          now.add(const Duration(days: 30)));
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
  group('address lookup after saving (Phase 7, D6)', () {
    final here = GeoPoint(60.17378, 24.93795);
    final there = GeoPoint(61.5, 23.76);
    late FakeGeocodingService geo;

    Future<void> buildWithGeocoder([List<Task> tasks = const []]) async {
      repo = FakeTaskRepository(tasks);
      geo = FakeGeocodingService(addresses: {
        here: 'Oodi, Töölönlahdenkatu 4, Helsinki',
        there: 'Tampere',
      });
      controller = TaskListController(repo, clock: () => now, geocoder: geo);
      await controller.load();
    }

    test('a new pinned task gets its address filled in, in the background',
        () async {
      await buildWithGeocoder();
      final saved = await controller.add(title: 'Library', location: here);
      expect(saved.address, isNull, reason: 'add does not wait for it');

      await controller.lastAddressLookup;
      expect(geo.reverseCalls, [here]);
      expect((await repo.getById(saved.id!))!.address,
          'Oodi, Töölönlahdenkatu 4, Helsinki');
      expect(controller.tasks.single.address,
          'Oodi, Töölönlahdenkatu 4, Helsinki');
    });

    test('saving a moved task looks up the new address', () async {
      await buildWithGeocoder([seed(1, 'x', at: here)]);
      await controller.save(controller.tasks.single
          .copyWith(location: () => there, address: () => null));
      await controller.lastAddressLookup;
      expect(controller.tasks.single.address, 'Tampere');
    });

    test('no lookup when there is an address already, or no location',
        () async {
      await buildWithGeocoder();
      await controller.add(title: 'a', location: here, address: 'Given');
      await controller.add(title: 'b');
      expect(geo.reverseCalls, isEmpty);
    });

    test('a failed lookup leaves the coordinates; the next save retries',
        () async {
      await buildWithGeocoder();
      geo.failNext = const GeocodingException(GeocodingFailure.offline);
      final saved = await controller.add(title: 'x', location: here);
      await controller.lastAddressLookup;
      expect((await repo.getById(saved.id!))!.address, isNull);

      await controller.save((await repo.getById(saved.id!))!);
      await controller.lastAddressLookup;
      expect((await repo.getById(saved.id!))!.address, isNotNull);
    });

    test('a place with no address (e.g. the sea) stays without one',
        () async {
      await buildWithGeocoder();
      final saved =
          await controller.add(title: 'Boat', location: GeoPoint(0, 0));
      await controller.lastAddressLookup;
      expect((await repo.getById(saved.id!))!.address, isNull);
    });

    test('never overwrites: the task moved meanwhile, or got an address',
        () async {
      await buildWithGeocoder();
      geo.holdReverse = Completer();
      final saved = await controller.add(title: 'x', location: here);
      // Before the lookup finishes, the user moves the task elsewhere
      // and names the address themselves.
      await repo.update((await repo.getById(saved.id!))!
          .copyWith(location: () => there, address: () => 'Mine'));
      geo.holdReverse!.complete();
      await controller.lastAddressLookup;
      final now = (await repo.getById(saved.id!))!;
      expect(now.address, 'Mine');
      expect(now.location, there);
    });

    test('a task binned meanwhile is left alone', () async {
      await buildWithGeocoder();
      geo.holdReverse = Completer();
      final saved = await controller.add(title: 'x', location: here);
      await repo.moveToBin(saved.id!, now);
      geo.holdReverse!.complete();
      await controller.lastAddressLookup;
      expect((await repo.getById(saved.id!))!.address, isNull);
    });

    test('without a geocoder nothing is looked up', () async {
      build();
      await controller.add(title: 'x', location: here);
      expect(controller.lastAddressLookup, isNull);
    });
  });
}
