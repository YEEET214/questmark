import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;

import '../../data/mbtiles_archive.dart';

// Together with base_map_layer.dart, the only place that uses the vector
// tile package (CLAUDE.md): if the package changes, only these two files
// change.

/// Serves tiles from the bundled world map only (PLAN.md D7). Used when
/// the map has to run with no network at all: zoom 0-5 from the file, and
/// closer zooms drawn by enlarging ("overzooming") the zoom-5 tiles.
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

/// The normal online source, with the world map in front of it for the low
/// zooms (PLAN.md D7):
/// * zoom 0-5 come from the bundled file: no network at all, so the whole
///   world always shows, even offline;
/// * closer zooms come from the network provider (OpenFreeMap, with its
///   disk cache), exactly as before. If the file lacks a low-zoom tile,
///   the network is asked instead.
class WorldFirstTileProvider extends vt.VectorTileProvider {
  WorldFirstTileProvider(this._network, MbTilesArchive world)
      : _world = WorldMapTileProvider(world);

  final vt.VectorTileProvider _network;
  final WorldMapTileProvider _world;

  @override
  int get minimumZoom => _network.minimumZoom;

  @override
  int get maximumZoom => _network.maximumZoom;

  /// The same data as the network source, so it shares its cache entries.
  @override
  String get cacheKey => _network.cacheKey;

  @override
  bool get cacheBytesToDisk => _network.cacheBytesToDisk;

  @override
  Future<vt.TileResponse> load(vt.TileKey tile,
      {vt.CancellationToken? cancellation}) async {
    if (tile.z <= _world.maximumZoom) {
      final local = await _world.load(tile, cancellation: cancellation);
      if (local is vt.TileResponseData || local is vt.TileResponseCancelled) {
        return local;
      }
    }
    return _network.load(tile, cancellation: cancellation);
  }

  /// The network provider belongs to the style, which disposes it; the
  /// archive is shared app-wide.
  @override
  void dispose() {}
}

/// [providers] with [sourceId]'s provider put behind the world map.
vt.TileProviders withWorldMap(
  vt.TileProviders providers,
  MbTilesArchive world, {
  String sourceId = 'openmaptiles',
}) {
  final network = providers[sourceId];
  if (network == null) return providers;
  return vt.TileProviders(
    {
      ...providers.providers,
      sourceId: WorldFirstTileProvider(network, world),
    },
    promoteIds: providers.promoteIds,
  );
}
