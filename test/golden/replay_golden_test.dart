import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ttx/core/taximeter_engine.dart';
import 'package:ttx/domain/models/tariff_config_v2.dart';
import 'package:ttx/domain/models/gps_sample.dart';

void main() {
  final fixturesDir = Directory('test/fixtures');
  final fixtures = fixturesDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  // Cache config từ fixture đầu tiên để các fixture khác kế thừa
  late TariffConfigV2 sharedConfig;

  group('Golden fixtures — engine correctness', () {
    setUpAll(() {
      final first = jsonDecode(
        fixtures.firstWhere((f) => f.path.contains('trip_001')).readAsStringSync(),
      );
      sharedConfig = TariffConfigV2.fromJson(first['config']);
    });

    for (final file in fixtures) {
      final fixture = jsonDecode(file.readAsStringSync());
      final name = file.uri.pathSegments.last.replaceAll('.json', '');

      test('$name — fares match expected', () {
        final config = fixture['config'] is Map
            ? TariffConfigV2.fromJson(fixture['config'])
            : sharedConfig;

        final samples = (fixture['samples'] as List)
            .map((s) => GpsSample.fromJson(s))
            .toList();

        final contexts = SurchargeContexts.fromJson(fixture['contexts']);
        final expected = fixture['expected'];

        final result = TaximeterEngine.compute(
          samples: samples,
          config: config,
          contexts: contexts,
        );

        // Distance với tolerance
        expect(
          result.distanceM,
          closeTo(expected['distance_m_approx'], expected['distance_tolerance_m']),
        );

        // Waiting (exact)
        expect(result.waitingSec, equals(expected['waiting_sec']));

        // Fare breakdown: opening & waiting & surcharge phải exact
        expect(result.fareOpening, equals(expected['fare_opening_vnd']));
        expect(result.fareWaiting, equals(expected['fare_waiting_vnd']));
        expect(result.fareSurcharge, equals(expected['fare_surcharge_vnd']));

        // fareDistance có tolerance vì phụ thuộc formula distance
        if (expected['fare_distance_vnd_approx'] != null) {
          expect(
            result.fareDistance,
            closeTo(
              expected['fare_distance_vnd_approx'],
              expected['fare_distance_vnd_tolerance'] ?? 0,
            ),
          );
        }

        // FARE TOTAL — PHẢI KHỚP CHÍNH XÁC (đây là con số khách trả)
        expect(result.fareTotal, equals(expected['fare_total_vnd']),
            reason: 'Fare total phải khớp chính xác với expected');
      });

      // E8: Replay phải khớp live byte-for-byte
      test('$name — E8 replay must match live', () {
        final config = fixture['config'] is Map
            ? TariffConfigV2.fromJson(fixture['config'])
            : sharedConfig;
        final samples = (fixture['samples'] as List)
            .map((s) => GpsSample.fromJson(s))
            .toList();
        final contexts = SurchargeContexts.fromJson(fixture['contexts']);

        final live = TaximeterEngine.compute(
            samples: samples, config: config, contexts: contexts);
        final replay = TaximeterEngine.compute(
            samples: samples, config: config, contexts: contexts);

        // So sánh TỪNG TRƯỜNG, không chỉ tổng
        expect(replay.fareTotal, equals(live.fareTotal));
        expect(replay.fareOpening, equals(live.fareOpening));
        expect(replay.fareDistance, equals(live.fareDistance));
        expect(replay.fareWaiting, equals(live.fareWaiting));
        expect(replay.fareSurcharge, equals(live.fareSurcharge));
        expect(replay.distanceM, equals(live.distanceM));
        expect(replay.waitingSec, equals(live.waitingSec));
        expect(replay.fareHash, equals(live.fareHash));
      });
    }
  });
}