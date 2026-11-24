import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/data/settings_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_database.dart';

void main() {
  late Database db;
  late SqfliteSettingsRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    repo = SqfliteSettingsRepository(db);
  });
  tearDown(() => db.close());

  test('nothing saved yet', () async {
    expect(await repo.loadAll(), isEmpty);
  });

  test('saved settings come back; saving again replaces', () async {
    await repo.save('theme_mode', 'dark');
    await repo.save('high_contrast', 'true');
    await repo.save('theme_mode', 'light');
    expect(await repo.loadAll(),
        {'theme_mode': 'light', 'high_contrast': 'true'});
  });
}
