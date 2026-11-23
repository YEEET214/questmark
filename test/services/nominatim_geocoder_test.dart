import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:questmark/app_info.dart';
import 'package:questmark/models/geo_point.dart';
import 'package:questmark/services/geocoding_service.dart';
import 'package:questmark/services/rate_limiter.dart';

/// A trimmed real Nominatim jsonv2 search answer (with addressdetails).
const _oodiJson = '''
[
  {
    "place_id": 1,
    "lat": "60.1737844",
    "lon": "24.9379464",
    "name": "Oodi",
    "display_name": "Oodi, 4, Töölönlahdenkatu, Kluuvi, Eteläinen suurpiiri, Helsinki, Helsingin seutukunta, Uusimaa, Manner-Suomi, 00100, Suomi / Finland",
    "address": {
      "amenity": "Oodi",
      "house_number": "4",
      "road": "Töölönlahdenkatu",
      "suburb": "Kluuvi",
      "city": "Helsinki",
      "postcode": "00100",
      "country": "Suomi / Finland"
    }
  }
]
''';

void main() {
  /// A geocoder whose HTTP goes to [handler], with no rate-limit delay
  /// (the limiter has its own tests; one test below checks it's used).
  NominatimGeocoder geocoder(
    Future<http.Response> Function(http.Request) handler, {
    RateLimiter? limiter,
  }) =>
      NominatimGeocoder(
        client: MockClient(handler),
        limiter: limiter ?? RateLimiter(Duration.zero),
      );

  http.Response utf8Json(String body, [int status = 200]) =>
      http.Response.bytes(utf8.encode(body), status,
          headers: {'content-type': 'application/json'});

  group('search', () {
    test('sends a polite request: our User-Agent, jsonv2, a small limit',
        () async {
      late http.Request sent;
      await geocoder((r) async {
        sent = r;
        return utf8Json('[]');
      }).search('Oodi Helsinki');

      expect(sent.method, 'GET');
      expect(sent.url.host, 'nominatim.openstreetmap.org');
      expect(sent.url.path, '/search');
      expect(sent.url.queryParameters['q'], 'Oodi Helsinki');
      expect(sent.url.queryParameters['format'], 'jsonv2');
      expect(sent.url.queryParameters['limit'], '5');
      expect(sent.headers['User-Agent'], AppInfo.userAgent);
    });

    test('parses results, with a short label and the full name', () async {
      final results =
          await geocoder((_) async => utf8Json(_oodiJson)).search('oodi');
      expect(results, hasLength(1));
      final r = results.single;
      expect(r.label, 'Oodi, Töölönlahdenkatu 4, Helsinki');
      expect(r.fullName, startsWith('Oodi, 4, Töölönlahdenkatu'));
      expect(r.point, GeoPoint(60.1737844, 24.9379464));
    });

    test('no results is an empty list', () async {
      expect(await geocoder((_) async => utf8Json('[]')).search('x'), isEmpty);
    });
  });

  group('reverse', () {
    test('asks for the address at building level', () async {
      late http.Request sent;
      final label = await geocoder((r) async {
        sent = r;
        return utf8Json(jsonEncode(
            (jsonDecode(_oodiJson) as List<Object?>).single));
      }).reverse(GeoPoint(60.17378, 24.93795));

      expect(sent.url.path, '/reverse');
      expect(sent.url.queryParameters['lat'], '60.17378');
      expect(sent.url.queryParameters['lon'], '24.93795');
      expect(sent.url.queryParameters['zoom'], '18');
      expect(sent.headers['User-Agent'], AppInfo.userAgent);
      expect(label, 'Oodi, Töölönlahdenkatu 4, Helsinki');
    });

    test('"Unable to geocode" (e.g. at sea) means no address, not an error',
        () async {
      final label = await geocoder(
              (_) async => utf8Json('{"error": "Unable to geocode"}'))
          .reverse(GeoPoint(0, 0));
      expect(label, isNull);
    });
  });

  group('errors', () {
    Future<GeocodingFailure> failureOf(
        Future<http.Response> Function(http.Request) handler) async {
      try {
        await geocoder(handler).search('x');
      } on GeocodingException catch (e) {
        return e.failure;
      }
      fail('expected a GeocodingException');
    }

    test('HTTP 429 -> rateLimited', () async {
      expect(await failureOf((_) async => http.Response('', 429)),
          GeocodingFailure.rateLimited);
    });

    test('other HTTP errors -> server', () async {
      expect(await failureOf((_) async => http.Response('', 503)),
          GeocodingFailure.server);
    });

    test('no connection -> offline', () async {
      expect(
          await failureOf((_) async => throw http.ClientException('no net')),
          GeocodingFailure.offline);
    });

    test('garbage -> badResponse', () async {
      expect(await failureOf((_) async => utf8Json('<html>oops</html>')),
          GeocodingFailure.badResponse);
      expect(await failureOf((_) async => utf8Json('[{"lat": 1}]')),
          GeocodingFailure.badResponse);
    });

    test('every failure has a message for the user', () {
      for (final f in GeocodingFailure.values) {
        expect(GeocodingException(f).userMessage, isNotEmpty);
      }
    });
  });

  test('requests go through the rate limiter (1.1 s apart)', () {
    fakeAsync((async) {
      final start = DateTime(2026, 11, 23);
      final sentAt = <Duration>[];
      final g = geocoder(
        (r) async {
          sentAt.add(async.elapsed);
          return utf8Json(r.url.path == '/reverse'
              ? '{"error": "Unable to geocode"}'
              : '[]');
        },
        limiter: RateLimiter(NominatimGeocoder.minInterval,
            clock: () => start.add(async.elapsed)),
      );
      g.search('a');
      g.search('b');
      g.reverse(GeoPoint(1, 1));
      async.elapse(const Duration(seconds: 5));
      expect(sentAt, [
        Duration.zero,
        NominatimGeocoder.minInterval,
        NominatimGeocoder.minInterval * 2,
      ]);
    });
  });

  group('shortLabel', () {
    String label(Map<String, Object?> address, {String? name}) =>
        NominatimGeocoder.shortLabel({
          'display_name': 'FULL',
          'name': ?name,
          'address': address,
        });

    test('street and number, then the town', () {
      expect(
          label({'road': 'Mannerheimintie', 'house_number': '13', 'city': 'Helsinki'}),
          'Mannerheimintie 13, Helsinki');
    });

    test('a named place comes first', () {
      expect(
          label({'road': 'Hämeenkatu', 'town': 'Tampere'}, name: 'Café X'),
          'Café X, Hämeenkatu, Tampere');
    });

    test('a name equal to the road is not repeated', () {
      expect(label({'road': 'Esplanadi', 'city': 'Helsinki'}, name: 'Esplanadi'),
          'Esplanadi, Helsinki');
    });

    test('villages and other places count as the town', () {
      expect(label({'road': 'Kylätie', 'village': 'Nuuksio'}),
          'Kylätie, Nuuksio');
    });

    test('falls back to the full name when nothing useful is there', () {
      expect(label({}), 'FULL');
      expect(
          NominatimGeocoder.shortLabel({'display_name': 'FULL'}), 'FULL');
    });
  });
}
