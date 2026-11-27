import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show QueryRow, Variable;

import '../db/app_database.dart';

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Khoa cai dat duoc sao luu (KHONG gom duong dan file ban do — chi hop le tren may nay).
const List<String> backupPrefKeys = <String>[
  'map_theme',
  'map_family',
  'warn_m',
  'ui_theme',
];

const String _dbName = 'database.db';
const String _prefsName = 'preferences.json';
const String _manifestName = 'manifest.json';
const String _sumsName = 'checksums.sha256';

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

class BackupInfo {
  const BackupInfo({required this.schemaVersion, required this.createdAt, required this.appVersion});
  final int schemaVersion;
  final int createdAt;
  final String appVersion;
}

/// Sao luu: ZIP gom database.db (ban chup nhat quan bang VACUUM INTO), preferences.json,
/// manifest.json, checksums.sha256. So tai khoan nam trong database.db theo quyet dinh cua
/// chu du an (2026-11-25) de khoi phuc khong phai nhap lai.
class BackupService {
  BackupService(this._db);
  final AppDatabase _db;

  Future<Uint8List> createBackupZip({
    required Directory workDir,
    required Map<String, Object?> prefs,
    required int nowMs,
    required String appVersion,
  }) async {
    await workDir.create(recursive: true);
    final File snap = File('${workDir.path}/snapshot_$nowMs.db');
    if (snap.existsSync()) snap.deleteSync();
    try {
      await _db.customStatement('VACUUM INTO ?', <Object?>[snap.path]);
      final Uint8List dbBytes = await snap.readAsBytes();
      final Map<String, Object?> safePrefs = <String, Object?>{
        for (final String k in backupPrefKeys)
          if (prefs[k] != null) k: prefs[k],
      };
      final Uint8List prefsBytes = Uint8List.fromList(utf8.encode(jsonEncode(safePrefs)));
      final Map<String, Object?> manifest = <String, Object?>{
        'app': 'ttx-taximeter-pro',
        'appVersion': appVersion,
        'schemaVersion': appSchemaVersion,
        'createdAt': nowMs,
        'files': <String>[_dbName, _prefsName],
      };
      final Uint8List manifestBytes = Uint8List.fromList(utf8.encode(jsonEncode(manifest)));
      final String sums = '${sha256Hex(dbBytes)}  $_dbName\n'
          '${sha256Hex(prefsBytes)}  $_prefsName\n'
          '${sha256Hex(manifestBytes)}  $_manifestName\n';
      final Archive a = Archive()
        ..addFile(ArchiveFile(_dbName, dbBytes.length, dbBytes))
        ..addFile(ArchiveFile(_prefsName, prefsBytes.length, prefsBytes))
        ..addFile(ArchiveFile(_manifestName, manifestBytes.length, manifestBytes))
        ..addFile(ArchiveFile(_sumsName, sums.length, utf8.encode(sums)));
      return Uint8List.fromList(ZipEncoder().encode(a)!);
    } finally {
      if (snap.existsSync()) snap.deleteSync();
    }
  }

  /// Kiem tra ZIP: du tep, checksum tung tep khop, schema khop. Sai -> BackupException.
  static ({Uint8List db, Map<String, Object?> prefs, BackupInfo info}) verifyZip(Uint8List zip) {
    final Archive a;
    try {
      a = ZipDecoder().decodeBytes(zip);
    } catch (_) {
      throw const BackupException('Tệp không phải bản sao lưu hợp lệ.');
    }
    Uint8List? file(String n) {
      for (final ArchiveFile f in a.files) {
        if (f.name == n && f.isFile) return Uint8List.fromList(f.content as List<int>);
      }
      return null;
    }

    final Uint8List? sums = file(_sumsName);
    if (sums == null) throw const BackupException('Thiếu checksums.sha256.');
    final Map<String, String> expected = <String, String>{};
    for (final String line in utf8.decode(sums).split('\n')) {
      final String t = line.trim();
      if (t.isEmpty) continue;
      final int i = t.indexOf('  ');
      if (i < 0) throw const BackupException('checksums.sha256 sai định dạng.');
      expected[t.substring(i + 2)] = t.substring(0, i);
    }
    for (final String n in <String>[_dbName, _prefsName, _manifestName]) {
      final Uint8List? b = file(n);
      if (b == null) throw BackupException('Thiếu tệp $n.');
      if (expected[n] != sha256Hex(b)) {
        throw BackupException('Tệp $n bị sửa hoặc hỏng (sai checksum). Không khôi phục.');
      }
    }
    final Map<String, dynamic> m = jsonDecode(utf8.decode(file(_manifestName)!)) as Map<String, dynamic>;
    final int schema = m['schemaVersion'] as int? ?? -1;
    if (schema != appSchemaVersion) {
      throw BackupException('Bản sao lưu dùng schema $schema, app hiện tại là $appSchemaVersion.');
    }
    return (
      db: file(_dbName)!,
      prefs: jsonDecode(utf8.decode(file(_prefsName)!)) as Map<String, Object?>,
      info: BackupInfo(
        schemaVersion: schema,
        createdAt: m['createdAt'] as int? ?? 0,
        appVersion: m['appVersion'] as String? ?? '',
      ),
    );
  }

  /// Khoi phuc: verify -> tu sao luu ban hien tai -> chep du lieu trong 1 transaction
  /// (loi bat ky -> rollback, giu nguyen du lieu cu). Tra ve (duong dan auto-backup, prefs trong ban sao luu).
  Future<({String autoBackupPath, Map<String, Object?> prefs})> restore({
    required Uint8List zip,
    required Directory workDir,
    required Map<String, Object?> currentPrefs,
    required int nowMs,
    required String appVersion,
  }) async {
    final v = verifyZip(zip);
    await workDir.create(recursive: true);
    final Uint8List auto = await createBackupZip(
        workDir: workDir, prefs: currentPrefs, nowMs: nowMs, appVersion: appVersion);
    final File autoFile = File('${workDir.path}/auto-backup-$nowMs.zip');
    await autoFile.writeAsBytes(auto, flush: true);

    final File src = File('${workDir.path}/restore_$nowMs.db');
    await src.writeAsBytes(v.db, flush: true);
    bool attached = false;
    try {
      await _db.customStatement('ATTACH DATABASE ? AS bk', <Object?>[src.path]);
      attached = true;
      final List<QueryRow> ic = await _db.customSelect('PRAGMA bk.integrity_check').get();
      if (ic.isEmpty || ic.first.data.values.first != 'ok') {
        throw const BackupException('Cơ sở dữ liệu trong bản sao lưu bị hỏng.');
      }
      final List<String> tables = (await _db
              .customSelect("SELECT name FROM main.sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
              .get())
          .map((QueryRow r) => r.read<String>('name'))
          .toList();
      for (final String t in tables) {
        final String a = await _cols('main', t);
        final String b = await _cols('bk', t);
        if (b.isEmpty || a != b) throw BackupException('Bảng $t trong bản sao lưu không khớp schema.');
      }
      final List<QueryRow> trig =
          await _db.customSelect("SELECT name, sql FROM main.sqlite_master WHERE type='trigger'").get();
      await _db.transaction(() async {
        for (final QueryRow t in trig) {
          await _db.customStatement('DROP TRIGGER IF EXISTS "${t.read<String>('name')}"');
        }
        for (final String t in tables) {
          await _db.customStatement('DELETE FROM main."$t"');
        }
        for (final String t in tables) {
          await _db.customStatement('INSERT INTO main."$t" SELECT * FROM bk."$t"');
        }
        // Khong khoi phuc chuyen dang chay cua may khac.
        await _db.customStatement('DELETE FROM main.active_trip_snapshot');
        for (final QueryRow t in trig) {
          await _db.customStatement(t.read<String>('sql'));
        }
      });
    } finally {
      if (attached) {
        try {
          await _db.customStatement('DETACH DATABASE bk');
        } catch (_) {}
      }
      if (src.existsSync()) src.deleteSync();
    }
    return (autoBackupPath: autoFile.path, prefs: v.prefs);
  }

  Future<String> _cols(String schema, String table) async {
    final List<QueryRow> r = await _db.customSelect(
      'SELECT name, type FROM pragma_table_info(?, ?) ORDER BY cid',
      variables: <Variable<Object>>[Variable<String>(table), Variable<String>(schema)],
    ).get();
    return r.map((QueryRow x) => '${x.read<String>('name')}:${x.read<String>('type')}').join(',');
  }
}
