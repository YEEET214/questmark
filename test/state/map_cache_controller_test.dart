import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/data/tile_cache.dart';
import 'package:questmark/state/map_cache_controller.dart';

import '../helpers/fake_tile_cache.dart';

void main() {
  late FakeTileCache cache;
  late MapCacheController c;

  CachedTile tile(int n) => CachedTile(Uint8List(n), fresh: true);

  setUp(() {
    cache = FakeTileCache()..tiles['14/1/1'] = tile(1000);
    c = MapCacheController(cache, maxBytes: 100 * 1000 * 1000);
  });

  test('reports the size and the limit', () {
    expect(c.sizeBytes, 1000);
    expect(c.maxBytes, 100 * 1000 * 1000);
  });

  test('refresh picks up tiles the map added meanwhile', () {
    var notified = 0;
    c.addListener(() => notified++);
    cache.tiles['14/1/2'] = tile(500);
    c.refresh();
    expect(c.sizeBytes, 1500);
    c.refresh(); // nothing new
    expect(notified, 1);
  });

  test('clear: "clearing" while it runs, then empty', () async {
    cache.holdClear = Completer<void>();
    final clearing = c.clear();
    expect(c.clearing, isTrue);
    await c.clear(); // a second tap while clearing does nothing
    expect(cache.clears, 1);
    cache.holdClear!.complete();
    await clearing;
    expect(c.clearing, isFalse);
    expect(c.sizeBytes, 0);
  });
}
