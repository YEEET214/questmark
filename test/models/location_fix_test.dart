import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/location_fix.dart';

void main() {
  final at = DateTime.utc(2026, 11, 22);

  test('equal when point, accuracy and time are equal', () {
    LocationFix make() =>
        LocationFix(point: GeoPoint(1, 2), accuracyMeters: 5, at: at);
    expect(make(), make());
    expect(make().hashCode, make().hashCode);
    expect(
      make(),
      isNot(LocationFix(point: GeoPoint(1, 2), accuracyMeters: 6, at: at)),
    );
  });

  test('rejects a negative or non-finite accuracy', () {
    for (final bad in [-1.0, double.nan, double.infinity]) {
      expect(
        () => LocationFix(point: GeoPoint(0, 0), accuracyMeters: bad, at: at),
        throwsArgumentError,
        reason: '$bad',
      );
    }
  });
}
