import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ttx_taximeter_pro/core/taximeter_engine.dart';
import 'package:ttx_taximeter_pro/core/tariff_config.dart';

import 'test_support.dart';

void main() {
  test('helper khoang cach chinh xac', () {
    expect(latHelperIsExact(3000), isTrue);
    expect(latHelperIsExact(3001), isTrue);
    expect(latHelperIsExact(500), isTrue);
  });

  test('T1: chuyen 0 diem -> chi tinh gia mo cua', () {
    final FareResult r = compute(<AcceptedPoint>[], fixtureConfig());
    expect(r.distanceM, 0);
    expect(r.fareTotalVnd, 10000);
  });

  test('T2: quang duong < includedMeters -> distance fare 0', () {
    final FareResult r = compute(straightTrip(500), fixtureConfig());
    expect(r.billableM, 0);
    expect(r.fareDistanceVnd, 0);
    expect(r.fareTotalVnd, 10000);
  });

  test('T3: fixture 3000 m -> 40000 VND', () {
    final FareResult r = compute(straightTrip(3000), fixtureConfig());
    expect(r.distanceM, 3000);
    expect(r.billableM, 2000);
    expect(r.fareDistanceVnd, 30000);
    expect(r.fareTotalVnd, 40000);
  });

  test('T4: chuyen bac dung bien upToMeters (inclusive)', () {
    final TariffConfigV2 cfg = fixtureConfig(
      tiers: const <DistanceTier>[
        DistanceTier(upToMeters: 2000, ratePerKmVnd: 15000),
        DistanceTier(upToMeters: null, ratePerKmVnd: 12000),
      ],
    );
    // billable 2000 -> het bac 1.
    expect(compute(straightTrip(3000), cfg).fareTotalVnd, 40000);
    // billable 2001 -> 1 m dau tien o bac 2: 12 VND.
    expect(compute(straightTrip(3001), cfg).fareTotalVnd, 40012);
  });

  test('T5: hieu chuan BEFORE vs AFTER opening', () {
    final FareResult before = compute(
      straightTrip(3000),
      fixtureConfig(calibrationPermille: 1100),
    );
    expect(before.calibratedM, 3300);
    expect(before.billableM, 2300);
    expect(before.fareTotalVnd, 44500);

    final FareResult after = compute(
      straightTrip(3000),
      fixtureConfig(
        calibrationPermille: 1100,
        calibrationMode: CalibrationMode.afterOpeningKm,
      ),
    );
    expect(after.billableM, 2200);
    expect(after.fareTotalVnd, 43000);
  });

  test('T6: cho ngan hon grace -> waiting 0', () {
    final List<AcceptedPoint> pts = <AcceptedPoint>[
      pt(0),
      pt(10000, speed: stopMmps),
      pt(20000, speed: stopMmps),
      pt(30000),
    ];
    final FareResult r = compute(pts, fixtureConfig());
    expect(r.waitingSec, 20);
    expect(r.waitingBillableSec, 0);
    expect(r.fareWaitingVnd, 0);
    expect(r.fareTotalVnd, 10000);
  });

  test('T7: cho dai hon grace -> tinh theo countingPolicy', () {
    // Mot dot cho 100 s, grace 30 s -> 70 s tinh tien.
    final List<AcceptedPoint> pts = <AcceptedPoint>[
      pt(0),
      pt(50000, speed: stopMmps),
      pt(100000, speed: stopMmps),
      pt(130000),
    ];
    final FareResult perSecond = compute(pts, fixtureConfig());
    expect(perSecond.waitingSec, 100);
    expect(perSecond.waitingBillableSec, 70);
    expect(perSecond.fareTotalVnd, 12333);

    final FareResult floorMin = compute(
      pts,
      fixtureConfig(counting: WaitingCounting.perFullMinuteFloor),
    );
    expect(floorMin.waitingBillableSec, 60);
    expect(floorMin.fareTotalVnd, 12000);

    final FareResult ceilMin = compute(
      pts,
      fixtureConfig(counting: WaitingCounting.perMinuteCeil),
    );
    expect(ceilMin.waitingBillableSec, 120);
    expect(ceilMin.fareTotalVnd, 14000);
  });

  test('T8: hysteresis enter/exit khong nhay trang thai', () {
    // enter < 5 km/h (1388 mm/s), exit > 8 km/h (2222 mm/s).
    final List<AcceptedPoint> pts = <AcceptedPoint>[
      pt(0),
      pt(10000, speed: 1000), // vao WAITING
      pt(20000, speed: 1800), // giua hai nguong: van WAITING
      pt(30000, speed: 1000),
      pt(40000, speed: 2500), // > exit: ra
    ];
    expect(compute(pts, fixtureConfig()).waitingSec, 30);

    // Toc do giua hai nguong khi dang chay khong kich hoat WAITING.
    final List<AcceptedPoint> moving = <AcceptedPoint>[
      pt(0),
      pt(10000, speed: 1800),
      pt(20000, speed: 1800),
    ];
    expect(compute(moving, fixtureConfig()).waitingSec, 0);
  });

  test('T9: phu phi MULTIPLIER nhan tren tong baseFare', () {
    final FareResult r = compute(
      straightTrip(3000),
      fixtureConfig(
        surcharges: const <Surcharge>[
          Surcharge(name: 'dem', kind: SurchargeKind.multiplier, permille: 1200),
          Surcharge(name: 'le', kind: SurchargeKind.multiplier, permille: 1500),
        ],
      ),
    );
    expect(r.fareTotalVnd, 72000); // 40000 x 1.2 x 1.5
  });

  test('T10: phu phi FIXED cong sau buoc nhan', () {
    final FareResult r = compute(
      straightTrip(3000),
      fixtureConfig(
        surcharges: const <Surcharge>[
          Surcharge(name: 'san bay', kind: SurchargeKind.fixed, fixedVnd: 5000),
          Surcharge(name: 'dem', kind: SurchargeKind.multiplier, permille: 1200),
        ],
      ),
    );
    expect(r.fareTotalVnd, 53000); // 40000 x 1.2 + 5000
  });

  test('T11: lam tron mot lan duy nhat, moi mode', () {
    RoundingPolicy rp(RoundingMode m) => RoundingPolicy(mode: m, stepVnd: 1000);

    // 40015 VND truoc lam tron (billable 2001 m, bac 1).
    expect(
      compute(straightTrip(3001), fixtureConfig(rounding: rp(RoundingMode.halfUp)))
          .fareTotalVnd,
      40000,
    );
    expect(
      compute(straightTrip(3001), fixtureConfig(rounding: rp(RoundingMode.up)))
          .fareTotalVnd,
      41000,
    );
    expect(
      compute(straightTrip(3001), fixtureConfig(rounding: rp(RoundingMode.down)))
          .fareTotalVnd,
      40000,
    );

    // 40500 VND truoc lam tron: HALF_UP len 41000.
    const List<Surcharge> plus500 = <Surcharge>[
      Surcharge(name: 'x', kind: SurchargeKind.fixed, fixedVnd: 500),
    ];
    expect(
      compute(
        straightTrip(3000),
        fixtureConfig(
          surcharges: plus500,
          rounding: rp(RoundingMode.halfUp),
        ),
      ).fareTotalVnd,
      41000,
    );
    expect(
      compute(
        straightTrip(3000),
        fixtureConfig(
          surcharges: plus500,
          rounding: rp(RoundingMode.down),
        ),
      ).fareTotalVnd,
      40000,
    );
  });

  test('T12: fareHash on dinh, doi 1 truong -> doi, replay khop tung byte', () {
    final TariffConfigV2 cfg = fixtureConfig();
    final FareResult a = compute(straightTrip(3000), cfg);
    final FareResult b = compute(straightTrip(3000), cfg);
    expect(a, equals(b));
    expect(a.fareHash, b.fareHash);

    final String expected =
        sha256.convert(utf8.encode('cfgsha${a.fareTotalVnd}trip-1')).toString();
    expect(a.fareHash, expected);

    expect(compute(straightTrip(3000), cfg, tripId: 'trip-2').fareHash,
        isNot(a.fareHash));
    expect(compute(straightTrip(3001), cfg).fareHash, isNot(a.fareHash));
  });
}
