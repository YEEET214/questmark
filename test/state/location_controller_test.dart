import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/services/location_service.dart';
import 'package:questmark/state/location_controller.dart';

import '../helpers/fake_location_service.dart';

void main() {
  late FakeLocationService gps;
  late FakeLastLocationRepository saved;
  late DateTime now;
  late LocationController c;

  LocationController make({
    Duration saveInterval = const Duration(minutes: 1),
  }) {
    final controller = LocationController(
      gps,
      saved,
      clock: () => now,
      saveInterval: saveInterval,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  setUp(() {
    gps = FakeLocationService();
    saved = FakeLastLocationRepository();
    now = DateTime(2026, 11, 22, 12);
  });

  group('start', () {
    test(
      'with permission and location on: listens and publishes fixes',
      () async {
        c = make();
        expect(c.status, LocationStatus.unknown);
        expect(c.hasStarted, isFalse);

        await c.start();
        expect(c.hasStarted, isTrue);
        expect(c.status, LocationStatus.on);
        expect(gps.isListening, isTrue);
        expect(c.current, isNull, reason: 'no fix yet');

        final f = fixAt(60.17, 24.94);
        gps.emit(f);
        await pumpEventQueue();
        expect(c.current, f);
        expect(c.lastKnown, f);
      },
    );

    test('loads the saved last-known position', () async {
      saved.saved = fixAt(51.5, -0.12);
      c = make();
      await c.start();
      expect(c.lastKnown, fixAt(51.5, -0.12));
      expect(c.current, isNull, reason: 'a saved fix is not a live one');
    });

    test('never asks for permission by itself', () async {
      gps.permission = LocationPermissionState.denied;
      c = make();
      await c.start();
      expect(c.status, LocationStatus.denied);
      expect(gps.requestCount, 0);
      expect(gps.isListening, isFalse);
    });

    test('reports deniedForever and serviceOff', () async {
      gps.permission = LocationPermissionState.deniedForever;
      c = make();
      await c.start();
      expect(c.status, LocationStatus.deniedForever);

      gps
        ..permission = LocationPermissionState.granted
        ..serviceEnabled = false;
      await c.refresh();
      expect(c.status, LocationStatus.serviceOff);
      expect(gps.isListening, isFalse);
    });

    test('a failing saved-location load still finishes starting', () async {
      c = LocationController(gps, _ThrowingRepo(), clock: () => now);
      addTearDown(c.dispose);
      await c.start();
      expect(c.hasStarted, isTrue);
      expect(c.lastKnown, isNull);
      expect(c.status, LocationStatus.on);
    });
  });

  group('requestAccess', () {
    test('asks once; granting starts listening', () async {
      gps.permission = LocationPermissionState.denied;
      c = make();
      await c.start();

      expect(await c.requestAccess(), LocationStatus.on);
      expect(gps.requestCount, 1);
      expect(gps.isListening, isTrue);
    });

    test('refusing keeps it denied', () async {
      gps
        ..permission = LocationPermissionState.denied
        ..permissionAfterRequest = LocationPermissionState.denied;
      c = make();
      await c.start();
      expect(await c.requestAccess(), LocationStatus.denied);
      expect(gps.isListening, isFalse);
    });

    test('does not ask when blocked or when location is off', () async {
      gps.permission = LocationPermissionState.deniedForever;
      c = make();
      await c.start();
      await c.requestAccess();
      gps.serviceEnabled = false;
      await c.refresh();
      await c.requestAccess();
      expect(gps.requestCount, 0);
    });
  });

  group('openSettings', () {
    test('opens location settings when location is off, app settings '
        'otherwise', () async {
      gps.serviceEnabled = false;
      c = make();
      await c.start();
      await c.openSettings();
      expect(gps.openedLocationSettings, 1);

      gps
        ..serviceEnabled = true
        ..permission = LocationPermissionState.deniedForever;
      await c.refresh();
      await c.openSettings();
      expect(gps.openedAppSettings, 1);
    });
  });

  group('location switched on or off while running', () {
    test('switching off stops the GPS and clears the live fix; switching '
        'on resumes', () async {
      c = make();
      await c.start();
      gps.emit(fixAt(60.17, 24.94));
      await pumpEventQueue();

      gps.setServiceEnabled(false);
      await pumpEventQueue();
      expect(c.status, LocationStatus.serviceOff);
      expect(c.current, isNull);
      expect(c.lastKnown, isNotNull, reason: 'the fallback stays');
      expect(gps.isListening, isFalse);

      gps.setServiceEnabled(true);
      await pumpEventQueue();
      expect(c.status, LocationStatus.on);
      expect(gps.isListening, isTrue);
    });

    test('a stream error re-checks the status', () async {
      c = make();
      await c.start();
      gps.permission = LocationPermissionState.denied; // withdrawn
      gps.fail();
      await pumpEventQueue();
      expect(c.status, LocationStatus.denied);
      expect(gps.isListening, isFalse);
    });

    test('a stream error with everything fine retries after a delay, '
        'not in a tight loop', () {
      fakeAsync((async) {
        c = LocationController(
          gps,
          saved,
          clock: () => now,
          retryDelay: const Duration(seconds: 5),
        );
        c.start();
        async.flushMicrotasks();
        expect(gps.fixesSubscriptions, 1);

        gps.fail();
        async.flushMicrotasks();
        expect(gps.fixesSubscriptions, 1, reason: 'waits before retrying');
        expect(c.status, LocationStatus.on);

        async.elapse(const Duration(seconds: 5));
        expect(gps.fixesSubscriptions, 2);
        expect(gps.isListening, isTrue);
        c.dispose();
      });
    });
  });

  group('saving the last-known position', () {
    test('the first fix is saved, then at most once per interval', () async {
      c = make();
      await c.start();

      gps.emit(fixAt(60.0, 24.0));
      await pumpEventQueue();
      expect(saved.saves, 1);

      now = now.add(const Duration(seconds: 30));
      gps.emit(fixAt(60.1, 24.0));
      await pumpEventQueue();
      expect(saved.saves, 1, reason: 'too soon');
      expect(c.lastKnown, fixAt(60.1, 24.0), reason: 'in memory it is fresh');

      now = now.add(const Duration(seconds: 30));
      gps.emit(fixAt(60.2, 24.0));
      await pumpEventQueue();
      expect(saved.saves, 2);
      expect(saved.saved, fixAt(60.2, 24.0));
    });

    test(
      'going to the background stops the GPS and saves an unsaved fix',
      () async {
        c = make();
        await c.start();
        gps.emit(fixAt(60.0, 24.0));
        await pumpEventQueue();
        now = now.add(const Duration(seconds: 10));
        gps.emit(fixAt(60.5, 24.0));
        await pumpEventQueue();
        expect(saved.saves, 1);

        await c.pause();
        expect(gps.isListening, isFalse);
        expect(saved.saves, 2);
        expect(saved.saved, fixAt(60.5, 24.0));

        await c.pause(); // nothing new to save
        expect(saved.saves, 2);
      },
    );

    test('while paused, a location-setting change does not restart the GPS; '
        'resume does', () async {
      c = make();
      await c.start();
      await c.pause();

      gps.setServiceEnabled(true);
      await pumpEventQueue();
      expect(gps.isListening, isFalse);

      await c.resume();
      expect(gps.isListening, isTrue);
    });
  });

  test('notifies listeners on status changes and fixes', () async {
    c = make();
    var notified = 0;
    c.addListener(() => notified++);
    await c.start();
    expect(notified, greaterThan(0));

    final before = notified;
    gps.emit(fixAt(1, 1));
    await pumpEventQueue();
    expect(notified, before + 1);
  });
}

class _ThrowingRepo extends FakeLastLocationRepository {
  @override
  Future<Never> load() async => throw StateError('db broken');
}
