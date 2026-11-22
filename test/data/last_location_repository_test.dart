import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/data/last_location_repository.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/location_fix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_database.dart';

void main() {
  late Database db;
  late SqfliteLastLocationRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    repo = SqfliteLastLocationRepository(db);
  });
  tearDown(() async => db.close());

  LocationFix fix(double lat, double lng, int minute) => LocationFix(
    point: GeoPoint(lat, lng),
    accuracyMeters: 12.5,
    at: DateTime(2026, 11, 22, 12, minute),
  );

  test('nothing is saved on a fresh install', () async {
    expect(await repo.load(), isNull);
  });

  test('a saved fix is loaded back unchanged', () async {
    final f = fix(60.17, 24.94, 5);
    await repo.save(f);
    expect(await repo.load(), f);
  });

  test('only the latest fix is kept, never a history', () async {
    await repo.save(fix(60.17, 24.94, 1));
    await repo.save(fix(51.5, -0.12, 2));
    await repo.save(fix(-33.86, 151.2, 3));

    expect(await repo.load(), fix(-33.86, 151.2, 3));
    expect(await db.query(SqfliteLastLocationRepository.table), hasLength(1));
  });

  test('the table rejects a second row and bad coordinates', () async {
    await expectLater(
      db.insert(SqfliteLastLocationRepository.table, {
        'id': 2,
        'latitude': 0,
        'longitude': 0,
        'accuracy_m': 0,
        'recorded_at': 0,
      }),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.insert(SqfliteLastLocationRepository.table, {
        'id': 1,
        'latitude': 91,
        'longitude': 0,
        'accuracy_m': 0,
        'recorded_at': 0,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });
}
