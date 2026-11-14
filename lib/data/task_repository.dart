import 'package:sqflite/sqflite.dart';

import '../models/task.dart';

/// Thrown when updating or reading a task id that doesn't exist.
class TaskNotFoundException implements Exception {
  TaskNotFoundException(this.id);
  final int id;
  @override
  String toString() => 'TaskNotFoundException: no task with id $id';
}

/// Storage for tasks.
///
/// This is an interface, so the state layer and widget tests can use an
/// in-memory fake. The real implementation is [SqfliteTaskRepository].
///
/// List ordering (used by [getAll] and [getWithLocation]):
/// 1. active tasks before completed ones;
/// 2. tasks with a due date first, earliest due first;
/// 3. then newest created first.
abstract interface class TaskRepository {
  Future<List<Task>> getAll();

  /// Only tasks that have a location, i.e. the ones the map shows.
  Future<List<Task>> getWithLocation();

  /// Returns `null` if there's no task with [id].
  Future<Task?> getById(int id);

  /// Stores a new task and returns it with its database id set.
  /// Throws [ArgumentError] if [task] already has an id.
  Future<Task> insert(Task task);

  /// Saves changes to an existing task.
  /// Throws [ArgumentError] if [task] has no id, or
  /// [TaskNotFoundException] if no task has that id.
  Future<void> update(Task task);

  /// Deletes the task. Returns `false` if it didn't exist.
  Future<bool> delete(int id);
}

class SqfliteTaskRepository implements TaskRepository {
  SqfliteTaskRepository(this._db);

  final Database _db;

  static const _table = 'tasks';

  static const _orderBy = '${Task.colIsDone} ASC, '
      '${Task.colDueAt} IS NULL ASC, '
      '${Task.colDueAt} ASC, '
      '${Task.colCreatedAt} DESC, '
      '${Task.colId} DESC';

  @override
  Future<List<Task>> getAll() => _query();

  @override
  Future<List<Task>> getWithLocation() =>
      _query(where: '${Task.colLatitude} IS NOT NULL');

  @override
  Future<Task?> getById(int id) async {
    final rows = await _db.query(_table,
        where: '${Task.colId} = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Task.fromMap(rows.first);
  }

  @override
  Future<Task> insert(Task task) async {
    if (task.id != null) {
      throw ArgumentError.value(task.id, 'task.id', 'new tasks have no id');
    }
    final id = await _db.insert(_table, task.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort);
    return task.copyWith(id: id);
  }

  @override
  Future<void> update(Task task) async {
    final id = task.id;
    if (id == null) {
      throw ArgumentError.value(null, 'task.id', 'cannot update unsaved task');
    }
    final changed = await _db.update(_table, task.toMap(),
        where: '${Task.colId} = ?', whereArgs: [id]);
    if (changed == 0) throw TaskNotFoundException(id);
  }

  @override
  Future<bool> delete(int id) async {
    final deleted = await _db
        .delete(_table, where: '${Task.colId} = ?', whereArgs: [id]);
    return deleted > 0;
  }

  Future<List<Task>> _query({String? where}) async {
    final rows = await _db.query(_table, where: where, orderBy: _orderBy);
    return rows.map(Task.fromMap).toList(growable: false);
  }
}
