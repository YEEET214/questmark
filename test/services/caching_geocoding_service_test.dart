import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/data/geocode_cache_repository.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/geocode_result.dart';
import 'package:questmark/services/caching_geocoding_service.dart';
import 'package:questmark/services/geocoding_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/fake_geocoding_service.dart';
import '../helpers/test_database.dart';

void main() {
  late Database db;
  late FakeGeocodingService network;
  late DateTime now;
  late CachingGeocodingService service;

  final oodi = GeocodeResult(
    label: 'Oodi, Töölönlahdenkatu 4, Helsinki',
    fullName: 'Oodi, 4, Töölönlahdenkatu, Helsinki, Suomi',
    point: GeoPoint(60.1737844, 24.9379464),
  );
  final here = GeoPoint(60.17378, 24.93795);

  setUp(() async {
    db = await openTestDatabase();
    network = FakeGeocodingService(
      searches: {'Oodi Helsinki': [oodi], 'nowhere': []},
      addresses: {here: 'Oodi, Töölönlahdenkatu 4, Helsinki'},
    );
    now = DateTime(2026, 11, 23);
    service = CachingGeocodingService(network, SqfliteGeocodeCache(db),
        clock: () => now);
  });
  tearDown(() async => db.close());

  group('search', () {
    test('the same question is sent to the server only once', () async {
      expect(await service.search('Oodi Helsinki'), [oodi]);
      expect(await service.search('Oodi Helsinki'), [oodi]);
      expect(network.searchCalls, ['Oodi Helsinki']);
    });

    test('case and extra spaces do not make a new question', () async {
      await service.search('Oodi Helsinki');
      expect(await service.search('  oodi   HELSINKI '), [oodi]);
      expect(network.searchCalls, hasLength(1));
    });

    test('"no results" is cached too', () async {
      await service.search('nowhere');
      expect(await service.search('nowhere'), isEmpty);
      expect(network.searchCalls, hasLength(1));
    });

    test('a blank query never reaches the server', () async {
      expect(await service.search('   '), isEmpty);
      expect(network.searchCalls, isEmpty);
    });

    test('errors are not cached: the next try asks again', () async {
      network.failNext =
          const GeocodingException(GeocodingFailure.offline);
      await expectLater(service.search('Oodi Helsinki'),
          throwsA(isA<GeocodingException>()));
      expect(await service.search('Oodi Helsinki'), [oodi]);
      expect(network.searchCalls, hasLength(2));
    });

    test('after 30 days the answer is fetched again', () async {
      await service.search('Oodi Helsinki');
      now = now.add(const Duration(days: 31));
      await service.search('Oodi Helsinki');
      expect(network.searchCalls, hasLength(2));
    });

    test('survives an app restart (it is in SQLite)', () async {
      await service.search('Oodi Helsinki');
      final restarted =
          CachingGeocodingService(network, SqfliteGeocodeCache(db));
      expect(await restarted.search('oodi helsinki'), [oodi]);
      expect(network.searchCalls, hasLength(1));
    });
  });

  group('reverse', () {
    test('cached by point (to about 1 m)', () async {
      expect(await service.reverse(here), 'Oodi, Töölönlahdenkatu 4, Helsinki');
      // A few centimetres away: same key.
      expect(await service.reverse(GeoPoint(60.173781, 24.937951)),
          'Oodi, Töölönlahdenkatu 4, Helsinki');
      expect(network.reverseCalls, hasLength(1));
    });

    test('"no address" is cached too', () async {
      expect(await service.reverse(GeoPoint(0, 0)), isNull);
      expect(await service.reverse(GeoPoint(0, 0)), isNull);
      expect(network.reverseCalls, hasLength(1));
    });
  });

  test('a broken cache does not break geocoding', () async {
    final broken =
        CachingGeocodingService(network, _BrokenCache(), clock: () => now);
    expect(await broken.search('Oodi Helsinki'), [oodi]);
    expect(await broken.reverse(here), isNotNull);
  });

  test('cache keys', () {
    expect(CachingGeocodingService.searchKey('  Oodi   Helsinki '),
        'search:oodi helsinki');
    expect(CachingGeocodingService.searchKey(' '), isNull);
    expect(CachingGeocodingService.reverseKey(GeoPoint(60.1, -0.123456)),
        'reverse:60.10000,-0.12346');
    expect(CachingGeocodingService.placeKey(GeoPoint(56.462, -2.971)),
        'place:56.46,-2.97');
  });

  group('placeName (region names, PLAN.md D26)', () {
    test('asked once per ~1 km; nearby points share the answer', () async {
      network.places[GeoPoint(56.462, -2.971)] = 'Dundee';
      expect(await service.placeName(GeoPoint(56.462, -2.971)), 'Dundee');
      // 300 m away, same rounded key: answered from the cache.
      expect(await service.placeName(GeoPoint(56.4641, -2.9690)), 'Dundee');
      expect(network.placeCalls, hasLength(1));
    });

    test('"no name" is cached; errors are not', () async {
      final sea = GeoPoint(57.5, 1.5);
      expect(await service.placeName(sea), isNull);
      expect(await service.placeName(sea), isNull);
      expect(network.placeCalls, hasLength(1));

      final other = GeoPoint(10, 10);
      network.failNext = const GeocodingException(GeocodingFailure.offline);
      await expectLater(
          service.placeName(other), throwsA(isA<GeocodingException>()));
      expect(await service.placeName(other), isNull);
      expect(network.placeCalls, hasLength(3));
    });
  });
}

class _BrokenCache implements GeocodeCache {
  @override
  Future<String?> get(String key, {required DateTime notBefore}) =>
      throw StateError('disk full');

  @override
  Future<void> put(String key, String value,
          {required DateTime at, required DateTime pruneBefore}) =>
      throw StateError('disk full');
}
