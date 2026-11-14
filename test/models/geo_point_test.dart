import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/models/geo_point.dart';

void main() {
  group('GeoPoint', () {
    test('accepts valid coordinates, including the extremes', () {
      expect(() => GeoPoint(0, 0), returnsNormally);
      expect(() => GeoPoint(90, 180), returnsNormally);
      expect(() => GeoPoint(-90, -180), returnsNormally);
      final p = GeoPoint(60.1699, 24.9384); // Helsinki
      expect(p.latitude, 60.1699);
      expect(p.longitude, 24.9384);
    });

    test('rejects latitude outside -90..90', () {
      expect(() => GeoPoint(90.0001, 0), throwsRangeError);
      expect(() => GeoPoint(-91, 0), throwsRangeError);
    });

    test('rejects longitude outside -180..180', () {
      expect(() => GeoPoint(0, 180.5), throwsRangeError);
      expect(() => GeoPoint(0, -181), throwsRangeError);
    });

    test('rejects NaN and infinity', () {
      expect(() => GeoPoint(double.nan, 0), throwsRangeError);
      expect(() => GeoPoint(0, double.infinity), throwsRangeError);
    });

    test('has value equality', () {
      expect(GeoPoint(1.5, 2.5), GeoPoint(1.5, 2.5));
      expect(GeoPoint(1.5, 2.5).hashCode, GeoPoint(1.5, 2.5).hashCode);
      expect(GeoPoint(1.5, 2.5), isNot(GeoPoint(2.5, 1.5)));
    });
  });
}
