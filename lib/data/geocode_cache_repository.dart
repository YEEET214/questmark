import 'package:sqflite/sqflite.dart';

/// Stores geocoding answers, so the same question is never sent to
/// Nominatim twice (PLAN.md D6). Values are JSON text; the caching
/// service decides what goes in.
abstract interface class GeocodeCache {
  /// The value stored for [key], if it was stored at or after [notBefore].
  Future<String?> get(String key, {required DateTime notBefore});

  /// Stores [value] for [key] (replacing any older one), and removes
  /// entries stored before [pruneBefore], so the table can't grow forever.
  Future<void> put(
    String key,
    String value, {
    required DateTime at,
    required DateTime pruneBefore,
  });
}

class SqfliteGeocodeCache implements GeocodeCache {
  SqfliteGeocodeCache(this._db);

  final Database _db;

  static const table = 'geocode_cache';
  static const colKey = 'cache_key';
  static const colValue = 'value';
  static const colFetchedAt = 'fetched_at';

  @override
  Future<String?> get(String key, {required DateTime notBefore}) async {
    final rows = await _db.query(
      table,
      columns: [colValue],
      where: '$colKey = ? AND $colFetchedAt >= ?',
      whereArgs: [key, notBefore.millisecondsSinceEpoch],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first[colValue] as String;
  }

  @override
  Future<void> put(
    String key,
    String value, {
    required DateTime at,
    required DateTime pruneBefore,
  }) {
    return _db.transaction((txn) async {
      await txn.delete(table,
          where: '$colFetchedAt < ?',
          whereArgs: [pruneBefore.millisecondsSinceEpoch]);
      await txn.insert(
        table,
        {
          colKey: key,
          colValue: value,
          colFetchedAt: at.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }
}
