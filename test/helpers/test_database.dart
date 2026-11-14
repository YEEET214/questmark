import 'package:questmark/data/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens a brand-new, empty in-memory database with the real app schema.
///
/// Uses sqflite's FFI implementation, so it runs on the development PC
/// under plain `flutter test` with no emulator. Each call returns an
/// independent database, so tests can't leak data into each other.
Future<Database> openTestDatabase({List<Migration>? schema}) {
  sqfliteFfiInit();
  return AppDatabase.open(
    factory: databaseFactoryFfi,
    path: inMemoryDatabasePath,
    schema: schema ?? AppDatabase.migrations,
  );
}
