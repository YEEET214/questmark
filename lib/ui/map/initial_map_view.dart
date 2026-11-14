import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'map_config.dart';

/// Where the camera starts when the map first opens.
///
/// * No quests: the whole world.
/// * One quest: centred on it at street level.
/// * Several: zoomed so they all fit on screen.
///
/// After that, the camera only moves when the user moves it. Adding a quest
/// doesn't make the map jump around.
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
  MapOptions toMapOptions();
}

class WorldView extends InitialMapView {
  const WorldView();

  @override
  MapOptions toMapOptions() => _options(
        initialCenter: MapConfig.worldCenter,
        initialZoom: MapConfig.worldZoom,
      );
}

class CenterView extends InitialMapView {
  const CenterView(this.center, this.zoom);
  final LatLng center;
  final double zoom;

  @override
  MapOptions toMapOptions() =>
      _options(initialCenter: center, initialZoom: zoom);
}

class FitView extends InitialMapView {
  const FitView(this.points);
  final List<LatLng> points;

  @override
  MapOptions toMapOptions() => _options(
        initialCameraFit: CameraFit.coordinates(
          coordinates: points,
          // Room for the marker graphics and the attribution button.
          padding: const EdgeInsets.all(64),
          maxZoom: MapConfig.questZoom,
        ),
      );
}

MapOptions _options({
  LatLng initialCenter = MapConfig.worldCenter,
  double initialZoom = MapConfig.worldZoom,
  CameraFit? initialCameraFit,
}) =>
    MapOptions(
      initialCenter: initialCenter,
      initialZoom: initialZoom,
      initialCameraFit: initialCameraFit,
      minZoom: MapConfig.minZoom,
      maxZoom: MapConfig.maxZoom,
      interactionOptions: const InteractionOptions(
        // A to-do map doesn't need rotation, and accidental rotation while
        // pinching is disorienting. North stays up.
        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
      ),
    );
