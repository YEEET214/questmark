import 'package:questmark/data/offline_region_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A brand-new, empty in-memory [OfflineRegionStore] (sqflite FFI, so it
/// runs under plain `flutter test`).
Future<OfflineRegionStore> openTestRegionStore() {
  sqfliteFfiInit();
  return OfflineRegionStore.open(
    factory: databaseFactoryFfi,
    path: inMemoryDatabasePath,
  );
}
