import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../dev/dev_tools.dart';
import '../../models/task.dart';
import '../../state/task_list_controller.dart';
import '../formatting.dart';
import 'task_actions.dart';

/// Shows all tasks: active ones first, then a "Completed" section.
///
/// * Tap a quest to edit it.
/// * Tick the checkbox to complete it (or untick to reopen).
/// * Swipe left to delete it, with Undo in the snackbar.
/// * The + button creates a new quest.
class TaskListPage extends StatelessWidget {
  const TaskListPage({super.key, this.clock = DateTime.now});

  /// Used for the "overdue" check. Injectable for tests.
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TaskListController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quests'),
        // TEMPORARY: debug-only developer tools (removed before release).
        actions: const [DevToolsButton()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openTaskEditor(context, null),
        icon: const Icon(Icons.add),
        label: const Text('New quest'),
      ),
      body: _buildBody(context, controller),
    );
  }

  Widget _buildBody(BuildContext context, TaskListController controller) {
    if (!controller.hasLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.loadError != null) {
      return _Message(
        icon: Icons.error_outline,
        title: "Couldn't load your quests",
        action: FilledButton(
          onPressed: controller.load,
          child: const Text('Try again'),
        ),
      );
    }
    if (controller.tasks.isEmpty) {
      return const _Message(
        icon: Icons.explore_outlined,
        title: 'No quests yet',
        subtitle: 'Tap "New quest" to add your first one.',
      );
    }

    final now = clock();
    final active = controller.activeTasks;
    final completed = controller.completedTasks;

    return ListView(
      // Leaves room so the last tile isn't hidden behind the FAB.
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        for (final t in active) _TaskTile(task: t, now: now),
        if (completed.isNotEmpty) ...[
          _SectionHeader('Completed (${completed.length})'),
          for (final t in completed) _TaskTile(task: t, now: now),
        ],
      ],
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.now});

  final Task task;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dismissible(
      key: ValueKey('task-${task.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Icon(Icons.delete, color: theme.colorScheme.onErrorContainer),
      ),
      // The delete happens in confirmDismiss, not onDismissed. Flutter
      // requires a dismissed item to leave the tree immediately, but our
      // delete is asynchronous. Awaiting it here means the list is already
      // rebuilt without the item when the animation ends, and if the
      // delete fails the tile simply slides back.
      confirmDismiss: (_) => deleteTaskWithUndo(context, task),
      child: ListTile(
        leading: Checkbox(
          value: task.isDone,
          onChanged: (done) => setTaskDone(context, task, done ?? false),
        ),
        title: Text(
          task.title,
          style: task.isDone
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : null,
        ),
        subtitle: _subtitle(context),
        onTap: () => openTaskEditor(context, task),
      ),
    );
  }

  Widget? _subtitle(BuildContext context) {
    final theme = Theme.of(context);
    final parts = <InlineSpan>[];

    final due = task.dueAt;
    if (due != null) {
      final date = formatDate(due.toLocal());
      final overdue = task.isOverdue(now);
      parts.add(TextSpan(
        text: overdue ? 'Overdue · $date' : 'Due $date',
        style: overdue
            ? TextStyle(
                color: theme.colorScheme.error, fontWeight: FontWeight.w600)
            : null,
      ));
    }
    final description = task.description;
    if (description != null) {
      if (parts.isNotEmpty) parts.add(const TextSpan(text: '\n'));
      parts.add(TextSpan(text: description));
    }
    if (parts.isEmpty) return null;
    return Text.rich(
      TextSpan(children: parts),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(text,
          style: theme.textTheme.titleSmall
              ?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(title,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
