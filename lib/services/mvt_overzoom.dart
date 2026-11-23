import 'dart:io' show gzip;
import 'dart:math' as math;
import 'dart:typed_data';

/// Makes a detailed tile out of a less detailed one ("overzooming"), for
/// when the real tile isn't available: no connection, and no downloaded
/// region has it (PLAN.md D27).
///
/// [bytes] is a Mapbox Vector Tile (gzipped or not) at zoom z. The result
/// is the tile at zoom z + [dz] whose position inside it is ([dx], [dy])
/// (0 ≤ dx, dy < 2^dz): every shape scaled up by 2^dz, moved, and cut to
/// the new tile plus a small [buffer] around it, so nothing visible is
/// lost and the map draws only what is on screen. Attributes (names,
/// classes) are copied unchanged, so the map style draws it as usual:
/// water stays blue, land keeps its rough outline.
///
/// Pure Dart, no I/O: it runs in a background isolate.
Uint8List overzoomMvt(
  Uint8List bytes, {
  required int dz,
  required int dx,
  required int dy,
  int buffer = 128,
}) {
  final data = bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b
      ? Uint8List.fromList(gzip.decode(bytes))
      : bytes;
  final out = _Writer();
  final r = _Reader(data, 0, data.length);
  while (r.more) {
    final start = r.pos;
    final tag = r.varint();
    if (tag == _layerTag) {
      final len = r.varint();
      final layer = _overzoomLayer(
          _Reader(data, r.pos, r.pos + len), dz, dx, dy, buffer);
      r.pos += len;
      if (layer != null) out.bytesField(3, layer);
    } else {
      r.skip(tag & 7);
      out.raw(data, start, r.pos);
    }
  }
  return out.take();
}

const _layerTag = (3 << 3) | 2;

Uint8List? _overzoomLayer(_Reader r, int dz, int dx, int dy, int buffer) {
  final features = <(int, int)>[];
  final other = _Writer();
  var extent = 4096;
  final data = r.data;
  while (r.more) {
    final start = r.pos;
    final tag = r.varint();
    if (tag == (2 << 3 | 2)) {
      final len = r.varint();
      features.add((r.pos, r.pos + len));
      r.pos += len;
      continue;
    }
    if (tag == (5 << 3 | 0)) {
      extent = r.varint();
    } else {
      r.skip(tag & 7);
    }
    other.raw(data, start, r.pos);
  }

  final clip = _Clip(
    scale: 1 << dz,
    offsetX: dx * extent,
    offsetY: dy * extent,
    lo: -buffer,
    hi: extent + buffer,
  );
  final out = _Writer()..raw(other.take(), 0, null);
  var kept = 0;
  for (final (s, e) in features) {
    final f = _overzoomFeature(_Reader(data, s, e), clip);
    if (f != null) {
      out.bytesField(2, f);
      kept++;
    }
  }
  return kept == 0 ? null : out.take();
}

Uint8List? _overzoomFeature(_Reader r, _Clip clip) {
  final other = _Writer();
  var type = 0;
  List<int>? geometry;
  final data = r.data;
  while (r.more) {
    final start = r.pos;
    final tag = r.varint();
    if (tag == (4 << 3 | 2)) {
      final len = r.varint();
      final end = r.pos + len;
      geometry = [];
      while (r.pos < end) {
        geometry.add(r.varint());
      }
      continue;
    }
    if (tag == (3 << 3 | 0)) {
      type = r.varint();
    } else {
      r.skip(tag & 7);
    }
    other.raw(data, start, r.pos);
  }
  if (geometry == null) return null;

  final parts = _decode(geometry, clip);
  final List<List<int>> clipped;
  switch (type) {
    case 1:
      clipped = [
        for (final p in parts)
          if (clip.inside(p[0], p[1])) p,
      ];
    case 2:
      clipped = [for (final p in parts) ...clip.line(p)];
    case 3:
      clipped = clip.polygon(parts);
    default:
      return null;
  }
  if (clipped.isEmpty) return null;

  final encoded = _encode(type, clipped);
  final out = _Writer()..raw(other.take(), 0, null);
  out.packedField(4, encoded);
  return out.take();
}

/// The parts of a geometry (points; lines; polygon rings), as flat
/// `[x0, y0, x1, y1, …]` lists, already scaled and moved by [clip].
List<List<int>> _decode(List<int> g, _Clip clip) {
  final parts = <List<int>>[];
  var x = 0, y = 0, i = 0;
  List<int>? current;
  while (i < g.length) {
    final command = g[i++];
    final id = command & 7;
    final count = command >> 3;
    if (id == 7) continue; // ClosePath: rings are closed implicitly here
    for (var k = 0; k < count && i + 1 < g.length; k++) {
      x += _unzigzag(g[i++]);
      y += _unzigzag(g[i++]);
      final px = x * clip.scale - clip.offsetX;
      final py = y * clip.scale - clip.offsetY;
      if (id == 1) {
        current = [px, py];
        parts.add(current);
      } else if (id == 2) {
        current?.addAll([px, py]);
      }
    }
  }
  return parts;
}

List<int> _encode(int type, List<List<int>> parts) {
  final out = <int>[];
  var cx = 0, cy = 0;
  void moveTo(int x, int y) {
    out
      ..add(_zigzag(x - cx))
      ..add(_zigzag(y - cy));
    cx = x;
    cy = y;
  }

  if (type == 1) {
    out.add(1 | (parts.length << 3));
    for (final p in parts) {
      moveTo(p[0], p[1]);
    }
    return out;
  }
  for (final p in parts) {
    out.add(1 | (1 << 3));
    moveTo(p[0], p[1]);
    out.add(2 | ((p.length ~/ 2 - 1) << 3));
    for (var j = 2; j < p.length; j += 2) {
      moveTo(p[j], p[j + 1]);
    }
    if (type == 3) out.add(7 | (1 << 3));
  }
  return out;
}

int _unzigzag(int n) => (n >> 1) ^ -(n & 1);
int _zigzag(int n) => (n << 1) ^ (n >> 63);

/// The new tile's window: scaling, offset, and cutting to [lo]..[hi].
class _Clip {
  _Clip({
    required this.scale,
    required this.offsetX,
    required this.offsetY,
    required this.lo,
    required this.hi,
  });

  final int scale, offsetX, offsetY, lo, hi;

  bool inside(int x, int y) => x >= lo && x <= hi && y >= lo && y <= hi;

  /// Cuts a polyline to the window: the runs that are inside it.
  List<List<int>> line(List<int> p) {
    final runs = <List<int>>[];
    List<int>? run;
    for (var j = 0; j + 3 < p.length; j += 2) {
      final seg = _clipSegment(
          p[j].toDouble(), p[j + 1].toDouble(), p[j + 2].toDouble(),
          p[j + 3].toDouble());
      if (seg == null) {
        run = null;
        continue;
      }
      final (ax, ay, bx, by) = seg;
      if (run == null || run[run.length - 2] != ax || run.last != ay) {
        run = [ax, ay];
        runs.add(run);
      }
      if (run[run.length - 2] != bx || run.last != by) run.addAll([bx, by]);
    }
    return [for (final r in runs) if (r.length >= 4) r];
  }

  /// Liang–Barsky: the part of segment a→b inside the window, rounded.
  (int, int, int, int)? _clipSegment(
      double ax, double ay, double bx, double by) {
    var t0 = 0.0, t1 = 1.0;
    final ddx = bx - ax, ddy = by - ay;
    bool edge(double p, double q) {
      if (p == 0) return q >= 0;
      final t = q / p;
      if (p < 0) {
        if (t > t1) return false;
        if (t > t0) t0 = t;
      } else {
        if (t < t0) return false;
        if (t < t1) t1 = t;
      }
      return true;
    }

    if (!edge(-ddx, ax - lo) ||
        !edge(ddx, hi - ax) ||
        !edge(-ddy, ay - lo) ||
        !edge(ddy, hi - ay)) {
      return null;
    }
    return (
      (ax + t0 * ddx).round(),
      (ay + t0 * ddy).round(),
      (ax + t1 * ddx).round(),
      (ay + t1 * ddy).round(),
    );
  }

  /// Cuts polygon rings to the window (Sutherland–Hodgman). A ring with a
  /// positive area is an outer ring; the rings after it with a negative
  /// area are its holes, and are dropped with it if it's cut away.
  List<List<int>> polygon(List<List<int>> rings) {
    final out = <List<int>>[];
    var outerKept = false;
    for (final ring in rings) {
      final area = _area(ring);
      if (area == 0) continue;
      final isOuter = area > 0;
      if (!isOuter && !outerKept) continue;
      final cut = _clipRing(ring);
      final ok = cut.length >= 6 && _area(cut) != 0;
      if (ok) out.add(cut);
      if (isOuter) outerKept = ok;
    }
    return out;
  }

  List<int> _clipRing(List<int> ring) {
    var minX = ring[0], maxX = ring[0], minY = ring[1], maxY = ring[1];
    for (var j = 2; j < ring.length; j += 2) {
      minX = math.min(minX, ring[j]);
      maxX = math.max(maxX, ring[j]);
      minY = math.min(minY, ring[j + 1]);
      maxY = math.max(maxY, ring[j + 1]);
    }
    if (maxX < lo || minX > hi || maxY < lo || minY > hi) return const [];
    if (minX >= lo && maxX <= hi && minY >= lo && maxY <= hi) return ring;

    var pts = <double>[for (final v in ring) v.toDouble()];
    // One pass per window edge: (axis, limit, keep >= limit?).
    for (final (axis, limit, keepAbove) in [
      (0, lo, true),
      (0, hi, false),
      (1, lo, true),
      (1, hi, false),
    ]) {
      if (pts.isEmpty) break;
      final next = <double>[];
      bool keep(double x, double y) {
        final v = axis == 0 ? x : y;
        return keepAbove ? v >= limit : v <= limit;
      }

      final n = pts.length ~/ 2;
      for (var k = 0; k < n; k++) {
        final cx = pts[2 * k], cy = pts[2 * k + 1];
        final pk = (k + n - 1) % n;
        final px = pts[2 * pk], py = pts[2 * pk + 1];
        final cIn = keep(cx, cy), pIn = keep(px, py);
        if (cIn != pIn) {
          final t = axis == 0
              ? (limit - px) / (cx - px)
              : (limit - py) / (cy - py);
          next
            ..add(px + t * (cx - px))
            ..add(py + t * (cy - py));
        }
        if (cIn) next.addAll([cx, cy]);
      }
      pts = next;
    }

    final out = <int>[];
    for (var j = 0; j < pts.length; j += 2) {
      final x = pts[j].round(), y = pts[j + 1].round();
      if (out.length >= 2 && out[out.length - 2] == x && out.last == y) {
        continue;
      }
      out.addAll([x, y]);
    }
    if (out.length >= 4 && out[0] == out[out.length - 2] &&
        out[1] == out.last) {
      out.length -= 2;
    }
    return out;
  }

  /// Twice the signed area (surveyor's formula, MVT's convention: an
  /// outer ring is positive).
  static int _area(List<int> r) {
    var sum = 0;
    final n = r.length ~/ 2;
    for (var k = 0; k < n; k++) {
      final j = (k + 1) % n;
      sum += r[2 * k] * r[2 * j + 1] - r[2 * j] * r[2 * k + 1];
    }
    return sum;
  }
}

class _Reader {
  _Reader(this.data, this.pos, this.end);
  final Uint8List data;
  int pos;
  final int end;

  bool get more => pos < end;

  int varint() {
    var result = 0, shift = 0;
    while (true) {
      final b = data[pos++];
      result |= (b & 0x7f) << shift;
      if (b & 0x80 == 0) return result;
      shift += 7;
    }
  }

  void skip(int wireType) {
    switch (wireType) {
      case 0:
        varint();
      case 1:
        pos += 8;
      case 2:
        // Not `pos += varint()`: that would add to pos as it was before
        // the length was read.
        final length = varint();
        pos += length;
      case 5:
        pos += 4;
      default:
        throw FormatException('Unsupported wire type $wireType');
    }
  }
}

class _Writer {
  final _b = BytesBuilder(copy: false);

  void raw(Uint8List data, int start, int? end) =>
      _b.add(Uint8List.sublistView(data, start, end));

  void varint(int v) {
    final out = <int>[];
    var n = v;
    while (n >= 0x80 || n < 0) {
      out.add((n & 0x7f) | 0x80);
      n = n >>> 7;
    }
    out.add(n);
    _b.add(out);
  }

  void bytesField(int field, Uint8List bytes) {
    varint(field << 3 | 2);
    varint(bytes.length);
    _b.add(bytes);
  }

  void packedField(int field, List<int> values) {
    final inner = _Writer();
    for (final v in values) {
      inner.varint(v);
    }
    bytesField(field, inner.take());
  }

  Uint8List take() => _b.takeBytes();
}
