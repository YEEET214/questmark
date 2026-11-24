import 'package:flutter/material.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

import '../../data/mbtiles_archive.dart';
import '../../data/offline_region_store.dart';
import '../../data/tile_cache.dart';
import '../../data/world_map_installer.dart';
import 'map_config.dart';
import 'world_map_tiles.dart';

/// Loads a map style (style.json plus the sources, sprites and fonts it
/// references).
typedef StyleLoader = Future<vt.Style> Function();

/// Loads the bundled offline style, drawing from what's on the phone
/// ([local] always has a world map here).
typedef OfflineStyleLoader = Future<vt.Style> Function(LocalTiles local);

/// Opens the bundled world map, or returns `null` if there is none.
typedef WorldMapLoader = Future<MbTilesArchive?> Function();

/// Opens the browse cache, or returns `null` if it can't be opened.
typedef TileCacheLoader = Future<NetworkTileCache?> Function();

/// The base map widget, provided app-wide (`Provider<MapBaseLayer>`), so a
/// page pushed on top of the shell, like the location picker, draws the
/// same map. Tests provide an empty one, so no tiles are loaded.
class MapBaseLayer {
  const MapBaseLayer(this.layer);
  final Widget layer;
}

/// Loads the OpenFreeMap style with our User-Agent.
///
/// The User-Agent header is sent with the style request and passed on by
/// the package to every tile request it makes. The style bundle is cached
/// on disk, so after the first successful load the map style is available
/// offline, and refreshed in the background at most twice a day.
Future<vt.Style> loadOpenFreeMapStyle() => vt.StyleReader(
      uri: MapConfig.styleUrl,
      headers: MapConfig.httpHeaders,
    ).read();

/// The offline copy of the style bundled with the app
/// (`tool/build_world_map.dart` writes it): OpenFreeMap's look, with every
/// tile from the phone and nothing fetched from the network (no icons,
/// and the phone's own fonts for labels). Downloaded regions and cached
/// tiles are drawn in detail; elsewhere the world map is enlarged (D27).
Future<vt.Style> loadOfflineWorldStyle(LocalTiles local) => vt.StyleReader(
      uri: 'asset://${MapConfig.offlineStyleAsset}',
      cache: false,
      resolveProvider: (id) async => id == MapConfig.tileSourceId
          ? OfflineTileProvider(local, version: local.world!.version)
          : null,
    ).read();

Future<MbTilesArchive?>? _bundledWorld;

/// The bundled world map (PLAN.md D7), copied out of the app's assets on
/// first launch and opened once for the whole app. `null` if this build
/// has no world map or it can't be opened; the map then works as before.
Future<MbTilesArchive?> openBundledWorldMap() {
  return _bundledWorld ??= () async {
    try {
      final path =
          await WorldMapInstaller(directory: getDatabasesPath).install();
      return path == null ? null : await MbTilesArchive.open(path);
    } catch (e) {
      debugPrint('World map unavailable: $e');
      return null;
    }
  }();
}

Future<NetworkTileCache?>? _tileCache;

/// The browse cache (PLAN.md D27), opened once for the whole app. `null`
/// if it can't be opened; the map then simply fetches what it shows.
Future<NetworkTileCache?> openAppTileCache() {
  return _tileCache ??= () async {
    try {
      return await SqfliteTileCache.open(
        maxBytes: MapConfig.tileCacheBytes,
        ttl: MapConfig.diskCacheTtl,
      );
    } catch (e) {
      debugPrint('Tile cache unavailable: $e');
      return null;
    }
  }();
}

Future<NetworkTileCache?> noTileCache() async => null;

/// What the base map ended up drawing from.
class BaseMap {
  const BaseMap(this.style, {required this.offline, required this.local});

  final vt.Style style;

  /// True when the online style couldn't be loaded and the bundled
  /// offline style is shown instead.
  final bool offline;

  /// What's on the phone: the world map, regions and browse cache.
  final LocalTiles local;

  /// The tile providers to draw with. Online: the style's own, with the
  /// world map (zoom 0-4), the regions (zoom 5-14) and the browse cache in
  /// front, and stand-in tiles while offline (D27). [generation] and
  /// [onRecovered]: see [LocalFirstTileProvider].
  vt.TileProviders providers({int generation = 0, VoidCallback? onRecovered}) =>
      offline
          ? style.providers
          : withLocalMaps(
              style.providers,
              world: local.world,
              regions: local.regions,
              cache: local.cache,
              generation: generation,
              onRecovered: onRecovered,
            );
}

/// Loads the base map in this order (PLAN.md D7):
/// 1. the online OpenFreeMap style (from its disk cache when offline),
///    with what's on the phone in front (see [BaseMap.providers]);
/// 2. if that fails (e.g. the very first launch without a connection):
///    the bundled offline style, drawn from the phone alone;
/// 3. if there's no world map either, the error from step 1 is thrown.
Future<BaseMap> loadBaseMap({
  required StyleLoader loadStyle,
  required OfflineStyleLoader loadOfflineStyle,
  required WorldMapLoader loadWorldMap,
  TileCacheLoader loadTileCache = noTileCache,
  RegionTileSource? regions,
}) async {
  Future<T?> quietly<T>(Future<T?> Function() open, String what) async {
    try {
      return await open();
    } catch (e) {
      debugPrint('$what unavailable: $e');
      return null;
    }
  }

  final world = await quietly(loadWorldMap, 'World map');
  final cache = await quietly(loadTileCache, 'Tile cache');
  final local = LocalTiles(world: world, regions: regions, cache: cache);
  try {
    final style = await loadStyle();
    return BaseMap(style, offline: false, local: local);
  } catch (_) {
    if (world == null) rethrow;
    final style = await loadOfflineStyle(local);
    return BaseMap(style, offline: true, local: local);
  }
}

/// The base map (streets, land, water, labels) drawn from OpenFreeMap
/// vector tiles. It goes first in `FlutterMap.children`, under the quest
/// markers.
///
/// Zoom 0-4 always come from the world map bundled with the app, so the
/// whole world shows even with no connection. Closer zooms come from the
/// downloaded regions ([regionTiles]) where there are any, then the browse
/// cache, then OpenFreeMap. Offline, tiles that aren't on the phone are
/// drawn by enlarging the nearest less detailed one, so the map never goes
/// blank (D27); once the network answers again, the map reloads with the
/// real tiles. If the online style can't be loaded at all, the bundled
/// offline style is shown with a small "offline" banner and Retry. Only if
/// that fails too is the error banner shown.
class OpenFreeMapLayer extends StatefulWidget {
  const OpenFreeMapLayer({
    super.key,
    this.loadStyle = loadOpenFreeMapStyle,
    this.loadOfflineStyle = loadOfflineWorldStyle,
    this.loadWorldMap = openBundledWorldMap,
    this.loadTileCache = openAppTileCache,
    this.regionTiles,
  });

  /// Injectable so tests never touch the network or the assets.
  final StyleLoader loadStyle;
  final OfflineStyleLoader loadOfflineStyle;
  final WorldMapLoader loadWorldMap;
  final TileCacheLoader loadTileCache;

  /// The downloaded regions (PLAN.md D26), if any.
  final RegionTileSource? regionTiles;

  @override
  State<OpenFreeMapLayer> createState() => _OpenFreeMapLayerState();
}

class _OpenFreeMapLayerState extends State<OpenFreeMapLayer> {
  BaseMap? _map;
  vt.TileProviders? _providers;
  int _generation = 0;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final map = await loadBaseMap(
        loadStyle: widget.loadStyle,
        loadOfflineStyle: widget.loadOfflineStyle,
        loadWorldMap: widget.loadWorldMap,
        loadTileCache: widget.loadTileCache,
        regions: widget.regionTiles,
      );
      if (!mounted) {
        map.style.dispose();
        return;
      }
      final old = _map;
      setState(() {
        _map = map;
        _providers = _providersFor(map);
      });
      old?.style.dispose();
    } catch (e) {
      // Keep showing what's there (e.g. the offline map) if a retry fails.
      if (mounted && _map == null) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Built once per map and generation: a new TileProviders object makes
  // the layer reload every tile.
  vt.TileProviders _providersFor(BaseMap map) =>
      map.providers(generation: _generation, onRecovered: _onRecovered);

  /// The network is back after stand-in tiles were shown: reload, so the
  /// real tiles replace them.
  void _onRecovered() {
    if (!mounted) return;
    final map = _map;
    if (map == null) return;
    setState(() {
      _generation++;
      _providers = _providersFor(map);
    });
  }

  @override
  void dispose() {
    // Releases the style's HTTP clients, sprite images and glyphs.
    _map?.style.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final map = _map;
    final providers = _providers;
    if (map != null && providers != null) {
      final layer = vt.VectorTileLayer(
        theme: map.style.theme,
        tileProviders: providers,
        rasterSources: map.style.rasterSources,
        sprites: map.style.sprites,
        glyphs: map.style.glyphs,
        // Only the shaded relief still goes through the package's disk
        // cache; the vector tiles have the app's own (D27).
        diskCacheMaximumSizeInBytes: MapConfig.diskCacheBytes,
        diskCacheTtl: MapConfig.diskCacheTtl,
        // Map speed (Phase 9b), with no change to the look: more decoded
        // tiles kept in memory, so zooming back and forth re-reads less,
        // and one more background worker decoding tiles.
        memoryCacheMaxBytes: MapConfig.memoryCacheBytes,
        concurrency: MapConfig.decodeWorkers,
      );
      if (!map.offline) return layer;
      return Stack(
        fit: StackFit.expand,
        children: [
          layer,
          MapOfflineBanner(onRetry: _loading ? null : _load),
        ],
      );
    }
    if (_error != null && !_loading) {
      return MapLoadErrorBanner(onRetry: _load);
    }
    return const SizedBox.shrink();
  }
}

/// Shown at the bottom of the map while only the bundled world map is
/// available: the user knows why there's no detail, and can retry.
class MapOfflineBanner extends StatelessWidget {
  const MapOfflineBanner({super.key, required this.onRetry});

  /// Null while a retry is running.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        // Between the badge (bottom-left) and the credits (bottom-right).
        padding: const EdgeInsets.fromLTRB(64, 0, 64, 12),
        child: Material(
          key: const Key('mapOfflineBanner'),
          elevation: 2,
          borderRadius: BorderRadius.circular(20),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 16),
                const SizedBox(width: 8),
                Flexible(
                  child: Text('Offline world map',
                      style: theme.textTheme.bodySmall),
                ),
                TextButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown over the map when the base map couldn't be loaded.
class MapLoadErrorBanner extends StatelessWidget {
  const MapLoadErrorBanner({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            elevation: 3,
            borderRadius: BorderRadius.circular(12),
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off,
                      color: theme.colorScheme.onErrorContainer),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      "Couldn't load the map. Check your connection.",
                      style: TextStyle(
                          color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                  TextButton(onPressed: onRetry, child: const Text('Retry')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
