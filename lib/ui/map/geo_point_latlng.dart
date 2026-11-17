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
}
