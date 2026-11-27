import 'traffic_models.dart';

/// Ten anh bieu tuong tren ban do cho tung bien / POI.
String signIconName(TrafficSign s) {
  if (s.kind == SignKind.maxSpeed && s.speedKmh > 0) return 'sign_speed_${s.speedKmh}';
  if (s.kind == SignKind.other && s.code != null) return 'sign_code:${s.code}';
  return 'sign_${s.kind.name}';
}

String poiIconName(Poi p) => p.kind == 'fuel' ? 'poi_fuel' : 'poi_ev';

/// Mau cham tren ban do theo loai bien (chi de hien thi).
String signColor(SignKind k) {
  switch (k) {
    case SignKind.speedCamera:
    case SignKind.streetCamera:
      return '#ff5252';
    case SignKind.maxSpeed:
      return '#ffffff';
    case SignKind.tollBooth:
      return '#ffb300';
    case SignKind.builtUpStart:
    case SignKind.builtUpEnd:
      return '#4fc3f7';
    case SignKind.tunnel:
    case SignKind.restArea:
      return '#ba68c8';
    case SignKind.noOvertaking:
      return '#ff8a65';
    case SignKind.p133:
      return '#81c784';
    case SignKind.other:
      return '#90caf9';
  }
}

String signLabel(SignKind k) {
  switch (k) {
    case SignKind.speedCamera:
      return 'Camera bắn tốc độ';
    case SignKind.streetCamera:
      return 'Camera giám sát';
    case SignKind.maxSpeed:
      return 'Tốc độ tối đa';
    case SignKind.tollBooth:
      return 'Trạm thu phí';
    case SignKind.builtUpStart:
      return 'Bắt đầu khu đông dân cư';
    case SignKind.builtUpEnd:
      return 'Hết khu đông dân cư';
    case SignKind.tunnel:
      return 'Hầm';
    case SignKind.restArea:
      return 'Điểm dừng nghỉ';
    case SignKind.noOvertaking:
      return 'Cấm vượt';
    case SignKind.p133:
      return 'Hết cấm vượt';
    case SignKind.other:
      return 'Biển báo';
  }
}

/// Ten hien thi day du: bien khac -> kem ma (vd 'Biển P.103a').
String signDisplayName(TrafficSign s) {
  if (s.kind == SignKind.other && s.code != null) return 'Biển ${s.code}';
  if (s.kind == SignKind.maxSpeed && s.speedKmh > 0) return '${signLabel(s.kind)} ${s.speedKmh}';
  return signLabel(s.kind);
}

Map<String, dynamic> signsGeoJson(Iterable<NearbySign> signs) => <String, dynamic>{
      'type': 'FeatureCollection',
      'features': <Map<String, dynamic>>[
        for (final NearbySign n in signs)
          <String, dynamic>{
            'type': 'Feature',
            'geometry': <String, dynamic>{
              'type': 'Point',
              // Chi de ve ban do: toa do thuc (do), khong anh huong cuoc.
              'coordinates': <double>[n.sign.lngE7 / 1e7, n.sign.latE7 / 1e7],
            },
            'properties': <String, dynamic>{
              'color': signColor(n.sign.kind),
              'icon': signIconName(n.sign),
              'kind': n.sign.kind.name,
              'speed': n.sign.speedKmh,
            },
          },
      ],
    };

Map<String, dynamic> poiGeoJson(Iterable<Poi> poi) => <String, dynamic>{
      'type': 'FeatureCollection',
      'features': <Map<String, dynamic>>[
        for (final Poi p in poi)
          <String, dynamic>{
            'type': 'Feature',
            'geometry': <String, dynamic>{
              'type': 'Point',
              'coordinates': <double>[p.lngE7 / 1e7, p.latE7 / 1e7],
            },
            'properties': <String, dynamic>{
              'name': p.name,
              'kind': p.kind,
              'color': p.kind == 'fuel' ? '#ffd54f' : '#29b6f6',
              'icon': poiIconName(p),
            },
          },
      ],
    };
