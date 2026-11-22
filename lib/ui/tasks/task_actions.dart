import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/geo_point.dart';
import '../../models/task.dart';
import '../../state/map_focus_controller.dart';
import '../../state/navigation_controller.dart';
import '../../state/task_list_controller.dart';
import '../common/confirm_dialog.dart';
import '../common/undo_snack_bar.dart';
import 'recycle_bin_page.dart';
import 'task_editor_page.dart';

/// User actions on tasks that more than one screen offers (the list page
/// and the map's quest details sheet). Keeping them in one place means
/// that editing, deleting and undo behave the same everywhere.

/// Opens the editor for [task] (or a new task when null) and applies the
/// result: save, create, or delete with undo. [location] pre-fills a new
/// task's location (long-press on the map).
Future<void> openTaskEditor(
  BuildContext context,
  Task? task, {
  GeoPoint? location,
}) async {
  final controller = context.read<TaskListController>();
  final result = await Navigator.of(context).push<TaskEditorResult>(
    MaterialPageRoute(
      builder: (_) => TaskEditorPage(initial: task, initialLocation: location),
    ),
  );
  if (result == null || !context.mounted) return;

  switch (result) {
    case TaskEditorSaved(
        :final title,
        :final description,
        :final dueAt,
        :final location,
        :final address,
      ):
      await runGuarded(context, () async {
        if (task == null) {
          await controller.add(
            title: title,
            description: description,
            dueAt: dueAt,
            location: location,
            address: address,
          );
        } else {
          await controller.save(task.copyWith(
            title: title,
            description: () => description,
            dueAt: () => dueAt,
            location: () => location,
            address: () => address,
          ));
        }
      });
    case TaskEditorDeleted():
      if (task != null) await deleteTaskWithUndo(context, task);
  }
}

/// Moves [task] to the recycle bin and shows a snackbar with Undo. Returns
/// whether it succeeded. (Nothing is destroyed: the bin keeps it for 30
/// days, PLAN.md D18.)
Future<bool> deleteTaskWithUndo(BuildContext context, Task task) async {
  final controller = context.read<TaskListController>();
  final messenger = ScaffoldMessenger.of(context);
  return runGuarded(context, () async {
    final deleted = await controller.moveToBin(task);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(undoSnackBar(
        message: 'Moved "${deleted.title}" to the recycle bin',
        onUndo: () => controller.restoreFromBin(deleted),
      ));
  });
}

/// Marks [task] done or not done, reporting failures in a snackbar.
Future<bool> setTaskDone(BuildContext context, Task task, bool done) {
  final controller = context.read<TaskListController>();
  return runGuarded(context, () => controller.setDone(task, done));
}

/// "Show on map": switches to the Map tab and asks the map to centre on
/// [task] and highlight it. Only offered for tasks with a location.
void showTaskOnMap(BuildContext context, Task task) {
  context.read<MapFocusController>().focusOn(task);
  context.read<NavigationController>().select(AppTab.map);
}

/// "Delete all completed tasks" (PLAN.md D18): asks for confirmation with
/// the exact wording the user specified, then moves every completed task
/// to the recycle bin and says how many were moved. "No" does nothing.
Future<void> deleteAllCompleted(BuildContext context) async {
  final controller = context.read<TaskListController>();
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await confirmDialog(
    context,
    title: 'Delete all completed tasks?',
    message: 'Are you sure? This will move all completed tasks to the '
        'recycle bin.',
    confirmLabel: 'Yes',
    cancelLabel: 'No',
  );
  if (!confirmed || !context.mounted) return;
  var moved = 0;
  final ok = await runGuarded(context, () async {
    moved = await controller.moveCompletedToBin();
  });
  if (!ok) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(moved == 1
          ? 'Moved 1 completed task to the recycle bin'
          : 'Moved $moved completed tasks to the recycle bin'),
    ));
}

/// Opens the recycle bin page.
Future<void> openRecycleBin(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const RecycleBinPage()),
  );
}

/// Runs a change and reports failures in a snackbar instead of crashing.
/// Returns whether it succeeded.
Future<bool> runGuarded(
    BuildContext context, Future<void> Function() action) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    return true;
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Something went wrong: $e')),
    );
    return false;
  }
}
