import 'package:flutter/foundation.dart';

import 'geo_point.dart';

/// One position report from the phone's GPS (PLAN.md D8).
@immutable
class LocationFix {
  LocationFix({
    required this.point,
    required this.accuracyMeters,
    required this.at,
  }) {
    if (!accuracyMeters.isFinite || accuracyMeters < 0) {
      throw ArgumentError.value(
        accuracyMeters,
        'accuracyMeters',
        'must be a finite number >= 0',
      );
    }
  }

  final GeoPoint point;

  /// Radius in metres within which the true position probably lies. The
  /// map draws it as the pale circle around the player dot.
  final double accuracyMeters;

  /// When the fix was taken.
  final DateTime at;

  @override
  bool operator ==(Object other) =>
      other is LocationFix &&
      other.point == point &&
      other.accuracyMeters == accuracyMeters &&
      other.at == at;

  @override
  int get hashCode => Object.hash(point, accuracyMeters, at);

  @override
  String toString() =>
      'LocationFix(${point.latitude}, ${point.longitude}, '
      '±${accuracyMeters}m, $at)';
}
