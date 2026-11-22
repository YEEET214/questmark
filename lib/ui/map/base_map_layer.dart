import 'package:flutter/material.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;

import 'map_config.dart';

/// Loads a map style (style.json plus the sources, sprites and fonts it
/// references).
typedef StyleLoader = Future<vt.Style> Function();

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

/// The base map (streets, land, water, labels) drawn from OpenFreeMap
/// vector tiles. It goes first in `FlutterMap.children`, under the quest
/// markers.
///
/// While the style loads, nothing is drawn: the quest markers still show
/// on the plain background. If loading fails (e.g. no network on first
/// launch), a banner with "Retry" is shown. The bundled offline world map
/// (Phase 8a) will remove that first-launch gap.
class OpenFreeMapLayer extends StatefulWidget {
  const OpenFreeMapLayer({super.key, this.loadStyle = loadOpenFreeMapStyle});

  /// Injectable so tests never touch the network.
  final StyleLoader loadStyle;

  @override
  State<OpenFreeMapLayer> createState() => _OpenFreeMapLayerState();
}

class _OpenFreeMapLayerState extends State<OpenFreeMapLayer> {
  vt.Style? _style;
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
      final style = await widget.loadStyle();
      if (!mounted) {
        style.dispose();
        return;
      }
      setState(() => _style = style);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    // Releases the style's HTTP clients, sprite images and glyphs.
    _style?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    if (style != null) {
      return vt.VectorTileLayer(
        theme: style.theme,
        tileProviders: style.providers,
        rasterSources: style.rasterSources,
        sprites: style.sprites,
        glyphs: style.glyphs,
        diskCacheMaximumSizeInBytes: MapConfig.diskCacheBytes,
        diskCacheTtl: MapConfig.diskCacheTtl,
      );
    }
    if (_error != null && !_loading) {
      return MapLoadErrorBanner(onRetry: _load);
    }
    return const SizedBox.shrink();
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
