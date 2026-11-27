import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ttx/data/bank/bank_repository.dart';
import 'package:ttx/data/db/app_database.dart';
import 'package:ttx/data/map/road_info.dart';
import 'package:ttx/data/map/style_adapter.dart';
import 'package:ttx/data/map/street_name.dart';
import 'package:ttx/data/tariff/tariff_repository.dart';
import 'package:ttx/domain/tariff/default_tariff.dart';
import 'package:ttx/domain/traffic/speed_limit.dart';
import 'package:ttx/ui/map/report_sheet.dart';
import 'package:ttx/ui/payment/bank_picker.dart';


RoadInfo road(RoadClass c, {String name = '', bool oneway = false, bool ramp = false, bool urban = true}) =>
    RoadInfo(cls: c, name: name, oneway: oneway, ramp: ramp, urbanHint: urban);

void main() {
  group('gioi han toc do mac dinh (QCVN 41 / TT 38/2024, taxi)', () {
    test('trong khu dan cu: 50, duong doi 60', () {
      expect(defaultLimitKmh(road(RoadClass.tertiary), urban: true), 50);
      expect(defaultLimitKmh(road(RoadClass.primary), urban: true), 50);
      expect(defaultLimitKmh(road(RoadClass.primary, oneway: true), urban: true), 60);
    });
    test('ngoai khu dan cu: 80, duong doi 90, cao toc 100', () {
      expect(defaultLimitKmh(road(RoadClass.secondary), urban: false), 80);
      expect(defaultLimitKmh(road(RoadClass.trunk, oneway: true), urban: false), 90);
      expect(defaultLimitKmh(road(RoadClass.motorway), urban: false), 100);
    });
    test('duong gom/service thap hon duong chinh', () {
      expect(defaultLimitKmh(road(RoadClass.service), urban: true), lessThan(50));
      expect(defaultLimitKmh(road(RoadClass.service), urban: false), 60);
    });
  });

  group('SpeedLimitTracker', () {
    test('cao toc 100 -> re xuong duong gom -> duong tinh: khong con 100', () {
      final SpeedLimitTracker t = SpeedLimitTracker();
      final RoadInfo hw = road(RoadClass.motorway, name: 'CT.01', urban: false);
      t.onRoad(hw);
      t.onSignPassed(100);
      t.onRoad(hw, movedM: 500);
      expect(t.limitKmh, 100);
      expect(t.fromSign, isTrue);
      final RoadInfo gom = road(RoadClass.service, name: 'Duong gom', urban: false);
      for (int i = 0; i < 3; i++) {
        t.onRoad(gom);
      }
      expect(t.fromSign, isFalse);
      expect(t.limitKmh, 60);
      final RoadInfo tinh = road(RoadClass.secondary, name: 'DT295', urban: false);
      for (int i = 0; i < 3; i++) {
        t.onRoad(tinh);
      }
      expect(t.limitKmh, 80);
    });

    test('doi tuyen thoang qua (1-2 mau) khong lam mat bien', () {
      final SpeedLimitTracker t = SpeedLimitTracker();
      final RoadInfo a = road(RoadClass.primary, name: 'QL1', urban: false);
      t.onRoad(a);
      t.onSignPassed(70);
      t.onRoad(road(RoadClass.service, name: 'x', urban: false));
      t.onRoad(road(RoadClass.service, name: 'x', urban: false));
      t.onRoad(a);
      expect(t.limitKmh, 70);
    });

    test('vao khu dan cu can 3 mau lien tiep moi doi muc mac dinh', () {
      final SpeedLimitTracker t = SpeedLimitTracker();
      t.onRoad(road(RoadClass.primary, name: 'QL1', urban: false));
      t.onRoad(road(RoadClass.primary, name: 'QL1', urban: false));
      t.onRoad(road(RoadClass.primary, name: 'QL1', urban: false));
      expect(t.limitKmh, 80);
      t.onRoad(road(RoadClass.primary, name: 'QL1'));
      expect(t.limitKmh, 80);
      t.onRoad(road(RoadClass.primary, name: 'QL1'));
      t.onRoad(road(RoadClass.primary, name: 'QL1'));
      expect(t.limitKmh, 50);
    });

    test('mat du lieu duong: giu bien toi da 1500 m roi bo', () {
      final SpeedLimitTracker t = SpeedLimitTracker();
      t.onRoad(road(RoadClass.primary, name: 'QL1', urban: false));
      t.onSignPassed(60);
      t.onRoad(null, movedM: 1000);
      expect(t.limitKmh, 60);
      t.onRoad(null, movedM: 600);
      expect(t.fromSign, isFalse);
    });
  });

  test('roadInfoAt: chon duong gan nhat, doc oneway/ramp, nha dong -> khu dan cu', () {
    final MvtFeature a = MvtFeature(2, <String, String>{'class': 'primary', 'oneway': '1'}, <List<(int, int)>>[
      <(int, int)>[(0, 100), (4096, 100)]
    ]);
    final MvtFeature b = MvtFeature(2, <String, String>{'class': 'service'}, <List<(int, int)>>[
      <(int, int)>[(0, 2000), (4096, 2000)]
    ]);
    final List<(int, int)> houses = <(int, int)>[for (int i = 0; i < 15; i++) (1000 + i, 120)];
    final RoadInfo? r = roadInfoAt(<MvtFeature>[a, b], <NamedLine>[NamedLine('Quoc lo 1', <(int, int)>[(0, 100), (4096, 100)])], houses, 1000, 110);
    expect(r, isNotNull);
    expect(r!.cls, RoadClass.primary);
    expect(r.oneway, isTrue);
    expect(r.name, 'Quoc lo 1');
    expect(r.urbanHint, isTrue);
    expect(roadInfoAt(<MvtFeature>[a], const <NamedLine>[], const <(int, int)>[], 1000, 110)!.urbanHint, isFalse);
    expect(roadInfoAt(<MvtFeature>[b], const <NamedLine>[], const <(int, int)>[], 1000, 110), isNull);
  });

  test('style: nhan ten duong chay doc theo duong, huong vao man hinh', () {
    final String style = jsonEncode(<String, dynamic>{
      'version': 8,
      'layers': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'highway-name-major',
          'type': 'symbol',
          'source': 'openmaptiles',
          'source-layer': 'transportation_name',
          'layout': <String, dynamic>{'text-field': '{name}', 'text-font': <String>['Noto Sans Regular']},
        },
        <String, dynamic>{'id': 'w', 'type': 'fill', 'source': 'openmaptiles', 'source-layer': 'water'},
        <String, dynamic>{'id': 't', 'type': 'line', 'source': 'openmaptiles', 'source-layer': 'transportation'},
      ],
    });
    final String? out = adaptStyleForOffline(
      styleJson: style,
      port: 1,
      minZoom: 0,
      maxZoom: 14,
      availableLayers: <String>{'transportation', 'transportation_name', 'water'},
    );
    final Map<String, dynamic> l = (jsonDecode(out!)['layers'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .firstWhere((Map<String, dynamic> e) => e['id'] == 'highway-name-major');
    final Map<String, dynamic> lay = l['layout'] as Map<String, dynamic>;
    expect(lay['symbol-placement'], 'line');
    expect(lay['text-pitch-alignment'], 'viewport');
    expect(lay['text-keep-upright'], true);
  });

  test('bao cao chi gom Bien cam va Hieu lenh', () {
    expect(reportGroups.keys.toList(), <String>['P', 'R']);
  });

  test('tim ngan hang theo ten, ma, BIN, khong dau', () {
    const List<BankInfo> banks = <BankInfo>[
      BankInfo(bin: '970436', code: 'VCB', shortName: 'Vietcombank'),
      BankInfo(bin: '970422', code: 'MB', shortName: 'MB Bank'),
    ];
    expect(filterBanks(banks, 'vcb').single.code, 'VCB');
    expect(filterBanks(banks, 'viet').single.code, 'VCB');
    expect(filterBanks(banks, '970422').single.code, 'MB');
    expect(filterBanks(banks, ''), hasLength(2));
    expect(filterBanks(banks, 'zzz'), isEmpty);
  });

  test('km <-> met bang so nguyen', () {
    expect(parseKmToMeters('0.8'), 800);
    expect(parseKmToMeters('30'), 30000);
    expect(parseKmToMeters('1,25'), 1250);
    expect(parseKmToMeters('1.2345'), isNull);
    expect(parseKmToMeters('a'), isNull);
    expect(metersToKmText(800), '0.8');
    expect(metersToKmText(30000), '30');
  });

  group('co so du lieu', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() async => db.close());

    test('nhieu tai khoan: tai khoan dau la mac dinh, doi mac dinh, xoa mac dinh -> chuyen sang tai khoan con lai', () async {
      final BankRepository r = BankRepository(db);
      final int a = await r.saveAccount(const DriverAccount(bin: '970436', accountNumber: '111', holder: 'A'), 1);
      final int b = await r.saveAccount(const DriverAccount(bin: '970422', accountNumber: '222', holder: 'B'), 2);
      expect((await r.getDriverAccount())!.id, a);
      await r.setDefault(b);
      final List<DriverAccount> l = await r.listAccounts();
      expect(l.first.id, b);
      expect(l.where((DriverAccount x) => x.isDefault).length, 1);
      await r.deleteAccount(b);
      expect((await r.getDriverAccount())!.id, a);
      expect((await r.getDriverAccount())!.isDefault, isTrue);
    });

    test('logo giua/duoi duoc luu va doc lai', () async {
      final BankRepository r = BankRepository(db);
      final Uint8List png = Uint8List.fromList(<int>[137, 80, 78, 71, 1, 2, 3]);
      await r.saveAccount(
          DriverAccount(bin: '970436', accountNumber: '111', holder: 'A', centerLogo: png, bottomLogo: png), 1);
      final DriverAccount a = (await r.getDriverAccount())!;
      expect(a.centerLogo, png);
      expect(a.bottomLogo, png);
    });

    test('nhieu bieu gia: luu phien ban moi, chon dung, mot ACTIVE duy nhat', () async {
      final TariffRepository r = TariffRepository(db);
      final Map<String, dynamic> j7 = defaultTariffJson(effectiveFromMs: 0)..['configId'] = 'xe-7-cho';
      (j7['distanceTiers'] as List<dynamic>).insert(
          1, <String, dynamic>{'index': 1, 'upToMeters': 50000, 'pricePerKmVnd': 13000});
      (j7['distanceTiers'] as List<dynamic>)[2] = <String, dynamic>{'index': 2, 'upToMeters': null, 'pricePerKmVnd': 11000};
      await r.saveVersion(defaultTariffJson(effectiveFromMs: 0), nowMs: 1795489200000, activate: true);
      await r.saveVersion(j7, nowMs: 1795489200000 + 1, activate: false);
      List<TariffSummary> l = await r.listConfigs();
      expect(l.length, 2);
      expect(l.where((TariffSummary t) => t.active).single.configId, defaultTariffId);
      await r.select('xe-7-cho', nowMs: 1795489200000 + 2);
      l = await r.listConfigs();
      expect(l.where((TariffSummary t) => t.active).single.configId, 'xe-7-cho');
      expect((l.firstWhere((TariffSummary t) => t.configId == 'xe-7-cho').json['distanceTiers'] as List<dynamic>).length, 3);
      // sua lai bieu gia dang dung -> phien ban 2 van la ACTIVE
      await r.saveVersion(j7, nowMs: 1795489200000 + 3, activate: true);
      final TariffSummary t7 = (await r.listConfigs()).firstWhere((TariffSummary t) => t.configId == 'xe-7-cho');
      expect(t7.version, 2);
      expect(t7.active, isTrue);
    });

    test('bieu gia sai bac (khong tang dan) bi tu choi va khong ghi gi', () async {
      final TariffRepository r = TariffRepository(db);
      final Map<String, dynamic> j = defaultTariffJson(effectiveFromMs: 0);
      (j['distanceTiers'] as List<dynamic>).insert(
          0, <String, dynamic>{'index': 0, 'upToMeters': 40000, 'pricePerKmVnd': 15000});
      (j['distanceTiers'] as List<dynamic>)[1] = <String, dynamic>{'index': 1, 'upToMeters': 30000, 'pricePerKmVnd': 14000};
      await expectLater(r.saveVersion(j, nowMs: 1, activate: true), throwsA(isA<TariffImportException>()));
      expect(await r.listConfigs(), isEmpty);
    });
  });
}
