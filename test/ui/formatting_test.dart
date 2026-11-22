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
}
