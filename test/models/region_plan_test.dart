import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/offline_region.dart';
import 'package:questmark/models/region_plan.dart';

void main() {
  final dundee = GeoPoint(56.462, -2.971);

  group('tile counts and OpenFreeMap\'s 3,000-tile limit', () {
    // Places that stress the maths: the equator, high latitudes, both
    // sides of the antimeridian, Greenwich, and tile edges.
    final places = [
      dundee,
      GeoPoint(0, 0),
      GeoPoint(51.4779, -0.0015),
      GeoPoint(-33.86, 151.21),
      GeoPoint(64.15, -21.94),
      GeoPoint(78.22, 15.65),
      GeoPoint(-77.85, 166.67),
      GeoPoint(10, 179.99),
      GeoPoint(10, -179.99),
      GeoPoint(85, 0),
      GeoPoint(-85, 0),
    ];

    for (final size in RegionSize.values) {
      test('${size.name}: never over 3,000 tiles, anywhere', () {
        for (final p in places) {
          final plan = RegionPlan(p, size);
          expect(plan.tileCount, lessThanOrEqualTo(RegionPlan.maxTiles),
              reason: '$p');
        }
      });
    }

    test('Large is the biggest square that stays under the limit', () {
      // The worst case is a square whose edges cut the most lower-zoom
      // tiles; it must still fit.
      var worst = 0;
      for (var i = 0; i < 64; i++) {
        final p = GeoPoint(56.0 + i * 0.0031, -3.0 + i * 0.0047);
        final n = RegionPlan(p, RegionSize.large).tileCount;
        if (n > worst) worst = n;
      }
      expect(worst, lessThanOrEqualTo(3000));
      expect(worst, greaterThan(2500));
    });

    test('the zoom-14 square has the chosen width, and zooms 5-14 only',
        () {
      final plan = RegionPlan(dundee, RegionSize.medium);
      final z14 = plan.tiles.where((t) => t.z == 14).toList();
      expect(z14, hasLength(29 * 29));
      expect(plan.tiles.map((t) => t.z).toSet(),
          {for (var z = 5; z <= 14; z++) z});
      expect(plan.tiles.toSet(), hasLength(plan.tileCount),
          reason: 'no duplicates');
    });

    test('sizes in km at Dundee: about 20, 39 and 61', () {
      expect(RegionPlan(dundee, RegionSize.small).kmAcross, closeTo(20.5, 1));
      expect(RegionPlan(dundee, RegionSize.medium).kmAcross, closeTo(39.6, 1));
      expect(RegionPlan(dundee, RegionSize.large).kmAcross, closeTo(61.5, 1));
      // Wider at the equator: the same tiles cover more ground.
      expect(RegionPlan(GeoPoint(0, 0), RegionSize.large).kmAcross,
          closeTo(110, 1));
    });

    test('across the antimeridian, x wraps round instead of going negative',
        () {
      final plan = RegionPlan(GeoPoint(10, 179.99), RegionSize.small);
      for (final t in plan.tiles) {
        expect(t.x, inInclusiveRange(0, (1 << t.z) - 1), reason: '$t');
      }
      final xs = plan.tiles.where((t) => t.z == 14).map((t) => t.x).toSet();
      expect(xs, contains(0));
      expect(xs, contains((1 << 14) - 1));
    });

    test('near the pole, rows stop at the map\'s edge', () {
      final plan = RegionPlan(GeoPoint(85.05, 0), RegionSize.small);
      for (final t in plan.tiles) {
        expect(t.y, inInclusiveRange(0, (1 << t.z) - 1));
      }
      expect(plan.tiles.where((t) => t.z == 14).length, lessThan(15 * 15));
    });
  });

  group('order: from the middle outwards', () {
    test('rings never go down, and the first tiles contain the centre', () {
      final plan = RegionPlan(dundee, RegionSize.medium);
      var last = 0;
      for (final t in plan.tiles) {
        final ring = plan.ringOf(t);
        expect(ring, greaterThanOrEqualTo(last));
        last = ring;
      }
      expect(last, plan.half);
      // Ring 0: one tile per zoom level, the one under the centre.
      final first = plan.tiles.takeWhile((t) => plan.ringOf(t) == 0).toList();
      expect(first.map((t) => t.z), [for (var z = 5; z <= 14; z++) z]);
      expect(first.last, TileId(14, plan.centerX, plan.centerY));
    });

    test('a download stopped after ring r covers every zoom within r', () {
      final plan = RegionPlan(dundee, RegionSize.small);
      final done = plan.tiles.where((t) => plan.ringOf(t) <= 3).toSet();
      expect(plan.coveredRadius(done), 3);
      // Every zoom-14 tile within 3 of the centre is there...
      for (var dx = -3; dx <= 3; dx++) {
        for (var dy = -3; dy <= 3; dy++) {
          expect(done,
              contains(TileId(14, plan.centerX + dx, plan.centerY + dy)));
        }
      }
      // ...and one missing tile in ring 2 drops the coverage to 1.
      final missing = plan.tiles.firstWhere((t) => plan.ringOf(t) == 2);
      expect(plan.coveredRadius(done..remove(missing)), 1);
    });

    test('coveredRadius: -1 with nothing, half with everything', () {
      final plan = RegionPlan(dundee, RegionSize.small);
      expect(plan.coveredRadius({}), -1);
      expect(plan.coveredRadius(plan.tiles.toSet()), plan.half);
    });
  });

  group('contains', () {
    final plan = RegionPlan(dundee, RegionSize.medium);

    test('the centre is inside from radius 0; nothing for -1', () {
      expect(plan.contains(dundee, 0), isTrue);
      expect(plan.contains(dundee, -1), isFalse);
    });

    test('about 15 km away: inside the medium square, not a small one', () {
      final east = GeoPoint(56.462, -2.971 + 0.24); // ~15 km east
      expect(plan.contains(east, plan.half), isTrue);
      expect(plan.contains(east, 7), isFalse);
      expect(plan.contains(GeoPoint(57.5, -2.971), plan.half), isFalse);
    });

    test('works across the antimeridian', () {
      final p = RegionPlan(GeoPoint(10, 179.99), RegionSize.small);
      expect(p.contains(GeoPoint(10, -179.98), p.half), isTrue);
    });
  });

  test('estimateBytes: countryside to big city, low < high', () {
    final e = RegionPlan(dundee, RegionSize.medium).estimateBytes();
    expect(e.low, greaterThan(1000 * 1000));
    expect(e.low, lessThan(10 * 1000 * 1000));
    // A big city's medium area is well over the 50 MB limit.
    expect(e.high, greaterThan(RegionPlan.maxBytes));
  });

  test('TileId equality and text', () {
    expect(const TileId(1, 2, 3), const TileId(1, 2, 3));
    expect(const TileId(1, 2, 3).hashCode, const TileId(1, 2, 3).hashCode);
    expect(const TileId(1, 2, 3), isNot(const TileId(1, 3, 2)));
    expect('${const TileId(14, 8, 9)}', '14/8/9');
  });

  test('RegionSize / RegionStatus names round-trip, with safe fallbacks', () {
    for (final s in RegionSize.values) {
      expect(RegionSize.fromName(s.name), s);
    }
    expect(RegionSize.fromName('huge'), RegionSize.medium);
    expect(RegionStatus.fromName('complete'), RegionStatus.complete);
    expect(RegionStatus.fromName('??'), RegionStatus.paused);
    expect(RegionProblem.fromName(null), isNull);
    expect(RegionProblem.fromName('connection'), RegionProblem.connection);
  });
}
