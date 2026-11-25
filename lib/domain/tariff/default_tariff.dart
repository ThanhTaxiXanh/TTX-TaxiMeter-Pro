// Bieu gia mac dinh (MAU) de app chay duoc ngay lan dau. Chu xe se thay bang
// bieu gia that cua minh trong Cai dat (Phase 6). Chi la so lieu minh hoa.
const String defaultTariffId = 'default-car4';

Map<String, dynamic> defaultTariffJson({required int effectiveFromMs}) {
  return <String, dynamic>{
    'schemaVersion': '2.0',
    'configId': defaultTariffId,
    'configVersion': 1,
    'effectiveFrom': effectiveFromMs,
    'effectiveTo': null,
    'status': 'ACTIVE',
    'units': <String, dynamic>{
      'distance': 'meter',
      'time': 'second',
      'money': 'VND',
      'multiplierBase': 1000,
    },
    'opening': <String, dynamic>{'fareVnd': 12000, 'includedMeters': 800},
    'distanceTiers': <Map<String, dynamic>>[
      <String, dynamic>{'index': 0, 'upToMeters': 30000, 'pricePerKmVnd': 15000},
      <String, dynamic>{'index': 1, 'upToMeters': null, 'pricePerKmVnd': 12000},
    ],
    'waiting': <String, dynamic>{
      'ratePerHourVnd': 90000,
      'enterThresholdKmh': 5,
      'exitThresholdKmh': 8,
      'graceSeconds': 30,
      'countingPolicy': 'EXCLUSIVE_FROM_DISTANCE',
      'minWaitSegmentSeconds': 5,
    },
    'gps': <String, dynamic>{
      'maxAccuracyMeters': 20,
      'maxSpeedKmh': 120,
      'calibrationFactorPermille': 1000,
      'calibrationApplyOrder': 'BEFORE_OPENING_KM',
      'anchorDriftGuard': <String, dynamic>{
        'enabled': true,
        'minSpeedMps': 1.5,
        'anchorRadiusMultiplier': 2.0,
        'maxAnchorAgeSeconds': 30,
      },
    },
    'rounding': <String, dynamic>{
      'unitVnd': 1000,
      'mode': 'ROUND_HALF_UP',
      'apply': 'FINAL_ONLY',
      'displayModeDuringTrip': 'FLOOR',
    },
    'surcharges': <Map<String, dynamic>>[],
    'surchargePipeline': <String, dynamic>{
      'order': <String>[],
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
