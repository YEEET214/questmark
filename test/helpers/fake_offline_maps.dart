import 'package:flutter/foundation.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/offline_region.dart';
import 'package:questmark/services/region_downloader.dart';
import 'package:questmark/state/offline_maps_controller.dart';

/// An [OfflineMapsController] for widget tests: no database, no network.
/// Records what the UI asked for; tests set the state directly.
class FakeOfflineMaps extends ChangeNotifier implements OfflineMapsController {
  FakeOfflineMaps({List<OfflineRegion>? regions})
      : regions = regions ?? [];

  @override
  List<OfflineRegion> regions;
  @override
  bool hasLoaded = true;
  @override
  int totalBytes = 0;
  @override
  DownloadProgress? progress;
  @override
  bool offerMyArea = true;
  bool notNowPressed = false;

  /// Whether [shouldOfferFor] says yes (when offering is on).
  bool offer = true;

  final downloads = <({GeoPoint center, RegionSize size, bool myArea})>[];
  final resumed = <int>[];
  final deleted = <int>[];
  final renamed = <(int, String)>[];
  int pauses = 0;

  @override
  bool get isDownloading => progress != null;

  @override
  int? get activeRegionId => progress?.regionId;

  @override
  Future<void>? get running => null;

  @override
  Future<void> load() async {}

  @override
  bool shouldOfferFor(GeoPoint point) =>
      offer && offerMyArea && !notNowPressed && !isDownloading;

  @override
  void notNow() {
    notNowPressed = true;
    notifyListeners();
  }

  @override
  Future<void> setOfferMyArea(bool offer) async {
    offerMyArea = offer;
    notifyListeners();
  }

  @override
  Future<OfflineRegion> download(GeoPoint center, RegionSize size,
      {bool myArea = false}) async {
    if (isDownloading) throw StateError('busy');
    downloads.add((center: center, size: size, myArea: myArea));
    final r = region(downloads.length + 100, center: center, size: size);
    progress = DownloadProgress(
        regionId: r.id,
        doneTiles: 0,
        totalTiles: r.plannedTiles,
        downloadedBytes: 0);
    regions = [r, ...regions];
    notifyListeners();
    return r;
  }

  @override
  Future<void> resume(int id) async {
    resumed.add(id);
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    pauses++;
    progress = null;
    notifyListeners();
  }

  @override
  Future<void> rename(int id, String name) async {
    renamed.add((id, name));
    notifyListeners();
  }

  @override
  Future<void> delete(int id) async {
    deleted.add(id);
    regions = [for (final r in regions) if (r.id != id) r];
    notifyListeners();
  }
}

/// A region for tests.
OfflineRegion region(
  int id, {
  String name = 'Dundee',
  GeoPoint? center,
  RegionSize size = RegionSize.medium,
  RegionStatus status = RegionStatus.complete,
  RegionProblem? problem,
  int bytes = 12300000,
  int coveredRadius = 14,
}) =>
    OfflineRegion(
      id: id,
      name: name,
      nameIsAuto: true,
      center: center ?? GeoPoint(56.462, -2.971),
      size: size,
      status: status,
      problem: problem,
      plannedTiles: 1180,
      doneTiles: status == RegionStatus.complete ? 1180 : 400,
      bytes: bytes,
      coveredRadius: coveredRadius,
      createdAt: DateTime(2026, 11, 23, 9),
    );
