import '../../core/geo.dart';
import 'traffic_models.dart';

/// Loai ban ghi sua tay (khop cot kind cua bang traffic_override).
const List<String> overrideKinds = <String>['SPEED_LIMIT', 'SIGN', 'CAMERA'];

/// source = 'REMOVE': an bien nguon cung loai trong [removeRadiusM] quanh diem nay.
const String sourceManual = 'MANUAL';
const String sourceReport = 'REPORT';
const String sourceRemove = 'REMOVE';
const int removeRadiusM = 30;

class TrafficOverrideItem {
  const TrafficOverrideItem({
    required this.id,
    required this.kind,
    required this.latE7,
    required this.lngE7,
    this.speedKmh,
    this.signCode,
    this.cameraType,
    this.source = sourceManual,
    this.validTo,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String kind;
  final int? latE7;
  final int? lngE7;
  final int? speedKmh;
  final String? signCode; // SignKind.name khi kind = SIGN
  final String? cameraType; // 'speedCamera' | 'streetCamera' khi kind = CAMERA
  final String source;
  final int? validTo;
  final String? note;
  final int createdAt;
  final int updatedAt;

  bool get isRemoval => source == sourceRemove;

  /// Loai bien tuong ung tren ban do (null neu khong xac dinh duoc).
  SignKind? get signKind {
    switch (kind) {
      case 'SPEED_LIMIT':
        return SignKind.maxSpeed;
      case 'CAMERA':
        return _byName(cameraType) ?? SignKind.speedCamera;
      case 'SIGN':
        return _byName(signCode);
    }
    return null;
  }

  static SignKind? _byName(String? n) {
    if (n == null) return null;
    for (final SignKind k in SignKind.values) {
      if (k.name == n) return k;
    }
    return null;
  }
}

/// Kiem tra du lieu nhap tay; tra ve thong bao loi tieng Viet hoac null neu hop le.
String? validateOverride({
  required String kind,
  required int? latE7,
  required int? lngE7,
  required int? speedKmh,
  required String? signCode,
  required String? cameraType,
}) {
  if (!overrideKinds.contains(kind)) return 'Loại không hợp lệ.';
  if (latE7 == null || lngE7 == null) return 'Cần tọa độ.';
  if (latE7 < -900000000 || latE7 > 900000000 || lngE7 < -1800000000 || lngE7 > 1800000000) {
    return 'Tọa độ ngoài phạm vi.';
  }
  if (kind == 'SPEED_LIMIT') {
    if (speedKmh == null || speedKmh < 5 || speedKmh > 130) return 'Tốc độ phải từ 5 đến 130 km/h.';
  } else if (kind == 'SIGN') {
    final SignKind? k = TrafficOverrideItem._byName(signCode);
    if (k == null || k == SignKind.speedCamera || k == SignKind.streetCamera) return 'Chọn loại biển.';
    if (k == SignKind.maxSpeed && (speedKmh == null || speedKmh < 5 || speedKmh > 130)) {
      return 'Tốc độ phải từ 5 đến 130 km/h.';
    }
  } else {
    if (cameraType != 'speedCamera' && cameraType != 'streetCamera') return 'Chọn loại camera.';
  }
  return null;
}

/// Ap dung sua tay len du lieu nguon: them diem moi, an diem bi bao "khong con".
/// Ban ghi het han (validTo < nowMs) bi bo qua.
List<TrafficSign> applyOverrides(List<TrafficSign> base, List<TrafficOverrideItem> overrides, int nowMs) {
  final List<TrafficOverrideItem> active = overrides
      .where((TrafficOverrideItem o) =>
          o.latE7 != null && o.lngE7 != null && o.signKind != null && (o.validTo == null || o.validTo! >= nowMs))
      .toList();
  final List<TrafficOverrideItem> removals = active.where((TrafficOverrideItem o) => o.isRemoval).toList();
  final List<TrafficSign> out = <TrafficSign>[];
  for (final TrafficSign s in base) {
    bool hidden = false;
    for (final TrafficOverrideItem r in removals) {
      if (r.signKind == s.kind && distanceMm(r.latE7!, r.lngE7!, s.latE7, s.lngE7) <= removeRadiusM * 1000) {
        hidden = true;
        break;
      }
    }
    if (!hidden) out.add(s);
  }
  for (final TrafficOverrideItem o in active) {
    if (o.isRemoval) continue;
    final SignKind k = o.signKind!;
    out.add(TrafficSign(
      latE7: o.latE7!,
      lngE7: o.lngE7!,
      kind: k,
      dirDeg: -1,
      speedKmh: k == SignKind.maxSpeed ? (o.speedKmh ?? -1) : -1,
    ));
  }
  return out;
}

/// Doi chuoi do thap phan ("10.7769") thanh E7 chi bang so nguyen; sai dinh dang -> null.
int? parseDegreesE7(String text) {
  final String t = text.trim().replaceAll(',', '.');
  final RegExpMatch? m = RegExp(r'^(-?)(\d{1,3})(?:\.(\d{0,9}))?$').firstMatch(t);
  if (m == null) return null;
  final int whole = int.parse(m.group(2)!);
  final String frac = ((m.group(3) ?? '') + '0000000').substring(0, 7);
  final int v = whole * 10000000 + int.parse(frac);
  return m.group(1) == '-' ? -v : v;
}

/// E7 -> chuoi do ("10.7769000") bang so nguyen.
String formatDegreesE7(int e7) {
  final bool neg = e7 < 0;
  final int a = neg ? -e7 : e7;
  final String frac = (a % 10000000).toString().padLeft(7, '0');
  return '${neg ? '-' : ''}${a ~/ 10000000}.$frac';
}
