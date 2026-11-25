import '../../core/taximeter_engine.dart';
import '../models/gps_sample.dart';
import '../models/tariff_config_v2.dart';

/// Mot chuyen dang chay. THUAN: khong doc dong ho, khong IO. Config duoc chot
/// luc bat dau chuyen va khong doi giua chuyen (cam resolve lai).
///
/// Moi mau GPS tho duoc giu nguyen; cuoc luon = TaximeterEngine.compute tren
/// toan bo mau => khoi phuc sau khi app bi tat cho ket qua y het.
class ActiveTripSession {
  ActiveTripSession({
    required this.tripId,
    required this.startedAtMs,
    required this.config,
    required this.contexts,
    List<GpsSample> samples = const <GpsSample>[],
  }) : _samples = List<GpsSample>.of(samples) {
    _live = _compute(config.rounding.displayMode);
  }

  final String tripId;
  final int startedAtMs;
  final TariffConfigV2 config;
  final SurchargeContexts contexts;
  final List<GpsSample> _samples;
  late FareResult _live;

  List<GpsSample> get samples => List<GpsSample>.unmodifiable(_samples);
  int get sampleCount => _samples.length;

  /// Cuoc hien thi trong chuyen (lam tron theo displayModeDuringTrip).
  FareResult get liveFare => _live;

  GpsSample? get lastSample => _samples.isEmpty ? null : _samples.last;

  void addSample(GpsSample s) {
    _samples.add(s);
    _live = _compute(config.rounding.displayMode);
  }

  /// Cuoc chot khi ket thuc chuyen (lam tron theo config, 1 lan).
  FareResult finalFare() => _compute(null);

  FareResult _compute(RoundingMode? mode) => TaximeterEngine.compute(
        samples: _samples,
        config: config,
        contexts: contexts,
        tripId: tripId,
        roundingModeOverride: mode,
      );
}
