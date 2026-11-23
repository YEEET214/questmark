import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/geo_point.dart';
import '../../models/geocode_result.dart';
import '../../services/geocoding_service.dart';
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

/// What the picker hands back: the point under the pin, and its address
/// if it came from an address search (PLAN.md D6, D23).
@immutable
class PickedLocation {
  const PickedLocation(this.point, {this.address});

  final GeoPoint point;

  /// The chosen search result's address, or `null` when the point was
  /// placed by moving the map (it's then looked up after saving).
  final String? address;

  @override
  bool operator ==(Object other) =>
      other is PickedLocation &&
      other.point == point &&
      other.address == address;

  @override
  int get hashCode => Object.hash(point, address);

  @override
  String toString() => 'PickedLocation($point, $address)';
}

/// Picks a location: returns a [PickedLocation], or `null` if cancelled.
///
/// Injectable into the task editor, so editor tests can use a fake picker.
typedef LocationPicker = Future<PickedLocation?> Function(
    BuildContext context, GeoPoint? current);

/// Opens [LocationPickerPage] and returns the choice (or `null`).
Future<PickedLocation?> pickLocationOnMap(
    BuildContext context, GeoPoint? current) {
  return Navigator.of(context).push<PickedLocation>(
    MaterialPageRoute(
      builder: (_) => LocationPickerPage(initial: current),
      fullscreenDialog: true,
    ),
  );
}

/// Full-screen map for placing a quest (PLAN.md D23), with address search
/// (D6).
///
/// * The pin stays fixed in the middle and the user moves the **map**
///   under it. Tapping or long-pressing a spot glides it under the pin.
/// * **Address search:** type an address and press Search (on the
///   keyboard or the field's button). There's no search-as-you-type,
///   because Nominatim's policy forbids autocomplete. Tapping a result
///   glides the map there.
/// * "Use this location" returns the point under the pin. If the pin is
///   still on the chosen search result, its address comes along.
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

  /// How close (in metres) the pin must be to a chosen search result for
  /// its address to still count. Further away, the address would describe
  /// a different place.
  static const addressMatchMeters = 5.0;

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage>
    with TickerProviderStateMixin {
  late final MapController _map = widget.mapController ?? MapController();
  late final CameraAnimator _camera = CameraAnimator(this, _map);
  late final LocationController _location;
  late final GeocodingService _geocoder;
  late final MapOptions _options;

  final _query = TextEditingController();
  final _searchFocus = FocusNode();

  /// The point under the pin, updated as the map moves.
  late LatLng _center;
  double? _zoom;

  /// The user tapped the my-location button before the first fix: go
  /// there when it arrives.
  bool _goToMeOnFix = false;

  bool _searching = false;

  /// The last search's results (`null`: none shown).
  List<GeocodeResult>? _results;

  /// The query those results are for, for the "no results" message.
  String _resultsQuery = '';
  String? _searchError;

  /// The search result the user tapped.
  GeocodeResult? _chosen;

  @override
  void initState() {
    super.initState();
    _location = context.read<LocationController>()
      ..addListener(_onLocationChanged);
    _geocoder = context.read<GeocodingService>();
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
    _query.dispose();
    _searchFocus.dispose();
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

  void _moveTo(LatLng point) {
    // Touching the map also closes an open results list.
    if (_results != null || _searchError != null) {
      setState(() {
        _results = null;
        _searchError = null;
      });
    }
    _searchFocus.unfocus();
    _camera.animateTo(point, _map.camera.zoom, instant: _instant);
  }

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

  /// Runs only when the user presses Search: no search-as-you-type
  /// (Nominatim policy, D6).
  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty || _searching) return;
    _searchFocus.unfocus();
    setState(() {
      _searching = true;
      _searchError = null;
      _results = null;
    });
    try {
      final results = await _geocoder.search(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _resultsQuery = query;
      });
    } on GeocodingException catch (e) {
      if (mounted) setState(() => _searchError = e.userMessage);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _choose(GeocodeResult result) {
    setState(() {
      _chosen = result;
      _results = null;
    });
    final camera = _map.camera;
    // Close in, but don't zoom out if the user is already closer.
    final zoom =
        camera.zoom < MapConfig.questZoom ? MapConfig.questZoom : camera.zoom;
    _camera.animateTo(result.point.toLatLng(), zoom, instant: _instant);
  }

  /// The chosen result's address, while the pin is still on it.
  String? get _matchedAddress {
    final chosen = _chosen;
    if (chosen == null) return null;
    final metres = const Distance().as(
        LengthUnit.Meter, _center, chosen.point.toLatLng());
    return metres <= LocationPickerPage.addressMatchMeters
        ? chosen.label
        : null;
  }

  void _confirm() {
    final center = _map.camera.center;
    _center = center;
    Navigator.of(context).pop(
      PickedLocation(center.toPickedGeoPoint(), address: _matchedAddress),
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseLayer =
        widget.baseLayer ?? context.read<MapBaseLayer>().layer;
    final fix = _location.current;
    final zoom = _zoom;

    return Scaffold(
      appBar: AppBar(title: const Text('Choose location')),
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
          // The search card goes above the map buttons, so an open
          // results list is never covered.
          Positioned(left: 8, right: 8, top: 8, child: _buildSearchCard()),
          // Last, so its open card is on top of everything.
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

  Widget _buildSearchCard() {
    final theme = Theme.of(context);
    final results = _results;
    final error = _searchError;
    final address = _matchedAddress;

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('addressSearchField'),
              controller: _query,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              onTapOutside: (_) => _searchFocus.unfocus(),
              decoration: InputDecoration(
                hintText: 'Search for an address',
                border: InputBorder.none,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        key: const Key('addressSearchButton'),
                        tooltip: 'Search',
                        icon: const Icon(Icons.arrow_forward),
                        onPressed: _search,
                      ),
              ),
            ),
            // Be open about what leaves the phone (user decisions, PR #11
            // review and Phase 8b): search text, the location of quests
            // that need an address, and, only to name a downloaded map
            // area, a rough position (PLAN.md D26).
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Searches and quest locations are sent to OpenStreetMap\'s '
                'Nominatim service to find addresses. Your own location is '
                'only sent, rounded to about 1 km, to name a map area you '
                'download.',
                key: const Key('nominatimNote'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  error,
                  key: const Key('addressSearchError'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            if (results != null && results.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'No places found for "$_resultsQuery". Try adding the '
                  'town, or move the map to the place instead.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (results != null && results.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (final (i, r) in results.indexed)
                      ListTile(
                        key: Key('addressResult-$i'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.place_outlined),
                        title: Text(r.label),
                        subtitle: Text(
                          r.fullName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _choose(r),
                      ),
                  ],
                ),
              ),
            const Divider(height: 8),
            if (address != null)
              Text(
                address,
                key: const Key('pickerAddress'),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              )
            else
              Text(
                'Or move the map to put the pin on the quest\'s place',
                style: theme.textTheme.bodySmall,
              ),
            Text(
              formatCoordinates(_center.toPickedGeoPoint()),
              key: const Key('pickerCoordinates'),
              style: theme.textTheme.bodySmall,
            ),
          ],
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
