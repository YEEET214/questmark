import 'package:latlong2/latlong.dart';

import '../../models/geo_point.dart';

/// Converts between our model type and the map library's type. This is the
/// only place the two meet (PLAN.md D3: the models don't depend on the
/// map package).
extension GeoPointToLatLng on GeoPoint {
  LatLng toLatLng() => LatLng(latitude, longitude);
}

extension LatLngToGeoPoint on LatLng {
  GeoPoint toGeoPoint() => GeoPoint(latitude, longitude);

  /// A point picked on the map, made safe to store:
  /// * longitude wrapped into -180..180 (the map can be panned past the
  ///   date line, giving e.g. 190°, which is -170°);
  /// * latitude clamped to -90..90;
  /// * both rounded to 6 decimals (about 0.1 m), so a stored location
  ///   doesn't carry meaningless digits.
  GeoPoint toPickedGeoPoint() {
    double round6(double v) => (v * 1e6).roundToDouble() / 1e6;
    final lng = ((longitude + 180) % 360 + 360) % 360 - 180;
    final lat = latitude.clamp(-90.0, 90.0);
    return GeoPoint(round6(lat), round6(lng));
  }
}
