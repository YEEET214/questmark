import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/geocode_cache_repository.dart';
import '../models/geo_point.dart';
import '../models/geocode_result.dart';
import 'geocoding_service.dart';

/// Answers from the SQLite cache when it can, and asks [inner] (Nominatim)
/// only when it must (PLAN.md D6).
///
/// * Searches are keyed by the **normalised** query (trimmed, lower-case,
///   single spaces), so "Oodi Helsinki" and "  oodi   helsinki " are one
///   question.
/// * Reverse lookups are keyed by the point rounded to 5 decimals (about
///   1 m); town names ([placeName]) by the point rounded to 2 (about
///   1 km).
/// * "No results" and "no address" are cached too: they're real answers.
///   Errors are not, so a failed lookup can be retried.
/// * Entries older than [maxAge] are ignored (places and addresses do
///   change), and removed when new entries are written.
/// * If the cache itself fails, the service still works, just uncached.
class CachingGeocodingService implements GeocodingService {
  CachingGeocodingService(
    this._inner,
    this._cache, {
    DateTime Function()? clock,
    this.maxAge = const Duration(days: 30),
  }) : _clock = clock ?? DateTime.now;

  final GeocodingService _inner;
  final GeocodeCache _cache;
  final DateTime Function() _clock;
  final Duration maxAge;

  /// The search cache key for [query], or `null` for a blank query.
  static String? searchKey(String query) {
    final normalised =
        query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return normalised.isEmpty ? null : 'search:$normalised';
  }

  static String reverseKey(GeoPoint p) =>
      'reverse:${p.latitude.toStringAsFixed(5)},'
      '${p.longitude.toStringAsFixed(5)}';

  /// Town names are asked for a point rounded to 2 decimals (about
  /// 1 km), so that's the key too.
  static String placeKey(GeoPoint p) =>
      'place:${p.latitude.toStringAsFixed(2)},'
      '${p.longitude.toStringAsFixed(2)}';

  @override
  Future<List<GeocodeResult>> search(String query) async {
    final key = searchKey(query);
    if (key == null) return const [];

    final cached = await _read(key);
    if (cached != null) {
      return [
        for (final r in (jsonDecode(cached) as List<Object?>))
          GeocodeResult.fromJson(r! as Map<String, Object?>),
      ];
    }
    final results = await _inner.search(query.trim());
    await _write(key, jsonEncode([for (final r in results) r.toJson()]));
    return results;
  }

  @override
  Future<String?> reverse(GeoPoint point) async {
    final key = reverseKey(point);
    final cached = await _read(key);
    if (cached != null) {
      return (jsonDecode(cached) as Map<String, Object?>)['label'] as String?;
    }
    final label = await _inner.reverse(point);
    await _write(key, jsonEncode({'label': label}));
    return label;
  }

  @override
  Future<String?> placeName(GeoPoint point) async {
    final key = placeKey(point);
    final cached = await _read(key);
    if (cached != null) {
      return (jsonDecode(cached) as Map<String, Object?>)['name'] as String?;
    }
    final name = await _inner.placeName(point);
    await _write(key, jsonEncode({'name': name}));
    return name;
  }

  Future<String?> _read(String key) async {
    try {
      return await _cache.get(key, notBefore: _clock().subtract(maxAge));
    } catch (e) {
      debugPrint('Geocode cache read failed: $e');
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    final now = _clock();
    try {
      await _cache.put(key, value, at: now, pruneBefore: now.subtract(maxAge));
    } catch (e) {
      debugPrint('Geocode cache write failed: $e');
    }
  }
}
