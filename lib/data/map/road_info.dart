import 'dart:io' show gzip;
import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/traffic/speed_limit.dart';
import 'pmtiles_reader.dart';
import 'street_name.dart';

const Set<String> _drivable = <String>{
  'motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'minor', 'service', 'track',
  'busway', 'raceway', 'motorway_construction', 'trunk_construction', 'primary_construction',
};

class _RoadTile {
  _RoadTile(this.roads, this.named, this.buildings);
  final List<MvtFeature> roads; // transportation (duong)
  final List<NamedLine> named; // transportation_name
  final List<(int, int)> buildings; // diem dau moi toa nha
}

String? _key;
_RoadTile? _cache;

/// So toa nha toi thieu quanh vi tri (hop ~340 m) de coi la khu vuc dong dan cu.
const int urbanBuildingThreshold = 12;

/// Thong tin duong tai vi tri doc tu PMTiles (offline); null neu khong co duong gan do.
/// [preferKey] giu tuyen cu neu no gan ngang tuyen gan nhat (tranh nhay khi GPS lech).
Future<RoadInfo?> roadInfoFromReader(PmTilesReader r, int latE7, int lngE7, {String? preferKey}) async {
  if (r.header.tileType != 1) return null;
  final int z = math.min(r.header.maxZoom, 14);
  final (int x, int y, int px, int py) = tileOf(latE7, lngE7, z);
  final String k = '${identityHashCode(r)}/$z/$x/$y';
  _RoadTile? t = _key == k ? _cache : null;
  if (t == null) {
    final Uint8List? raw = await r.getTile(z, x, y);
    if (raw == null) return null;
    final Uint8List tile = r.header.tileCompression == 2 ? Uint8List.fromList(gzip.decode(raw)) : raw;
    final List<MvtFeature> roads = decodeFeatures(tile, 'transportation')
        .where((MvtFeature f) => f.type == 2 && _drivable.contains(f.props['class']))
        .toList();
    final List<(int, int)> b = <(int, int)>[
      for (final MvtFeature f in decodeFeatures(tile, 'building'))
        if (f.parts.isNotEmpty && f.parts.first.isNotEmpty) f.parts.first.first,
    ];
    t = _RoadTile(roads, decodeNamedLines(tile), b);
    _key = k;
    _cache = t;
  }
  return roadInfoAt(t.roads, t.named, t.buildings, px, py, preferKey: preferKey);
}

/// Phan thuan tuy de kiem thu: chon duong gan nhat, ten, co oneway/ramp, mat do nha.
RoadInfo? roadInfoAt(
  List<MvtFeature> roads,
  List<NamedLine> named,
  List<(int, int)> buildings,
  int px,
  int py, {
  String? preferKey,
  int maxDist = 60,
}) {
  MvtFeature? best;
  double bestD = maxDist + 1.0;
  final Map<MvtFeature, double> dist = <MvtFeature, double>{};
  for (final MvtFeature f in roads) {
    double d = double.infinity;
    for (final List<(int, int)> part in f.parts) {
      for (int i = 0; i + 1 < part.length; i++) {
        d = math.min(d, segmentDistance(px, py, part[i], part[i + 1]));
      }
    }
    dist[f] = d;
    if (d < bestD) {
      bestD = d;
      best = f;
    }
  }
  if (best == null) return null;
  final String? name = nearestStreetName(named, px, py, maxDist: 60);
  RoadInfo make(MvtFeature f, String n) => RoadInfo(
        cls: roadClassFromOmt(f.props['class'] ?? ''),
        name: n,
        oneway: f.props['oneway'] == '1',
        ramp: f.props['ramp'] == '1',
        expressway: f.props['expressway'] == '1',
        urbanHint: _isUrban(buildings, px, py),
      );
  final RoadInfo cand = make(best, name ?? '');
  if (preferKey != null && cand.key != preferKey) {
    // tuyen cu con gan ngang (<= 12 don vi ~ 7 m) thi giu nguyen
    for (final MapEntry<MvtFeature, double> e in dist.entries) {
      if (e.value <= bestD + 12) {
        final RoadInfo o = make(e.key, name ?? '');
        if (o.key == preferKey) return o;
      }
    }
  }
  return cand;
}

bool _isUrban(List<(int, int)> b, int px, int py) {
  int n = 0;
  for (final (int, int) p in b) {
    if ((p.$1 - px).abs() <= 300 && (p.$2 - py).abs() <= 300) {
      if (++n >= urbanBuildingThreshold) return true;
    }
  }
  return false;
}
