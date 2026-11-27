/// Gioi han toc do theo loai duong cho o to <= 8 cho (taxi), theo QCVN 41:2024/BGTVT
/// va Thong tu 38/2024/TT-BGTVT. Chi la gia tri MAC DINH khi khong co bien bao hieu luc.
///
///  - Khu vuc dong dan cu: duong doi (co dai phan cach giua) / mot chieu >= 2 lan: 60; con lai: 50.
///  - Ngoai khu vuc dong dan cu: duong doi / mot chieu >= 2 lan: 90; con lai: 80.
///  - Cao toc: theo bien (toi da 120); khong co bien thi dung 100.
/// Du lieu ban do khong cho biet so lan/dai phan cach, nen chi coi la "duong doi" khi la
/// duong oneway cap trunk/primary/secondary (hai chieu tach rieng) — uoc tinh than trong (thap hon).
enum RoadClass { motorway, trunk, primary, secondary, tertiary, minor, service, track, other }

RoadClass roadClassFromOmt(String cls) {
  switch (cls) {
    case 'motorway':
      return RoadClass.motorway;
    case 'trunk':
      return RoadClass.trunk;
    case 'primary':
      return RoadClass.primary;
    case 'secondary':
      return RoadClass.secondary;
    case 'tertiary':
      return RoadClass.tertiary;
    case 'minor':
      return RoadClass.minor;
    case 'service':
      return RoadClass.service;
    case 'track':
      return RoadClass.track;
    default:
      return RoadClass.other;
  }
}

class RoadInfo {
  const RoadInfo({
    required this.cls,
    this.name = '',
    this.oneway = false,
    this.ramp = false,
    this.expressway = false,
    this.urbanHint = true,
  });

  final RoadClass cls;
  final String name;
  final bool oneway;
  final bool ramp;
  final bool expressway;

  /// Goi y khu dan cu tu du lieu (mat do nha); tracker se lam muot.
  final bool urbanHint;

  /// Dinh danh tuyen: loai + ten. Doi tuyen = bien toc do cu het hieu luc.
  String get key => '${cls.name}|$name|${ramp ? 'r' : ''}';

  bool get isMotorway => (cls == RoadClass.motorway && !ramp) || expressway;
}

/// Toc do mac dinh (km/h) cho taxi tren [road]; [urban] la ket qua da lam muot.
int defaultLimitKmh(RoadInfo road, {required bool urban}) {
  if (road.isMotorway) return 100;
  if (road.ramp) return 50;
  switch (road.cls) {
    case RoadClass.service:
    case RoadClass.track:
      return urban ? 40 : 60;
    case RoadClass.minor:
      return urban ? 40 : 60;
    case RoadClass.other:
      return urban ? 30 : 50;
    case RoadClass.trunk:
    case RoadClass.primary:
    case RoadClass.secondary:
    case RoadClass.tertiary:
    case RoadClass.motorway:
      final bool dual = road.oneway &&
          (road.cls == RoadClass.trunk || road.cls == RoadClass.primary || road.cls == RoadClass.secondary);
      if (urban) return dual ? 60 : 50;
      return dual ? 90 : 80;
  }
}

/// Giu gioi han toc do dang hieu luc:
///  - Bien toc do chi hieu luc sau khi xe DA QUA bien, va chi ttren cung tuyen duong dat bien:
///    doi tuyen (vd cao toc -> duong gom -> duong tinh) la het hieu luc, quay ve mac dinh theo duong.
///  - Doi tuyen/khu dan cu can 3 mau lien tiep de tranh nhay khi GPS dao dong giua hai duong song song.
///  - Mat du lieu duong: giu bien toi da [maxNoRoadM] met roi bo.
class SpeedLimitTracker {
  SpeedLimitTracker({this.confirmSamples = 3, this.maxNoRoadM = 1500});

  final int confirmSamples;
  final int maxNoRoadM;

  int? _signKmh;
  String? _signKey;
  int _noRoadM = 0;
  int _lapse = 0;
  bool _urban = true;
  int _urbanFlip = 0;
  RoadInfo? _road;

  int get limitKmh {
    final int? s = _signKmh;
    if (s != null) return s;
    final RoadInfo? r = _road;
    return r == null ? 0 : defaultLimitKmh(r, urban: _urban);
  }

  bool get fromSign => _signKmh != null;
  RoadInfo? get road => _road;
  bool get urban => _urban;

  /// Xe vua di qua mot bien toc do toi da [kmh].
  void onSignPassed(int kmh) {
    _signKmh = kmh;
    _signKey = _road?.key;
    _noRoadM = 0;
    _lapse = 0;
  }

  /// Cap nhat theo duong hien tai ([road] null = khong co du lieu) va quang duong vua di [movedM].
  void onRoad(RoadInfo? road, {int movedM = 0}) {
    if (road == null) {
      if (_signKmh != null) {
        _noRoadM += movedM;
        if (_noRoadM > maxNoRoadM) _signKmh = null;
      }
      return;
    }
    _noRoadM = 0;
    // khu dan cu co tre
    if (road.urbanHint != _urban) {
      if (++_urbanFlip >= confirmSamples) {
        _urban = road.urbanHint;
        _urbanFlip = 0;
      }
    } else {
      _urbanFlip = 0;
    }
    if (_signKmh != null) {
      final String? k = _signKey;
      if (k == null) {
        _signKey = road.key; // bien nhan khi chua biet duong: gan vao tuyen dau tien thay
      } else if (k != road.key) {
        if (++_lapse >= confirmSamples) {
          _signKmh = null;
          _signKey = null;
          _lapse = 0;
        }
      } else {
        _lapse = 0;
      }
    }
    _road = road;
  }

  void reset() {
    _signKmh = null;
    _signKey = null;
    _road = null;
    _lapse = 0;
    _noRoadM = 0;
    _urbanFlip = 0;
  }
}
