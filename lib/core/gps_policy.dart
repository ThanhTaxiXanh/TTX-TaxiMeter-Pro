// PURE: khong doc dong ho he thong, khong ngau nhien, khong I/O.
// Thoi gian lay tu tsMs cua diem. Chi so nguyen.
// Xem .github/skills/gps-and-offline-map/SKILL.md.

import '../domain/models/gps_sample.dart';
import '../domain/models/tariff_config_v2.dart';
import 'geo.dart';

enum GpsDecision { accepted, rejected, paused }

class GpsPolicyConfig {
  const GpsPolicyConfig({
    this.maxSpeedKmh = 120,
    this.strictAccuracyMm = 20000,
    this.relaxedAccuracyMm = 35000,
    this.relaxAfterMs = 10000,
    this.pauseAfterMs = 30000,
    this.minTeleportDtMs = 500,
    this.anchorEnabled = true,
    this.anchorMaxSpeedMmps = 1500,
    this.anchorMinAccuracyMm = 8000,
    this.anchorRadiusPermille = 2000,
    this.anchorMaxAgeMs = 30000,
  });

  factory GpsPolicyConfig.fromRules(GpsRules r) {
    return GpsPolicyConfig(
      maxSpeedKmh: r.maxSpeedKmh,
      strictAccuracyMm: r.maxAccuracyMm,
      relaxedAccuracyMm: r.relaxedAccuracyMm,
      anchorEnabled: r.anchorEnabled,
      anchorMaxSpeedMmps: r.anchorMaxSpeedMmps,
      anchorRadiusPermille: r.anchorRadiusPermille,
      anchorMaxAgeMs: r.anchorMaxAgeMs,
    );
  }

  final int maxSpeedKmh;
  final int strictAccuracyMm;
  final int relaxedAccuracyMm;

  /// Mat GPS (tu diem ACCEPTED cuoi) >= relaxAfterMs thi noi nguong sang relaxed.
  final int relaxAfterMs;

  /// Mat GPS >= pauseAfterMs ma van khong du do chinh xac -> PAUSED.
  final int pauseAfterMs;
  final int minTeleportDtMs;
  final bool anchorEnabled;
  final int anchorMaxSpeedMmps;
  final int anchorMinAccuracyMm;

  /// Ban kinh chong troi = anchorRadiusPermille/1000 x accuracy.
  final int anchorRadiusPermille;

  /// Neo cu hon so nay (tinh tu lan xac nhan gan nhat) thi bo qua guard.
  final int anchorMaxAgeMs;
}

/// Trang thai bat bien; moi lan evaluate tra trang thai moi.
class GpsPolicyState {
  const GpsPolicyState({
    this.prevTsMs,
    this.lastAccepted,
    this.anchorRefreshTsMs,
    this.window = const <GpsSample>[],
  });

  /// Moc thoi gian cua mau hop le gan nhat (bat ke quyet dinh).
  final int? prevTsMs;

  /// Diem ACCEPTED cuoi cung (cung la anchor chong troi).
  final GpsSample? lastAccepted;

  /// Lan cuoi anchor duoc "xac nhan" (nhan diem moi hoac loai diem do troi).
  final int? anchorRefreshTsMs;

  /// Toi da 3 mau ACCEPTED gan nhat de lam muot.
  final List<GpsSample> window;
}

class GpsEvaluation {
  const GpsEvaluation({
    required this.decision,
    required this.state,
    this.rejectReason,
    this.suspicious = false,
    this.smoothedLatE7,
    this.smoothedLngE7,
  });

  final GpsDecision decision;
  final GpsPolicyState state;
  final String? rejectReason;
  final bool suspicious;

  /// Toa do lam muot, CHI de hien thi ban do. Tinh cuoc dung toa do tho.
  final int? smoothedLatE7;
  final int? smoothedLngE7;
}

class GpsPolicy {
  const GpsPolicy._();

  static const int _weightNumerator = 100000000000000; // 1e14

  static GpsEvaluation evaluate(
    GpsPolicyState state,
    GpsSample s,
    GpsPolicyConfig cfg,
  ) {
    // Tang 1: sanity.
    final bool badCoord = s.latE7 < -900000000 ||
        s.latE7 > 900000000 ||
        s.lngE7 < -1800000000 ||
        s.lngE7 > 1800000000;
    final int? prev = state.prevTsMs;
    final bool badTs = prev != null && s.tsMs <= prev;
    if (badCoord || badTs) {
      return GpsEvaluation(
        decision: GpsDecision.rejected,
        state: state,
        rejectReason: badCoord ? 'SANITY_COORD' : 'SANITY_TS',
      );
    }

    // Tang 2: mock -> co SUSPICIOUS, van tiep tuc xet.
    final bool suspicious = s.isMock;

    final GpsSample? last = state.lastAccepted;
    final GpsPolicyState seen = GpsPolicyState(
      prevTsMs: s.tsMs,
      lastAccepted: last,
      anchorRefreshTsMs: state.anchorRefreshTsMs,
      window: state.window,
    );

    // Tang 3: accuracy thich ung theo thoi gian mat GPS.
    final int gapMs = last == null ? 0 : s.tsMs - last.tsMs;
    final int limit = gapMs < cfg.relaxAfterMs
        ? cfg.strictAccuracyMm
        : cfg.relaxedAccuracyMm;
    if (s.accuracyMm > limit) {
      final bool pause = last != null && gapMs >= cfg.pauseAfterMs;
      return GpsEvaluation(
        decision: pause ? GpsDecision.paused : GpsDecision.rejected,
        state: seen,
        rejectReason: pause ? 'ACCURACY_PAUSED' : 'ACCURACY',
        suspicious: suspicious,
      );
    }

    if (last != null) {
      final int distMm = distanceMm(
        last.latE7,
        last.lngE7,
        s.latE7,
        s.lngE7,
      );

      // Tang 4: teleport (chi khi dt >= 0.5 s).
      if (gapMs >= cfg.minTeleportDtMs) {
        final int impliedMmps = distMm * 1000 ~/ gapMs;
        final int maxMmps = cfg.maxSpeedKmh * 1000000 ~/ 3600;
        if (impliedMmps > maxMmps) {
          return GpsEvaluation(
            decision: GpsDecision.rejected,
            state: seen,
            rejectReason: 'TELEPORT',
            suspicious: suspicious,
          );
        }
      }

      // Tang 5: anchor drift (dung yen + accuracy xau + nam trong vung nhieu).
      // Toc do am (khong biet) -> suy ra tu vi tri so voi anchor.
      if (cfg.anchorEnabled) {
        final int refresh = state.anchorRefreshTsMs ?? last.tsMs;
        final int ageMs = s.tsMs - refresh;
        final int speed = s.speedMmps >= 0
            ? s.speedMmps
            : (gapMs > 0 ? distMm * 1000 ~/ gapMs : 0);
        if (ageMs <= cfg.anchorMaxAgeMs &&
            speed < cfg.anchorMaxSpeedMmps &&
            s.accuracyMm > cfg.anchorMinAccuracyMm &&
            distMm * 1000 < cfg.anchorRadiusPermille * s.accuracyMm) {
          return GpsEvaluation(
            decision: GpsDecision.rejected,
            state: GpsPolicyState(
              prevTsMs: s.tsMs,
              lastAccepted: last,
              anchorRefreshTsMs: s.tsMs,
              window: state.window,
            ),
            rejectReason: 'ANCHOR_DRIFT',
            suspicious: suspicious,
          );
        }
      }
    }

    // Tang 6: lam muot cua so 3 mau, trong so 1/accuracy^2 (chi de hien thi).
    final List<GpsSample> win = <GpsSample>[...state.window, s];
    if (win.length > 3) {
      win.removeAt(0);
    }
    int sumW = 0;
    int sumLat = 0;
    int sumLng = 0;
    for (final GpsSample w in win) {
      final int acc = w.accuracyMm < 1000 ? 1000 : w.accuracyMm;
      final int weight = _weightNumerator ~/ (acc * acc);
      sumW += weight;
      sumLat += weight * w.latE7;
      sumLng += weight * w.lngE7;
    }
    final int latS = sumW == 0 ? s.latE7 : sumLat ~/ sumW;
    final int lngS = sumW == 0 ? s.lngE7 : sumLng ~/ sumW;

    return GpsEvaluation(
      decision: GpsDecision.accepted,
      state: GpsPolicyState(
        prevTsMs: s.tsMs,
        lastAccepted: s,
        anchorRefreshTsMs: s.tsMs,
        window: List<GpsSample>.unmodifiable(win),
      ),
      suspicious: suspicious,
      smoothedLatE7: latS,
      smoothedLngE7: lngS,
    );
  }
}
