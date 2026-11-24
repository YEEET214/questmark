import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/task.dart';
import '../../state/task_list_controller.dart';
import '../common/confirm_dialog.dart';
import '../formatting.dart';
import 'task_actions.dart';

/// Whole days left before a binned task is deleted for good, rounded up,
/// so "less than a day" still reads as 1. Never negative.
int binDaysLeft(DateTime expiresAt, DateTime now) {
  final hours = expiresAt.difference(now).inHours;
  if (hours <= 0) return 0;
  return (hours / 24).ceil();
}

/// The recycle bin (PLAN.md D18): deleted quests stay here for 30 days.
/// Each can be restored (it comes back exactly as it was) or deleted
/// permanently. "Empty bin" removes them all for good.
///
/// Opening the page also removes anything older than 30 days.
class RecycleBinPage extends StatefulWidget {
  const RecycleBinPage({super.key, this.clock = DateTime.now});

  /// Used for "days left". Injectable for tests.
  final DateTime Function() clock;

  @override
  State<RecycleBinPage> createState() => _RecycleBinPageState();
}

class _RecycleBinPageState extends State<RecycleBinPage> {
  @override
  void initState() {
    super.initState();
    // The "when the bin is opened" purge (the other one runs on app start).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<TaskListController>().purgeExpiredBin();
    });
  }

  Future<void> _restore(Task task) async {
    final controller = context.read<TaskListController>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await runGuarded(context, () => controller.restoreFromBin(task));
    if (ok) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Restored "${task.title}"')));
    }
  }

  Future<void> _deleteForever(Task task) async {
    final controller = context.read<TaskListController>();
    final confirmed = await confirmDialog(
      context,
      title: 'Delete permanently?',
      message: '"${task.title}" will be deleted for good. '
          'This can\'t be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await runGuarded(context, () => controller.deletePermanently(task));
  }

  Future<void> _emptyBin() async {
    final controller = context.read<TaskListController>();
    final messenger = ScaffoldMessenger.of(context);
    final count = controller.binTasks.length;
    final confirmed = await confirmDialog(
      context,
      title: 'Empty the recycle bin?',
      message: count == 1
          ? '1 quest will be deleted for good. This can\'t be undone.'
          : '$count quests will be deleted for good. This can\'t be undone.',
      confirmLabel: 'Empty bin',
      cancelLabel: 'Cancel',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final ok = await runGuarded(context, controller.emptyBin);
    if (ok) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Recycle bin emptied')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TaskListController>();
    final binned = controller.binTasks;
    final now = widget.clock();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recycle bin'),
        actions: [
          IconButton(
            tooltip: 'Empty recycle bin',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: binned.isEmpty ? null : _emptyBin,
          ),
        ],
      ),
      body: binned.isEmpty
          ? Center(
              // Scrolls if a large font size makes it taller than the
              // screen (D30).
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_outline,
                        size: 64, color: theme.colorScheme.primary),
                    const SizedBox(height: 16),
                    Text('The recycle bin is empty',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const Text(
                      'Deleted quests are kept here for 30 days.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    'Quests here are deleted for good 30 days after they '
                    'were deleted.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                for (final t in binned)
                  ListTile(
                    key: ValueKey('bin-${t.id}'),
                    title: Text(t.title),
                    subtitle: Text(_subtitle(controller, t, now)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Restore',
                          icon: const Icon(Icons.restore_from_trash_outlined),
                          onPressed: () => _restore(t),
                        ),
                        IconButton(
                          tooltip: 'Delete permanently',
                          icon: const Icon(Icons.delete_forever_outlined),
                          onPressed: () => _deleteForever(t),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  static String _subtitle(TaskListController c, Task t, DateTime now) {
    final days = binDaysLeft(c.expiresAt(t), now);
    final left = days == 1 ? '1 day left' : '$days days left';
    return 'Deleted ${formatDate(t.deletedAt!.toLocal())} · $left';
  }
}
