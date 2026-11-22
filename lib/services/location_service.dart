import 'package:geolocator/geolocator.dart';

import '../models/geo_point.dart';
import '../models/location_fix.dart';

/// Whether the app may read the phone's location.
enum LocationPermissionState {
  /// Allowed while the app is in use.
  granted,

  /// Not allowed (yet). The app may ask, and the OS shows its dialog.
  denied,

  /// Blocked ("don't ask again"). The OS no longer shows its dialog, so
  /// only the system settings can change this.
  deniedForever,
}

/// Access to the phone's GPS (PLAN.md D8).
///
/// This is an interface so the state layer and widget tests can use a fake
/// that emits made-up positions. [GeolocatorLocationService] is the real
/// one. Foreground only: there's no background tracking.
abstract interface class LocationService {
  /// Whether the phone's location setting is switched on.
  Future<bool> isServiceEnabled();

  Future<LocationPermissionState> checkPermission();

  /// Shows the OS permission dialog (if the OS still allows asking) and
  /// returns the result.
  Future<LocationPermissionState> requestPermission();

  /// Position updates while subscribed. Only sends an update when the
  /// phone has moved a few metres, to save battery. Emits an error if the
  /// location service is switched off or permission is withdrawn.
  Stream<LocationFix> fixes();

  /// Emits `true` / `false` when the phone's location setting is switched
  /// on / off.
  Stream<bool> serviceEnabledChanges();

  /// Opens this app's page in the system settings (to undo
  /// [LocationPermissionState.deniedForever]).
  Future<bool> openAppSettings();

  /// Opens the system's location settings (to switch location on).
  Future<bool> openLocationSettings();
}

/// [LocationService] backed by the `geolocator` plugin.
class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  /// Updates only after moving this far (PLAN.md D8). Saves battery and
  /// avoids redrawing the map for GPS jitter.
  static const distanceFilterMeters = 5;

  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermissionState> checkPermission() async =>
      _map(await Geolocator.checkPermission());

  @override
  Future<LocationPermissionState> requestPermission() async =>
      _map(await Geolocator.requestPermission());

  @override
  Stream<LocationFix> fixes() =>
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilterMeters,
        ),
      ).map(
        (p) => LocationFix(
          point: GeoPoint(p.latitude, p.longitude),
          accuracyMeters: p.accuracy.isFinite && p.accuracy >= 0
              ? p.accuracy
              : 0,
          at: p.timestamp,
        ),
      );

  @override
  Stream<bool> serviceEnabledChanges() => Geolocator.getServiceStatusStream()
      .map((s) => s == ServiceStatus.enabled);

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  static LocationPermissionState _map(LocationPermission p) => switch (p) {
    LocationPermission.always ||
    LocationPermission.whileInUse => LocationPermissionState.granted,
    LocationPermission.deniedForever => LocationPermissionState.deniedForever,
    // unableToDetermine only happens on the web.
    LocationPermission.denied ||
    LocationPermission.unableToDetermine => LocationPermissionState.denied,
  };
}
