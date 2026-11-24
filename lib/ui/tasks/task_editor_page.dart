import 'package:flutter/material.dart';

import '../../models/geo_point.dart';
import '../../models/task.dart';
import '../formatting.dart';
import '../map/location_picker_page.dart';

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
    this.location,
    this.address,
  });

  final String title;
  final String? description;
  final DateTime? dueAt;

  /// Where the quest is, or `null` for a list-only quest.
  final GeoPoint? location;

  /// The address that goes with [location]. Cleared when the location
  /// changes, because the old address would no longer match.
  final String? address;
}

/// The user pressed Delete (only offered when editing an existing task).
class TaskEditorDeleted extends TaskEditorResult {
  const TaskEditorDeleted();
}

/// Form for creating ([initial] is null) or editing a task.
///
/// The editor is deliberately "dumb": it doesn't save anything itself, it
/// just pops a [TaskEditorResult]. That keeps it free of storage concerns
/// and easy to test. Fields it doesn't show (the done state) are left
/// untouched by the caller.
///
/// The location is optional. "Add location" (or tapping the row) opens
/// [pickLocation]: by default the full-screen [LocationPickerPage], where
/// the user can move the map or search for an address (PLAN.md D6, D23).
class TaskEditorPage extends StatefulWidget {
  const TaskEditorPage({
    super.key,
    this.initial,
    this.initialLocation,
    this.clock = DateTime.now,
    this.pickLocation = pickLocationOnMap,
  });

  final Task? initial;

  /// Pre-filled location for a *new* quest (long-press on the map).
  /// Ignored when editing: the quest's own location is used.
  final GeoPoint? initialLocation;

  /// Opens the location picker. Injectable for tests.
  final LocationPicker pickLocation;

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

  late GeoPoint? _location = widget.isEditing
      ? widget.initial!.location
      : widget.initialLocation;
  late String? _address = widget.initial?.address;

  /// The location (and its address) from before the user removed it, so
  /// the picker can reopen there: re-pinning is usually a small
  /// adjustment, not a new place (user request, PR #10 review).
  GeoPoint? _removedLocation;
  String? _removedAddress;

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

  Future<void> _pickLocation() async {
    // Hide the keyboard first: the picker needs the whole screen.
    FocusScope.of(context).unfocus();
    // After "remove", the picker still starts at the removed location.
    final picked =
        await widget.pickLocation(context, _location ?? _removedLocation);
    if (!mounted || picked == null) return;
    final point = picked.point;
    setState(() {
      // An address from the address search always wins. Otherwise an
      // address belongs to its point: kept for the same point, restored
      // if the removed point is picked again, and dropped for a new point
      // (it's looked up after saving, D6).
      _address = picked.address ??
          (point == _location
              ? _address
              : point == _removedLocation
                  ? _removedAddress
                  : null);
      _location = point;
    });
  }

  void _clearLocation() => setState(() {
        _removedLocation = _location;
        _removedAddress = _address;
        _location = null;
        _address = null;
      });

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(TaskEditorSaved(
      title: _title.text,
      description: _description.text,
      // Stored as local midnight of the chosen day. The model converts it
      // to UTC, and the list converts back to local time for display.
      dueAt: _dueDay,
      location: _location,
      address: _address,
    ));
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete quest?'),
        content: Text('"${widget.initial!.title}" will be moved to the '
            'recycle bin. You can restore it from there for 30 days.'),
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
            _EditorRow(
              icon: Icons.event,
              title: dueDay == null
                  ? 'No due date'
                  : 'Due ${formatDate(dueDay)}',
              onTap: _pickDueDate,
              trailing: dueDay == null
                  ? TextButton(
                      onPressed: _pickDueDate,
                      child: const Text('Set due date',
                          textAlign: TextAlign.center),
                    )
                  : IconButton(
                      tooltip: 'Remove due date',
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _dueDay = null),
                    ),
            ),
            _LocationTile(
              location: _location,
              address: _address,
              onPick: _pickLocation,
              onClear: _clearLocation,
            ),
          ],
        ),
      ),
    );
  }
}

/// The editor's location row, laid out like the due-date row: tap to pick,
/// a button to remove. Shows the address if known, else "Pinned on the
/// map", with the coordinates underneath.
class _LocationTile extends StatelessWidget {
  const _LocationTile({
    required this.location,
    required this.address,
    required this.onPick,
    required this.onClear,
  });

  final GeoPoint? location;
  final String? address;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final location = this.location;
    return _EditorRow(
      key: const Key('locationTile'),
      icon: Icons.place_outlined,
      title: location == null ? 'No location' : address ?? 'Pinned on the map',
      subtitle: location == null ? null : formatCoordinates(location),
      onTap: onPick,
      trailing: location == null
          ? TextButton(
              key: const Key('pickLocationButton'),
              onPressed: onPick,
              child: const Text('Add location', textAlign: TextAlign.center),
            )
          : IconButton(
              key: const Key('clearLocationButton'),
              tooltip: 'Remove location',
              icon: const Icon(Icons.clear),
              onPressed: onClear,
            ),
    );
  }
}

/// One row of the editor (due date, location): an icon, the value, and a
/// button. Like a ListTile, but the button may take at most 40 % of the
/// width and wraps its text, so with a large font size on a small phone it
/// grows taller instead of running off the screen (PLAN.md D30).
class _EditorRow extends StatelessWidget {
  const _EditorRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = this.subtitle;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: LayoutBuilder(
          builder: (context, box) => Row(
            children: [
              Icon(icon, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.bodyLarge),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: box.maxWidth * 0.4),
                child: trailing,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
