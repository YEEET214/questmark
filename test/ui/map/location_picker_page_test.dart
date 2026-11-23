import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/geocode_result.dart';
import 'package:questmark/services/geocoding_service.dart';
import 'package:questmark/services/location_service.dart';
import 'package:questmark/state/location_controller.dart';
import 'package:questmark/ui/map/base_map_layer.dart';
import 'package:questmark/ui/map/location_picker_page.dart';
import 'package:questmark/ui/map/map_config.dart';

import '../../helpers/fake_geocoding_service.dart';
import '../../helpers/fake_location_service.dart';

void main() {
  late MapController map;
  late FakeLocationService gps;
  late LocationController location;
  late FakeGeocodingService geo;

  /// Pumps a launcher that opens the picker (via [pickLocationOnMap], the
  /// same way the editor does) and returns a getter for its result.
  /// Animations are off, so camera moves are instant.
  Future<PickedLocation? Function()> openPicker(
    WidgetTester tester, {
    GeoPoint? initial,
    FakeGeocodingService? geocoder,
    FakeLocationService? gpsService,
    FakeLastLocationRepository? saved,
  }) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    map = MapController();
    gps = gpsService ?? FakeLocationService();
    location =
        LocationController(gps, saved ?? FakeLastLocationRepository());
    await location.start();
    addTearDown(location.dispose);

    geo = geocoder ?? FakeGeocodingService();
    PickedLocation? result;
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider.value(value: const MapBaseLayer(SizedBox.shrink())),
        ChangeNotifierProvider.value(value: location),
        Provider<GeocodingService>.value(value: geo),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<PickedLocation>(
                MaterialPageRoute(
                  builder: (_) =>
                      LocationPickerPage(initial: initial, mapController: map),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  void expectCameraAt(double lat, double lng) {
    expect(map.camera.center.latitude, closeTo(lat, 0.0001));
    expect(map.camera.center.longitude, closeTo(lng, 0.0001));
  }

  Future<void> useThisLocation(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('useLocationButton')));
    await tester.pumpAndSettle();
  }

  group('starting view', () {
    testWidgets("the quest's current location, at quest zoom",
        (tester) async {
      await openPicker(tester,
          initial: GeoPoint(60.17, 24.94),
          saved: FakeLastLocationRepository(fixAt(51.5, -0.12)));
      expectCameraAt(60.17, 24.94);
      expect(map.camera.zoom, MapConfig.questZoom);
    });

    testWidgets('else the last known position', (tester) async {
      await openPicker(tester,
          saved: FakeLastLocationRepository(fixAt(51.5, -0.12)));
      expectCameraAt(51.5, -0.12);
      expect(map.camera.zoom, MapConfig.playerZoom);
    });

    testWidgets('else the whole world', (tester) async {
      await openPicker(tester);
      expectCameraAt(MapConfig.worldCenter.latitude,
          MapConfig.worldCenter.longitude);
    });
  });

  testWidgets('"Use this location" returns the point under the pin, rounded',
      (tester) async {
    final result = await openPicker(tester, initial: GeoPoint(60.17, 24.94));
    map.move(const LatLng(60.1712345678, 24.9512345678), 16);
    await tester.pumpAndSettle();

    await useThisLocation(tester);
    expect(find.byType(LocationPickerPage), findsNothing);
    expect(result(), PickedLocation(GeoPoint(60.171235, 24.951235)));
  });

  testWidgets('the back button cancels: no point is returned',
      (tester) async {
    final result = await openPicker(tester, initial: GeoPoint(60.17, 24.94));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(LocationPickerPage), findsNothing);
    expect(result(), isNull);
  });

  testWidgets('the coordinates shown follow the map', (tester) async {
    await openPicker(tester, initial: GeoPoint(60.17, 24.94));
    expect(find.text('60.17000, 24.94000'), findsOneWidget);

    map.move(const LatLng(61.5, 23.76), 15);
    await tester.pumpAndSettle();
    expect(find.text('61.50000, 23.76000'), findsOneWidget);
  });

  testWidgets('tapping a spot brings it under the pin', (tester) async {
    await openPicker(tester, initial: GeoPoint(60.17, 24.94));
    final mapRect = tester.getRect(find.byType(FlutterMap));
    final target = mapRect.center + const Offset(-100, 120);
    final expected = map.camera.screenOffsetToLatLng(
        target - mapRect.topLeft);

    await tester.tapAt(target);
    // flutter_map reports a single tap only after the double-tap window.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expectCameraAt(expected.latitude, expected.longitude);
  });

  testWidgets("the pin's tip is exactly at the map's centre", (tester) async {
    await openPicker(tester, initial: GeoPoint(60.17, 24.94));
    final pin = tester.getRect(find.byType(PickerPin));
    final mapRect = tester.getRect(find.byType(FlutterMap));
    expect(pin.center.dx, closeTo(mapRect.center.dx, 0.5));
    expect(pin.center.dy, closeTo(mapRect.center.dy, 0.5));
  });

  testWidgets('has my-location and zoom buttons, but no completed toggle',
      (tester) async {
    await openPicker(tester);
    expect(find.byKey(const Key('myLocationButton')), findsOneWidget);
    expect(find.byKey(const Key('zoomInButton')), findsOneWidget);
    expect(find.byKey(const Key('toggleCompletedButton')), findsNothing);
    expect(find.byKey(const Key('attributionButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('zoomInButton')));
    await tester.pumpAndSettle();
    expect(map.camera.zoom, closeTo(MapConfig.worldZoom + 1, 0.001));
  });

  group('my-location button', () {
    testWidgets('goes to the live position', (tester) async {
      await openPicker(tester, initial: GeoPoint(60.17, 24.94));
      gps.emit(fixAt(61.0, 25.0));
      await tester.pumpAndSettle();
      expectCameraAt(60.17, 24.94); // the picker doesn't follow by itself

      await tester.tap(find.byKey(const Key('myLocationButton')));
      await tester.pumpAndSettle();
      expectCameraAt(61.0, 25.0);
    });

    testWidgets('before the first fix: goes there when it arrives',
        (tester) async {
      await openPicker(tester, initial: GeoPoint(60.17, 24.94));
      await tester.tap(find.byKey(const Key('myLocationButton')));
      await tester.pumpAndSettle();
      expect(find.text('Finding your location…'), findsOneWidget);

      gps.emit(fixAt(61.0, 25.0));
      await tester.pumpAndSettle();
      expectCameraAt(61.0, 25.0);
    });

    testWidgets('asks for permission when not allowed yet', (tester) async {
      await openPicker(tester,
          gpsService:
              FakeLocationService(permission: LocationPermissionState.denied));
      await tester.tap(find.byKey(const Key('myLocationButton')));
      await tester.pumpAndSettle();
      expect(gps.requestCount, 1);
      expect(location.status, LocationStatus.on);
    });

    testWidgets('location off: explains and offers the settings',
        (tester) async {
      await openPicker(tester,
          gpsService: FakeLocationService(serviceEnabled: false));
      await tester.tap(find.byKey(const Key('myLocationButton')));
      await tester.pumpAndSettle();
      expect(find.text('Location is turned off'), findsOneWidget);
    });
  });

  testWidgets('shows the player dot when there is a fix', (tester) async {
    await openPicker(tester, initial: GeoPoint(61.0, 25.0));
    expect(find.byKey(const ValueKey('player-marker')), findsNothing);
    gps.emit(fixAt(61.0, 25.0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('player-marker')), findsOneWidget);
  });
  group('address search (Phase 7, D6)', () {
    final oodi = GeocodeResult(
      label: 'Oodi, Töölönlahdenkatu 4, Helsinki',
      fullName: 'Oodi, 4, Töölönlahdenkatu, Kluuvi, Helsinki, Suomi',
      point: GeoPoint(60.17378, 24.93795),
    );
    final oodiTampere = GeocodeResult(
      label: 'Oodi Café, Tampere',
      fullName: 'Oodi Café, Hämeenkatu, Tampere, Suomi',
      point: GeoPoint(61.4978, 23.7610),
    );

    FakeGeocodingService geocoder() =>
        FakeGeocodingService(searches: {'oodi': [oodi, oodiTampere]});

    Future<void> search(WidgetTester tester, String query) async {
      await tester.enterText(
          find.byKey(const Key('addressSearchField')), query);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
    }

    testWidgets('a note under the search field says what is sent to '
        'Nominatim (PR #11 review)', (tester) async {
      await openPicker(tester, geocoder: geocoder());
      final note = find.byKey(const Key('nominatimNote'));
      expect(note, findsOneWidget);
      expect(find.textContaining('Nominatim'), findsOneWidget);
      expect(find.textContaining('Your own location is never sent.'),
          findsOneWidget);
      expect(tester.getRect(note).top,
          greaterThanOrEqualTo(tester
              .getRect(find.byKey(const Key('addressSearchField')))
              .bottom),
          reason: 'under the search field');
    });

    testWidgets('typing alone never searches (no autocomplete)',
        (tester) async {
      await openPicker(tester, geocoder: geocoder());
      await tester.enterText(
          find.byKey(const Key('addressSearchField')), 'oodi');
      await tester.pumpAndSettle();
      expect(geo.searchCalls, isEmpty);
    });

    testWidgets('pressing Search shows the results', (tester) async {
      await openPicker(tester, geocoder: geocoder());
      await search(tester, 'oodi');
      expect(geo.searchCalls, ['oodi']);
      expect(find.text(oodi.label), findsOneWidget);
      expect(find.text(oodi.fullName), findsOneWidget);
      expect(find.text(oodiTampere.label), findsOneWidget);
    });

    testWidgets('the search button works too; a blank query does nothing',
        (tester) async {
      await openPicker(tester, geocoder: geocoder());
      await tester.tap(find.byKey(const Key('addressSearchButton')));
      await tester.pumpAndSettle();
      expect(geo.searchCalls, isEmpty);

      await tester.enterText(
          find.byKey(const Key('addressSearchField')), '  oodi ');
      await tester.tap(find.byKey(const Key('addressSearchButton')));
      await tester.pumpAndSettle();
      expect(geo.searchCalls, ['oodi'], reason: 'trimmed');
    });

    testWidgets('choosing a result moves the pin there and returns its '
        'address', (tester) async {
      final result = await openPicker(tester, geocoder: geocoder());
      await search(tester, 'oodi');
      await tester.tap(find.byKey(const Key('addressResult-0')));
      await tester.pumpAndSettle();

      expectCameraAt(oodi.point.latitude, oodi.point.longitude);
      expect(map.camera.zoom, MapConfig.questZoom);
      expect(find.byKey(const Key('addressResult-1')), findsNothing,
          reason: 'the list closes');
      expect(find.byKey(const Key('pickerAddress')), findsOneWidget);

      await useThisLocation(tester);
      expect(result(), PickedLocation(oodi.point, address: oodi.label));
    });

    testWidgets('moving the pin away from the result drops its address',
        (tester) async {
      final result = await openPicker(tester, geocoder: geocoder());
      await search(tester, 'oodi');
      await tester.tap(find.byKey(const Key('addressResult-0')));
      await tester.pumpAndSettle();

      // About 50 m north: a different place.
      map.move(LatLng(oodi.point.latitude + 0.00045, oodi.point.longitude),
          map.camera.zoom);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pickerAddress')), findsNothing);

      await useThisLocation(tester);
      expect(result()!.address, isNull);
    });

    testWidgets('no results: says so', (tester) async {
      await openPicker(tester, geocoder: geocoder());
      await search(tester, 'nowhere at all');
      expect(find.textContaining('No places found for "nowhere at all"'),
          findsOneWidget);
    });

    testWidgets('a failed search explains why, and can be retried',
        (tester) async {
      final g = geocoder()
        ..failNext = const GeocodingException(GeocodingFailure.offline);
      await openPicker(tester, geocoder: g);
      await search(tester, 'oodi');
      expect(find.byKey(const Key('addressSearchError')), findsOneWidget);
      expect(find.textContaining('No connection'), findsOneWidget);

      await search(tester, 'oodi');
      expect(find.byKey(const Key('addressSearchError')), findsNothing);
      expect(find.text(oodi.label), findsOneWidget);
    });

    testWidgets('tapping the map closes the results list', (tester) async {
      await openPicker(tester, geocoder: geocoder());
      await search(tester, 'oodi');
      final mapRect = tester.getRect(find.byType(FlutterMap));
      await tester.tapAt(mapRect.bottomLeft + const Offset(60, -120));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text(oodi.label), findsNothing);
    });
  });
}
