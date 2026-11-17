import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'map_config.dart';

/// Map callbacks the page wants, passed through to [MapOptions].
typedef MapTapCallback = void Function(TapPosition, LatLng);
typedef MapPositionCallback = void Function(MapCamera, bool hasGesture);

/// Where the camera starts when the map first opens.
///
/// * No quests: the whole world.
/// * One quest: centred on it at street level.
/// * Several: zoomed so they all fit on screen.
/// * A pending "Show on map" request (made before the map existed) wins
///   over all of these: the map then simply starts centred on that quest.
///
/// After that, the camera only moves when the user moves it, or when a
/// "Show on map" request or a zoom button moves it on their behalf.
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

  /// Converts to flutter_map options.
  MapOptions toMapOptions({
    MapTapCallback? onTap,
    MapPositionCallback? onPositionChanged,
  });
}

class WorldView extends InitialMapView {
  const WorldView();

  @override
  MapOptions toMapOptions({
    MapTapCallback? onTap,
    MapPositionCallback? onPositionChanged,
  }) =>
      _options(
        initialCenter: MapConfig.worldCenter,
        initialZoom: MapConfig.worldZoom,
        onTap: onTap,
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
    MapPositionCallback? onPositionChanged,
  }) =>
      _options(
        initialCenter: center,
        initialZoom: zoom,
        onTap: onTap,
        onPositionChanged: onPositionChanged,
      );
}

class FitView extends InitialMapView {
  const FitView(this.points);
  final List<LatLng> points;

  @override
  MapOptions toMapOptions({
    MapTapCallback? onTap,
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
        onPositionChanged: onPositionChanged,
      );
}

MapOptions _options({
  LatLng initialCenter = MapConfig.worldCenter,
  double initialZoom = MapConfig.worldZoom,
  CameraFit? initialCameraFit,
  MapTapCallback? onTap,
  MapPositionCallback? onPositionChanged,
}) =>
    MapOptions(
      initialCenter: initialCenter,
      initialZoom: initialZoom,
      initialCameraFit: initialCameraFit,
      minZoom: MapConfig.minZoom,
      maxZoom: MapConfig.maxZoom,
      onTap: onTap,
      onPositionChanged: onPositionChanged,
      interactionOptions: const InteractionOptions(
        // A to-do map doesn't need rotation, and accidental rotation while
        // pinching is disorienting. North stays up.
        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
      ),
    );
