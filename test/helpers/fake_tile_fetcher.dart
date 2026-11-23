import 'dart:async';
import 'dart:typed_data';

import 'package:questmark/models/region_plan.dart';
import 'package:questmark/services/tile_fetcher.dart';

/// A [TileFetcher] that never touches the network: every tile is
/// [tileBytes] bytes, unless [failures] says otherwise. Records what was
/// asked and how many requests ran at once.
class FakeTileFetcher implements TileFetcher {
  FakeTileFetcher({this.tileBytes = 10});

  int tileBytes;
  final asked = <TileId>[];

  /// Failures to throw, in order, before answering normally again.
  final failures = <TileFetchFailure>[];

  /// If set, every request waits for it (to test pausing and parallelism).
  Completer<void>? gate;

  /// How long each request takes.
  Duration latency = Duration.zero;

  /// Tiles with no data on the server.
  final empty = <TileId>{};

  int _running = 0;
  int maxRunning = 0;

  @override
  Future<FetchedTile> fetch(TileId tile) async {
    asked.add(tile);
    _running++;
    if (_running > maxRunning) maxRunning = _running;
    try {
      await Future<void>.delayed(latency);
      await gate?.future;
      if (failures.isNotEmpty) {
        throw TileFetchException(failures.removeAt(0));
      }
      if (empty.contains(tile)) {
        return FetchedTile(Uint8List(0), downloaded: 0);
      }
      return FetchedTile(Uint8List(tileBytes), downloaded: tileBytes);
    } finally {
      _running--;
    }
  }
}
