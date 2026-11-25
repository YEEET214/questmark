import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// A tile from the cache, and whether it's still fresh.
class CachedTile {
  const CachedTile(this.bytes, {required this.fresh});

  /// Empty for "the server had no tile here".
  final Uint8List bytes;
  final bool fresh;
}

/// The tiles seen while browsing online, so a revisit costs the server
/// nothing and works offline (PLAN.md D5, D27).
abstract interface class NetworkTileCache {
  Future<CachedTile?> get(int z, int x, int y);
  Future<void> put(int z, int x, int y, Uint8List bytes);

  /// Space the cached tiles take (shown in Settings, D29).
  int get sizeBytes;

  /// Removes every cached tile and gives the space back (Settings).
  Future<void> clear();
}

/// [NetworkTileCache] in its own SQLite file (`map_cache.db`).
///
/// The app keeps this cache itself, instead of the map package's, so a
/// stand-in tile made while offline (D27) is never stored as if it were
/// the real one, and downloaded regions aren't copied into it.
///
/// * Tiles older than [ttl] are "stale": still served when the network
///   fails, else fetched again.
/// * Past [maxBytes] the oldest tiles are removed, down to 90 %.
class SqfliteTileCache implements NetworkTileCache {
  SqfliteTileCache._(this._db, this.maxBytes, this.ttl, this._clock,
      this._bytes);

  final Database _db;
  final int maxBytes;
  final Duration ttl;
  final DateTime Function() _clock;

  /// Total size of the cached tiles, kept up to date on every write.
  int _bytes;

  @override
  int get sizeBytes => _bytes;

  static const fileName = 'map_cache.db';

  static Future<SqfliteTileCache> open({
    String? path,
    DatabaseFactory? factory,
    required int maxBytes,
    required Duration ttl,
    DateTime Function()? clock,
  }) async {
    final f = factory ?? databaseFactory;
    // Always an absolute path (sqflite resolves relative ones against its
    // own folder, D25).
    final file = path ?? p.join(await f.getDatabasesPath(), fileName);
    final db = await f.openDatabase(
      file,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE cache_tiles (
              z INTEGER NOT NULL,
              x INTEGER NOT NULL,
              y INTEGER NOT NULL,
              data BLOB NOT NULL,
              fetched_at INTEGER NOT NULL,
              PRIMARY KEY (z, x, y)
            ) WITHOUT ROWID''');
          await db.execute(
              'CREATE INDEX idx_cache_tiles_age ON cache_tiles (fetched_at)');
        },
      ),
    );
    final rows = await db.rawQuery(
        'SELECT COALESCE(SUM(length(data)), 0) AS n FROM cache_tiles');
    return SqfliteTileCache._(
        db, maxBytes, ttl, clock ?? DateTime.now, rows.first['n']! as int);
  }

  Future<void> close() => _db.close();

  @override
  Future<CachedTile?> get(int z, int x, int y) async {
    final rows = await _db.query('cache_tiles',
        columns: ['data', 'fetched_at'],
        where: 'z = ? AND x = ? AND y = ?',
        whereArgs: [z, x, y]);
    if (rows.isEmpty) return null;
    final data = rows.first['data'];
    final at = DateTime.fromMillisecondsSinceEpoch(
        rows.first['fetched_at']! as int);
    return CachedTile(
      data is Uint8List ? data : Uint8List.fromList(data! as List<int>),
      fresh: _clock().difference(at) < ttl,
    );
  }

  @override
  Future<void> put(int z, int x, int y, Uint8List bytes) async {
    await _db.transaction((txn) async {
      final old = await txn.rawQuery(
          'SELECT length(data) AS n FROM cache_tiles '
          'WHERE z = ? AND x = ? AND y = ?',
          [z, x, y]);
      if (old.isNotEmpty) _bytes -= old.first['n']! as int;
      await txn.insert(
        'cache_tiles',
        {
          'z': z,
          'x': x,
          'y': y,
          'data': bytes,
          'fetched_at': _clock().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      _bytes += bytes.length;
    });
    if (_bytes > maxBytes) await _evict();
  }

  @override
  Future<void> clear() async {
    await _db.delete('cache_tiles');
    _bytes = 0;
    // SQLite doesn't shrink the file by itself.
    await _db.execute('VACUUM');
  }

  /// Removes the oldest tiles until the cache is at 90 % of [maxBytes].
  Future<void> _evict() async {
    final target = maxBytes * 9 ~/ 10;
    while (_bytes > target) {
      final rows = await _db.rawQuery(
          'SELECT z, x, y, length(data) AS n FROM cache_tiles '
          'ORDER BY fetched_at LIMIT 100');
      if (rows.isEmpty) {
        _bytes = 0;
        return;
      }
      final batch = _db.batch();
      for (final r in rows) {
        if (_bytes <= target) break;
        batch.delete('cache_tiles',
            where: 'z = ? AND x = ? AND y = ?',
            whereArgs: [r['z'], r['x'], r['y']]);
        _bytes -= r['n']! as int;
      }
      await batch.commit(noResult: true);
    }
  }
}
