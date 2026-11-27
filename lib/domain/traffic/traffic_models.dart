import 'dart:convert';
import 'dart:typed_data';

import '../../core/geo.dart';

/// Thu tu khop type_index cua du lieu nguon (xem tool/convert_traffic_data.py).
enum SignKind {
  builtUpEnd,
  builtUpStart,
  maxSpeed,
  noOvertaking,
  p133,
  restArea,
  speedCamera,
  streetCamera,
  tollBooth,
  tunnel,

  /// Bien khac trong danh muc QCVN (xem TrafficSign.code); khong co trong signs.bin.
  other,
}

class TrafficSign {
  const TrafficSign({
    required this.latE7,
    required this.lngE7,
    required this.kind,
    required this.dirDeg,
    required this.speedKmh,
    this.code,
  });

  /// Ma bien QCVN (vi du P.103a) cho kind = other.
  final String? code;

  final int latE7;
  final int lngE7;
  final SignKind kind;

  /// Huong xe ma bien ap dung (do, 0 = Bac, theo chieu kim dong ho); -1 neu khong co.
  final int dirDeg;

  /// Toc do toi da km/h (chi cho maxSpeed); -1 neu khong co.
  final int speedKmh;
}

class NearbySign {
  const NearbySign(this.sign, this.distanceM, this.bearingDeg);
  final TrafficSign sign;
  final int distanceM;

  /// Phuong vi tu vi tri hien tai toi bien.
  final int bearingDeg;
}

/// atan(num/den) * 10 do, 0 <= num <= den, sai so < 0,3 do.
int _atanDegX10(int num, int den) {
  final int t = num * 1000 ~/ den;
  return t * (450000 + 156400 * (1000 - t) ~/ 1000) ~/ 1000000;
}

/// Phuong vi (do, 0..359, 0 = Bac) cua vector (dxEast, dyNorth). So nguyen.
int bearingDegrees(int dxEast, int dyNorth) {
  if (dxEast == 0 && dyNorth == 0) return 0;
  final int ax = dxEast < 0 ? -dxEast : dxEast;
  final int ay = dyNorth < 0 ? -dyNorth : dyNorth;
  final int a = ay >= ax ? _atanDegX10(ax, ay) : 900 - _atanDegX10(ay, ax);
  int x10;
  if (dxEast >= 0 && dyNorth >= 0) {
    x10 = a;
  } else if (dxEast >= 0) {
    x10 = 1800 - a;
  } else if (dyNorth < 0) {
    x10 = 1800 + a;
  } else {
    x10 = 3600 - a;
  }
  return ((x10 + 5) ~/ 10) % 360;
}

/// Phuong vi tu diem 1 den diem 2 (E7).
int bearingBetweenE7(int lat1E7, int lng1E7, int lat2E7, int lng2E7) {
  final int cos = cosPpmForLatE7(lat1E7);
  final int dx = (lng2E7 - lng1E7) * cos ~/ 1000000;
  final int dy = lat2E7 - lat1E7;
  return bearingDegrees(dx, dy);
}

/// Chenh lech goc nho nhat giua hai huong (0..180).
int angleDiffDeg(int a, int b) {
  int d = (a - b) % 360;
  if (d < 0) d += 360;
  return d > 180 ? 360 - d : d;
}

/// Chi muc khong gian (luoi ~1,1 km) cho ~71k bien bao.
class SignIndex {
  SignIndex(this.signs) {
    for (int i = 0; i < signs.length; i++) {
      _grid.putIfAbsent(_key(signs[i].latE7, signs[i].lngE7), () => <int>[]).add(i);
    }
  }

  /// Doc signs.bin ('TSG1' + u32 + n * <i4 lat, i4 lng, u1 cat, u2 dir, u2 value>).
  factory SignIndex.fromBytes(Uint8List bytes) {
    final ByteData b = ByteData.sublistView(bytes);
    if (bytes.length < 8 || utf8.decode(bytes.sublist(0, 4)) != 'TSG1') {
      throw const FormatException('signs.bin sai dinh dang');
    }
    final int n = b.getUint32(4, Endian.little);
    if (bytes.length != 8 + n * 13) {
      throw const FormatException('signs.bin sai kich thuoc');
    }
    final List<TrafficSign> list = <TrafficSign>[];
    for (int i = 0; i < n; i++) {
      final int o = 8 + i * 13;
      final int cat = b.getUint8(o + 8);
      final int dir = b.getUint16(o + 9, Endian.little);
      final int val = b.getUint16(o + 11, Endian.little);
      if (cat >= SignKind.other.index) {
        throw FormatException('Loai bien khong hop le: $cat');
      }
      list.add(TrafficSign(
        latE7: b.getInt32(o, Endian.little),
        lngE7: b.getInt32(o + 4, Endian.little),
        kind: SignKind.values[cat],
        dirDeg: dir == 65535 ? -1 : dir,
        speedKmh: val == 65535 ? -1 : val,
      ));
    }
    return SignIndex(list);
  }

  static const int _cell = 100000; // 0,01 do ~ 1,1 km

  final List<TrafficSign> signs;
  final Map<int, List<int>> _grid = <int, List<int>>{};

  static int _cellOf(int v) => v >= 0 ? v ~/ _cell : -((-v + _cell - 1) ~/ _cell);
  static int _key(int latE7, int lngE7) => _cellOf(latE7) * 1000003 + _cellOf(lngE7);

  /// Cac bien trong ban kinh [radiusM] (m), gan nhat truoc.
  List<NearbySign> nearby(int latE7, int lngE7, int radiusM) {
    final int span = radiusM ~/ 1000 + 1;
    final int cy = _cellOf(latE7);
    final int cx = _cellOf(lngE7);
    final int radiusMm = radiusM * 1000;
    final List<NearbySign> out = <NearbySign>[];
    for (int dy = -span; dy <= span; dy++) {
      for (int dx = -span; dx <= span; dx++) {
        final List<int>? ids = _grid[(cy + dy) * 1000003 + (cx + dx)];
        if (ids == null) continue;
        for (final int i in ids) {
          final TrafficSign s = signs[i];
          final int mm = distanceMm(latE7, lngE7, s.latE7, s.lngE7);
          if (mm <= radiusMm) {
            out.add(NearbySign(s, mm ~/ 1000,
                bearingBetweenE7(latE7, lngE7, s.latE7, s.lngE7)));
          }
        }
      }
    }
    out.sort((NearbySign a, NearbySign b) => a.distanceM.compareTo(b.distanceM));
    return out;
  }
}

/// Bien tren huong di: ap dung cho huong xe (lech <= 60 do) va nam phia truoc
/// (lech <= 90 do) neu biet huong di [headingDeg]; bien khong co huong ap dung moi phia.
List<NearbySign> signsAhead(List<NearbySign> near, int headingDeg) {
  return near.where((NearbySign n) {
    final bool dirOk = n.sign.dirDeg < 0 || angleDiffDeg(n.sign.dirDeg, headingDeg) <= 60;
    final bool ahead = angleDiffDeg(n.bearingDeg, headingDeg) <= 90;
    return dirOk && ahead;
  }).toList();
}

/// Gioi han toc do dang ap dung: bien maxSpeed gan nhat cung huong di trong
/// [radiusM], gom ca bien vua di qua (bien ap dung tu cho dat bien).
NearbySign? currentSpeedLimit(List<NearbySign> near, int headingDeg, {int radiusM = 300}) {
  for (final NearbySign n in near) {
    if (n.distanceM > radiusM) break;
    if (n.sign.kind != SignKind.maxSpeed || n.sign.speedKmh <= 0) continue;
    if (n.sign.dirDeg >= 0 && angleDiffDeg(n.sign.dirDeg, headingDeg) > 60) continue;
    return n;
  }
  return null;
}

/// Theo doi huong di tu cac vi tri lien tiep (>= 5 m moi cap nhat).
class HeadingTracker {
  int _lat = 0, _lng = 0;
  bool _has = false;
  int headingDeg = -1;

  void update(int latE7, int lngE7) {
    if (!_has) {
      _lat = latE7;
      _lng = lngE7;
      _has = true;
      return;
    }
    if (distanceMm(_lat, _lng, latE7, lngE7) >= 5000) {
      headingDeg = bearingBetweenE7(_lat, _lng, latE7, lngE7);
      _lat = latE7;
      _lng = lngE7;
    }
  }
}

class Poi {
  const Poi(this.latE7, this.lngE7, this.kind, this.name);
  final int latE7;
  final int lngE7;
  final String kind; // fuel | charging_station | charging_station_motorcycle
  final String name;
}

List<Poi> parsePoiJson(String jsonText) {
  final Map<String, dynamic> m = jsonDecode(jsonText) as Map<String, dynamic>;
  final List<dynamic> kinds = m['kinds'] as List<dynamic>;
  return (m['poi'] as List<dynamic>).map((dynamic e) {
    final List<dynamic> r = e as List<dynamic>;
    return Poi(r[0] as int, r[1] as int, kinds[r[2] as int] as String, r[3] as String);
  }).toList();
}

/// Bien can ve tren man hinh ban do: theo tam camera va muc zoom (toi da [cap]).
/// Zoom thap -> khong ve (qua day dac).
List<NearbySign> viewportSigns(SignIndex idx, int latE7, int lngE7, double zoom, {int cap = 800}) {
  if (zoom < 11) return const <NearbySign>[];
  final int radius = zoom >= 15 ? 1500 : (zoom >= 14 ? 2500 : 4000);
  final List<NearbySign> n = idx.nearby(latE7, lngE7, radius);
  return n.length > cap ? n.sublist(0, cap) : n;
}

/// POI (tram xang/sac) trong khung nhin, gan tam truoc, toi da [cap].
List<Poi> viewportPoi(List<Poi> all, int latE7, int lngE7, double zoom, {int cap = 600}) {
  if (zoom < 10) return const <Poi>[];
  final int radiusMm = (zoom >= 14 ? 3000 : 8000) * 1000;
  final List<MapEntry<int, Poi>> hit = <MapEntry<int, Poi>>[];
  for (final Poi p in all) {
    final int d = distanceMm(latE7, lngE7, p.latE7, p.lngE7);
    if (d <= radiusMm) hit.add(MapEntry<int, Poi>(d, p));
  }
  hit.sort((MapEntry<int, Poi> a, MapEntry<int, Poi> b) => a.key.compareTo(b.key));
  return hit.take(cap).map((MapEntry<int, Poi> e) => e.value).toList();
}

class NearestPoi {
  const NearestPoi(this.poi, this.distanceM);
  final Poi poi;
  final int distanceM;
}

/// POI gan nhat thuoc [kinds] trong [maxM] m (khong co -> null).
NearestPoi? nearestPoi(List<Poi> all, int latE7, int lngE7, Set<String> kinds, {int maxM = 30000}) {
  Poi? best;
  int bestMm = maxM * 1000 + 1;
  for (final Poi p in all) {
    if (!kinds.contains(p.kind)) continue;
    final int d = distanceMm(latE7, lngE7, p.latE7, p.lngE7);
    if (d < bestMm) {
      bestMm = d;
      best = p;
    }
  }
  return best == null ? null : NearestPoi(best, bestMm ~/ 1000);
}

/// Ban dem theo gio Viet Nam (UTC+7): 18:00-05:59.
bool isNightVn(int tsMs) {
  final int hour = ((tsMs + 7 * 3600000) ~/ 3600000) % 24;
  return hour >= 18 || hour < 6;
}


/// Bien phia truoc xe trong [radiusM] (mac dinh 2 km), gan nhat truoc. Khong biet huong -> moi phia.
List<NearbySign> aheadSigns(SignIndex idx, int latE7, int lngE7, int headingDeg,
    {int radiusM = 2000, int cap = 400}) {
  final List<NearbySign> near = idx.nearby(latE7, lngE7, radiusM);
  final List<NearbySign> l = headingDeg < 0 ? near : signsAhead(near, headingDeg);
  return l.length > cap ? l.sublist(0, cap) : l;
}

/// POI (tram xang/sac) phia truoc xe trong [radiusM], gan nhat truoc.
List<Poi> poiAhead(List<Poi> all, int latE7, int lngE7, int headingDeg, {int radiusM = 2000, int cap = 200}) {
  final int radiusMm = radiusM * 1000;
  final List<MapEntry<int, Poi>> hit = <MapEntry<int, Poi>>[];
  for (final Poi p in all) {
    final int d = distanceMm(latE7, lngE7, p.latE7, p.lngE7);
    if (d > radiusMm) continue;
    if (headingDeg >= 0 && d > 30000) {
      final int b = bearingBetweenE7(latE7, lngE7, p.latE7, p.lngE7);
      if (angleDiffDeg(b, headingDeg) > 100) continue;
    }
    hit.add(MapEntry<int, Poi>(d, p));
  }
  hit.sort((MapEntry<int, Poi> a, MapEntry<int, Poi> b) => a.key.compareTo(b.key));
  return hit.take(cap).map((MapEntry<int, Poi> e) => e.value).toList();
}

/// Can nap lai bien/POI phia truoc khi xe da di >= [minMoveM] m hoac doi huong >= [minTurnDeg] do.
bool needsAheadRefresh({
  required bool hasLast,
  required int lastLatE7,
  required int lastLngE7,
  required int lastHeadingDeg,
  required int latE7,
  required int lngE7,
  required int headingDeg,
  int minMoveM = 40,
  int minTurnDeg = 20,
}) {
  if (!hasLast) return true;
  if (distanceMm(lastLatE7, lastLngE7, latE7, lngE7) >= minMoveM * 1000) return true;
  if (headingDeg >= 0 && (lastHeadingDeg < 0 || angleDiffDeg(lastHeadingDeg, headingDeg) >= minTurnDeg)) return true;
  return false;
}
