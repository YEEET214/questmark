import 'package:flutter/foundation.dart';

import '../data/offline_region_store.dart';
import '../models/geo_point.dart';
import '../models/offline_region.dart';
import '../services/geocoding_service.dart';
import '../services/region_downloader.dart';

/// The downloaded map regions and the one download that may be running
/// (R11, PLAN.md D7, D26). Used by the Offline maps screen and by the
/// map's "download your area?" card.
///
/// Nothing is ever downloaded unless the user asks: [download] and
/// [resume] are only called from a button.
class OfflineMapsController extends ChangeNotifier {
  OfflineMapsController(
    this._store,
    this._downloader, {
    this._geocoder,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final OfflineRegionStore _store;
  final RegionDownloader _downloader;
  final GeocodingService? _geocoder;
  final DateTime Function() _clock;

  /// Settings key: "no" after "Don't ask again".
  static const offerMyAreaKey = 'offer_my_area';

  /// Default names until a place name is found.
  static const myAreaName = 'My area';
  static const areaName = 'Map area';

  List<OfflineRegion> _regions = const [];
  bool _hasLoaded = false;
  bool _offerMyArea = true;
  bool _notNow = false;
  int _totalBytes = 0;
  DownloadProgress? _progress;
  DownloadCancel? _cancel;
  Future<void>? _running;
  final _deleting = <int>{};
  bool _disposed = false;

  /// Newest first.
  List<OfflineRegion> get regions => _regions;
  bool get hasLoaded => _hasLoaded;

  /// Space all offline maps take on the phone.
  int get totalBytes => _totalBytes;

  /// The running download, if any.
  DownloadProgress? get progress => _progress;
  bool get isDownloading => _running != null;
  int? get activeRegionId => isDownloading ? _progress?.regionId : null;

  /// Whether [id] is being deleted (it can take a few seconds: the file is
  /// compacted afterwards to give the space back).
  bool isDeleting(int id) => _deleting.contains(id);

  /// Whether the map may offer to download the user's area (off after
  /// "Don't ask again"; can be turned back on in Offline maps).
  bool get offerMyArea => _offerMyArea;

  Future<void> load() async {
    await _store.pauseInterrupted();
    _offerMyArea = await _store.setting(offerMyAreaKey) != 'no';
    await _reload();
    _hasLoaded = true;
    _notify();
  }

  Future<void> _reload() async {
    _regions = await _store.regions();
    _totalBytes = await _store.totalBytes();
  }

  /// Whether to show "Download the map for your area?" for a user at
  /// [point]: they haven't said no, nothing is downloading, and no region
  /// (finished or not) is meant to cover that spot.
  bool shouldOfferFor(GeoPoint point) =>
      _hasLoaded &&
      _offerMyArea &&
      !_notNow &&
      !isDownloading &&
      !_regions.any((r) => r.plannedAround(point));

  /// "Not now": not again until the app is restarted.
  void notNow() {
    _notNow = true;
    _notify();
  }

  /// "Don't ask again", or the switch in Offline maps.
  Future<void> setOfferMyArea(bool offer) async {
    _offerMyArea = offer;
    if (offer) _notNow = false;
    _notify();
    await _store.setSetting(offerMyAreaKey, offer ? 'yes' : 'no');
  }

  /// Starts downloading the area of [size] around [center]. [myArea]: it's
  /// the area around the user (for its name until the place is known).
  /// Throws [StateError] if a download is already running.
  Future<OfflineRegion> download(
    GeoPoint center,
    RegionSize size, {
    bool myArea = false,
  }) async {
    if (isDownloading) throw StateError('A download is already running');
    final region = await _store.createRegion(
      name: myArea ? myAreaName : areaName,
      center: center,
      size: size,
      createdAt: _clock(),
    );
    await _reload();
    _start(region);
    return region;
  }

  /// Continues a paused download where it stopped.
  Future<void> resume(int id) async {
    if (isDownloading) throw StateError('A download is already running');
    final region = await _store.region(id);
    if (region == null || !region.canResume) return;
    _start(region);
  }

  /// Stops the running download; it can be resumed later.
  Future<void> pause() async {
    _cancel?.cancel();
    await _running;
  }

  Future<void> rename(int id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _store.rename(id, trimmed);
    await _reload();
    _notify();
  }

  /// Deletes a region (stopping it first if it's downloading). Tiles that
  /// another region also uses are kept.
  Future<void> delete(int id) async {
    if (!_deleting.add(id)) return; // already being deleted
    _notify();
    try {
      if (activeRegionId == id) await pause();
      await _store.deleteRegion(id);
      await _reload();
    } finally {
      _deleting.remove(id);
      _notify();
    }
  }

  void _start(OfflineRegion region) {
    final cancel = _cancel = DownloadCancel();
    _progress = DownloadProgress(
      regionId: region.id,
      doneTiles: region.doneTiles,
      totalTiles: region.plannedTiles,
      downloadedBytes: region.downloadedBytes,
    );
    _running = _run(region, cancel);
    _notify();
  }

  Future<void> _run(OfflineRegion region, DownloadCancel cancel) async {
    if (region.nameIsAuto) _lookUpName(region);
    try {
      await _downloader.run(
        region,
        cancel: cancel,
        onProgress: (p) {
          _progress = p;
          _notify();
        },
      );
    } catch (e) {
      debugPrint('Region download failed: $e');
      await _store.setStatus(region.id, RegionStatus.paused,
          problem: RegionProblem.server);
    } finally {
      _running = null;
      _cancel = null;
      _progress = null;
      if (!_disposed) {
        await _reload();
        _notify();
      }
    }
  }

  /// Names the region after its town (Nominatim, through the cache). Runs
  /// alongside the download; if it fails, the default name stays and it's
  /// tried again on resume.
  Future<void> _lookUpName(OfflineRegion region) async {
    final geocoder = _geocoder;
    if (geocoder == null) return;
    try {
      final name = await geocoder.placeName(region.center);
      if (name == null || _disposed) return;
      await _store.setAutoName(region.id, name);
      await _reload();
      _notify();
    } catch (e) {
      debugPrint('Region name lookup failed: $e');
    }
  }

  /// For tests: completes when the running download has finished.
  @visibleForTesting
  Future<void>? get running => _running;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel();
    super.dispose();
  }
}
