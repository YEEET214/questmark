import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/offline_region.dart';
import 'package:questmark/models/region_plan.dart';
import 'package:questmark/services/region_downloader.dart';
import 'package:questmark/state/offline_maps_controller.dart';
import 'package:questmark/ui/map/map_attribution.dart';
import 'package:questmark/ui/offline/region_select_page.dart';
import 'package:questmark/ui/offline/region_texts.dart';

import '../../helpers/fake_offline_maps.dart';

void main() {
  late FakeOfflineMaps maps;
  late MapController map;
  final dundee = GeoPoint(56.462, -2.971);

  Future<void> pump(WidgetTester tester) async {
    maps = FakeOfflineMaps();
    map = MapController();
    await tester.pumpWidget(ChangeNotifierProvider<OfflineMapsController>.value(
      value: maps,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => RegionSelectPage(
                        initialCenter: dundee,
                        baseLayer: const SizedBox.shrink(),
                        mapController: map,
                      ))),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  String estimate(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const Key('regionSelectEstimate')))
      .data!;

  testWidgets('a map with the square, the estimate and the credits',
      (tester) async {
    await pump(tester);
    expect(find.text('Choose an area'), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byKey(const Key('regionSquare')), findsOneWidget);
    expect(find.byType(MapAttribution), findsOneWidget);
    expect(estimate(tester),
        regionEstimate(RegionPlan(dundee, RegionSize.medium)));
    expect(maps.downloads, isEmpty, reason: 'nothing before the button');
  });

  testWidgets('a bigger size zooms out so the square still fits',
      (tester) async {
    await pump(tester);
    final medium = map.camera.zoom;
    expect(map.camera.center.latitude, closeTo(dundee.latitude, 0.0001));

    await tester.tap(find.byKey(const Key('regionSize-large')));
    await tester.pumpAndSettle();
    expect(estimate(tester),
        regionEstimate(RegionPlan(dundee, RegionSize.large)));
    // 45 tiles instead of 29 across: log2(45 / 29) ≈ 0.63 zoom levels out.
    expect(map.camera.zoom, closeTo(medium - 0.63, 0.02));
    expect(map.camera.center.latitude, closeTo(dundee.latitude, 0.0001));
  });

  testWidgets('Download starts this area and goes back', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('regionSize-small')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('regionSelectDownload')));
    await tester.pumpAndSettle();

    final d = maps.downloads.single;
    expect(d.size, RegionSize.small);
    expect(d.myArea, isFalse);
    expect(d.center.latitude, closeTo(dundee.latitude, 0.0001));
    expect(d.center.longitude, closeTo(dundee.longitude, 0.0001));
    expect(find.text('open'), findsOneWidget, reason: 'back');
    expect(find.textContaining('Downloading'), findsOneWidget);
  });

  testWidgets('another download running: says so and stays', (tester) async {
    await pump(tester);
    maps.progress = const DownloadProgress(
        regionId: 1, doneTiles: 1, totalTiles: 10, downloadedBytes: 1);
    await tester.tap(find.byKey(const Key('regionSelectDownload')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Another download is running'), findsOneWidget);
    expect(find.text('Choose an area'), findsOneWidget);
  });
}
