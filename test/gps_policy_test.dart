import 'package:flutter_test/flutter_test.dart';
import 'package:ttx_taximeter_pro/core/gps_policy.dart';

import 'test_support.dart';

const GpsPolicyConfig cfg = GpsPolicyConfig();

GpsSample s(
  int ts, {
  int lat = 0,
  int lng = 0,
  int acc = 5000,
  int speed = 10000,
  bool mock = false,
}) {
  return GpsSample(
    tsMs: ts,
    latE7: lat,
    lngE7: lng,
    accuracyMm: acc,
    speedMmps: speed,
    isMock: mock,
  );
}

GpsEvaluation step(GpsEvaluation? prev, GpsSample sample) {
  return GpsPolicy.evaluate(
    prev?.state ?? const GpsPolicyState(),
    sample,
    cfg,
  );
}

void main() {
  test('G1: toa do ngoai mien / ts khong tang -> REJECT', () {
    final GpsEvaluation bad = step(null, s(1000, lat: 910000000));
    expect(bad.decision, GpsDecision.rejected);
    expect(bad.rejectReason, 'SANITY_COORD');

    final GpsEvaluation ok = step(null, s(1000));
    expect(ok.decision, GpsDecision.accepted);
    final GpsEvaluation sameTs = step(ok, s(1000));
    expect(sameTs.decision, GpsDecision.rejected);
    expect(sameTs.rejectReason, 'SANITY_TS');
    final GpsEvaluation olderTs = step(ok, s(900));
    expect(olderTs.decision, GpsDecision.rejected);
  });

  test('G2: isMock -> ACCEPT + co SUSPICIOUS', () {
    final GpsEvaluation e = step(null, s(1000, mock: true));
    expect(e.decision, GpsDecision.accepted);
    expect(e.suspicious, isTrue);
    expect(step(null, s(1000)).suspicious, isFalse);
  });

  test('G3: accuracy thich ung 20 m -> 35 m -> PAUSED', () {
    // Moi bat dau: nguong 20 m.
    expect(step(null, s(0, acc: 25000)).decision, GpsDecision.rejected);

    final GpsEvaluation first = step(null, s(0));
    // Mat GPS 5 s: van nguong 20 m.
    final GpsEvaluation shortGap =
        step(first, s(5000, lat: latE7ForMeters(50), acc: 25000));
    expect(shortGap.decision, GpsDecision.rejected);
    expect(shortGap.rejectReason, 'ACCURACY');

    // Mat GPS 15 s: noi len 35 m -> chap nhan 25 m.
    final GpsEvaluation relaxed =
        step(first, s(15000, lat: latE7ForMeters(100), acc: 25000));
    expect(relaxed.decision, GpsDecision.accepted);

    // Mat GPS 60 s va van > 35 m -> PAUSED.
    final GpsEvaluation paused = step(first, s(60000, acc: 40000));
    expect(paused.decision, GpsDecision.paused);
  });

  test('G4: teleport (dt >= 0.5 s, v > max) -> REJECT', () {
    final GpsEvaluation first = step(null, s(0));
    final GpsEvaluation e = step(first, s(1000, lat: latE7ForMeters(1000)));
    expect(e.decision, GpsDecision.rejected);
    expect(e.rejectReason, 'TELEPORT');
  });

  test('G5: dt < 0.5 s -> bo qua teleport gate', () {
    final GpsEvaluation first = step(null, s(0));
    final GpsEvaluation e = step(first, s(300, lat: latE7ForMeters(1000)));
    expect(e.decision, GpsDecision.accepted);
  });

  test('G6: anchor drift: dung yen + accuracy xau -> REJECT', () {
    final GpsEvaluation first = step(null, s(0));
    final GpsEvaluation drift = step(first, s(2000, acc: 10000, speed: 500));
    expect(drift.decision, GpsDecision.rejected);
    expect(drift.rejectReason, 'ANCHOR_DRIFT');

    // Di chuyen that (toc do cao) -> chap nhan.
    final GpsEvaluation moving = step(
      first,
      s(2000, lat: latE7ForMeters(20), acc: 10000, speed: 8000),
    );
    expect(moving.decision, GpsDecision.accepted);

    // Accuracy tot (<= 8 m) -> khong bi anchor guard.
    final GpsEvaluation good = step(first, s(2000, acc: 5000, speed: 500));
    expect(good.decision, GpsDecision.accepted);
  });

  test('G7: lam muot cua so 3 mau, trong so 1/accuracy^2', () {
    // Cung accuracy: trung binh cua so.
    GpsEvaluation e = step(null, s(0, lat: 0));
    e = step(e, s(1000, lat: 30));
    e = step(e, s(2000, lat: 60));
    expect(e.decision, GpsDecision.accepted);
    expect(e.smoothedLatE7, 30);

    // Khac accuracy: w(5 m) = 4 x w(10 m) -> (0*4 + 100*1) / 5 = 20.
    GpsEvaluation w = step(null, s(0, lat: 0, acc: 5000));
    w = step(w, s(1000, lat: 100, acc: 10000));
    expect(w.decision, GpsDecision.accepted);
    expect(w.smoothedLatE7, 20);
    expect(w.smoothedLngE7, 0);

    // Cua so chi giu 3 mau.
    GpsEvaluation c = step(null, s(0, lat: 1000));
    c = step(c, s(1000, lat: 0));
    c = step(c, s(2000, lat: 0));
    c = step(c, s(3000, lat: 0));
    expect(c.state.window.length, 3);
    expect(c.smoothedLatE7, 0);
  });

  test('G8: replay cung chuoi diem hai lan -> quyet dinh giong het', () {
    final List<GpsSample> track = <GpsSample>[
      s(0),
      s(1000, lat: 90),
      s(1500, lat: 1000000), // teleport
      s(2000, lat: 180, acc: 30000), // accuracy xau
      s(3000, lat: 270, acc: 9000, speed: 400), // anchor drift
      s(2500), // ts lui
      s(4000, lat: 360, mock: true),
    ];

    List<String> run() {
      final List<String> out = <String>[];
      GpsPolicyState state = const GpsPolicyState();
      for (final GpsSample x in track) {
        final GpsEvaluation e = GpsPolicy.evaluate(state, x, cfg);
        state = e.state;
        out.add('${e.decision.name}|${e.rejectReason}|${e.suspicious}|'
            '${e.smoothedLatE7}|${e.smoothedLngE7}');
      }
      return out;
    }

    final List<String> a = run();
    final List<String> b = run();
    expect(a, equals(b));
    expect(a.length, track.length);
  });
}
