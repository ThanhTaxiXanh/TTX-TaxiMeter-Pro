// PURE: khong doc dong ho he thong, khong ngau nhien, khong I/O.
// Chi so nguyen. Xem .github/skills/taximeter-engine/SKILL.md.

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'geo.dart';
import 'tariff_config.dart';

/// Thang trung gian: VND x 60000. Lam tron dung 1 lan o buoc cuoi.
const int fareScale = 60000;

/// Diem GPS da duoc GpsPolicy chap nhan (toa do da lam muot).
class AcceptedPoint {
  const AcceptedPoint({
    required this.tsMs,
    required this.latE7,
    required this.lngE7,
    required this.speedMmps,
  });

  final int tsMs;
  final int latE7;
  final int lngE7;
  final int speedMmps;
}

class FareResult {
  const FareResult({
    required this.distanceM,
    required this.calibratedM,
    required this.billableM,
    required this.waitingSec,
    required this.waitingBillableSec,
    required this.fareOpeningVnd,
    required this.fareDistanceVnd,
    required this.fareWaitingVnd,
    required this.fareSurchargeVnd,
    required this.fareTotalVnd,
    required this.fareHash,
  });

  /// Tong quang duong tho giua cac diem ACCEPTED (m, nguyen).
  final int distanceM;
  final int calibratedM;
  final int billableM;

  /// Tong thoi gian o trang thai WAITING (giay, cat xuong).
  final int waitingSec;

  /// So giay cho bi tinh tien (sau grace va counting policy).
  final int waitingBillableSec;
  final int fareOpeningVnd;
  final int fareDistanceVnd;
  final int fareWaitingVnd;

  /// Thanh phan thong tin: = total - (opening + distance + waiting), da gom
  /// phan phu phi va chenh lech do lam tron mot lan cuoi. `fareTotalVnd` la
  /// so co tham quyen.
  final int fareSurchargeVnd;
  final int fareTotalVnd;
  final String fareHash;

  @override
  bool operator ==(Object other) =>
      other is FareResult &&
      other.distanceM == distanceM &&
      other.calibratedM == calibratedM &&
      other.billableM == billableM &&
      other.waitingSec == waitingSec &&
      other.waitingBillableSec == waitingBillableSec &&
      other.fareOpeningVnd == fareOpeningVnd &&
      other.fareDistanceVnd == fareDistanceVnd &&
      other.fareWaitingVnd == fareWaitingVnd &&
      other.fareSurchargeVnd == fareSurchargeVnd &&
      other.fareTotalVnd == fareTotalVnd &&
      other.fareHash == fareHash;

  @override
  int get hashCode => fareHash.hashCode;

  @override
  String toString() =>
      'FareResult(distanceM: $distanceM, waitingSec: $waitingSec, '
      'total: $fareTotalVnd, hash: $fareHash)';
}

class TaximeterEngine {
  const TaximeterEngine._();

  /// fareHash = sha256(configSha256 + fareTotalVnd + tripId), noi chuoi
  /// thap phan, UTF-8, khong dau phan cach.
  static String fareHash({
    required String configSha256,
    required int fareTotalVnd,
    required String tripId,
  }) {
    final List<int> bytes = utf8.encode('$configSha256$fareTotalVnd$tripId');
    return sha256.convert(bytes).toString();
  }

  static FareResult compute({
    required List<AcceptedPoint> points,
    required TariffConfigV2 config,
    required String configSha256,
    required String tripId,
  }) {
    // 1. Quang duong tich luy (mm -> m, cat xuong).
    int totalMm = 0;
    for (int i = 1; i < points.length; i++) {
      totalMm += distanceMm(
        points[i - 1].latE7,
        points[i - 1].lngE7,
        points[i].latE7,
        points[i].lngE7,
      );
    }
    final int distanceM = totalMm ~/ 1000;

    // 2-3. Hieu chuan va quang duong tinh tien.
    final int f = config.calibrationFactorPermille;
    final int inc = config.opening.includedMeters;
    final int calibratedM;
    final int billableM;
    switch (config.calibrationMode) {
      case CalibrationMode.beforeOpeningKm:
        calibratedM = distanceM * f ~/ 1000;
        billableM = _max0(calibratedM - inc);
      case CalibrationMode.afterOpeningKm:
        calibratedM = distanceM * f ~/ 1000;
        billableM = _max0(distanceM - inc) * f ~/ 1000;
    }

    // 4. Luy tien bac thang (thang fareScale).
    final int distScaled = _tieredScaled(billableM, config.tiers);

    // 5. Cho (hysteresis + grace + counting).
    final _Waiting w = _waiting(points, config.waiting);
    final int waitScaled = w.billableSec * config.waiting.ratePerMinVnd * 1000;

    // 6. Gia co ban.
    final int openingScaled = config.opening.fareVnd * fareScale;
    int scaled = openingScaled + distScaled + waitScaled;

    // 7. Phu phi: nhan permille lien tiep, sau do cong co dinh.
    for (final Surcharge s in config.surcharges) {
      if (s.kind == SurchargeKind.multiplier) {
        scaled = scaled * s.permille ~/ 1000;
      }
    }
    for (final Surcharge s in config.surcharges) {
      if (s.kind == SurchargeKind.fixed) {
        scaled += s.fixedVnd * fareScale;
      }
    }

    // 8. Lam tron dung mot lan.
    final int total = _roundScaled(scaled, config.rounding);

    final int fareDistanceVnd = distScaled ~/ fareScale;
    final int fareWaitingVnd = waitScaled ~/ fareScale;
    final int fareOpeningVnd = config.opening.fareVnd;
    final int surchargePart =
        total - (fareOpeningVnd + fareDistanceVnd + fareWaitingVnd);

    return FareResult(
      distanceM: distanceM,
      calibratedM: calibratedM,
      billableM: billableM,
      waitingSec: w.rawSec,
      waitingBillableSec: w.billableSec,
      fareOpeningVnd: fareOpeningVnd,
      fareDistanceVnd: fareDistanceVnd,
      fareWaitingVnd: fareWaitingVnd,
      fareSurchargeVnd: surchargePart,
      fareTotalVnd: total,
      fareHash: fareHash(
        configSha256: configSha256,
        fareTotalVnd: total,
        tripId: tripId,
      ),
    );
  }

  static int _max0(int v) => v < 0 ? 0 : v;

  static int _tieredScaled(int billableM, List<DistanceTier> tiers) {
    int scaled = 0;
    int prevUp = 0;
    for (final DistanceTier t in tiers) {
      if (billableM <= prevUp) break;
      final int up = t.upToMeters ?? billableM;
      final int top = billableM < up ? billableM : up;
      final int meters = top - prevUp;
      if (meters > 0) {
        // rate VND/km * m / 1000 VND = rate * m * 60 / fareScale.
        scaled += t.ratePerKmVnd * meters * 60;
      }
      prevUp = up;
    }
    return scaled;
  }

  static int _roundScaled(int scaled, RoundingPolicy r) {
    final int step = r.stepVnd < 1 ? 1 : r.stepVnd;
    final int stepScaled = step * fareScale;
    final int units;
    switch (r.mode) {
      case RoundingMode.halfUp:
        units = (scaled + stepScaled ~/ 2) ~/ stepScaled;
      case RoundingMode.up:
        units = (scaled + stepScaled - 1) ~/ stepScaled;
      case RoundingMode.down:
        units = scaled ~/ stepScaled;
    }
    return units * step;
  }

  /// Trang thai cho tai diem i ap dung cho khoang (i-1, i].
  static _Waiting _waiting(List<AcceptedPoint> pts, WaitingPolicy p) {
    final int enterMmps = p.enterThresholdKmh * 1000000 ~/ 3600;
    final int exitMmps = p.exitThresholdKmh * 1000000 ~/ 3600;
    final int graceMs = p.graceSeconds * 1000;

    bool waiting = false;
    int episodeMs = 0;
    int rawMs = 0;
    int billableSec = 0;

    int closeEpisode(int ms) {
      final int over = ms - graceMs;
      if (over <= 0) return 0;
      switch (p.counting) {
        case WaitingCounting.perSecond:
          return over ~/ 1000;
        case WaitingCounting.perFullMinuteFloor:
          return (over ~/ 60000) * 60;
        case WaitingCounting.perMinuteCeil:
          return ((over + 59999) ~/ 60000) * 60;
      }
    }

    for (int i = 1; i < pts.length; i++) {
      final int speed = pts[i].speedMmps;
      if (!waiting && speed < enterMmps) {
        waiting = true;
      } else if (waiting && speed > exitMmps) {
        waiting = false;
        billableSec += closeEpisode(episodeMs);
        episodeMs = 0;
      }
      if (waiting) {
        final int dt = pts[i].tsMs - pts[i - 1].tsMs;
        if (dt > 0) {
          episodeMs += dt;
          rawMs += dt;
        }
      }
    }
    if (waiting) {
      billableSec += closeEpisode(episodeMs);
    }
    return _Waiting(rawMs ~/ 1000, billableSec);
  }
}

class _Waiting {
  const _Waiting(this.rawSec, this.billableSec);

  final int rawSec;
  final int billableSec;
}
