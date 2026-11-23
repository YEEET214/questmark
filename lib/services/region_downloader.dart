import 'dart:async';

import '../data/offline_region_store.dart';
import '../models/offline_region.dart';
import '../models/region_plan.dart';
import 'tile_fetcher.dart';

/// Lets the user stop a running download.
class DownloadCancel {
  bool _requested = false;
  bool get requested => _requested;
  void cancel() => _requested = true;
}

/// How far a download is.
class DownloadProgress {
  const DownloadProgress({
    required this.regionId,
    required this.doneTiles,
    required this.totalTiles,
    required this.downloadedBytes,
  });

  final int regionId;
  final int doneTiles;
  final int totalTiles;
  final int downloadedBytes;

  double get fraction => totalTiles == 0 ? 1 : doneTiles / totalTiles;
}

/// Downloads a region's tiles from OpenFreeMap into the
/// [OfflineRegionStore], within OpenFreeMap's rules for offline downloads
/// (PLAN.md D4, D26):
///
/// * at most [RegionPlan.maxTiles] tiles, checked before any request;
/// * stops before [RegionPlan.maxBytes] (50 MB), counted over the whole
///   region, resumes included; the middle is downloaded first, so what's
///   there is still a usable square;
/// * [parallel] requests at a time (2; the limit is 4);
/// * the User-Agent is set by the [TileFetcher].
///
/// Resuming skips tiles the region already has, and tiles another region
/// already downloaded are shared instead of downloaded again.
class RegionDownloader {
  RegionDownloader(
    this._store,
    this._fetcher, {
    this.parallel = 2,
    this.byteLimit = defaultByteLimit,
    this.retryDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 6),
      Duration(seconds: 15),
    ],
    Future<void> Function(Duration)? wait,
  }) : _wait = wait ?? Future<void>.delayed;

  /// Stops a little under 50 MB, leaving room for the requests still in
  /// flight when the limit is reached.
  static const defaultByteLimit = RegionPlan.maxBytes - 1000 * 1000;

  final OfflineRegionStore _store;
  final TileFetcher _fetcher;
  final int parallel;
  final int byteLimit;

  /// Pauses before each retry of a failed tile; when they're used up, the
  /// download pauses.
  final List<Duration> retryDelays;
  final Future<void> Function(Duration) _wait;

  /// Downloads what [region] is missing, then records the outcome in the
  /// store: complete, limit reached, or paused (with the reason). Returns
  /// the updated region.
  Future<OfflineRegion> run(
    OfflineRegion region, {
    DownloadCancel? cancel,
    void Function(DownloadProgress)? onProgress,
  }) async {
    final plan = region.plan;
    final tiles = plan.tiles;
    if (tiles.length > RegionPlan.maxTiles) {
      throw StateError('${tiles.length} tiles is over OpenFreeMap\'s limit');
    }
    if (region.status == RegionStatus.limitReached) return region;

    await _store.setStatus(region.id, RegionStatus.downloading);
    final done = await _store.tilesOf(region.id);
    final todo = [for (final t in tiles) if (!done.contains(t)) t];
    var downloaded = region.downloadedBytes;
    var next = 0;
    var limitReached = downloaded >= byteLimit;
    TileFetchFailure? failure;

    void report() => onProgress?.call(DownloadProgress(
          regionId: region.id,
          doneTiles: done.length,
          totalTiles: tiles.length,
          downloadedBytes: downloaded,
        ));

    bool stopped() =>
        limitReached || failure != null || (cancel?.requested ?? false);

    Future<void> worker() async {
      while (!stopped() && next < todo.length) {
        final tile = todo[next++];
        if (await _store.addExisting(region.id, tile)) {
          done.add(tile);
          report();
          continue;
        }
        final (fetched, why) = await _fetchWithRetries(tile, stopped);
        if (fetched == null) {
          // Out of retries (why), or stopped while waiting to retry. The
          // tile is simply fetched on resume.
          failure ??= why;
          return;
        }
        await _store.addDownloaded(region.id, tile, fetched.data,
            downloaded: fetched.downloaded);
        done.add(tile);
        downloaded += fetched.downloaded;
        if (downloaded >= byteLimit) limitReached = true;
        report();
      }
    }

    report();
    await Future.wait([for (var i = 0; i < parallel; i++) worker()]);

    final covered = plan.coveredRadius(done);
    final RegionStatus status;
    RegionProblem? problem;
    if (done.length >= tiles.length) {
      status = RegionStatus.complete;
    } else if (limitReached) {
      status = RegionStatus.limitReached;
    } else {
      status = RegionStatus.paused;
      problem = switch (failure) {
        null => null, // the user paused it
        TileFetchFailure.connection => RegionProblem.connection,
        TileFetchFailure.busy || TileFetchFailure.server =>
          RegionProblem.server,
      };
    }
    await _store.setStatus(region.id, status,
        problem: problem, coveredRadius: covered);
    return (await _store.region(region.id))!;
  }

  /// The tile; or no tile and the reason, when it still failed after the
  /// retries; or neither, when the download was stopped meanwhile.
  Future<(FetchedTile?, TileFetchFailure?)> _fetchWithRetries(
      TileId tile, bool Function() stopped) async {
    for (var attempt = 0;; attempt++) {
      try {
        return (await _fetcher.fetch(tile), null);
      } on TileFetchException catch (e) {
        if (!e.retryable || attempt >= retryDelays.length) {
          return (null, e.failure);
        }
      }
      await _wait(retryDelays[attempt]);
      if (stopped()) return (null, null);
    }
  }
}
