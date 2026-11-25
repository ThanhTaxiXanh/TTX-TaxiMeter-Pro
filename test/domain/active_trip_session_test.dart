import 'package:flutter_test/flutter_test.dart';
import 'package:ttx/domain/models/gps_sample.dart';
import 'package:ttx/domain/trip/active_trip_session.dart';

import '../test_support.dart';

List<GpsSample> trip5km() {
  final List<GpsSample> out = <GpsSample>[];
  for (int i = 0; i <= 500; i++) {
    out.add(gs(i * 1000, latE7: latE7ForMeters(i * 10)));
  }
  return out;
}

ActiveTripSession newSession() => ActiveTripSession(
      tripId: 'trip-s1',
      startedAtMs: baseTsMs,
      config: fixtureConfig(roundingUnit: 1000),
      contexts: contextsAt(baseTsMs),
    );

void main() {
  test('chuyen moi: chi co cuoc mo cua', () {
    final ActiveTripSession s = newSession();
    expect(s.liveFare.fareTotal, 10000);
    expect(s.sampleCount, 0);
  });

  test('cuoc chot = engine.compute tren toan bo mau (replay)', () {
    final ActiveTripSession s = newSession();
    final List<GpsSample> pts = trip5km();
    for (final GpsSample p in pts) {
      s.addSample(p);
    }
    final fare = compute(pts, fixtureConfig(roundingUnit: 1000), tripId: 'trip-s1');
    expect(s.finalFare(), fare);
    expect(s.finalFare().fareTotal % 1000, 0);
  });

  test('cuoc hien thi trong chuyen khong vuot cuoc chot (floor)', () {
    final ActiveTripSession s = newSession();
    for (final GpsSample p in trip5km()) {
      s.addSample(p);
      expect(s.liveFare.fareTotal <= s.finalFare().fareTotal, isTrue);
    }
  });

  test('khoi phuc tu danh sach mau cho ket qua y het', () {
    final ActiveTripSession a = newSession();
    final List<GpsSample> pts = trip5km();
    for (final GpsSample p in pts) {
      a.addSample(p);
    }
    final ActiveTripSession b = ActiveTripSession(
      tripId: a.tripId,
      startedAtMs: a.startedAtMs,
      config: a.config,
      contexts: a.contexts,
      samples: a.samples,
    );
    expect(b.finalFare(), a.finalFare());
    expect(b.liveFare, a.liveFare);
  });
}
