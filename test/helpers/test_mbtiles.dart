import 'dart:io';
import 'dart:typed_data';

import 'package:questmark/data/mbtiles_archive.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Writes a small MBTiles file to a temp folder and opens it, for tests.
/// [tiles] uses slippy-map numbering, `'z/x/y'` → bytes; they're stored
/// with the MBTiles (TMS) row flip, like the real build script does.
Future<MbTilesArchive> openTestMbTiles(
  Map<String, List<int>> tiles, {
  int minZoom = 0,
  int maxZoom = 5,
  String version = 'test',
}) async {
  sqfliteFfiInit();
  final dir = await Directory.systemTemp.createTemp('mbtiles_test');
  final path = '${dir.path}/world.mbtiles';
  final db = await databaseFactoryFfi.openDatabase(path);
  await db.execute('CREATE TABLE metadata (name TEXT, value TEXT)');
  await db.execute('CREATE TABLE tiles (zoom_level INTEGER, '
      'tile_column INTEGER, tile_row INTEGER, tile_data BLOB)');
  for (final e in {
    'minzoom': '$minZoom',
    'maxzoom': '$maxZoom',
    'version': version,
    'generated': '2026-11-23',
  }.entries) {
    await db.insert('metadata', {'name': e.key, 'value': e.value});
  }
  for (final e in tiles.entries) {
    final [z, x, y] = e.key.split('/').map(int.parse).toList();
    await db.insert('tiles', {
      'zoom_level': z,
      'tile_column': x,
      'tile_row': (1 << z) - 1 - y,
      'tile_data': Uint8List.fromList(e.value),
    });
  }
  await db.close();
  return MbTilesArchive.open(path, factory: databaseFactoryFfi);
}
