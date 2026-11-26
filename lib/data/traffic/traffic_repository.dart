
import 'package:drift/drift.dart' show QueryRow;

import '../../domain/traffic/traffic_models.dart';
import '../../domain/traffic/traffic_overrides.dart';
import '../db/app_database.dart';
import 'traffic_report_repository.dart';

class TrafficRepositoryException implements Exception {
  const TrafficRepositoryException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Sua tay du lieu giao thong (traffic_override) va duyet bao cao (traffic_report).
/// Tat ca nam tren may, khong gui di dau.
class TrafficRepository {
  TrafficRepository(this._db);
  final AppDatabase _db;

  TrafficOverrideItem _row(QueryRow r) => TrafficOverrideItem(
        id: r.read<int>('id'),
        kind: r.read<String>('kind'),
        latE7: r.readNullable<int>('lat_e7'),
        lngE7: r.readNullable<int>('lng_e7'),
        speedKmh: r.readNullable<int>('speed_kmh'),
        signCode: r.readNullable<String>('sign_code'),
        cameraType: r.readNullable<String>('camera_type'),
        source: r.read<String>('source'),
        validTo: r.readNullable<int>('valid_to'),
        note: r.readNullable<String>('note'),
        createdAt: r.read<int>('created_at'),
        updatedAt: r.read<int>('updated_at'),
      );

  Future<List<TrafficOverrideItem>> list() async {
    final List<QueryRow> rows =
        await _db.customSelect('SELECT * FROM traffic_override ORDER BY updated_at DESC, id DESC').get();
    return rows.map(_row).toList();
  }

  Future<int> create({
    required String kind,
    required int? latE7,
    required int? lngE7,
    int? speedKmh,
    String? signCode,
    String? cameraType,
    String source = sourceManual,
    String? note,
    required int nowMs,
  }) async {
    final String? err = validateOverride(
        kind: kind, latE7: latE7, lngE7: lngE7, speedKmh: speedKmh, signCode: signCode, cameraType: cameraType);
    if (err != null) throw TrafficRepositoryException(err);
    await _db.customStatement(
      'INSERT INTO traffic_override(kind, lat_e7, lng_e7, speed_kmh, sign_code, camera_type, source, note, '
      'created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
      <Object?>[kind, latE7, lngE7, speedKmh, signCode, cameraType, source, note, nowMs, nowMs],
    );
    final List<QueryRow> r = await _db.customSelect('SELECT last_insert_rowid() AS id').get();
    return r.first.read<int>('id');
  }

  Future<void> update({
    required int id,
    required String kind,
    required int? latE7,
    required int? lngE7,
    int? speedKmh,
    String? signCode,
    String? cameraType,
    String? note,
    required int nowMs,
  }) async {
    final String? err = validateOverride(
        kind: kind, latE7: latE7, lngE7: lngE7, speedKmh: speedKmh, signCode: signCode, cameraType: cameraType);
    if (err != null) throw TrafficRepositoryException(err);
    await _db.customStatement(
      'UPDATE traffic_override SET kind=?, lat_e7=?, lng_e7=?, speed_kmh=?, sign_code=?, camera_type=?, '
      'note=?, updated_at=? WHERE id=?',
      <Object?>[kind, latE7, lngE7, speedKmh, signCode, cameraType, note, nowMs, id],
    );
  }

  /// Chi xoa du lieu sua tay (khong phai so cai tai chinh), khong co rang buoc so cai.
  Future<void> delete(int id) => _db.customStatement('DELETE FROM traffic_override WHERE id=?', <Object?>[id]);

  /// Duyet bao cao: ADD -> tao diem moi; REMOVE -> an bien cung loai quanh vi tri bao cao.
  /// Bao cao + diem sua tay duoc ghi trong cung mot giao dich.
  Future<void> approveReport(TrafficReportItem r, {required int nowMs, String? reviewerNote}) async {
    if (r.status != 'PENDING') throw const TrafficRepositoryException('Báo cáo đã được xử lý.');
    final SignKind? k = _kindByName(r.kind);
    if (k == null) throw const TrafficRepositoryException('Loại biển không xác định.');
    if (r.latE7 == null || r.lngE7 == null) throw const TrafficRepositoryException('Báo cáo thiếu vị trí.');
    final bool add = (r.proposed['action'] as String?) != 'REMOVE';
    final int? speed = r.proposed['speedKmh'] as int?;
    final bool cam = k == SignKind.speedCamera || k == SignKind.streetCamera;
    final String ovKind = cam ? 'CAMERA' : (k == SignKind.maxSpeed && add ? 'SPEED_LIMIT' : 'SIGN');
    final String? err = validateOverride(
      kind: ovKind,
      latE7: r.latE7,
      lngE7: r.lngE7,
      speedKmh: add ? speed : (k == SignKind.maxSpeed ? 5 : null),
      signCode: ovKind == 'SIGN' ? k.name : null,
      cameraType: cam ? k.name : null,
    );
    if (err != null) throw TrafficRepositoryException(err);
    await _db.transaction(() async {
      await _db.customStatement(
        'INSERT INTO traffic_override(kind, lat_e7, lng_e7, speed_kmh, sign_code, camera_type, source, note, '
        'created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
        <Object?>[
          ovKind,
          r.latE7,
          r.lngE7,
          add ? speed : null,
          ovKind == 'SIGN' ? k.name : null,
          cam ? k.name : null,
          add ? sourceReport : sourceRemove,
          r.proposed['note'] as String?,
          nowMs,
          nowMs,
        ],
      );
      await _db.customStatement(
        "UPDATE traffic_report SET status='APPROVED', reviewed_at=?, reviewer_note=? WHERE id=? AND status='PENDING'",
        <Object?>[nowMs, reviewerNote, r.id],
      );
    });
  }

  Future<void> rejectReport(int id, {required int nowMs, String? reviewerNote}) => _db.customStatement(
        "UPDATE traffic_report SET status='REJECTED', reviewed_at=?, reviewer_note=? WHERE id=? AND status='PENDING'",
        <Object?>[nowMs, reviewerNote, id],
      );

  static SignKind? _byNameStatic(String n) {
    for (final SignKind k in SignKind.values) {
      if (k.name == n) return k;
    }
    return null;
  }

  SignKind? _kindByName(String n) => _byNameStatic(n);

  Future<int> pendingCount() async {
    final List<QueryRow> r =
        await _db.customSelect("SELECT COUNT(*) AS n FROM traffic_report WHERE status='PENDING'").get();
    return r.first.read<int>('n');
  }
}

