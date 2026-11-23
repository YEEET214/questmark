import 'dart:math' as math;

import 'geo_point.dart';
import 'offline_region.dart';

/// One map tile in slippy-map numbering (y counted from the top).
class TileId {
  const TileId(this.z, this.x, this.y);

  final int z;
  final int x;
  final int y;

  @override
  bool operator ==(Object other) =>
      other is TileId && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(z, x, y);

  @override
  String toString() => '$z/$x/$y';
}

/// The tiles of a downloadable region (PLAN.md D7, D26): a square of
/// zoom-14 tiles centred on a point, plus every tile of zoom 5-13 that
/// overlaps it. Pure maths, no I/O.
///
/// Zoom 0-4 are left out because the world map bundled with the app has
/// them (D25). Vector tiles stop at zoom 14; the map draws closer zooms
/// from the zoom-14 data.
class RegionPlan {
  RegionPlan(this.center, this.size)
      : centerX = _tileX(center.longitude, maxZoom),
        centerY = _tileY(center.latitude, maxZoom);

  static const minZoom = 5;
  static const maxZoom = 14;

  /// OpenFreeMap's limits for one offline download.
  static const maxTiles = 3000;
  static const maxBytes = 50 * 1000 * 1000;

  final GeoPoint center;
  final RegionSize size;

  /// The centre tile at zoom 14.
  final int centerX;
  final int centerY;

  /// Zoom-14 tiles from the centre tile to the edge.
  int get half => (size.tilesAcross - 1) ~/ 2;

  /// Every tile, **from the middle outwards**: sorted by [ringOf], then by
  /// zoom. If a download has to stop early (the 50 MB limit in a big city),
  /// what's on the phone is then a smaller but complete square around the
  /// centre, at every zoom level.
  late final List<TileId> tiles = _buildTiles();

  int get tileCount => tiles.length;

  /// How far [tile] is from the centre tile, in zoom-14 tiles (Chebyshev
  /// distance, 0 for any tile that contains the centre). Once every tile
  /// with a ring ≤ r is downloaded, the square of zoom-14 tiles within r
  /// of the centre is complete at every zoom.
  ///
  /// [tile]'s x may be "unwrapped" (beyond the antimeridian); tiles in
  /// [tiles] are wrapped, so they're compared the short way round.
  int ringOf(TileId tile) {
    final shift = maxZoom - tile.z;
    final world = 1 << maxZoom;
    // The tile's span in zoom-14 tiles: [lo, hi].
    final xLo = tile.x << shift;
    final xHi = ((tile.x + 1) << shift) - 1;
    final yLo = tile.y << shift;
    final yHi = ((tile.y + 1) << shift) - 1;
    int distance(int lo, int hi, int c) =>
        c < lo ? lo - c : (c > hi ? c - hi : 0);
    // The centre may be closer by going round the world.
    final dx = [-world, 0, world]
        .map((offset) => distance(xLo + offset, xHi + offset, centerX))
        .reduce(math.min);
    final dy = distance(yLo, yHi, centerY);
    return math.max(dx, dy);
  }

  /// Whether [point] is within [radius] zoom-14 tiles of the centre tile
  /// (always false for a negative radius).
  bool contains(GeoPoint point, int radius) {
    if (radius < 0) return false;
    final world = 1 << maxZoom;
    var dx = (_tileX(point.longitude, maxZoom) - centerX) % world;
    if (dx > world ~/ 2) dx -= world;
    final dy = _tileY(point.latitude, maxZoom) - centerY;
    return dx.abs() <= radius && dy.abs() <= radius;
  }

  /// The width in km of [tiles] zoom-14 tiles at the centre's latitude.
  double kmFor(int tiles) =>
      tiles *
      _earthCircumferenceKm *
      math.cos(center.latitude * math.pi / 180) /
      (1 << maxZoom);

  /// Width of the whole square, in km.
  double get kmAcross => kmFor(size.tilesAcross);

  /// A rough download size: (countryside, big city), from tiles measured
  /// on OpenFreeMap in November 2026 (PLAN.md D26). The high end is often
  /// over [maxBytes], where the download stops.
  ({int low, int high}) estimateBytes() {
    var low = 0;
    var high = 0;
    for (final t in tiles) {
      final (l, h) = switch (t.z) {
        14 => (2000, 70000),
        12 || 13 => (3000, 110000),
        10 || 11 => (23000, 140000),
        _ => (45000, 150000),
      };
      low += l;
      high += h;
    }
    return (low: low, high: high);
  }

  List<TileId> _buildTiles() {
    final world14 = 1 << maxZoom;
    // The square at zoom 14, unwrapped in x, clamped in y.
    final x0 = centerX - half;
    final x1 = centerX + half;
    final y0 = math.max(0, centerY - half);
    final y1 = math.min(world14 - 1, centerY + half);

    final seen = <TileId>{};
    final unordered = <(int, TileId)>[];
    for (var z = minZoom; z <= maxZoom; z++) {
      final shift = maxZoom - z;
      final n = 1 << z;
      // `>>` rounds towards minus infinity, so negative x works too.
      for (var y = y0 >> shift; y <= y1 >> shift; y++) {
        for (var x = x0 >> shift; x <= x1 >> shift; x++) {
          final unwrapped = TileId(z, x, y);
          final tile = TileId(z, x % n, y);
          if (seen.add(tile)) unordered.add((ringOf(unwrapped), tile));
        }
      }
    }
    unordered.sort((a, b) {
      final byRing = a.$1.compareTo(b.$1);
      if (byRing != 0) return byRing;
      final byZoom = a.$2.z.compareTo(b.$2.z);
      if (byZoom != 0) return byZoom;
      final byY = a.$2.y.compareTo(b.$2.y);
      return byY != 0 ? byY : a.$2.x.compareTo(b.$2.x);
    });
    return [for (final e in unordered) e.$2];
  }

  /// How far out every tile is downloaded, given the tiles that are: the
  /// ring just before the first missing one. -1 if the centre is missing;
  /// [half] if everything is there.
  int coveredRadius(Set<TileId> done) {
    for (final t in tiles) {
      if (!done.contains(t)) return ringOf(t) - 1;
    }
    return half;
  }

  static const _earthCircumferenceKm = 40075.016686;

  static int _tileX(double longitude, int z) {
    final n = 1 << z;
    final x = ((longitude + 180) / 360 * n).floor();
    return x.clamp(0, n - 1);
  }

  static int _tileY(double latitude, int z) {
    final n = 1 << z;
    // Web Mercator stops at ±85.0511°.
    final lat = latitude.clamp(-85.0511, 85.0511) * math.pi / 180;
    final y = ((1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) /
            2 *
            n)
        .floor();
    return y.clamp(0, n - 1);
  }
}
