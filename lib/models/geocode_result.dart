import 'package:flutter/foundation.dart';

import 'geo_point.dart';

/// One address-search hit (PLAN.md D6).
@immutable
class GeocodeResult {
  const GeocodeResult({
    required this.label,
    required this.fullName,
    required this.point,
  });

  /// Short, readable address, e.g. "Oodi, Töölönlahdenkatu 4, Helsinki".
  /// This is what gets stored as a quest's address.
  final String label;

  /// Nominatim's full name, with district, region, postcode and country.
  /// Shown under the label in the results, to tell similar places apart.
  final String fullName;

  final GeoPoint point;

  Map<String, Object?> toJson() => {
        'label': label,
        'fullName': fullName,
        'lat': point.latitude,
        'lng': point.longitude,
      };

  factory GeocodeResult.fromJson(Map<String, Object?> json) => GeocodeResult(
        label: json['label']! as String,
        fullName: json['fullName']! as String,
        point: GeoPoint(
          (json['lat']! as num).toDouble(),
          (json['lng']! as num).toDouble(),
        ),
      );

  @override
  bool operator ==(Object other) =>
      other is GeocodeResult &&
      other.label == label &&
      other.fullName == fullName &&
      other.point == point;

  @override
  int get hashCode => Object.hash(label, fullName, point);

  @override
  String toString() => 'GeocodeResult($label, $point)';
}
