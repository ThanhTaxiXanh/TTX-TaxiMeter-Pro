import 'package:drift/drift.dart' show QueryRow, Variable;

import '../db/app_database.dart';
import 'trip_models.dart';

const List<String> tombstoneReasons = <String>['DUPLICATE', 'TEST', 'WRONG_ENTRY', 'OTHER'];

/// Xoa vinh vien = chen tombstone + xoa trip_record TRONG CUNG 1 transaction.
class TombstoneRepository {
  TombstoneRepository(this._db);
  final AppDatabase _db;

  Future<void> deletePermanently({
    required String tripId,
    required String reason,
    String? note,
    required int nowMs,
  }) async {
    if (!tombstoneReasons.contains(reason)) {
      throw ArgumentError('Ly do xoa khong hop le: $reason');
    }
    await _db.transaction(() async {
      final List<QueryRow> t = await _db.customSelect(
        'SELECT r.*, p.method AS pay_method, p.state AS pay_state, '
        'p.bank_bin AS p_bin, p.bank_account AS p_acc, p.account_holder AS p_holder '
        'FROM trip_record r LEFT JOIN trip_payment p ON p.trip_id = r.trip_id '
        'WHERE r.trip_id = ?',
        variables: <Variable<Object>>[Variable<String>(tripId)],
      ).get();
      if (t.isEmpty) throw StateError('Khong tim thay chuyen $tripId');
      final QueryRow r = t.first;

      // 1) Bia mo truoc (trigger chan DELETE neu thieu).
      await _db.customStatement(
        'INSERT OR IGNORE INTO trip_tombstone(trip_id, deleted_at, deleted_reason, '
        'deleted_note, trip_started_at, trip_ended_at, duration_sec, distance_m, '
        'waiting_sec, fare_opening_vnd, fare_distance_vnd, fare_waiting_vnd, '
        'fare_surcharge_vnd, fare_total_vnd, payment_method, payment_state, '
        'config_id, config_version, config_sha256, fare_hash, raw_points_hash, '
        'bank_bin, bank_account, account_holder, driver_note) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        <Object?>[
          tripId, nowMs, reason, note,
          r.read<int>('started_at'), r.read<int>('ended_at'),
          r.read<int>('duration_sec'), r.read<int>('distance_m'),
          r.read<int>('waiting_sec'), r.read<int>('fare_opening_vnd'),
          r.read<int>('fare_distance_vnd'), r.read<int>('fare_waiting_vnd'),
          r.read<int>('fare_surcharge_vnd'), r.read<int>('fare_total_vnd'),
          r.readNullable<String>('pay_method'), r.readNullable<String>('pay_state'),
          r.read<String>('config_id'), r.read<int>('config_version'),
          r.read<String>('config_sha256'), r.read<String>('fare_hash'),
          r.readNullable<String>('raw_points_hash'),
          r.readNullable<String>('p_bin'), r.readNullable<String>('p_acc'),
          r.readNullable<String>('p_holder'), r.readNullable<String>('note'),
        ],
      );
      // Neu chuyen da tung duoc khoi phuc tu bia mo -> bo dau "da khoi phuc".
      await _db.customStatement(
          'UPDATE trip_tombstone SET restored_at = NULL WHERE trip_id = ?', <Object?>[tripId]);

      // 2) Du lieu phu thuoc.
      for (final String table in <String>[
        'trip_adjustment', 'trip_payment', 'raw_gps_points', 'raw_trace_meta'
      ]) {
        await _db.customStatement('DELETE FROM $table WHERE trip_id = ?', <Object?>[tripId]);
      }
      // 3) Cuoi cung moi xoa chuyen.
      await _db.customStatement('DELETE FROM trip_record WHERE trip_id = ?', <Object?>[tripId]);
    });
  }

  TombstoneItem _item(QueryRow r) => TombstoneItem(
        tripId: r.read<String>('trip_id'),
        deletedAt: r.read<int>('deleted_at'),
        deletedReason: r.read<String>('deleted_reason'),
        deletedNote: r.readNullable<String>('deleted_note'),
        tripStartedAt: r.read<int>('trip_started_at'),
        tripEndedAt: r.read<int>('trip_ended_at'),
        distanceM: r.readNullable<int>('distance_m'),
        fareTotalVnd: r.read<int>('fare_total_vnd'),
        paymentMethod: r.readNullable<String>('payment_method'),
        paymentState: r.readNullable<String>('payment_state'),
        reconciled: r.read<int>('reconciled') == 1,
        reconciledAt: r.readNullable<int>('reconciled_at'),
        reconciliationNote: r.readNullable<String>('reconciliation_note'),
        restoredAt: r.readNullable<int>('restored_at'),
      );

  Future<List<TombstoneItem>> list({bool? reconciled}) async {
    final String where = reconciled == null ? '' : 'WHERE reconciled = ${reconciled ? 1 : 0}';
    final List<QueryRow> rows = await _db
        .customSelect('SELECT * FROM trip_tombstone $where ORDER BY trip_started_at DESC')
        .get();
    return rows.map(_item).toList();
  }

  /// Doi soat: chi sua cac cot reconciled*, ghi chu (trigger cho phep).
  Future<void> setReconciled({
    required String tripId,
    required bool reconciled,
    String? note,
    required int nowMs,
  }) async {
    await _db.customStatement(
      'UPDATE trip_tombstone SET reconciled = ?, reconciled_at = ?, reconciliation_note = ? '
      'WHERE trip_id = ?',
      <Object?>[reconciled ? 1 : 0, reconciled ? nowMs : null, note, tripId],
    );
  }

  /// Khoi phuc chuyen da xoa tu bia mo: tao lai trip_record (danh dau
  /// is_reconstructed) tu cac truong cuoc da luu; khong tinh lai cuoc.
  Future<void> restore(String tripId, int nowMs) async {
    await _db.transaction(() async {
      final List<QueryRow> t = await _db.customSelect(
        'SELECT * FROM trip_tombstone WHERE trip_id = ?',
        variables: <Variable<Object>>[Variable<String>(tripId)],
      ).get();
      if (t.isEmpty) throw StateError('Khong co bia mo cho $tripId');
      final QueryRow r = t.first;
      final List<QueryRow> exists = await _db.customSelect(
        'SELECT 1 FROM trip_record WHERE trip_id = ?',
        variables: <Variable<Object>>[Variable<String>(tripId)],
      ).get();
      if (exists.isNotEmpty) throw StateError('Chuyen da ton tai');
      if (r.readNullable<String>('config_id') == null ||
          r.readNullable<String>('config_sha256') == null) {
        throw StateError('Bia mo thieu thong tin bieu gia, khong khoi phuc duoc');
      }
      await _db.customStatement(
        'INSERT INTO trip_record(trip_id, started_at, ended_at, duration_sec, distance_m, '
        'waiting_sec, fare_opening_vnd, fare_distance_vnd, fare_waiting_vnd, '
        'fare_surcharge_vnd, fare_total_vnd, config_id, config_version, config_sha256, '
        'fare_hash, raw_points_hash, note, is_reconstructed, reconstructed_at, created_at) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,1,?,?)',
        <Object?>[
          tripId, r.read<int>('trip_started_at'), r.read<int>('trip_ended_at'),
          r.readNullable<int>('duration_sec') ?? 0, r.readNullable<int>('distance_m') ?? 0,
          r.readNullable<int>('waiting_sec') ?? 0, r.readNullable<int>('fare_opening_vnd') ?? 0,
          r.readNullable<int>('fare_distance_vnd') ?? 0, r.readNullable<int>('fare_waiting_vnd') ?? 0,
          r.readNullable<int>('fare_surcharge_vnd') ?? 0, r.read<int>('fare_total_vnd'),
          r.read<String>('config_id'), r.readNullable<int>('config_version') ?? 1,
          r.read<String>('config_sha256'), r.read<String>('fare_hash'),
          r.readNullable<String>('raw_points_hash'), r.readNullable<String>('driver_note'),
          nowMs, nowMs,
        ],
      );
      final String? method = r.readNullable<String>('payment_method');
      if (method != null) {
        await _db.customStatement(
          'INSERT OR REPLACE INTO trip_payment(trip_id, method, state, amount_vnd, bank_bin, '
          'bank_account, account_holder, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?)',
          <Object?>[
            tripId, method, r.readNullable<String>('payment_state') ?? 'UNPAID',
            r.read<int>('fare_total_vnd'), r.readNullable<String>('bank_bin'),
            r.readNullable<String>('bank_account'), r.readNullable<String>('account_holder'),
            nowMs, nowMs,
          ],
        );
      }
      await _db.customStatement(
          'UPDATE trip_tombstone SET restored_at = ? WHERE trip_id = ?', <Object?>[nowMs, tripId]);
    });
  }
}
