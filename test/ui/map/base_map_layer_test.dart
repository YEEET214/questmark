import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:questmark/data/mbtiles_archive.dart';
import 'package:questmark/data/offline_region_store.dart';
import 'package:questmark/ui/map/base_map_layer.dart';
import 'package:questmark/ui/map/map_config.dart';
import 'package:questmark/ui/map/world_map_tiles.dart';

import '../../helpers/test_mbtiles.dart';

/// A real (tiny) style: a background layer and an in-memory OpenFreeMap
/// source, so no network is involved.
vt.Style _style(String name) => vt.Style(
      name: name,
      theme: const vt.ThemeReader().read({
        'version': 8,
        'sources': {
          'openmaptiles': {'type': 'vector'},
        },
        'layers': [
          {
            'id': 'background',
            'type': 'background',
            'paint': {'background-color': '#eeeeee'},
          },
        ],
      }, id: name),
      providers: vt.TileProviders({
        'openmaptiles': vt.MemoryVectorTileProvider(tiles: {}),
      }),
    );

/// The success path with real map tiles needs the network and a device,
/// so it's checked by hand on a phone. These tests cover what the app
/// decides around it: which style and tiles to use, and what to show when
/// loading fails.
Future<MbTilesArchive?> noWorldMap() async => null;

Future<vt.Style> noOfflineStyle(LocalTiles _) =>
    Future.error(StateError('no offline style expected'));

void main() {

  Future<void> pumpLayer(
    WidgetTester tester,
    StyleLoader loader, {
    WorldMapLoader loadWorldMap = noWorldMap,
    OfflineStyleLoader loadOfflineStyle = noOfflineStyle,
  }) {
    // Inside a real FlutterMap, as in the app.
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FlutterMap(
          options: const MapOptions(
              initialCenter: LatLng(60, 25), initialZoom: 3),
          children: [
            OpenFreeMapLayer(
              loadStyle: loader,
              loadWorldMap: loadWorldMap,
              loadOfflineStyle: loadOfflineStyle,
              loadTileCache: noTileCache,
            ),
          ],
        ),
      ),
    ));
  }

  testWidgets('shows nothing while the style is loading', (tester) async {
    final pending = Completer<vt.Style>();
    await pumpLayer(tester, () => pending.future);
    await tester.pump();

    expect(find.byType(MapLoadErrorBanner), findsNothing);
    expect(find.byType(vt.VectorTileLayer), findsNothing);
  });

  testWidgets('a failed load with no world map shows the error banner',
      (tester) async {
    await pumpLayer(tester, () async => throw Exception('offline'));
    await tester.pumpAndSettle();

    expect(find.byType(MapLoadErrorBanner), findsOneWidget);
    expect(find.textContaining("Couldn't load the map"), findsOneWidget);
  });

  testWidgets('Retry loads the style again', (tester) async {
    var calls = 0;
    final second = Completer<vt.Style>();
    await pumpLayer(tester, () {
      calls++;
      return calls == 1 ? Future.error(Exception('offline')) : second.future;
    });
    await tester.pumpAndSettle();
    expect(calls, 1);

    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(calls, 2);
    // While the retry is in flight, the banner is hidden.
    expect(find.byType(MapLoadErrorBanner), findsNothing);
  });

  group('with the bundled world map (Phase 8a, D7)', () {
    late MbTilesArchive world;
    setUp(() async => world = await openTestMbTiles({'0/0/0': [1]}));
    tearDown(() => world.close());

    group('loadBaseMap', () {
      test('online: the online style, with the world map in front', () async {
        final online = _style('online');
        final map = await loadBaseMap(
          loadStyle: () async => online,
          loadOfflineStyle: noOfflineStyle,
          loadWorldMap: () async => world,
        );
        expect(map.offline, isFalse);
        expect(map.style, same(online));
        expect(map.providers()['openmaptiles'], isA<LocalFirstTileProvider>());
      });

      test('online without a world map: the style as it is', () async {
        final online = _style('online');
        final map = await loadBaseMap(
          loadStyle: () async => online,
          loadOfflineStyle: noOfflineStyle,
          loadWorldMap: noWorldMap,
        );
        expect(map.providers(), same(online.providers));
      });

      test('no connection at all: the bundled offline style', () async {
        final offline = _style('offline');
        MbTilesArchive? usedWorld;
        final map = await loadBaseMap(
          loadStyle: () async => throw Exception('offline'),
          loadOfflineStyle: (local) async {
            usedWorld = local.world;
            return offline;
          },
          loadWorldMap: () async => world,
        );
        expect(map.offline, isTrue);
        expect(map.style, same(offline));
        expect(usedWorld, same(world));
      });

      test('a world map that fails to open is skipped, not fatal', () async {
        final online = _style('online');
        final map = await loadBaseMap(
          loadStyle: () async => online,
          loadOfflineStyle: noOfflineStyle,
          loadWorldMap: () async => throw StateError('broken file'),
        );
        expect(map.offline, isFalse);
        expect(map.providers(), same(online.providers));
      });

      test('downloaded regions are passed on, online and offline (D26)',
          () async {
        final regions = _NoRegionTiles();
        final online = await loadBaseMap(
          loadStyle: () async => _style('online'),
          loadOfflineStyle: noOfflineStyle,
          loadWorldMap: noWorldMap,
          regions: regions,
        );
        expect(
            online.providers()['openmaptiles'], isA<LocalFirstTileProvider>());

        RegionTileSource? usedRegions;
        await loadBaseMap(
          loadStyle: () async => throw Exception('offline'),
          loadOfflineStyle: (local) async {
            usedRegions = local.regions;
            return _style('offline');
          },
          loadWorldMap: () async => world,
          regions: regions,
        );
        expect(usedRegions, same(regions));
      });

      test('nothing works: the online error is passed on', () async {
        await expectLater(
          loadBaseMap(
            loadStyle: () async => throw Exception('offline'),
            loadOfflineStyle: noOfflineStyle,
            loadWorldMap: noWorldMap,
          ),
          throwsA(isA<Exception>()),
        );
      });
    });

    testWidgets('offline: draws the world map with an "Offline world map" '
        'banner, not the error', (tester) async {
      await pumpLayer(
        tester,
        () async => throw Exception('offline'),
        loadWorldMap: () async => world,
        loadOfflineStyle: (_) async => _style('offline'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(vt.VectorTileLayer), findsOneWidget);
      expect(find.byKey(const Key('mapOfflineBanner')), findsOneWidget);
      expect(find.text('Offline world map'), findsOneWidget);
      expect(find.byType(MapLoadErrorBanner), findsNothing);
    });

    testWidgets('the layer uses the speed settings (Phase 9b), labels as '
        'before', (tester) async {
      await pumpLayer(
        tester,
        () async => throw Exception('offline'),
        loadWorldMap: () async => world,
        loadOfflineStyle: (_) async => _style('offline'),
      );
      await tester.pumpAndSettle();
      final layer =
          tester.widget<vt.VectorTileLayer>(find.byType(vt.VectorTileLayer));
      expect(layer.memoryCacheMaxBytes, MapConfig.memoryCacheBytes);
      expect(layer.memoryCacheMaxBytes, greaterThan(24 * 1024 * 1024));
      expect(layer.concurrency, MapConfig.decodeWorkers);
      expect(layer.labelMode, vt.LabelMode.screen,
          reason: 'the user chose to keep labels as they are');
    });

    testWidgets('Retry on the offline banner switches to the online map '
        'once the connection is back', (tester) async {
      var online = false;
      await pumpLayer(
        tester,
        () async => online ? _style('online') : throw Exception('offline'),
        loadWorldMap: () async => world,
        loadOfflineStyle: (_) async => _style('offline'),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mapOfflineBanner')), findsOneWidget);

      online = true;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mapOfflineBanner')), findsNothing);
      expect(find.byType(vt.VectorTileLayer), findsOneWidget);
    });

    testWidgets('a failed retry keeps the offline map on screen',
        (tester) async {
      await pumpLayer(
        tester,
        () async => throw Exception('offline'),
        loadWorldMap: () async => world,
        loadOfflineStyle: (_) async => _style('offline'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(vt.VectorTileLayer), findsOneWidget);
      expect(find.byType(MapLoadErrorBanner), findsNothing);
    });
  });
}

class _NoRegionTiles implements RegionTileSource {
  @override
  Future<Uint8List?> tile(int z, int x, int y) async => null;

  @override
  Future<bool> hasTiles() async => false;
}
