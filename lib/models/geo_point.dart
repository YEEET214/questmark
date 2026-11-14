/// A WGS84 coordinate (the system GPS and OpenStreetMap use).
///
/// This is our own small type rather than `LatLng` from the map package.
/// Keeping the models free of map-library types means the data layer and its
/// tests don't depend on `flutter_map`, and swapping the map library later
/// would only touch the UI. The conversion to `LatLng` lives in the map UI.
class GeoPoint {
  /// Creates a point, throwing [RangeError] if a coordinate is out of range
  /// or not a finite number.
  GeoPoint(this.latitude, this.longitude) {
    if (!latitude.isFinite || latitude < -90 || latitude > 90) {
      throw RangeError.range(latitude, -90, 90, 'latitude');
    }
    if (!longitude.isFinite || longitude < -180 || longitude > 180) {
      throw RangeError.range(longitude, -180, 180, 'longitude');
    }
  }

  /// Degrees north (positive) or south (negative), -90..90.
  final double latitude;

  /// Degrees east (positive) or west (negative), -180..180.
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';
}
