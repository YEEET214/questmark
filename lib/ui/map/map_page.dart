import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/task.dart';
import '../../state/map_focus_controller.dart';
import '../../state/task_list_controller.dart';
import '../tasks/task_actions.dart';
import 'base_map_layer.dart';
import 'geo_point_latlng.dart';
import 'initial_map_view.dart';
import 'map_config.dart';
import 'map_controls.dart';
import 'missing_location_badge.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('World Map')),
      // Wait for the first task load, so the initial camera can frame the
      // quests instead of jumping once they arrive.
      body: controller.hasLoaded
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
  late final MapOptions _options;

  /// Completed quests are hidden by default (PLAN.md D17). This lasts for
  /// the app session and resets to hidden on restart.
  bool _showCompleted = false;

  /// Current zoom, tracked to disable "+" / "−" at the limits. Null until
  /// the map reports its first position.
  double? _zoom;

  AnimationController? _cameraAnimation;

  @override
  void initState() {
    super.initState();
    _focus = context.read<MapFocusController>()..addListener(_onFocusChanged);

    // A "Show on map" request made before the map existed (e.g. the very
    // first visit to the Map tab) decides the starting view.
    final pending = _focus.takeRequest();
    final view = pending != null
        ? CenterView(pending.point.toLatLng(), MapConfig.questZoom)
        : InitialMapView.forPoints(
            [for (final t in _visibleTasks()) t.location!.toLatLng()]);
    _options = view.toMapOptions(
      onTap: (_, _) => _focus.clearHighlight(),
      onPositionChanged: _onCameraMoved,
    );
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _cameraAnimation?.dispose();
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
        _animateTo(request.point.toLatLng(), MapConfig.questZoom);
      }
    });
  }

  void _onCameraMoved(MapCamera camera, bool hasGesture) {
    if (camera.zoom == _zoom) return;
    void update() {
      if (mounted) setState(() => _zoom = camera.zoom);
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

  /// Moves the camera smoothly, or instantly if the OS "remove animations"
  /// setting is on.
  void _animateTo(LatLng center, double zoom) {
    _cameraAnimation?.dispose();
    _cameraAnimation = null;
    final zoomTarget = zoom.clamp(MapConfig.minZoom, MapConfig.maxZoom);

    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _map.move(center, zoomTarget);
      return;
    }

    final camera = _map.camera;
    final lat = Tween(begin: camera.center.latitude, end: center.latitude);
    final lng = Tween(begin: camera.center.longitude, end: center.longitude);
    final z = Tween(begin: camera.zoom, end: zoomTarget);
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    final curve =
        CurvedAnimation(parent: controller, curve: Curves.easeInOutCubic);
    controller.addListener(() {
      _map.move(
        LatLng(lat.evaluate(curve), lng.evaluate(curve)),
        z.evaluate(curve),
      );
    });
    _cameraAnimation = controller;
    controller.forward();
  }

  void _zoomBy(double delta) {
    final camera = _map.camera;
    _animateTo(camera.center, camera.zoom + delta);
  }

  @override
  Widget build(BuildContext context) {
    final zoom = _zoom;
    final canZoomIn = zoom == null || zoom < MapConfig.maxZoom - 0.01;
    final canZoomOut = zoom == null || zoom > MapConfig.minZoom + 0.01;

    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: _options,
          children: [
            widget.baseLayer,
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
            showCompleted: _showCompleted,
            onToggleCompleted: () =>
                setState(() => _showCompleted = !_showCompleted),
            onZoomIn: canZoomIn ? () => _zoomBy(1) : null,
            onZoomOut: canZoomOut ? () => _zoomBy(-1) : null,
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
