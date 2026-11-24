import 'package:ttx/core/geo.dart';
import 'package:ttx/core/taximeter_engine.dart';
import 'package:ttx/domain/models/gps_sample.dart';
import 'package:ttx/domain/models/tariff_config_v2.dart';

/// dLat (e7) nho nhat de khoang cach doc theo kinh tuyen >= [meters] m.
int latE7ForMeters(int meters) => (meters * 10000000 + 111194) ~/ 111195;

/// Kiem tra nhanh helper: khoang cach nam trong [meters, meters + 1) m.
bool latHelperIsExact(int meters) {
  final int mm = distanceMm(0, 0, latE7ForMeters(meters), 0);
  return mm ~/ 1000 == meters;
}

/// 2026-11-24 10:00 gio Viet Nam.
const int baseTsMs = 1795489200000;
const int fastMmps = 10000; // 36 km/h

/// Mau GPS cach moc [baseTsMs] `tMs` ms; accuracy 5 m.
GpsSample gs(
  int tMs, {
  int latE7 = 0,
  int lngE7 = 0,
  int acc = 5000,
  int speed = fastMmps,
  bool mock = false,
}) {
  return GpsSample(
    tsMs: baseTsMs + tMs,
    latE7: latE7,
    lngE7: lngE7,
    accuracyMm: acc,
    speedMmps: speed,
    isMock: mock,
  );
}

/// Chuyen thang theo kinh tuyen dai [meters] m, 2 diem, toc do 10 m/s.
List<GpsSample> straightTrip(int meters) {
  return <GpsSample>[
    gs(0),
    gs(meters * 100, latE7: latE7ForMeters(meters)),
  ];
}

List<Map<String, dynamic>> defaultTiers() => <Map<String, dynamic>>[
      <String, dynamic>{'index': 0, 'upToMeters': 30000, 'pricePerKmVnd': 15000},
      <String, dynamic>{'index': 1, 'upToMeters': null, 'pricePerKmVnd': 12000},
    ];

/// Bieu gia mau (JSON schema 2.0) cho test: mo cua 10000 gom 1000 m; bac 1
/// den 30000 m: 15000 VND/km, bac 2: 12000; cho 120000 VND/gio, grace 30 s.
Map<String, dynamic> fixtureConfigJson({
  int calibrationPermille = 1000,
  String calibrationOrder = 'BEFORE_OPENING_KM',
  List<Map<String, dynamic>>? tiers,
  String roundingMode = 'ROUND_HALF_UP',
  int roundingUnit = 1,
  List<Map<String, dynamic>> surcharges = const <Map<String, dynamic>>[],
  List<String> pipelineOrder = const <String>[],
  int ratePerHour = 120000,
  int graceSeconds = 30,
  int minWaitSeconds = 5,
}) {
  return <String, dynamic>{
    'schemaVersion': '2.0',
    'configId': 'test',
    'configVersion': 1,
    'effectiveFrom': 1730000000000,
    'effectiveTo': null,
    'status': 'ACTIVE',
    'units': <String, dynamic>{
      'distance': 'meter',
      'time': 'second',
      'money': 'VND',
      'multiplierBase': 1000,
    },
    'opening': <String, dynamic>{'fareVnd': 10000, 'includedMeters': 1000},
    'distanceTiers': tiers ?? defaultTiers(),
    'waiting': <String, dynamic>{
      'ratePerHourVnd': ratePerHour,
      'enterThresholdKmh': 5,
      'exitThresholdKmh': 8,
      'graceSeconds': graceSeconds,
      'countingPolicy': 'EXCLUSIVE_FROM_DISTANCE',
      'minWaitSegmentSeconds': minWaitSeconds,
    },
    'gps': <String, dynamic>{
      'maxAccuracyMeters': 20,
      'maxSpeedKmh': 120,
      'calibrationFactorPermille': calibrationPermille,
      'calibrationApplyOrder': calibrationOrder,
      'anchorDriftGuard': <String, dynamic>{
        'enabled': true,
        'minSpeedMps': 1.5,
        'anchorRadiusMultiplier': 2.0,
        'maxAnchorAgeSeconds': 30,
      },
    },
    'rounding': <String, dynamic>{
      'unitVnd': roundingUnit,
      'mode': roundingMode,
      'apply': 'FINAL_ONLY',
      'displayModeDuringTrip': 'FLOOR',
    },
    'surcharges': surcharges,
    'surchargePipeline': <String, dynamic>{
      'order': pipelineOrder,
      'allowStacking': true,
      'stackingMode': 'MULTIPLICATIVE_THEN_ADDITIVE',
      'maxStackCount': 3,
    },
    'validation': <String, dynamic>{
      'requireMonotonicTiers': true,
      'requirePositiveRates': true,
      'maxTierCount': 12,
      'requireExitAboveEnter': true,
    },
    'integrity': <String, dynamic>{'sha256': null, 'signature': null},
  };
}

TariffConfigV2 fixtureConfig({
  int calibrationPermille = 1000,
  String calibrationOrder = 'BEFORE_OPENING_KM',
  List<Map<String, dynamic>>? tiers,
  String roundingMode = 'ROUND_HALF_UP',
  int roundingUnit = 1,
  List<Map<String, dynamic>> surcharges = const <Map<String, dynamic>>[],
  List<String> pipelineOrder = const <String>[],
  int ratePerHour = 120000,
  int graceSeconds = 30,
  int minWaitSeconds = 5,
}) {
  return TariffConfigV2.fromJson(fixtureConfigJson(
    calibrationPermille: calibrationPermille,
    calibrationOrder: calibrationOrder,
    tiers: tiers,
    roundingMode: roundingMode,
    roundingUnit: roundingUnit,
    surcharges: surcharges,
    pipelineOrder: pipelineOrder,
    ratePerHour: ratePerHour,
    graceSeconds: graceSeconds,
    minWaitSeconds: minWaitSeconds,
  ));
}

SurchargeContexts contextsAt(int startMs) => SurchargeContexts(
      tripStartTimeMs: startMs,
      timezone: 'Asia/Ho_Chi_Minh',
      vehicleType: 'CAR_4',
      geofenceMatches: const <String>[],
    );

FareResult compute(
  List<GpsSample> samples,
  TariffConfigV2 config, {
  String tripId = 'trip-1',
  int startMs = baseTsMs,
}) {
  return TaximeterEngine.compute(
    samples: samples,
    config: config,
    contexts: contextsAt(startMs),
    tripId: tripId,
  );
}
