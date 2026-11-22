import 'package:flutter/foundation.dart';

import '../models/task_query.dart';

/// How the task list is currently viewed: the [TaskQuery] (search, filters,
/// sort), plus the tasks kept visible after being ticked (PLAN.md D16).
///
/// Kept apart from [TaskListController] (the data), because this is only
/// about presentation. It's app-wide, so the filter sheet (a separate
/// route) can reach it, and so the query survives switching tabs during a
/// session.
class TaskListViewController extends ChangeNotifier {
  TaskQuery _query = const TaskQuery();
  final Set<int> _keepVisible = {};

  TaskQuery get query => _query;

  /// Ids of tasks ticked or unticked since the filter was last changed.
  /// They stay in view even if the status filter would now hide them.
  Set<int> get keepVisible => Set.unmodifiable(_keepVisible);

  /// Replaces the query. When the *filters* change (not only the sort),
  /// the kept-visible tasks are released, because "changing the filter"
  /// is when a ticked task may leave the list.
  void setQuery(TaskQuery query) {
    if (query == _query) return;
    final filtersChanged = !_sameFilters(query, _query);
    _query = query;
    if (filtersChanged) _keepVisible.clear();
    notifyListeners();
  }

  /// Remembers that [taskId] was just ticked or unticked here.
  void keepTaskVisible(int taskId) {
    if (_keepVisible.add(taskId)) notifyListeners();
  }

  /// Called when the user leaves the list page.
  void releaseKeptTasks() {
    if (_keepVisible.isEmpty) return;
    _keepVisible.clear();
    notifyListeners();
  }

  static bool _sameFilters(TaskQuery a, TaskQuery b) =>
      a.search == b.search &&
      a.status == b.status &&
      a.created == b.created &&
      a.due == b.due &&
      a.completed == b.completed;
}
