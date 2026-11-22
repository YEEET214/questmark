import 'package:flutter/foundation.dart';

import 'geo_point.dart';

/// A to-do item ("quest"). It may have a location, in which case it is
/// shown on the map.
///
/// Immutable: changes are made with [copyWith], so the state layer can
/// compare old and new values and widgets never see a half-edited task.
@immutable
class Task {
  /// Creates a task.
  ///
  /// * [title] is trimmed and must not be empty ([ArgumentError]).
  /// * Times are normalised to UTC with millisecond precision, matching
  ///   what SQLite stores (see [toMap]). A task therefore equals itself
  ///   after a database round trip.
  /// * [completedAt] is dropped when the task isn't done, so an open task
  ///   can never carry a completion date.
  Task({
    this.id,
    required String title,
    String? description,
    this.isDone = false,
    required DateTime createdAt,
    DateTime? dueAt,
    DateTime? completedAt,
    String? address,
    this.location,
  })  : title = title.trim(),
        description = _blankToNull(description),
        address = _blankToNull(address),
        createdAt = _normalise(createdAt),
        dueAt = dueAt == null ? null : _normalise(dueAt),
        completedAt = (!isDone || completedAt == null)
            ? null
            : _normalise(completedAt) {
    if (this.title.isEmpty) {
      throw ArgumentError.value(title, 'title', 'must not be empty');
    }
  }

  /// Database id. `null` until the task has been inserted.
  final int? id;
  final String title;
  final String? description;
  final bool isDone;
  final DateTime createdAt;
  final DateTime? dueAt;

  /// When the task was ticked. `null` while open, and also for tasks
  /// completed before this was recorded (schema v1): unknown.
  final DateTime? completedAt;

  /// Human-readable address. Shown in the UI and kept so we never have to
  /// geocode the same task twice.
  final String? address;

  /// Where the quest marker goes. `null` means the task is list-only.
  ///
  /// Latitude and longitude are a single [GeoPoint], so the model cannot
  /// hold one without the other.
  final GeoPoint? location;

  bool get hasLocation => location != null;

  /// Whether this task is still open and its due *day* (local time) is
  /// before today. A task due today is not overdue yet.
  bool isOverdue(DateTime now) {
    final due = dueAt;
    if (isDone || due == null) return false;
    final d = due.toLocal();
    final n = now.toLocal();
    return DateTime(d.year, d.month, d.day)
        .isBefore(DateTime(n.year, n.month, n.day));
  }

  /// Returns a copy with the given fields replaced.
  ///
  /// The nullable fields take a function, so they can be explicitly
  /// cleared: `copyWith(location: () => null)` removes the location, while
  /// leaving the argument out keeps it. A plain `GeoPoint?` parameter could
  /// not tell "not given" apart from "set to null".
  Task copyWith({
    int? id,
    String? title,
    ValueGetter<String?>? description,
    bool? isDone,
    DateTime? createdAt,
    ValueGetter<DateTime?>? dueAt,
    ValueGetter<DateTime?>? completedAt,
    ValueGetter<String?>? address,
    ValueGetter<GeoPoint?>? location,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description != null ? description() : this.description,
      isDone: isDone ?? this.isDone,
      createdAt: createdAt ?? this.createdAt,
      dueAt: dueAt != null ? dueAt() : this.dueAt,
      completedAt: completedAt != null ? completedAt() : this.completedAt,
      address: address != null ? address() : this.address,
      location: location != null ? location() : this.location,
    );
  }

  /// A copy with no database id, ready to be inserted as a new row (used
  /// to undo a delete). [copyWith] can't do this, because `id: null` there
  /// means "keep the id".
  Task withoutId() => Task(
        title: title,
        description: description,
        isDone: isDone,
        createdAt: createdAt,
        dueAt: dueAt,
        completedAt: completedAt,
        address: address,
        location: location,
      );

  /// Column names, shared with the schema so they're never misspelled.
  static const colId = 'id';
  static const colTitle = 'title';
  static const colDescription = 'description';
  static const colIsDone = 'is_done';
  static const colCreatedAt = 'created_at';
  static const colDueAt = 'due_at';
  static const colCompletedAt = 'completed_at'; // schema v2
  static const colAddress = 'address';
  static const colLatitude = 'latitude';
  static const colLongitude = 'longitude';

  /// Converts to an SQLite row. SQLite has no boolean or date types, so
  /// `isDone` becomes 0/1 and times become epoch milliseconds (UTC).
  /// `id` is left out when null so SQLite assigns one on insert.
  Map<String, Object?> toMap() => {
        if (id != null) colId: id,
        colTitle: title,
        colDescription: description,
        colIsDone: isDone ? 1 : 0,
        colCreatedAt: createdAt.millisecondsSinceEpoch,
        colDueAt: dueAt?.millisecondsSinceEpoch,
        colCompletedAt: completedAt?.millisecondsSinceEpoch,
        colAddress: address,
        colLatitude: location?.latitude,
        colLongitude: location?.longitude,
      };

  /// Builds a task from an SQLite row.
  ///
  /// Throws [FormatException] if only one of latitude/longitude is set.
  /// The schema's CHECK constraint prevents that, so if it happens the
  /// database is corrupt and we'd rather fail loudly than drop data
  /// silently.
  factory Task.fromMap(Map<String, Object?> map) {
    final lat = (map[colLatitude] as num?)?.toDouble();
    final lng = (map[colLongitude] as num?)?.toDouble();
    if ((lat == null) != (lng == null)) {
      throw FormatException(
          'Task ${map[colId]} has only one of latitude/longitude set');
    }
    final dueMs = map[colDueAt] as int?;
    final completedMs = map[colCompletedAt] as int?;
    return Task(
      id: map[colId] as int?,
      title: map[colTitle] as String,
      description: map[colDescription] as String?,
      isDone: (map[colIsDone] as int) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          map[colCreatedAt] as int,
          isUtc: true),
      dueAt: dueMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(dueMs, isUtc: true),
      completedAt: completedMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(completedMs, isUtc: true),
      address: map[colAddress] as String?,
      location: lat == null ? null : GeoPoint(lat, lng!),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Task &&
      other.id == id &&
      other.title == title &&
      other.description == description &&
      other.isDone == isDone &&
      other.createdAt == createdAt &&
      other.dueAt == dueAt &&
      other.completedAt == completedAt &&
      other.address == address &&
      other.location == location;

  @override
  int get hashCode => Object.hash(id, title, description, isDone, createdAt,
      dueAt, completedAt, address, location);

  @override
  String toString() =>
      'Task(id: $id, title: $title, done: $isDone, location: $location)';

  static String? _blankToNull(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  /// UTC, truncated to whole milliseconds (DateTime.now() can carry
  /// microseconds, which SQLite would drop).
  static DateTime _normalise(DateTime t) =>
      DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch,
          isUtc: true);
}
