import 'dart:convert';

import 'pmtiles_reader.dart';

bool _has(String id, List<String> words) {
  final String s = id.toLowerCase();
  return words.any(s.contains);
}

/// Sinh style MapLibre (nen toi) tu danh sach lop vector trong metadata PMTiles.
/// Khong biet truoc schema (OpenMapTiles/Protomaps...) nen to mau theo ten lop.
/// Chua ve nhan chu (can font glyph offline — de sau).
String buildMapStyleJson({
  required int port,
  required PmTilesHeader header,
  required Map<String, dynamic> metadata,
  bool light = false,
}) {
  final _Palette c = light ? _Palette.light : _Palette.dark;
  final String ext = header.tileType == 1 ? 'mvt' : (header.tileType == 2 ? 'png' : 'jpg');
  final String url = 'http://127.0.0.1:$port/tiles/{z}/{x}/{y}.$ext';
  final Map<String, dynamic> source = <String, dynamic>{
    'type': header.tileType == 1 ? 'vector' : 'raster',
    'tiles': <String>[url],
    'minzoom': header.minZoom,
    'maxzoom': header.maxZoom,
    if (header.tileType != 1) 'tileSize': 256,
  };
  final List<Map<String, dynamic>> layers = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'background',
      'type': 'background',
      'paint': <String, dynamic>{'background-color': c.background},
    },
  ];

  if (header.tileType != 1) {
    layers.add(<String, dynamic>{'id': 'raster', 'type': 'raster', 'source': 'v'});
  } else {
    final List<String> ids = <String>[];
    final Object? vl = metadata['vector_layers'];
    if (vl is List) {
      for (final Object? e in vl) {
        if (e is Map && e['id'] is String) ids.add(e['id'] as String);
      }
    }
    // Thu tu ve: nen/dat -> nuoc -> cong trinh -> duong -> con lai.
    int rank(String id) {
      if (_has(id, <String>['earth', 'landcover', 'landuse', 'park', 'green'])) return 0;
      if (_has(id, <String>['water', 'ocean', 'lake', 'river'])) return 1;
      if (_has(id, <String>['building'])) return 2;
      if (_has(id, <String>['road', 'transport', 'street', 'highway', 'path'])) return 3;
      return 4;
    }

    ids.sort((String a, String b) => rank(a).compareTo(rank(b)));
    for (final String id in ids) {
      final int r = rank(id);
      if (_has(id, <String>['place', 'poi', 'label', 'housenumber', 'name'])) continue;
      final String fillColor = r == 0
          ? (_has(id, <String>['park', 'green', 'landcover']) ? c.park : c.land)
          : r == 1
              ? c.water
              : r == 2
                  ? c.building
                  : c.land;
      if (r == 2) {
        // Cong trinh 3D: dung chieu cao trong du lieu, mac dinh 9 m.
        layers.add(<String, dynamic>{
          'id': '$id-3d',
          'type': 'fill-extrusion',
          'source': 'v',
          'source-layer': id,
          'minzoom': 14,
          'filter': <Object>['==', r'$type', 'Polygon'],
          'paint': <String, dynamic>{
            'fill-extrusion-color': c.building,
            'fill-extrusion-opacity': 0.9,
            'fill-extrusion-height': <Object>[
              'coalesce', <Object>['get', 'render_height'], <Object>['get', 'height'], 9,
            ],
            'fill-extrusion-base': <Object>[
              'coalesce', <Object>['get', 'render_min_height'], <Object>['get', 'min_height'], 0,
            ],
          },
        });
        continue;
      }
      layers.add(<String, dynamic>{
        'id': '$id-fill',
        'type': 'fill',
        'source': 'v',
        'source-layer': id,
        'filter': <Object>['==', r'$type', 'Polygon'],
        'paint': <String, dynamic>{'fill-color': fillColor},
      });
      if (r == 1) {
        layers.add(<String, dynamic>{
          'id': '$id-line',
          'type': 'line',
          'source': 'v',
          'source-layer': id,
          'filter': <Object>['==', r'$type', 'LineString'],
          'paint': <String, dynamic>{'line-color': c.waterLine, 'line-width': 1.2},
        });
      } else if (r == 3) {
        layers.add(<String, dynamic>{
          'id': '$id-line',
          'type': 'line',
          'source': 'v',
          'source-layer': id,
          'filter': <Object>['==', r'$type', 'LineString'],
          'layout': <String, dynamic>{'line-cap': 'round', 'line-join': 'round'},
          'paint': <String, dynamic>{
            'line-color': c.road,
            'line-width': <Object>[
              'interpolate', <String>['linear'], <String>['zoom'], 10, 0.4, 14, 1.6, 18, 7,
            ],
          },
        });
      } else if (r == 4 && _has(id, <String>['boundar', 'admin'])) {
        layers.add(<String, dynamic>{
          'id': '$id-line',
          'type': 'line',
          'source': 'v',
          'source-layer': id,
          'filter': <Object>['==', r'$type', 'LineString'],
          'paint': <String, dynamic>{'line-color': c.boundary, 'line-width': 0.8, 'line-dasharray': <num>[3, 2]},
        });
      }
    }
  }

  return jsonEncode(<String, dynamic>{
    'version': 8,
    'name': 'TTX offline',
    'sources': <String, dynamic>{'v': source},
    'layers': layers,
  });
}

class _Palette {
  const _Palette({
    required this.background,
    required this.land,
    required this.park,
    required this.water,
    required this.waterLine,
    required this.building,
    required this.road,
    required this.boundary,
  });

  final String background, land, park, water, waterLine, building, road, boundary;

  static const _Palette dark = _Palette(
    background: '#0f1417',
    land: '#141b1f',
    park: '#16301f',
    water: '#12304a',
    waterLine: '#1f5a85',
    building: '#2b343a',
    road: '#8d9aa2',
    boundary: '#4a5560',
  );

  static const _Palette light = _Palette(
    background: '#eceff1',
    land: '#f4f2ec',
    park: '#cde6c3',
    water: '#a9cdeb',
    waterLine: '#7fb2dc',
    building: '#d6d1c8',
    road: '#ffffff',
    boundary: '#b0a9a0',
  );
}
