import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ttx/data/db/app_database.dart';
import 'package:ttx/data/traffic/traffic_report_repository.dart';
import 'package:ttx/data/traffic/traffic_repository.dart';
import 'package:ttx/domain/traffic/sign_catalog.dart';
import 'package:ttx/domain/traffic/traffic_geojson.dart';
import 'package:ttx/domain/traffic/traffic_models.dart';
import 'package:ttx/domain/traffic/traffic_overrides.dart';

void main() {
  late List<CatalogSign> cat;
  setUpAll(() => cat = parseSignCatalog(File('assets/data/sign_catalog.json').readAsStringSync()));

  test('danh muc: ma hop le, khong trung, co P.133 va P.127', () {
    expect(cat.length, greaterThan(300));
    expect(cat.map((CatalogSign s) => s.code).toSet().length, cat.length);
    for (final CatalogSign s in cat) {
      expect(isCatalogCode(s.code), isTrue, reason: s.code);
      expect(signGroupLabels.containsKey(s.group), isTrue, reason: s.code);
    }
    expect(cat.firstWhere((CatalogSign s) => s.code == 'P.133').name, 'Hết cấm vượt');
    expect(cat.firstWhere((CatalogSign s) => s.code == 'P.127').group, 'P');
  });

  test('foldVi + filterCatalog tim theo ma / ten khong dau', () {
    expect(foldVi('Cấm đỗ xe Ơ ư'), 'cam do xe o u');
    expect(filterCatalog(cat, 'P', 'p103a').map((CatalogSign s) => s.code), contains('P.103a'));
    expect(filterCatalog(cat, 'P', 'P.103a').map((CatalogSign s) => s.code), contains('P.103a'));
    expect(filterCatalog(cat, 'P', 'cam xe may').map((CatalogSign s) => s.code), contains('P.104'));
    expect(filterCatalog(cat, 'W', 'p103a'), isEmpty);
    expect(filterCatalog(cat, 'W', '').every((CatalogSign s) => s.group == 'W'), isTrue);
  });

  test('bien khac: ma danh muc -> SignKind.other co icon rieng', () {
    const TrafficOverrideItem o = TrafficOverrideItem(
        id: 1, kind: 'SIGN', latE7: 1, lngE7: 2, signCode: 'P.103a', createdAt: 0, updatedAt: 0);
    expect(o.signKind, SignKind.other);
    expect(validateOverride(kind: 'SIGN', latE7: 1, lngE7: 2, speedKmh: null, signCode: 'P.103a', cameraType: null), isNull);
    expect(validateOverride(kind: 'SIGN', latE7: 1, lngE7: 2, speedKmh: null, signCode: 'other', cameraType: null), isNotNull);
    final List<TrafficSign> out = applyOverrides(const <TrafficSign>[], const <TrafficOverrideItem>[o], 0);
    expect(out.single.kind, SignKind.other);
    expect(out.single.code, 'P.103a');
    expect(signIconName(out.single), 'sign_code:P.103a');
    expect(signDisplayName(out.single), 'Biển P.103a');
  });

  test('duyet bao cao theo ma danh muc tao diem bien khac', () async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final TrafficReportRepository reports = TrafficReportRepository(db);
    final TrafficRepository repo = TrafficRepository(db);
    final int id = await reports.create(
        kind: 'P.103a', proposed: <String, dynamic>{'action': 'ADD', 'name': 'Cấm xe ôtô'},
        latE7: 107769000, lngE7: 1067009000, nowMs: 5);
    await repo.approveReport((await reports.list()).single, nowMs: 6);
    final List<TrafficOverrideItem> ov = await repo.list();
    expect(ov.single.signCode, 'P.103a');
    expect(ov.single.signKind, SignKind.other);
    expect((await reports.list()).firstWhere((TrafficReportItem r) => r.id == id).status, 'APPROVED');
  });
}
