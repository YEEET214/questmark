import 'package:flutter/material.dart';

import '../../models/task_query.dart';
import '../formatting.dart';
import 'query_labels.dart';

/// Bottom sheet for the date filters (PLAN.md D16): date created, due date
/// and date completed, each with an optional "From" and "To" day:
/// * only From = on or after that day;
/// * only To = on or before that day;
/// * both = between them (both days included).
///
/// It edits a draft copy and returns the new query on "Apply", or null if
/// dismissed, so nothing changes until the user confirms.
class TaskFilterSheet extends StatefulWidget {
  const TaskFilterSheet({super.key, required this.initial});

  final TaskQuery initial;

  /// Shows the sheet and returns the edited query, or null if cancelled.
  static Future<TaskQuery?> show(BuildContext context, TaskQuery initial) {
    return showModalBottomSheet<TaskQuery>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => TaskFilterSheet(initial: initial),
    );
  }

  @override
  State<TaskFilterSheet> createState() => _TaskFilterSheetState();
}

class _TaskFilterSheetState extends State<TaskFilterSheet> {
  late TaskQuery _draft = widget.initial;

  static final _firstDay = DateTime(2000);
  static final _lastDay = DateTime(2100, 12, 31);

  Future<void> _pick(DateFilterField field, {required bool isFrom}) async {
    final range = field.of(_draft);
    final today = DateTime.now();
    // Keep the range valid: "From" can't be after "To" and vice versa.
    final first = isFrom ? _firstDay : (range.from ?? _firstDay);
    final last = isFrom ? (range.to ?? _lastDay) : _lastDay;
    var initial = (isFrom ? range.from : range.to) ?? today;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: '${field.label}: ${isFrom ? 'from' : 'to'}',
    );
    if (picked == null) return;
    setState(() {
      _draft = field.set(
        _draft,
        isFrom
            ? DayRange(from: picked, to: range.to)
            : DayRange(from: range.from, to: picked),
      );
    });
  }

  void _clear(DateFilterField field, {required bool isFrom}) {
    final range = field.of(_draft);
    setState(() {
      _draft = field.set(
        _draft,
        isFrom
            ? DayRange(to: range.to)
            : DayRange(from: range.from),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Filter by date', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Set a From day, a To day, or both. Both days are included.',
              style: theme.textTheme.bodySmall,
            ),
            for (final field in DateFilterField.values) ...[
              const SizedBox(height: 16),
              Text(field.label, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _dayButton(field, isFrom: true)),
                  const SizedBox(width: 8),
                  Expanded(child: _dayButton(field, isFrom: false)),
                ],
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                TextButton(
                  onPressed: _draft.hasDateFilters
                      ? () => setState(() => _draft = _draft.copyWith(
                            created: const DayRange.any(),
                            due: const DayRange.any(),
                            completed: const DayRange.any(),
                          ))
                      : null,
                  child: const Text('Clear dates'),
                ),
                const Spacer(),
                FilledButton(
                  key: const Key('applyFiltersButton'),
                  onPressed: () => Navigator.pop(context, _draft),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayButton(DateFilterField field, {required bool isFrom}) {
    final range = field.of(_draft);
    final day = isFrom ? range.from : range.to;
    final label = isFrom ? 'From' : 'To';
    final key = '${field.name}-${isFrom ? 'from' : 'to'}';
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            key: Key(key),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: () => _pick(field, isFrom: isFrom),
            // Shrinks the text instead of wrapping it onto several lines
            // on narrow phones.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                day == null ? label : '$label ${formatDate(day)}',
                maxLines: 1,
              ),
            ),
          ),
        ),
        if (day != null)
          IconButton(
            key: Key('$key-clear'),
            tooltip: 'Clear ${label.toLowerCase()} date',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => _clear(field, isFrom: isFrom),
          ),
      ],
    );
  }
}
