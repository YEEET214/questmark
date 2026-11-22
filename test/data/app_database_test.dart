import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:questmark/data/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_database.dart';

void main() {
  late Database db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  Map<String, Object?> validRow() => {'title': 'x', 'created_at': 0};

  group('fresh install', () {
    test('schema version equals the number of migrations', () async {
      expect(await db.getVersion(), AppDatabase.migrations.length);
    });

    test('creates the tasks table and its index', () async {
      final names = (await db.query('sqlite_master', columns: ['name']))
          .map((r) => r['name'])
          .toSet();
      expect(names, containsAll(['tasks', 'idx_tasks_done_created']));
    });

    test('is_done defaults to 0', () async {
      final id = await db.insert('tasks', validRow());
      final row =
          (await db.query('tasks', where: 'id = ?', whereArgs: [id])).single;
      expect(row['is_done'], 0);
    });
  });

  group('CHECK constraints (second line of defence behind the model)', () {
    Future<void> expectRejected(Map<String, Object?> row) async {
      await expectLater(
          db.insert('tasks', row), throwsA(isA<DatabaseException>()));
    }

    test('reject an empty or blank title', () async {
      await expectRejected({...validRow(), 'title': ''});
      await expectRejected({...validRow(), 'title': '   '});
    });

    test('reject only one coordinate set', () async {
      await expectRejected({...validRow(), 'latitude': 1.0});
      await expectRejected({...validRow(), 'longitude': 1.0});
    });

    test('reject out-of-range coordinates', () async {
      await expectRejected({...validRow(), 'latitude': 91.0, 'longitude': 0});
      await expectRejected(
          {...validRow(), 'latitude': 0, 'longitude': -181.0});
    });

    test('reject is_done values other than 0/1', () async {
      await expectRejected({...validRow(), 'is_done': 2});
    });

    test('accept a valid located row', () async {
      expect(
        await db.insert(
            'tasks', {...validRow(), 'latitude': 60.0, 'longitude': 25.0}),
        greaterThan(0),
      );
    });
  });

  group('upgrades', () {
    late Directory dir;
    late String path;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('questmark_db_test');
      path = p.join(dir.path, 'upgrade.db');
    });
    tearDown(() async => dir.delete(recursive: true));

    Future<void> createV1WithOneTask() async {
      final v1 =
          await AppDatabase.open(factory: databaseFactoryFfi, path: path);
      await v1.insert('tasks', {...validRow(), 'title': 'survivor'});
      await v1.close();
    }

    test('applying a new migration keeps existing data', () async {
      await createV1WithOneTask();

      // A hypothetical future migration adds a column.
      final schemaV2 = [
        ...AppDatabase.migrations,
        ['ALTER TABLE tasks ADD COLUMN priority INTEGER NOT NULL DEFAULT 0'],
      ];
      final v2 = await AppDatabase.open(
          factory: databaseFactoryFfi, path: path, schema: schemaV2);
      addTearDown(v2.close);

      expect(await v2.getVersion(), schemaV2.length);
      final rows = await v2.query('tasks');
      expect(rows.single['title'], 'survivor');
      expect(rows.single['priority'], 0);
    });

    test('the real v1 -> v2 upgrade adds completed_at and keeps tasks',
        () async {
      // Build a genuine version-1 database (only the first migration).
      final v1 = await AppDatabase.open(
          factory: databaseFactoryFfi,
          path: path,
          schema: AppDatabase.migrations.sublist(0, 1));
      await v1.insert('tasks', {...validRow(), 'title': 'old done', 'is_done': 1});
      expect(await v1.getVersion(), 1);
      await v1.close();

      final current =
          await AppDatabase.open(factory: databaseFactoryFfi, path: path);
      addTearDown(current.close);

      expect(await current.getVersion(), greaterThanOrEqualTo(2));
      final row = (await current.query('tasks')).single;
      expect(row['title'], 'old done');
      expect(row['is_done'], 1);
      expect(row.containsKey('completed_at'), isTrue);
      expect(row['completed_at'], isNull,
          reason: 'tasks completed before v2 have an unknown completion date');
    });

    test('the real v2 -> v3 upgrade adds deleted_at; nothing is in the bin',
        () async {
      final v2 = await AppDatabase.open(
          factory: databaseFactoryFfi,
          path: path,
          schema: AppDatabase.migrations.sublist(0, 2));
      await v2.insert('tasks', {...validRow(), 'title': 'kept'});
      expect(await v2.getVersion(), 2);
      await v2.close();

      final current =
          await AppDatabase.open(factory: databaseFactoryFfi, path: path);
      addTearDown(current.close);

      expect(await current.getVersion(), greaterThanOrEqualTo(3));
      final row = (await current.query('tasks')).single;
      expect(row['title'], 'kept');
      expect(row['deleted_at'], isNull, reason: 'existing tasks are not binned');
      final names = (await current.query('sqlite_master', columns: ['name']))
          .map((r) => r['name']);
      expect(names, contains('idx_tasks_deleted'));
    });

    test('the real v3 -> v4 upgrade adds an empty last_location table',
        () async {
      final v3 = await AppDatabase.open(
          factory: databaseFactoryFfi,
          path: path,
          schema: AppDatabase.migrations.sublist(0, 3));
      await v3.insert('tasks', {...validRow(), 'title': 'kept'});
      await v3.close();

      final current =
          await AppDatabase.open(factory: databaseFactoryFfi, path: path);
      addTearDown(current.close);

      expect(await current.getVersion(), greaterThanOrEqualTo(4));
      expect((await current.query('tasks')).single['title'], 'kept');
      expect(await current.query('last_location'), isEmpty);
    });

    test('a failing migration rolls back and leaves the old data intact',
        () async {
      await createV1WithOneTask();

      final broken = [
        ...AppDatabase.migrations,
        ['ALTER TABLE tasks ADD COLUMN ok INTEGER', 'THIS IS NOT SQL'],
      ];
      await expectLater(
        AppDatabase.open(
            factory: databaseFactoryFfi, path: path, schema: broken),
        throwsA(isA<DatabaseException>()),
      );

      final reopened =
          await AppDatabase.open(factory: databaseFactoryFfi, path: path);
      addTearDown(reopened.close);
      expect(await reopened.getVersion(), AppDatabase.migrations.length);
      final rows = await reopened.query('tasks');
      expect(rows.single['title'], 'survivor');
      expect(rows.single.containsKey('ok'), isFalse);
    });
  });
}
