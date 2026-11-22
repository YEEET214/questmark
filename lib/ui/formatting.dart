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
