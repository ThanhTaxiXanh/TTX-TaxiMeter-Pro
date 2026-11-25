import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:drift/drift.dart';

import '../../core/taximeter_engine.dart';
import '../../domain/models/gps_sample.dart';
import '../../domain/models/surcharge.dart';
import '../../domain/models/tariff_config_v2.dart';
import '../../domain/tariff/default_tariff.dart';
import '../../domain/trip/active_trip_session.dart';
import '../db/app_database.dart';

/// Chuyen khoi phuc tu snapshot sau khi app bi tat giua chuyen.
class RestoredTrip {
  const RestoredTrip(this.session);
  final ActiveTripSession session;
}

abstract class TripStore {
  /// Bieu gia ACTIVE hien hanh (tao bieu gia mac dinh neu chua co). Chi goi
  /// LUC BAT DAU chuyen.
  Future<TariffConfigV2> resolveActiveTariff(int nowMs);

  /// Ghi them cac mau GPS moi (tu chi so [fromSeq]) + snapshot, 1 transaction.
  Future<void> saveProgress({
    required ActiveTripSession session,
    required int fromSeq,
    required int nowMs,
  });

  Future<RestoredTrip?> loadActive();

  /// Chot chuyen: ghi trip_record + xoa snapshot, 1 transaction.
  Future<void> finishTrip({
    required ActiveTripSession session,
    required int endedAtMs,
    required int nowMs,
  });

  /// Bo chuyen dang chay (khong luu ca trip_record).
  Future<void> discardActive();
}

class DriftTripStore implements TripStore {
  DriftTripStore(this._db);
  final AppDatabase _db;

  @override
  Future<TariffConfigV2> resolveActiveTariff(int nowMs) async {
    final List<QueryRow> rows = await _db.customSelect(
      "SELECT json_body FROM tariff_config WHERE status = 'ACTIVE' "
      'AND effective_from <= ? AND (effective_to IS NULL OR effective_to > ?) '
      'ORDER BY effective_from DESC, config_version DESC LIMIT 1',
      variables: <Variable<Object>>[Variable<int>(nowMs), Variable<int>(nowMs)],
    ).get();
    if (rows.isNotEmpty) {
      return TariffConfigV2.fromJson(jsonDecode(rows.first.read<String>('json_body')));
    }
    final Map<String, dynamic> json = defaultTariffJson(effectiveFromMs: 0);
    final TariffConfigV2 cfg = TariffConfigV2.fromJson(json);
    await _db.customStatement(
      'INSERT INTO tariff_config(config_id, config_version, effective_from, '
      'effective_to, status, json_body, sha256, created_at) '
      "VALUES (?, ?, 0, NULL, 'ACTIVE', ?, ?, ?)",
      <Object?>[cfg.configId, cfg.configVersion, jsonEncode(json), cfg.contentSha256, nowMs],
    );
    return cfg;
  }

  @override
  Future<void> saveProgress({
    required ActiveTripSession session,
    required int fromSeq,
    required int nowMs,
  }) async {
    final List<GpsSample> all = session.samples;
    await _db.transaction(() async {
      for (int i = fromSeq; i < all.length; i++) {
        final GpsSample s = all[i];
        await _db.customStatement(
          'INSERT INTO raw_gps_points(trip_id, seq, ts_ms, lat_e7, lng_e7, '
          'accuracy_mm, speed_mmps, is_mock, source, decision) '
          "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'RAW')",
          <Object?>[
            session.tripId, i, s.tsMs, s.latE7, s.lngE7, s.accuracyMm,
            s.speedMmps, s.isMock ? 1 : 0, s.source,
          ],
        );
      }
      final String state = jsonEncode(<String, Object>{
        'v': 1,
        'contexts': session.contexts.toJson(),
        'sampleCount': all.length,
      });
      await _db.customStatement(
        'INSERT OR REPLACE INTO active_trip_snapshot(id, trip_id, started_at, '
        'config_id, config_version, config_sha256, state_json, updated_at) '
        'VALUES (1, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          session.tripId, session.startedAtMs, session.config.configId,
          session.config.configVersion, session.config.contentSha256, state, nowMs,
        ],
      );
    });
  }

  @override
  Future<RestoredTrip?> loadActive() async {
    final List<QueryRow> snap =
        await _db.customSelect('SELECT * FROM active_trip_snapshot WHERE id = 1').get();
    if (snap.isEmpty) return null;
    final QueryRow r = snap.first;
    final String tripId = r.read<String>('trip_id');

    // Config CHOT cua chuyen: lay dung (id, version), khong resolve lai.
    final List<QueryRow> cfgRows = await _db.customSelect(
      'SELECT json_body, sha256 FROM tariff_config WHERE config_id = ? AND config_version = ?',
      variables: <Variable<Object>>[
        Variable<String>(r.read<String>('config_id')),
        Variable<int>(r.read<int>('config_version')),
      ],
    ).get();
    if (cfgRows.isEmpty) return null;
    final TariffConfigV2 cfg =
        TariffConfigV2.fromJson(jsonDecode(cfgRows.first.read<String>('json_body')));
    if (cfg.contentSha256 != r.read<String>('config_sha256')) return null;

    final Map<String, dynamic> state =
        jsonDecode(r.read<String>('state_json')) as Map<String, dynamic>;
    final List<QueryRow> pts = await _db.customSelect(
      'SELECT ts_ms, lat_e7, lng_e7, accuracy_mm, speed_mmps, is_mock, source '
      'FROM raw_gps_points WHERE trip_id = ? ORDER BY seq',
      variables: <Variable<Object>>[Variable<String>(tripId)],
    ).get();
    final List<GpsSample> samples = pts
        .map((QueryRow p) => GpsSample(
              tsMs: p.read<int>('ts_ms'),
              latE7: p.read<int>('lat_e7'),
              lngE7: p.read<int>('lng_e7'),
              accuracyMm: p.read<int>('accuracy_mm'),
              speedMmps: p.read<int>('speed_mmps'),
              isMock: p.read<int>('is_mock') == 1,
              source: p.read<String>('source'),
            ))
        .toList();
    return RestoredTrip(ActiveTripSession(
      tripId: tripId,
      startedAtMs: r.read<int>('started_at'),
      config: cfg,
      contexts: SurchargeContexts.fromJson(state['contexts']),
      samples: samples,
    ));
  }

  @override
  Future<void> finishTrip({
    required ActiveTripSession session,
    required int endedAtMs,
    required int nowMs,
  }) async {
    final FareResult fare = session.finalFare();
    final List<GpsSample> all = session.samples;
    final String rawHash = crypto.sha256
        .convert(utf8.encode(jsonEncode(all.map((GpsSample s) => s.toJson()).toList())))
        .toString();
    final GpsSample? first = all.isEmpty ? null : all.first;
    final GpsSample? last = all.isEmpty ? null : all.last;
    await _db.transaction(() async {
      await _db.customStatement(
        'INSERT INTO trip_record(trip_id, started_at, ended_at, duration_sec, '
        'distance_m, waiting_sec, fare_opening_vnd, fare_distance_vnd, '
        'fare_waiting_vnd, fare_surcharge_vnd, fare_total_vnd, config_id, '
        'config_version, config_sha256, fare_hash, raw_points_hash, start_lat_e7, '
        'start_lng_e7, end_lat_e7, end_lng_e7, created_at) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        <Object?>[
          session.tripId, session.startedAtMs, endedAtMs,
          (endedAtMs - session.startedAtMs) ~/ 1000,
          fare.distanceM, fare.waitingSec, fare.fareOpening, fare.fareDistance,
          fare.fareWaiting, fare.fareSurcharge, fare.fareTotal,
          session.config.configId, session.config.configVersion,
          session.config.contentSha256, fare.fareHash, rawHash,
          first?.latE7, first?.lngE7, last?.latE7, last?.lngE7, nowMs,
        ],
      );
      await _db.customStatement(
        'INSERT INTO raw_trace_meta(trip_id, point_count, accepted_count, size_bytes) '
        'VALUES (?,?,?,?)',
        <Object?>[session.tripId, all.length, fare.acceptedCount, all.length * 48],
      );
      await _db.customStatement('DELETE FROM active_trip_snapshot WHERE id = 1');
    });
  }

  @override
  Future<void> discardActive() async {
    await _db.transaction(() async {
      final List<QueryRow> snap =
          await _db.customSelect('SELECT trip_id FROM active_trip_snapshot WHERE id = 1').get();
      if (snap.isNotEmpty) {
        await _db.customStatement(
            'DELETE FROM raw_gps_points WHERE trip_id = ?', <Object?>[snap.first.read<String>('trip_id')]);
      }
      await _db.customStatement('DELETE FROM active_trip_snapshot WHERE id = 1');
    });
  }
}
