import 'dart:convert';

import 'package:drift/drift.dart' show QueryRow, Variable;

import '../db/app_database.dart';

class TrafficReportItem {
  const TrafficReportItem({
    required this.id,
    required this.kind,
    required this.proposed,
    required this.latE7,
    required this.lngE7,
    required this.status,
    required this.reportedAt,
  });
  final int id;
  final String kind;
  final Map<String, dynamic> proposed;
  final int? latE7;
  final int? lngE7;
  final String status; // PENDING | APPROVED | REJECTED
  final int reportedAt;
}

/// Bao cao bien bao/camera cua tai xe (luu cuc bo, khong gui di dau).
class TrafficReportRepository {
  TrafficReportRepository(this._db);
  final AppDatabase _db;

  Future<int> create({
    required String kind,
    required Map<String, dynamic> proposed,
    int? latE7,
    int? lngE7,
    required int nowMs,
  }) async {
    await _db.customStatement(
      "INSERT INTO traffic_report(kind, proposed_data, lat_e7, lng_e7, status, reported_at) "
      "VALUES (?,?,?,?,'PENDING',?)",
      <Object?>[kind, jsonEncode(proposed), latE7, lngE7, nowMs],
    );
    final List<QueryRow> r = await _db.customSelect('SELECT last_insert_rowid() AS id').get();
    return r.first.read<int>('id');
  }

  Future<List<TrafficReportItem>> list({String? status}) async {
    final List<QueryRow> rows = status == null
        ? await _db.customSelect('SELECT * FROM traffic_report ORDER BY reported_at DESC').get()
        : await _db.customSelect(
            'SELECT * FROM traffic_report WHERE status = ? ORDER BY reported_at DESC',
            variables: <Variable<Object>>[Variable<String>(status)],
          ).get();
    return rows
        .map((QueryRow r) => TrafficReportItem(
              id: r.read<int>('id'),
              kind: r.read<String>('kind'),
              proposed: jsonDecode(r.read<String>('proposed_data')) as Map<String, dynamic>,
              latE7: r.readNullable<int>('lat_e7'),
              lngE7: r.readNullable<int>('lng_e7'),
              status: r.read<String>('status'),
              reportedAt: r.read<int>('reported_at'),
            ))
        .toList();
  }
}
