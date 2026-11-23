import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:questmark/data/mbtiles_archive.dart';
import 'package:questmark/data/world_map_installer.dart';
import 'package:questmark/ui/map/map_config.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Checks the world map files that actually ship in assets/map/ (made by
/// tool/build_world_map.dart), so a bad rebuild can't slip into the app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('world.json describes world.mbtiles exactly', () async {
    final manifest = jsonDecode(
            await rootBundle.loadString(WorldMapInstaller.manifestAsset))
        as Map<String, Object?>;
    final file = File(WorldMapInstaller.mapAsset);
    expect(manifest['bytes'], await file.length(),
        reason: 'the app uses the size to tell a good copy from a bad one');
    expect(manifest['version'], isA<String>());
    expect(manifest['maxZoom'], 4, reason: 'user decision in Phase 8a');
  });

  test('world.mbtiles opens and has every tile of zoom 0-4', () async {
    sqfliteFfiInit();
    final archive = await MbTilesArchive.open(
        File(WorldMapInstaller.mapAsset).absolute.path,
        factory: databaseFactoryFfi);
    addTearDown(archive.close);
    expect(archive.minZoom, 0);
    expect(archive.maxZoom, 4);

    // Spot checks: the whole world at zoom 0, and Helsinki at zoom 4.
    for (final (z, x, y) in [(0, 0, 0), (4, 9, 4)]) {
      final bytes = await archive.tile(z, x, y);
      expect(bytes, isNotNull, reason: '$z/$x/$y');
      expect(bytes!.take(2), [0x1f, 0x8b], reason: 'stored gzipped');
    }
  });

  test('the offline style reads with no network, and needs none', () async {
    final json = jsonDecode(
            await rootBundle.loadString(MapConfig.offlineStyleAsset))
        as Map<String, Object?>;
    expect(json.containsKey('sprite'), isFalse);
    expect(json.containsKey('glyphs'), isFalse);
    expect((json['sources'] as Map).keys, [MapConfig.tileSourceId]);

    final resolved = <String>[];
    final style = await vt.StyleReader(
      uri: 'asset://${MapConfig.offlineStyleAsset}',
      cache: false,
      // Any HTTP request would fail this test.
      httpClient: MockClient((r) async => fail('network used: ${r.url}')),
      resolveProvider: (id) async {
        resolved.add(id);
        return vt.MemoryVectorTileProvider(tiles: {});
      },
    ).read();
    addTearDown(style.dispose);
    expect(resolved, [MapConfig.tileSourceId]);
    expect(style.sprites, isNull);
    expect(style.glyphs, isNull);
  });
}
