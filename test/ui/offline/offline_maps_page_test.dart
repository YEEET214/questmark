import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/offline_region.dart';
import 'package:questmark/services/region_downloader.dart';
import 'package:questmark/state/offline_maps_controller.dart';
import 'package:questmark/ui/offline/offline_maps_page.dart';

import '../../helpers/fake_offline_maps.dart';

void main() {
  late FakeOfflineMaps maps;

  Future<void> pump(WidgetTester tester, {GeoPoint? center}) async {
    await tester.pumpWidget(ChangeNotifierProvider<OfflineMapsController>.value(
      value: maps,
      child: MaterialApp(
        home: OfflineMapsPage(
          initialCenter: center,
          selectPage: (c) => Scaffold(body: Text('select at $c')),
        ),
      ),
    ));
  }

  Future<void> openMenu(WidgetTester tester, int id) async {
    await tester.tap(find.byKey(Key('regionMenu-$id')));
    await tester.pumpAndSettle();
  }

  setUp(() => maps = FakeOfflineMaps());

  testWidgets('no regions yet: says so', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('noRegions')), findsOneWidget);
    expect(find.text('Offline maps'), findsOneWidget);
  });

  testWidgets('lists regions with state, date, size and width',
      (tester) async {
    maps.regions = [
      region(1, name: 'Dundee'),
      region(2,
          name: 'London',
          status: RegionStatus.limitReached,
          coveredRadius: 6),
      region(3,
          name: 'Muscat',
          status: RegionStatus.paused,
          problem: RegionProblem.connection),
    ];
    maps.totalBytes = 34500000;
    await pump(tester);

    expect(find.text('Dundee'), findsOneWidget);
    expect(find.text('Ready offline'), findsOneWidget);
    expect(find.text('23-11-2026 · 12 MB · 39 km across'), findsWidgets);
    expect(
        find.textContaining('Stopped at OpenFreeMap\'s 50 MB limit'),
        findsOneWidget);
    expect(find.text('Paused: no connection'), findsOneWidget);
    expect(find.text('Offline maps use 35 MB on this phone.'),
        findsOneWidget);
  });

  testWidgets('a running download shows progress and can be paused',
      (tester) async {
    maps.regions = [region(7, status: RegionStatus.downloading)];
    maps.progress = const DownloadProgress(
        regionId: 7, doneTiles: 590, totalTiles: 1180, downloadedBytes: 4200000);
    await pump(tester);
    expect(find.text('590 of 1,180 tiles · 4.2 MB'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        0.5);

    await openMenu(tester, 7);
    await tester.tap(find.byKey(const Key('regionPause')));
    await tester.pumpAndSettle();
    expect(maps.pauses, 1);
  });

  testWidgets('a paused region can be resumed', (tester) async {
    maps.regions = [region(3, status: RegionStatus.paused)];
    await pump(tester);
    await openMenu(tester, 3);
    await tester.tap(find.byKey(const Key('regionResume')));
    await tester.pumpAndSettle();
    expect(maps.resumed, [3]);
  });

  testWidgets('a finished region has no Resume', (tester) async {
    maps.regions = [region(1)];
    await pump(tester);
    await openMenu(tester, 1);
    expect(find.byKey(const Key('regionResume')), findsNothing);
    expect(find.byKey(const Key('regionDelete')), findsOneWidget);
  });

  testWidgets('delete asks first: No keeps it, Yes deletes it',
      (tester) async {
    maps.regions = [region(1, name: 'Dundee')];
    await pump(tester);

    await openMenu(tester, 1);
    await tester.tap(find.byKey(const Key('regionDelete')));
    await tester.pumpAndSettle();
    expect(find.text('Delete "Dundee"?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('regionDeleteNo')));
    await tester.pumpAndSettle();
    expect(maps.deleted, isEmpty);

    await openMenu(tester, 1);
    await tester.tap(find.byKey(const Key('regionDelete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('regionDeleteYes')));
    await tester.pumpAndSettle();
    expect(maps.deleted, [1]);
    expect(find.byKey(const Key('noRegions')), findsOneWidget);
  });

  testWidgets('rename', (tester) async {
    maps.regions = [region(1, name: 'My area')];
    await pump(tester);
    await openMenu(tester, 1);
    await tester.tap(find.byKey(const Key('regionRename')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('regionNameField')), 'Home');
    await tester.tap(find.byKey(const Key('regionNameSave')));
    await tester.pumpAndSettle();
    expect(maps.renamed, [(1, 'Home')]);
  });

  testWidgets('the switch turns the "download your area?" offer off and on',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('offerMyAreaSwitch')));
    await tester.pump();
    expect(maps.offerMyArea, isFalse);
    await tester.tap(find.byKey(const Key('offerMyAreaSwitch')));
    await tester.pump();
    expect(maps.offerMyArea, isTrue);
  });

  testWidgets('"Download an area" opens the area picker at the map\'s centre',
      (tester) async {
    final center = GeoPoint(60.17, 24.94);
    await pump(tester, center: center);
    await tester.tap(find.byKey(const Key('downloadAreaButton')));
    await tester.pumpAndSettle();
    expect(find.text('select at $center'), findsOneWidget);
  });

  testWidgets('... but not while another download is running',
      (tester) async {
    maps.regions = [region(7, status: RegionStatus.downloading)];
    maps.progress = const DownloadProgress(
        regionId: 7, doneTiles: 1, totalTiles: 10, downloadedBytes: 1);
    await pump(tester);
    await tester.tap(find.byKey(const Key('downloadAreaButton')));
    await tester.pumpAndSettle();
    expect(find.textContaining('select at'), findsNothing);
    expect(find.textContaining('Wait for the current download'),
        findsOneWidget);
  });
}
