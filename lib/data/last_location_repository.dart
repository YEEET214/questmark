import 'package:sqflite/sqflite.dart';

import '../models/geo_point.dart';
import '../models/location_fix.dart';

/// Remembers the most recent GPS fix across app restarts, so the map can
/// start there when there's no current fix (PLAN.md D19).
///
/// Only the latest position is kept, never a history, and it never leaves
/// the phone.
abstract interface class LastLocationRepository {
  /// The saved fix, or `null` if none has been saved yet.
  Future<LocationFix?> load();

  /// Replaces the saved fix.
  Future<void> save(LocationFix fix);
}

class SqfliteLastLocationRepository implements LastLocationRepository {
  SqfliteLastLocationRepository(this._db);

  final Database _db;

  static const table = 'last_location';
  static const colId = 'id';
  static const colLatitude = 'latitude';
  static const colLongitude = 'longitude';
  static const colAccuracy = 'accuracy_m';
  static const colRecordedAt = 'recorded_at';

  /// The table holds at most one row, with this id.
  static const _onlyRow = 1;

  @override
  Future<LocationFix?> load() async {
    final rows = await _db.query(
      table,
      where: '$colId = ?',
      whereArgs: [_onlyRow],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return LocationFix(
      point: GeoPoint(
        (r[colLatitude] as num).toDouble(),
        (r[colLongitude] as num).toDouble(),
      ),
      accuracyMeters: (r[colAccuracy] as num).toDouble(),
      at: DateTime.fromMillisecondsSinceEpoch(r[colRecordedAt] as int),
    );
  }

  @override
  Future<void> save(LocationFix fix) => _db.insert(
    table,
    {
      colId: _onlyRow,
      colLatitude: fix.point.latitude,
      colLongitude: fix.point.longitude,
      colAccuracy: fix.accuracyMeters,
      colRecordedAt: fix.at.millisecondsSinceEpoch,
    },
    // Overwrites the previous row: only the latest fix is kept.
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}
