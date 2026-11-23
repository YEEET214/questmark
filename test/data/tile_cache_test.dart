import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/data/tile_cache.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late DateTime now;
  late SqfliteTileCache cache;

  Future<SqfliteTileCache> open({int maxBytes = 1000, String? path}) {
    sqfliteFfiInit();
    return SqfliteTileCache.open(
      path: path ?? inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      maxBytes: maxBytes,
      ttl: const Duration(days: 30),
      clock: () => now,
    );
  }

  Uint8List bytes(int n, [int fill = 1]) =>
      Uint8List.fromList(List.filled(n, fill));

  setUp(() async {
    now = DateTime(2026, 11, 23);
    cache = await open();
  });
  tearDown(() => cache.close());

  test('a stored tile comes back, fresh', () async {
    await cache.put(14, 1, 2, bytes(10));
    final t = (await cache.get(14, 1, 2))!;
    expect(t.bytes, bytes(10));
    expect(t.fresh, isTrue);
    expect(await cache.get(14, 2, 1), isNull);
  });

  test('after 30 days it is stale, but still there for offline', () async {
    await cache.put(14, 1, 2, bytes(10));
    now = now.add(const Duration(days: 31));
    final t = (await cache.get(14, 1, 2))!;
    expect(t.fresh, isFalse);
    expect(t.bytes, hasLength(10));
  });

  test('"no tile here" is stored as empty', () async {
    await cache.put(14, 1, 2, Uint8List(0));
    expect((await cache.get(14, 1, 2))!.bytes, isEmpty);
  });

  test('replacing a tile keeps the size right', () async {
    await cache.put(14, 1, 2, bytes(100));
    await cache.put(14, 1, 2, bytes(40));
    expect(cache.sizeBytes, 40);
  });

  test('over the limit, the oldest tiles go, down to 90 %', () async {
    for (var i = 0; i < 10; i++) {
      now = now.add(const Duration(minutes: 1));
      await cache.put(14, i, 0, bytes(100));
    }
    expect(cache.sizeBytes, 1000);
    now = now.add(const Duration(minutes: 1));
    await cache.put(14, 99, 0, bytes(100)); // 1,100 > 1,000
    expect(cache.sizeBytes, lessThanOrEqualTo(900));
    expect(await cache.get(14, 0, 0), isNull, reason: 'oldest');
    expect(await cache.get(14, 1, 0), isNull);
    expect(await cache.get(14, 99, 0), isNotNull, reason: 'newest');
  });

  test('the size is known again after reopening', () async {
    final dir = await Directory.systemTemp.createTemp('tile_cache');
    final path = '${dir.path}/${SqfliteTileCache.fileName}';
    var c = await open(path: path);
    await c.put(14, 1, 1, bytes(70));
    await c.close();
    c = await open(path: path);
    expect(c.sizeBytes, 70);
    await c.close();
    await dir.delete(recursive: true);
  });
}
