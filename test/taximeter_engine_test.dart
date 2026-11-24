import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ttx/core/taximeter_engine.dart';
import 'package:ttx/domain/models/gps_sample.dart';
import 'package:ttx/domain/models/tariff_config_v2.dart';

import 'test_support.dart';

Map<String, dynamic> nightSurcharge({List<int>? days}) => <String, dynamic>{
      'id': 'night',
      'type': 'MULTIPLIER',
      'valuePermille': 1200,
      'appliesTo': <String>['opening', 'distance', 'waiting'],
      'condition': <String, dynamic>{
        'type': 'TIME_RANGE',
        'timezone': 'Asia/Ho_Chi_Minh',
        'ranges': <Map<String, String>>[
          <String, String>{'from': '22:00', 'to': '05:00'},
        ],
        'daysOfWeek': days ?? <int>[1, 2, 3, 4, 5, 6, 7],
      },
      'evaluationBasis': 'TRIP_START_TIME',
    };

void main() {
  test('helper khoang cach chinh xac', () {
    expect(latHelperIsExact(3000), isTrue);
    expect(latHelperIsExact(3001), isTrue);
    expect(latHelperIsExact(500), isTrue);
  });

  test('T1: chuyen 0 diem -> chi tinh gia mo cua', () {
    final FareResult r = compute(<GpsSample>[], fixtureConfig());
    expect(r.distanceM, 0);
    expect(r.fareTotal, 10000);
  });

  test('T2: quang duong < includedMeters -> distance fare 0', () {
    final FareResult r = compute(straightTrip(500), fixtureConfig());
    expect(r.billableM, 0);
    expect(r.fareDistance, 0);
    expect(r.fareTotal, 10000);
  });

  test('T3: fixture 3000 m -> 40000 VND', () {
    final FareResult r = compute(straightTrip(3000), fixtureConfig());
    expect(r.distanceM, 3000);
    expect(r.billableM, 2000);
    expect(r.fareDistance, 30000);
    expect(r.fareTotal, 40000);
  });

  test('T4: chuyen bac dung bien upToMeters (inclusive)', () {
    final TariffConfigV2 cfg = fixtureConfig(
      tiers: <Map<String, dynamic>>[
        <String, dynamic>{'index': 0, 'upToMeters': 2000, 'pricePerKmVnd': 15000},
        <String, dynamic>{'index': 1, 'upToMeters': null, 'pricePerKmVnd': 12000},
      ],
    );
    // billable 2000 -> het bac 1.
    expect(compute(straightTrip(3000), cfg).fareTotal, 40000);
    // billable 2001 -> 1 m dau tien o bac 2: 12 VND.
    expect(compute(straightTrip(3001), cfg).fareTotal, 40012);
  });

  test('T5: hieu chuan BEFORE vs AFTER opening', () {
    final FareResult before = compute(
      straightTrip(3000),
      fixtureConfig(calibrationPermille: 1100),
    );
    expect(before.calibratedM, 3300);
    expect(before.billableM, 2300);
    expect(before.fareTotal, 44500);

    final FareResult after = compute(
      straightTrip(3000),
      fixtureConfig(
        calibrationPermille: 1100,
        calibrationOrder: 'AFTER_OPENING_KM',
      ),
    );
    expect(after.billableM, 2200);
    expect(after.fareTotal, 43000);
  });

  test('T6: cho ngan hon grace -> waiting 0', () {
    final List<GpsSample> pts = <GpsSample>[
      gs(0),
      gs(10000, speed: 0),
      gs(20000, speed: 0),
      gs(30000),
    ];
    final FareResult r = compute(pts, fixtureConfig());
    expect(r.waitingSec, 20);
    expect(r.waitingBillableSec, 0);
    expect(r.fareWaiting, 0);
    expect(r.fareTotal, 10000);
  });

  test('T7: cho dai hon grace -> tinh theo gio, tru grace; bo doan cho khoi quang duong', () {
    // Mot dot cho 100 s, grace 30 s -> 70 s tinh tien: 70 x 120000/3600.
    final List<GpsSample> pts = <GpsSample>[
      gs(0),
      gs(50000, speed: 0),
      gs(100000, speed: 0),
      gs(130000),
    ];
    final FareResult r = compute(pts, fixtureConfig());
    expect(r.waitingSec, 100);
    expect(r.waitingBillableSec, 70);
    expect(r.fareWaiting, 2333);
    expect(r.fareTotal, 12333);

    // EXCLUSIVE_FROM_DISTANCE: 30 m di cham trong dot cho khong tinh vao quang duong.
    final List<GpsSample> creeping = <GpsSample>[
      gs(0),
      gs(100000, latE7: latE7ForMeters(1000)),
      gs(160000, latE7: latE7ForMeters(1030), speed: 500),
      gs(170000, latE7: latE7ForMeters(1130)),
    ];
    final FareResult c = compute(creeping, fixtureConfig());
    expect(c.waitingSec, 60);
    expect(c.waitingBillableSec, 30);
    expect(c.distanceM, inInclusiveRange(1098, 1102));
  });

  test('T7b: dot cho ngan hon minWaitSegmentSeconds bi bo qua', () {
    final List<GpsSample> pts = <GpsSample>[
      gs(0),
      gs(3000, speed: 0),
      gs(10000),
    ];
    final FareResult r =
        compute(pts, fixtureConfig(minWaitSeconds: 5, graceSeconds: 0));
    expect(r.waitingSec, 0);
    expect(r.fareWaiting, 0);
  });

  test('T8: hysteresis enter/exit khong nhay trang thai', () {
    // enter < 5 km/h (1388 mm/s), exit > 8 km/h (2222 mm/s).
    final List<GpsSample> pts = <GpsSample>[
      gs(0),
      gs(10000, speed: 1000), // vao WAITING
      gs(20000, speed: 1800), // giua hai nguong: van WAITING
      gs(30000, speed: 1000),
      gs(40000, speed: 2500), // > exit: ra
    ];
    expect(compute(pts, fixtureConfig()).waitingSec, 30);

    // Toc do giua hai nguong khi dang chay khong kich hoat WAITING.
    final List<GpsSample> moving = <GpsSample>[
      gs(0),
      gs(10000, speed: 1800),
      gs(20000, speed: 1800),
    ];
    expect(compute(moving, fixtureConfig()).waitingSec, 0);
  });

  test('T8b: toc do am (khong biet) duoc suy ra tu vi tri', () {
    final List<GpsSample> pts = <GpsSample>[
      gs(0, speed: -1),
      gs(60000, speed: -1), // dung yen 60 s
      gs(120000, speed: -1),
      gs(180000, latE7: latE7ForMeters(1000), speed: -1),
    ];
    final FareResult r = compute(pts, fixtureConfig());
    expect(r.waitingSec, 120);
  });

  test('T9: phu phi MULTIPLIER nhan tren tong baseFare', () {
    final FareResult r = compute(
      straightTrip(3000),
      fixtureConfig(
        surcharges: <Map<String, dynamic>>[
          <String, dynamic>{'id': 'a', 'type': 'MULTIPLIER', 'valuePermille': 1200},
          <String, dynamic>{'id': 'b', 'type': 'MULTIPLIER', 'valuePermille': 1500},
        ],
        pipelineOrder: <String>['a', 'b'],
      ),
    );
    expect(r.fareTotal, 72000); // 40000 x 1.2 x 1.5
    expect(r.fareSurcharge, 32000);
    expect(r.fareOpening, 10000);
  });

  test('T9b: appliesTo gioi han thanh phan duoc nhan', () {
    final FareResult r = compute(
      straightTrip(3000),
      fixtureConfig(
        surcharges: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'a',
            'type': 'MULTIPLIER',
            'valuePermille': 2000,
            'appliesTo': <String>['opening'],
          },
        ],
        pipelineOrder: <String>['a'],
      ),
    );
    expect(r.fareTotal, 50000); // opening 10000 x 2 + distance 30000
    expect(r.fareSurcharge, 10000);
  });

  test('T10: phu phi FIXED cong sau buoc nhan', () {
    final FareResult r = compute(
      straightTrip(3000),
      fixtureConfig(
        surcharges: <Map<String, dynamic>>[
          <String, dynamic>{'id': 'fix', 'type': 'FIXED', 'valueVnd': 5000},
          <String, dynamic>{'id': 'night', 'type': 'MULTIPLIER', 'valuePermille': 1200},
        ],
        pipelineOrder: <String>['fix', 'night'],
      ),
    );
    expect(r.fareTotal, 53000); // 40000 x 1.2 + 5000
  });

  test('T10b: phu phi dem theo TRIP_START_TIME (bien 22:00, nua dem, ngay trong tuan)', () {
    TariffConfigV2 cfg({List<int>? days}) => fixtureConfig(
          surcharges: <Map<String, dynamic>>[nightSurcharge(days: days)],
          pipelineOrder: <String>['night'],
        );
    // 2026-11-24 la thu ba (ISO 2).
    const int at1000 = baseTsMs; // 10:00
    const int at2155 = 1795532100000; // 21:55
    const int at2200 = at2155 + 5 * 60000; // 22:00 -> ap dung
    const int at2300 = 1795536000000; // 23:00
    const int at0200Next = 1795546800000; // 02:00 thu tu (thuoc dem thu ba)

    int surchargeAt(int startMs, TariffConfigV2 c) =>
        compute(straightTrip(3000), c, startMs: startMs).fareSurcharge;

    expect(surchargeAt(at1000, cfg()), 0);
    expect(surchargeAt(at2155, cfg()), 0);
    expect(surchargeAt(at2200, cfg()), 8000);
    expect(surchargeAt(at2300, cfg()), 8000);
    expect(surchargeAt(at0200Next, cfg()), 8000);

    // Chi thu hai: 23:00 thu ba khong ap dung.
    expect(surchargeAt(at2300, cfg(days: <int>[1])), 0);
    // Phan sau nua dem tinh theo ngay bat dau khung gio (thu ba = 2).
    expect(surchargeAt(at0200Next, cfg(days: <int>[2])), 8000);
    expect(surchargeAt(at0200Next, cfg(days: <int>[3])), 0);
  });

  test('T11: lam tron mot lan duy nhat, moi mode', () {
    TariffConfigV2 cfg(String mode, {List<Map<String, dynamic>>? sur}) =>
        fixtureConfig(
          roundingMode: mode,
          roundingUnit: 1000,
          surcharges: sur ?? const <Map<String, dynamic>>[],
          pipelineOrder: <String>['x'],
        );

    // 40012 VND truoc lam tron (billable 2001 m: 2001 x 15 = 30015 -> 40015).
    expect(compute(straightTrip(3001), cfg('ROUND_HALF_UP')).fareTotal, 40000);
    expect(compute(straightTrip(3001), cfg('CEIL')).fareTotal, 41000);
    expect(compute(straightTrip(3001), cfg('FLOOR')).fareTotal, 40000);

    // 40500 VND truoc lam tron: HALF_UP len 41000, FLOOR 40000.
    final List<Map<String, dynamic>> plus500 = <Map<String, dynamic>>[
      <String, dynamic>{'id': 'x', 'type': 'FIXED', 'valueVnd': 500},
    ];
    expect(
      compute(straightTrip(3000), cfg('ROUND_HALF_UP', sur: plus500)).fareTotal,
      41000,
    );
    expect(
      compute(straightTrip(3000), cfg('FLOOR', sur: plus500)).fareTotal,
      40000,
    );
  });

  test('T12: fareHash on dinh, doi 1 truong -> doi, replay khop tung byte', () {
    final TariffConfigV2 cfg = fixtureConfig();
    final FareResult a = compute(straightTrip(3000), cfg);
    final FareResult b = compute(straightTrip(3000), cfg);
    expect(a, equals(b));
    expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
    expect(a.fareHash, b.fareHash);

    final String expected = sha256
        .convert(utf8.encode('${cfg.contentSha256}${a.fareTotal}trip-1'))
        .toString();
    expect(a.fareHash, expected);

    expect(compute(straightTrip(3000), cfg, tripId: 'trip-2').fareHash,
        isNot(a.fareHash));
    expect(compute(straightTrip(3001), cfg).fareHash, isNot(a.fareHash));
    // Doi bieu gia -> sha256 config doi -> hash doi.
    expect(
      compute(straightTrip(3000), fixtureConfig(calibrationPermille: 1001)).fareHash,
      isNot(a.fareHash),
    );
  });

  group('TariffConfigV2.fromJson', () {
    test('contentSha256 xac dinh va bo qua khoa integrity', () {
      final TariffConfigV2 a = fixtureConfig();
      final TariffConfigV2 b = fixtureConfig();
      expect(a.contentSha256, b.contentSha256);
      expect(a.contentSha256.length, 64);

      final Map<String, dynamic> withSig = fixtureConfigJson();
      withSig['integrity'] = <String, dynamic>{'sha256': null, 'signature': 'abc'};
      expect(TariffConfigV2.fromJson(withSig).contentSha256, a.contentSha256);
    });

    test('integrity.sha256 sai -> FormatException; dung -> chap nhan', () {
      final Map<String, dynamic> j = fixtureConfigJson();
      final String good = TariffConfigV2.fromJson(j).contentSha256;
      j['integrity'] = <String, dynamic>{'sha256': good, 'signature': null};
      expect(TariffConfigV2.fromJson(j).contentSha256, good);
      j['integrity'] = <String, dynamic>{'sha256': 'deadbeef', 'signature': null};
      expect(() => TariffConfigV2.fromJson(j), throwsFormatException);
    });

    test('parse day du cac truong', () {
      final TariffConfigV2 c = fixtureConfig(
        surcharges: <Map<String, dynamic>>[nightSurcharge()],
        pipelineOrder: <String>['night'],
      );
      expect(c.tiers.length, 2);
      expect(c.tiers.first.upToMeters, 30000);
      expect(c.tiers.last.upToMeters, isNull);
      expect(c.rounding.unitVnd, 1);
      expect(c.rounding.mode, RoundingMode.halfUp);
      expect(c.gps.anchorMaxSpeedMmps, 1500);
      expect(c.gps.anchorRadiusPermille, 2000);
      expect(c.gps.maxAccuracyMm, 20000);
      expect(c.surcharges.single.valuePermille, 1200);
      expect(c.pipeline.order, <String>['night']);
    });

    test('gia tri khong ho tro / sai -> FormatException', () {
      Map<String, dynamic> j() => fixtureConfigJson();

      final Map<String, dynamic> a = j();
      (a['waiting'] as Map<String, dynamic>)['countingPolicy'] = 'SOMETHING_ELSE';
      expect(() => TariffConfigV2.fromJson(a), throwsFormatException);

      final Map<String, dynamic> b = j();
      (b['waiting'] as Map<String, dynamic>)['exitThresholdKmh'] = 5;
      expect(() => TariffConfigV2.fromJson(b), throwsFormatException);

      final Map<String, dynamic> c = j();
      c['distanceTiers'] = <Map<String, dynamic>>[
        <String, dynamic>{'index': 0, 'upToMeters': 5000, 'pricePerKmVnd': 1000},
        <String, dynamic>{'index': 1, 'upToMeters': 4000, 'pricePerKmVnd': 900},
        <String, dynamic>{'index': 2, 'upToMeters': null, 'pricePerKmVnd': 800},
      ];
      expect(() => TariffConfigV2.fromJson(c), throwsFormatException);

      final Map<String, dynamic> d = j();
      (d['rounding'] as Map<String, dynamic>)['mode'] = 'BANKERS';
      expect(() => TariffConfigV2.fromJson(d), throwsFormatException);

      final Map<String, dynamic> e = j();
      e['surcharges'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'x',
          'type': 'MULTIPLIER',
          'valuePermille': 1100,
          'evaluationBasis': 'TRIP_END_TIME',
        },
      ];
      expect(() => TariffConfigV2.fromJson(e), throwsFormatException);
    });
  });
}
