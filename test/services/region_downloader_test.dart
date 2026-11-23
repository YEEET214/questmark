import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/data/offline_region_store.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/offline_region.dart';
import 'package:questmark/models/region_plan.dart';
import 'package:questmark/services/region_downloader.dart';
import 'package:questmark/services/tile_fetcher.dart';

import '../helpers/fake_tile_fetcher.dart';
import '../helpers/test_region_store.dart';

void main() {
  late OfflineRegionStore store;
  late FakeTileFetcher fetcher;
  final dundee = GeoPoint(56.462, -2.971);
  final waits = <Duration>[];

  setUp(() async {
    store = await openTestRegionStore();
    fetcher = FakeTileFetcher();
    waits.clear();
  });
  tearDown(() => store.close());

  RegionDownloader downloader({int byteLimit = 1 << 40}) => RegionDownloader(
        store,
        fetcher,
        byteLimit: byteLimit,
        // No real waiting in tests; just record it.
        wait: (d) async => waits.add(d),
      );

  Future<OfflineRegion> newRegion([GeoPoint? at]) => store.createRegion(
      name: 'Area',
      center: at ?? dundee,
      size: RegionSize.small,
      createdAt: DateTime(2026, 11, 23));

  test('downloads every tile once, middle first, and is then complete',
      () async {
    final region = await newRegion();
    final plan = region.plan;
    final progress = <int>[];
    final done = await downloader()
        .run(region, onProgress: (p) => progress.add(p.doneTiles));

    expect(done.status, RegionStatus.complete);
    expect(done.doneTiles, plan.tileCount);
    expect(done.coveredRadius, plan.half);
    expect(fetcher.asked.toSet(), plan.tiles.toSet());
    expect(fetcher.asked, hasLength(plan.tileCount), reason: 'each once');
    // Roughly in the plan's order (two at a time): the centre comes first.
    expect(fetcher.asked.take(2), plan.tiles.take(2));
    expect(progress.last, plan.tileCount);
    expect(await store.tilesOf(region.id), plan.tiles.toSet());
  });

  test('never more than 2 requests at a time', () async {
    final region = await newRegion();
    // Slow enough that requests overlap.
    fetcher.latency = const Duration(milliseconds: 1);
    await downloader().run(region);
    expect(fetcher.maxRunning, 2);
  });

  test('"no tile here" answers are stored as empty, not asked again',
      () async {
    final region = await newRegion();
    final sea = region.plan.tiles[5];
    fetcher.empty.add(sea);
    await downloader().run(region);
    expect(await store.tile(sea.z, sea.x, sea.y), isEmpty);
  });

  test('pausing stops it; resuming fetches only what is missing', () async {
    final region = await newRegion();
    final cancel = DownloadCancel();
    var seen = 0;
    final paused = await downloader().run(region, cancel: cancel,
        onProgress: (p) {
      if (++seen == 40) cancel.cancel();
    });
    expect(paused.status, RegionStatus.paused);
    expect(paused.problem, isNull, reason: 'the user paused it');
    expect(paused.doneTiles, inInclusiveRange(39, 41));
    expect(paused.coveredRadius, greaterThanOrEqualTo(0));

    final before = fetcher.asked.length;
    final done = await downloader().run(paused);
    expect(done.status, RegionStatus.complete);
    final again = fetcher.asked.sublist(before);
    expect(again.toSet().intersection(fetcher.asked.sublist(0, before).toSet()),
        isEmpty,
        reason: 'nothing already on the phone is downloaded again');
    expect(fetcher.asked, hasLength(region.plannedTiles));
  });

  test('tiles another region already has are shared, not downloaded',
      () async {
    final first = await newRegion();
    await downloader().run(first);
    fetcher.asked.clear();

    // A second area a few km east: most of its tiles overlap the first.
    final second = await newRegion(GeoPoint(56.462, -2.90));
    final done = await downloader().run(second);
    expect(done.status, RegionStatus.complete);
    expect(fetcher.asked.length, lessThan(second.plannedTiles ~/ 2));
    expect(done.downloadedBytes, fetcher.asked.length * fetcher.tileBytes);
  });

  test('stops at the size limit; the middle is kept and it is not resumed',
      () async {
    final region = await newRegion();
    fetcher.tileBytes = 1000;
    final done = await downloader(byteLimit: 50 * 1000).run(region);

    expect(done.status, RegionStatus.limitReached);
    expect(done.downloadedBytes, inInclusiveRange(50 * 1000, 51 * 1000),
        reason: 'stops as soon as the limit is reached (2 in flight)');
    expect(done.coveredRadius, greaterThanOrEqualTo(0));
    expect(done.canResume, isFalse);

    // Running it again downloads nothing more.
    final asked = fetcher.asked.length;
    await downloader(byteLimit: 50 * 1000).run(done);
    expect(fetcher.asked, hasLength(asked));
  });

  test('the size limit counts across resumes', () async {
    final region = await newRegion();
    fetcher.tileBytes = 1000;
    final cancel = DownloadCancel();
    var seen = 0;
    final paused = await downloader(byteLimit: 30 * 1000).run(region,
        cancel: cancel, onProgress: (_) {
      if (++seen == 20) cancel.cancel();
    });
    expect(paused.status, RegionStatus.paused);
    final done = await downloader(byteLimit: 30 * 1000).run(paused);
    expect(done.status, RegionStatus.limitReached);
    expect(done.downloadedBytes, inInclusiveRange(30 * 1000, 31 * 1000));
  });

  test('a busy server is retried after growing pauses', () async {
    final region = await newRegion();
    fetcher.failures.addAll([TileFetchFailure.busy, TileFetchFailure.busy]);
    final done = await downloader().run(region);
    expect(done.status, RegionStatus.complete);
    expect(waits, const [Duration(seconds: 2), Duration(seconds: 6)]);
  });

  test('a lasting connection failure pauses it, with the reason', () async {
    final region = await newRegion();
    fetcher.failures.addAll(List.filled(10, TileFetchFailure.connection));
    final paused = await downloader().run(region);
    expect(paused.status, RegionStatus.paused);
    expect(paused.problem, RegionProblem.connection);
    expect(paused.canResume, isTrue);
  });

  test('an answer that retrying can\'t fix pauses it at once', () async {
    final region = await newRegion();
    fetcher.failures.add(TileFetchFailure.server);
    final paused = await downloader().run(region);
    expect(paused.problem, RegionProblem.server);
    expect(waits, isEmpty);
  });

  test('sizes are within the limits the downloader checks', () async {
    // The downloader also refuses anything over 3,000 tiles before any
    // request; no real size can get there (region_plan_test).
    final region = await newRegion();
    expect(region.plan.tileCount, lessThanOrEqualTo(RegionPlan.maxTiles));
    expect(RegionDownloader.defaultByteLimit,
        lessThan(RegionPlan.maxBytes),
        reason: 'stops a little under 50 MB');
  });

  test('pausing while waiting to retry stops without another request',
      () async {
    final region = await newRegion();
    final cancel = DownloadCancel();
    fetcher.failures.addAll(List.filled(10, TileFetchFailure.busy));
    final d = RegionDownloader(store, fetcher, wait: (d) async {
      cancel.cancel();
    });
    final paused = await d.run(region, cancel: cancel);
    expect(paused.status, RegionStatus.paused);
    expect(paused.problem, isNull);
    expect(fetcher.asked, hasLength(2), reason: 'one per worker');
  });

  test('progress reports tiles and bytes', () async {
    final region = await newRegion();
    DownloadProgress? last;
    await downloader().run(region, onProgress: (p) => last = p);
    expect(last!.regionId, region.id);
    expect(last!.totalTiles, region.plannedTiles);
    expect(last!.fraction, 1);
    expect(last!.downloadedBytes, region.plannedTiles * fetcher.tileBytes);
  });

  test('gate: requests in flight finish before pause takes effect', () async {
    final region = await newRegion();
    final cancel = DownloadCancel();
    fetcher.gate = Completer<void>();
    final running = downloader().run(region, cancel: cancel);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    cancel.cancel();
    fetcher.gate!.complete();
    final paused = await running;
    expect(paused.doneTiles, 2, reason: 'the two in flight are kept');
  });
}
