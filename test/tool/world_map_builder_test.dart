import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../tool/world_map/world_map_builder.dart';

/// A fake OpenFreeMap: a style, its TileJSON, and tiles whose bytes say
/// which tile they are. Records every request.
class _FakeServer {
  final requests = <http.Request>[];
  var inFlight = 0;
  var maxInFlight = 0;

  /// Tiles that answer 404 ("no tile here").
  final missing = <String>{};

  /// Status codes to answer, in order, before answering normally.
  final queuedStatuses = <int>[];

  Map<String, Object?> style = {
    'version': 8,
    'name': 'Liberty',
    'sprite': 'https://tiles.example/sprites/ofm',
    'glyphs': 'https://tiles.example/fonts/{fontstack}/{range}.pbf',
    'sources': {
      'openmaptiles': {
        'type': 'vector',
        'url': 'https://tiles.example/planet',
      },
      'ne2_shaded': {'type': 'raster', 'tiles': ['https://x/{z}/{x}/{y}.png']},
    },
    'layers': [
      {'id': 'background', 'type': 'background'},
      {'id': 'relief', 'type': 'raster', 'source': 'ne2_shaded'},
      {'id': 'water', 'type': 'fill', 'source': 'openmaptiles'},
    ],
  };

  late final client = MockClient((request) async {
    requests.add(request);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final path = request.url.path;
      if (path == '/styles/liberty') {
        return _utf8(jsonEncode(style));
      }
      if (path == '/planet') {
        return _utf8(
            jsonEncode({
              'tiles': ['https://tiles.example/v1/{z}/{x}/{y}.pbf'],
              'attribution': '© OpenMapTiles © OSM',
              'vector_layers': [
                {'id': 'water'}
              ],
              'version': '3.15',
            }));
      }
      if (queuedStatuses.isNotEmpty) {
        return http.Response('', queuedStatuses.removeAt(0));
      }
      final tile = path.replaceFirst('/v1/', '').replaceFirst('.pbf', '');
      if (missing.contains(tile)) return http.Response('', 404);
      // Plain (not gzipped) bytes, like a client that already inflated them.
      return http.Response.bytes(utf8.encode('tile $tile'), 200);
    } finally {
      inFlight--;
    }
  });
}

/// JSON as real servers send it: UTF-8 bytes.
http.Response _utf8(String body) => http.Response.bytes(utf8.encode(body), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  late Directory dir;
  late _FakeServer server;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('world_map_test');
    server = _FakeServer();
  });
  tearDown(() async => dir.delete(recursive: true));

  WorldMapBuilder builder({
    int maxZoom = 2,
    int maxTiles = 3000,
    int maxBytes = 50 * 1024 * 1024,
  }) =>
      WorldMapBuilder(
        client: server.client,
        databaseFactory: databaseFactoryFfi,
        userAgent: 'QuestMark/1.0.0',
        styleUrl: 'https://tiles.example/styles/liberty',
        maxZoom: maxZoom,
        maxTiles: maxTiles,
        maxBytes: maxBytes,
        retryDelay: Duration.zero,
      );

  late String mbtiles;
  late String stylePath;
  setUp(() {
    mbtiles = '${dir.path}/world.mbtiles';
    stylePath = '${dir.path}/style.json';
  });

  Future<WorldMapReport> build(WorldMapBuilder b) =>
      b.build(mbtilesPath: mbtiles, stylePath: stylePath);

  group('tile maths', () {
    test('zoom 0-5 is 1,365 tiles; zoom 0-4 is 341', () {
      expect(WorldMapBuilder.tilesUpTo(5), hasLength(1365));
      expect(WorldMapBuilder.tilesUpTo(4), hasLength(341));
      expect(WorldMapBuilder.tilesUpTo(0), [(z: 0, x: 0, y: 0)]);
    });

    test('MBTiles rows are flipped (TMS)', () {
      expect(WorldMapBuilder.tmsRow(0, 0), 0);
      expect(WorldMapBuilder.tmsRow(2, 0), 3);
      expect(WorldMapBuilder.tmsRow(2, 3), 0);
    });
  });

  test('downloads every tile once, politely, and writes a valid MBTiles',
      () async {
    final report = await build(builder());

    final tileRequests =
        server.requests.where((r) => r.url.path.startsWith('/v1/')).toList();
    expect(tileRequests, hasLength(21), reason: '1 + 4 + 16 tiles');
    expect(tileRequests.map((r) => r.url.path).toSet(), hasLength(21));
    for (final r in server.requests) {
      expect(r.headers['User-Agent'], 'QuestMark/1.0.0');
    }
    expect(server.maxInFlight, lessThanOrEqualTo(2),
        reason: 'OpenFreeMap allows 4 at once; we use 2');
    expect(report.tilesStored, 21);

    final db = await databaseFactoryFfi.openDatabase(mbtiles);
    addTearDown(db.close);
    final meta = {
      for (final r in await db.query('metadata'))
        r['name'] as String: r['value'] as String,
    };
    expect(meta['format'], 'pbf');
    expect(meta['minzoom'], '0');
    expect(meta['maxzoom'], '2');
    expect(meta['attribution'], '© OpenMapTiles © OSM');

    // Slippy tile 2/1/0 is stored at TMS row 3, gzipped.
    final row = (await db.query('tiles',
            where: 'zoom_level = 2 AND tile_column = 1 AND tile_row = 3'))
        .single;
    final data = row['tile_data'] as List<int>;
    expect(data.take(2), [0x1f, 0x8b], reason: 'stored gzipped');
    expect(utf8.decode(gzip.decode(data)), 'tile 2/1/0');
  });

  test('a relative output path is relative to the current folder', () async {
    final before = Directory.current;
    Directory.current = dir;
    addTearDown(() => Directory.current = before);
    await builder(maxZoom: 0)
        .build(mbtilesPath: 'out/world.mbtiles', stylePath: 'style.json');
    expect(File('${dir.path}/out/world.mbtiles').existsSync(), isTrue);
  });

  test('tiles the server does not have (404) are simply skipped', () async {
    server.missing.add('2/3/3');
    final report = await build(builder());
    expect(report.tilesStored, 20);
  });

  test('over the tile limit: stops before downloading anything', () async {
    await expectLater(build(builder(maxZoom: 2, maxTiles: 20)),
        throwsA(isA<WorldMapBuildException>()));
    expect(server.requests, isEmpty);
    expect(File(mbtiles).existsSync(), isFalse);
  });

  test('over the size limit: stops, sends no more requests, writes nothing',
      () async {
    await expectLater(build(builder(maxZoom: 3, maxBytes: 200)),
        throwsA(isA<WorldMapBuildException>()));
    final tileRequests =
        server.requests.where((r) => r.url.path.startsWith('/v1/')).length;
    expect(tileRequests, lessThan(85), reason: 'stopped early');
    expect(File(mbtiles).existsSync(), isFalse);
  });

  test('a temporary server error is retried', () async {
    server.queuedStatuses.addAll([503, 429]);
    final report = await build(builder(maxZoom: 1));
    expect(report.tilesStored, 5);
  });

  test('a lasting error fails the build', () async {
    server.queuedStatuses.addAll(List.filled(50, 500));
    await expectLater(build(builder(maxZoom: 1)),
        throwsA(isA<WorldMapBuildException>()));
  });

  test('writes the offline style next to the tiles', () async {
    await build(builder(maxZoom: 0));
    final style =
        jsonDecode(File(stylePath).readAsStringSync()) as Map<String, Object?>;
    expect(style.containsKey('sprite'), isFalse);
    expect(style.containsKey('glyphs'), isFalse);
  });

  group('offlineStyle', () {
    test('keeps only the vector source and the layers that work offline',
        () {
      final style = WorldMapBuilder.offlineStyle(server.style, 'openmaptiles');
      expect((style['sources'] as Map).keys, ['openmaptiles']);
      expect([for (final l in style['layers'] as List) (l as Map)['id']],
          ['background', 'water']);
      expect(style.containsKey('sprite'), isFalse,
          reason: 'icons need the network');
      expect(style.containsKey('glyphs'), isFalse,
          reason: 'map fonts need the network; the phone\'s fonts are used');
      expect(style['name'], 'Liberty (QuestMark offline)');
      expect(style['version'], 8);
    });
  });
}
