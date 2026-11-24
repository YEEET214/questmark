import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/app.dart';
import 'package:questmark/data/tile_cache.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/offline_region.dart';
import 'package:questmark/models/task.dart';
import 'package:questmark/services/location_service.dart';
import 'package:questmark/services/region_downloader.dart';

import '../helpers/fake_geocoding_service.dart';
import '../helpers/fake_location_service.dart';
import '../helpers/fake_offline_maps.dart';
import '../helpers/fake_task_repository.dart';
import '../helpers/fake_tile_cache.dart';

/// Every main screen at several phone sizes and font sizes (PLAN.md D30).
///
/// The app lays itself out in logical pixels and fills the space it gets,
/// so what can go wrong is content that doesn't fit: text pushing a row
/// past the screen edge ("RenderFlex overflowed"). Flutter reports that as
/// an error, which fails the test. Portrait only: the app is locked to it.
///
/// Sizes in logical pixels (screen pixels ÷ density):
const sizes = <String, Size>{
  'small phone 320x568': Size(320, 568),
  'emulator 360x640': Size(360, 640),
  'Galaxy S24 Ultra 412x915': Size(412, 915),
  'small tablet 600x960': Size(600, 960),
};

/// The phone's font size setting: normal, larger, and Android's largest.
const textScales = [1.0, 1.3, 2.0];

final now = DateTime(2026, 11, 24, 10);
final dundee = GeoPoint(56.462, -2.971);

List<Task> sampleTasks() => [
      Task(
        id: 1,
        title: 'Return the library books before the end of the semester',
        description: 'Three books, second floor desk',
        location: dundee,
        address: 'University of Dundee Library, Small\'s Wynd, Dundee',
        dueAt: now.add(const Duration(days: 1)),
        createdAt: DateTime(2026, 11, 1),
      ),
      Task(
        id: 2,
        title: 'Buy milk',
        location: GeoPoint(56.465, -2.98),
        dueAt: now.subtract(const Duration(days: 2)),
        createdAt: DateTime(2026, 11, 2),
      ),
      Task(
        id: 3,
        title: 'Finished quest with a fairly long title to wrap',
        isDone: true,
        createdAt: DateTime(2026, 11, 3),
      ),
      Task(id: 4, title: 'No location', createdAt: DateTime(2026, 11, 4)),
    ];

void main() {
  late FakeLocationService gps;
  late FakeOfflineMaps offlineMaps;

  Future<void> pumpApp(
    WidgetTester tester,
    Size size,
    double textScale, {
    bool locationAllowed = true,
    bool noTasks = false,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = size * 3;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    // Quest markers bob forever; without animations pumpAndSettle ends.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    });

    gps = FakeLocationService(
      permission: locationAllowed
          ? LocationPermissionState.granted
          : LocationPermissionState.denied,
    );
    offlineMaps = FakeOfflineMaps(regions: [
      region(1, name: 'Dundee'),
      region(2,
          name: 'A rather long area name, London',
          status: RegionStatus.limitReached,
          coveredRadius: 6),
      region(3,
          name: 'Muscat',
          status: RegionStatus.paused,
          problem: RegionProblem.server),
      region(4, name: 'Downloading', status: RegionStatus.downloading),
    ])
      ..totalBytes = 34500000
      ..progress = const DownloadProgress(
          regionId: 4,
          doneTiles: 590,
          totalTiles: 1180,
          downloadedBytes: 4200000);
    final cache = FakeTileCache()
      ..tiles['14/1/1'] = CachedTile(Uint8List(34000000), fresh: true);

    await tester.pumpWidget(QuestMarkApp(
      taskRepository: FakeTaskRepository(noTasks ? const [] : sampleTasks()),
      locationService: gps,
      lastLocationRepository: FakeLastLocationRepository(),
      geocodingService: FakeGeocodingService(),
      offlineMaps: offlineMaps,
      tileCache: cache,
      mapBaseLayer: const SizedBox.shrink(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> openMap(WidgetTester tester) =>
      tap(tester, find.text('Map').last);

  Future<void> openMenuItem(WidgetTester tester, String item) async {
    await tap(tester, find.byTooltip('More options'));
    await tap(tester, find.text(item));
  }

  final screens = <String, Future<void> Function(WidgetTester)>{
    'quest list': (_) async {},
    'the ⋮ menu': (t) => tap(t, find.byTooltip('More options')),
    'new quest editor': (t) => tap(t, find.text('New quest')),
    'editing a quest with a location': (t) =>
        tap(t, find.textContaining('Return the library books')),
    'location picker': (t) async {
      await tap(t, find.text('New quest'));
      // On a small screen with big text the row starts below the fold,
      // and the editor's list only builds rows once they scroll in.
      await t.scrollUntilVisible(
          find.byKey(const Key('pickLocationButton')), 100,
          scrollable: find.byType(Scrollable).first);
      await tap(t, find.byKey(const Key('pickLocationButton')));
    },
    'recycle bin': (t) => openMenuItem(t, 'Recycle bin'),
    'settings': (t) => openMenuItem(t, 'Settings'),
    'map with the long-press tip': openMap,
    'map with the "download your area?" card': (t) async {
      await openMap(t);
      offlineMaps.progress = null; // nothing downloading: it may offer
      gps.emit(fixAt(56.462, -2.971));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('regionPrompt')), findsOneWidget);
    },
    'offline maps': (t) async {
      await openMap(t);
      await tap(t, find.byKey(const Key('offlineMapsButton')));
    },
    'choose an area to download': (t) async {
      offlineMaps.progress = null;
      await openMap(t);
      await tap(t, find.byKey(const Key('offlineMapsButton')));
      await tap(t, find.byKey(const Key('downloadAreaButton')));
      expect(find.text('Choose an area'), findsOneWidget);
    },
  };

  for (final MapEntry(key: sizeName, value: size) in sizes.entries) {
    for (final scale in textScales) {
      group('$sizeName, text ×$scale', () {
        for (final MapEntry(key: screen, value: open) in screens.entries) {
          testWidgets('$screen fits', (tester) async {
            await pumpApp(tester, size, scale);
            await open(tester);
            // Any overflow was reported as an error, failing the test.
          });
        }
        testWidgets('empty quest list fits', (tester) async {
          await pumpApp(tester, size, scale, noTasks: true);
          expect(find.text('No quests yet'), findsOneWidget);
        });
        testWidgets('map with the location card fits', (tester) async {
          await pumpApp(tester, size, scale, locationAllowed: false);
          await openMap(tester);
          expect(find.byKey(const Key('locationPrompt')), findsOneWidget);
        });
      });
    }
  }
}
