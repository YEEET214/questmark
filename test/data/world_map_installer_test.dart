import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:questmark/data/world_map_installer.dart';

/// An asset bundle with a world map of [mapBytes] and version [version].
/// Counts how often the (big) map asset is read.
class _Bundle extends CachingAssetBundle {
  _Bundle({required this.version, required this.mapBytes, this.hasMap = true});

  String version;
  List<int> mapBytes;
  bool hasMap;
  int mapLoads = 0;

  @override
  Future<ByteData> load(String key) async {
    if (!hasMap) throw StateError('no asset $key');
    if (key == WorldMapInstaller.mapAsset) {
      mapLoads++;
      return ByteData.sublistView(Uint8List.fromList(mapBytes));
    }
    if (key == WorldMapInstaller.manifestAsset) {
      final json = jsonEncode({'version': version, 'bytes': mapBytes.length});
      return ByteData.sublistView(Uint8List.fromList(utf8.encode(json)));
    }
    throw StateError('no asset $key');
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      utf8.decode((await load(key)).buffer.asUint8List());
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('world_inst'));
  tearDown(() async => dir.delete(recursive: true));

  WorldMapInstaller installer(_Bundle bundle) =>
      WorldMapInstaller(directory: () async => dir.path, bundle: bundle);

  List<String> files() =>
      dir.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

  test('a build without a bundled map returns null', () async {
    final bundle = _Bundle(version: 'v1', mapBytes: [1], hasMap: false);
    expect(await installer(bundle).install(), isNull);
  });

  test('the first launch copies the map out of the assets', () async {
    final bundle = _Bundle(version: '2026-11-23-z5', mapBytes: [1, 2, 3]);
    final path = await installer(bundle).install();
    expect(File(path!).readAsBytesSync(), [1, 2, 3]);
    expect(files(), ['world_map_2026-11-23-z5.mbtiles']);
  });

  test('later launches reuse the copy without reading the asset again',
      () async {
    final bundle = _Bundle(version: 'v1', mapBytes: [1, 2, 3]);
    await installer(bundle).install();
    await installer(bundle).install();
    expect(bundle.mapLoads, 1);
  });

  test('a damaged copy (wrong size) is replaced', () async {
    final bundle = _Bundle(version: 'v1', mapBytes: [1, 2, 3]);
    final path = await installer(bundle).install();
    File(path!).writeAsBytesSync([9]);
    await installer(bundle).install();
    expect(File(path).readAsBytesSync(), [1, 2, 3]);
  });

  test('an app update with a new map replaces the old file', () async {
    final bundle = _Bundle(version: 'v1', mapBytes: [1]);
    await installer(bundle).install();
    bundle
      ..version = 'v2'
      ..mapBytes = [2, 2];
    final path = await installer(bundle).install();
    expect(File(path!).readAsBytesSync(), [2, 2]);
    expect(files(), ['world_map_v2.mbtiles']);
  });

  test('an unfinished copy from an interrupted launch is cleaned up',
      () async {
    File('${dir.path}/world_map_v1.mbtiles.part').writeAsBytesSync([0]);
    await installer(_Bundle(version: 'v1', mapBytes: [1])).install();
    expect(files(), ['world_map_v1.mbtiles']);
  });

  test('other files in the folder are left alone', () async {
    File('${dir.path}/questmark.db').writeAsBytesSync([7]);
    await installer(_Bundle(version: 'v1', mapBytes: [1])).install();
    expect(files(), contains('questmark.db'));
  });
}
