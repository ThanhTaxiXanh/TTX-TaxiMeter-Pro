import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ttx/data/map/street_name.dart';
import 'package:ttx/domain/traffic/traffic_models.dart';

List<int> varint(int n) {
  final List<int> o = <int>[];
  while (n > 0x7F) {
    o.add((n & 0x7F) | 0x80);
    n >>= 7;
  }
  o.add(n);
  return o;
}

List<int> ld(int f, List<int> d) => <int>[(f << 3) | 2, ...varint(d.length), ...d];
int zz(int n) => (n << 1) ^ (n >> 31);

Uint8List tileWith(String layer, String name, List<(int, int)> pts) {
  final List<int> geom = <int>[(1 << 3) | 1, ...varint(zz(pts[0].$1)), ...varint(zz(pts[0].$2))];
  geom.add(((pts.length - 1) << 3) | 2);
  for (int i = 1; i < pts.length; i++) {
    geom
      ..addAll(varint(zz(pts[i].$1 - pts[i - 1].$1)))
      ..addAll(varint(zz(pts[i].$2 - pts[i - 1].$2)));
  }
  final List<int> feature = <int>[
    ...ld(2, <int>[0, 0]),
    ...<int>[(3 << 3), 2],
    ...ld(4, geom),
  ];
  final List<int> l = <int>[
    ...ld(1, utf8.encode(layer)),
    ...ld(2, feature),
    ...ld(3, utf8.encode('name')),
    ...ld(4, ld(1, utf8.encode(name))),
    ...<int>[(5 << 3), ...varint(4096)],
  ];
  return Uint8List.fromList(ld(3, l));
}

const int lat = 210000000, lng = 1062000000;
int eastE7(int meters) => meters * 100; // ~ 1 m = 100 E7 o vi do 21 (xap xi, du cho test)

TrafficSign sign(int dLngM, {int dLatM = 0, int dir = -1, SignKind k = SignKind.speedCamera}) =>
    TrafficSign(latE7: lat + dLatM * 90, lngE7: lng + dLngM * 96, kind: k, dirDeg: dir, speedKmh: -1);

void main() {
  test('MVT: doc ten duong va tim duong gan nhat', () {
    final Uint8List t = tileWith('transportation_name', 'Phố Yết Kiêu', <(int, int)>[(100, 100), (300, 100)]);
    final List<NamedLine> lines = decodeNamedLines(t);
    expect(lines.length, 1);
    expect(lines.first.name, 'Phố Yết Kiêu');
    expect(lines.first.points, <(int, int)>[(100, 100), (300, 100)]);
    expect(nearestStreetName(lines, 200, 130), 'Phố Yết Kiêu');
    expect(nearestStreetName(lines, 200, 400), isNull);
    expect(decodeNamedLines(tileWith('building', 'x', <(int, int)>[(0, 0), (1, 1)])), isEmpty);
  });

  test('tileOf: toa do tile hop ly', () {
    final (int x, int y, int px, int py) = tileOf(lat, lng, 14);
    expect(x, inInclusiveRange(0, 16383));
    expect(y, inInclusiveRange(0, 16383));
    expect(px, inInclusiveRange(0, 4096));
    expect(py, inInclusiveRange(0, 4096));
    // Hai diem cach nhau ~1 km theo kinh do lech ~ 1000 m / 0,6 m moi don vi tile ~ vai tram don vi.
    final (int x2, _, int px2, _) = tileOf(lat, lng + 96000, 14);
    expect(((x2 - x) * 4096 + px2 - px).abs(), inInclusiveRange(1200, 2200));
  });

  test('aheadSigns chi lay bien phia truoc trong 2 km', () {
    final SignIndex idx = SignIndex(<TrafficSign>[
      sign(500), // phia truoc (huong Dong)
      sign(1900), // phia truoc, gan 2 km
      sign(-500), // phia sau
      sign(3000), // qua 2 km
      sign(800, dir: 270), // phia truoc nhung ap dung cho chieu nguoc lai
    ]);
    final List<NearbySign> a = aheadSigns(idx, lat, lng, 90);
    expect(a.length, 2);
    expect(a.first.distanceM, lessThan(a.last.distanceM));
    // Khong biet huong -> moi phia trong 2 km.
    expect(aheadSigns(idx, lat, lng, -1).length, 4);
    // Xe di qua bien -> bien phia truoc bien mat khoi danh sach.
    final List<NearbySign> after = aheadSigns(idx, lat, lng + 96 * 600, 90);
    expect(after.length, 1); // chi con sign(1900) (sign(3000) van xa hon 2 km)
  });

  test('poiAhead loc theo huong va ban kinh', () {
    final List<Poi> poi = <Poi>[
      Poi(lat, lng + 96 * 800, 'fuel', 'truoc'),
      Poi(lat, lng - 96 * 800, 'fuel', 'sau'),
      Poi(lat, lng + 96 * 2500, 'fuel', 'xa'),
    ];
    final List<Poi> a = poiAhead(poi, lat, lng, 90);
    expect(a.map((Poi p) => p.name).toList(), <String>['truoc']);
    expect(poiAhead(poi, lat, lng, -1).length, 2);
  });

  test('needsAheadRefresh', () {
    bool n(int moveM, int hNow, {int hLast = 90, bool has = true}) => needsAheadRefresh(
        hasLast: has,
        lastLatE7: lat,
        lastLngE7: lng,
        lastHeadingDeg: hLast,
        latE7: lat,
        lngE7: lng + 96 * moveM,
        headingDeg: hNow);
    expect(n(0, 90, has: false), isTrue);
    expect(n(10, 90), isFalse);
    expect(n(45, 90), isTrue);
    expect(n(5, 120), isTrue);
    expect(n(5, 100), isFalse);
  });
}
