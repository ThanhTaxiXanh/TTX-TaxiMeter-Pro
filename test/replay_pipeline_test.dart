import 'package:flutter_test/flutter_test.dart';
import 'package:ttx_taximeter_pro/core/geo.dart';
import 'package:ttx_taximeter_pro/core/gps_policy.dart';
import 'package:ttx_taximeter_pro/core/taximeter_engine.dart';

import 'test_support.dart';

/// Chuoi diem tong hop co dinh (khong ngau nhien): di thang, dung cho,
/// roi di tiep, kem vai diem nhieu.
List<GpsSample> syntheticTrack() {
  final List<GpsSample> out = <GpsSample>[];
  int ts = 0;
  int lat = 0;
  for (int i = 0; i < 300; i++) {
    ts += 1000;
    final bool stopped = i >= 100 && i < 160;
    if (!stopped) {
      lat += 120; // ~1.3 m / s ... du de khac 0
    }
    final bool noisy = i % 37 == 0 && i > 0;
    out.add(GpsSample(
      tsMs: ts,
      latE7: noisy ? lat + 4000 : lat,
      lngE7: i * 3,
      accuracyMm: noisy ? 30000 : 4000 + (i % 5) * 300,
      speedMmps: stopped ? 100 : 9000,
      isMock: i == 250,
    ));
  }
  return out;
}

String runPipeline(List<GpsSample> track) {
  GpsPolicyState state = const GpsPolicyState();
  final List<AcceptedPoint> accepted = <AcceptedPoint>[];
  for (final GpsSample s in track) {
    final GpsEvaluation e = GpsPolicy.evaluate(state, s, const GpsPolicyConfig());
    state = e.state;
    if (e.decision == GpsDecision.accepted) {
      accepted.add(AcceptedPoint(
        tsMs: s.tsMs,
        latE7: e.smoothedLatE7!,
        lngE7: e.smoothedLngE7!,
        speedMmps: s.speedMmps,
      ));
    }
  }
  final FareResult r = compute(accepted, fixtureConfig());
  return '${accepted.length}|$r';
}

void main() {
  test('Replay pipeline GpsPolicy -> Engine: hai lan chay khop tung byte', () {
    final String a = runPipeline(syntheticTrack());
    final String b = runPipeline(syntheticTrack());
    expect(a, equals(b));
  });

  test('geo: isqrt va khoang cach doi xung', () {
    expect(isqrt(0), 0);
    expect(isqrt(15), 3);
    expect(isqrt(16), 4);
    expect(isqrt(1000000000000000000), 1000000000);
    expect(distanceMm(0, 0, 1000, 500), distanceMm(1000, 500, 0, 0));
    // 1 do vi do ~ 111195 m.
    expect(distanceMm(0, 0, 10000000, 0) ~/ 1000, 111195);
  });
}
