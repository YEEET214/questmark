import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../app_info.dart';
import '../models/region_plan.dart';

/// A downloaded tile.
class FetchedTile {
  const FetchedTile(this.data, {required this.downloaded});

  /// The bytes to store: gzipped vector tile, or empty for "no tile here".
  final Uint8List data;

  /// What the download cost (for OpenFreeMap's 50 MB limit).
  final int downloaded;
}

enum TileFetchFailure {
  /// No connection, or no answer in time. Worth retrying.
  connection,

  /// HTTP 429 or 5xx: the server is busy. Worth retrying, after a pause.
  busy,

  /// Any other answer. Retrying won't help.
  server,
}

class TileFetchException implements Exception {
  const TileFetchException(this.failure, [this.detail]);
  final TileFetchFailure failure;
  final String? detail;

  bool get retryable => failure != TileFetchFailure.server;

  @override
  String toString() => 'TileFetchException($failure, $detail)';
}

/// Downloads single map tiles, for region downloads (PLAN.md D26). An
/// interface, so the downloader can be tested without a network.
abstract interface class TileFetcher {
  /// Throws [TileFetchException].
  Future<FetchedTile> fetch(TileId tile);
}

/// [TileFetcher] for OpenFreeMap. Finds the current tile URL from its
/// TileJSON (it changes with each weekly data release), then fetches
/// tiles with our User-Agent. Never uses tile.openstreetmap.org (D4).
///
/// Tiles are kept as they arrive, gzipped, so what's stored is what was
/// downloaded (gzipping it here if the server didn't).
class OpenFreeMapTileFetcher implements TileFetcher {
  OpenFreeMapTileFetcher({
    http.Client? client,
    this.tileJsonUrl = defaultTileJsonUrl,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ??
            // No automatic unzipping: the tile stays exactly as downloaded,
            // and its size is the real download size.
            IOClient(HttpClient()..autoUncompress = false);

  static const defaultTileJsonUrl = 'https://tiles.openfreemap.org/planet';

  final http.Client _client;
  final String tileJsonUrl;
  final Duration timeout;

  static const _headers = {
    'User-Agent': AppInfo.userAgent,
    'Accept-Encoding': 'gzip',
  };

  Future<String>? _template;

  @override
  Future<FetchedTile> fetch(TileId tile) async {
    final template = await (_template ??= _loadTemplate().catchError(
      (Object e) {
        _template = null; // try again next time
        throw e;
      },
    ));
    final url = template
        .replaceAll('{z}', '${tile.z}')
        .replaceAll('{x}', '${tile.x}')
        .replaceAll('{y}', '${tile.y}');
    final response = await _get(url);
    final body = response.bodyBytes;
    return FetchedTile(
      body.isEmpty || response.statusCode != 200 ? Uint8List(0) : gzipped(body),
      downloaded: body.length,
    );
  }

  Future<String> _loadTemplate() async {
    final response = await _get(tileJsonUrl);
    if (response.statusCode != 200) {
      throw TileFetchException(
          TileFetchFailure.server, 'TileJSON: HTTP ${response.statusCode}');
    }
    try {
      final json =
          jsonDecode(utf8.decode(ungzipped(response.bodyBytes))) as Map;
      final tiles = json['tiles'] as List;
      return tiles.first as String;
    } catch (e) {
      throw TileFetchException(TileFetchFailure.server, 'TileJSON: $e');
    }
  }

  /// GETs [url]; 200, 204 and 404 are normal answers (204/404: no tile
  /// there), anything else throws.
  Future<http.Response> _get(String url) async {
    final http.Response response;
    try {
      response =
          await _client.get(Uri.parse(url), headers: _headers).timeout(timeout);
    } on TimeoutException catch (e) {
      throw TileFetchException(TileFetchFailure.connection, '$e');
    } on SocketException catch (e) {
      throw TileFetchException(TileFetchFailure.connection, '$e');
    } on http.ClientException catch (e) {
      throw TileFetchException(TileFetchFailure.connection, '$e');
    }
    final code = response.statusCode;
    if (code == 200 || code == 204 || code == 404) return response;
    throw TileFetchException(
      code == 429 || code >= 500
          ? TileFetchFailure.busy
          : TileFetchFailure.server,
      'HTTP $code',
    );
  }

  static bool _isGzip(Uint8List b) =>
      b.length >= 2 && b[0] == 0x1f && b[1] == 0x8b;

  static Uint8List gzipped(Uint8List bytes) =>
      _isGzip(bytes) ? bytes : Uint8List.fromList(gzip.encode(bytes));

  static Uint8List ungzipped(Uint8List bytes) =>
      _isGzip(bytes) ? Uint8List.fromList(gzip.decode(bytes)) : bytes;
}
