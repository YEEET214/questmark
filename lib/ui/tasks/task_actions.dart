import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/task.dart';
import '../../state/map_focus_controller.dart';
import '../../state/navigation_controller.dart';
import '../../state/task_list_controller.dart';
import 'task_editor_page.dart';

/// User actions on tasks that more than one screen offers (the list page
/// and the map's quest details sheet). Keeping them in one place means
/// that editing, deleting and undo behave the same everywhere.

/// Opens the editor for [task] (or a new task when null) and applies the
/// result: save, create, or delete with undo.
Future<void> openTaskEditor(BuildContext context, Task? task) async {
  final controller = context.read<TaskListController>();
  final result = await Navigator.of(context).push<TaskEditorResult>(
    MaterialPageRoute(builder: (_) => TaskEditorPage(initial: task)),
  );
  if (result == null || !context.mounted) return;

  switch (result) {
    case TaskEditorSaved(:final title, :final description, :final dueAt):
      await runGuarded(context, () async {
        if (task == null) {
          await controller.add(
              title: title, description: description, dueAt: dueAt);
        } else {
          await controller.save(task.copyWith(
            title: title,
            description: () => description,
            dueAt: () => dueAt,
          ));
        }
      });
    case TaskEditorDeleted():
      if (task != null) await deleteTaskWithUndo(context, task);
  }
}

/// Deletes [task] and shows a snackbar with Undo. Returns whether the
/// delete succeeded.
Future<bool> deleteTaskWithUndo(BuildContext context, Task task) async {
  final controller = context.read<TaskListController>();
  final messenger = ScaffoldMessenger.of(context);
  return runGuarded(context, () async {
    final deleted = await controller.delete(task);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Deleted "${deleted.title}"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => controller.restore(deleted),
        ),
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
