import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../../models/task.dart';
import '../../state/task_list_controller.dart';
import '../tasks/task_actions.dart';
import 'base_map_layer.dart';
import 'geo_point_latlng.dart';
import 'initial_map_view.dart';
import 'map_config.dart';
import 'quest_details_sheet.dart';
import 'quest_marker.dart';

/// World map with every located task drawn as a quest marker.
///
/// Layers, bottom to top: the base map ([baseLayer]), quest markers, and
/// the attribution button. Tapping a marker opens [QuestDetailsSheet].
class MapPage extends StatelessWidget {
  const MapPage({
    super.key,
    this.baseLayer = const OpenFreeMapLayer(),
    this.clock = DateTime.now,
  });

  /// The base map. Tests pass an empty widget, so they don't load real map
  /// tiles from the network.
  final Widget baseLayer;

  /// Used to decide due-soon / overdue marker colours. Injectable for tests.
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TaskListController>();
    return Scaffold(
      appBar: AppBar(title: const Text('World Map')),
      // Wait for the first task load, so the initial camera can frame the
      // quests instead of jumping once they arrive.
      body: controller.hasLoaded
          ? _QuestMap(
              tasks: controller.locatedTasks,
              baseLayer: baseLayer,
              now: clock(),
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
  });

  final List<Task> tasks;
  final Widget baseLayer;
  final DateTime now;

  @override
  State<_QuestMap> createState() => _QuestMapState();
}

class _QuestMapState extends State<_QuestMap> {
  /// Decided once, when the map first appears. Later changes to the task
  /// list update the markers but never move the camera.
  late final MapOptions _options = InitialMapView.forPoints(
    [for (final t in widget.tasks) t.location!.toLatLng()],
  ).toMapOptions();

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: _options,
      children: [
        widget.baseLayer,
        MarkerLayer(markers: _markers()),
        RichAttributionWidget(
          // Attributions are required by the data licence (ODbL) and by
          // OpenFreeMap / OpenMapTiles.
          attributions: [
            for (final a in MapConfig.attributions) TextSourceAttribution(a),
          ],
        ),
      ],
    );
  }

  List<Marker> _markers() {
    final entries = [
      for (final t in widget.tasks) (task: t, kind: QuestMarkerKind.of(t, widget.now)),
    ];
    // Later entries are drawn on top. Put completed quests at the bottom
    // and overdue ones on top, so the urgent markers are never hidden.
    entries.sort((a, b) => a.kind.drawOrder.compareTo(b.kind.drawOrder));

    return [
      for (final e in entries)
        Marker(
          key: ValueKey('quest-marker-${e.task.id}'),
          point: e.task.location!.toLatLng(),
          width: QuestMarker.size,
          height: QuestMarker.size,
          child: QuestMarker(
            task: e.task,
            kind: e.kind,
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
