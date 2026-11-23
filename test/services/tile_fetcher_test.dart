import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:questmark/models/region_plan.dart';
import 'package:questmark/services/tile_fetcher.dart';

void main() {
  const tileJson = 'https://tiles.openfreemap.org/planet';
  const template = 'https://tiles.openfreemap.org/planet/20261115/{z}/{x}/{y}.pbf';
  final pbf = Uint8List.fromList([0x1a, 0x05, 1, 2, 3, 4, 5]);
  final gz = Uint8List.fromList(gzip.encode(pbf));

  late List<http.Request> requests;

  OpenFreeMapTileFetcher fetcher(
      http.Response Function(http.Request) tiles) {
    requests = [];
    return OpenFreeMapTileFetcher(
      client: MockClient((r) async {
        requests.add(r);
        if (r.url.toString() == tileJson) {
          return http.Response(jsonEncode({'tiles': [template]}), 200);
        }
        return tiles(r);
      }),
    );
  }

  test('reads the tile URL from the TileJSON once, then fetches tiles with '
      'the User-Agent', () async {
    final f = fetcher((_) => http.Response.bytes(gz, 200));
    await f.fetch(const TileId(14, 8000, 5000));
    await f.fetch(const TileId(13, 4000, 2500));
    expect(requests.map((r) => r.url.toString()), [
      tileJson,
      'https://tiles.openfreemap.org/planet/20261115/14/8000/5000.pbf',
      'https://tiles.openfreemap.org/planet/20261115/13/4000/2500.pbf',
    ]);
    for (final r in requests) {
      expect(r.headers['User-Agent'], 'QuestMark/1.0.0');
      expect(r.url.host, isNot('tile.openstreetmap.org'));
    }
  });

  test('a gzipped tile is kept as downloaded, and its size counted', () async {
    final t = await fetcher((_) => http.Response.bytes(gz, 200))
        .fetch(const TileId(14, 1, 1));
    expect(t.data, gz);
    expect(t.downloaded, gz.length);
  });

  test('a tile that arrives unzipped is gzipped for storage', () async {
    final t = await fetcher((_) => http.Response.bytes(pbf, 200))
        .fetch(const TileId(14, 1, 1));
    expect(gzip.decode(t.data), pbf);
    expect(t.downloaded, pbf.length);
  });

  test('204, 404 and an empty body mean "no tile here"', () async {
    for (final code in [204, 404]) {
      final t = await fetcher((_) => http.Response('', code))
          .fetch(const TileId(14, 1, 1));
      expect(t.data, isEmpty, reason: '$code');
    }
    final t = await fetcher((_) => http.Response.bytes(const [], 200))
        .fetch(const TileId(14, 1, 1));
    expect(t.data, isEmpty);
  });

  test('429 and 5xx are "busy" (retry); other codes are not retried',
      () async {
    Future<TileFetchException> failure(int code) async {
      try {
        await fetcher((_) => http.Response('', code))
            .fetch(const TileId(14, 1, 1));
      } on TileFetchException catch (e) {
        return e;
      }
      fail('no exception for $code');
    }

    expect((await failure(429)).failure, TileFetchFailure.busy);
    expect((await failure(503)).retryable, isTrue);
    expect((await failure(403)).failure, TileFetchFailure.server);
    expect((await failure(403)).retryable, isFalse);
  });

  test('no connection is a "connection" failure, and the TileJSON is asked '
      'for again next time', () async {
    var online = false;
    requests = [];
    final f = OpenFreeMapTileFetcher(
      client: MockClient((r) async {
        requests.add(r);
        if (!online) throw http.ClientException('no network');
        if (r.url.toString() == tileJson) {
          return http.Response(jsonEncode({'tiles': [template]}), 200);
        }
        return http.Response.bytes(gz, 200);
      }),
    );
    await expectLater(
      f.fetch(const TileId(14, 1, 1)),
      throwsA(isA<TileFetchException>()
          .having((e) => e.failure, 'failure', TileFetchFailure.connection)),
    );
    online = true;
    expect((await f.fetch(const TileId(14, 1, 1))).data, gz);
    expect(requests.where((r) => r.url.toString() == tileJson), hasLength(2));
  });
}
