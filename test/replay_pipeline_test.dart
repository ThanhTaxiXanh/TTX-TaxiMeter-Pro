import 'package:flutter_test/flutter_test.dart';
import 'package:ttx/core/geo.dart';
import 'package:ttx/core/taximeter_engine.dart';
import 'package:ttx/domain/models/gps_sample.dart';

import 'test_support.dart';

/// Chuoi diem tong hop co dinh (khong ngau nhien): di thang, dung cho,
/// roi di tiep, kem vai diem nhieu.
List<GpsSample> syntheticTrack() {
  final List<GpsSample> out = <GpsSample>[];
  int lat = 0;
  for (int i = 0; i < 300; i++) {
    final bool stopped = i >= 100 && i < 160;
    if (!stopped) {
      lat += 120;
    }
    final bool noisy = i % 37 == 0 && i > 0;
    out.add(GpsSample(
      tsMs: baseTsMs + (i + 1) * 1000,
      latE7: noisy ? lat + 4000 : lat,
      lngE7: i * 3,
      accuracyMm: noisy ? 30000 : 4000 + (i % 5) * 300,
      speedMmps: stopped ? 100 : 9000,
      isMock: i == 250,
    ));
  }
  return out;
}

void main() {
  test('Replay pipeline GpsPolicy -> Engine: hai lan chay khop tung byte', () {
    final FareResult a = compute(syntheticTrack(), fixtureConfig());
    final FareResult b = compute(syntheticTrack(), fixtureConfig());
    expect(a, equals(b));
    expect(a.toString(), b.toString());
    expect(a.rejectedCount, greaterThan(0));
    expect(a.waitingSec, greaterThan(0));
    expect(a.suspiciousCount, 1);
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
