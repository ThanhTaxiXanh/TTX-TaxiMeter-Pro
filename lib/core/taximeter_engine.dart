// PURE: khong doc dong ho he thong, khong ngau nhien, khong I/O.
// Chi so nguyen. Xem .github/skills/taximeter-engine/SKILL.md.

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import '../domain/models/gps_sample.dart';
import '../domain/models/tariff_config_v2.dart';
import 'geo.dart';
import 'gps_policy.dart';

/// Thang trung gian: VND x 18000 (= BCNN(1000, 3600) de don gia VND/km va
/// VND/gio deu ra so nguyen). Lam tron dung 1 lan o buoc cuoi.
const int fareScale = 18000;
const int _scalePerMeterPerKm = fareScale ~/ 1000; // 18
const int _scalePerSecondPerHour = fareScale ~/ 3600; // 5

class FareResult {
  const FareResult({
    required this.acceptedCount,
    required this.rejectedCount,
    required this.pausedCount,
    required this.suspiciousCount,
    required this.distanceM,
    required this.calibratedM,
    required this.billableM,
    required this.waitingSec,
    required this.waitingBillableSec,
    required this.fareOpening,
    required this.fareDistance,
    required this.fareWaiting,
    required this.fareSurcharge,
    required this.fareTotal,
    required this.fareHash,
  });

  final int acceptedCount;
  final int rejectedCount;
  final int pausedCount;
  final int suspiciousCount;

  /// Quang duong tho (m, nguyen) giua cac diem ACCEPTED, da bo cac doan cho
  /// (EXCLUSIVE_FROM_DISTANCE).
  final int distanceM;
  final int calibratedM;
  final int billableM;

  /// Tong giay o trang thai cho (dot cho >= minWaitSegmentSeconds).
  final int waitingSec;

  /// Giay cho bi tinh tien (da tru grace tung dot).
  final int waitingBillableSec;
  final int fareOpening;
  final int fareDistance;
  final int fareWaiting;

  /// Phan phu phi thuan (sau - truoc khi ap phu phi). Khong gom chenh lech
  /// do lam tron.
  final int fareSurcharge;

  /// So tien khach tra (da lam tron 1 lan). Day la so co tham quyen.
  final int fareTotal;
  final String fareHash;

  Map<String, Object> toJson() => <String, Object>{
        'accepted': acceptedCount,
        'rejected': rejectedCount,
        'paused': pausedCount,
        'suspicious': suspiciousCount,
        'distance_m': distanceM,
        'calibrated_m': calibratedM,
        'billable_m': billableM,
        'waiting_sec': waitingSec,
        'waiting_billable_sec': waitingBillableSec,
        'fare_opening_vnd': fareOpening,
        'fare_distance_vnd': fareDistance,
        'fare_waiting_vnd': fareWaiting,
        'fare_surcharge_vnd': fareSurcharge,
        'fare_total_vnd': fareTotal,
        'fare_hash': fareHash,
      };

  @override
  bool operator ==(Object other) =>
      other is FareResult && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => fareHash.hashCode;

  @override
  String toString() => jsonEncode(toJson());
}

class TaximeterEngine {
  const TaximeterEngine._();

  /// fareHash = sha256(utf8(configSha256 + fareTotalVnd + tripId)), noi chuoi
  /// thap phan, khong dau phan cach, hex thuong.
  static String fareHash({
    required String configSha256,
    required int fareTotalVnd,
    required String tripId,
  }) {
    final List<int> bytes = utf8.encode('$configSha256$fareTotalVnd$tripId');
    return crypto.sha256.convert(bytes).toString();
  }

  /// Tinh cuoc tu GPS tho: GpsPolicy loc -> quang duong (toa do tho) ->
  /// cho -> bac thang -> phu phi -> lam tron 1 lan.
  static FareResult compute({
    required List<GpsSample> samples,
    required TariffConfigV2 config,
    required SurchargeContexts contexts,
    String tripId = '',
  }) {
    // 1. Loc GPS.
    final GpsPolicyConfig policy = GpsPolicyConfig.fromRules(config.gps);
    GpsPolicyState state = const GpsPolicyState();
    final List<GpsSample> acc = <GpsSample>[];
    int rejected = 0;
    int paused = 0;
    int suspicious = 0;
    for (final GpsSample s in samples) {
      final GpsEvaluation e = GpsPolicy.evaluate(state, s, policy);
      state = e.state;
      if (e.suspicious) suspicious++;
      switch (e.decision) {
        case GpsDecision.accepted:
          acc.add(s);
        case GpsDecision.rejected:
          rejected++;
        case GpsDecision.paused:
          paused++;
      }
    }

    // 2. Cac doan (i-1 -> i) giua cac diem ACCEPTED.
    final int segCount = acc.length < 2 ? 0 : acc.length - 1;
    final List<int> dtMs = List<int>.filled(segCount, 0);
    final List<int> distMm = List<int>.filled(segCount, 0);
    final List<int> speed = List<int>.filled(segCount, 0);
    for (int j = 0; j < segCount; j++) {
      final GpsSample a = acc[j];
      final GpsSample b = acc[j + 1];
      dtMs[j] = b.tsMs - a.tsMs;
      distMm[j] = distanceMm(a.latE7, a.lngE7, b.latE7, b.lngE7);
      // Toc do bao cao (>= 0) duoc uu tien; am = khong biet -> suy ra.
      speed[j] = b.speedMmps >= 0
          ? b.speedMmps
          : (dtMs[j] > 0 ? distMm[j] * 1000 ~/ dtMs[j] : 0);
    }

    // 3. Cho: hysteresis theo tung doan, gom thanh cac dot.
    final WaitingPolicy wp = config.waiting;
    final int enterMmps = wp.enterThresholdKmh * 1000000 ~/ 3600;
    final int exitMmps = wp.exitThresholdKmh * 1000000 ~/ 3600;
    final List<bool> waitingSeg = List<bool>.filled(segCount, false);
    bool inWait = false;
    for (int j = 0; j < segCount; j++) {
      if (!inWait && speed[j] < enterMmps) {
        inWait = true;
      } else if (inWait && speed[j] > exitMmps) {
        inWait = false;
      }
      waitingSeg[j] = inWait;
    }

    final int minWaitMs = wp.minWaitSegmentSeconds * 1000;
    final int graceMs = wp.graceSeconds * 1000;
    final List<bool> excluded = List<bool>.filled(segCount, false);
    int waitingMs = 0;
    int billableSec = 0;
    int idx = 0;
    while (idx < segCount) {
      if (!waitingSeg[idx]) {
        idx++;
        continue;
      }
      int k = idx;
      int episodeMs = 0;
      while (k < segCount && waitingSeg[k]) {
        episodeMs += dtMs[k];
        k++;
      }
      if (episodeMs >= minWaitMs) {
        waitingMs += episodeMs;
        final int over = episodeMs - graceMs;
        if (over > 0) billableSec += over ~/ 1000;
        // EXCLUSIVE_FROM_DISTANCE: doan trong dot cho khong tinh quang duong.
        for (int q = idx; q < k; q++) {
          excluded[q] = true;
        }
      }
      idx = k;
    }

    // 4. Quang duong, hieu chuan, quang duong tinh tien.
    int totalMm = 0;
    for (int q = 0; q < segCount; q++) {
      if (!excluded[q]) totalMm += distMm[q];
    }
    final int distanceM = totalMm ~/ 1000;
    final int f = config.gps.calibrationFactorPermille;
    final int inc = config.opening.includedMeters;
    final int calibratedM = distanceM * f ~/ 1000;
    final int billableM;
    switch (config.gps.calibrationOrder) {
      case CalibrationOrder.beforeOpeningKm:
        billableM = _max0(calibratedM - inc);
      case CalibrationOrder.afterOpeningKm:
        billableM = _max0(distanceM - inc) * f ~/ 1000;
    }

    // 5. Thanh phan cuoc (thang fareScale).
    final int openingScaled = config.opening.fareVnd * fareScale;
    final int distScaled = _tieredScaled(billableM, config.tiers);
    final int waitScaled =
        billableSec * wp.ratePerHourVnd * _scalePerSecondPerHour;
    final int baseScaled = openingScaled + distScaled + waitScaled;

    // 6. Phu phi: nhan tung thanh phan, sau do cong co dinh.
    int o = openingScaled;
    int d = distScaled;
    int w = waitScaled;
    int fixedScaled = 0;
    for (final Surcharge s in _activeSurcharges(config, contexts)) {
      if (s.kind == SurchargeKind.multiplier) {
        if (s.appliesTo.contains('opening')) o = o * s.valuePermille ~/ 1000;
        if (s.appliesTo.contains('distance')) d = d * s.valuePermille ~/ 1000;
        if (s.appliesTo.contains('waiting')) w = w * s.valuePermille ~/ 1000;
      } else {
        fixedScaled += s.valueVnd * fareScale;
      }
    }
    final int afterScaled = o + d + w + fixedScaled;

    // 7. Lam tron dung 1 lan.
    final int total = _roundScaled(afterScaled, config.rounding);

    return FareResult(
      acceptedCount: acc.length,
      rejectedCount: rejected,
      pausedCount: paused,
      suspiciousCount: suspicious,
      distanceM: distanceM,
      calibratedM: calibratedM,
      billableM: billableM,
      waitingSec: waitingMs ~/ 1000,
      waitingBillableSec: billableSec,
      fareOpening: config.opening.fareVnd,
      fareDistance: distScaled ~/ fareScale,
      fareWaiting: waitScaled ~/ fareScale,
      fareSurcharge: (afterScaled - baseScaled) ~/ fareScale,
      fareTotal: total,
      fareHash: fareHash(
        configSha256: config.contentSha256,
        fareTotalVnd: total,
        tripId: tripId,
      ),
    );
  }

  static int _max0(int v) => v < 0 ? 0 : v;

  /// Luy tien bac thang tren billableM; bien upToMeters inclusive.
  static int _tieredScaled(int billableM, List<DistanceTier> tiers) {
    int scaled = 0;
    int prevUp = 0;
    for (final DistanceTier t in tiers) {
      if (billableM <= prevUp) break;
      final int up = t.upToMeters ?? billableM;
      final int top = billableM < up ? billableM : up;
      final int meters = top - prevUp;
      if (meters > 0) {
        scaled += t.pricePerKmVnd * meters * _scalePerMeterPerKm;
      }
      prevUp = up;
    }
    return scaled;
  }

  /// Phu phi dang hieu luc theo thu tu pipeline, gioi han so lop xep chong.
  static List<Surcharge> _activeSurcharges(
    TariffConfigV2 config,
    SurchargeContexts ctx,
  ) {
    final List<Surcharge> ordered = <Surcharge>[];
    for (final String id in config.pipeline.order) {
      for (final Surcharge s in config.surcharges) {
        if (s.id == id && !ordered.contains(s)) ordered.add(s);
      }
    }
    for (final Surcharge s in config.surcharges) {
      if (!ordered.contains(s)) ordered.add(s);
    }
    final List<Surcharge> matched =
        ordered.where((Surcharge s) => s.matches(ctx)).toList();
    final int limit = config.pipeline.allowStacking
        ? config.pipeline.maxStackCount
        : 1;
    if (matched.length > limit) {
      return matched.sublist(0, limit);
    }
    return matched;
  }

  static int _roundScaled(int scaled, RoundingPolicy r) {
    final int unitScaled = r.unitVnd * fareScale;
    final int units;
    switch (r.mode) {
      case RoundingMode.halfUp:
        units = (scaled + unitScaled ~/ 2) ~/ unitScaled;
      case RoundingMode.ceil:
        units = (scaled + unitScaled - 1) ~/ unitScaled;
      case RoundingMode.floor:
        units = scaled ~/ unitScaled;
    }
    return units * r.unitVnd;
  }
}
