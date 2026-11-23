import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;

import '../../data/mbtiles_archive.dart';
import '../../data/offline_region_store.dart';
import '../../models/region_plan.dart';

// Together with base_map_layer.dart, the only place that uses the vector
// tile package (CLAUDE.md): if the package changes, only these two files
// change.

/// Serves tiles from the bundled world map only (PLAN.md D7). Used when
/// the map has to run with no network at all: zoom 0-4 from the file, and
/// closer zooms drawn by enlarging ("overzooming") the zoom-4 tiles.
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

/// Downloaded regions alone, with the world map below them: the source for
/// the bundled offline style (no connection and no cached style). Zoom 0-4
/// come from the world map, zoom 5-14 from the downloaded regions; outside
/// them, those zooms are empty.
class OfflineTileProvider extends vt.VectorTileProvider {
  OfflineTileProvider(MbTilesArchive world, this._regions)
      : _world = WorldMapTileProvider(world);

  final WorldMapTileProvider _world;
  final RegionTileSource _regions;

  @override
  int get minimumZoom => _world.minimumZoom;

  @override
  int get maximumZoom => RegionPlan.maxZoom;

  @override
  String get cacheKey => 'questmark-offline:${_world.cacheKey}';

  /// Everything is already on the phone.
  @override
  bool get cacheBytesToDisk => false;

  @override
  Future<vt.TileResponse> load(vt.TileKey tile,
      {vt.CancellationToken? cancellation}) async {
    if (tile.z <= _world.maximumZoom) {
      return _world.load(tile, cancellation: cancellation);
    }
    return await _regionTile(_regions, tile, cancellation) ??
        const vt.TileResponseNotFound();
  }

  @override
  void dispose() {}
}

/// The normal online source, with what's on the phone in front of it
/// (PLAN.md D7, D26):
/// * zoom 0-4 come from the bundled world map: no network at all, so the
///   whole world always shows, even offline;
/// * zoom 5-14 come from downloaded regions where there are any;
/// * everything else comes from the network provider (OpenFreeMap, with
///   its disk cache), exactly as before. A tile missing from the world map
///   is fetched instead.
class LocalFirstTileProvider extends vt.VectorTileProvider {
  LocalFirstTileProvider(
    this._network, {
    MbTilesArchive? world,
    this._regions,
  }) : _world = world == null ? null : WorldMapTileProvider(world);

  final vt.VectorTileProvider _network;
  final WorldMapTileProvider? _world;
  final RegionTileSource? _regions;

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
    final world = _world;
    final regions = _regions;
    if (world != null && tile.z <= world.maximumZoom) {
      final local = await world.load(tile, cancellation: cancellation);
      if (local is vt.TileResponseData || local is vt.TileResponseCancelled) {
        return local;
      }
    } else if (regions != null && tile.z >= RegionPlan.minZoom) {
      final local = await _regionTile(regions, tile, cancellation);
      if (local != null) return local;
    }
    return _network.load(tile, cancellation: cancellation);
  }

  /// The network provider belongs to the style, which disposes it; the
  /// world map and the regions are shared app-wide.
  @override
  void dispose() {}
}

/// [tile] from the downloaded regions, or null if none has it (or the
/// store can't be read: the caller then falls back to something else).
Future<vt.TileResponse?> _regionTile(RegionTileSource regions,
    vt.TileKey tile, vt.CancellationToken? cancellation) async {
  if (cancellation?.isCancelled ?? false) {
    return const vt.TileResponseCancelled();
  }
  try {
    final bytes = await regions.tile(tile.z, tile.x, tile.y);
    if (bytes == null) return null;
    // Empty: the region has it, but the server had no tile there.
    return bytes.isEmpty
        ? const vt.TileResponseNotFound()
        : vt.TileResponseData(bytes);
  } catch (_) {
    return null;
  }
}

/// [providers] with [sourceId]'s provider put behind the world map and
/// the downloaded regions. Unchanged if there's neither.
vt.TileProviders withLocalMaps(
  vt.TileProviders providers, {
  MbTilesArchive? world,
  RegionTileSource? regions,
  String sourceId = 'openmaptiles',
}) {
  final network = providers[sourceId];
  if (network == null || (world == null && regions == null)) return providers;
  return vt.TileProviders(
    {
      ...providers.providers,
      sourceId: LocalFirstTileProvider(network, world: world, regions: regions),
    },
    promoteIds: providers.promoteIds,
  );
}
