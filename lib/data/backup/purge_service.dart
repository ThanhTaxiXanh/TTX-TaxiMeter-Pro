import 'package:drift/drift.dart' show QueryRow, Variable;

import '../db/app_database.dart';
import '../trip/tombstone_repository.dart';
import 'csv.dart';

const int trashRetentionDays = 30;
const int msPerDay = 86400000;

/// Chuoi xac nhan bat buoc cho moi thao tac xoa o Vung nguy hiem.
const String deleteConfirmWord = 'XOA';
bool isDeleteConfirmed(String typed) => typed.trim() == deleteConfirmWord;

const List<String> _tripCsvHeader = <String>[
  'trip_id', 'started_at_ms', 'ended_at_ms', 'duration_sec', 'distance_m', 'waiting_sec',
  'fare_opening_vnd', 'fare_distance_vnd', 'fare_waiting_vnd', 'fare_surcharge_vnd', 'fare_total_vnd',
  'adjustments_vnd', 'payment_method', 'payment_state', 'config_id', 'config_version', 'fare_hash',
  'archived', 'archived_at_ms', 'archive_reason', 'note',
];

/// Don dep du lieu: thung rac qua han (xuat CSV truoc), GPS tho qua han, xoa o Vung nguy hiem.
class PurgeService {
  PurgeService(this._db) : _tombstones = TombstoneRepository(_db);
  final AppDatabase _db;
  final TombstoneRepository _tombstones;

  Future<List<QueryRow>> _tripRows(String where, List<Variable<Object>> args) => _db.customSelect(
        'SELECT r.*, p.method AS pay_method, p.state AS pay_state, '
        '(SELECT COALESCE(SUM(a.amount_vnd),0) FROM trip_adjustment a WHERE a.trip_id = r.trip_id) AS adj '
        'FROM trip_record r LEFT JOIN trip_payment p ON p.trip_id = r.trip_id '
        'WHERE $where ORDER BY r.started_at',
        variables: args,
      ).get();

  String _csv(List<QueryRow> rows) => buildCsv(
        _tripCsvHeader,
        rows
            .map((QueryRow r) => <Object?>[
                  r.read<String>('trip_id'), r.read<int>('started_at'), r.read<int>('ended_at'),
                  r.read<int>('duration_sec'), r.read<int>('distance_m'), r.read<int>('waiting_sec'),
                  r.read<int>('fare_opening_vnd'), r.read<int>('fare_distance_vnd'),
                  r.read<int>('fare_waiting_vnd'), r.read<int>('fare_surcharge_vnd'),
                  r.read<int>('fare_total_vnd'), r.read<int>('adj'),
                  r.readNullable<String>('pay_method'), r.readNullable<String>('pay_state'),
                  r.read<String>('config_id'), r.read<int>('config_version'), r.read<String>('fare_hash'),
                  r.read<int>('archived'), r.readNullable<int>('archived_at'),
                  r.readNullable<String>('archive_reason'), r.readNullable<String>('note'),
                ])
            .toList(),
      );

  /// CSV toan bo chuyen (de nguoi dung luu/gui di).
  Future<String> exportAllTripsCsv() async => _csv(await _tripRows('1=1', const <Variable<Object>>[]));

  Future<int> expiredTrashCount(int nowMs) async {
    final List<QueryRow> r = await _db.customSelect(
      'SELECT COUNT(*) AS n FROM trip_record WHERE archived = 1 AND archived_at < ?',
      variables: <Variable<Object>>[Variable<int>(nowMs - trashRetentionDays * msPerDay)],
    ).get();
    return r.first.read<int>('n');
  }

  /// Don thung rac qua 30 ngay: [saveCsv] PHAI ghi xong CSV thi moi xoa (loi -> khong xoa gi).
  /// Moi chuyen xoa bang tombstone trong cung transaction (TombstoneRepository). Tra ve so chuyen da xoa.
  Future<int> purgeExpiredTrash({
    required int nowMs,
    required Future<void> Function(String csv, int count) saveCsv,
    bool all = false,
  }) async {
    final List<QueryRow> rows = all
        ? await _tripRows('r.archived = 1', const <Variable<Object>>[])
        : await _tripRows('r.archived = 1 AND r.archived_at < ?',
            <Variable<Object>>[Variable<int>(nowMs - trashRetentionDays * msPerDay)]);
    if (rows.isEmpty) return 0;
    await saveCsv(_csv(rows), rows.length);
    for (final QueryRow r in rows) {
      await _tombstones.deletePermanently(
        tripId: r.read<String>('trip_id'),
        reason: 'OTHER',
        note: all ? 'Dọn thùng rác (Vùng nguy hiểm)' : 'Tự dọn thùng rác sau $trashRetentionDays ngày',
        nowMs: nowMs,
      );
    }
    return rows.length;
  }

  /// Xoa diem GPS tho cua chuyen ket thuc truoc [keepDays] ngay; giu raw_points_hash va dau vet purged_at.
  Future<int> purgeRawGps({required int nowMs, required int keepDays}) async {
    final int cutoff = nowMs - keepDays * msPerDay;
    return _db.transaction(() async {
      final List<QueryRow> ids = await _db.customSelect(
        'SELECT DISTINCT g.trip_id AS id FROM raw_gps_points g '
        'JOIN trip_record r ON r.trip_id = g.trip_id WHERE r.ended_at < ?',
        variables: <Variable<Object>>[Variable<int>(cutoff)],
      ).get();
      int n = 0;
      for (final QueryRow r in ids) {
        final String id = r.read<String>('id');
        final List<QueryRow> c = await _db.customSelect(
            'SELECT COUNT(*) AS n FROM raw_gps_points WHERE trip_id = ?',
            variables: <Variable<Object>>[Variable<String>(id)]).get();
        n += c.first.read<int>('n');
        await _db.customStatement('DELETE FROM raw_gps_points WHERE trip_id = ?', <Object?>[id]);
        await _db.customStatement(
            'UPDATE raw_trace_meta SET purged_at = ? WHERE trip_id = ? AND purged_at IS NULL', <Object?>[nowMs, id]);
      }
      return n;
    });
  }

  /// Xoa tat ca tombstone (so doi soat) — chi goi sau khi nguoi dung go XOA rieng cho thao tac nay.
  Future<int> deleteAllTombstones() async {
    final List<QueryRow> c = await _db.customSelect('SELECT COUNT(*) AS n FROM trip_tombstone').get();
    await _db.customStatement('DELETE FROM trip_tombstone');
    return c.first.read<int>('n');
  }
}
