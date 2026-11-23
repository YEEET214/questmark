import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/data/mbtiles_archive.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_mbtiles.dart';

void main() {
  test('reads the zoom range and version from the metadata', () async {
    final a = await openTestMbTiles({}, minZoom: 0, maxZoom: 4, version: 'v9');
    addTearDown(a.close);
    expect(a.minZoom, 0);
    expect(a.maxZoom, 4);
    expect(a.version, contains('v9'));
  });

  test('finds tiles by slippy-map numbers (rows are flipped inside)',
      () async {
    final a = await openTestMbTiles({
      '2/1/0': [1, 2, 3],
      '2/1/3': [4, 5],
    });
    addTearDown(a.close);
    expect(await a.tile(2, 1, 0), [1, 2, 3]);
    expect(await a.tile(2, 1, 3), [4, 5]);
  });

  test('missing or out-of-range tiles are null, not errors', () async {
    final a = await openTestMbTiles({'0/0/0': [1]}, maxZoom: 5);
    addTearDown(a.close);
    expect(await a.tile(1, 0, 0), isNull, reason: 'not in the file');
    expect(await a.tile(6, 0, 0), isNull, reason: 'above maxzoom');
    expect(await a.tile(1, 0, 5), isNull, reason: 'row outside the grid');
  });

  test('a file that is not MBTiles fails to open', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('mbtiles_bad');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/bad.mbtiles';
    final db = await databaseFactoryFfi.openDatabase(path);
    await db.execute('CREATE TABLE something_else (x INTEGER)');
    await db.close();
    await expectLater(MbTilesArchive.open(path, factory: databaseFactoryFfi),
        throwsA(anything));
  });
}
