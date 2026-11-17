import 'package:flutter/foundation.dart';

import '../data/task_repository.dart';
import '../models/geo_point.dart';
import '../models/task.dart';

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
  TaskListController(this._repository, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final TaskRepository _repository;

  /// Injected so tests can control `createdAt` timestamps.
  final DateTime Function() _clock;

  List<Task> _tasks = const [];
  bool _isLoading = false;
  bool _hasLoaded = false;
  Object? _loadError;

  /// All tasks, in repository order (active first, see [TaskRepository]).
  List<Task> get tasks => _tasks;

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

  /// (Re)loads all tasks from the repository.
  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      _tasks = await _repository.getAll();
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
  }) async {
    final saved = await _repository.insert(Task(
      title: title,
      description: description,
      dueAt: dueAt,
      location: location,
      createdAt: _clock(),
    ));
    await _refresh();
    return saved;
  }

  /// Saves an edited task (it must already have an id).
  Future<void> save(Task task) async {
    await _repository.update(task);
    await _refresh();
  }

  Future<void> setDone(Task task, bool done) async {
    if (task.isDone == done) return;
    await save(task.copyWith(isDone: done));
  }

  /// Deletes [task]. Returns it so the caller can offer "Undo" via
  /// [restore].
  Future<Task> delete(Task task) async {
    final id = task.id;
    if (id == null) throw ArgumentError.value(task, 'task', 'has no id');
    await _repository.delete(id);
    await _refresh();
    return task;
  }

  /// Puts back a task removed with [delete].
  ///
  /// It is re-inserted as a new row, so it gets a new id. Nothing refers
  /// to task ids long-term, so this is harmless and keeps the repository
  /// contract simple ("insert never takes an id").
  Future<Task> restore(Task deleted) async {
    final saved =
        await _repository.insert(deleted.withoutId());
    await _refresh();
    return saved;
  }

  Future<void> _refresh() async {
    _tasks = await _repository.getAll();
    _loadError = null;
    notifyListeners();
  }
}
