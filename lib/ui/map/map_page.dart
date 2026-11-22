import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/location_fix.dart';
import '../../models/task.dart';
import '../../state/location_controller.dart';
import '../../state/map_focus_controller.dart';
import '../../state/task_list_controller.dart';
import '../tasks/task_actions.dart';
import 'base_map_layer.dart';
import 'camera_animator.dart';
import 'geo_point_latlng.dart';
import 'initial_map_view.dart';
import 'location_access.dart';
import 'map_config.dart';
import 'map_controls.dart';
import 'location_prompt.dart';
import 'missing_location_badge.dart';
import 'player_marker.dart';
import 'quest_details_sheet.dart';
import 'quest_marker.dart';

/// World map with located tasks drawn as quest markers.
///
/// Layers, bottom to top: the base map ([baseLayer]), quest markers, the
/// attribution button, and the [MapControls] (completed toggle, zoom).
/// Tapping a marker opens [QuestDetailsSheet]. A [MissingLocationBadge] in
/// the bottom-left corner counts the tasks that have no location.
///
/// "Show on map" requests arrive through [MapFocusController]. The camera
/// glides to the quest and its marker is highlighted until the user taps
/// empty map.
///
/// The player's position comes from [LocationController] (PLAN.md D8,
/// D19): a blue dot with an accuracy circle, a my-location button that
/// centres on the user and then follows them until they drag the map, and
/// a [LocationPrompt] that explains before the OS permission dialog.
class MapPage extends StatelessWidget {
  const MapPage({
    super.key,
    this.baseLayer = const OpenFreeMapLayer(),
    this.clock = DateTime.now,
    this.mapController,
  });

  /// The base map. Tests pass an empty widget, so they don't load real map
  /// tiles from the network.
  final Widget baseLayer;

  /// Used to decide due-soon / overdue marker colours. Injectable for tests.
  final DateTime Function() clock;

  /// Lets tests inspect the camera. The page creates its own if null.
  final MapController? mapController;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TaskListController>();
    // Only whether the location check has finished matters here; the map
    // itself listens for position updates.
    final locationReady = context.select<LocationController, bool>(
      (l) => l.hasStarted,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('World Map')),
      // Wait for the first task load and the location check (both quick),
      // so the starting camera can use them instead of jumping once they
      // arrive (PLAN.md D19).
      body: controller.hasLoaded && locationReady
          ? Stack(
              children: [
                _QuestMap(
                  tasks: controller.locatedTasks,
                  baseLayer: baseLayer,
                  now: clock(),
                  mapController: mapController,
                ),
                // Bottom-left, because the attribution button sits
                // bottom-right.
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: MissingLocationBadge(
                    count: controller.unlocatedTasks.length,
                  ),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}

class _QuestMap extends StatefulWidget {
  const _QuestMap({
    required this.tasks,
    required this.baseLayer,
    required this.now,
    this.mapController,
  });

  final List<Task> tasks;
  final Widget baseLayer;
  final DateTime now;
  final MapController? mapController;

  @override
  State<_QuestMap> createState() => _QuestMapState();
}

class _QuestMapState extends State<_QuestMap> with TickerProviderStateMixin {
  late final MapController _map = widget.mapController ?? MapController();
  late final MapFocusController _focus;
  late final LocationController _location;
  late final MapOptions _options;

  /// What the starting view was based on (PLAN.md D19).
  late final StartViewSource _startSource;

  /// Whether the camera has been moved by the user, or on their behalf
  /// (a button, "Show on map"). Once true, the first GPS fix no longer
  /// moves the camera by itself.
  bool _touched = false;

  /// Whether this map has seen a GPS fix yet.
  bool _hadFix = false;

  /// The last fix the map reacted to, to tell new fixes from other
  /// location changes.
  LocationFix? _seenFix;

  /// Follow mode: the camera stays on the user as they move. Turned on by
  /// the my-location button, off by dragging the map.
  bool _following = false;

  /// "Not now" on the [LocationPrompt]. Lasts for this app session.
  bool _promptDismissed = false;

  /// Completed quests are hidden by default (PLAN.md D17). This lasts for
  /// the app session and resets to hidden on restart.
  bool _showCompleted = false;

  /// Current zoom, tracked to disable "+" / "−" at the limits. Null until
  /// the map reports its first position.
  double? _zoom;

  late final CameraAnimator _camera = CameraAnimator(this, _map);

  @override
  void initState() {
    super.initState();
    _focus = context.read<MapFocusController>()..addListener(_onFocusChanged);
    _location = context.read<LocationController>()
      ..addListener(_onLocationChanged);

    // Starting view (PLAN.md D19): a "Show on map" request made before the
    // map existed, else the user's live position, else their last known
    // position, else the quests.
    final pending = _focus.takeRequest();
    final current = _location.current;
    final start = InitialMapView.choose(
      focus: pending?.point.toLatLng(),
      gps: current?.point.toLatLng(),
      lastKnown: _location.lastKnown?.point.toLatLng(),
      quests: [for (final t in _visibleTasks()) t.location!.toLatLng()],
    );
    _startSource = start.source;
    _touched = pending != null;
    _seenFix = current;
    _hadFix = current != null;
    _options = start.view.toMapOptions(
      onTap: (_, _) => _focus.clearHighlight(),
      // Long-press: a new quest at that spot (R7, PLAN.md D23).
      onLongPress: (_, point) => _newQuestAt(point),
      onPositionChanged: _onCameraMoved,
    );
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _location.removeListener(_onLocationChanged);
    _camera.dispose();
    if (widget.mapController == null) _map.dispose();
    super.dispose();
  }

  /// Open quests, plus completed ones when the toggle is on. The highlighted
  /// quest is always included, so "Show on map" works for a completed task
  /// even while completed quests are hidden.
  List<Task> _visibleTasks() {
    final highlighted = _focus.highlightedTaskId;
    return [
      for (final t in widget.tasks)
        if (!t.isDone || _showCompleted || t.id == highlighted) t,
    ];
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() {}); // the highlight may have changed
    if (_focus.pendingRequest == null) return;
    // Act after this frame: by then the Map tab is visible and laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final request = _focus.takeRequest();
      if (request != null) {
        _touched = true;
        if (_following) setState(() => _following = false);
        _animateTo(request.point.toLatLng(), MapConfig.questZoom);
      }
    });
  }

  void _onLocationChanged() {
    if (!mounted) return;
    setState(() {
      // Following needs a position. If location became unavailable, stop.
      if (_location.status != LocationStatus.on) _following = false;
    });

    final fix = _location.current;
    if (fix == null || fix == _seenFix) return;
    _seenFix = fix;
    final first = !_hadFix;
    _hadFix = true;

    if (_following) {
      _animateTo(fix.point.toLatLng(), _map.camera.zoom);
    } else if (first && !_touched && _startSource != StartViewSource.gps) {
      // D19: the map opened before the first fix. Glide to the user,
      // unless they've already moved the map themselves.
      _animateTo(fix.point.toLatLng(), MapConfig.playerZoom);
    }
  }

  /// The my-location button (and the prompt's "Allow"): asks, explains or
  /// offers the settings as needed (D22), then centres and follows.
  Future<void> _onMyLocationPressed() async {
    _touched = true;
    final couldAsk = _location.status == LocationStatus.denied ||
        _location.status == LocationStatus.unknown;
    final status = await ensureLocationAccess(context, _location);
    if (!mounted) return;
    // Asked once from here: the prompt card has done its job.
    if (couldAsk) setState(() => _promptDismissed = true);
    if (status == LocationStatus.on) _startFollowing();
  }

  /// Centres on the user (at street level, or closer if already closer)
  /// and keeps following them. With no fix yet, the first fix does it.
  void _startFollowing() {
    setState(() => _following = true);
    final fix = _location.current;
    if (fix == null) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Finding your location…'),
            duration: Duration(seconds: 2),
          ),
        );
      return;
    }
    final zoom = _map.camera.zoom < MapConfig.playerZoom
        ? MapConfig.playerZoom
        : _map.camera.zoom;
    _animateTo(fix.point.toLatLng(), zoom);
  }

  /// Opens the new-quest editor with [point] already filled in. The
  /// vibration confirms the long-press was recognised.
  void _newQuestAt(LatLng point) {
    HapticFeedback.mediumImpact();
    openTaskEditor(context, null, location: point.toPickedGeoPoint());
  }

  void _onCameraMoved(MapCamera camera, bool hasGesture) {
    if (hasGesture) {
      _touched = true;
      // Dragging the map ends follow mode, like in other map apps.
      if (_following) _setStateSafely(() => _following = false);
    }
    if (camera.zoom == _zoom) return;
    _setStateSafely(() => _zoom = camera.zoom);
  }

  /// The map can report positions during layout, when setState isn't
  /// allowed. In that case, update right after the frame.
  void _setStateSafely(VoidCallback change) {
    void update() {
      if (mounted) setState(change);
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => update());
    } else {
      update();
    }
  }

  /// Moves the camera smoothly, or instantly if the OS "remove animations"
  /// setting is on.
  void _animateTo(LatLng center, double zoom) => _camera.animateTo(
        center,
        zoom,
        instant: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
      );

  void _zoomBy(double delta) {
    // Zooming keeps follow mode: the camera zooms around its centre, which
    // is the user while following.
    _touched = true;
    final camera = _map.camera;
    _animateTo(camera.center, camera.zoom + delta);
  }

  @override
  Widget build(BuildContext context) {
    final zoom = _zoom;
    final canZoomIn = zoom == null || zoom < MapConfig.maxZoom - 0.01;
    final canZoomOut = zoom == null || zoom > MapConfig.minZoom + 0.01;
    final fix = _location.current;
    final status = _location.status;
    final showPrompt = status == LocationStatus.denied && !_promptDismissed;

    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: _options,
          children: [
            widget.baseLayer,
            // The player is drawn below the quests, so a quest at the
            // user's position can still be tapped.
            if (fix != null) PlayerMarker.accuracyLayer(fix),
            if (fix != null) PlayerMarker.dotLayer(fix),
            MarkerLayer(markers: _markers()),
            RichAttributionWidget(
              // Attributions are required by the data licence (ODbL) and by
              // OpenFreeMap / OpenMapTiles.
              attributions: [
                for (final a in MapConfig.attributions)
                  TextSourceAttribution(a),
              ],
            ),
          ],
        ),
        // Above the attribution button in the bottom-right corner.
        Positioned(
          right: 12,
          bottom: 72,
          child: MapControls(
            myLocation: status != LocationStatus.on
                ? MyLocationButtonState.unavailable
                : _following
                ? MyLocationButtonState.following
                : MyLocationButtonState.available,
            onMyLocation: _onMyLocationPressed,
            showCompleted: _showCompleted,
            onToggleCompleted: () =>
                setState(() => _showCompleted = !_showCompleted),
            onZoomIn: canZoomIn ? () => _zoomBy(1) : null,
            onZoomOut: canZoomOut ? () => _zoomBy(-1) : null,
          ),
        ),
        if (showPrompt)
          Positioned(
            left: 8,
            right: 8,
            top: 8,
            child: LocationPrompt(
              onAllow: _onMyLocationPressed,
              onDismiss: () => setState(() => _promptDismissed = true),
            ),
          ),
      ],
    );
  }

  List<Marker> _markers() {
    final highlighted = _focus.highlightedTaskId;
    final entries = [
      for (final t in _visibleTasks())
        (task: t, kind: QuestMarkerKind.of(t, widget.now)),
    ];
    // Later entries are drawn on top: completed at the bottom, overdue
    // above the rest, and the highlighted quest above everything.
    int order(({Task task, QuestMarkerKind kind}) e) =>
        e.task.id == highlighted ? 99 : e.kind.drawOrder;
    entries.sort((a, b) => order(a).compareTo(order(b)));

    return [
      for (final e in entries)
        Marker(
          key: ValueKey('quest-marker-${e.task.id}'),
          point: e.task.location!.toLatLng(),
          width: e.task.id == highlighted
              ? QuestMarker.highlightedSize
              : QuestMarker.size,
          height: e.task.id == highlighted
              ? QuestMarker.highlightedSize
              : QuestMarker.size,
          child: QuestMarker(
            task: e.task,
            kind: e.kind,
            highlighted: e.task.id == highlighted,
            onTap: () => _showDetails(e.task, e.kind),
          ),
        ),
    ];
  }

  Future<void> _showDetails(Task task, QuestMarkerKind kind) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => QuestDetailsSheet(
        task: task,
        kind: kind,
        onToggleDone: () {
          Navigator.pop(sheetContext);
          setTaskDone(context, task, !task.isDone);
        },
        onEdit: () {
          Navigator.pop(sheetContext);
          openTaskEditor(context, task);
        },
      ),
    );
  }
}

extension on QuestMarkerKind {
  int get drawOrder => switch (this) {
        QuestMarkerKind.done => 0,
        QuestMarkerKind.active => 1,
        QuestMarkerKind.dueSoon => 2,
        QuestMarkerKind.overdue => 3,
      };
}
