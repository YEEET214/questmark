import 'package:sqflite/sqflite.dart';

import '../models/task.dart';

/// Thrown when updating or reading a task id that doesn't exist.
class TaskNotFoundException implements Exception {
  TaskNotFoundException(this.id);
  final int id;
  @override
  String toString() => 'TaskNotFoundException: no task with id $id';
}

/// Storage for tasks, including the recycle bin (PLAN.md D18).
///
/// This is an interface, so the state layer and widget tests can use an
/// in-memory fake. The real implementation is [SqfliteTaskRepository].
///
/// **Recycle bin:** deleting is a *soft* delete. [moveToBin] stamps
/// `deleted_at`, and such tasks are left out of [getAll] and
/// [getWithLocation] (so out of the list and the map) and listed by
/// [getBin] instead. Only [deletePermanently], [emptyBin] and [purgeBin]
/// remove rows for good.
///
/// Ordering: [getAll] and [getWithLocation] return newest created first.
/// This is only a stable default; the list page applies the user's chosen
/// sort (TaskQuery, PLAN.md D16). [getBin] returns the most recently
/// deleted first.
abstract interface class TaskRepository {
  /// Every task that is not in the recycle bin.
  Future<List<Task>> getAll();

  /// Tasks not in the bin that have a location, i.e. the ones the map shows.
  Future<List<Task>> getWithLocation();

  /// Tasks in the recycle bin, most recently deleted first.
  Future<List<Task>> getBin();

  /// Returns `null` if there's no task with [id]. Finds tasks in the bin
  /// too.
  Future<Task?> getById(int id);

  /// Stores a new task and returns it with its database id set.
  /// Throws [ArgumentError] if [task] already has an id.
  Future<Task> insert(Task task);

  /// Saves changes to an existing task.
  /// Throws [ArgumentError] if [task] has no id, or
  /// [TaskNotFoundException] if no task has that id.
  Future<void> update(Task task);

  /// Moves a task to the recycle bin, stamped with [at]. Returns `false`
  /// if there's no such task, or it is already in the bin.
  Future<bool> moveToBin(int id, DateTime at);

  /// Moves every completed task that isn't already in the bin to the bin,
  /// in one statement. Returns how many were moved.
  Future<int> moveCompletedToBin(DateTime at);

  /// Takes a task back out of the bin, unchanged and with the same id.
  /// Returns `false` if it wasn't in the bin.
  Future<bool> restoreFromBin(int id);

  /// Removes a task for good. Returns `false` if it didn't exist.
  Future<bool> deletePermanently(int id);

  /// Permanently removes every task in the bin. Returns how many.
  Future<int> emptyBin();

  /// Permanently removes bin tasks deleted before [deletedBefore] (the
  /// 30-day rule). Returns how many.
  Future<int> purgeBin({required DateTime deletedBefore});
}

class SqfliteTaskRepository implements TaskRepository {
  SqfliteTaskRepository(this._db);

  final Database _db;

  static const _table = 'tasks';

  static const _notDeleted = '${Task.colDeletedAt} IS NULL';
  static const _deleted = '${Task.colDeletedAt} IS NOT NULL';

  static const _orderBy = '${Task.colCreatedAt} DESC, ${Task.colId} DESC';
  static const _binOrderBy = '${Task.colDeletedAt} DESC, ${Task.colId} DESC';

  @override
  Future<List<Task>> getAll() => _query(where: _notDeleted);

  @override
  Future<List<Task>> getWithLocation() =>
      _query(where: '$_notDeleted AND ${Task.colLatitude} IS NOT NULL');

  @override
  Future<List<Task>> getBin() => _query(where: _deleted, orderBy: _binOrderBy);

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
  Future<bool> moveToBin(int id, DateTime at) async {
    final changed = await _db.update(
      _table,
      {Task.colDeletedAt: at.millisecondsSinceEpoch},
      where: '${Task.colId} = ? AND $_notDeleted',
      whereArgs: [id],
    );
    return changed > 0;
  }

  @override
  Future<int> moveCompletedToBin(DateTime at) => _db.update(
        _table,
        {Task.colDeletedAt: at.millisecondsSinceEpoch},
        where: '${Task.colIsDone} = 1 AND $_notDeleted',
      );

  @override
  Future<bool> restoreFromBin(int id) async {
    final changed = await _db.update(
      _table,
      {Task.colDeletedAt: null},
      where: '${Task.colId} = ? AND $_deleted',
      whereArgs: [id],
    );
    return changed > 0;
  }

  @override
  Future<bool> deletePermanently(int id) async {
    final deleted = await _db
        .delete(_table, where: '${Task.colId} = ?', whereArgs: [id]);
    return deleted > 0;
  }

  @override
  Future<int> emptyBin() => _db.delete(_table, where: _deleted);

  @override
  Future<int> purgeBin({required DateTime deletedBefore}) => _db.delete(
        _table,
        where: '$_deleted AND ${Task.colDeletedAt} < ?',
        whereArgs: [deletedBefore.millisecondsSinceEpoch],
      );

  Future<List<Task>> _query({String? where, String orderBy = _orderBy}) async {
    final rows = await _db.query(_table, where: where, orderBy: orderBy);
    return rows.map(Task.fromMap).toList(growable: false);
  }
}
