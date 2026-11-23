import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;

import '../../data/mbtiles_archive.dart';
import '../../data/offline_region_store.dart';
import '../../data/tile_cache.dart';
import '../../models/region_plan.dart';
import '../../services/mvt_overzoom.dart';

// Together with base_map_layer.dart, the only place that uses the vector
// tile package (CLAUDE.md): if the package changes, only these two files
// change.

/// Serves tiles from the bundled world map only (PLAN.md D7). Zoom 0-4
/// from the file, and closer zooms drawn by enlarging ("overzooming") the
/// zoom-4 tiles.
class WorldMapTileProvider extends vt.VectorTileProvider {
  WorldMapTileProvider(this._world);

  final MbTilesArchive _world;

  @override
  int get minimumZoom => _world.minZoom;

  @override
  int get maximumZoom => _world.maxZoom;

  @override
  String get cacheKey => 'questmark-world:${_world.version}';

  /// The file is already on the phone; a disk-cache copy would only
  /// duplicate it.
  @override
  bool get cacheBytesToDisk => false;

  @override
  Future<vt.TileResponse> load(vt.TileKey tile,
      {vt.CancellationToken? cancellation}) async {
    if (cancellation?.isCancelled ?? false) {
      return const vt.TileResponseCancelled();
    }
    try {
      final bytes = await _world.tile(tile.z, tile.x, tile.y);
      return bytes == null
          ? const vt.TileResponseNotFound()
          : vt.TileResponseData(bytes);
    } catch (e) {
      return vt.TileResponseError(e);
    }
  }

  /// The archive is shared app-wide and stays open.
  @override
  void dispose() {}
}

/// What's on the phone, for tiles the network can't give: the bundled
/// world map, the downloaded regions and the browse cache (PLAN.md D27).
class LocalTiles {
  const LocalTiles({this.world, this.regions, this.cache});

  final MbTilesArchive? world;
  final RegionTileSource? regions;
  final NetworkTileCache? cache;

  bool get isEmpty => world == null && regions == null && cache == null;

  /// The world map's tile (zoom 0-4), or null.
  Future<vt.TileResponse?> worldTile(vt.TileKey tile) async {
    final w = world;
    if (w == null || tile.z > w.maxZoom) return null;
    final bytes = await quietly(() => w.tile(tile.z, tile.x, tile.y));
    return bytes == null ? null : vt.TileResponseData(bytes);
  }

  /// A downloaded region's tile (zoom 5-14), or null if none has it.
  Future<vt.TileResponse?> regionTile(vt.TileKey tile) async {
    final r = regions;
    if (r == null || tile.z < RegionPlan.minZoom) return null;
    final bytes = await quietly(() => r.tile(tile.z, tile.x, tile.y));
    return bytes == null ? null : response(bytes);
  }

  /// The cached tile, fresh or not, or null.
  Future<CachedTile?> cached(vt.TileKey tile) async {
    final c = cache;
    if (c == null) return null;
    return quietly(() => c.get(tile.z, tile.x, tile.y));
  }

  /// A stand-in for a tile that isn't on the phone: the nearest less
  /// detailed tile that is (a region's, a cached one, or the world map's),
  /// cut out and enlarged (overzoomed). Water stays blue, and coasts and
  /// borders keep their rough shape. Null if there's nothing to make it
  /// from. Never cached: it's only for while the real tile can't be had.
  Future<vt.TileResponse?> standIn(vt.TileKey tile) async {
    final worldMax = world?.maxZoom ?? -1;
    for (var z = tile.z - 1; z > worldMax && z >= 0; z--) {
      final d = tile.z - z;
      final ax = tile.x >> d, ay = tile.y >> d;
      Uint8List? bytes;
      final r = regions;
      if (r != null && z >= RegionPlan.minZoom) {
        bytes = await quietly(() => r.tile(z, ax, ay));
      }
      final c = cache;
      if (bytes == null && c != null) {
        bytes = (await quietly(() => c.get(z, ax, ay)))?.bytes;
      }
      if (bytes != null) return _enlarged(bytes, tile, z);
    }
    final w = world;
    if (w == null) return null;
    final z = tile.z < worldMax ? tile.z : worldMax;
    final d = tile.z - z;
    final bytes = await quietly(() => w.tile(z, tile.x >> d, tile.y >> d));
    return bytes == null ? null : _enlarged(bytes, tile, z);
  }

  Future<vt.TileResponse> _enlarged(
      Uint8List parent, vt.TileKey tile, int z) async {
    // Empty: nothing in the parent, so nothing in this part of it either.
    if (parent.isEmpty) return const vt.TileResponseNotFound();
    final d = tile.z - z;
    if (d == 0) return vt.TileResponseData(parent);
    final dx = tile.x - ((tile.x >> d) << d);
    final dy = tile.y - ((tile.y >> d) << d);
    try {
      // Reading a big zoom-4 tile takes a moment: not on the UI thread.
      final out =
          await Isolate.run(() => overzoomMvt(parent, dz: d, dx: dx, dy: dy));
      return response(out);
    } catch (e) {
      debugPrint('Stand-in tile ${tile.z}/${tile.x}/${tile.y} failed: $e');
      return const vt.TileResponseNotFound();
    }
  }

  /// Empty bytes mean "no tile here".
  static vt.TileResponse response(Uint8List bytes) => bytes.isEmpty
      ? const vt.TileResponseNotFound()
      : vt.TileResponseData(bytes);

  /// Local storage problems never break the map: the tile is just missing.
  static Future<T?> quietly<T>(Future<T?> Function() read) async {
    try {
      return await read();
    } catch (e) {
      debugPrint('Local tile read failed: $e');
      return null;
    }
  }
}

/// The source for the bundled offline style (no connection, and no map
/// style cached yet): everything from the phone. Zoom 0-4 from the world
/// map, zoom 5-14 from downloaded regions and the browse cache, and
/// elsewhere the enlarged stand-in tiles (D27).
class OfflineTileProvider extends vt.VectorTileProvider {
  OfflineTileProvider(this._local, {required this._version});

  final LocalTiles _local;
  final String _version;

  @override
  int get minimumZoom => 0;

  @override
  int get maximumZoom => RegionPlan.maxZoom;

  @override
  String get cacheKey => 'questmark-offline:$_version';

  /// Everything is already on the phone.
  @override
  bool get cacheBytesToDisk => false;

  @override
  Future<vt.TileResponse> load(vt.TileKey tile,
      {vt.CancellationToken? cancellation}) async {
    if (cancellation?.isCancelled ?? false) {
      return const vt.TileResponseCancelled();
    }
    final world = await _local.worldTile(tile);
    if (world != null) return world;
    final region = await _local.regionTile(tile);
    if (region != null) return region;
    final cached = await _local.cached(tile);
    if (cached != null) return LocalTiles.response(cached.bytes);
    return await _local.standIn(tile) ?? const vt.TileResponseNotFound();
  }

  @override
  void dispose() {}
}

/// The normal online source, with what's on the phone around it
/// (PLAN.md D7, D26, D27). For each tile, in this order:
/// 1. zoom 0-4: the bundled world map (no network at all);
/// 2. zoom 5-14: a downloaded region;
/// 3. the browse cache, if the tile is fresh (under 30 days old);
/// 4. OpenFreeMap (the network provider); what arrives is cached;
/// 5. if the network fails: the cached copy even if old, else a stand-in
///    made by enlarging the nearest less detailed tile on the phone.
///
/// Stand-ins are never cached. When the network answers again after one
/// was shown, [onRecovered] is called, so the map reloads and swaps them
/// for the real tiles.
///
/// The package's own disk cache is not used for these tiles
/// ([cacheBytesToDisk] is false): it would store stand-ins as real tiles
/// for 30 days, and copy downloaded regions into itself.
class LocalFirstTileProvider extends vt.VectorTileProvider {
  LocalFirstTileProvider(
    this._network, {
    MbTilesArchive? world,
    RegionTileSource? regions,
    NetworkTileCache? cache,
    this.generation = 0,
    this.onRecovered,
  }) : _local = LocalTiles(world: world, regions: regions, cache: cache);

  final vt.VectorTileProvider _network;
  final LocalTiles _local;

  /// Bumped each time the map reloads after the network came back, so the
  /// in-memory tiles (kept by [cacheKey]) are fetched again, without the
  /// stand-ins.
  final int generation;
  final VoidCallback? onRecovered;

  bool _servedStandIn = false;

  /// Whether a stand-in was shown since the network last answered.
  @visibleForTesting
  bool get servedStandIn => _servedStandIn;

  @override
  int get minimumZoom => _network.minimumZoom;

  @override
  int get maximumZoom => _network.maximumZoom;

  @override
  String get cacheKey => '${_network.cacheKey}#questmark$generation';

  @override
  bool get cacheBytesToDisk => false;

  @override
  Future<vt.TileResponse> load(vt.TileKey tile,
      {vt.CancellationToken? cancellation}) async {
    if (cancellation?.isCancelled ?? false) {
      return const vt.TileResponseCancelled();
    }
    final world = await _local.worldTile(tile);
    if (world != null) return world;
    final region = await _local.regionTile(tile);
    if (region != null) return region;

    final cached = await _local.cached(tile);
    if (cached != null && cached.fresh) {
      return LocalTiles.response(cached.bytes);
    }

    final response = await _network.load(tile, cancellation: cancellation);
    final cache = _local.cache;
    switch (response) {
      case vt.TileResponseData(:final bytes):
        _networkAnswered();
        await LocalTiles.quietly(
            () async => cache?.put(tile.z, tile.x, tile.y, bytes));
        return response;
      case vt.TileResponseNotFound():
        _networkAnswered();
        await LocalTiles.quietly(
            () async => cache?.put(tile.z, tile.x, tile.y, Uint8List(0)));
        return response;
      case vt.TileResponseCancelled():
        return response;
      case vt.TileResponseError():
        if (cached != null) return LocalTiles.response(cached.bytes);
        final standIn = await _local.standIn(tile);
        if (standIn == null) return response;
        _servedStandIn = true;
        return standIn;
    }
  }

  void _networkAnswered() {
    if (!_servedStandIn) return;
    _servedStandIn = false;
    onRecovered?.call();
  }

  /// The network provider belongs to the style, which disposes it; the
  /// world map, regions and cache are shared app-wide.
  @override
  void dispose() {}
}

/// [providers] with [sourceId]'s provider wrapped in a
/// [LocalFirstTileProvider]. Unchanged if there's nothing on the phone.
vt.TileProviders withLocalMaps(
  vt.TileProviders providers, {
  MbTilesArchive? world,
  RegionTileSource? regions,
  NetworkTileCache? cache,
  int generation = 0,
  VoidCallback? onRecovered,
  String sourceId = 'openmaptiles',
}) {
  final network = providers[sourceId];
  if (network == null || (world == null && regions == null && cache == null)) {
    return providers;
  }
  return vt.TileProviders(
    {
      ...providers.providers,
      sourceId: LocalFirstTileProvider(
        network,
        world: world,
        regions: regions,
        cache: cache,
        generation: generation,
        onRecovered: onRecovered,
      ),
    },
    promoteIds: providers.promoteIds,
  );
}
