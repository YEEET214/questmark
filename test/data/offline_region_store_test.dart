import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/data/offline_region_store.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/offline_region.dart';
import 'package:questmark/models/region_plan.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_region_store.dart';

void main() {
  late OfflineRegionStore store;
  final dundee = GeoPoint(56.462, -2.971);
  final created = DateTime(2026, 11, 23, 10);

  setUp(() async => store = await openTestRegionStore());
  tearDown(() => store.close());

  Future<OfflineRegion> newRegion({String name = 'Area'}) => store
      .createRegion(
          name: name, center: dundee, size: RegionSize.small, createdAt: created);

  Uint8List bytes(int n) => Uint8List.fromList(List.filled(n, 7));
  const a = TileId(14, 8000, 5000);
  const b = TileId(14, 8001, 5000);

  test('a new region: downloading, planned tile count, nothing yet', () async {
    final r = await newRegion(name: 'My area');
    expect(r.name, 'My area');
    expect(r.nameIsAuto, isTrue);
    expect(r.center, dundee);
    expect(r.size, RegionSize.small);
    expect(r.status, RegionStatus.downloading);
    expect(r.plannedTiles, RegionPlan(dundee, RegionSize.small).tileCount);
    expect(r.doneTiles, 0);
    expect(r.coveredRadius, -1);
    expect(r.createdAt, created);
    expect(await store.regions(), hasLength(1));
  });

  test('regions are listed newest first', () async {
    await newRegion(name: 'old');
    await store.createRegion(
        name: 'new',
        center: dundee,
        size: RegionSize.small,
        createdAt: created.add(const Duration(days: 1)));
    expect((await store.regions()).map((r) => r.name), ['new', 'old']);
  });

  test('downloaded tiles are stored and counted; the map can read them',
      () async {
    final r = await newRegion();
    await store.addDownloaded(r.id, a, bytes(100), downloaded: 100);
    await store.addDownloaded(r.id, b, Uint8List(0), downloaded: 0);
    final after = (await store.region(r.id))!;
    expect(after.doneTiles, 2);
    expect(after.bytes, 100);
    expect(after.downloadedBytes, 100);
    expect(await store.tilesOf(r.id), {a, b});
    expect(await store.tile(a.z, a.x, a.y), bytes(100));
    // Empty: "the server had no tile here".
    expect(await store.tile(b.z, b.x, b.y), isEmpty);
    expect(await store.tile(14, 1, 1), isNull);
    expect(await store.hasTiles(), isTrue);
    expect(await store.totalBytes(), 100);
  });

  test('a tile another region has is shared, not downloaded or stored twice',
      () async {
    final first = await newRegion(name: 'first');
    final second = await newRegion(name: 'second');
    await store.addDownloaded(first.id, a, bytes(100), downloaded: 100);

    expect(await store.addExisting(second.id, a), isTrue);
    expect(await store.addExisting(second.id, b), isFalse);
    final s = (await store.region(second.id))!;
    expect(s.doneTiles, 1);
    expect(s.bytes, 100, reason: 'it uses 100 bytes of map');
    expect(s.downloadedBytes, 0, reason: 'but cost no download');
    expect(await store.totalBytes(), 100, reason: 'stored once');
  });

  test('adding the same tile twice to a region counts it once', () async {
    final r = await newRegion();
    await store.addDownloaded(r.id, a, bytes(10), downloaded: 10);
    await store.addExisting(r.id, a);
    expect((await store.region(r.id))!.doneTiles, 1);
  });

  test('deleting a region keeps tiles that another region still uses',
      () async {
    final first = await newRegion(name: 'first');
    final second = await newRegion(name: 'second');
    await store.addDownloaded(first.id, a, bytes(100), downloaded: 100);
    await store.addDownloaded(first.id, b, bytes(50), downloaded: 50);
    await store.addExisting(second.id, a);

    await store.deleteRegion(first.id);
    expect(await store.region(first.id), isNull);
    expect(await store.tile(a.z, a.x, a.y), isNotNull, reason: 'shared');
    expect(await store.tile(b.z, b.x, b.y), isNull, reason: 'only first');
    expect(await store.totalBytes(), 100);

    await store.deleteRegion(second.id);
    expect(await store.tile(a.z, a.x, a.y), isNull);
    expect(await store.hasTiles(), isFalse);
    expect(await store.regions(), isEmpty);
  });

  test('status, problem and coverage are saved', () async {
    final r = await newRegion();
    await store.setStatus(r.id, RegionStatus.paused,
        problem: RegionProblem.connection, coveredRadius: 3);
    var after = (await store.region(r.id))!;
    expect(after.status, RegionStatus.paused);
    expect(after.problem, RegionProblem.connection);
    expect(after.coveredRadius, 3);
    expect(after.canResume, isTrue);

    await store.setStatus(r.id, RegionStatus.complete, coveredRadius: 7);
    after = (await store.region(r.id))!;
    expect(after.problem, isNull);
    expect(after.canResume, isFalse);
  });

  test('downloads still "running" at start-up are paused as interrupted',
      () async {
    final running = await newRegion(name: 'running');
    final done = await newRegion(name: 'done');
    await store.setStatus(done.id, RegionStatus.complete);
    await store.pauseInterrupted();
    final r = (await store.region(running.id))!;
    expect(r.status, RegionStatus.paused);
    expect(r.problem, RegionProblem.interrupted);
    expect((await store.region(done.id))!.status, RegionStatus.complete);
  });

  test('renaming beats a place name that arrives later', () async {
    final r = await newRegion(name: 'My area');
    await store.setAutoName(r.id, 'Dundee');
    expect((await store.region(r.id))!.name, 'Dundee');
    await store.rename(r.id, 'Home');
    await store.setAutoName(r.id, 'Somewhere else');
    final after = (await store.region(r.id))!;
    expect(after.name, 'Home');
    expect(after.nameIsAuto, isFalse);
  });

  test('settings are remembered', () async {
    expect(await store.setting('offer_my_area'), isNull);
    await store.setSetting('offer_my_area', 'no');
    expect(await store.setting('offer_my_area'), 'no');
    await store.setSetting('offer_my_area', 'yes');
    expect(await store.setting('offer_my_area'), 'yes');
  });

  test('a store on disk keeps its regions across opens', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('regions_test');
    final path = '${dir.path}/${OfflineRegionStore.fileName}';
    var s = await OfflineRegionStore.open(path: path, factory: databaseFactoryFfi);
    await s.createRegion(
        name: 'kept', center: dundee, size: RegionSize.small, createdAt: created);
    await s.close();
    s = await OfflineRegionStore.open(path: path, factory: databaseFactoryFfi);
    expect((await s.regions()).single.name, 'kept');
    await s.close();
    expect(File(path).existsSync(), isTrue);
    await dir.delete(recursive: true);
  });
}
