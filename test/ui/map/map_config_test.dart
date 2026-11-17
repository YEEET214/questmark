import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/ui/map/map_config.dart';

/// These tests guard the map-provider rules in CLAUDE.md / PLAN.md D4–D5.
void main() {
  test('style comes from OpenFreeMap over HTTPS', () {
    final uri = Uri.parse(MapConfig.styleUrl);
    expect(uri.scheme, 'https');
    expect(uri.host, 'tiles.openfreemap.org');
  });

  test('no code ever points at the OSM tile server', () {
    // OSM's tile policy forbids offline use and prefetching entirely, so
    // the app must never fetch tiles from it, not even by accident.
    // Comment lines are skipped, so docs may still explain the rule.
    bool usesOsmTiles(File f) => f
        .readAsLinesSync()
        .where((line) => !line.trimLeft().startsWith('//'))
        .any((line) => line.contains('tile.openstreetmap.org'));

    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where(usesOsmTiles)
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty);
  });

  test('User-Agent names the app and is sent as a header', () {
    expect(MapConfig.userAgent, matches(RegExp(r'^QuestMark/\d+\.\d+\.\d+$')));
    expect(MapConfig.httpHeaders['User-Agent'], MapConfig.userAgent);
  });

  test('User-Agent version matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version =
        RegExp(r'^version:\s*([\d.]+)', multiLine: true).firstMatch(pubspec)!;
    expect(MapConfig.appVersion, version.group(1));
  });

  test('attribution credits OpenStreetMap, OpenMapTiles and OpenFreeMap', () {
    final all = MapConfig.attributions.join(' ');
    expect(all, contains('OpenStreetMap contributors'));
    expect(all, contains('OpenMapTiles'));
    expect(all, contains('OpenFreeMap'));
  });

  test('zoom limits allow overzooming past the zoom-14 tile data', () {
    expect(MapConfig.maxZoom, greaterThan(14));
    expect(MapConfig.minZoom, lessThan(MapConfig.worldZoom));
    expect(MapConfig.questZoom, lessThanOrEqualTo(MapConfig.maxZoom));
  });
}
