import 'dart:async';
import 'dart:typed_data';

import 'package:questmark/data/tile_cache.dart';

/// The browse cache in memory: `'z/x/y'` → tile.
class FakeTileCache implements NetworkTileCache {
  final tiles = <String, CachedTile>{};

  /// If set, [clear] waits for it, so a test can see "Clearing…".
  Completer<void>? holdClear;
  int clears = 0;

  @override
  Future<CachedTile?> get(int z, int x, int y) async => tiles['$z/$x/$y'];

  @override
  Future<void> put(int z, int x, int y, Uint8List bytes) async =>
      tiles['$z/$x/$y'] = CachedTile(bytes, fresh: true);

  @override
  int get sizeBytes =>
      tiles.values.fold(0, (sum, t) => sum + t.bytes.length);

  @override
  Future<void> clear() async {
    clears++;
    await holdClear?.future;
    tiles.clear();
  }
}
