import 'package:questmark/data/task_repository.dart';
import 'package:questmark/models/task.dart';

/// In-memory [TaskRepository] for state and widget tests.
///
/// Widget tests run in a fake-async zone where real database I/O would
/// hang, so they use this fake instead of SQLite. It follows the same
/// contract and ordering as [SqfliteTaskRepository], and that real
/// implementation is covered by its own tests against a real (in-memory)
/// SQLite database.
class FakeTaskRepository implements TaskRepository {
  FakeTaskRepository([Iterable<Task> seed = const []]) {
    for (final t in seed) {
      final id = t.id ?? ++_lastId;
      if (id > _lastId) _lastId = id;
      _rows[id] = t.copyWith(id: id);
    }
  }

  final Map<int, Task> _rows = {};
  int _lastId = 0;

  /// If set, the next [getAll] throws this (once).
  Object? failNextLoad;

  /// If set, the next insert/update/delete throws this (once).
  Object? failNextWrite;

  /// Number of write operations performed (for "did it save?" checks).
  int writes = 0;

  @override
  Future<List<Task>> getAll() async {
    final err = failNextLoad;
    if (err != null) {
      failNextLoad = null;
      throw err;
    }
    return _sorted(_rows.values);
  }

  @override
  Future<List<Task>> getWithLocation() async =>
      _sorted(_rows.values.where((t) => t.hasLocation));

  @override
  Future<Task?> getById(int id) async => _rows[id];

  @override
  Future<Task> insert(Task task) async {
    _maybeFailWrite();
    if (task.id != null) throw ArgumentError('new tasks have no id');
    final saved = task.copyWith(id: ++_lastId);
    _rows[saved.id!] = saved;
    return saved;
  }

  @override
  Future<void> update(Task task) async {
    _maybeFailWrite();
    final id = task.id;
    if (id == null) throw ArgumentError('cannot update unsaved task');
    if (!_rows.containsKey(id)) throw TaskNotFoundException(id);
    _rows[id] = task;
  }

  @override
  Future<bool> delete(int id) async {
    _maybeFailWrite();
    return _rows.remove(id) != null;
  }

  void _maybeFailWrite() {
    final err = failNextWrite;
    if (err != null) {
      failNextWrite = null;
      throw err;
    }
    writes++;
  }

  /// Same rules as the SQL ORDER BY in SqfliteTaskRepository.
  static List<Task> _sorted(Iterable<Task> tasks) {
    final list = tasks.toList();
    list.sort((a, b) {
      if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
      final ad = a.dueAt, bd = b.dueAt;
      if ((ad == null) != (bd == null)) return ad == null ? 1 : -1;
      if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
      final c = b.createdAt.compareTo(a.createdAt);
      if (c != 0) return c;
      return b.id!.compareTo(a.id!);
    });
    return list;
  }
}
