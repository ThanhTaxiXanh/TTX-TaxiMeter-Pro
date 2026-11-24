// Golden replay: 5 chuyen that (GPX -> CSV so nguyen) chay qua
// TaximeterEngine.compute (GpsPolicy -> engine), so khop byte-for-byte voi
// test/golden/<slug>.expected.json.
//
// Bieu gia: lay config cua test/fixtures/trip_001 (cac fixture khac ke thua).
// GPX khong co accuracy -> co dinh 5 m.
// Ket qua mong doi chi duoc cap nhat co chu dich (ghi ly do trong
// docs/CONTEXT_STATE.md).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ttx/core/taximeter_engine.dart';
import 'package:ttx/domain/models/gps_sample.dart';
import 'package:ttx/domain/models/tariff_config_v2.dart';

const List<String> slugs = <String>[
  'da_mai_20261122',
  'ngo388_nguyen_thi_luu_20261122',
  'xuong_giang_422_20261122',
  'than_canh_van_20261121',
  'tran_nguyen_han_20261124',
];

const int gpxAccuracyMm = 5000;

List<GpsSample> loadCsv(String slug) {
  final List<String> lines = File('test/golden/$slug.csv').readAsLinesSync();
  final List<GpsSample> out = <GpsSample>[];
  for (final String line in lines.skip(1)) {
    if (line.isEmpty) continue;
    final List<int> v = line.split(',').map(int.parse).toList();
    out.add(GpsSample(
      tsMs: v[0],
      latE7: v[1],
      lngE7: v[2],
      accuracyMm: gpxAccuracyMm,
      speedMmps: v[3],
      source: 'GPX',
    ));
  }
  return out;
}

TariffConfigV2 loadConfig() {
  final dynamic first = jsonDecode(
    File('test/fixtures/trip_001_short_2km_daytime.json').readAsStringSync(),
  );
  return TariffConfigV2.fromJson(first['config']);
}

/// Doi chieu doc lap (chi dung trong test): haversine tren tat ca diem tho.
int haversineRefM(List<GpsSample> raw) {
  const double r = 6371000;
  double total = 0;
  for (int i = 1; i < raw.length; i++) {
    final double la1 = raw[i - 1].latE7 / 1e7 * math.pi / 180;
    final double la2 = raw[i].latE7 / 1e7 * math.pi / 180;
    final double dLa = la2 - la1;
    final double dLo = (raw[i].lngE7 - raw[i - 1].lngE7) / 1e7 * math.pi / 180;
    final double a = math.pow(math.sin(dLa / 2), 2).toDouble() +
        math.cos(la1) * math.cos(la2) * math.pow(math.sin(dLo / 2), 2).toDouble();
    total += 2 * r * math.asin(math.sqrt(a));
  }
  return total.round();
}

FareResult replay(String slug, List<GpsSample> raw, TariffConfigV2 config) {
  return TaximeterEngine.compute(
    samples: raw,
    config: config,
    contexts: SurchargeContexts(
      tripStartTimeMs: raw.first.tsMs,
      timezone: 'Asia/Ho_Chi_Minh',
      vehicleType: 'CAR_4',
      geofenceMatches: const <String>[],
    ),
    tripId: slug,
  );
}

void main() {
  final TariffConfigV2 config = loadConfig();
  for (final String slug in slugs) {
    test('real trip replay: $slug', () {
      final List<GpsSample> raw = loadCsv(slug);
      expect(raw.length, greaterThan(500));

      final FareResult a = replay(slug, raw, config);
      final FareResult b = replay(slug, raw, config);
      expect(a.toString(), equals(b.toString()),
          reason: 'replay hai lan phai y het');

      // Doi chieu doc lap: quang duong engine ~ haversine (bo cac doan cho
      // nen co the hut mot it, khong duoc dai hon).
      final int ref = haversineRefM(raw);
      // ignore: avoid_print
      print('GOLDEN_JSON ${jsonEncode(<String, Object>{'slug': slug, ...a.toJson()})} ref_m=$ref');
      expect(a.distanceM, lessThanOrEqualTo(ref * 1005 ~/ 1000));
      expect(a.distanceM, greaterThanOrEqualTo(ref * 95 ~/ 100));

      final File expected = File('test/golden/$slug.expected.json');
      expect(
        expected.existsSync(),
        isTrue,
        reason: 'thieu $slug.expected.json: golden phai duoc ghi lai co chu dich',
      );
      expect(
        jsonEncode(<String, Object>{'slug': slug, ...a.toJson()}),
        equals(expected.readAsStringSync().trim()),
      );
    });
  }
}
