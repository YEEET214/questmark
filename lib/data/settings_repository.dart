import 'package:sqflite/sqflite.dart';

/// The user's app settings, as text values by key (PLAN.md D28).
abstract interface class SettingsRepository {
  /// All saved settings.
  Future<Map<String, String>> loadAll();

  /// Saves (or replaces) one setting.
  Future<void> save(String key, String value);
}

/// [SettingsRepository] in the app database's `settings` table (schema v6).
class SqfliteSettingsRepository implements SettingsRepository {
  SqfliteSettingsRepository(this._db);

  final Database _db;

  static const table = 'settings';
  static const colKey = 'key';
  static const colValue = 'value';

  @override
  Future<Map<String, String>> loadAll() async {
    final rows = await _db.query(table);
    return {
      for (final r in rows) r[colKey]! as String: r[colValue]! as String,
    };
  }

  @override
  Future<void> save(String key, String value) => _db.insert(
        table,
        {colKey: key, colValue: value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
}
