import 'dart:io';
import 'dart:typed_data';

// The package's own decoder, to check the output is a tile it can read.
// ignore: implementation_imports
import 'package:flutter_map_vector_tiles/src/mvt/mvt_decoder.dart';
// ignore: implementation_imports
import 'package:flutter_map_vector_tiles/src/mvt/mvt_tile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/data/mbtiles_archive.dart';
import 'package:questmark/services/mvt_overzoom.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/mvt_builder.dart';

MvtLayer _layer(Uint8List bytes, String name) =>
    decodeMvt(bytes).layer(name)!;

List<double> _coords(MvtFeature f) => [for (final p in f.parts) ...p];

void main() {
  // An outer square over the whole tile, with a hole in the top-left
  // quarter.
  final water = mvtTile('water', [
    mvtFeature(3, [
      [0, 0, 4096, 0, 4096, 4096, 0, 4096], // clockwise (y down): outer
      [512, 512, 512, 1536, 1536, 1536, 1536, 512], // anticlockwise: hole
    ], nameValue: 0),
  ]);

  test('the zoomed tile is a valid tile with the same layers and names',
      () {
    final out = overzoomMvt(water, dz: 1, dx: 1, dy: 1);
    final layer = _layer(out, 'water');
    expect(layer.extent, 4096);
    expect(layer.features, hasLength(1));
    expect(layer.features.single.type, MvtGeomType.polygon);
    expect(layer.features.single.decodeProperties(layer), {'name': 'Sea'});
  });

  test('a polygon covering the tile still covers the zoomed tile', () {
    // Bottom-right quarter: no hole there, so one ring, cut to the window.
    final f = _layer(overzoomMvt(water, dz: 1, dx: 1, dy: 1), 'water')
        .features
        .single;
    expect(f.parts, hasLength(1));
    expect(f.minX, lessThanOrEqualTo(0));
    expect(f.minY, lessThanOrEqualTo(0));
    expect(f.maxX, greaterThanOrEqualTo(4096));
    expect(f.maxY, greaterThanOrEqualTo(4096));
    // Cut to the window plus the 128 buffer, not the whole parent scaled
    // (which would reach -4096).
    expect(f.minX, greaterThanOrEqualTo(-128));
  });

  test('a hole is kept, scaled, where it falls inside the zoomed tile', () {
    // Top-left quarter: the hole (512..1536) becomes 1024..3072.
    final f = _layer(overzoomMvt(water, dz: 1, dx: 0, dy: 0), 'water')
        .features
        .single;
    expect(f.parts, hasLength(2));
    final hole = f.parts[1];
    final xs = [for (var i = 0; i < hole.length; i += 2) hole[i]];
    expect(xs.reduce((a, b) => a < b ? a : b), 1024);
    expect(xs.reduce((a, b) => a > b ? a : b), 3072);
  });

  test('lines are cut into the runs inside the window; points outside drop',
      () {
    final tile = mvtTile('transportation', [
      // A line across the whole parent tile, left to right, at y = 1000.
      mvtFeature(2, [
        [0, 1000, 4096, 1000],
      ]),
      // A point in the top-right quarter and one in the top-left.
      mvtFeature(1, [
        [3000, 1000],
      ]),
      mvtFeature(1, [
        [100, 100],
      ]),
    ]);
    final layer = _layer(overzoomMvt(tile, dz: 1, dx: 1, dy: 0), 'transportation');
    final lines =
        layer.features.where((f) => f.type == MvtGeomType.lineString);
    final points = layer.features.where((f) => f.type == MvtGeomType.point);
    final c = _coords(lines.single);
    // The line ends at the parent's edge, which is this tile's right edge.
    expect(c, [-128, 2000, 4096, 2000]);
    expect(points, hasLength(1));
    expect(_coords(points.single), [3000 * 2 - 4096, 2000]);
  });

  test('a layer with nothing left is dropped; deep zoom works (dz 10)', () {
    final tile = mvtTile('poi', [
      mvtFeature(1, [
        [10, 10],
      ]),
    ]);
    expect(decodeMvt(overzoomMvt(tile, dz: 1, dx: 1, dy: 1)).layers, isEmpty);

    final deep = overzoomMvt(water, dz: 10, dx: 1000, dy: 1000);
    final f = _layer(deep, 'water').features.single;
    expect(f.parts, hasLength(1), reason: 'far from the hole');
    expect(f.maxX, greaterThanOrEqualTo(4096));
  });

  test('gzipped input is read too', () {
    final out =
        overzoomMvt(Uint8List.fromList(gzip.encode(water)), dz: 1, dx: 0, dy: 0);
    expect(_layer(out, 'water').features, hasLength(1));
  });

  test('a real zoom-4 world tile becomes a readable zoom-8 tile, with water',
      () async {
    sqfliteFfiInit();
    final file = File('assets/map/world.mbtiles');
    if (!file.existsSync()) {
      markTestSkipped('no bundled world map in this checkout');
      return;
    }
    final world =
        await MbTilesArchive.open(file.absolute.path, factory: databaseFactoryFfi);
    addTearDown(world.close);
    // Zoom 4 tile over the North Sea / Scotland: 4/7/4.
    final parent = (await world.tile(4, 7, 4))!;
    // A zoom-8 tile at sea east of Dundee: 8/126/78 → inside 4/7/4 at
    // (126 - 7·16, 78 - 4·16) = (14, 14).
    final child = overzoomMvt(parent, dz: 4, dx: 14, dy: 14);
    final tile = decodeMvt(child);
    expect(tile.layer('water'), isNotNull);
    expect(child.length, lessThan(parent.length * 4),
        reason: 'cut down, not the whole parent');
    for (final layer in tile.layers) {
      for (final f in layer.features) {
        expect(f.minX, greaterThanOrEqualTo(-129), reason: layer.name);
        expect(f.maxX, lessThanOrEqualTo(4096 + 129), reason: layer.name);
      }
    }
  });
}
