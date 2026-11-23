import 'package:latlong2/latlong.dart';

import '../../app_info.dart';

/// Everything about where the map comes from and how it behaves, in one
/// place. See PLAN.md D4/D5 for why these values were chosen.
abstract final class MapConfig {
  /// OpenFreeMap's "Liberty" style: OpenStreetMap data as vector tiles,
  /// with no API key. OSM's own tile server (tile.openstreetmap.org) must
  /// never be used, because its policy forbids offline use and prefetching
  /// (PLAN.md D4).
  static const styleUrl = 'https://tiles.openfreemap.org/styles/liberty';

  /// The style source holding OpenFreeMap's vector tiles. The bundled
  /// world map stands in for it at zoom 0-4 (PLAN.md D7, D25).
  static const tileSourceId = 'openmaptiles';

  /// The offline copy of the style, bundled with the app (Phase 8a).
  static const offlineStyleAsset = 'assets/map/offline_style.json';

  /// App version, sent in the User-Agent (see [AppInfo]).
  static const appVersion = AppInfo.version;

  /// OpenFreeMap requires a unique, stable User-Agent. It names only the
  /// app and its version.
  static const userAgent = AppInfo.userAgent;

  static const httpHeaders = {'User-Agent': userAgent};

  /// Required attribution for OpenFreeMap / OpenMapTiles / OSM data.
  static const attributions = [
    'OpenFreeMap',
    '© OpenMapTiles',
    'Data © OpenStreetMap contributors',
  ];

  /// Vector tiles exist up to zoom 14. Closer zooms are drawn by scaling
  /// up ("overzooming") the zoom-14 data, so we allow zooming in further.
  static const double minZoom = 1;
  static const double maxZoom = 19;

  /// Zoom used when focusing on a single quest.
  static const double questZoom = 15;

  /// Zoom used when centring on the user (street level, PLAN.md D19).
  static const double playerZoom = 15;

  /// Starting view when there are no quests to show: the whole world.
  static const worldCenter = LatLng(20, 0);
  static const double worldZoom = 1.5;

  /// The persistent tile cache. Tiles already seen are served from disk,
  /// so repeat views cost the server nothing. The OS doesn't clear this
  /// folder (it's in the app support directory).
  ///
  /// Vector tiles go in the app's own cache ([tileCacheBytes], PLAN.md
  /// D27); the package's disk cache ([diskCacheBytes]) now only holds the
  /// shaded relief images, so it is small. Lowering it from 100 MB also
  /// lets the package clear out the vector tiles it cached before.
  static const tileCacheBytes = 100 * 1000 * 1000; // 100 MB
  static const diskCacheBytes = 20 * 1024 * 1024; // 20 MB
  static const diskCacheTtl = Duration(days: 30);
}
