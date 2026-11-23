import 'dart:typed_data';

/// A tiny Mapbox Vector Tile writer, to build exact test tiles.
///
/// [mvtFeature] takes parts as absolute coordinates; type 1 = points,
/// 2 = lines, 3 = polygons. [mvtTile] makes a one-layer tile whose
/// features may use tag key 0 = "name", value 0 = "Sea".


List<int> _varint(int v) {
  final out = <int>[];
  while (v >= 0x80) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  return out..add(v);
}

List<int> _field(int n, List<int> bytes) =>
    [..._varint(n << 3 | 2), ..._varint(bytes.length), ...bytes];

int _zz(int n) => (n << 1) ^ (n >> 63);

/// Geometry commands for parts given as absolute coordinates.
List<int> _geometry(int type, List<List<int>> parts) {
  final g = <int>[];
  var cx = 0, cy = 0;
  void to(int x, int y) {
    g
      ..add(_zz(x - cx))
      ..add(_zz(y - cy));
    cx = x;
    cy = y;
  }

  for (final p in parts) {
    g.add(1 | 1 << 3);
    to(p[0], p[1]);
    if (p.length > 2) {
      g.add(2 | ((p.length ~/ 2 - 1) << 3));
      for (var i = 2; i < p.length; i += 2) {
        to(p[i], p[i + 1]);
      }
    }
    if (type == 3) g.add(7 | 1 << 3);
  }
  return g;
}

List<int> mvtFeature(int type, List<List<int>> parts, {int? nameValue}) {
  final packed = [for (final v in _geometry(type, parts)) ..._varint(v)];
  return [
    if (nameValue != null) ..._field(2, [..._varint(0), ..._varint(nameValue)]),
    ..._varint(3 << 3), ..._varint(type),
    ..._field(4, packed),
  ];
}

Uint8List mvtTile(String layer, List<List<int>> features) {
  final value = _field(1, 'Sea'.codeUnits); // Value.string_value
  return Uint8List.fromList(_field(3, [
    ..._field(1, layer.codeUnits),
    for (final f in features) ..._field(2, f),
    ..._field(3, 'name'.codeUnits),
    ..._field(4, value),
    ..._varint(5 << 3), ..._varint(4096),
    ..._varint(15 << 3), ..._varint(2),
  ]));
}

