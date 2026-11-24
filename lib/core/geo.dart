// PURE: chi so nguyen (khong so thuc), khong I/O.
//
// Khoang cach equirectangular tren so nguyen. Don vi vao: lat_e7/lng_e7.
// Don vi ra: milimet (mm). Quyet dinh kien truc (Phase 1): khong doi sau nay,
// neu doi phai cap nhat golden replay.

/// 1 do vi do ~ 111_195 m (ban kinh Trai Dat trung binh 6_371_000 m).
const int _mmPerE7Num = 111195; // mm = dE7 * 111195 ~/ 10000
const int _mmPerE7Den = 10000;

/// cos(do) * 1e6, do = 0..90.
const List<int> _cosPpm = <int>[
  1000000, 999848, 999391, 998630, 997564, 996195, 994522, 992546, 990268,
  987688, 984808, 981627, 978148, 974370, 970296, 965926, 961262, 956305,
  951057, 945519, 939693, 933580, 927184, 920505, 913545, 906308, 898794,
  891007, 882948, 874620, 866025, 857167, 848048, 838671, 829038, 819152,
  809017, 798636, 788011, 777146, 766044, 754710, 743145, 731354, 719340,
  707107, 694658, 681998, 669131, 656059, 642788, 629320, 615661, 601815,
  587785, 573576, 559193, 544639, 529919, 515038, 500000, 484810, 469472,
  453990, 438371, 422618, 406737, 390731, 374607, 358368, 342020, 325568,
  309017, 292372, 275637, 258819, 241922, 224951, 207912, 190809, 173648,
  156434, 139173, 121869, 104528, 87156, 69756, 52336, 34899, 17452, 0,
];

const int _e7PerDegree = 10000000;

/// cos(vi do) * 1e6, noi suy tuyen tinh theo bang do nguyen. latE7 co dau.
int cosPpmForLatE7(int latE7) {
  final int a = latE7.abs();
  int idx = a ~/ _e7PerDegree;
  if (idx >= 90) return 0;
  final int frac = a % _e7PerDegree;
  final int c0 = _cosPpm[idx];
  final int c1 = _cosPpm[idx + 1];
  return c0 + (c1 - c0) * frac ~/ _e7PerDegree;
}

/// Can bac hai nguyen (floor) cua n >= 0.
int isqrt(int n) {
  if (n <= 0) return 0;
  int x = n;
  int y = (x + 1) ~/ 2;
  while (y < x) {
    x = y;
    y = (x + n ~/ x) ~/ 2;
  }
  return x;
}

/// Khoang cach giua hai diem, don vi mm (so nguyen, xac dinh).
int distanceMm(int lat1E7, int lng1E7, int lat2E7, int lng2E7) {
  final int dLat = lat2E7 - lat1E7;
  final int dLng = lng2E7 - lng1E7;
  final int cosPpm = cosPpmForLatE7((lat1E7 + lat2E7) ~/ 2);
  final int dyMm = dLat * _mmPerE7Num ~/ _mmPerE7Den;
  final int dxMm = dLng * _mmPerE7Num ~/ _mmPerE7Den * cosPpm ~/ 1000000;
  return isqrt(dxMm * dxMm + dyMm * dyMm);
}
