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

  group('toPickedGeoPoint (a point picked on the map)', () {
    test('rounds to 6 decimals', () {
      expect(const LatLng(60.169912345, 24.938456789).toPickedGeoPoint(),
          GeoPoint(60.169912, 24.938457));
    });

    test('wraps longitudes panned past the date line', () {
      expect(const LatLng(10, 190).toPickedGeoPoint(), GeoPoint(10, -170));
      expect(const LatLng(10, -200).toPickedGeoPoint(), GeoPoint(10, 160));
      expect(const LatLng(10, 540).toPickedGeoPoint(), GeoPoint(10, -180));
      expect(const LatLng(10, 179.5).toPickedGeoPoint(), GeoPoint(10, 179.5));
    });

    test('keeps latitude in range', () {
      // LatLng itself allows only -90..90, so this checks the edges.
      expect(const LatLng(90, 0).toPickedGeoPoint(), GeoPoint(90, 0));
      expect(const LatLng(-90, 0).toPickedGeoPoint(), GeoPoint(-90, 0));
    });
  });
}
