// Mau GPS tho (tu cam bien hoac fixture). Chi so nguyen.

class GpsSample {
  const GpsSample({
    required this.tsMs,
    required this.latE7,
    required this.lngE7,
    required this.accuracyMm,
    required this.speedMmps,
    this.isMock = false,
    this.source = 'FUSED',
  });

  /// `json` la Map doc tu JSON (kieu dynamic) voi cac khoa: ts_ms, lat_e7,
  /// lng_e7, accuracy_mm, speed_mmps, is_mock, source.
  factory GpsSample.fromJson(dynamic json) {
    final Map<String, dynamic> m = json as Map<String, dynamic>;
    return GpsSample(
      tsMs: m['ts_ms'] as int,
      latE7: m['lat_e7'] as int,
      lngE7: m['lng_e7'] as int,
      accuracyMm: m['accuracy_mm'] as int,
      speedMmps: m['speed_mmps'] as int,
      isMock: (m['is_mock'] as bool?) ?? false,
      source: (m['source'] as String?) ?? 'UNKNOWN',
    );
  }

  final int tsMs;
  final int latE7;
  final int lngE7;
  final int accuracyMm;

  /// Toc do mm/s; am (vd -1) = khong biet, engine tu suy ra tu vi tri/thoi gian.
  final int speedMmps;
  final bool isMock;
  final String source;

  Map<String, Object> toJson() => <String, Object>{
        'ts_ms': tsMs,
        'lat_e7': latE7,
        'lng_e7': lngE7,
        'accuracy_mm': accuracyMm,
        'speed_mmps': speedMmps,
        'is_mock': isMock,
        'source': source,
      };
}
