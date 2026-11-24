// Golden replay: 5 chuyen that (GPX -> CSV so nguyen) chay qua
// GpsPolicy -> TaximeterEngine, so khop byte-for-byte voi *.expected.json.
//
// Ket qua mong doi chi duoc cap nhat co chu dich (ghi ly do trong
// docs/CONTEXT_STATE.md). Tai lieu: .github/skills/taximeter-engine/SKILL.md.
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ttx_taximeter_pro/core/gps_policy.dart';
import 'package:ttx_taximeter_pro/core/taximeter_engine.dart';

import 'test_support.dart';

const List<String> slugs = <String>[
  'da_mai_20261122',
  'ngo388_nguyen_thi_luu_20261122',
  'xuong_giang_422_20261122',
  'than_canh_van_20261121',
  'tran_nguyen_han_20261124',
];

/// GPX khong co accuracy -> co dinh 5 m.
const int gpxAccuracyMm = 5000;

class Raw {
  const Raw(this.tsMs, this.latE7, this.lngE7, this.speedMmps);

  final int tsMs;
  final int latE7;
  final int lngE7;
  final int speedMmps;
}

List<Raw> loadCsv(String slug) {
  final List<String> lines = File('test/golden/$slug.csv').readAsLinesSync();
  final List<Raw> out = <Raw>[];
  for (final String line in lines.skip(1)) {
    if (line.isEmpty) continue;
    final List<int> v = line.split(',').map(int.parse).toList();
    out.add(Raw(v[0], v[1], v[2], v[3]));
  }
  return out;
}

/// Doi chieu doc lap (chi dung trong test): haversine tren tat ca diem tho.
int haversineRefM(List<Raw> raw) {
  const double r = 6371000;
  double total = 0;
  for (int i = 1; i < raw.length; i++) {
    final double la1 = raw[i - 1].latE7 / 1e7 * math.pi / 180;
    final double la2 = raw[i].latE7 / 1e7 * math.pi / 180;
    final double dLa = la2 - la1;
    final double dLo = (raw[i].lngE7 - raw[i - 1].lngE7) / 1e7 * math.pi / 180;
    final double a = math.pow(math.sin(dLa / 2), 2).toDouble() +
        math.cos(la1) * math.cos(la2) * math.pow(math.sin(dLo / 2), 2).toDouble();
    total += 2 * r * math.asin(math.sqrt(a));
  }
  return total.round();
}

class Outcome {
  const Outcome(this.json, this.distanceM);

  final String json;
  final int distanceM;
}

Outcome replay(String slug, List<Raw> raw) {
  GpsPolicyState state = const GpsPolicyState();
  final List<AcceptedPoint> accepted = <AcceptedPoint>[];
  final SplayTreeMap<String, int> reasons = SplayTreeMap<String, int>();
  int rejected = 0;
  int paused = 0;
  int suspicious = 0;
  for (final Raw p in raw) {
    final GpsEvaluation e = GpsPolicy.evaluate(
      state,
      GpsSample(
        tsMs: p.tsMs,
        latE7: p.latE7,
        lngE7: p.lngE7,
        accuracyMm: gpxAccuracyMm,
        speedMmps: p.speedMmps,
      ),
      const GpsPolicyConfig(),
    );
    state = e.state;
    if (e.suspicious) suspicious++;
    switch (e.decision) {
      case GpsDecision.accepted:
        accepted.add(AcceptedPoint(
          tsMs: p.tsMs,
          latE7: e.smoothedLatE7!,
          lngE7: e.smoothedLngE7!,
          speedMmps: p.speedMmps,
        ));
      case GpsDecision.rejected:
        rejected++;
        reasons.update(e.rejectReason!, (int v) => v + 1, ifAbsent: () => 1);
      case GpsDecision.paused:
        paused++;
        reasons.update(e.rejectReason!, (int v) => v + 1, ifAbsent: () => 1);
    }
  }
  final FareResult r = TaximeterEngine.compute(
    points: accepted,
    config: fixtureConfig(),
    configSha256: 'golden-fixture-v1',
    tripId: slug,
  );
  final Map<String, Object> out = <String, Object>{
    'slug': slug,
    'points': raw.length,
    'accepted': accepted.length,
    'rejected': rejected,
    'paused': paused,
    'suspicious': suspicious,
    'reasons': reasons,
    'distance_m': r.distanceM,
    'waiting_sec': r.waitingSec,
    'waiting_billable_sec': r.waitingBillableSec,
    'fare_total_vnd': r.fareTotalVnd,
    'fare_hash': r.fareHash,
  };
  return Outcome(jsonEncode(out), r.distanceM);
}

void main() {
  for (final String slug in slugs) {
    test('golden replay: $slug', () {
      final List<Raw> raw = loadCsv(slug);
      expect(raw.length, greaterThan(500));

      final Outcome a = replay(slug, raw);
      final Outcome b = replay(slug, raw);
      expect(a.json, equals(b.json), reason: 'replay hai lan phai y het');

      // Doi chieu doc lap: quang duong engine ~ haversine tren diem tho
      // (lam muot + equirectangular nen hoi ngan hon, khong dai hon).
      final int ref = haversineRefM(raw);
      expect(a.distanceM, lessThanOrEqualTo(ref * 1005 ~/ 1000));
      expect(a.distanceM, greaterThanOrEqualTo(ref * 98 ~/ 100));

      final File expected = File('test/golden/$slug.expected.json');
      expect(
        expected.existsSync(),
        isTrue,
        reason: 'thieu $slug.expected.json: golden phai duoc ghi lai co chu dich',
      );
      expect(a.json, equals(expected.readAsStringSync().trim()));
    });
  }
}
