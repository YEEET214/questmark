import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/ui/formatting.dart';

void main() {
  group('formatDate (dd-mm-yyyy)', () {
    test('formats day-month-year with dashes', () {
      expect(formatDate(DateTime(2026, 11, 20)), '20-11-2026');
    });

    test('pads single-digit days and months with a zero', () {
      expect(formatDate(DateTime(2026, 1, 5)), '05-01-2026');
    });

    test('ignores the time of day', () {
      expect(formatDate(DateTime(2026, 12, 31, 23, 59)), '31-12-2026');
    });

    test('pads years to four digits', () {
      expect(formatDate(DateTime(999, 3, 4)), '04-03-0999');
    });
  });

  group('formatCoordinates', () {
    test('latitude, longitude with five decimals', () {
      expect(formatCoordinates(GeoPoint(60.1699, 24.938456)),
          '60.16990, 24.93846');
    });

    test('keeps the minus sign for south and west', () {
      expect(formatCoordinates(GeoPoint(-33.86, -70.5)), '-33.86000, -70.50000');
    });
  });
  group('offline map numbers (Phase 8b)', () {
    test('formatCount: thousands separators', () {
      expect(formatCount(0), '0');
      expect(formatCount(999), '999');
      expect(formatCount(1180), '1,180');
      expect(formatCount(1234567), '1,234,567');
      expect(formatCount(-2500), '-2,500');
    });

    test('formatMegabytes: one decimal below 10 MB, whole above', () {
      expect(formatMegabytes(0), '0.0 MB');
      expect(formatMegabytes(20000), '0.1 MB', reason: 'never "0.0" for data');
      expect(formatMegabytes(3700000), '3.7 MB');
      expect(formatMegabytes(12300000), '12 MB');
      expect(formatMegabytes(50000000), '50 MB');
    });

    test('formatKm', () {
      expect(formatKm(9.46), '9.5 km');
      expect(formatKm(39.2), '39 km');
    });
  });
}
