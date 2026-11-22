import 'package:flutter/foundation.dart';

import 'task.dart';

/// Which tasks to show by completion state (PLAN.md D16).
enum StatusFilter { all, notCompleted, completed, overdue }

/// What to sort the list by. Each can be ascending or descending.
enum SortField { title, created, due, completed }

/// An inclusive range of local calendar days, open at either end:
/// * only [from] means "on or after";
/// * only [to] means "on or before";
/// * both means "between" (both days included);
/// * neither means "any day" (no filtering).
@immutable
class DayRange {
  const DayRange.any()
      : from = null,
        to = null;

  /// Creates a range. Times of day are dropped; only the calendar day
  /// counts. Throws [ArgumentError] if [from] is after [to].
  DayRange({DateTime? from, DateTime? to})
      : from = _day(from),
        to = _day(to) {
    final f = this.from, t = this.to;
    if (f != null && t != null && f.isAfter(t)) {
      throw ArgumentError('from ($f) is after to ($t)');
    }
  }

  final DateTime? from;
  final DateTime? to;

  bool get isAny => from == null && to == null;

  /// Whether [time]'s local calendar day lies in the range.
  bool contains(DateTime time) {
    final day = _day(time)!;
    final f = from, t = to;
    if (f != null && day.isBefore(f)) return false;
    if (t != null && day.isAfter(t)) return false;
    return true;
  }

  static DateTime? _day(DateTime? t) {
    if (t == null) return null;
    final l = t.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  @override
  bool operator ==(Object other) =>
      other is DayRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'DayRange($from..$to)';
}

/// Search, filters and sort for the task list, as one immutable value
/// (PLAN.md D16).
///
/// [apply] is a pure function: give it tasks and "now", get back the tasks
/// to show, in order. All the list's filtering rules live here, so they
/// can be unit-tested without any widgets.
@immutable
class TaskQuery {
  const TaskQuery({
    this.search = '',
    this.status = StatusFilter.all,
    this.created = const DayRange.any(),
    this.due = const DayRange.any(),
    this.completed = const DayRange.any(),
    this.sortField = SortField.due,
    this.ascending = true,
  });

  /// Free text; every word must appear in the title or description
  /// (case-insensitive).
  final String search;
  final StatusFilter status;
  final DayRange created;
  final DayRange due;
  final DayRange completed;
  final SortField sortField;
  final bool ascending;

  /// Whether anything narrows the list (the sort doesn't count).
  bool get hasFilters =>
      search.trim().isNotEmpty ||
      status != StatusFilter.all ||
      hasDateFilters;

  bool get hasDateFilters => !created.isAny || !due.isAny || !completed.isAny;

  /// Removes every filter and the search, keeping the sort.
  TaskQuery clearFilters() =>
      TaskQuery(sortField: sortField, ascending: ascending);

  TaskQuery copyWith({
    String? search,
    StatusFilter? status,
    DayRange? created,
    DayRange? due,
    DayRange? completed,
    SortField? sortField,
    bool? ascending,
  }) =>
      TaskQuery(
        search: search ?? this.search,
        status: status ?? this.status,
        created: created ?? this.created,
        due: due ?? this.due,
        completed: completed ?? this.completed,
        sortField: sortField ?? this.sortField,
        ascending: ascending ?? this.ascending,
      );

  /// Filters and sorts [tasks].
  ///
  /// Tasks whose id is in [keepVisible] skip the *status* filter only. A
  /// task you just ticked under "Not completed" stays in view (struck
  /// through), so an accidental tick is easy to undo. Search and date
  /// filters still apply to them.
  List<Task> apply(
    Iterable<Task> tasks, {
    required DateTime now,
    Set<int> keepVisible = const {},
  }) {
    final words = search
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    final result = tasks.where((t) {
      if (!keepVisible.contains(t.id) && !_matchesStatus(t, now)) return false;
      if (!_matchesSearch(t, words)) return false;
      if (!created.isAny && !created.contains(t.createdAt)) return false;
      if (!due.isAny) {
        final d = t.dueAt;
        if (d == null || !due.contains(d)) return false;
      }
      if (!completed.isAny) {
        final c = t.completedAt;
        if (c == null || !completed.contains(c)) return false;
      }
      return true;
    }).toList();

    result.sort(_compare);
    return result;
  }

  bool _matchesStatus(Task t, DateTime now) => switch (status) {
        StatusFilter.all => true,
        StatusFilter.notCompleted => !t.isDone,
        StatusFilter.completed => t.isDone,
        StatusFilter.overdue => t.isOverdue(now),
      };

  static bool _matchesSearch(Task t, List<String> words) {
    if (words.isEmpty) return true;
    final text = '${t.title} ${t.description ?? ''}'.toLowerCase();
    return words.every(text.contains);
  }

  /// Sort by the chosen field and direction. Tasks with no value for the
  /// field (no due date / no completion date) go last in *both*
  /// directions. Ties fall back to newest created first, then highest id,
  /// so the order is always stable.
  int _compare(Task a, Task b) {
    final ka = _key(a), kb = _key(b);
    if (ka != null || kb != null) {
      if (ka == null) return 1;
      if (kb == null) return -1;
      final c = ka.compareTo(kb);
      if (c != 0) return ascending ? c : -c;
    }
    final c = b.createdAt.compareTo(a.createdAt);
    if (c != 0) return c;
    return (b.id ?? 0).compareTo(a.id ?? 0);
  }

  Comparable<Object>? _key(Task t) => switch (sortField) {
        SortField.title => t.title.toLowerCase(),
        SortField.created => t.createdAt,
        SortField.due => t.dueAt,
        SortField.completed => t.completedAt,
      } as Comparable<Object>?;

  @override
  bool operator ==(Object other) =>
      other is TaskQuery &&
      other.search == search &&
      other.status == status &&
      other.created == created &&
      other.due == due &&
      other.completed == completed &&
      other.sortField == sortField &&
      other.ascending == ascending;

  @override
  int get hashCode =>
      Object.hash(search, status, created, due, completed, sortField, ascending);
}
