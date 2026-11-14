/// Formats the calendar day of [date] as `dd-mm-yyyy`, e.g. `20-11-2026`.
///
/// A fixed format (the user's choice), used everywhere a date is shown, so
/// it can't differ between screens. Only the date parts are used, so pass a
/// local time (`toLocal()`) to get the day the user sees on their calendar.
String formatDate(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}-${two(date.month)}-${date.year.toString().padLeft(4, '0')}';
}
