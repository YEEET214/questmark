import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../models/location_fix.dart';
import 'geo_point_latlng.dart';

/// The player's position on the map (PLAN.md D9): a blue dot with a white
/// ring, inside a pale circle showing the GPS accuracy.
abstract final class PlayerMarker {
  static const color = Color(0xFF1A73E8);
  static const double dotSize = 22;

  /// Accuracy circles bigger than this are not drawn: they'd cover the
  /// whole screen and say little more than "somewhere around here".
  static const double maxAccuracyCircleMeters = 2000;

  /// The accuracy circle, drawn in metres so it scales with the zoom.
  static Widget accuracyLayer(LocationFix fix) => CircleLayer(
    key: const ValueKey('player-accuracy'),
    circles: [
      if (fix.accuracyMeters > 0 &&
          fix.accuracyMeters <= maxAccuracyCircleMeters)
        CircleMarker(
          point: fix.point.toLatLng(),
          radius: fix.accuracyMeters,
          useRadiusInMeter: true,
          color: color.withValues(alpha: 0.15),
          borderColor: color.withValues(alpha: 0.4),
          borderStrokeWidth: 1,
        ),
    ],
  );

  static Widget dotLayer(LocationFix fix) => MarkerLayer(
    markers: [
      Marker(
        key: const ValueKey('player-marker'),
        point: fix.point.toLatLng(),
        width: dotSize,
        height: dotSize,
        child: const PlayerDot(),
      ),
    ],
  );
}

class PlayerDot extends StatelessWidget {
  const PlayerDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Your location',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: PlayerMarker.color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}
