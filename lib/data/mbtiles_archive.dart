import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

/// Reads vector tiles from an MBTiles file (a SQLite database with a
/// `tiles` table), read-only. Used for the world map bundled with the app
/// (PLAN.md D7).
///
/// MBTiles numbers rows bottom-up (TMS); this class takes and converts
/// the top-down (slippy map) numbers the map uses.
class MbTilesArchive {
  MbTilesArchive._(this._db, this.minZoom, this.maxZoom, this.version);

  final Database _db;

  /// Zoom range of the tiles in the file, from its metadata.
  final int minZoom;
  final int maxZoom;

  /// The file's build version (`version` + `generated` metadata), used to
  /// keep the map's tile caches apart from other builds.
  final String version;

  /// Opens [path] read-only. Throws if it isn't a readable MBTiles file.
  static Future<MbTilesArchive> open(String path,
      {DatabaseFactory? factory}) async {
    final db = await (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      final meta = {
        for (final r in await db.query('metadata'))
          r['name'] as String: r['value'] as String?,
      };
      int zoom(String key, int fallback) =>
          int.tryParse(meta[key] ?? '') ?? fallback;
      return MbTilesArchive._(
        db,
        zoom('minzoom', 0),
        zoom('maxzoom', 0),
        '${meta['version'] ?? ''}@${meta['generated'] ?? ''}',
      );
    } catch (_) {
      await db.close();
      rethrow;
    }
  }

  /// The tile's bytes (as stored: usually gzipped MVT), or `null` if the
  /// file has no tile there.
  Future<Uint8List?> tile(int z, int x, int y) async {
    if (z < minZoom || z > maxZoom || y < 0 || y >= (1 << z)) return null;
    final rows = await _db.query(
      'tiles',
      columns: ['tile_data'],
      where: 'zoom_level = ? AND tile_column = ? AND tile_row = ?',
      whereArgs: [z, x, (1 << z) - 1 - y],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final data = rows.first['tile_data'];
    return data is Uint8List ? data : Uint8List.fromList(data! as List<int>);
  }

  Future<void> close() => _db.close();
}
