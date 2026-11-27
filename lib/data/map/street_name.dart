import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math' as math;
import 'dart:typed_data';

import 'pmtiles_reader.dart';

/// Mot duong (chuoi diem trong toa do tile) co ten, doc tu lop transportation_name.
class NamedLine {
  NamedLine(this.name, this.points);
  final String name;
  final List<(int, int)> points;
}

/// Doc toi thieu Mapbox Vector Tile (protobuf) de lay cac duong co ten trong [layerName].
/// Ten uu tien: name:vi, name, name_vi, name_en. Chi lay hinh hoc LineString.
List<NamedLine> decodeNamedLines(Uint8List tile, {String layerName = 'transportation_name'}) {
  final List<NamedLine> out = <NamedLine>[];
  final _Reader t = _Reader(tile);
  while (!t.done) {
    final int tag = t.varint();
    if (tag >> 3 == 3 && tag & 7 == 2) {
      final Uint8List layer = t.bytes();
      _decodeLayer(layer, layerName, out);
    } else {
      t.skip(tag & 7);
    }
  }
  return out;
}

void _decodeLayer(Uint8List data, String wanted, List<NamedLine> out) {
  final _Reader r = _Reader(data);
  String name = '';
  final List<String> keys = <String>[];
  final List<String?> values = <String?>[];
  final List<Uint8List> features = <Uint8List>[];
  while (!r.done) {
    final int tag = r.varint();
    final int f = tag >> 3;
    final int w = tag & 7;
    if (f == 1 && w == 2) {
      name = utf8.decode(r.bytes());
    } else if (f == 2 && w == 2) {
      features.add(r.bytes());
    } else if (f == 3 && w == 2) {
      keys.add(utf8.decode(r.bytes()));
    } else if (f == 4 && w == 2) {
      values.add(_stringValue(r.bytes()));
    } else {
      r.skip(w);
    }
  }
  if (name != wanted) return;
  for (final Uint8List fe in features) {
    final _Reader fr = _Reader(fe);
    List<int> tags = <int>[];
    int type = 0;
    Uint8List geom = Uint8List(0);
    while (!fr.done) {
      final int tag = fr.varint();
      final int f = tag >> 3;
      final int w = tag & 7;
      if (f == 2 && w == 2) {
        tags = _Reader(fr.bytes()).packedVarints();
      } else if (f == 3 && w == 0) {
        type = fr.varint();
      } else if (f == 4 && w == 2) {
        geom = fr.bytes();
      } else {
        fr.skip(w);
      }
    }
    if (type != 2) continue;
    final Map<String, String> props = <String, String>{};
    for (int i = 0; i + 1 < tags.length; i += 2) {
      final int k = tags[i], v = tags[i + 1];
      if (k < keys.length && v < values.length && values[v] != null) props[keys[k]] = values[v]!;
    }
    final String? n = props['name:vi'] ?? props['name'] ?? props['name_vi'] ?? props['name_en'];
    if (n == null || n.isEmpty) continue;
    for (final List<(int, int)> line in _decodeLines(geom)) {
      if (line.length >= 2) out.add(NamedLine(n, line));
    }
  }
}

String? _stringValue(Uint8List data) {
  final _Reader r = _Reader(data);
  while (!r.done) {
    final int tag = r.varint();
    if (tag >> 3 == 1 && tag & 7 == 2) return utf8.decode(r.bytes());
    r.skip(tag & 7);
  }
  return null;
}

List<List<(int, int)>> _decodeLines(Uint8List geom) {
  final List<int> g = _Reader(geom).packedVarints();
  final List<List<(int, int)>> lines = <List<(int, int)>>[];
  List<(int, int)> cur = <(int, int)>[];
  int x = 0, y = 0, i = 0;
  while (i < g.length) {
    final int cmd = g[i] & 7;
    final int count = g[i] >> 3;
    i++;
    if (cmd == 7) continue;
    for (int c = 0; c < count && i + 1 < g.length; c++) {
      x += (g[i] >> 1) ^ -(g[i] & 1);
      y += (g[i + 1] >> 1) ^ -(g[i + 1] & 1);
      i += 2;
      if (cmd == 1) {
        if (cur.length >= 2) lines.add(cur);
        cur = <(int, int)>[(x, y)];
      } else {
        cur.add((x, y));
      }
    }
  }
  if (cur.length >= 2) lines.add(cur);
  return lines;
}

class _Reader {
  _Reader(this._b);
  final Uint8List _b;
  int _p = 0;
  bool get done => _p >= _b.length;

  int varint() {
    int shift = 0, v = 0;
    while (true) {
      if (_p >= _b.length) throw const FormatException('MVT cut cut');
      final int b = _b[_p++];
      v |= (b & 0x7F) << shift;
      if (b & 0x80 == 0) return v;
      shift += 7;
      if (shift > 63) throw const FormatException('MVT varint qua dai');
    }
  }

  Uint8List bytes() {
    final int n = varint();
    if (n < 0 || _p + n > _b.length) throw const FormatException('MVT sai do dai');
    final Uint8List s = Uint8List.sublistView(_b, _p, _p + n);
    _p += n;
    return s;
  }

  List<int> packedVarints() {
    final List<int> o = <int>[];
    while (!done) {
      o.add(varint());
    }
    return o;
  }

  void skip(int wire) {
    switch (wire) {
      case 0:
        varint();
      case 1:
        _p += 8;
      case 2:
        bytes();
      case 5:
        _p += 4;
      default:
        throw const FormatException('MVT wire type la');
    }
  }
}

/// Ten duong gan nhat (trong [maxDist] don vi tile, mac dinh ~45 m o zoom 14) hoac null.
String? nearestStreetName(List<NamedLine> lines, int px, int py, {int maxDist = 80}) {
  String? best;
  double bestD = maxDist.toDouble() + 1;
  for (final NamedLine l in lines) {
    for (int i = 0; i + 1 < l.points.length; i++) {
      final double d = _segDist(px, py, l.points[i], l.points[i + 1]);
      if (d < bestD) {
        bestD = d;
        best = l.name;
      }
    }
  }
  return best;
}

double _segDist(int px, int py, (int, int) a, (int, int) b) {
  final double dx = (b.$1 - a.$1).toDouble(), dy = (b.$2 - a.$2).toDouble();
  final double len2 = dx * dx + dy * dy;
  double t = len2 == 0 ? 0 : ((px - a.$1) * dx + (py - a.$2) * dy) / len2;
  t = t.clamp(0.0, 1.0);
  final double cx = a.$1 + t * dx, cy = a.$2 + t * dy;
  return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
}

/// Toa do tile Web Mercator (chi de hien thi ban do, khong dung cho tinh cuoc).
(int x, int y, int px, int py) tileOf(int latE7, int lngE7, int z, {int extent = 4096}) {
  final double lat = latE7 / 1e7, lng = lngE7 / 1e7;
  final double n = (1 << z).toDouble();
  final double xf = (lng + 180.0) / 360.0 * n;
  final double latRad = lat * math.pi / 180.0;
  final double yf = (1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) / 2.0 * n;
  final int x = xf.floor(), y = yf.floor();
  return (x, y, ((xf - x) * extent).round(), ((yf - y) * extent).round());
}

String? _cacheKey;
List<NamedLine>? _cacheLines;

/// Ten duong tai vi tri, doc truc tiep tu PMTiles (khong can ve ban do).
Future<String?> streetNameFromReader(PmTilesReader r, int latE7, int lngE7) async {
  if (r.header.tileType != 1) return null;
  final int z = math.min(r.header.maxZoom, 14);
  final (int x, int y, int px, int py) = tileOf(latE7, lngE7, z);
  final String key = '${identityHashCode(r)}/$z/$x/$y';
  List<NamedLine>? lines = _cacheKey == key ? _cacheLines : null;
  if (lines == null) {
    final Uint8List? raw = await r.getTile(z, x, y);
    if (raw == null) return null;
    final Uint8List tile = r.header.tileCompression == 2 ? Uint8List.fromList(gzip.decode(raw)) : raw;
    lines = decodeNamedLines(tile);
    _cacheKey = key;
    _cacheLines = lines;
  }
  return nearestStreetName(lines, px, py);
}

/// Mot doi tuong MVT: kieu hinh hoc (1 diem, 2 duong, 3 vung), thuoc tinh va cac phan hinh hoc.
class MvtFeature {
  MvtFeature(this.type, this.props, this.parts);
  final int type;
  final Map<String, String> props;
  final List<List<(int, int)>> parts;
}

/// Giai ma moi doi tuong cua lop [layerName] (thuoc tinh dang chuoi; so duoc doi sang chuoi).
List<MvtFeature> decodeFeatures(Uint8List tile, String layerName) {
  final List<MvtFeature> out = <MvtFeature>[];
  final _Reader t = _Reader(tile);
  while (!t.done) {
    final int tag = t.varint();
    if (tag >> 3 == 3 && tag & 7 == 2) {
      _decodeFeatureLayer(t.bytes(), layerName, out);
    } else {
      t.skip(tag & 7);
    }
  }
  return out;
}

void _decodeFeatureLayer(Uint8List data, String wanted, List<MvtFeature> out) {
  final _Reader r = _Reader(data);
  String name = '';
  final List<String> keys = <String>[];
  final List<String?> values = <String?>[];
  final List<Uint8List> features = <Uint8List>[];
  while (!r.done) {
    final int tag = r.varint();
    final int f = tag >> 3;
    final int w = tag & 7;
    if (f == 1 && w == 2) {
      name = utf8.decode(r.bytes());
    } else if (f == 2 && w == 2) {
      features.add(r.bytes());
    } else if (f == 3 && w == 2) {
      keys.add(utf8.decode(r.bytes()));
    } else if (f == 4 && w == 2) {
      values.add(_anyValue(r.bytes()));
    } else {
      r.skip(w);
    }
  }
  if (name != wanted) return;
  for (final Uint8List fe in features) {
    final _Reader fr = _Reader(fe);
    List<int> tags = <int>[];
    int type = 0;
    Uint8List geom = Uint8List(0);
    while (!fr.done) {
      final int tag = fr.varint();
      final int f = tag >> 3;
      final int w = tag & 7;
      if (f == 2 && w == 2) {
        tags = _Reader(fr.bytes()).packedVarints();
      } else if (f == 3 && w == 0) {
        type = fr.varint();
      } else if (f == 4 && w == 2) {
        geom = fr.bytes();
      } else {
        fr.skip(w);
      }
    }
    final Map<String, String> props = <String, String>{};
    for (int i = 0; i + 1 < tags.length; i += 2) {
      final int k = tags[i], v = tags[i + 1];
      if (k < keys.length && v < values.length && values[v] != null) props[keys[k]] = values[v]!;
    }
    out.add(MvtFeature(type, props, _decodeParts(geom)));
  }
}

/// Gia tri MVT -> chuoi: string(1), int(4), uint(5), sint(6), bool(7).
String? _anyValue(Uint8List data) {
  final _Reader r = _Reader(data);
  while (!r.done) {
    final int tag = r.varint();
    final int f = tag >> 3;
    final int w = tag & 7;
    if (f == 1 && w == 2) return utf8.decode(r.bytes());
    if ((f == 4 || f == 5) && w == 0) return r.varint().toString();
    if (f == 6 && w == 0) {
      final int z = r.varint();
      return ((z >> 1) ^ -(z & 1)).toString();
    }
    if (f == 7 && w == 0) return r.varint() == 0 ? 'false' : 'true';
    r.skip(w);
  }
  return null;
}

/// Cac phan hinh hoc (giu ca phan 1 diem).
List<List<(int, int)>> _decodeParts(Uint8List geom) {
  final List<int> g = _Reader(geom).packedVarints();
  final List<List<(int, int)>> parts = <List<(int, int)>>[];
  List<(int, int)> cur = <(int, int)>[];
  int x = 0, y = 0, i = 0;
  while (i < g.length) {
    final int cmd = g[i] & 7;
    final int count = g[i] >> 3;
    i++;
    if (cmd == 7) continue;
    for (int c = 0; c < count && i + 1 < g.length; c++) {
      x += (g[i] >> 1) ^ -(g[i] & 1);
      y += (g[i + 1] >> 1) ^ -(g[i + 1] & 1);
      i += 2;
      if (cmd == 1) {
        if (cur.isNotEmpty) parts.add(cur);
        cur = <(int, int)>[(x, y)];
      } else {
        cur.add((x, y));
      }
    }
  }
  if (cur.isNotEmpty) parts.add(cur);
  return parts;
}

/// Khoang cach (don vi tile) tu diem toi doan thang.
double segmentDistance(int px, int py, (int, int) a, (int, int) b) => _segDist(px, py, a, b);
