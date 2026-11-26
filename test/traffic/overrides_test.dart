import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ttx/data/db/app_database.dart';
import 'package:ttx/data/traffic/traffic_report_repository.dart';
import 'package:ttx/data/traffic/traffic_repository.dart';
import 'package:ttx/domain/traffic/traffic_models.dart';
import 'package:ttx/domain/traffic/traffic_overrides.dart';

const int lat = 107769000, lng = 1067009000;

void main() {
  test('parseDegreesE7 / formatDegreesE7 chi dung so nguyen', () {
    expect(parseDegreesE7('10.7769'), 107769000);
    expect(parseDegreesE7('106,7009'), 1067009000);
    expect(parseDegreesE7('-0.5'), -5000000);
    expect(parseDegreesE7('10.77690001234'), isNull);
    expect(parseDegreesE7('abc'), isNull);
    expect(parseDegreesE7(''), isNull);
    expect(formatDegreesE7(107769000), '10.7769000');
    expect(formatDegreesE7(-5000000), '-0.5000000');
    expect(formatDegreesE7(parseDegreesE7('105.123456789')!), '105.1234567');
  });

  test('validateOverride', () {
    String? v(String k, {int? sp, String? sc, String? ct, int? la = lat, int? ln = lng}) =>
        validateOverride(kind: k, latE7: la, lngE7: ln, speedKmh: sp, signCode: sc, cameraType: ct);
    expect(v('SPEED_LIMIT', sp: 50), isNull);
    expect(v('SPEED_LIMIT', sp: 4), isNotNull);
    expect(v('SPEED_LIMIT', sp: 131), isNotNull);
    expect(v('SPEED_LIMIT'), isNotNull);
    expect(v('SPEED_LIMIT', sp: 50, la: null), isNotNull);
    expect(v('SIGN', sc: 'tollBooth'), isNull);
    expect(v('SIGN', sc: 'maxSpeed'), isNotNull);
    expect(v('SIGN', sc: 'maxSpeed', sp: 60), isNull);
    expect(v('SIGN', sc: 'speedCamera'), isNotNull);
    expect(v('SIGN', sc: 'xyz'), isNotNull);
    expect(v('CAMERA', ct: 'speedCamera'), isNull);
    expect(v('CAMERA', ct: 'x'), isNotNull);
    expect(v('FOO', sp: 50), isNotNull);
  });

  test('applyOverrides them, an va bo qua ban ghi het han', () {
    const TrafficSign base = TrafficSign(latE7: lat, lngE7: lng, kind: SignKind.speedCamera, dirDeg: 90, speedKmh: -1);
    const TrafficSign far = TrafficSign(latE7: lat + 100000, lngE7: lng, kind: SignKind.speedCamera, dirDeg: 90, speedKmh: -1);
    const TrafficOverrideItem remove = TrafficOverrideItem(
        id: 1, kind: 'CAMERA', latE7: lat + 100, lngE7: lng, cameraType: 'speedCamera',
        source: sourceRemove, createdAt: 0, updatedAt: 0);
    const TrafficOverrideItem add = TrafficOverrideItem(
        id: 2, kind: 'SPEED_LIMIT', latE7: lat, lngE7: lng, speedKmh: 40, createdAt: 0, updatedAt: 0);
    const TrafficOverrideItem expired = TrafficOverrideItem(
        id: 3, kind: 'SPEED_LIMIT', latE7: lat, lngE7: lng, speedKmh: 30, validTo: 10, createdAt: 0, updatedAt: 0);
    final List<TrafficSign> out = applyOverrides(<TrafficSign>[base, far], <TrafficOverrideItem>[remove, add, expired], 1000);
    expect(out.length, 2);
    expect(out.where((TrafficSign s) => s.kind == SignKind.speedCamera).length, 1); // chi con bien xa
    final TrafficSign sp = out.firstWhere((TrafficSign s) => s.kind == SignKind.maxSpeed);
    expect(sp.speedKmh, 40);
    expect(sp.dirDeg, -1);
  });

  group('TrafficRepository', () {
    late AppDatabase db;
    late TrafficRepository repo;
    late TrafficReportRepository reports;
    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = TrafficRepository(db);
      reports = TrafficReportRepository(db);
    });
    tearDown(() => db.close());

    test('tao/sua/xoa va tu choi du lieu sai', () async {
      final int id = await repo.create(kind: 'SPEED_LIMIT', latE7: lat, lngE7: lng, speedKmh: 50, nowMs: 100);
      var l = await repo.list();
      expect(l.single.speedKmh, 50);
      await repo.update(id: id, kind: 'SPEED_LIMIT', latE7: lat, lngE7: lng, speedKmh: 60, nowMs: 200);
      l = await repo.list();
      expect(l.single.speedKmh, 60);
      expect(l.single.updatedAt, 200);
      expect(l.single.createdAt, 100);
      await expectLater(repo.create(kind: 'SPEED_LIMIT', latE7: lat, lngE7: lng, speedKmh: 1, nowMs: 1),
          throwsA(isA<TrafficRepositoryException>()));
      await repo.delete(id);
      expect(await repo.list(), isEmpty);
    });

    test('duyet bao cao ADD tao diem, REMOVE tao diem an, tu choi khong tao', () async {
      final int a = await reports.create(
          kind: 'maxSpeed', proposed: <String, dynamic>{'action': 'ADD', 'speedKmh': 40},
          latE7: lat, lngE7: lng, nowMs: 10);
      final int b = await reports.create(
          kind: 'speedCamera', proposed: <String, dynamic>{'action': 'REMOVE'}, latE7: lat, lngE7: lng, nowMs: 11);
      final int c = await reports.create(
          kind: 'tollBooth', proposed: <String, dynamic>{'action': 'ADD'}, latE7: lat, lngE7: lng, nowMs: 12);
      expect(await repo.pendingCount(), 3);
      List<TrafficReportItem> all = await reports.list();
      TrafficReportItem byId(int id) => all.firstWhere((TrafficReportItem r) => r.id == id);
      await repo.approveReport(byId(a), nowMs: 20);
      await repo.approveReport(byId(b), nowMs: 21);
      await repo.rejectReport(c, nowMs: 22);
      all = await reports.list();
      expect(byId(a).status, 'APPROVED');
      expect(byId(b).status, 'APPROVED');
      expect(byId(c).status, 'REJECTED');
      expect(await repo.pendingCount(), 0);
      final List<TrafficOverrideItem> ov = await repo.list();
      expect(ov.length, 2);
      expect(ov.where((TrafficOverrideItem o) => o.isRemoval).length, 1);
      expect(ov.firstWhere((TrafficOverrideItem o) => !o.isRemoval).speedKmh, 40);
      // Duyet lai bao cao da xu ly bi tu choi.
      await expectLater(repo.approveReport(byId(a), nowMs: 30), throwsA(isA<TrafficRepositoryException>()));
      expect((await repo.list()).length, 2);
    });
  });
}
