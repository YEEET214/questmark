import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/ui/map/geo_point_latlng.dart';

void main() {
  test('GeoPoint -> LatLng keeps the coordinates', () {
    expect(GeoPoint(60.17, 24.94).toLatLng(), const LatLng(60.17, 24.94));
  });

  test('LatLng -> GeoPoint keeps the coordinates', () {
    expect(const LatLng(-33.86, 151.21).toGeoPoint(), GeoPoint(-33.86, 151.21));
  });

  test('round trip is lossless', () {
    final p = GeoPoint(51.5007, -0.1246);
    expect(p.toLatLng().toGeoPoint(), p);
  });
}
