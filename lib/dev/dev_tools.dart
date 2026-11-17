// TEMPORARY developer tools, to be removed before the app is finished
// (see PLAN.md, "Before release").
//
// They exist only in debug builds (kDebugMode), so a release build never
// shows them. They let us check on the emulator what unit tests can't:
// how the real map and the quest markers actually look.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/geo_point.dart';
import '../state/navigation_controller.dart';
import '../state/task_list_controller.dart';

/// One hardcoded demo quest.
class DemoQuest {
  const DemoQuest(this.title,
      {this.at, this.dueInDays, this.done = false, this.description});

  final String title;
  final GeoPoint? at;

  /// Due date relative to today: 0 = today, -3 = three days ago.
  final int? dueInDays;
  final bool done;
  final String? description;
}

/// Demo quests in central Helsinki, chosen to show every marker state at
/// once, plus two list-only quests for the "tasks without locations"
/// badge.
abstract final class DemoQuests {
  /// Every demo quest's title starts with this, so they can be found and
  /// removed again without touching real quests.
  static const titlePrefix = '[Demo] ';

  static final all = <DemoQuest>[
    DemoQuest('Pick up parcel', // gold: open, no due date
        at: GeoPoint(60.1719, 24.9414),
        description: 'Central railway station'),
    DemoQuest('Return library books', // orange: due today
        at: GeoPoint(60.1738, 24.9380),
        dueInDays: 0,
        description: 'Oodi library'),
    DemoQuest('Pay parking fine', // red: overdue
        at: GeoPoint(60.1683, 24.9318),
        dueInDays: -3),
    DemoQuest('Buy coffee beans', // grey check: done
        at: GeoPoint(60.1675, 24.9525),
        done: true),
    DemoQuest('Visit Suomenlinna', // gold: due later
        at: GeoPoint(60.1454, 24.9881),
        dueInDays: 10),
    DemoQuest('Call the bank'), // no location
    DemoQuest('Water the plants'), // no location
  ];

  /// Adds all demo quests. Returns how many were added.
  static Future<int> add(TaskListController controller,
      {DateTime Function() clock = DateTime.now}) async {
    final now = clock();
    final today = DateTime(now.year, now.month, now.day);
    for (final q in all) {
      final due = q.dueInDays;
      final saved = await controller.add(
        title: '$titlePrefix${q.title}',
        description: q.description,
        dueAt: due == null ? null : today.add(Duration(days: due)),
        location: q.at,
      );
      if (q.done) await controller.setDone(saved, true);
    }
    return all.length;
  }

  /// Deletes every quest whose title starts with [titlePrefix]. Returns how
  /// many were removed.
  static Future<int> removeAll(TaskListController controller) async {
    final demo = controller.tasks
        .where((t) => t.title.startsWith(titlePrefix.trim()))
        .toList();
    for (final t in demo) {
      await controller.delete(t);
    }
    return demo.length;
  }
}

/// A bug icon for the list page's app bar that opens the developer tools.
/// Renders nothing in release builds.
class DevToolsButton extends StatelessWidget {
  const DevToolsButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Developer tools',
      icon: const Icon(Icons.bug_report_outlined),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => DevToolsSheet(hostContext: context),
      ),
    );
  }
}

class DevToolsSheet extends StatelessWidget {
  const DevToolsSheet({super.key, required this.hostContext});

  /// The page's context. The sheet closes itself before acting, so the
  /// actions and snackbars must use the page's context.
  final BuildContext hostContext;

  Future<void> _run(BuildContext sheetContext,
      Future<String> Function(TaskListController) action) async {
    final controller = hostContext.read<TaskListController>();
    final messenger = ScaffoldMessenger.of(hostContext);
    Navigator.pop(sheetContext);
    final message = await action(controller);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Developer tools (temporary, debug builds only)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Add demo quests and open the map'),
              onPressed: () => _run(context, (c) async {
                final n = await DemoQuests.add(c);
                if (hostContext.mounted) {
                  hostContext.read<NavigationController>().select(AppTab.map);
                }
                return 'Added $n demo quests';
              }),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Remove demo quests'),
              onPressed: () => _run(context, (c) async {
                final n = await DemoQuests.removeAll(c);
                return 'Removed $n demo quests';
              }),
            ),
          ],
        ),
      ),
    );
  }
}
