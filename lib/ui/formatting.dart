import '../models/geo_point.dart';

/// Formats a location as `60.16990, 24.93840` (latitude, longitude; five
/// decimals, about 1 m). Shown for a pinned quest until it has an address
/// (address lookup arrives in Phase 7).
String formatCoordinates(GeoPoint p) =>
    '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';

/// Formats the calendar day of [date] as `dd-mm-yyyy`, e.g. `20-11-2026`.
///
/// A fixed format (the user's choice), used everywhere a date is shown, so
/// it can't differ between screens. Only the date parts are used, so pass a
/// local time (`toLocal()`) to get the day the user sees on their calendar.
String formatDate(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}-${two(date.month)}-${date.year.toString().padLeft(4, '0')}';
}

/// Formats a whole number with thousands separators, e.g. `1,180`.
String formatCount(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Formats a size in bytes as megabytes (1 MB = 1,000,000 bytes, as in
/// OpenFreeMap's "50 MB" limit): `0.4 MB`, `3.7 MB`, `12 MB`, `50 MB`.
String formatMegabytes(int bytes) {
  final mb = bytes / 1000000;
  if (bytes > 0 && mb < 0.1) return '0.1 MB';
  return mb >= 10 ? '${mb.round()} MB' : '${mb.toStringAsFixed(1)} MB';
}

/// Formats a distance in km: `9.5 km` below 10 km, else `40 km`.
String formatKm(double km) =>
    km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
