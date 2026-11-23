import 'package:flutter/material.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

import '../../data/mbtiles_archive.dart';
import '../../data/world_map_installer.dart';
import 'map_config.dart';
import 'world_map_tiles.dart';

/// Loads a map style (style.json plus the sources, sprites and fonts it
/// references).
typedef StyleLoader = Future<vt.Style> Function();

/// Loads the bundled offline style, drawing from [world].
typedef OfflineStyleLoader = Future<vt.Style> Function(MbTilesArchive world);

/// Opens the bundled world map, or returns `null` if there is none.
typedef WorldMapLoader = Future<MbTilesArchive?> Function();

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
/// (`tool/build_world_map.dart` writes it): OpenFreeMap's look, but with
/// every tile from the world map file and nothing fetched from the
/// network (no icons, and the phone's own fonts for labels).
Future<vt.Style> loadOfflineWorldStyle(MbTilesArchive world) =>
    vt.StyleReader(
      uri: 'asset://${MapConfig.offlineStyleAsset}',
      cache: false,
      resolveProvider: (id) async =>
          id == MapConfig.tileSourceId ? WorldMapTileProvider(world) : null,
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

/// What the base map ended up drawing from.
class BaseMap {
  const BaseMap(this.style, this.providers, {required this.offline});

  final vt.Style style;

  /// The tile providers to draw with: the style's own, with the world map
  /// in front for zoom 0-5 when it's available.
  final vt.TileProviders providers;

  /// True when the online style couldn't be loaded and the bundled
  /// offline style is shown instead.
  final bool offline;
}

/// Loads the base map in this order (PLAN.md D7):
/// 1. the online OpenFreeMap style (from its disk cache when offline),
///    with the bundled world map serving zoom 0-5;
/// 2. if that fails (e.g. the very first launch without a connection):
///    the bundled offline style on the world map alone;
/// 3. if there's no world map either, the error from step 1 is thrown.
Future<BaseMap> loadBaseMap({
  required StyleLoader loadStyle,
  required OfflineStyleLoader loadOfflineStyle,
  required WorldMapLoader loadWorldMap,
}) async {
  MbTilesArchive? world;
  try {
    world = await loadWorldMap();
  } catch (e) {
    debugPrint('World map unavailable: $e');
  }
  try {
    final style = await loadStyle();
    return BaseMap(
      style,
      world == null ? style.providers : withWorldMap(style.providers, world),
      offline: false,
    );
  } catch (_) {
    if (world == null) rethrow;
    final style = await loadOfflineStyle(world);
    return BaseMap(style, style.providers, offline: true);
  }
}

/// The base map (streets, land, water, labels) drawn from OpenFreeMap
/// vector tiles. It goes first in `FlutterMap.children`, under the quest
/// markers.
///
/// Zoom 0-5 always come from the world map bundled with the app, so the
/// whole world shows even with no connection. Closer zooms come from
/// OpenFreeMap (and its disk cache). If the online style can't be loaded
/// at all, the bundled offline style is shown with a small "offline"
/// banner and Retry. Only if that fails too is the error banner shown.
class OpenFreeMapLayer extends StatefulWidget {
  const OpenFreeMapLayer({
    super.key,
    this.loadStyle = loadOpenFreeMapStyle,
    this.loadOfflineStyle = loadOfflineWorldStyle,
    this.loadWorldMap = openBundledWorldMap,
  });

  /// Injectable so tests never touch the network or the assets.
  final StyleLoader loadStyle;
  final OfflineStyleLoader loadOfflineStyle;
  final WorldMapLoader loadWorldMap;

  @override
  State<OpenFreeMapLayer> createState() => _OpenFreeMapLayerState();
}

class _OpenFreeMapLayerState extends State<OpenFreeMapLayer> {
  BaseMap? _map;
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
      );
      if (!mounted) {
        map.style.dispose();
        return;
      }
      final old = _map;
      setState(() => _map = map);
      old?.style.dispose();
    } catch (e) {
      // Keep showing what's there (e.g. the offline map) if a retry fails.
      if (mounted && _map == null) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    if (map != null) {
      final layer = vt.VectorTileLayer(
        theme: map.style.theme,
        tileProviders: map.providers,
        rasterSources: map.style.rasterSources,
        sprites: map.style.sprites,
        glyphs: map.style.glyphs,
        diskCacheMaximumSizeInBytes: MapConfig.diskCacheBytes,
        diskCacheTtl: MapConfig.diskCacheTtl,
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
