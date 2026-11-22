import '../../models/task_query.dart';
import '../formatting.dart';

/// User-facing names for the list's filter and sort options. Kept out of
/// the model, so the model stays free of UI text.
extension StatusFilterLabel on StatusFilter {
  String get label => switch (this) {
        StatusFilter.all => 'All',
        StatusFilter.notCompleted => 'Not completed',
        StatusFilter.completed => 'Completed',
        StatusFilter.overdue => 'Overdue',
      };
}

extension SortFieldLabel on SortField {
  String get label => switch (this) {
        SortField.title => 'Alphabetical',
        SortField.created => 'Date created',
        SortField.due => 'Due date',
        SortField.completed => 'Date completed',
      };
}

/// The three date filters, so the UI can treat them uniformly.
enum DateFilterField {
  created('Date created', 'Created'),
  due('Due date', 'Due'),
  completed('Date completed', 'Completed');

  const DateFilterField(this.label, this.shortLabel);

  final String label;

  /// Used on the compact chips under the search bar.
  final String shortLabel;

  DayRange of(TaskQuery q) => switch (this) {
        DateFilterField.created => q.created,
        DateFilterField.due => q.due,
        DateFilterField.completed => q.completed,
      };

  TaskQuery set(TaskQuery q, DayRange range) => switch (this) {
        DateFilterField.created => q.copyWith(created: range),
        DateFilterField.due => q.copyWith(due: range),
        DateFilterField.completed => q.copyWith(completed: range),
      };
}

/// Describes a range for a chip, e.g. "Due: 01-12-2026 – 15-12-2026",
/// "Due: from 01-12-2026" or "Due: until 15-12-2026".
String describeRange(DateFilterField field, DayRange range) {
  final f = range.from, t = range.to;
  final text = f != null && t != null
      ? '${formatDate(f)} – ${formatDate(t)}'
      : f != null
          ? 'from ${formatDate(f)}'
          : 'until ${formatDate(t!)}';
  return '${field.shortLabel}: $text';
}
