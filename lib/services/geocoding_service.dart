import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../app_info.dart';
import '../models/geo_point.dart';
import '../models/geocode_result.dart';
import 'rate_limiter.dart';

/// Address search and reverse geocoding (PLAN.md D6).
///
/// An interface so the UI and state can be tested with a fake. The real
/// one is [NominatimGeocoder], wrapped in a caching layer
/// (`CachingGeocodingService`).
abstract interface class GeocodingService {
  /// Places matching [query], best first (at most a few). Throws
  /// [GeocodingException].
  Future<List<GeocodeResult>> search(String query);

  /// A short address for [point], or `null` if there is none (e.g. the
  /// open sea). Throws [GeocodingException].
  Future<String?> reverse(GeoPoint point);

  /// The name of the town or area around [point] (e.g. "Dundee"), or
  /// `null` if there is none. Names downloaded map regions (PLAN.md D26).
  /// Throws [GeocodingException].
  Future<String?> placeName(GeoPoint point);
}

enum GeocodingFailure {
  /// No connection, or the server didn't answer in time.
  offline,

  /// The server says we're asking too often (HTTP 429).
  rateLimited,

  /// Any other server error.
  server,

  /// The answer wasn't in the expected format.
  badResponse,
}

class GeocodingException implements Exception {
  const GeocodingException(this.failure, [this.detail]);

  final GeocodingFailure failure;
  final String? detail;

  /// A short explanation for the user.
  String get userMessage => switch (failure) {
        GeocodingFailure.offline =>
          'No connection. Check your internet and try again.',
        GeocodingFailure.rateLimited =>
          'The address service is busy. Try again in a moment.',
        GeocodingFailure.server =>
          'The address service is not available right now.',
        GeocodingFailure.badResponse =>
          'The address service sent an answer QuestMark can\'t read.',
      };

  @override
  String toString() => 'GeocodingException($failure, $detail)';
}

/// [GeocodingService] using OpenStreetMap's Nominatim server.
///
/// Policy (https://operations.osmfoundation.org/policies/nominatim/):
/// * at most 1 request per second, no parallel requests: every call goes
///   through [limiter] (≥ 1.1 s apart);
/// * a User-Agent that identifies the app ([AppInfo.userAgent]);
/// * no autocomplete: the UI calls [search] only when the user presses
///   Search;
/// * results are cached (by `CachingGeocodingService`), so the same
///   question is never asked twice.
class NominatimGeocoder implements GeocodingService {
  NominatimGeocoder({
    http.Client? client,
    RateLimiter? limiter,
    this.baseUri = defaultBaseUri,
    this.timeout = const Duration(seconds: 10),
  })  : _client = client ?? http.Client(),
        _limiter = limiter ?? RateLimiter(minInterval);

  static const defaultBaseUri = 'https://nominatim.openstreetmap.org';

  /// Spacing between requests: a little over the policy's 1 s.
  static const minInterval = Duration(milliseconds: 1100);

  /// How many search results to ask for.
  static const resultLimit = 5;

  final http.Client _client;
  final RateLimiter _limiter;
  final String baseUri;
  final Duration timeout;

  static const _headers = {
    'User-Agent': AppInfo.userAgent,
    'Accept': 'application/json',
  };

  @override
  Future<List<GeocodeResult>> search(String query) async {
    final body = await _get('/search', {
      'q': query,
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '$resultLimit',
    });
    try {
      final list = jsonDecode(body) as List<Object?>;
      return [
        for (final item in list.cast<Map<String, Object?>>())
          GeocodeResult(
            label: shortLabel(item),
            fullName: item['display_name']! as String,
            point: GeoPoint(
              double.parse(item['lat']! as String),
              double.parse(item['lon']! as String),
            ),
          ),
      ];
    } catch (e) {
      throw GeocodingException(GeocodingFailure.badResponse, '$e');
    }
  }

  @override
  Future<String?> reverse(GeoPoint point) async {
    final body = await _get('/reverse', {
      'lat': '${point.latitude}',
      'lon': '${point.longitude}',
      'format': 'jsonv2',
      'addressdetails': '1',
      // Building level: the nearest address, not just the street.
      'zoom': '18',
    });
    try {
      final json = jsonDecode(body) as Map<String, Object?>;
      // Nominatim answers {"error": "Unable to geocode"} when there's no
      // address (e.g. at sea). That's a normal "no address", not a failure.
      if (json.containsKey('error')) return null;
      return shortLabel(json);
    } catch (e) {
      throw GeocodingException(GeocodingFailure.badResponse, '$e');
    }
  }

  /// Rounds [point] to 2 decimals (about 1 km) before sending it: a town
  /// name doesn't need more, and for "my area" it is the user's own
  /// position.
  @override
  Future<String?> placeName(GeoPoint point) async {
    final body = await _get('/reverse', {
      'lat': point.latitude.toStringAsFixed(2),
      'lon': point.longitude.toStringAsFixed(2),
      'format': 'jsonv2',
      'addressdetails': '1',
      // Town / city level.
      'zoom': '10',
    });
    try {
      final json = jsonDecode(body) as Map<String, Object?>;
      if (json.containsKey('error')) return null;
      return townName(json);
    } catch (e) {
      throw GeocodingException(GeocodingFailure.badResponse, '$e');
    }
  }

  /// The town (or the nearest larger area) of a Nominatim result, e.g.
  /// "Dundee"; falls back to the result's name, then to the first part of
  /// its full name.
  static String? townName(Map<String, Object?> item) {
    final address = item['address'];
    if (address is Map<String, Object?>) {
      for (final k in const [
        'city',
        'town',
        'village',
        'municipality',
        'hamlet',
        'county',
        'state_district',
        'state',
        'country',
      ]) {
        final v = address[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    }
    final name = (item['name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) return name;
    final full = (item['display_name'] as String?)?.split(',').first.trim();
    return full == null || full.isEmpty ? null : full;
  }

  Future<String> _get(String path, Map<String, String> params) {
    final uri = Uri.parse('$baseUri$path').replace(queryParameters: params);
    return _limiter.run(() async {
      final http.Response response;
      try {
        response =
            await _client.get(uri, headers: _headers).timeout(timeout);
      } on TimeoutException catch (e) {
        throw GeocodingException(GeocodingFailure.offline, '$e');
      } on SocketException catch (e) {
        throw GeocodingException(GeocodingFailure.offline, '$e');
      } on http.ClientException catch (e) {
        throw GeocodingException(GeocodingFailure.offline, '$e');
      }
      if (response.statusCode == 429) {
        throw const GeocodingException(GeocodingFailure.rateLimited);
      }
      if (response.statusCode != 200) {
        throw GeocodingException(
            GeocodingFailure.server, 'HTTP ${response.statusCode}');
      }
      // Nominatim sends UTF-8; decode explicitly so "ä" etc. survive even
      // if the content type has no charset.
      return utf8.decode(response.bodyBytes);
    });
  }

  /// A short, readable address from a Nominatim result: the place's name
  /// (if it has one), then "street number", then the town. For example
  /// "Oodi, Töölönlahdenkatu 4, Helsinki" instead of the full
  /// "Oodi, 4, Töölönlahdenkatu, Kluuvi, Eteläinen suurpiiri, Helsinki,
  /// …, Suomi / Finland". Falls back to the full name.
  static String shortLabel(Map<String, Object?> item) {
    final full = (item['display_name'] as String?) ?? '';
    final address = item['address'];
    if (address is! Map<String, Object?>) return full;

    String? field(List<String> keys) {
      for (final k in keys) {
        final v = address[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return null;
    }

    final road =
        field(['road', 'pedestrian', 'footway', 'path', 'square', 'cycleway']);
    final number = field(['house_number']);
    final place = field([
      'city',
      'town',
      'village',
      'hamlet',
      'municipality',
      'suburb',
      'county',
      'state',
    ]);
    final name = (item['name'] as String?)?.trim();

    final parts = <String>[
      if (name != null && name.isNotEmpty && name != road) name,
      if (road != null) number == null ? road : '$road $number',
      ?place,
    ];
    final unique = <String>[];
    for (final p in parts) {
      if (!unique.contains(p)) unique.add(p);
    }
    return unique.isEmpty ? full : unique.join(', ');
  }
}
