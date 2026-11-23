/// How QuestMark identifies itself to the servers it uses (OpenFreeMap
/// tiles, Nominatim address search). Both services require a unique,
/// stable User-Agent, and it names only the app and its version: no
/// device or user details.
abstract final class AppInfo {
  /// Keep in sync with pubspec.yaml (a test checks this).
  static const version = '1.0.0';

  static const userAgent = 'QuestMark/$version';
}
