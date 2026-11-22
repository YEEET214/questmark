import 'package:flutter/animation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'map_config.dart';

/// Glides a [MapController]'s camera to a new centre and zoom (PLAN.md
/// D20): 600 ms, ease in/out. `flutter_map` 8 has no animated move of its
/// own, so this tweens over `MapController.move`.
///
/// Used by the world map and the location picker, so camera moves look
/// the same everywhere.
class CameraAnimator {
  CameraAnimator(this._vsync, this._map);

  final TickerProvider _vsync;
  final MapController _map;

  static const duration = Duration(milliseconds: 600);

  AnimationController? _animation;

  /// Moves to [center] at [zoom] (clamped to the map's limits). With
  /// [instant] (the OS "remove animations" setting), it jumps instead.
  /// A new move replaces one still in progress.
  void animateTo(LatLng center, double zoom, {bool instant = false}) {
    stop();
    final zoomTarget = zoom.clamp(MapConfig.minZoom, MapConfig.maxZoom);
    if (instant) {
      _map.move(center, zoomTarget);
      return;
    }

    final camera = _map.camera;
    final lat = Tween(begin: camera.center.latitude, end: center.latitude);
    final lng = Tween(begin: camera.center.longitude, end: center.longitude);
    final z = Tween(begin: camera.zoom, end: zoomTarget);
    final controller = AnimationController(vsync: _vsync, duration: duration);
    final curve =
        CurvedAnimation(parent: controller, curve: Curves.easeInOutCubic);
    controller.addListener(() {
      _map.move(
        LatLng(lat.evaluate(curve), lng.evaluate(curve)),
        z.evaluate(curve),
      );
    });
    _animation = controller;
    controller.forward();
  }

  /// Stops a move in progress, leaving the camera where it is.
  void stop() {
    _animation?.dispose();
    _animation = null;
  }

  void dispose() => stop();
}
