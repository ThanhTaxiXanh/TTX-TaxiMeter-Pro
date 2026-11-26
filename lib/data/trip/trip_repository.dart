import 'package:drift/drift.dart' show QueryRow, Variable;

import '../db/app_database.dart';
import 'trip_models.dart';

/// So cai chuyen di. KHONG bao gio UPDATE fare_total_vnd; doi tien = adjustment.
class TripRepository {
  TripRepository(this._db);
  final AppDatabase _db;

  static const String _selectItem = '''
SELECT r.trip_id, r.started_at, r.ended_at, r.duration_sec, r.distance_m,
  r.waiting_sec, r.fare_total_vnd, r.is_test, r.archived, r.archived_at,
  r.archive_reason, r.note, p.method AS pay_method, p.state AS pay_state,
  COALESCE((SELECT SUM(a.amount_vnd) FROM trip_adjustment a
            WHERE a.trip_id = r.trip_id), 0) AS adj
FROM trip_record r LEFT JOIN trip_payment p ON p.trip_id = r.trip_id''';

  TripListItem _item(QueryRow r) => TripListItem(
        tripId: r.read<String>('trip_id'),
        startedAt: r.read<int>('started_at'),
        endedAt: r.read<int>('ended_at'),
        durationSec: r.read<int>('duration_sec'),
        distanceM: r.read<int>('distance_m'),
        waitingSec: r.read<int>('waiting_sec'),
        fareTotalVnd: r.read<int>('fare_total_vnd'),
        adjustmentVnd: r.read<int>('adj'),
        paymentMethod: r.readNullable<String>('pay_method'),
        paymentState: r.readNullable<String>('pay_state'),
        isTest: r.read<int>('is_test') == 1,
        archived: r.read<int>('archived') == 1,
        archivedAt: r.readNullable<int>('archived_at'),
        archiveReason: r.readNullable<String>('archive_reason'),
        note: r.readNullable<String>('note'),
      );

  /// Chuyen dang dung (khong o thung rac), moi nhat truoc.
  Future<List<TripListItem>> listTrips({int limit = 500, int offset = 0}) async {
    final List<QueryRow> rows = await _db.customSelect(
      '$_selectItem WHERE r.archived = 0 ORDER BY r.started_at DESC LIMIT ? OFFSET ?',
      variables: <Variable<Object>>[Variable<int>(limit), Variable<int>(offset)],
    ).get();
    return rows.map(_item).toList();
  }

  Future<List<TripListItem>> listTrash() async {
    final List<QueryRow> rows = await _db
        .customSelect('$_selectItem WHERE r.archived = 1 ORDER BY r.archived_at DESC')
        .get();
    return rows.map(_item).toList();
  }

  /// Chuyen co thoi diem bat dau trong [fromMs, toMs) (gom ca da luu tru de
  /// tong hop tu quyet dinh; RevenueSummary bo qua archived/test).
  Future<List<TripListItem>> tripsInRange(int fromMs, int toMs) async {
    final List<QueryRow> rows = await _db.customSelect(
      '$_selectItem WHERE r.started_at >= ? AND r.started_at < ? ORDER BY r.started_at DESC',
      variables: <Variable<Object>>[Variable<int>(fromMs), Variable<int>(toMs)],
    ).get();
    return rows.map(_item).toList();
  }

  Future<TripDetail?> getTrip(String tripId) async {
    final List<QueryRow> rows = await _db.customSelect(
      '$_selectItem WHERE r.trip_id = ?',
      variables: <Variable<Object>>[Variable<String>(tripId)],
    ).get();
    if (rows.isEmpty) return null;
    final List<QueryRow> full = await _db.customSelect(
      'SELECT fare_opening_vnd, fare_distance_vnd, fare_waiting_vnd, fare_surcharge_vnd, '
      'config_id, config_version, fare_hash, edit_count, is_reconstructed '
      'FROM trip_record WHERE trip_id = ?',
      variables: <Variable<Object>>[Variable<String>(tripId)],
    ).get();
    final QueryRow f = full.first;
    final List<QueryRow> adj = await _db.customSelect(
      'SELECT id, amount_vnd, reason, created_at FROM trip_adjustment '
      'WHERE trip_id = ? ORDER BY id',
      variables: <Variable<Object>>[Variable<String>(tripId)],
    ).get();
    return TripDetail(
      item: _item(rows.first),
      fareOpening: f.read<int>('fare_opening_vnd'),
      fareDistance: f.read<int>('fare_distance_vnd'),
      fareWaiting: f.read<int>('fare_waiting_vnd'),
      fareSurcharge: f.read<int>('fare_surcharge_vnd'),
      configId: f.read<String>('config_id'),
      configVersion: f.read<int>('config_version'),
      fareHash: f.read<String>('fare_hash'),
      editCount: f.read<int>('edit_count'),
      isReconstructed: f.read<int>('is_reconstructed') == 1,
      adjustments: adj
          .map((QueryRow a) => Adjustment(a.read<int>('id'), a.read<int>('amount_vnd'),
              a.read<String>('reason'), a.read<int>('created_at')))
          .toList(),
    );
  }

  /// Sua ghi chu / co chuyen thu. Ghi trip_edit_log cho tung truong doi.
  Future<void> editMeta({
    required String tripId,
    required String? note,
    required bool isTest,
    required int nowMs,
  }) async {
    final String? newNote = (note == null || note.trim().isEmpty) ? null : note.trim();
    await _db.transaction(() async {
      final List<QueryRow> cur = await _db.customSelect(
        'SELECT note, is_test FROM trip_record WHERE trip_id = ?',
        variables: <Variable<Object>>[Variable<String>(tripId)],
      ).get();
      if (cur.isEmpty) throw StateError('Khong tim thay chuyen $tripId');
      final String? oldNote = cur.first.readNullable<String>('note');
      final bool oldTest = cur.first.read<int>('is_test') == 1;
      int changes = 0;
      if (oldNote != newNote) {
        await _log(tripId, 'note', oldNote, newNote, nowMs);
        changes++;
      }
      if (oldTest != isTest) {
        await _log(tripId, 'is_test', oldTest ? '1' : '0', isTest ? '1' : '0', nowMs);
        changes++;
      }
      if (changes == 0) return;
      await _db.customStatement(
        'UPDATE trip_record SET note = ?, is_test = ?, edited_at = ?, '
        'edit_count = edit_count + ? WHERE trip_id = ?',
        <Object?>[newNote, isTest ? 1 : 0, nowMs, changes, tripId],
      );
    });
  }

  Future<void> _log(String tripId, String field, String? o, String? n, int nowMs) {
    return _db.customStatement(
      'INSERT INTO trip_edit_log(trip_id, field, old_value, new_value, edited_at) VALUES (?,?,?,?,?)',
      <Object?>[tripId, field, o, n, nowMs],
    );
  }

  /// Them dieu chinh tien (+/-). Chi them dong, khong sua cuoc goc.
  Future<void> addAdjustment({
    required String tripId,
    required int amountVnd,
    required String reason,
    required int nowMs,
  }) async {
    if (amountVnd == 0) throw ArgumentError('So tien dieu chinh phai khac 0');
    if (reason.trim().isEmpty) throw ArgumentError('Phai ghi ly do dieu chinh');
    await _db.customStatement(
      'INSERT INTO trip_adjustment(trip_id, amount_vnd, reason, created_at) VALUES (?,?,?,?)',
      <Object?>[tripId, amountVnd, reason.trim(), nowMs],
    );
  }

  /// Xoa mem: dua vao thung rac (30 ngay, xem PurgeService o Phase 6).
  Future<void> moveToTrash(String tripId, String? reason, int nowMs) async {
    await _db.customStatement(
      'UPDATE trip_record SET archived = 1, archived_at = ?, archive_reason = ? '
      'WHERE trip_id = ? AND archived = 0',
      <Object?>[nowMs, reason, tripId],
    );
  }

  Future<void> restoreFromTrash(String tripId) async {
    await _db.customStatement(
      'UPDATE trip_record SET archived = 0, archived_at = NULL, archive_reason = NULL '
      'WHERE trip_id = ?',
      <Object?>[tripId],
    );
  }
}
