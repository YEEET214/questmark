// Builds the world map that ships inside QuestMark (PLAN.md D7, Phase 8a).
//
// Run once, from the project root, on a developer PC:
//
//   dart run tool/build_world_map.dart            (zoom 0-5, the default)
//   dart run tool/build_world_map.dart --max-zoom 4
//
// Writes assets/map/world.mbtiles, assets/map/offline_style.json and
// assets/map/world.json (version and size, read by the app). Downloads at
// most 3,000 tiles / 50 MB, 2 at a time, as OpenFreeMap's rules require.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:questmark/app_info.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'world_map/world_map_builder.dart';

Future<void> main(List<String> args) async {
  var maxZoom = 5;
  final i = args.indexOf('--max-zoom');
  if (i >= 0 && i + 1 < args.length) maxZoom = int.parse(args[i + 1]);

  sqfliteFfiInit();
  final client = http.Client();
  final builder = WorldMapBuilder(
    client: client,
    databaseFactory: databaseFactoryFfi,
    userAgent: AppInfo.userAgent,
    maxZoom: maxZoom,
    log: stdout.writeln,
  );
  try {
    final report = await builder.build(
      mbtilesPath: 'assets/map/world.mbtiles',
      stylePath: 'assets/map/offline_style.json',
    );
    final version = DateTime.now().toUtc().toIso8601String().split('T').first;
    await File('assets/map/world.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'version': '$version-z$maxZoom',
        'maxZoom': maxZoom,
        'bytes': report.fileBytes,
        'tiles': report.tilesStored,
      }),
    );
    stdout.writeln('Wrote assets/map/world.json');
  } on WorldMapBuildException catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  } finally {
    client.close();
  }
}
