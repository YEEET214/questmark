import 'dart:async';

import 'package:questmark/models/geo_point.dart';
import 'package:questmark/models/geocode_result.dart';
import 'package:questmark/services/geocoding_service.dart';

/// A [GeocodingService] with canned answers, for state and widget tests.
/// Never touches the network.
class FakeGeocodingService implements GeocodingService {
  FakeGeocodingService({
    Map<String, List<GeocodeResult>>? searches,
    Map<GeoPoint, String>? addresses,
  })  : searches = searches ?? {},
        addresses = addresses ?? {};

  /// Answers for [search], keyed by the exact query.
  final Map<String, List<GeocodeResult>> searches;

  /// Answers for [reverse]; points not listed have no address.
  final Map<GeoPoint, String> addresses;

  final searchCalls = <String>[];
  final reverseCalls = <GeoPoint>[];

  /// If set, the next call throws this (once).
  GeocodingException? failNext;

  @override
  Future<List<GeocodeResult>> search(String query) async {
    searchCalls.add(query);
    _maybeFail();
    return searches[query] ?? const [];
  }

  /// If set, [reverse] waits for it before answering, so a test can change
  /// things while a lookup is "on the network".
  Completer<void>? holdReverse;

  @override
  Future<String?> reverse(GeoPoint point) async {
    reverseCalls.add(point);
    await holdReverse?.future;
    _maybeFail();
    return addresses[point];
  }

  /// Answers for [placeName]; any other point has no name.
  final places = <GeoPoint, String>{};
  final placeCalls = <GeoPoint>[];

  @override
  Future<String?> placeName(GeoPoint point) async {
    placeCalls.add(point);
    _maybeFail();
    return places[point];
  }

  void _maybeFail() {
    final e = failNext;
    if (e != null) {
      failNext = null;
      throw e;
    }
  }
}
