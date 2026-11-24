import 'package:flutter_test/flutter_test.dart';
import 'package:ttx_taximeter_pro/core/gps_policy.dart';
import 'package:ttx_taximeter_pro/core/taximeter_engine.dart';

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

/// Chay mot chuoi mau tu trang thai rong, tra ve moi ket qua.
List<GpsEvaluation> run(List<GpsSample> samples) {
  final List<GpsEvaluation> out = <GpsEvaluation>[];
  GpsPolicyState state = const GpsPolicyState();
  for (final GpsSample x in samples) {
    final GpsEvaluation e = GpsPolicy.evaluate(state, x, cfg);
    state = e.state;
    out.add(e);
  }
  return out;
}

List<AcceptedPoint> acceptedPoints(
  List<GpsSample> samples,
  List<GpsEvaluation> evals,
) {
  final List<AcceptedPoint> pts = <AcceptedPoint>[];
  for (int i = 0; i < samples.length; i++) {
    if (evals[i].decision == GpsDecision.accepted) {
      pts.add(AcceptedPoint(
        tsMs: samples[i].tsMs,
        latE7: evals[i].smoothedLatE7!,
        lngE7: evals[i].smoothedLngE7!,
        speedMmps: samples[i].speedMmps,
      ));
    }
  }
  return pts;
}

// ---- Kich ban G1..G7 (dung chung cho G8 replay) ----

/// G1: dung yen 60 mau, drift +-8 m quanh mot diem.
List<GpsSample> g1Samples() {
  final int d = latE7ForMeters(8); // ~8 m (cos(0) = 1 nen lng tuong tu)
  final List<GpsSample> out = <GpsSample>[];
  for (int i = 0; i < 60; i++) {
    int lat = 0;
    int lng = 0;
    switch (i % 4) {
      case 1:
        lat = d;
      case 2:
        lng = d;
      case 3:
        lat = -d;
      default:
        lng = -d;
    }
    if (i == 0) {
      lat = 0;
      lng = 0;
    }
    out.add(s(i * 1000, lat: lat, lng: lng, acc: 12000, speed: 0));
  }
  return out;
}

/// G2: accuracy 50 m.
List<GpsSample> g2Samples() => <GpsSample>[
      s(0, acc: 50000),
      s(1000), // tot
      s(2000, acc: 50000), // xau sau khi co fix tot
    ];

/// G3: teleport 252 km/h (70 m trong 1 s), sau do di chuyen hop le.
List<GpsSample> g3Samples() => <GpsSample>[
      s(0),
      s(1000, lat: latE7ForMeters(70), speed: 70000), // 252 km/h -> reject
      s(2000, lat: latE7ForMeters(50), speed: 50000), // 50 m / 2 s tu diem nhan cuoi -> accept
    ];

/// G4: chay deu ~40 km/h (11.1 m moi giay), 60 mau.
List<GpsSample> g4Samples() => <GpsSample>[
      for (int i = 0; i < 60; i++) s(i * 1000, lat: i * 1000, speed: 11111),
    ];

/// G5: mock.
List<GpsSample> g5Samples() => <GpsSample>[
      s(0),
      s(1000, lat: 900, mock: true),
    ];

/// G6: mat GPS 45 s.
List<GpsSample> g6Samples() => <GpsSample>[
      s(0),
      s(25000, acc: 50000), // moi 25 s: chua PAUSED
      s(45000, acc: 50000), // 45 s: PAUSED
    ];

/// G7: timestamp giam.
List<GpsSample> g7Samples() => <GpsSample>[
      s(2000),
      s(1500, lat: 100), // lui -> reject
      s(2000, lat: 100), // bang -> reject
      s(3000, lat: 200), // tiep tuc binh thuong
    ];

void main() {
  test('G1: dung yen 60 mau drift +-8 m -> 0 m duoc chap nhan', () {
    final List<GpsSample> samples = g1Samples();
    final List<GpsEvaluation> evals = run(samples);
    expect(samples.length, 60);

    // Chi mau dau (anchor) duoc nhan; 59 mau drift con lai deu bi loai.
    final int accepted =
        evals.where((GpsEvaluation e) => e.decision == GpsDecision.accepted).length;
    expect(accepted, 1);
    for (int i = 1; i < evals.length; i++) {
      expect(evals[i].decision, GpsDecision.rejected, reason: 'mau $i');
      expect(evals[i].rejectReason, 'ANCHOR_DRIFT', reason: 'mau $i');
    }

    final FareResult r = compute(acceptedPoints(samples, evals), fixtureConfig());
    expect(r.distanceM, 0);
    expect(r.fareTotalVnd, 10000);
  });

  test('G2: accuracy 50 m -> reject', () {
    final List<GpsSample> samples = g2Samples();
    final List<GpsEvaluation> evals = run(samples);
    expect(evals[0].decision, GpsDecision.rejected);
    expect(evals[0].rejectReason, 'ACCURACY');
    expect(evals[1].decision, GpsDecision.accepted);
    expect(evals[2].decision, GpsDecision.rejected);
    expect(evals[2].rejectReason, 'ACCURACY');
  });

  test('G3: teleport 250 km/h -> reject', () {
    final List<GpsEvaluation> evals = run(g3Samples());
    expect(evals[0].decision, GpsDecision.accepted);
    expect(evals[1].decision, GpsDecision.rejected);
    expect(evals[1].rejectReason, 'TELEPORT');
    // Di chuyen hop le sau teleport -> nhan.
    expect(evals[2].decision, GpsDecision.accepted);
  });

  test('G4: chay 40 km/h deu -> tat ca accept', () {
    final List<GpsSample> samples = g4Samples();
    final List<GpsEvaluation> evals = run(samples);
    expect(
      evals.every((GpsEvaluation e) => e.decision == GpsDecision.accepted),
      isTrue,
    );
    final FareResult r = compute(acceptedPoints(samples, evals), fixtureConfig());
    // Duong that ~656 m; diem lam muot tre ~11 m.
    expect(r.distanceM, inInclusiveRange(600, 700));
  });

  test('G5: mock -> accept + co', () {
    final List<GpsEvaluation> evals = run(g5Samples());
    expect(evals[0].decision, GpsDecision.accepted);
    expect(evals[0].suspicious, isFalse);
    expect(evals[1].decision, GpsDecision.accepted);
    expect(evals[1].suspicious, isTrue);
  });

  test('G6: mat GPS 45 s -> chuyen PAUSED', () {
    final List<GpsEvaluation> evals = run(g6Samples());
    expect(evals[0].decision, GpsDecision.accepted);
    expect(evals[1].decision, GpsDecision.rejected); // 25 s < 30 s
    expect(evals[2].decision, GpsDecision.paused); // 45 s
    expect(evals[2].rejectReason, 'ACCURACY_PAUSED');

    // GPS hoi phuc tot sau 45 s -> nhan lai binh thuong.
    final GpsEvaluation first = step(null, s(0));
    final GpsEvaluation back =
        step(first, s(45000, lat: latE7ForMeters(300), speed: 7000));
    expect(back.decision, GpsDecision.accepted);
  });

  test('G7: timestamp giam -> reject', () {
    final List<GpsEvaluation> evals = run(g7Samples());
    expect(evals[0].decision, GpsDecision.accepted);
    expect(evals[1].decision, GpsDecision.rejected);
    expect(evals[1].rejectReason, 'SANITY_TS');
    expect(evals[2].decision, GpsDecision.rejected);
    expect(evals[2].rejectReason, 'SANITY_TS');
    expect(evals[3].decision, GpsDecision.accepted);
  });

  test('G8: replay G1-G7 voi config -> ket qua y het', () {
    final List<List<GpsSample>> scenarios = <List<GpsSample>>[
      g1Samples(),
      g2Samples(),
      g3Samples(),
      g4Samples(),
      g5Samples(),
      g6Samples(),
      g7Samples(),
    ];

    List<String> replay() {
      final List<String> out = <String>[];
      for (int k = 0; k < scenarios.length; k++) {
        for (final GpsEvaluation e in run(scenarios[k])) {
          out.add('G${k + 1}|${e.decision.name}|${e.rejectReason}|'
              '${e.suspicious}|${e.smoothedLatE7}|${e.smoothedLngE7}|'
              '${e.state.prevTsMs}|${e.state.window.length}');
        }
      }
      return out;
    }

    final List<String> a = replay();
    final List<String> b = replay();
    expect(a.length, greaterThan(150));
    expect(a, equals(b));
  });
}
