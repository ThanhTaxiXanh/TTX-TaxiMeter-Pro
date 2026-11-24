// PURE: cau hinh bieu gia TariffConfigV2, chi so nguyen.
//
// Don vi: met, giay, VND, permille (he so x 1000), km/h nguyen.

enum CalibrationMode {
  /// Hieu chuan truoc khi tru quang duong gom trong gia mo cua:
  /// billable = max(0, raw * f ~/ 1000 - includedMeters).
  beforeOpeningKm,

  /// Tru quang duong gom truoc, hieu chuan phan con lai:
  /// billable = max(0, raw - includedMeters) * f ~/ 1000.
  afterOpeningKm,
}

enum WaitingCounting {
  /// Tinh theo tung giay (sau khi tru grace).
  perSecond,

  /// Lam tron xuong theo phut tron cua moi dot cho.
  perFullMinuteFloor,

  /// Lam tron len theo phut cua moi dot cho (neu con du > 0 giay).
  perMinuteCeil,
}

enum SurchargeKind { multiplier, fixed }

enum RoundingMode { halfUp, up, down }

class OpeningPolicy {
  const OpeningPolicy({required this.fareVnd, required this.includedMeters});

  final int fareVnd;
  final int includedMeters;
}

class DistanceTier {
  const DistanceTier({required this.upToMeters, required this.ratePerKmVnd});

  /// Bien tren (inclusive) tinh theo tong billableM. null = khong gioi han
  /// (chi cho phep o bac cuoi cung).
  final int? upToMeters;
  final int ratePerKmVnd;
}

class WaitingPolicy {
  const WaitingPolicy({
    required this.enterThresholdKmh,
    required this.exitThresholdKmh,
    required this.graceSeconds,
    required this.ratePerMinVnd,
    required this.counting,
  });

  /// Vao WAITING khi toc do < enterThresholdKmh.
  final int enterThresholdKmh;

  /// Ra khoi WAITING khi toc do > exitThresholdKmh (phai > enter).
  final int exitThresholdKmh;
  final int graceSeconds;
  final int ratePerMinVnd;
  final WaitingCounting counting;
}

class Surcharge {
  const Surcharge({
    required this.name,
    required this.kind,
    this.permille = 1000,
    this.fixedVnd = 0,
  });

  final String name;
  final SurchargeKind kind;

  /// Dung cho multiplier (1000 = x1.0, 1200 = x1.2).
  final int permille;

  /// Dung cho fixed.
  final int fixedVnd;
}

class RoundingPolicy {
  const RoundingPolicy({required this.mode, required this.stepVnd});

  final RoundingMode mode;

  /// Buoc lam tron (1 = khong lam tron them, 500, 1000...).
  final int stepVnd;
}

class TariffConfigV2 {
  const TariffConfigV2({
    required this.configId,
    required this.configVersion,
    required this.calibrationFactorPermille,
    required this.calibrationMode,
    required this.opening,
    required this.tiers,
    required this.waiting,
    required this.surcharges,
    required this.rounding,
  });

  final String configId;
  final int configVersion;
  final int calibrationFactorPermille;
  final CalibrationMode calibrationMode;
  final OpeningPolicy opening;

  /// Sap xep tang dan theo upToMeters; bac cuoi co upToMeters == null.
  final List<DistanceTier> tiers;
  final WaitingPolicy waiting;
  final List<Surcharge> surcharges;
  final RoundingPolicy rounding;
}
