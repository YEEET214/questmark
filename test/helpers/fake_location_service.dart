import 'dart:async';

import 'package:questmark/data/last_location_repository.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/location_fix.dart';
import 'package:questmark/services/location_service.dart';

/// A [LocationService] whose GPS is driven by the test: [emit] sends a
/// fix, [fail] sends a stream error, and [serviceEnabled] / [permission]
/// are plain fields.
class FakeLocationService implements LocationService {
  FakeLocationService({
    this.serviceEnabled = true,
    this.permission = LocationPermissionState.granted,
    this.permissionAfterRequest = LocationPermissionState.granted,
  });

  bool serviceEnabled;
  LocationPermissionState permission;

  /// What the "user" answers in the OS dialog.
  LocationPermissionState permissionAfterRequest;

  int requestCount = 0;
  int fixesSubscriptions = 0;
  int openedAppSettings = 0;
  int openedLocationSettings = 0;

  StreamController<LocationFix>? _fixes;
  final _serviceChanges = StreamController<bool>.broadcast();

  /// Whether something is currently listening to the GPS.
  bool get isListening => _fixes?.hasListener ?? false;

  void emit(LocationFix fix) {
    final c = _fixes;
    if (c == null || !c.hasListener) {
      throw StateError('nobody is listening to the GPS');
    }
    c.add(fix);
  }

  void fail([Object error = 'gps failed']) => _fixes?.addError(error);

  /// Flips the location setting and tells listeners, like the OS does.
  void setServiceEnabled(bool on) {
    serviceEnabled = on;
    _serviceChanges.add(on);
  }

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermissionState> checkPermission() async => permission;

  @override
  Future<LocationPermissionState> requestPermission() async {
    requestCount++;
    if (permission == LocationPermissionState.denied) {
      permission = permissionAfterRequest;
    }
    return permission;
  }

  @override
  Stream<LocationFix> fixes() {
    fixesSubscriptions++;
    final c = StreamController<LocationFix>();
    _fixes = c;
    return c.stream;
  }

  @override
  Stream<bool> serviceEnabledChanges() => _serviceChanges.stream;

  @override
  Future<bool> openAppSettings() async {
    openedAppSettings++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    openedLocationSettings++;
    return true;
  }
}

class FakeLastLocationRepository implements LastLocationRepository {
  FakeLastLocationRepository([this.saved]);

  LocationFix? saved;
  int saves = 0;

  @override
  Future<LocationFix?> load() async => saved;

  @override
  Future<void> save(LocationFix fix) async {
    saves++;
    saved = fix;
  }
}

/// A fix at [lat], [lng] with 10 m accuracy.
LocationFix fixAt(
  double lat,
  double lng, {
  DateTime? at,
  double accuracy = 10,
}) => LocationFix(
  point: GeoPoint(lat, lng),
  accuracyMeters: accuracy,
  at: at ?? DateTime.utc(2026, 11, 22, 12),
);
