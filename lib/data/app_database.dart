import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/task.dart';

/// One schema migration: a list of SQL statements that moves the database
/// from version N to N + 1.
typedef Migration = List<String>;

/// Opens the app's SQLite database and keeps its schema up to date.
///
/// ## How migrations work
/// [migrations] is an ordered list: entry 0 creates version 1, entry 1
/// turns version 1 into version 2, and so on. The schema version is
/// `migrations.length`.
/// * A **fresh install** runs every migration in order (in `onCreate`).
/// * An **upgrade** runs only the migrations the existing file is missing
///   (in `onUpgrade`).
///
/// Both paths run the same statements, so a fresh install and an upgraded
/// install always end up with the same schema. sqflite runs both callbacks
/// inside a transaction, so a failing migration leaves the old database
/// untouched.
///
/// **Rule:** never edit a migration that has shipped. Append a new one.
class AppDatabase {
  AppDatabase._();

  static const fileName = 'questmark.db';

  /// The app's schema history. Later phases append entries here
  /// (e.g. the geocode cache in phase 7, map regions in phase 8b).
  static const List<Migration> migrations = [
    // v1: tasks table.
    [
      '''
      CREATE TABLE tasks (
        ${Task.colId}          INTEGER PRIMARY KEY AUTOINCREMENT,
        ${Task.colTitle}       TEXT    NOT NULL CHECK (length(trim(${Task.colTitle})) > 0),
        ${Task.colDescription} TEXT,
        ${Task.colIsDone}      INTEGER NOT NULL DEFAULT 0 CHECK (${Task.colIsDone} IN (0, 1)),
        ${Task.colCreatedAt}   INTEGER NOT NULL,
        ${Task.colDueAt}       INTEGER,
        ${Task.colAddress}     TEXT,
        ${Task.colLatitude}    REAL CHECK (${Task.colLatitude} BETWEEN -90 AND 90),
        ${Task.colLongitude}   REAL CHECK (${Task.colLongitude} BETWEEN -180 AND 180),
        CHECK ((${Task.colLatitude} IS NULL) = (${Task.colLongitude} IS NULL))
      )
      ''',
      // Matches the list ordering (active first), so sorting stays cheap
      // as the list grows.
      'CREATE INDEX idx_tasks_done_created '
          'ON tasks (${Task.colIsDone}, ${Task.colCreatedAt})',
    ],
  ];

  /// Opens (creating or upgrading as needed) the database.
  ///
  /// * [factory]: defaults to the platform sqflite factory. Tests pass
  ///   `databaseFactoryFfi`, which runs on the PC.
  /// * [path]: defaults to `questmark.db` in the app's databases folder.
  ///   Tests pass `inMemoryDatabasePath` or a temp file.
  /// * [schema]: defaults to [migrations]. Tests pass shorter or longer
  ///   lists to exercise the upgrade path.
  static Future<Database> open({
    DatabaseFactory? factory,
    String? path,
    List<Migration> schema = migrations,
  }) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    return f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schema.length,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => _migrate(db, schema, from: 0, to: version),
        onUpgrade: (db, from, to) => _migrate(db, schema, from: from, to: to),
        // Single-instance is the sqflite default. Tests that need two
        // independent in-memory databases switch it off.
        singleInstance: path != inMemoryDatabasePath,
      ),
    );
  }

  static Future<void> _migrate(
    Database db,
    List<Migration> schema, {
    required int from,
    required int to,
  }) async {
    for (var v = from; v < to; v++) {
      for (final statement in schema[v]) {
        await db.execute(statement);
      }
    }
  }
}
