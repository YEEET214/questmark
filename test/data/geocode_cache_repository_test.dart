import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/data/geocode_cache_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_database.dart';

void main() {
  late Database db;
  late SqfliteGeocodeCache cache;
  final t0 = DateTime(2026, 11, 1);

  setUp(() async {
    db = await openTestDatabase();
    cache = SqfliteGeocodeCache(db);
  });
  tearDown(() async => db.close());

  Future<void> put(String key, String value, DateTime at) =>
      cache.put(key, value, at: at, pruneBefore: DateTime(2000));

  test('an unknown key is a miss', () async {
    expect(await cache.get('search:x', notBefore: DateTime(2000)), isNull);
  });

  test('a stored value is returned', () async {
    await put('search:oodi', '[1]', t0);
    expect(await cache.get('search:oodi', notBefore: DateTime(2000)), '[1]');
  });

  test('storing again replaces the value', () async {
    await put('search:oodi', 'old', t0);
    await put('search:oodi', 'new', t0.add(const Duration(days: 1)));
    expect(await cache.get('search:oodi', notBefore: DateTime(2000)), 'new');
    expect(await db.query(SqfliteGeocodeCache.table), hasLength(1));
  });

  test('values older than notBefore are ignored', () async {
    await put('search:oodi', '[1]', t0);
    expect(
        await cache.get('search:oodi',
            notBefore: t0.add(const Duration(seconds: 1))),
        isNull);
  });

  test('writing removes entries older than pruneBefore', () async {
    await put('search:old', 'a', t0);
    await put('search:recent', 'b', t0.add(const Duration(days: 20)));
    await cache.put('search:new', 'c',
        at: t0.add(const Duration(days: 40)),
        pruneBefore: t0.add(const Duration(days: 10)));

    final keys = (await db.query(SqfliteGeocodeCache.table))
        .map((r) => r[SqfliteGeocodeCache.colKey])
        .toSet();
    expect(keys, {'search:recent', 'search:new'});
  });
}
