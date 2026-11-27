import 'dart:convert';

import 'package:drift/drift.dart' show QueryRow, Variable;

import '../../domain/models/tariff_config_v2.dart';
import '../db/app_database.dart';

class TariffImportException implements Exception {
  const TariffImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TariffListItem {
  const TariffListItem(this.configId, this.version, this.status, this.effectiveFrom);
  final String configId;
  final int version;
  final String status;
  final int effectiveFrom;
}

/// Nhap bieu gia that cua chu xe (JSON schema 2.0). Chuyen dang chay giu config cu (khong resolve lai).
class TariffRepository {
  TariffRepository(this._db);
  final AppDatabase _db;

  Future<List<TariffListItem>> list() async {
    final List<QueryRow> r =
        await _db.customSelect('SELECT * FROM tariff_config ORDER BY effective_from DESC, config_version DESC').get();
    return r
        .map((QueryRow x) => TariffListItem(x.read<String>('config_id'), x.read<int>('config_version'),
            x.read<String>('status'), x.read<int>('effective_from')))
        .toList();
  }

  /// Kiem tra JSON bang TariffConfigV2.fromJson; (configId, version) da co -> tu choi.
  /// Bieu gia moi co hieu luc tu [nowMs]; cac bieu gia ACTIVE cu chuyen RETIRED.
  Future<TariffConfigV2> importJson(String jsonText, {required int nowMs}) async {
    final TariffConfigV2 cfg;
    try {
      cfg = TariffConfigV2.fromJson(jsonDecode(jsonText));
    } on FormatException catch (e) {
      throw TariffImportException('Biểu giá không hợp lệ: ${e.message}');
    } catch (e) {
      throw TariffImportException('Biểu giá không hợp lệ: $e');
    }
    final Map<String, dynamic> raw = jsonDecode(jsonText) as Map<String, dynamic>;
    final int from = (raw['effectiveFrom'] as int?) ?? 0;
    final int effective = from > nowMs ? from : nowMs;
    await _db.transaction(() async {
      final List<QueryRow> dup = await _db.customSelect(
        'SELECT 1 FROM tariff_config WHERE config_id = ? AND config_version = ?',
        variables: <Variable<Object>>[Variable<String>(cfg.configId), Variable<int>(cfg.configVersion)],
      ).get();
      if (dup.isNotEmpty) {
        throw TariffImportException(
            'Biểu giá ${cfg.configId} phiên bản ${cfg.configVersion} đã có. Hãy tăng configVersion.');
      }
      await _db.customStatement(
          "UPDATE tariff_config SET status = 'RETIRED', effective_to = ? WHERE status = 'ACTIVE'", <Object?>[effective]);
      await _db.customStatement(
        'INSERT INTO tariff_config(config_id, config_version, effective_from, effective_to, status, '
        "json_body, sha256, created_at) VALUES (?, ?, ?, NULL, 'ACTIVE', ?, ?, ?)",
        <Object?>[cfg.configId, cfg.configVersion, effective, jsonText, cfg.contentSha256, nowMs],
      );
    });
    return cfg;
  }

  /// Moi bieu gia (configId) lay phien ban moi nhat; `active` neu dang duoc chon dung cho chuyen moi.
  Future<List<TariffSummary>> listConfigs() async {
    final List<QueryRow> rows = await _db.customSelect(
      'SELECT t.config_id, t.config_version, t.status, t.json_body FROM tariff_config t '
      'WHERE t.config_version = (SELECT MAX(config_version) FROM tariff_config WHERE config_id = t.config_id) '
      "ORDER BY (t.status = 'ACTIVE') DESC, t.config_id",
    ).get();
    return rows
        .map((QueryRow r) => TariffSummary(
              configId: r.read<String>('config_id'),
              version: r.read<int>('config_version'),
              active: r.read<String>('status') == 'ACTIVE',
              json: jsonDecode(r.read<String>('json_body')) as Map<String, dynamic>,
            ))
        .toList();
  }

  /// Chon bieu gia dung cho chuyen MOI (chuyen dang chay giu cu). Bieu gia khac chuyen sang RETIRED.
  Future<void> select(String configId, {required int nowMs}) async {
    await _db.transaction(() async {
      final List<QueryRow> r = await _db.customSelect(
        'SELECT MAX(config_version) AS v FROM tariff_config WHERE config_id = ?',
        variables: <Variable<Object>>[Variable<String>(configId)],
      ).get();
      final int? v = r.isEmpty ? null : r.first.readNullable<int>('v');
      if (v == null) throw const TariffImportException('Không tìm thấy biểu giá.');
      await _db.customStatement(
        "UPDATE tariff_config SET status = 'RETIRED', effective_to = ? WHERE status = 'ACTIVE' AND config_id != ?",
        <Object?>[nowMs, configId],
      );
      await _db.customStatement(
        "UPDATE tariff_config SET status = 'ACTIVE', effective_from = ?, effective_to = NULL "
        'WHERE config_id = ? AND config_version = ? AND status != \'ACTIVE\'',
        <Object?>[nowMs, configId, v],
      );
    });
  }

  /// Luu bieu gia da sua thanh phien ban moi (configVersion = max + 1). [activate] = chon dung ngay.
  /// Kiem tra bang TariffConfigV2.fromJson; sai thi nem TariffImportException va khong ghi gi.
  Future<TariffConfigV2> saveVersion(Map<String, dynamic> json, {required int nowMs, required bool activate}) async {
    final String id = (json['configId'] as String?)?.trim() ?? '';
    if (id.isEmpty) throw const TariffImportException('Biểu giá cần có tên.');
    late TariffConfigV2 cfg;
    await _db.transaction(() async {
      final List<QueryRow> r = await _db.customSelect(
        'SELECT MAX(config_version) AS v FROM tariff_config WHERE config_id = ?',
        variables: <Variable<Object>>[Variable<String>(id)],
      ).get();
      final int version = (r.isEmpty ? null : r.first.readNullable<int>('v')) ?? 0;
      final Map<String, dynamic> j = Map<String, dynamic>.of(json)
        ..['configId'] = id
        ..['configVersion'] = version + 1
        ..['effectiveFrom'] = nowMs
        ..['effectiveTo'] = null
        ..['status'] = activate ? 'ACTIVE' : 'RETIRED'
        ..['integrity'] = <String, dynamic>{'sha256': null, 'signature': null};
      try {
        cfg = TariffConfigV2.fromJson(j);
      } on FormatException catch (e) {
        throw TariffImportException('Biểu giá không hợp lệ: ${e.message}');
      } catch (e) {
        throw TariffImportException('Biểu giá không hợp lệ: $e');
      }
      if (activate) {
        await _db.customStatement(
            "UPDATE tariff_config SET status = 'RETIRED', effective_to = ? WHERE status = 'ACTIVE'", <Object?>[nowMs]);
      }
      await _db.customStatement(
        'INSERT INTO tariff_config(config_id, config_version, effective_from, effective_to, status, '
        'json_body, sha256, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[id, version + 1, nowMs, activate ? null : nowMs, activate ? 'ACTIVE' : 'RETIRED', jsonEncode(j), cfg.contentSha256, nowMs],
      );
    });
    return cfg;
  }
}

class TariffSummary {
  const TariffSummary({required this.configId, required this.version, required this.active, required this.json});
  final String configId;
  final int version;
  final bool active;
  final Map<String, dynamic> json;
}

/// "0.8" -> 800 (m); chap nhan dau , hoac . ; toi da 3 chu so thap phan. Khong dung so thuc.
int? parseKmToMeters(String s) {
  final String t = s.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  final List<String> p = t.split('.');
  if (p.length > 2) return null;
  final int? whole = int.tryParse(p[0].isEmpty ? '0' : p[0]);
  if (whole == null || whole < 0) return null;
  int frac = 0;
  if (p.length == 2) {
    if (p[1].length > 3 || p[1].isEmpty) return null;
    final int? f = int.tryParse(p[1].padRight(3, '0'));
    if (f == null) return null;
    frac = f;
  }
  return whole * 1000 + frac;
}

/// 800 -> "0.8"; 30000 -> "30".
String metersToKmText(int m) {
  final int w = m ~/ 1000, f = m % 1000;
  if (f == 0) return '$w';
  String fs = f.toString().padLeft(3, '0');
  while (fs.endsWith('0')) {
    fs = fs.substring(0, fs.length - 1);
  }
  return '$w.$fs';
}
