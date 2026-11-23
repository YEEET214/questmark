import 'package:flutter/foundation.dart';

import '../data/task_repository.dart';
import '../models/geo_point.dart';
import '../models/task.dart';
import '../services/geocoding_service.dart';

/// App-wide task state, shared by the list page and (from phase 3) the map.
///
/// ## Write-through, then reload
/// Every change is written to the repository first, then the list is
/// re-read from it. The alternative, patching the in-memory list
/// optimistically, would have to repeat the SQL ordering rules in Dart and
/// could drift out of sync with the database. With a local SQLite database
/// a reload takes about a millisecond, so the simple approach costs nothing
/// noticeable, and the database stays the single source of truth.
class TaskListController extends ChangeNotifier {
  TaskListController(
    this._repository, {
    DateTime Function()? clock,
    this.geocoder,
  }) : _clock = clock ?? DateTime.now;

  /// How long a deleted task stays in the recycle bin before it is removed
  /// for good (PLAN.md D18).
  static const binRetention = Duration(days: 30);

  final TaskRepository _repository;

  /// Injected so tests can control `createdAt` timestamps.
  final DateTime Function() _clock;

  /// Looks up addresses for pinned tasks (PLAN.md D6). Optional: without
  /// it, tasks simply keep showing their coordinates.
  final GeocodingService? geocoder;

  /// The address lookup started by the last add/save, if any. Lets tests
  /// wait for it; the UI never needs to.
  @visibleForTesting
  Future<void>? lastAddressLookup;

  List<Task> _tasks = const [];
  List<Task> _binTasks = const [];
  bool _isLoading = false;
  bool _hasLoaded = false;
  Object? _loadError;

  /// All tasks not in the recycle bin, in repository order (newest
  /// created first; the list page applies its own sort).
  List<Task> get tasks => _tasks;

  /// Tasks in the recycle bin, most recently deleted first.
  List<Task> get binTasks => _binTasks;

  List<Task> get activeTasks => _tasks.where((t) => !t.isDone).toList();
  List<Task> get completedTasks => _tasks.where((t) => t.isDone).toList();

  /// Tasks that should appear on the map.
  List<Task> get locatedTasks => _tasks.where((t) => t.hasLocation).toList();

  /// Tasks with no location: list-only, not shown on the map. The map
  /// shows their count as a reminder.
  List<Task> get unlocatedTasks =>
      _tasks.where((t) => !t.hasLocation).toList();

  bool get isLoading => _isLoading;

  /// `true` once the first load has finished (successfully or not). Lets
  /// the UI tell "still loading" apart from "loaded, and empty".
  bool get hasLoaded => _hasLoaded;

  /// The error from the last [load], or `null`. Errors from changes
  /// (add/update/...) are rethrown to the caller instead, because only the
  /// UI that triggered the change knows how to report it.
  Object? get loadError => _loadError;

  /// (Re)loads all tasks from the repository. Bin tasks older than
  /// [binRetention] are removed for good first; this is the "on app start"
  /// purge.
  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _purge();
      _tasks = await _repository.getAll();
      _binTasks = await _repository.getBin();
      _loadError = null;
    } catch (e) {
      _loadError = e;
    } finally {
      _isLoading = false;
      _hasLoaded = true;
      notifyListeners();
    }
  }

  /// Creates a new task, stamped with the current time.
  Future<Task> add({
    required String title,
    String? description,
    DateTime? dueAt,
    GeoPoint? location,
    String? address,
  }) async {
    final saved = await _repository.insert(Task(
      title: title,
      description: description,
      dueAt: dueAt,
      location: location,
      address: address,
      createdAt: _clock(),
    ));
    await _refresh();
    _lookUpAddressLater(saved);
    return saved;
  }

  /// Saves an edited task (it must already have an id).
  Future<void> save(Task task) async {
    await _repository.update(task);
    await _refresh();
    _lookUpAddressLater(task);
  }

  /// A saved task with a location but no address (pinned on the map) gets
  /// its address looked up once, in the background (PLAN.md D6). The save
  /// itself never waits for the network. If the lookup fails (e.g.
  /// offline), the task keeps its coordinates and the next save tries
  /// again.
  void _lookUpAddressLater(Task task) {
    final geocoder = this.geocoder;
    final id = task.id;
    final point = task.location;
    if (geocoder == null || id == null || point == null) return;
    if (task.address != null) return;
    lastAddressLookup = _lookUpAddress(geocoder, id, point);
  }

  Future<void> _lookUpAddress(
      GeocodingService geocoder, int id, GeoPoint point) async {
    final String? address;
    try {
      address = await geocoder.reverse(point);
    } catch (e) {
      debugPrint('Address lookup failed: $e');
      return;
    }
    if (address == null || _disposed) return;
    try {
      // Re-read: the user may have moved the quest, added an address or
      // deleted it while the lookup was running. Only fill in an address
      // for the same point, and never overwrite one.
      final current = await _repository.getById(id);
      if (current == null ||
          current.isInBin ||
          current.location != point ||
          current.address != null) {
        return;
      }
      await _repository.update(current.copyWith(address: () => address));
      await _refresh();
    } catch (e) {
      debugPrint('Saving the looked-up address failed: $e');
    }
  }

  /// Ticks or unticks [task]. Ticking records the completion time (from
  /// the clock); unticking clears it.
  Future<void> setDone(Task task, bool done) async {
    if (task.isDone == done) return;
    await save(task.copyWith(
      isDone: done,
      completedAt: () => done ? _clock() : null,
    ));
  }

  /// Moves [task] to the recycle bin. Returns it so the caller can offer
  /// "Undo" via [restoreFromBin].
  Future<Task> moveToBin(Task task) async {
    await _repository.moveToBin(_idOf(task), _clock());
    await _refresh();
    return task;
  }

  /// Takes [task] out of the bin. It comes back exactly as it was, with the
  /// same id. Also used for "Undo" after deleting.
  Future<void> restoreFromBin(Task task) async {
    await _repository.restoreFromBin(_idOf(task));
    await _refresh();
  }

  /// Moves every completed task to the bin ("Delete all completed tasks").
  /// Returns how many were moved.
  Future<int> moveCompletedToBin() async {
    final moved = await _repository.moveCompletedToBin(_clock());
    await _refresh();
    return moved;
  }

  /// Removes [task] for good.
  Future<void> deletePermanently(Task task) async {
    await _repository.deletePermanently(_idOf(task));
    await _refresh();
  }

  /// Removes everything in the bin for good. Returns how many.
  Future<int> emptyBin() async {
    final removed = await _repository.emptyBin();
    await _refresh();
    return removed;
  }

  /// Removes bin tasks older than [binRetention]. Called when the bin page
  /// opens, in addition to every [load]. Returns how many were removed.
  Future<int> purgeExpiredBin() async {
    final removed = await _purge();
    if (removed > 0) await _refresh();
    return removed;
  }

  /// When [task] (in the bin) will be removed for good.
  DateTime expiresAt(Task task) => task.deletedAt!.add(binRetention);

  Future<int> _purge() =>
      _repository.purgeBin(deletedBefore: _clock().subtract(binRetention));

  static int _idOf(Task task) {
    final id = task.id;
    if (id == null) throw ArgumentError.value(task, 'task', 'has no id');
    return id;
  }

  Future<void> _refresh() async {
    _tasks = await _repository.getAll();
    _binTasks = await _repository.getBin();
    _loadError = null;
    if (!_disposed) notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
