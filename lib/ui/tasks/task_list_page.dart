import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../dev/dev_tools.dart';
import '../../models/task.dart';
import '../../models/task_query.dart';
import '../../state/navigation_controller.dart';
import '../../state/task_list_controller.dart';
import '../../state/task_list_view_controller.dart';
import '../formatting.dart';
import 'query_labels.dart';
import 'task_actions.dart';
import 'task_filter_sheet.dart';

/// All tasks in one list, with search, filters and sorting (PLAN.md D16).
///
/// * Ticking a task strikes it through **in place**. It never jumps to
///   another section. Under a status filter that would now hide it, it
///   stays visible until the filter changes or you leave the page, and
///   completing shows an Undo snackbar.
/// * Search (title and description), status chips, date filters (filter
///   button) and sort (sort button) live in the app bar and just below it.
/// * Tap a quest to edit it. Swipe left to delete it, with Undo. The +
///   button creates a new quest.
class TaskListPage extends StatefulWidget {
  const TaskListPage({super.key, this.clock = DateTime.now});

  /// Used for "overdue" and the status filter. Injectable for tests.
  final DateTime Function() clock;

  @override
  State<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends State<TaskListPage> {
  late final NavigationController _nav;
  late final TaskListViewController _view;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _view = context.read<TaskListViewController>();
    _search.text = _view.query.search;
    _nav = context.read<NavigationController>()..addListener(_onTabChanged);
    // Rebuild when the search field gains or loses focus (keyboard open or
    // closed), to hide or show the "New quest" button.
    _searchFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nav.removeListener(_onTabChanged);
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Leaving the page releases the tasks kept visible after ticking.
  void _onTabChanged() {
    if (_nav.current != AppTab.tasks) _view.releaseKeptTasks();
  }

  void _setQuery(TaskQuery q) => _view.setQuery(q);

  void _dismissKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TaskListController>();
    final view = context.watch<TaskListViewController>();
    final query = view.query;
    final showControls =
        controller.hasLoaded && controller.loadError == null &&
            controller.tasks.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quests'),
        actions: [
          if (showControls) ...[
            _SortButton(
              query: query,
              onChanged: _setQuery,
              onOpened: _dismissKeyboard,
            ),
            IconButton(
              tooltip: 'Filter by date',
              icon: Badge(
                isLabelVisible: query.hasDateFilters,
                smallSize: 8,
                // A funnel, so it doesn't look like the sort icon's lines.
                child: const Icon(Icons.filter_alt_outlined),
              ),
              onPressed: () async {
                _dismissKeyboard();
                final edited = await TaskFilterSheet.show(context, query);
                if (edited != null) _setQuery(edited);
              },
            ),
          ],
          // TEMPORARY: debug-only developer tools (removed before release).
          const DevToolsButton(),
        ],
      ),
      // Hidden while typing a search (the keyboard is open then), so it
      // doesn't float over the results. Keyed on the search field's focus,
      // not on the keyboard size: the app shell's Scaffold already absorbs
      // the keyboard, so this page never sees it.
      floatingActionButton: _searchFocus.hasFocus
          ? null
          : FloatingActionButton.extended(
              onPressed: () => openTaskEditor(context, null),
              icon: const Icon(Icons.add),
              label: const Text('New quest'),
            ),
      body: showControls
          ? Column(
              // Chip rows start at the left edge even when they're
              // narrower than the screen.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSearchField(query),
                _StatusChips(
                  selected: query.status,
                  onSelected: (s) => _setQuery(query.copyWith(status: s)),
                ),
                if (query.hasDateFilters)
                  _DateFilterChips(query: query, onChanged: _setQuery),
                Expanded(child: _buildList(controller, view)),
              ],
            )
          : _buildEmptyOrError(controller),
    );
  }

  Widget _buildSearchField(TaskQuery query) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        key: const Key('searchField'),
        controller: _search,
        focusNode: _searchFocus,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search quests',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: query.search.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _search.clear();
                    _setQuery(query.copyWith(search: ''));
                  },
                ),
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(28)),
          ),
          isDense: true,
        ),
        // The search runs on the phone's own list, so filtering on every
        // keystroke is cheap (no network involved).
        onChanged: (text) => _setQuery(query.copyWith(search: text)),
        // Tapping anywhere else closes the keyboard. Without this, the
        // field keeps focus and the keyboard pops back up whenever a sheet
        // or menu closes.
        onTapOutside: (_) => _dismissKeyboard(),
      ),
    );
  }

  Widget _buildEmptyOrError(TaskListController controller) {
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
    return const _Message(
      icon: Icons.explore_outlined,
      title: 'No quests yet',
      subtitle: 'Tap "New quest" to add your first one.',
    );
  }

  Widget _buildList(TaskListController controller, TaskListViewController view) {
    final now = widget.clock();
    final shown = view.query.apply(
      controller.tasks,
      now: now,
      keepVisible: view.keepVisible,
    );
    if (shown.isEmpty) {
      return _Message(
        icon: Icons.search_off,
        title: 'No quests match',
        subtitle: 'Try a different search or filter.',
        action: OutlinedButton(
          onPressed: () {
            _search.clear();
            _setQuery(view.query.clearFilters());
          },
          child: const Text('Clear filters'),
        ),
      );
    }
    return ListView(
      // Leaves room so the last tile isn't hidden behind the FAB.
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        for (final t in shown)
          _TaskTile(
            task: t,
            now: now,
            onToggleDone: (done) => _toggleDone(t, done),
          ),
      ],
    );
  }

  /// Ticks or unticks a task without moving it, and offers Undo after
  /// completing.
  Future<void> _toggleDone(Task task, bool done) async {
    final id = task.id;
    if (id == null) return;
    final controller = context.read<TaskListController>();
    final messenger = ScaffoldMessenger.of(context);
    _view.keepTaskVisible(id);
    final ok = await setTaskDone(context, task, done);
    if (!ok || !done) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Completed "${task.title}"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            final current =
                controller.tasks.where((t) => t.id == id).firstOrNull;
            if (current != null) controller.setDone(current, false);
          },
        ),
      ));
  }
}

class _StatusChips extends StatelessWidget {
  const _StatusChips({required this.selected, required this.onSelected});

  final StatusFilter selected;
  final ValueChanged<StatusFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final s in StatusFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: Key('status-${s.name}'),
                label: Text(s.label),
                selected: s == selected,
                onSelected: (_) => onSelected(s),
              ),
            ),
        ],
      ),
    );
  }
}

/// The active date filters as removable chips, e.g. "Due: from 01-12-2026 ✕".
class _DateFilterChips extends StatelessWidget {
  const _DateFilterChips({required this.query, required this.onChanged});

  final TaskQuery query;
  final ValueChanged<TaskQuery> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          for (final field in DateFilterField.values)
            if (!field.of(query).isAny)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InputChip(
                  key: Key('dateChip-${field.name}'),
                  avatar: const Icon(Icons.event, size: 18),
                  label: Text(describeRange(field, field.of(query))),
                  onPressed: () async {
                    FocusManager.instance.primaryFocus?.unfocus();
                    final edited = await TaskFilterSheet.show(context, query);
                    if (edited != null) onChanged(edited);
                  },
                  onDeleted: () =>
                      onChanged(field.set(query, const DayRange.any())),
                  deleteButtonTooltipMessage: 'Remove filter',
                ),
              ),
        ],
      ),
    );
  }
}

/// Sort menu: pick the field, then ascending or descending.
class _SortButton extends StatelessWidget {
  const _SortButton({
    required this.query,
    required this.onChanged,
    required this.onOpened,
  });

  final TaskQuery query;
  final ValueChanged<TaskQuery> onChanged;
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context) {
    final direction = query.ascending ? 'ascending' : 'descending';
    return PopupMenuButton<Object>(
      tooltip: 'Sort: ${query.sortField.label}, $direction',
      icon: const Icon(Icons.sort),
      onOpened: onOpened,
      onSelected: (choice) => onChanged(switch (choice) {
        SortField f => query.copyWith(sortField: f),
        bool asc => query.copyWith(ascending: asc),
        _ => query,
      }),
      itemBuilder: (_) => [
        for (final f in SortField.values)
          CheckedPopupMenuItem<Object>(
            value: f,
            checked: f == query.sortField,
            child: Text(f.label),
          ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem<Object>(
          value: true,
          checked: query.ascending,
          child: const Text('Ascending'),
        ),
        CheckedPopupMenuItem<Object>(
          value: false,
          checked: !query.ascending,
          child: const Text('Descending'),
        ),
      ],
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    required this.now,
    required this.onToggleDone,
  });

  final Task task;
  final DateTime now;
  final ValueChanged<bool> onToggleDone;

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
          onChanged: (done) => onToggleDone(done ?? false),
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
        // Only tasks with a location get the button; the others have
        // nothing to show (PLAN.md D10, user decision).
        trailing: task.hasLocation
            ? IconButton(
                tooltip: 'Show on map',
                icon: const Icon(Icons.travel_explore),
                onPressed: () => showTaskOnMap(context, task),
              )
            : null,
        onTap: () => openTaskEditor(context, task),
      ),
    );
  }

  Widget? _subtitle(BuildContext context) {
    final theme = Theme.of(context);
    final dates = <InlineSpan>[];

    final due = task.dueAt;
    if (due != null) {
      final date = formatDate(due.toLocal());
      final overdue = task.isOverdue(now);
      dates.add(TextSpan(
        text: overdue ? 'Overdue · $date' : 'Due $date',
        style: overdue
            ? TextStyle(
                color: theme.colorScheme.error, fontWeight: FontWeight.w600)
            : null,
      ));
    }
    final completed = task.completedAt;
    if (completed != null) {
      if (dates.isNotEmpty) dates.add(const TextSpan(text: ' · '));
      dates.add(TextSpan(text: 'Completed ${formatDate(completed.toLocal())}'));
    }

    final parts = <InlineSpan>[...dates];
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
      child: SingleChildScrollView(
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
