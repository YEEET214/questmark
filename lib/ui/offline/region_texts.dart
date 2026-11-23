import '../../models/offline_region.dart';
import '../../models/region_plan.dart';
import '../formatting.dart';

/// "≈ 40 km across · 1,180 tiles · 3–50 MB": what a download would be,
/// before it starts. The size is a range (countryside to big city); the
/// download never goes over 50 MB.
String regionEstimate(RegionPlan plan) {
  final bytes = plan.estimateBytes();
  final high = bytes.high > RegionPlan.maxBytes ? RegionPlan.maxBytes : bytes.high;
  final low = bytes.low > high ? high : bytes.low;
  return '≈ ${formatKm(plan.kmAcross)} across · '
      '${formatCount(plan.tileCount)} tiles · '
      '${_mbNumber(low)}–${formatMegabytes(high)}';
}

String _mbNumber(int bytes) =>
    formatMegabytes(bytes).replaceAll(' MB', '');

/// Explains the size range under an estimate.
const regionEstimateNote =
    'More in big cities. A download stops at OpenFreeMap\'s 50 MB limit, '
    'with the middle of the area downloaded first.';

/// Where the place name comes from (the privacy note, PLAN.md D24, D26).
const regionNameNote =
    'The area\'s name is looked up with OpenStreetMap\'s Nominatim, which '
    'receives its centre, rounded to about 1 km.';

/// One line about a region's state, for the Offline maps list.
String regionStatusText(OfflineRegion r) => switch (r.status) {
      RegionStatus.complete => 'Ready offline',
      RegionStatus.limitReached =>
        'Ready offline: the middle ${formatKm(r.coveredKm)}. Stopped at '
            'OpenFreeMap\'s 50 MB limit',
      RegionStatus.downloading => 'Downloading…',
      RegionStatus.paused => switch (r.problem) {
          null => 'Paused',
          RegionProblem.connection => 'Paused: no connection',
          RegionProblem.server => 'Paused: the map server isn\'t answering',
          RegionProblem.interrupted => 'Paused: the app was closed',
        },
    };
