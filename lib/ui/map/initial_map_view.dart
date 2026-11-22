import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'map_config.dart';

/// Map callbacks the page wants, passed through to [MapOptions].
typedef MapTapCallback = void Function(TapPosition, LatLng);
typedef MapPositionCallback = void Function(MapCamera, bool hasGesture);

/// What [InitialMapView.choose] based the starting view on.
enum StartViewSource { focusRequest, gps, lastKnown, quests }

/// Where the camera starts when the map first opens.
///
/// * No quests: the whole world.
/// * One quest: centred on it at street level.
/// * Several: zoomed so they all fit on screen.
/// * A pending "Show on map" request (made before the map existed) wins
///   over all of these: the map then simply starts centred on that quest.
///
/// [choose] puts the user's position (live or last known) ahead of the
/// quests (PLAN.md D19).
///
/// After that, the camera only moves when the user moves it, or when a
/// "Show on map" request, a map button or follow mode moves it on their
/// behalf. The one exception: the first GPS fix glides the camera to the
/// user if they haven't touched the map yet (D19).
sealed class InitialMapView {
  const InitialMapView();

  factory InitialMapView.forPoints(List<LatLng> points) {
    if (points.isEmpty) return const WorldView();
    final first = points.first;
    if (points.every((p) => p == first)) {
      // A single point (or all quests at one spot) has no extent to fit.
      return CenterView(first, MapConfig.questZoom);
    }
    return FitView(points);
  }

  /// Picks the map's starting view, in this order (PLAN.md D19):
  /// 1. a pending "Show on map" request ([focus]);
  /// 2. the current GPS position ([gps]);
  /// 3. the last known position ([lastKnown]);
  /// 4. otherwise [InitialMapView.forPoints] on the [quests].
  ///
  /// The returned source tells the map whether a GPS fix arriving later
  /// should still glide the camera to the user.
  static ({InitialMapView view, StartViewSource source}) choose({
    LatLng? focus,
    LatLng? gps,
    LatLng? lastKnown,
    required List<LatLng> quests,
  }) {
    if (focus != null) {
      return (
        view: CenterView(focus, MapConfig.questZoom),
        source: StartViewSource.focusRequest,
      );
    }
    if (gps != null) {
      return (
        view: CenterView(gps, MapConfig.playerZoom),
        source: StartViewSource.gps,
      );
    }
    if (lastKnown != null) {
      return (
        view: CenterView(lastKnown, MapConfig.playerZoom),
        source: StartViewSource.lastKnown,
      );
    }
    return (
      view: InitialMapView.forPoints(quests),
      source: StartViewSource.quests,
    );
  }

  /// Converts to flutter_map options.
  MapOptions toMapOptions({
    MapTapCallback? onTap,
    MapTapCallback? onLongPress,
    MapPositionCallback? onPositionChanged,
  });
}

class WorldView extends InitialMapView {
  const WorldView();

  @override
  MapOptions toMapOptions({
    MapTapCallback? onTap,
    MapTapCallback? onLongPress,
    MapPositionCallback? onPositionChanged,
  }) =>
      _options(
        initialCenter: MapConfig.worldCenter,
        initialZoom: MapConfig.worldZoom,
        onTap: onTap,
        onLongPress: onLongPress,
        onPositionChanged: onPositionChanged,
      );
}

class CenterView extends InitialMapView {
  const CenterView(this.center, this.zoom);
  final LatLng center;
  final double zoom;

  @override
  MapOptions toMapOptions({
    MapTapCallback? onTap,
    MapTapCallback? onLongPress,
    MapPositionCallback? onPositionChanged,
  }) =>
      _options(
        initialCenter: center,
        initialZoom: zoom,
        onTap: onTap,
        onLongPress: onLongPress,
        onPositionChanged: onPositionChanged,
      );
}

class FitView extends InitialMapView {
  const FitView(this.points);
  final List<LatLng> points;

  @override
  MapOptions toMapOptions({
    MapTapCallback? onTap,
    MapTapCallback? onLongPress,
    MapPositionCallback? onPositionChanged,
  }) =>
      _options(
        initialCameraFit: CameraFit.coordinates(
          coordinates: points,
          // Room for the marker graphics and the map controls.
          padding: const EdgeInsets.all(64),
          maxZoom: MapConfig.questZoom,
        ),
        onTap: onTap,
        onLongPress: onLongPress,
        onPositionChanged: onPositionChanged,
      );
}

MapOptions _options({
  LatLng initialCenter = MapConfig.worldCenter,
  double initialZoom = MapConfig.worldZoom,
  CameraFit? initialCameraFit,
  MapTapCallback? onTap,
  MapTapCallback? onLongPress,
  MapPositionCallback? onPositionChanged,
}) =>
    MapOptions(
      initialCenter: initialCenter,
      initialZoom: initialZoom,
      initialCameraFit: initialCameraFit,
      minZoom: MapConfig.minZoom,
      maxZoom: MapConfig.maxZoom,
      onTap: onTap,
      onLongPress: onLongPress,
      onPositionChanged: onPositionChanged,
      interactionOptions: const InteractionOptions(
        // A to-do map doesn't need rotation, and accidental rotation while
        // pinching is disorienting. North stays up.
        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
      ),
    );
