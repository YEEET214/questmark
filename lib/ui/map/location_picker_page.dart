import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/geo_point.dart';
import '../../state/location_controller.dart';
import '../formatting.dart';
import '../theme.dart';
import 'base_map_layer.dart';
import 'camera_animator.dart';
import 'geo_point_latlng.dart';
import 'initial_map_view.dart';
import 'location_access.dart';
import 'map_attribution.dart';
import 'map_config.dart';
import 'map_controls.dart';
import 'player_marker.dart';

/// Picks a point on the map: returns a [GeoPoint], or `null` if cancelled.
///
/// Injectable into the task editor, so editor tests can use a fake picker.
typedef LocationPicker = Future<GeoPoint?> Function(
    BuildContext context, GeoPoint? current);

/// Opens [LocationPickerPage] and returns the chosen point (or `null`).
Future<GeoPoint?> pickLocationOnMap(BuildContext context, GeoPoint? current) {
  return Navigator.of(context).push<GeoPoint>(
    MaterialPageRoute(
      builder: (_) => LocationPickerPage(initial: current),
      fullscreenDialog: true,
    ),
  );
}

/// Full-screen map for placing a quest (PLAN.md D23).
///
/// The pin stays fixed in the middle of the screen and the user moves the
/// **map** under it (as in most map apps). This is easier than dragging a
/// small marker, which the finger would hide. Tapping or long-pressing a
/// spot glides it under the pin. "Use this location" returns the point
/// under the pin.
///
/// It starts at the quest's current location, else the user's position
/// (live or last known), else the whole world.
class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({
    super.key,
    this.initial,
    this.baseLayer,
    this.mapController,
  });

  /// The quest's current location, if it has one.
  final GeoPoint? initial;

  /// The base map. Defaults to the app-wide [MapBaseLayer].
  final Widget? baseLayer;

  /// Lets tests inspect the camera. The page creates its own if null.
  final MapController? mapController;

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage>
    with TickerProviderStateMixin {
  late final MapController _map = widget.mapController ?? MapController();
  late final CameraAnimator _camera = CameraAnimator(this, _map);
  late final LocationController _location;
  late final MapOptions _options;

  /// The point under the pin, updated as the map moves.
  late LatLng _center;
  double? _zoom;

  /// The user tapped the my-location button before the first fix: go
  /// there when it arrives.
  bool _goToMeOnFix = false;

  @override
  void initState() {
    super.initState();
    _location = context.read<LocationController>()
      ..addListener(_onLocationChanged);
    final start = InitialMapView.choose(
      focus: widget.initial?.toLatLng(),
      gps: _location.current?.point.toLatLng(),
      lastKnown: _location.lastKnown?.point.toLatLng(),
      quests: const [],
    );
    _center = switch (start.view) {
      CenterView(:final center) => center,
      _ => MapConfig.worldCenter,
    };
    _options = start.view.toMapOptions(
      // A tap or long-press brings that spot under the pin.
      onTap: (_, point) => _moveTo(point),
      onLongPress: (_, point) => _moveTo(point),
      onPositionChanged: _onCameraMoved,
    );
  }

  @override
  void dispose() {
    _location.removeListener(_onLocationChanged);
    _camera.dispose();
    if (widget.mapController == null) _map.dispose();
    super.dispose();
  }

  void _onLocationChanged() {
    if (!mounted) return;
    setState(() {}); // the player dot
    final fix = _location.current;
    if (_goToMeOnFix && fix != null) {
      _goToMeOnFix = false;
      _goTo(fix.point.toLatLng());
    }
  }

  void _onCameraMoved(MapCamera camera, bool hasGesture) {
    void update() {
      if (!mounted) return;
      setState(() {
        _center = camera.center;
        _zoom = camera.zoom;
      });
    }

    // The map can report positions during layout, when setState isn't
    // allowed. In that case, update right after the frame.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => update());
    } else {
      update();
    }
  }

  bool get _instant => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _moveTo(LatLng point) =>
      _camera.animateTo(point, _map.camera.zoom, instant: _instant);

  /// Centres on [point] at street level, or closer if already closer.
  void _goTo(LatLng point) {
    final zoom = _map.camera.zoom < MapConfig.playerZoom
        ? MapConfig.playerZoom
        : _map.camera.zoom;
    _camera.animateTo(point, zoom, instant: _instant);
  }

  Future<void> _onMyLocationPressed() async {
    final status = await ensureLocationAccess(context, _location);
    if (!mounted || status != LocationStatus.on) return;
    final fix = _location.current;
    if (fix != null) {
      _goTo(fix.point.toLatLng());
      return;
    }
    _goToMeOnFix = true;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Finding your location…'),
        duration: Duration(seconds: 2),
      ));
  }

  void _zoomBy(double delta) {
    final camera = _map.camera;
    _camera.animateTo(camera.center, camera.zoom + delta, instant: _instant);
  }

  void _confirm() {
    Navigator.of(context).pop(_map.camera.center.toPickedGeoPoint());
  }

  @override
  Widget build(BuildContext context) {
    final baseLayer =
        widget.baseLayer ?? context.read<MapBaseLayer>().layer;
    final fix = _location.current;
    final zoom = _zoom;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Pick location')),
      body: Stack(
        // The map must fill the page even while the base map is still
        // loading (an empty layer), or it would shrink to nothing.
        fit: StackFit.expand,
        children: [
          FlutterMap(
            mapController: _map,
            options: _options,
            children: [
              baseLayer,
              if (fix != null) PlayerMarker.accuracyLayer(fix),
              if (fix != null) PlayerMarker.dotLayer(fix),
            ],
          ),
          const IgnorePointer(child: Center(child: PickerPin())),
          Positioned(
            left: 8,
            right: 8,
            top: 8,
            child: Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Move the map to put the pin on the quest\'s place',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatCoordinates(_center.toPickedGeoPoint()),
                      key: const Key('pickerCoordinates'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 72,
            child: MapControls(
              myLocation: _location.status == LocationStatus.on
                  ? MyLocationButtonState.available
                  : MyLocationButtonState.unavailable,
              onMyLocation: _onMyLocationPressed,
              onZoomIn: zoom == null || zoom < MapConfig.maxZoom - 0.01
                  ? () => _zoomBy(1)
                  : null,
              onZoomOut: zoom == null || zoom > MapConfig.minZoom + 0.01
                  ? () => _zoomBy(-1)
                  : null,
            ),
          ),
          // Last, so its open card is on top of the map buttons.
          const Positioned(right: 12, bottom: 12, child: MapAttribution()),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            key: const Key('useLocationButton'),
            onPressed: _confirm,
            icon: const Icon(Icons.check),
            label: const Text('Use this location'),
          ),
        ),
      ),
    );
  }
}

/// The pin in the middle of the picker. Its tip marks the exact point: the
/// icon is lifted by half its height, and a small dot sits on the point.
class PickerPin extends StatelessWidget {
  const PickerPin({super.key});

  static const double size = 48;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -size / 2),
            child: const Icon(
              Icons.location_on,
              size: size,
              color: questGold,
              shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }
}
