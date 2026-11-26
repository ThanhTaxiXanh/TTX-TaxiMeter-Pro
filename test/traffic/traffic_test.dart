import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ttx/domain/traffic/traffic_models.dart';

import '../test_support.dart';

Uint8List pack(List<List<int>> recs) {
  final ByteData b = ByteData(8 + recs.length * 13);
  final List<int> m = utf8.encode('TSG1');
  for (int i = 0; i < 4; i++) {
    b.setUint8(i, m[i]);
  }
  b.setUint32(4, recs.length, Endian.little);
  for (int i = 0; i < recs.length; i++) {
    final int o = 8 + i * 13;
    final List<int> r = recs[i]; // lat, lng, cat, dir, val
    b.setInt32(o, r[0], Endian.little);
    b.setInt32(o + 4, r[1], Endian.little);
    b.setUint8(o + 8, r[2]);
    b.setUint16(o + 9, r[3], Endian.little);
    b.setUint16(o + 11, r[4], Endian.little);
  }
  return b.buffer.asUint8List();
}

const int lat0 = 210000000; // 21 do Bac
const int lng0 = 1061000000;

void main() {
  test('bearing: bon huong chinh va duong cheo', () {
    expect(bearingDegrees(0, 100), 0);
    expect(bearingDegrees(100, 0), 90);
    expect(bearingDegrees(0, -100), 180);
    expect(bearingDegrees(-100, 0), 270);
    expect(bearingDegrees(100, 100), 45);
    expect(bearingDegrees(100, -100), 135);
    expect(bearingDegrees(-100, -100), 225);
    expect(bearingDegrees(-100, 100), 315);
    expect((bearingDegrees(100, 50) - 63).abs() <= 1, isTrue); // atan2(100,50)=63.4
    expect(bearingDegrees(0, 0), 0);
  });

  test('angleDiff', () {
    expect(angleDiffDeg(10, 350), 20);
    expect(angleDiffDeg(0, 180), 180);
    expect(angleDiffDeg(90, 90), 0);
  });

  test('doc signs.bin, loi dinh dang', () {
    final SignIndex i = SignIndex.fromBytes(pack(<List<int>>[
      <int>[lat0, lng0, 2, 90, 50],
      <int>[lat0, lng0, 7, 65535, 65535],
    ]));
    expect(i.signs, hasLength(2));
    expect(i.signs[0].kind, SignKind.maxSpeed);
    expect(i.signs[0].speedKmh, 50);
    expect(i.signs[1].dirDeg, -1);
    expect(i.signs[1].speedKmh, -1);
    expect(() => SignIndex.fromBytes(Uint8List(3)), throwsFormatException);
    expect(() => SignIndex.fromBytes(pack(<List<int>>[<int>[0, 0, 99, 0, 0]])), throwsFormatException);
  });

  test('nearby: loc theo ban kinh, gan nhat truoc, qua ranh gioi o luoi', () {
    final int d100 = latE7ForMeters(100);
    final int d900 = latE7ForMeters(900);
    final int d2000 = latE7ForMeters(2000);
    final SignIndex i = SignIndex.fromBytes(pack(<List<int>>[
      <int>[lat0 + d900, lng0, 6, 65535, 65535],
      <int>[lat0 + d100, lng0, 2, 0, 60],
      <int>[lat0 + d2000, lng0, 7, 65535, 65535],
    ]));
    final List<NearbySign> n = i.nearby(lat0, lng0, 1000);
    expect(n.map((NearbySign e) => e.sign.kind), <SignKind>[SignKind.maxSpeed, SignKind.speedCamera]);
    expect((n.first.distanceM - 100).abs() <= 1, isTrue);
    expect(n.first.bearingDeg, 0);
    expect(i.nearby(lat0, lng0, 50), isEmpty);
    expect(i.nearby(lat0, lng0, 3000), hasLength(3));
  });

  test('gioi han toc do va bien phia truoc theo huong di', () {
    final int d = latE7ForMeters(100);
    final SignIndex i = SignIndex.fromBytes(pack(<List<int>>[
      <int>[lat0 + d, lng0, 2, 0, 60], // phia Bac, ap dung xe huong Bac
      <int>[lat0 - d, lng0, 2, 180, 40], // phia Nam, xe huong Nam
      <int>[lat0 + d, lng0, 6, 65535, 65535], // camera phia Bac
    ]));
    final List<NearbySign> n = i.nearby(lat0, lng0, 300);
    expect(currentSpeedLimit(n, 0)!.sign.speedKmh, 60);
    expect(currentSpeedLimit(n, 180)!.sign.speedKmh, 40);
    expect(currentSpeedLimit(n, 90), isNull); // huong Dong: khong bien nao ap dung
    final List<NearbySign> ahead = signsAhead(n, 0);
    expect(ahead.map((NearbySign e) => e.sign.kind), containsAll(<SignKind>[SignKind.maxSpeed, SignKind.speedCamera]));
    expect(ahead.any((NearbySign e) => e.sign.speedKmh == 40), isFalse);
  });

  test('HeadingTracker', () {
    final HeadingTracker h = HeadingTracker();
    h.update(lat0, lng0);
    expect(h.headingDeg, -1);
    h.update(lat0 + 1, lng0); // < 5 m
    expect(h.headingDeg, -1);
    h.update(lat0 + latE7ForMeters(20), lng0);
    expect(h.headingDeg, 0);
    h.update(lat0 + latE7ForMeters(20), lng0 + 400);
    expect(h.headingDeg, 90);
  });

  test('POI json', () {
    final List<Poi> p = parsePoiJson(
        '{"kinds":["fuel","charging_station"],"poi":[[210000000,1061000000,0,"Tram A"],[1,2,1,""]]}');
    expect(p, hasLength(2));
    expect(p[0].kind, 'fuel');
    expect(p[0].name, 'Tram A');
    expect(p[1].kind, 'charging_station');
  });

  test('du lieu that: assets/data/signs.bin va poi.json doc duoc', () {
    final SignIndex i = SignIndex.fromBytes(File('assets/data/signs.bin').readAsBytesSync());
    expect(i.signs.length, 70971);
    expect(i.signs.where((TrafficSign s) => s.kind == SignKind.maxSpeed).length, 23912);
    expect(i.signs.where((TrafficSign s) => s.kind == SignKind.speedCamera).length, 1550);
    final TrafficSign s0 = i.signs.first;
    expect(s0.latE7, 85712080); // 8.571208
    expect(s0.lngE7, 1048305840);
    expect(s0.speedKmh, 40);
    expect(s0.dirDeg, 204);
    final List<Poi> p = parsePoiJson(File('assets/data/poi.json').readAsStringSync());
    expect(p.length, 5311);
    expect(p.where((Poi e) => e.kind == 'fuel').length, 4899);
  });
}
