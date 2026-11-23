import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Puts the bundled world map (PLAN.md D7) where SQLite can read it.
///
/// The map ships as a Flutter asset, but SQLite can only open real files,
/// so the first launch copies it into the app's own storage. Later
/// launches find the copy and skip this. When an app update brings a new
/// world map (a new `version` in `world.json`), the new file is copied and
/// the old one deleted.
///
/// The copy is written to a temporary name and renamed when complete, so
/// a launch interrupted mid-copy never leaves a half-written map behind.
class WorldMapInstaller {
  WorldMapInstaller({
    required this.directory,
    AssetBundle? bundle,
  }) : _bundle = bundle ?? rootBundle;

  /// Where the copy goes (the app's private storage).
  final Future<String> Function() directory;
  final AssetBundle _bundle;

  static const manifestAsset = 'assets/map/world.json';
  static const mapAsset = 'assets/map/world.mbtiles';
  static const _prefix = 'world_map_';

  /// Copies the map if needed and returns the file's path, or `null` if
  /// this build of the app has no bundled world map.
  Future<String?> install() async {
    final Map<String, Object?> manifest;
    try {
      manifest = jsonDecode(await _bundle.loadString(manifestAsset))
          as Map<String, Object?>;
    } catch (_) {
      return null; // no bundled map in this build
    }
    final version = (manifest['version'] as String)
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final bytes = manifest['bytes'] as int;

    final dir = await directory();
    await Directory(dir).create(recursive: true);
    final target = File(p.join(dir, '$_prefix$version.mbtiles'));

    if (!(await target.exists() && await target.length() == bytes)) {
      final data = await _bundle.load(mapAsset);
      final part = File('${target.path}.part');
      await part.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
    }

    // Remove maps (and unfinished copies) from older versions.
    await for (final e in Directory(dir).list()) {
      final name = p.basename(e.path);
      if (e is File && name.startsWith(_prefix) && e.path != target.path) {
        await e.delete();
      }
    }
    return target.path;
  }
}
