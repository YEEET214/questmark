import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/last_location_repository.dart';
import '../models/location_fix.dart';
import '../services/location_service.dart';

/// What the app can currently do with the phone's location.
enum LocationStatus {
  /// Not checked yet (until [LocationController.start] has run).
  unknown,

  /// The phone's location setting is switched off.
  serviceOff,

  /// The app isn't allowed (yet). It can ask.
  denied,

  /// Blocked. Only the system settings can change it.
  deniedForever,

  /// Allowed and switched on. Fixes are coming in (or will be shortly).
  on,
}

/// The phone's position, as app-wide state (PLAN.md D8, D19).
///
/// * [start] loads the saved last-known position and checks permission. It
///   **never asks** for permission by itself: asking happens only when the
///   user taps something ([requestAccess]), after the app has explained why.
/// * While [status] is [LocationStatus.on], it listens to the GPS and
///   publishes [current]. Every fix also updates [lastKnown], which is
///   saved to SQLite at most once per [saveInterval] (and when the app goes
///   to the background), so a fallback exists on the next start.
/// * Foreground only: [pause] stops listening when the app is hidden, and
///   [refresh] re-checks everything when it comes back (the user may have
///   changed the settings in the meantime).
class LocationController extends ChangeNotifier {
  LocationController(
    this._service,
    this._lastLocations, {
    DateTime Function()? clock,
    this.saveInterval = const Duration(minutes: 1),
    this.retryDelay = const Duration(seconds: 5),
  }) : _clock = clock ?? DateTime.now;

  final LocationService _service;
  final LastLocationRepository _lastLocations;
  final DateTime Function() _clock;

  /// Minimum time between two saves of the last-known position.
  final Duration saveInterval;

  /// How long to wait before listening again after the GPS stream failed
  /// although permission and the location setting look fine.
  final Duration retryDelay;

  LocationStatus _status = LocationStatus.unknown;
  LocationFix? _current;
  LocationFix? _lastKnown;
  bool _hasStarted = false;

  StreamSubscription<LocationFix>? _fixes;
  StreamSubscription<bool>? _serviceChanges;
  Timer? _retry;
  DateTime? _lastSavedAt;
  bool _unsaved = false;
  bool _paused = false;
  bool _disposed = false;

  /// Serialises [refresh] calls, so overlapping checks can't race.
  Future<void> _refreshing = Future.value();

  LocationStatus get status => _status;

  /// The latest fix from this session, while [status] is on. Cleared when
  /// location becomes unavailable, so the map never shows a stale dot as
  /// if it were live.
  LocationFix? get current => _current;

  /// The newest position known at all: this session's latest fix, or the
  /// one saved by an earlier session.
  LocationFix? get lastKnown => _lastKnown;

  /// True once [start] has loaded the saved position and checked the
  /// permission, so the map can choose its starting view.
  bool get hasStarted => _hasStarted;

  /// Loads the saved position, checks permission and the location setting,
  /// and starts listening if both allow it. Never throws: on failure the
  /// status simply stays unavailable.
  Future<void> start() async {
    try {
      _lastKnown = await _lastLocations.load();
    } catch (e, s) {
      _report(e, s, 'loading the last location');
    }
    try {
      _serviceChanges ??= _service.serviceEnabledChanges().listen(
        (_) => refresh(),
        onError: (Object e, StackTrace s) =>
            _report(e, s, 'watching the location setting'),
      );
    } catch (e, s) {
      _report(e, s, 'watching the location setting');
    }
    await refresh();
    _hasStarted = true;
    _notify();
  }

  /// Re-checks permission and the location setting, and starts or stops
  /// listening to match (unless [pause]d). Safe to call any number of
  /// times.
  Future<void> refresh() => _refreshing = _refreshing.then((_) => _refresh());

  Future<void> _refresh() async {
    if (_disposed) return;
    final status = await _check();
    if (_disposed) return;
    _apply(status);
  }

  /// Asks for permission (showing the OS dialog) if the app may still ask.
  /// Returns the resulting status. For [LocationStatus.serviceOff] and
  /// [LocationStatus.deniedForever] nothing can be asked: the UI offers
  /// [openSettings] instead.
  Future<LocationStatus> requestAccess() async {
    if (_status == LocationStatus.denied || _status == LocationStatus.unknown) {
      try {
        await _service.requestPermission();
      } catch (e, s) {
        _report(e, s, 'asking for location permission');
      }
    }
    await refresh();
    return _status;
  }

  /// Opens the system settings page that can fix the current status.
  Future<void> openSettings() async {
    try {
      if (_status == LocationStatus.serviceOff) {
        await _service.openLocationSettings();
      } else {
        await _service.openAppSettings();
      }
    } catch (e, s) {
      _report(e, s, 'opening the settings');
    }
  }

  /// The app is visible again: re-check (the settings may have changed
  /// meanwhile) and listen again if allowed.
  Future<void> resume() {
    _paused = false;
    return refresh();
  }

  /// The app went to the background: stop the GPS and save the latest
  /// position if it hasn't been saved yet. [resume] undoes this.
  Future<void> pause() async {
    _paused = true;
    _stopListening();
    await _saveIfUnsaved();
  }

  Future<LocationStatus> _check() async {
    try {
      if (!await _service.isServiceEnabled()) return LocationStatus.serviceOff;
      return switch (await _service.checkPermission()) {
        LocationPermissionState.granted => LocationStatus.on,
        LocationPermissionState.denied => LocationStatus.denied,
        LocationPermissionState.deniedForever => LocationStatus.deniedForever,
      };
    } catch (e, s) {
      _report(e, s, 'checking location access');
      return LocationStatus.serviceOff;
    }
  }

  void _apply(LocationStatus status) {
    final changed = status != _status;
    _status = status;
    if (status == LocationStatus.on) {
      if (!_paused) _startListening();
    } else {
      _stopListening();
      if (_current != null) {
        _current = null;
        _notify();
        return;
      }
    }
    if (changed) _notify();
  }

  void _startListening() {
    // Already listening, or waiting out [retryDelay] after a failure.
    if (_fixes != null || _retry != null) return;
    try {
      _fixes = _service.fixes().listen(_onFix, onError: _onFixError);
    } catch (e, s) {
      _onFixError(e, s);
    }
  }

  void _stopListening() {
    _retry?.cancel();
    _retry = null;
    _fixes?.cancel();
    _fixes = null;
  }

  void _onFix(LocationFix fix) {
    _current = fix;
    _lastKnown = fix;
    _unsaved = true;
    final last = _lastSavedAt;
    if (last == null || !_clock().isBefore(last.add(saveInterval))) {
      _save(fix);
    }
    _notify();
  }

  /// The stream fails when location is switched off or permission is
  /// withdrawn. Re-check: that updates the status, and if everything still
  /// looks fine, try listening again after [retryDelay].
  void _onFixError(Object error, [StackTrace? stack]) {
    _report(error, stack, 'reading the GPS');
    _fixes?.cancel();
    _fixes = null;
    // Wait before listening again, so a stream that keeps failing can't
    // spin. A refresh that finds location unavailable cancels the wait.
    _retry?.cancel();
    _retry = Timer(retryDelay, () {
      _retry = null;
      if (!_disposed && !_paused && _status == LocationStatus.on) {
        _startListening();
      }
    });
    refresh();
  }

  Future<void> _save(LocationFix fix) async {
    _lastSavedAt = _clock();
    _unsaved = false;
    try {
      await _lastLocations.save(fix);
    } catch (e, s) {
      _report(e, s, 'saving the last location');
    }
  }

  Future<void> _saveIfUnsaved() async {
    final fix = _lastKnown;
    if (_unsaved && fix != null) await _save(fix);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Location problems are expected (GPS off, permission denied) and the
  /// UI shows them through [status]; details go to the debug log.
  void _report(Object error, StackTrace? stack, String what) {
    debugPrint('LocationController: error while $what: $error');
  }

  @override
  void dispose() {
    _disposed = true;
    _stopListening();
    _serviceChanges?.cancel();
    super.dispose();
  }
}
