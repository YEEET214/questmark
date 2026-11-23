import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Builds the low-detail world map that ships inside the app (PLAN.md D7,
/// Phase 8a): every vector tile of zoom 0..[maxZoom] from OpenFreeMap,
/// packed into one MBTiles file, plus an offline copy of the map style.
///
/// It runs **once, on a developer's PC** (`dart run tool/build_world_map.dart`),
/// never in the app. It follows OpenFreeMap's rules for offline downloads:
/// * at most [maxTiles] tiles (OpenFreeMap allows 3,000 per download) and
///   [maxBytes] bytes (50 MB); the tile count is checked *before*
///   downloading anything;
/// * at most [parallel] requests at a time (OpenFreeMap allows 4; we use 2);
/// * a User-Agent naming the app.
class WorldMapBuilder {
  WorldMapBuilder({
    required this.client,
    required this.databaseFactory,
    required this.userAgent,
    this.styleUrl = 'https://tiles.openfreemap.org/styles/liberty',
    this.sourceId = 'openmaptiles',
    this.maxZoom = 5,
    this.parallel = 2,
    this.maxTiles = 3000,
    this.maxBytes = 50 * 1024 * 1024,
    this.retries = 3,
    this.retryDelay = const Duration(seconds: 2),
    void Function(String)? log,
  }) : log = log ?? ((_) {});

  final http.Client client;
  final DatabaseFactory databaseFactory;
  final String userAgent;
  final String styleUrl;

  /// The style source the tiles come from.
  final String sourceId;
  final int maxZoom;
  final int parallel;
  final int maxTiles;
  final int maxBytes;
  final int retries;
  final Duration retryDelay;
  final void Function(String) log;

  Map<String, String> get _headers => {'User-Agent': userAgent};

  /// Every tile of zoom 0..[maxZoom], in slippy-map (XYZ) numbering.
  static List<({int z, int x, int y})> tilesUpTo(int maxZoom) => [
        for (var z = 0; z <= maxZoom; z++)
          for (var x = 0; x < (1 << z); x++)
            for (var y = 0; y < (1 << z); y++) (z: z, x: x, y: y),
      ];

  /// MBTiles stores rows bottom-up (TMS); slippy maps count top-down.
  static int tmsRow(int z, int y) => (1 << z) - 1 - y;

  /// Downloads everything and writes [mbtilesPath] and [stylePath].
  /// Throws [WorldMapBuildException] if a limit would be broken or a tile
  /// can't be fetched; the output files are then not written.
  Future<WorldMapReport> build({
    required String mbtilesPath,
    required String stylePath,
  }) async {
    // sqflite resolves a relative path against its own databases folder,
    // not the current directory, so make it absolute first.
    mbtilesPath = File(mbtilesPath).absolute.path;
    final tiles = tilesUpTo(maxZoom);
    if (tiles.length > maxTiles) {
      throw WorldMapBuildException(
          '${tiles.length} tiles is over the limit of $maxTiles');
    }

    log('Reading the style: $styleUrl');
    final style = await _getJson(styleUrl) as Map<String, Object?>;
    final sources = style['sources'] as Map<String, Object?>;
    final source = sources[sourceId] as Map<String, Object?>?;
    final tileJsonUrl = source?['url'] as String?;
    if (tileJsonUrl == null) {
      throw WorldMapBuildException('the style has no "$sourceId" source URL');
    }
    final tileJson = await _getJson(tileJsonUrl) as Map<String, Object?>;
    final template = (tileJson['tiles'] as List<Object?>).first as String;
    log('Tiles: $template (${tiles.length} tiles, zoom 0-$maxZoom, '
        '$parallel at a time)');

    final data = <({int z, int x, int y}), Uint8List>{};
    var bytes = 0;
    var next = 0;
    var done = 0;
    var stopped = false;

    Future<void> worker() async {
      try {
        while (!stopped && next < tiles.length) {
          final t = tiles[next++];
          final url = template
              .replaceAll('{z}', '${t.z}')
              .replaceAll('{x}', '${t.x}')
              .replaceAll('{y}', '${t.y}');
          final body = await _getTile(url);
          done++;
          if (body == null) continue; // no tile there (e.g. empty ocean)
          final stored = _gzipped(body);
          bytes += stored.length;
          if (bytes > maxBytes) {
            throw WorldMapBuildException(
                'over the size limit of ${maxBytes ~/ (1024 * 1024)} MB '
                'after $done tiles');
          }
          data[t] = stored;
          if (done % 100 == 0) {
            log('  $done / ${tiles.length} tiles, '
                '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB');
          }
        }
      } catch (_) {
        // One failure stops every worker: no more requests are sent.
        stopped = true;
        rethrow;
      }
    }

    await Future.wait([for (var i = 0; i < parallel; i++) worker()]);

    await _writeMbTiles(mbtilesPath, data, tileJson);
    await File(stylePath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(offlineStyle(style, sourceId)));

    final fileBytes = await File(mbtilesPath).length();
    log('Done: ${data.length} tiles, '
        '${(fileBytes / (1024 * 1024)).toStringAsFixed(1)} MB file');
    return WorldMapReport(
      tilesRequested: tiles.length,
      tilesStored: data.length,
      tileBytes: bytes,
      fileBytes: fileBytes,
    );
  }

  /// The style, cut down to what works with no network at all:
  /// * only the [sourceId] source (the app serves it from the bundled
  ///   file); raster sources such as shaded relief are dropped, with the
  ///   layers that draw them;
  /// * no `sprite` (icons) and no `glyphs` (map fonts): both would need
  ///   the network. Labels then use the phone's own fonts, and the few
  ///   icons are left out, which at zoom 0-5 is hardly noticeable.
  static Map<String, Object?> offlineStyle(
      Map<String, Object?> style, String sourceId) {
    final sources = style['sources'] as Map<String, Object?>;
    final layers = (style['layers'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .where((l) => l['source'] == null || l['source'] == sourceId)
        .toList();
    return {
      for (final e in style.entries)
        if (e.key != 'sprite' && e.key != 'glyphs') e.key: e.value,
      'name': '${style['name'] ?? 'Map'} (QuestMark offline)',
      'sources': {sourceId: sources[sourceId]},
      'layers': layers,
    };
  }

  static Uint8List _gzipped(Uint8List bytes) =>
      bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b
          ? bytes
          : Uint8List.fromList(gzip.encode(bytes));

  Future<Object?> _getJson(String url) async {
    final body = await _get(url);
    if (body == null) throw WorldMapBuildException('not found: $url');
    return jsonDecode(utf8.decode(body));
  }

  Future<Uint8List?> _getTile(String url) => _get(url);

  /// GET with retries. `null` for 204/404 (no tile there).
  Future<Uint8List?> _get(String url) async {
    Object? lastError;
    for (var attempt = 0; attempt <= retries; attempt++) {
      if (attempt > 0) await Future<void>.delayed(retryDelay * attempt);
      try {
        final response = await client.get(Uri.parse(url), headers: _headers);
        if (response.statusCode == 200) {
          return response.bodyBytes.isEmpty ? null : response.bodyBytes;
        }
        if (response.statusCode == 204 || response.statusCode == 404) {
          return null;
        }
        lastError = 'HTTP ${response.statusCode}';
        // Asked to slow down, or a server error: worth retrying. Any other
        // client error won't get better.
        if (response.statusCode != 429 && response.statusCode < 500) break;
      } on http.ClientException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      }
    }
    throw WorldMapBuildException('failed to fetch $url: $lastError');
  }

  Future<void> _writeMbTiles(
    String path,
    Map<({int z, int x, int y}), Uint8List> tiles,
    Map<String, Object?> tileJson,
  ) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
    await file.parent.create(recursive: true);
    final db = await databaseFactory.openDatabase(path);
    try {
      await db.execute('CREATE TABLE metadata (name TEXT, value TEXT)');
      await db.execute('CREATE TABLE tiles (zoom_level INTEGER, '
          'tile_column INTEGER, tile_row INTEGER, tile_data BLOB)');
      await db.execute('CREATE UNIQUE INDEX tile_index '
          'ON tiles (zoom_level, tile_column, tile_row)');
      final metadata = <String, String>{
        'name': 'QuestMark world map',
        'format': 'pbf',
        'type': 'baselayer',
        'minzoom': '0',
        'maxzoom': '$maxZoom',
        'bounds': '-180,-85.05113,180,85.05113',
        'attribution': (tileJson['attribution'] as String?) ??
            '© OpenMapTiles © OpenStreetMap contributors',
        'json': jsonEncode({'vector_layers': tileJson['vector_layers'] ?? []}),
        'source': styleUrl,
        'version': (tileJson['version'] ?? '').toString(),
        'generated': DateTime.now().toUtc().toIso8601String(),
      };
      final batch = db.batch();
      metadata.forEach((k, v) => batch.insert('metadata', {'name': k, 'value': v}));
      tiles.forEach((t, data) => batch.insert('tiles', {
            'zoom_level': t.z,
            'tile_column': t.x,
            'tile_row': tmsRow(t.z, t.y),
            'tile_data': data,
          }));
      await batch.commit(noResult: true);
    } finally {
      await db.close();
    }
  }
}

class WorldMapReport {
  const WorldMapReport({
    required this.tilesRequested,
    required this.tilesStored,
    required this.tileBytes,
    required this.fileBytes,
  });

  final int tilesRequested;
  final int tilesStored;
  final int tileBytes;
  final int fileBytes;
}

class WorldMapBuildException implements Exception {
  WorldMapBuildException(this.message);
  final String message;
  @override
  String toString() => 'WorldMapBuildException: $message';
}
