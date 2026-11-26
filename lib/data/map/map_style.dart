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
}) {
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
      'paint': <String, dynamic>{'background-color': '#0f1417'},
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
          ? (_has(id, <String>['park', 'green', 'landcover']) ? '#16301f' : '#141b1f')
          : r == 1
              ? '#12304a'
              : r == 2
                  ? '#242c31'
                  : '#1b2328';
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
          'paint': <String, dynamic>{'line-color': '#1f5a85', 'line-width': 1.2},
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
            'line-color': '#7f8c93',
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
          'paint': <String, dynamic>{'line-color': '#4a5560', 'line-width': 0.8, 'line-dasharray': <num>[3, 2]},
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
