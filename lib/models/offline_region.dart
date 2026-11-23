import 'geo_point.dart';
import 'region_plan.dart';

/// How big a downloaded region is (PLAN.md D26), counted in detailed
/// (zoom-14) tiles across, so the 3,000-tile limit holds everywhere on
/// Earth. In kilometres the same square is wider near the equator and
/// narrower near the poles; [RegionPlan.kmAcross] gives the real width.
enum RegionSize {
  /// About 20 km across at Dundee's latitude; ~350 tiles.
  small(15, 'Small'),

  /// About 39 km across at Dundee's latitude; ~1,200 tiles.
  medium(29, 'Medium'),

  /// About 61 km across at Dundee's latitude; at most ~2,860 tiles.
  large(45, 'Large');

  const RegionSize(this.tilesAcross, this.label);

  /// Zoom-14 tiles along each side. Odd, so the centre tile is in the
  /// middle.
  final int tilesAcross;
  final String label;

  static RegionSize fromName(String name) =>
      values.firstWhere((s) => s.name == name, orElse: () => medium);
}

enum RegionStatus {
  /// A download is running (or was, when the app was closed).
  downloading,

  /// Stopped before the end; can be resumed. See [OfflineRegion.problem].
  paused,

  /// Every tile is on the phone.
  complete,

  /// Stopped at OpenFreeMap's 50 MB per-download limit (a big city). The
  /// middle of the area is downloaded and usable; it can't be resumed.
  limitReached;

  static RegionStatus fromName(String name) =>
      values.firstWhere((s) => s.name == name, orElse: () => paused);
}

/// Why a download is paused.
enum RegionProblem {
  /// No connection, or the server didn't answer in time.
  connection,

  /// The map server kept answering with errors.
  server,

  /// The app was closed during the download.
  interrupted;

  static RegionProblem? fromName(String? name) {
    for (final p in values) {
      if (p.name == name) return p;
    }
    return null;
  }
}

/// A detailed map area downloaded for offline use (R11, PLAN.md D7, D26).
class OfflineRegion {
  const OfflineRegion({
    required this.id,
    required this.name,
    required this.nameIsAuto,
    required this.center,
    required this.size,
    required this.status,
    required this.plannedTiles,
    required this.createdAt,
    this.doneTiles = 0,
    this.bytes = 0,
    this.downloadedBytes = 0,
    this.coveredRadius = -1,
    this.problem,
  });

  final int id;

  /// Shown in the list. Until the user renames it, it's the place name
  /// looked up for [center] ([nameIsAuto]).
  final String name;
  final bool nameIsAuto;

  final GeoPoint center;
  final RegionSize size;
  final RegionStatus status;

  /// Tiles in the whole area, and how many are on the phone.
  final int plannedTiles;
  final int doneTiles;

  /// Space its tiles take on the phone (a tile shared with another region
  /// is counted in both).
  final int bytes;

  /// What was actually downloaded for it, for the 50 MB limit. Tiles that
  /// another region already had cost nothing.
  final int downloadedBytes;

  /// How far from the centre tile (in zoom-14 tiles) every zoom level is
  /// complete; -1 if nothing is yet. See [RegionPlan.ringOf].
  final int coveredRadius;

  final RegionProblem? problem;
  final DateTime createdAt;

  RegionPlan get plan => RegionPlan(center, size);

  /// Whether [point] is inside the part of this region that is fully
  /// downloaded.
  bool covers(GeoPoint point) => plan.contains(point, coveredRadius);

  /// Whether [point] is inside the area this region is meant to cover,
  /// downloaded or not.
  bool plannedAround(GeoPoint point) => plan.contains(point, plan.half);

  bool get canResume =>
      status == RegionStatus.paused || status == RegionStatus.downloading;

  /// Width of the fully downloaded square, in km.
  double get coveredKm =>
      coveredRadius < 0 ? 0 : plan.kmFor(2 * coveredRadius + 1);
}
