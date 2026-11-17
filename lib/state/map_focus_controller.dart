import 'package:flutter/foundation.dart';

import '../models/geo_point.dart';
import '../models/task.dart';

/// A request for the map to centre on one task.
@immutable
class MapFocusRequest {
  const MapFocusRequest({required this.taskId, required this.point});

  final int taskId;
  final GeoPoint point;
}

/// Lets other screens ask the map to centre on a task ("Show on map"),
/// without holding a reference to the map widget (PLAN.md D10).
///
/// * [focusOn] stores a pending request, and the map consumes it with
///   [takeRequest]. A request made before the map exists is kept until
///   the map is built, so it's never lost.
/// * [highlightedTaskId] says which marker to emphasise. It stays set
///   after the request is consumed, until [clearHighlight] is called (the
///   user taps empty map) or another task is focused.
class MapFocusController extends ChangeNotifier {
  MapFocusRequest? _pending;
  int? _highlightedTaskId;

  MapFocusRequest? get pendingRequest => _pending;
  int? get highlightedTaskId => _highlightedTaskId;

  /// Asks the map to centre on [task]. Throws [ArgumentError] if the task
  /// has no location or no id: the UI never offers "Show on map" for such
  /// tasks (PLAN.md D10).
  void focusOn(Task task) {
    final id = task.id;
    final point = task.location;
    if (id == null || point == null) {
      throw ArgumentError.value(task, 'task', 'needs an id and a location');
    }
    _pending = MapFocusRequest(taskId: id, point: point);
    _highlightedTaskId = id;
    notifyListeners();
  }

  /// Returns the pending request (if any) and clears it, so each request
  /// moves the camera exactly once.
  MapFocusRequest? takeRequest() {
    final r = _pending;
    _pending = null;
    return r;
  }

  void clearHighlight() {
    if (_highlightedTaskId == null) return;
    _highlightedTaskId = null;
    notifyListeners();
  }
}
