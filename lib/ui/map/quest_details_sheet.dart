import 'package:flutter/material.dart';

import '../../models/task.dart';
import '../formatting.dart';
import 'quest_marker.dart';

/// Bottom sheet shown when a quest marker is tapped: the quest's details
/// plus quick actions.
///
/// It only reports what was pressed through callbacks. The map page owns
/// the actual actions, which it shares with the list page (task_actions).
class QuestDetailsSheet extends StatelessWidget {
  const QuestDetailsSheet({
    super.key,
    required this.task,
    required this.kind,
    required this.onToggleDone,
    required this.onEdit,
  });

  final Task task;
  final QuestMarkerKind kind;
  final VoidCallback onToggleDone;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = QuestMarkerColors.of(kind);
    final description = task.description;
    final address = task.address;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  task.isDone ? Icons.check_circle : Icons.priority_high,
                  color: colors.fill,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(task.title, style: theme.textTheme.titleLarge),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_statusLine(), style: TextStyle(color: colors.fill)),
            if (description != null) ...[
              const SizedBox(height: 12),
              Text(description),
            ],
            if (address != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text(address)),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: onToggleDone,
                    icon: Icon(task.isDone ? Icons.undo : Icons.check),
                    label: Text(task.isDone ? 'Reopen' : 'Complete'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _statusLine() {
    final due = task.dueAt;
    final date = due == null ? null : formatDate(due.toLocal());
    return switch (kind) {
      QuestMarkerKind.done => 'Completed',
      QuestMarkerKind.overdue => 'Overdue · $date',
      QuestMarkerKind.dueSoon => 'Due soon · $date',
      QuestMarkerKind.active => date == null ? 'Open quest' : 'Due $date',
    };
  }
}
