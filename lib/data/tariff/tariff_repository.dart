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
}
