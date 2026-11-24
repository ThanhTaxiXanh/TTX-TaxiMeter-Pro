import 'package:ttx_taximeter_pro/core/geo.dart';
import 'package:ttx_taximeter_pro/core/taximeter_engine.dart';
import 'package:ttx_taximeter_pro/core/tariff_config.dart';

/// dLat (e7) nho nhat de khoang cach doc theo kinh tuyen >= [meters] m.
int latE7ForMeters(int meters) => (meters * 10000000 + 111194) ~/ 111195;

/// Kiem tra nhanh helper: khoang cach nam trong [meters, meters + 1) m.
bool latHelperIsExact(int meters) {
  final int mm = distanceMm(0, 0, latE7ForMeters(meters), 0);
  return mm ~/ 1000 == meters;
}

const int fastMmps = 10000; // 36 km/h
const int stopMmps = 0;

AcceptedPoint pt(int tsMs, {int latE7 = 0, int lngE7 = 0, int speed = fastMmps}) {
  return AcceptedPoint(
    tsMs: tsMs,
    latE7: latE7,
    lngE7: lngE7,
    speedMmps: speed,
  );
}

/// Chuyen thang theo kinh tuyen dai [meters] m, 2 diem, toc do cao.
List<AcceptedPoint> straightTrip(int meters) {
  return <AcceptedPoint>[
    pt(0),
    pt(600000, latE7: latE7ForMeters(meters)),
  ];
}

/// Bieu gia mau (xem SKILL taximeter-engine).
TariffConfigV2 fixtureConfig({
  int calibrationPermille = 1000,
  CalibrationMode calibrationMode = CalibrationMode.beforeOpeningKm,
  List<DistanceTier>? tiers,
  WaitingCounting counting = WaitingCounting.perSecond,
  List<Surcharge> surcharges = const <Surcharge>[],
  RoundingPolicy rounding =
      const RoundingPolicy(mode: RoundingMode.halfUp, stepVnd: 1),
}) {
  return TariffConfigV2(
    configId: 'test',
    configVersion: 1,
    calibrationFactorPermille: calibrationPermille,
    calibrationMode: calibrationMode,
    opening: const OpeningPolicy(fareVnd: 10000, includedMeters: 1000),
    tiers: tiers ??
        const <DistanceTier>[
          DistanceTier(upToMeters: 30000, ratePerKmVnd: 15000),
          DistanceTier(upToMeters: null, ratePerKmVnd: 12000),
        ],
    waiting: WaitingPolicy(
      enterThresholdKmh: 5,
      exitThresholdKmh: 8,
      graceSeconds: 30,
      ratePerMinVnd: 2000,
      counting: counting,
    ),
    surcharges: surcharges,
    rounding: rounding,
  );
}

FareResult compute(
  List<AcceptedPoint> points,
  TariffConfigV2 config, {
  String tripId = 'trip-1',
}) {
  return TaximeterEngine.compute(
    points: points,
    config: config,
    configSha256: 'cfgsha',
    tripId: tripId,
  );
}
