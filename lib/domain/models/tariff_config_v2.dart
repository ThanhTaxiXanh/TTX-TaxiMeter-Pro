// TariffConfigV2: bieu gia bat bien (schema 2.0), doc tu JSON.
//
// Chi so nguyen. Gia tri thap phan trong JSON (vd 1.5 m/s, 2.0 lan) duoc doi
// MOT LAN o bien doc sang so nguyen (x1000) ngay trong fromJson.
// Gia tri khong ho tro / sai kieu -> FormatException (hong nhanh).

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import 'surcharge.dart';

export 'surcharge.dart';

enum CalibrationOrder { beforeOpeningKm, afterOpeningKm }

enum RoundingMode { halfUp, floor, ceil }

class OpeningPolicy {
  const OpeningPolicy({required this.fareVnd, required this.includedMeters});

  final int fareVnd;
  final int includedMeters;
}

class DistanceTier {
  const DistanceTier({required this.upToMeters, required this.pricePerKmVnd});

  /// Bien tren (inclusive) theo tong quang duong tinh tien; null = khong gioi han.
  final int? upToMeters;
  final int pricePerKmVnd;
}

class WaitingPolicy {
  const WaitingPolicy({
    required this.ratePerHourVnd,
    required this.enterThresholdKmh,
    required this.exitThresholdKmh,
    required this.graceSeconds,
    required this.minWaitSegmentSeconds,
  });

  final int ratePerHourVnd;
  final int enterThresholdKmh;
  final int exitThresholdKmh;
  final int graceSeconds;

  /// Dot cho ngan hon so giay nay bi bo qua (coi la dang chay).
  final int minWaitSegmentSeconds;
}

class GpsRules {
  const GpsRules({
    required this.maxAccuracyMm,
    required this.relaxedAccuracyMm,
    required this.maxSpeedKmh,
    required this.calibrationFactorPermille,
    required this.calibrationOrder,
    required this.anchorEnabled,
    required this.anchorMaxSpeedMmps,
    required this.anchorRadiusPermille,
    required this.anchorMaxAgeMs,
  });

  final int maxAccuracyMm;
  final int relaxedAccuracyMm;
  final int maxSpeedKmh;
  final int calibrationFactorPermille;
  final CalibrationOrder calibrationOrder;
  final bool anchorEnabled;
  final int anchorMaxSpeedMmps;
  final int anchorRadiusPermille;
  final int anchorMaxAgeMs;
}

class RoundingPolicy {
  const RoundingPolicy({
    required this.unitVnd,
    required this.mode,
    this.displayMode = RoundingMode.floor,
  });

  final int unitVnd;
  final RoundingMode mode;

  /// Che do lam tron de HIEN THI cuoc dang chay (displayModeDuringTrip).
  final RoundingMode displayMode;
}

class TariffConfigV2 {
  const TariffConfigV2({
    required this.schemaVersion,
    required this.configId,
    required this.configVersion,
    required this.effectiveFrom,
    required this.effectiveTo,
    required this.status,
    required this.opening,
    required this.tiers,
    required this.waiting,
    required this.gps,
    required this.rounding,
    required this.surcharges,
    required this.pipeline,
    required this.contentSha256,
  });

  /// `json` la Map doc tu JSON (kieu dynamic).
  ///
  /// contentSha256 = SHA-256(UTF-8(jsonEncode(config khong co khoa `integrity`))).
  /// `integrity.sha256` = null -> dung gia tri tinh duoc; khac null thi phai
  /// khop, neu khong -> FormatException.
  factory TariffConfigV2.fromJson(dynamic json) {
    final Map<String, dynamic> root = _map(json, 'config');

    final Map<String, dynamic> hashed = Map<String, dynamic>.of(root)
      ..remove('integrity');
    final String computed =
        crypto.sha256.convert(utf8.encode(jsonEncode(hashed))).toString();
    final Object? integrity = root['integrity'];
    if (integrity is Map<String, dynamic>) {
      final Object? declared = integrity['sha256'];
      if (declared != null && declared != computed) {
        throw const FormatException('integrity.sha256 khong khop noi dung config');
      }
    }

    if (_str(root, 'schemaVersion') != '2.0') {
      throw FormatException('schemaVersion khong ho tro: ${root['schemaVersion']}');
    }
    final Map<String, dynamic> units = _map(root['units'], 'units');
    if (_int(units, 'multiplierBase') != 1000) {
      throw const FormatException('units.multiplierBase phai la 1000');
    }

    final Map<String, dynamic> opening = _map(root['opening'], 'opening');
    final Map<String, dynamic> validation =
        root['validation'] is Map<String, dynamic>
            ? root['validation'] as Map<String, dynamic>
            : const <String, dynamic>{};

    // --- bac thang ---
    final List<Map<String, dynamic>> tierMaps = _list(root['distanceTiers'], 'distanceTiers')
        .map((dynamic e) => _map(e, 'distanceTiers[]'))
        .toList()
      ..sort((Map<String, dynamic> a, Map<String, dynamic> b) =>
          _int(a, 'index').compareTo(_int(b, 'index')));
    final List<DistanceTier> tiers = tierMaps
        .map((Map<String, dynamic> t) => DistanceTier(
              upToMeters: _intOrNull(t, 'upToMeters'),
              pricePerKmVnd: _int(t, 'pricePerKmVnd'),
            ))
        .toList();
    _validateTiers(tiers, validation);

    // --- cho ---
    final Map<String, dynamic> wm = _map(root['waiting'], 'waiting');
    if (_str(wm, 'countingPolicy') != 'EXCLUSIVE_FROM_DISTANCE') {
      throw FormatException('countingPolicy khong ho tro: ${wm['countingPolicy']}');
    }
    final WaitingPolicy waiting = WaitingPolicy(
      ratePerHourVnd: _int(wm, 'ratePerHourVnd'),
      enterThresholdKmh: _int(wm, 'enterThresholdKmh'),
      exitThresholdKmh: _int(wm, 'exitThresholdKmh'),
      graceSeconds: _int(wm, 'graceSeconds'),
      minWaitSegmentSeconds: _intOrNull(wm, 'minWaitSegmentSeconds') ?? 0,
    );
    if ((validation['requireExitAboveEnter'] as bool?) ?? true) {
      if (waiting.exitThresholdKmh <= waiting.enterThresholdKmh) {
        throw const FormatException('exitThresholdKmh phai > enterThresholdKmh');
      }
    }

    // --- gps ---
    final Map<String, dynamic> gm = _map(root['gps'], 'gps');
    final Map<String, dynamic> am = _map(gm['anchorDriftGuard'], 'gps.anchorDriftGuard');
    final int maxAccMm = _int(gm, 'maxAccuracyMeters') * 1000;
    final int relaxedMeters = _intOrNull(gm, 'relaxedAccuracyMeters') ?? 35;
    final int relaxedMm = relaxedMeters * 1000;
    final GpsRules gps = GpsRules(
      maxAccuracyMm: maxAccMm,
      relaxedAccuracyMm: relaxedMm < maxAccMm ? maxAccMm : relaxedMm,
      maxSpeedKmh: _int(gm, 'maxSpeedKmh'),
      calibrationFactorPermille: _int(gm, 'calibrationFactorPermille'),
      calibrationOrder: _calibrationOrder(_str(gm, 'calibrationApplyOrder')),
      anchorEnabled: (am['enabled'] as bool?) ?? true,
      anchorMaxSpeedMmps: _milli(am['minSpeedMps'], 'minSpeedMps'),
      anchorRadiusPermille:
          _milli(am['anchorRadiusMultiplier'], 'anchorRadiusMultiplier'),
      anchorMaxAgeMs: _int(am, 'maxAnchorAgeSeconds') * 1000,
    );

    // --- lam tron ---
    final Map<String, dynamic> rm = _map(root['rounding'], 'rounding');
    if (_str(rm, 'apply') != 'FINAL_ONLY') {
      throw FormatException('rounding.apply khong ho tro: ${rm['apply']}');
    }
    final int unit = _int(rm, 'unitVnd');
    if (unit < 1) throw const FormatException('rounding.unitVnd phai >= 1');
    final Object? displayRaw = rm['displayModeDuringTrip'];
    final RoundingPolicy rounding = RoundingPolicy(
      unitVnd: unit,
      mode: _roundingMode(_str(rm, 'mode')),
      displayMode:
          displayRaw is String ? _roundingMode(displayRaw) : RoundingMode.floor,
    );

    // --- phu phi ---
    final List<Surcharge> surcharges =
        (root['surcharges'] == null ? const <dynamic>[] : _list(root['surcharges'], 'surcharges'))
            .map((dynamic e) => _surcharge(_map(e, 'surcharges[]')))
            .toList();
    final Object? pm = root['surchargePipeline'];
    SurchargePipeline pipeline = const SurchargePipeline();
    if (pm is Map<String, dynamic>) {
      final Object? mode = pm['stackingMode'];
      if (mode != null && mode != 'MULTIPLICATIVE_THEN_ADDITIVE') {
        throw FormatException('stackingMode khong ho tro: $mode');
      }
      pipeline = SurchargePipeline(
        order: (pm['order'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic e) => e as String)
            .toList(),
        allowStacking: (pm['allowStacking'] as bool?) ?? true,
        maxStackCount: _intOrNull(pm, 'maxStackCount') ?? 3,
      );
    }

    return TariffConfigV2(
      schemaVersion: '2.0',
      configId: _str(root, 'configId'),
      configVersion: _int(root, 'configVersion'),
      effectiveFrom: _int(root, 'effectiveFrom'),
      effectiveTo: _intOrNull(root, 'effectiveTo'),
      status: _str(root, 'status'),
      opening: OpeningPolicy(
        fareVnd: _int(opening, 'fareVnd'),
        includedMeters: _int(opening, 'includedMeters'),
      ),
      tiers: tiers,
      waiting: waiting,
      gps: gps,
      rounding: rounding,
      surcharges: surcharges,
      pipeline: pipeline,
      contentSha256: computed,
    );
  }

  final String schemaVersion;
  final String configId;
  final int configVersion;
  final int effectiveFrom;
  final int? effectiveTo;
  final String status;
  final OpeningPolicy opening;
  final List<DistanceTier> tiers;
  final WaitingPolicy waiting;
  final GpsRules gps;
  final RoundingPolicy rounding;
  final List<Surcharge> surcharges;
  final SurchargePipeline pipeline;

  /// SHA-256 noi dung config (khong gom `integrity`); luu cung moi chuyen.
  final String contentSha256;
}

// ---------- helper doc JSON ----------

Map<String, dynamic> _map(Object? v, String path) {
  if (v is Map<String, dynamic>) return v;
  throw FormatException('$path phai la object');
}

List<dynamic> _list(Object? v, String path) {
  if (v is List<dynamic>) return v;
  throw FormatException('$path phai la mang');
}

int _int(Map<String, dynamic> m, String k) {
  final Object? v = m[k];
  if (v is int) return v;
  throw FormatException('Truong "$k" thieu hoac khong phai so nguyen: $v');
}

int? _intOrNull(Map<String, dynamic> m, String k) {
  final Object? v = m[k];
  if (v == null) return null;
  if (v is int) return v;
  throw FormatException('Truong "$k" khong phai so nguyen: $v');
}

String _str(Map<String, dynamic> m, String k) {
  final Object? v = m[k];
  if (v is String) return v;
  throw FormatException('Truong "$k" thieu hoac khong phai chuoi: $v');
}

/// Doi so thuc trong JSON (vd 1.5) sang so nguyen x1000 (1500), mot lan.
int _milli(Object? v, String k) {
  if (v is num) return (v * 1000).round();
  throw FormatException('Truong "$k" phai la so: $v');
}

CalibrationOrder _calibrationOrder(String s) {
  switch (s) {
    case 'BEFORE_OPENING_KM':
      return CalibrationOrder.beforeOpeningKm;
    case 'AFTER_OPENING_KM':
      return CalibrationOrder.afterOpeningKm;
  }
  throw FormatException('calibrationApplyOrder khong ho tro: $s');
}

RoundingMode _roundingMode(String s) {
  switch (s) {
    case 'ROUND_HALF_UP':
      return RoundingMode.halfUp;
    case 'FLOOR':
      return RoundingMode.floor;
    case 'CEIL':
      return RoundingMode.ceil;
  }
  throw FormatException('rounding.mode khong ho tro: $s');
}

void _validateTiers(List<DistanceTier> tiers, Map<String, dynamic> validation) {
  if (tiers.isEmpty) throw const FormatException('Thieu bac thang');
  final int maxCount = (validation['maxTierCount'] as int?) ?? 12;
  if (tiers.length > maxCount) {
    throw FormatException('Qua $maxCount bac thang');
  }
  if ((validation['requirePositiveRates'] as bool?) ?? true) {
    for (final DistanceTier t in tiers) {
      if (t.pricePerKmVnd <= 0) {
        throw const FormatException('Don gia bac thang phai > 0');
      }
    }
  }
  if ((validation['requireMonotonicTiers'] as bool?) ?? true) {
    int prev = 0;
    for (int i = 0; i < tiers.length; i++) {
      final int? up = tiers[i].upToMeters;
      final bool last = i == tiers.length - 1;
      if (up == null) {
        if (!last) throw const FormatException('Chi bac cuoi duoc upToMeters = null');
        continue;
      }
      if (up <= prev) throw const FormatException('Bac thang phai tang dan');
      if (last) throw const FormatException('Bac cuoi phai co upToMeters = null');
      prev = up;
    }
  }
}

Surcharge _surcharge(Map<String, dynamic> m) {
  if (m['evaluationBasis'] != null && m['evaluationBasis'] != 'TRIP_START_TIME') {
    throw FormatException('evaluationBasis khong ho tro: ${m['evaluationBasis']}');
  }
  final Object? cm = m['condition'];
  TimeRangeCondition? condition;
  if (cm != null) {
    final Map<String, dynamic> c = _map(cm, 'condition');
    if (_str(c, 'type') != 'TIME_RANGE') {
      throw FormatException('condition.type khong ho tro: ${c['type']}');
    }
    condition = TimeRangeCondition.fromJson(c);
  }
  final String type = _str(m, 'type');
  final Set<String> applies = m['appliesTo'] == null
      ? const <String>{'opening', 'distance', 'waiting'}
      : _list(m['appliesTo'], 'appliesTo').map((dynamic e) => e as String).toSet();
  for (final String a in applies) {
    if (a != 'opening' && a != 'distance' && a != 'waiting') {
      throw FormatException('appliesTo khong ho tro: $a');
    }
  }
  switch (type) {
    case 'MULTIPLIER':
      return Surcharge(
        id: _str(m, 'id'),
        kind: SurchargeKind.multiplier,
        valuePermille: _int(m, 'valuePermille'),
        appliesTo: applies,
        condition: condition,
      );
    case 'FIXED':
      return Surcharge(
        id: _str(m, 'id'),
        kind: SurchargeKind.fixed,
        valueVnd: _int(m, 'valueVnd'),
        appliesTo: applies,
        condition: condition,
      );
  }
  throw FormatException('surcharge.type khong ho tro: $type');
}
