import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/data/offline_region_store.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/offline_region.dart';
import 'package:questmark/services/geocoding_service.dart';
import 'package:questmark/services/region_downloader.dart';
import 'package:questmark/services/tile_fetcher.dart';
import 'package:questmark/state/offline_maps_controller.dart';

import '../helpers/fake_geocoding_service.dart';
import '../helpers/fake_tile_fetcher.dart';
import '../helpers/test_region_store.dart';

void main() {
  late OfflineRegionStore store;
  late FakeTileFetcher fetcher;
  late FakeGeocodingService geocoder;
  late OfflineMapsController c;
  final dundee = GeoPoint(56.462, -2.971);

  setUp(() async {
    store = await openTestRegionStore();
    fetcher = FakeTileFetcher();
    geocoder = FakeGeocodingService();
    c = OfflineMapsController(
      store,
      RegionDownloader(store, fetcher, wait: (_) async {}),
      geocoder: geocoder,
      clock: () => DateTime(2026, 11, 23, 9),
    );
    await c.load();
  });
  tearDown(() async {
    c.dispose();
    await store.close();
  });

  test('nothing is downloaded until asked', () async {
    expect(c.regions, isEmpty);
    expect(c.isDownloading, isFalse);
    expect(fetcher.asked, isEmpty);
  });

  test('download: runs to the end, then lists the region', () async {
    var notified = 0;
    c.addListener(() => notified++);
    final region = await c.download(dundee, RegionSize.small, myArea: true);
    expect(c.isDownloading, isTrue);
    expect(c.activeRegionId, region.id);
    await c.running;

    expect(c.isDownloading, isFalse);
    expect(c.progress, isNull);
    final r = c.regions.single;
    expect(r.status, RegionStatus.complete);
    expect(r.size, RegionSize.small);
    expect(r.createdAt, DateTime(2026, 11, 23, 9));
    expect(c.totalBytes, greaterThan(0));
    expect(notified, greaterThan(10), reason: 'progress updates');
  });

  test('the region is named after its town; "My area" until then', () async {
    geocoder.places[dundee] = 'Dundee';
    final region = await c.download(dundee, RegionSize.small, myArea: true);
    expect(region.name, OfflineMapsController.myAreaName);
    await c.running;
    await pumpEventQueue();
    expect(c.regions.single.name, 'Dundee');
    expect(geocoder.placeCalls, [dundee]);
  });

  test('no place name: the default name stays; a failed lookup too',
      () async {
    await c.download(dundee, RegionSize.small);
    await c.running;
    await pumpEventQueue();
    expect(c.regions.single.name, OfflineMapsController.areaName);

    geocoder.failNext =
        const GeocodingException(GeocodingFailure.offline);
    await c.download(GeoPoint(10, 10), RegionSize.small);
    await c.running;
    await pumpEventQueue();
    expect(c.regions.first.name, OfflineMapsController.areaName);
  });

  test('only one download at a time', () async {
    await c.download(dundee, RegionSize.small);
    expect(() => c.download(GeoPoint(10, 10), RegionSize.small),
        throwsStateError);
    await c.running;
  });

  test('pause, then resume where it stopped', () async {
    fetcher.latency = const Duration(milliseconds: 1);
    final region = await c.download(dundee, RegionSize.small);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await c.pause();
    expect(c.isDownloading, isFalse);
    final paused = c.regions.single;
    expect(paused.status, RegionStatus.paused);
    expect(paused.doneTiles, lessThan(region.plannedTiles));

    fetcher.latency = Duration.zero;
    await c.resume(region.id);
    await c.running;
    expect(c.regions.single.status, RegionStatus.complete);
    expect(fetcher.asked, hasLength(region.plannedTiles));
  });

  test('delete: also stops a running download, and frees the space',
      () async {
    fetcher.latency = const Duration(milliseconds: 1);
    final region = await c.download(dundee, RegionSize.small);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await c.delete(region.id);
    expect(c.isDownloading, isFalse);
    expect(c.regions, isEmpty);
    expect(c.totalBytes, 0);
    expect(await store.hasTiles(), isFalse);
  });

  test('rename (blank names are ignored)', () async {
    final region = await c.download(dundee, RegionSize.small);
    await c.running;
    await c.rename(region.id, '  Home  ');
    expect(c.regions.single.name, 'Home');
    await c.rename(region.id, '   ');
    expect(c.regions.single.name, 'Home');
  });

  test('a download interrupted by closing the app is paused on next start',
      () async {
    await store.createRegion(
        name: 'x',
        center: dundee,
        size: RegionSize.small,
        createdAt: DateTime(2026, 11, 22));
    final again = OfflineMapsController(
        store, RegionDownloader(store, fetcher));
    await again.load();
    expect(again.regions.single.status, RegionStatus.paused);
    expect(again.regions.single.problem, RegionProblem.interrupted);
    expect(fetcher.asked, isEmpty, reason: 'never resumed by itself');
    again.dispose();
  });

  group('offering the user\'s area', () {
    test('offered when outside every region, not inside one', () async {
      expect(c.shouldOfferFor(dundee), isTrue);
      await c.download(dundee, RegionSize.small, myArea: true);
      expect(c.shouldOfferFor(GeoPoint(40, 10)), isFalse,
          reason: 'not while downloading');
      await c.running;
      expect(c.shouldOfferFor(dundee), isFalse);
      expect(c.shouldOfferFor(GeoPoint(40, 10)), isTrue);
    });

    test('a paused region around the user also counts', () async {
      fetcher.failures.addAll(List.filled(10, TileFetchFailure.connection));
      await c.download(dundee, RegionSize.small, myArea: true);
      await c.running;
      expect(c.regions.single.status, RegionStatus.paused);
      expect(c.shouldOfferFor(dundee), isFalse);
    });

    test('"Not now" lasts until restart', () async {
      c.notNow();
      expect(c.shouldOfferFor(dundee), isFalse);
      final restarted = OfflineMapsController(
          store, RegionDownloader(store, fetcher));
      await restarted.load();
      expect(restarted.shouldOfferFor(dundee), isTrue);
      restarted.dispose();
    });

    test('"Don\'t ask again" is remembered; the switch turns it back on',
        () async {
      await c.setOfferMyArea(false);
      expect(c.shouldOfferFor(dundee), isFalse);
      final restarted = OfflineMapsController(
          store, RegionDownloader(store, fetcher));
      await restarted.load();
      expect(restarted.offerMyArea, isFalse);
      expect(restarted.shouldOfferFor(dundee), isFalse);

      await restarted.setOfferMyArea(true);
      expect(restarted.shouldOfferFor(dundee), isTrue);
      restarted.dispose();
    });

    test('not before the list has loaded', () {
      final fresh = OfflineMapsController(
          store, RegionDownloader(store, fetcher));
      expect(fresh.shouldOfferFor(dundee), isFalse);
      fresh.dispose();
    });
  });
}
