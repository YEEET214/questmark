import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/geo_point.dart';
import '../models/offline_region.dart';
import '../models/region_plan.dart';

/// Downloaded map tiles, for the map to draw from (PLAN.md D7).
abstract interface class RegionTileSource {
  /// The stored bytes of tile z/x/y: `null` if no region has it, empty if
  /// a region has it but the map server had no tile there (e.g. open sea).
  Future<Uint8List?> tile(int z, int x, int y);

  /// Whether any region has tiles at all.
  Future<bool> hasTiles();
}

/// The downloaded regions and their tiles, in their own SQLite file
/// (`offline_maps.db`), apart from the quests (PLAN.md D26):
///
/// * `tiles`: each tile once (as downloaded, usually gzipped), however many
///   regions include it;
/// * `region_tiles`: which region has which tile, so a tile shared by two
///   regions stays until both are deleted;
/// * `regions`: name, area, progress and status, for the Offline maps list;
/// * `settings`: e.g. "don't offer my area again".
class OfflineRegionStore implements RegionTileSource {
  OfflineRegionStore._(this._db);

  final Database _db;

  static const fileName = 'offline_maps.db';
  static const _version = 1;

  /// Opens (creating if needed) the store. [path] defaults to
  /// [fileName] in the app's databases folder; tests pass
  /// `inMemoryDatabasePath` and an FFI [factory].
  static Future<OfflineRegionStore> open({
    String? path,
    DatabaseFactory? factory,
  }) async {
    final f = factory ?? databaseFactory;
    // sqflite resolves relative paths against its own folder, so the
    // path is always made absolute (D25).
    final file = path ?? p.join(await f.getDatabasesPath(), fileName);
    final db = await f.openDatabase(
      file,
      options: OpenDatabaseOptions(
        version: _version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          final batch = db.batch()
            ..execute('''
              CREATE TABLE regions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                name_is_auto INTEGER NOT NULL,
                center_lat REAL NOT NULL,
                center_lng REAL NOT NULL,
                size TEXT NOT NULL,
                status TEXT NOT NULL,
                planned_tiles INTEGER NOT NULL,
                done_tiles INTEGER NOT NULL DEFAULT 0,
                bytes INTEGER NOT NULL DEFAULT 0,
                downloaded_bytes INTEGER NOT NULL DEFAULT 0,
                covered_radius INTEGER NOT NULL DEFAULT -1,
                problem TEXT,
                created_at INTEGER NOT NULL
              )''')
            ..execute('''
              CREATE TABLE tiles (
                z INTEGER NOT NULL,
                x INTEGER NOT NULL,
                y INTEGER NOT NULL,
                data BLOB NOT NULL,
                PRIMARY KEY (z, x, y)
              ) WITHOUT ROWID''')
            ..execute('''
              CREATE TABLE region_tiles (
                region_id INTEGER NOT NULL
                  REFERENCES regions(id) ON DELETE CASCADE,
                z INTEGER NOT NULL,
                x INTEGER NOT NULL,
                y INTEGER NOT NULL,
                PRIMARY KEY (region_id, z, x, y)
              ) WITHOUT ROWID''')
            ..execute(
                'CREATE INDEX idx_region_tiles_tile ON region_tiles (z, x, y)')
            ..execute(
                'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
          await batch.commit(noResult: true);
        },
      ),
    );
    return OfflineRegionStore._(db);
  }

  Future<void> close() => _db.close();

  // ---- Regions ----

  /// All regions, newest first.
  Future<List<OfflineRegion>> regions() async {
    final rows = await _db.query('regions', orderBy: 'created_at DESC, id DESC');
    return [for (final r in rows) _fromRow(r)];
  }

  Future<OfflineRegion?> region(int id) async {
    final rows = await _db.query('regions', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<OfflineRegion> createRegion({
    required String name,
    required GeoPoint center,
    required RegionSize size,
    required DateTime createdAt,
    bool nameIsAuto = true,
  }) async {
    final id = await _db.insert('regions', {
      'name': name,
      'name_is_auto': nameIsAuto ? 1 : 0,
      'center_lat': center.latitude,
      'center_lng': center.longitude,
      'size': size.name,
      'status': RegionStatus.downloading.name,
      'planned_tiles': RegionPlan(center, size).tileCount,
      'created_at': createdAt.millisecondsSinceEpoch,
    });
    return (await region(id))!;
  }

  /// A name the user chose.
  Future<void> rename(int id, String name) => _db.update(
      'regions', {'name': name, 'name_is_auto': 0},
      where: 'id = ?', whereArgs: [id]);

  /// A looked-up place name. Ignored if the user has renamed the region.
  Future<void> setAutoName(int id, String name) => _db.update(
      'regions', {'name': name},
      where: 'id = ? AND name_is_auto = 1', whereArgs: [id]);

  Future<void> setStatus(
    int id,
    RegionStatus status, {
    RegionProblem? problem,
    int? coveredRadius,
  }) =>
      _db.update(
        'regions',
        {
          'status': status.name,
          'problem': problem?.name,
          'covered_radius': ?coveredRadius,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

  /// Downloads that were running when the app was closed are paused, so
  /// they can be resumed (the app never resumes on its own).
  Future<void> pauseInterrupted() => _db.update(
        'regions',
        {
          'status': RegionStatus.paused.name,
          'problem': RegionProblem.interrupted.name,
        },
        where: 'status = ?',
        whereArgs: [RegionStatus.downloading.name],
      );

  /// Deletes the region and every tile no other region uses, then gives
  /// the space back to the phone.
  Future<void> deleteRegion(int id) async {
    await _db.transaction((txn) async {
      await txn.delete('region_tiles', where: 'region_id = ?', whereArgs: [id]);
      await txn.delete('regions', where: 'id = ?', whereArgs: [id]);
      await txn.rawDelete('''
        DELETE FROM tiles WHERE NOT EXISTS (
          SELECT 1 FROM region_tiles r
          WHERE r.z = tiles.z AND r.x = tiles.x AND r.y = tiles.y)''');
    });
    // SQLite doesn't shrink the file by itself.
    await _db.execute('VACUUM');
  }

  // ---- Tiles ----

  /// The tiles [regionId] already has (to resume where it stopped).
  Future<Set<TileId>> tilesOf(int regionId) async {
    final rows = await _db.query('region_tiles',
        columns: ['z', 'x', 'y'],
        where: 'region_id = ?',
        whereArgs: [regionId]);
    return {
      for (final r in rows) TileId(r['z']! as int, r['x']! as int, r['y']! as int),
    };
  }

  /// Gives [regionId] a tile another region already downloaded, without
  /// downloading it again. Returns false if no region has it.
  Future<bool> addExisting(int regionId, TileId tile) {
    return _db.transaction((txn) async {
      final rows = await txn.rawQuery(
          'SELECT length(data) AS n FROM tiles WHERE z = ? AND x = ? AND y = ?',
          [tile.z, tile.x, tile.y]);
      if (rows.isEmpty) return false;
      await _link(txn, regionId, tile, rows.first['n']! as int, 0);
      return true;
    });
  }

  /// Stores a downloaded tile for [regionId]. [data] is empty for "no tile
  /// here". [downloaded] is what the download cost, for the 50 MB limit.
  Future<void> addDownloaded(
    int regionId,
    TileId tile,
    Uint8List data, {
    required int downloaded,
  }) {
    return _db.transaction((txn) async {
      await txn.insert(
        'tiles',
        {'z': tile.z, 'x': tile.x, 'y': tile.y, 'data': data},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _link(txn, regionId, tile, data.length, downloaded);
    });
  }

  Future<void> _link(Transaction txn, int regionId, TileId tile, int size,
      int downloaded) async {
    final existing = await txn.query('region_tiles',
        columns: ['z'],
        where: 'region_id = ? AND z = ? AND x = ? AND y = ?',
        whereArgs: [regionId, tile.z, tile.x, tile.y]);
    final isNew = existing.isEmpty;
    if (isNew) {
      await txn.insert('region_tiles',
          {'region_id': regionId, 'z': tile.z, 'x': tile.x, 'y': tile.y});
    }
    await txn.rawUpdate('''
      UPDATE regions SET
        done_tiles = done_tiles + ?,
        bytes = bytes + ?,
        downloaded_bytes = downloaded_bytes + ?
      WHERE id = ?''', [isNew ? 1 : 0, isNew ? size : 0, downloaded, regionId]);
  }

  @override
  Future<Uint8List?> tile(int z, int x, int y) async {
    final rows = await _db.query('tiles',
        columns: ['data'],
        where: 'z = ? AND x = ? AND y = ?',
        whereArgs: [z, x, y],
        limit: 1);
    if (rows.isEmpty) return null;
    final data = rows.first['data'];
    return data is Uint8List ? data : Uint8List.fromList(data! as List<int>);
  }

  @override
  Future<bool> hasTiles() async =>
      (await _db.rawQuery('SELECT 1 FROM tiles LIMIT 1')).isNotEmpty;

  /// Space all offline maps take (each tile counted once).
  Future<int> totalBytes() async {
    final rows =
        await _db.rawQuery('SELECT COALESCE(SUM(length(data)), 0) AS n FROM tiles');
    return rows.first['n']! as int;
  }

  // ---- Settings ----

  Future<String?> setting(String key) async {
    final rows = await _db.query('settings',
        columns: ['value'], where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String? value) => _db.insert(
      'settings', {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace);

  static OfflineRegion _fromRow(Map<String, Object?> r) => OfflineRegion(
        id: r['id']! as int,
        name: r['name']! as String,
        nameIsAuto: r['name_is_auto'] == 1,
        center: GeoPoint(
            (r['center_lat']! as num).toDouble(), (r['center_lng']! as num).toDouble()),
        size: RegionSize.fromName(r['size']! as String),
        status: RegionStatus.fromName(r['status']! as String),
        plannedTiles: r['planned_tiles']! as int,
        doneTiles: r['done_tiles']! as int,
        bytes: r['bytes']! as int,
        downloadedBytes: r['downloaded_bytes']! as int,
        coveredRadius: r['covered_radius']! as int,
        problem: RegionProblem.fromName(r['problem'] as String?),
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at']! as int),
      );
}
