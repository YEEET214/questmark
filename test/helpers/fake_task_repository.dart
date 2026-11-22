import 'package:questmark/data/task_repository.dart';
import 'package:questmark/models/task.dart';

/// In-memory [TaskRepository] for state and widget tests.
///
/// Widget tests run in a fake-async zone where real database I/O would
/// hang, so they use this fake instead of SQLite. It follows the same
/// contract and ordering as [SqfliteTaskRepository] (including the recycle
/// bin), and that real implementation is covered by its own tests against
/// a real (in-memory) SQLite database.
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

  /// If set, the next write (insert/update/bin/delete) throws this (once).
  Object? failNextWrite;

  /// Number of write operations performed (for "did it save?" checks).
  int writes = 0;

  Iterable<Task> get _live => _rows.values.where((t) => !t.isInBin);
  Iterable<Task> get _bin => _rows.values.where((t) => t.isInBin);

  @override
  Future<List<Task>> getAll() async {
    final err = failNextLoad;
    if (err != null) {
      failNextLoad = null;
      throw err;
    }
    return _sorted(_live);
  }

  @override
  Future<List<Task>> getWithLocation() async =>
      _sorted(_live.where((t) => t.hasLocation));

  @override
  Future<List<Task>> getBin() async {
    final list = _bin.toList()
      ..sort((a, b) {
        final c = b.deletedAt!.compareTo(a.deletedAt!);
        return c != 0 ? c : b.id!.compareTo(a.id!);
      });
    return list;
  }

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
  Future<bool> moveToBin(int id, DateTime at) async {
    _maybeFailWrite();
    final t = _rows[id];
    if (t == null || t.isInBin) return false;
    _rows[id] = t.copyWith(deletedAt: () => at);
    return true;
  }

  @override
  Future<int> moveCompletedToBin(DateTime at) async {
    _maybeFailWrite();
    final done = _live.where((t) => t.isDone).toList();
    for (final t in done) {
      _rows[t.id!] = t.copyWith(deletedAt: () => at);
    }
    return done.length;
  }

  @override
  Future<bool> restoreFromBin(int id) async {
    _maybeFailWrite();
    final t = _rows[id];
    if (t == null || !t.isInBin) return false;
    _rows[id] = t.copyWith(deletedAt: () => null);
    return true;
  }

  @override
  Future<bool> deletePermanently(int id) async {
    _maybeFailWrite();
    return _rows.remove(id) != null;
  }

  @override
  Future<int> emptyBin() async {
    _maybeFailWrite();
    final ids = _bin.map((t) => t.id!).toList();
    ids.forEach(_rows.remove);
    return ids.length;
  }

  @override
  Future<int> purgeBin({required DateTime deletedBefore}) async {
    final ids = _bin
        .where((t) => t.deletedAt!.isBefore(deletedBefore))
        .map((t) => t.id!)
        .toList();
    ids.forEach(_rows.remove);
    return ids.length;
  }

  void _maybeFailWrite() {
    final err = failNextWrite;
    if (err != null) {
      failNextWrite = null;
      throw err;
    }
    writes++;
  }

  /// Same rule as the SQL ORDER BY in SqfliteTaskRepository: newest
  /// created first, then highest id.
  static List<Task> _sorted(Iterable<Task> tasks) {
    final list = tasks.toList();
    list.sort((a, b) {
      final c = b.createdAt.compareTo(a.createdAt);
      if (c != 0) return c;
      return b.id!.compareTo(a.id!);
    });
    return list;
  }
}
