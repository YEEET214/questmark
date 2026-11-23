import 'dart:typed_data';

import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/data/mbtiles_archive.dart';
import 'package:questmark/data/offline_region_store.dart';
import 'package:questmark/ui/map/world_map_tiles.dart';

import '../../helpers/test_mbtiles.dart';

/// Stands in for OpenFreeMap: records what it was asked for.
class FakeNetworkProvider extends vt.VectorTileProvider {
  final asked = <String>[];

  @override
  int get minimumZoom => 0;
  @override
  int get maximumZoom => 14;
  @override
  String get cacheKey => 'https://tiles.example/{z}/{x}/{y}.pbf';

  @override
  Future<vt.TileResponse> load(vt.TileKey tile,
      {vt.CancellationToken? cancellation}) async {
    asked.add('${tile.z}/${tile.x}/${tile.y}');
    return vt.TileResponseData(Uint8List.fromList([9, 9]));
  }
}

void main() {
  late MbTilesArchive world;

  setUp(() async {
    world = await openTestMbTiles({
      '0/0/0': [1],
      '5/17/9': [5, 5],
    }, maxZoom: 5, version: 'w1');
  });
  tearDown(() => world.close());

  List<int>? bytesOf(vt.TileResponse r) =>
      r is vt.TileResponseData ? r.bytes : null;

  group('WorldMapTileProvider (offline: the world map alone)', () {
    test('serves the file\'s tiles, and "not found" for the rest', () async {
      final p = WorldMapTileProvider(world);
      expect(bytesOf(await p.load(const vt.TileKey(5, 17, 9))), [5, 5]);
      expect(await p.load(const vt.TileKey(5, 0, 0)),
          isA<vt.TileResponseNotFound>());
    });

    test('zooms come from the file; closer zooms are overzoomed', () {
      final p = WorldMapTileProvider(world);
      expect(p.minimumZoom, 0);
      expect(p.maximumZoom, 5);
    });

    test('is not copied into the disk cache, and has its own cache key',
        () {
      final p = WorldMapTileProvider(world);
      expect(p.cacheBytesToDisk, isFalse);
      expect(p.cacheKey, contains('w1'));
    });

    test('a cancelled request is reported as cancelled', () async {
      final token = vt.CancellationToken()..cancel();
      expect(
          await WorldMapTileProvider(world)
              .load(const vt.TileKey(0, 0, 0), cancellation: token),
          isA<vt.TileResponseCancelled>());
    });
  });

  group('LocalFirstTileProvider (online, with the world map in front)', () {
    late FakeNetworkProvider network;
    late LocalFirstTileProvider p;
    setUp(() {
      network = FakeNetworkProvider();
      p = LocalFirstTileProvider(network, world: world);
    });

    test('zoom 0-4 (here 0-5) comes from the file, with no network request', () async {
      expect(bytesOf(await p.load(const vt.TileKey(0, 0, 0))), [1]);
      expect(bytesOf(await p.load(const vt.TileKey(5, 17, 9))), [5, 5]);
      expect(network.asked, isEmpty);
    });

    test('closer zooms come from the network, as before', () async {
      expect(bytesOf(await p.load(const vt.TileKey(6, 34, 18))), [9, 9]);
      expect(network.asked, ['6/34/18']);
    });

    test('a low-zoom tile missing from the file is fetched instead',
        () async {
      expect(bytesOf(await p.load(const vt.TileKey(3, 1, 1))), [9, 9]);
      expect(network.asked, ['3/1/1']);
    });

    test('keeps the network source\'s zoom range and cache', () {
      expect(p.maximumZoom, 14);
      expect(p.cacheKey, network.cacheKey);
      expect(p.cacheBytesToDisk, isTrue);
    });
  });

  test('withLocalMaps replaces only the OpenFreeMap source', () {
    final network = FakeNetworkProvider();
    final other = FakeNetworkProvider();
    final wrapped = withLocalMaps(
      vt.TileProviders({'openmaptiles': network, 'other': other}),
      world: world,
    );
    expect(wrapped['openmaptiles'], isA<LocalFirstTileProvider>());
    expect(wrapped['other'], same(other));
  });

  test('withLocalMaps leaves a style without that source unchanged', () {
    final providers = vt.TileProviders({'other': FakeNetworkProvider()});
    expect(withLocalMaps(providers, world: world), same(providers));
  });
  group('downloaded regions (PLAN.md D26)', () {
    late FakeRegionTiles regions;
    late FakeNetworkProvider network;
    setUp(() {
      regions = FakeRegionTiles({
        '8/127/79': [8, 8],
        '14/8000/5000': [14],
        '14/8001/5000': [], // the region has it, but there's no tile
      });
      network = FakeNetworkProvider();
    });

    test('online: zoom 5-14 from a region, with no network request',
        () async {
      final p = LocalFirstTileProvider(network, world: world, regions: regions);
      expect(bytesOf(await p.load(const vt.TileKey(8, 127, 79))), [8, 8]);
      expect(bytesOf(await p.load(const vt.TileKey(14, 8000, 5000))), [14]);
      expect(await p.load(const vt.TileKey(14, 8001, 5000)),
          isA<vt.TileResponseNotFound>());
      expect(network.asked, isEmpty);
    });

    test('online: outside the regions, from the network as before',
        () async {
      final p = LocalFirstTileProvider(network, world: world, regions: regions);
      expect(bytesOf(await p.load(const vt.TileKey(14, 1, 1))), [9, 9]);
      expect(network.asked, ['14/1/1']);
    });

    test('online: zoom 0-4 still come from the world map, not a region',
        () async {
      final p = LocalFirstTileProvider(network, world: world, regions: regions);
      expect(bytesOf(await p.load(const vt.TileKey(0, 0, 0))), [1]);
      expect(regions.asked, isEmpty);
    });

    test('online: a store that can\'t be read falls back to the network',
        () async {
      regions.broken = true;
      final p = LocalFirstTileProvider(network, regions: regions);
      expect(bytesOf(await p.load(const vt.TileKey(14, 8000, 5000))), [9, 9]);
    });

    test('offline: the world map below, regions above, empty elsewhere',
        () async {
      final p = OfflineTileProvider(world, regions);
      expect(p.maximumZoom, 14);
      expect(p.cacheBytesToDisk, isFalse);
      expect(bytesOf(await p.load(const vt.TileKey(0, 0, 0))), [1]);
      expect(bytesOf(await p.load(const vt.TileKey(14, 8000, 5000))), [14]);
      expect(await p.load(const vt.TileKey(14, 1, 1)),
          isA<vt.TileResponseNotFound>());
    });

    test('withLocalMaps works with regions alone (no world map)', () {
      final wrapped = withLocalMaps(
          vt.TileProviders({'openmaptiles': network}),
          regions: regions);
      expect(wrapped['openmaptiles'], isA<LocalFirstTileProvider>());
      final none = vt.TileProviders({'openmaptiles': network});
      expect(withLocalMaps(none), same(none));
    });
  });
}

/// Downloaded tiles in memory: `'z/x/y'` → bytes.
class FakeRegionTiles implements RegionTileSource {
  FakeRegionTiles(this.tiles);
  final Map<String, List<int>> tiles;
  final asked = <String>[];
  bool broken = false;

  @override
  Future<Uint8List?> tile(int z, int x, int y) async {
    asked.add('$z/$x/$y');
    if (broken) throw StateError('disk error');
    final t = tiles['$z/$x/$y'];
    return t == null ? null : Uint8List.fromList(t);
  }

  @override
  Future<bool> hasTiles() async => tiles.isNotEmpty;
}
