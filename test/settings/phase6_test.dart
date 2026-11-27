import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:ttx/app/providers.dart';
import 'package:ttx/data/backup/backup_service.dart';
import 'package:ttx/data/backup/csv.dart';
import 'package:ttx/data/backup/purge_service.dart';
import 'package:ttx/data/db/app_database.dart';
import 'package:ttx/data/tariff/tariff_repository.dart';

import '../test_support.dart';

String tariffJson(int version) {
  final Map<String, dynamic> j = fixtureConfigJson();
  j['configId'] = 'taxi-ttx';
  j['configVersion'] = version;
  return jsonEncode(j);
}

void main() {
  late AppDatabase db;
  late Directory tmp;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tmp = Directory.systemTemp.createTempSync('ttx_p6_');
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  test('csv: escape dau phay, nhay kep, xuong dong; co BOM', () {
    expect(csvCell('a,b'), '"a,b"');
    expect(csvCell('x"y'), '"x""y"');
    expect(csvCell('a\nb'), '"a\nb"');
    expect(csvCell(null), '');
    expect(buildCsv(<String>['h'], <List<Object?>>[<Object?>[1]]).startsWith('﻿'), isTrue);
  });

  test('xac nhan xoa: dung "XOA" sau trim, sai thi khong', () {
    expect(isDeleteConfirmed('XOA'), isTrue);
    expect(isDeleteConfirmed('  XOA '), isTrue);
    expect(isDeleteConfirmed('xoa'), isFalse);
    expect(isDeleteConfirmed(''), isFalse);
  });

  test('themeModeFromName', () {
    expect(themeModeFromName('light'), ThemeMode.light);
    expect(themeModeFromName('dark'), ThemeMode.dark);
    expect(themeModeFromName('system'), ThemeMode.system);
    expect(themeModeFromName('zzz'), isNull);
    expect(themeModeFromName(null), isNull);
  });

  test('nhap bieu gia: hop le -> ACTIVE moi, trung phien ban bi tu choi, JSON hong bi tu choi', () async {
    final TariffRepository r = TariffRepository(db);
    await r.importJson(tariffJson(1), nowMs: baseTsMs);
    await r.importJson(tariffJson(2), nowMs: baseTsMs + 1000);
    final List<TariffListItem> l = await r.list();
    expect(l.where((TariffListItem t) => t.status == 'ACTIVE').length, 1);
    expect(l.firstWhere((TariffListItem t) => t.status == 'ACTIVE').version, 2);
    expect(() => r.importJson(tariffJson(2), nowMs: baseTsMs + 2000), throwsA(isA<TariffImportException>()));
    expect(() => r.importJson('{oops', nowMs: baseTsMs), throwsA(isA<TariffImportException>()));
  });

  test('sao luu -> khoi phuc: du lieu tro lai, prefs qua allowlist', () async {
    final TariffRepository r = TariffRepository(db);
    await r.importJson(tariffJson(1), nowMs: baseTsMs);
    final BackupService svc = BackupService(db);
    final Uint8List zip = await svc.createBackupZip(
      workDir: tmp,
      prefs: <String, Object?>{'map_theme': 'dark', 'secret': 'x'},
      nowMs: baseTsMs,
      appVersion: '0.1.0+1',
    );
    final v = BackupService.verifyZip(zip);
    expect(v.prefs.containsKey('secret'), isFalse);
    expect(v.prefs['map_theme'], 'dark');

    await r.importJson(tariffJson(2), nowMs: baseTsMs + 1000);
    expect((await r.list()).length, 2);
    final res = await svc.restore(
      zip: zip,
      workDir: tmp,
      currentPrefs: const <String, Object?>{},
      nowMs: baseTsMs + 5000,
      appVersion: '0.1.0+1',
    );
    expect((await r.list()).length, 1);
    expect(File(res.autoBackupPath).existsSync(), isTrue);
  });

  test('tep sao luu bi sua 1 byte -> tu choi, du lieu giu nguyen', () async {
    final TariffRepository r = TariffRepository(db);
    await r.importJson(tariffJson(1), nowMs: baseTsMs);
    final BackupService svc = BackupService(db);
    final Uint8List zip = await svc.createBackupZip(
        workDir: tmp, prefs: const <String, Object?>{}, nowMs: baseTsMs, appVersion: '0.1.0+1');
    final Uint8List bad = Uint8List.fromList(zip);
    bad[bad.length ~/ 2] ^= 0xFF;
    await expectLater(
      svc.restore(zip: bad, workDir: tmp, currentPrefs: const <String, Object?>{}, nowMs: baseTsMs + 1, appVersion: 'x'),
      throwsA(anything),
    );
    expect((await r.list()).length, 1);
  });

  test('don thung rac: khong co gi qua han -> 0, khong goi saveCsv', () async {
    final PurgeService p = PurgeService(db);
    bool called = false;
    final int n = await p.purgeExpiredTrash(nowMs: baseTsMs, saveCsv: (String c, int k) async => called = true);
    expect(n, 0);
    expect(called, isFalse);
    expect(await p.expiredTrashCount(baseTsMs), 0);
  });
}
