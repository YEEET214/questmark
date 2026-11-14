import 'package:flutter/material.dart';

import '../../models/task.dart';
import '../formatting.dart';

/// What the editor hands back when it closes. (Closing with the back button
/// returns `null`: nothing changes.)
sealed class TaskEditorResult {
  const TaskEditorResult();
}

/// The user pressed Save. Contains only the fields the editor edits, so
/// the caller decides whether this creates a new task or updates one.
class TaskEditorSaved extends TaskEditorResult {
  const TaskEditorSaved({
    required this.title,
    this.description,
    this.dueAt,
  });

  final String title;
  final String? description;
  final DateTime? dueAt;
}

/// The user pressed Delete (only offered when editing an existing task).
class TaskEditorDeleted extends TaskEditorResult {
  const TaskEditorDeleted();
}

/// Form for creating ([initial] is null) or editing a task.
///
/// The editor is deliberately "dumb": it doesn't save anything itself, it
/// just pops a [TaskEditorResult]. That keeps it free of storage concerns
/// and easy to test. Fields it doesn't show (location, done state) are
/// left untouched by the caller. Location editing arrives in phases 6–7.
class TaskEditorPage extends StatefulWidget {
  const TaskEditorPage({super.key, this.initial, this.clock = DateTime.now});

  final Task? initial;

  /// Used for the date picker's starting date. Injectable for tests.
  final DateTime Function() clock;

  bool get isEditing => initial != null;

  @override
  State<TaskEditorPage> createState() => _TaskEditorPageState();
}

class _TaskEditorPageState extends State<TaskEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title =
      TextEditingController(text: widget.initial?.title);
  late final TextEditingController _description =
      TextEditingController(text: widget.initial?.description);

  /// The due *day* in local time (date only, no time of day).
  late DateTime? _dueDay = widget.initial?.dueAt == null
      ? null
      : _dateOnly(widget.initial!.dueAt!.toLocal());

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  static DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

  Future<void> _pickDueDate() async {
    final today = _dateOnly(widget.clock());
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDay ?? today,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _dueDay = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(TaskEditorSaved(
      title: _title.text,
      description: _description.text,
      // Stored as local midnight of the chosen day. The model converts it
      // to UTC, and the list converts back to local time for display.
      dueAt: _dueDay,
    ));
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete quest?'),
        content: Text('"${widget.initial!.title}" will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop(const TaskEditorDeleted());
    }
  }

  @override
  Widget build(BuildContext context) {
    final dueDay = _dueDay;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit quest' : 'New quest'),
        actions: [
          if (widget.isEditing)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('titleField'),
              controller: _title,
              autofocus: !widget.isEditing,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Give your quest a title'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('descriptionField'),
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(dueDay == null
                  ? 'No due date'
                  : 'Due ${formatDate(dueDay)}'),
              onTap: _pickDueDate,
              trailing: dueDay == null
                  ? TextButton(
                      onPressed: _pickDueDate,
                      child: const Text('Set due date'),
                    )
                  : IconButton(
                      tooltip: 'Remove due date',
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _dueDay = null),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
