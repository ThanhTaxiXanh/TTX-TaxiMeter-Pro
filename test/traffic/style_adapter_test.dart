import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ttx/data/map/style_adapter.dart';

void main() {
  const Set<String> omt = <String>{
    'transportation', 'water', 'building', 'park', 'landuse', 'landcover', 'aeroway', 'waterway', 'boundary',
    'transportation_name', 'place', 'water_name', 'poi'
  };

  void check(String json) {
    final Map<String, dynamic> m = jsonDecode(json) as Map<String, dynamic>;
    expect(m.containsKey('sprite'), isFalse);
    expect(m['glyphs'], 'http://127.0.0.1:1234/fonts/{fontstack}/{range}.pbf');
    expect((m['sources'] as Map<String, dynamic>).keys, <String>['openmaptiles']);
    final String url = ((m['sources'] as Map<String, dynamic>)['openmaptiles'] as Map<String, dynamic>)['tiles'][0] as String;
    expect(url.startsWith('http://127.0.0.1:1234/'), isTrue);
    for (final dynamic l in m['layers'] as List<dynamic>) {
      final Map<String, dynamic> layer = l as Map<String, dynamic>;
      expect(layer['type'], isNot('raster'));
      if (layer['type'] == 'symbol') {
        final Map<String, dynamic> lay = layer['layout'] as Map<String, dynamic>;
        expect(lay.keys.any((String k) => k.startsWith('icon-')), isFalse, reason: '${layer['id']}');
        expect(lay.containsKey('text-field'), isTrue);
        expect(<String>[fontRegular, fontBold, fontItalic].contains((lay['text-font'] as List<dynamic>).single), isTrue);
        expect(layer['source-layer'], isNot('poi'));
      }
      if (layer['type'] != 'background') {
        expect(layer['source'], 'openmaptiles');
        expect(omt.contains(layer['source-layer']), isTrue, reason: '${layer['id']}');
      }
    }
  }

  test('adapter bo symbol/raster, doi nguon sang may chu cuc bo', () {
    final String out = adaptStyleForOffline(
      styleJson: jsonEncode(<String, dynamic>{
        'version': 8,
        'sprite': 'https://x',
        'glyphs': 'https://x',
        'sources': <String, dynamic>{
          'openmaptiles': <String, dynamic>{'type': 'vector', 'url': 'https://x'},
          'ne2': <String, dynamic>{'type': 'raster', 'tiles': <String>['https://x']},
        },
        'layers': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'bg', 'type': 'background'},
          <String, dynamic>{'id': 'ne', 'type': 'raster', 'source': 'ne2'},
          <String, dynamic>{'id': 'w', 'type': 'fill', 'source': 'openmaptiles', 'source-layer': 'water'},
          <String, dynamic>{'id': 'poi', 'type': 'fill', 'source': 'openmaptiles', 'source-layer': 'poi'},
          <String, dynamic>{'id': 'lbl', 'type': 'symbol', 'source': 'openmaptiles', 'source-layer': 'place'},
          <String, dynamic>{
            'id': 'road-name',
            'type': 'symbol',
            'source': 'openmaptiles',
            'source-layer': 'transportation',
            'layout': <String, dynamic>{
              'text-field': '{name}',
              'text-font': <String>['Noto Sans Bold'],
              'icon-image': 'x',
            },
          },
          <String, dynamic>{
            'id': 'shield',
            'type': 'symbol',
            'source': 'openmaptiles',
            'source-layer': 'transportation',
            'layout': <String, dynamic>{'text-field': '{ref}'},
          },
        ],
      }),
      port: 1234,
      minZoom: 0,
      maxZoom: 14,
      availableLayers: omt,
    )!;
    final List<dynamic> layers = (jsonDecode(out) as Map<String, dynamic>)['layers'] as List<dynamic>;
    expect(layers.map((dynamic l) => (l as Map<String, dynamic>)['id']).toList(), <String>['bg', 'w', 'road-name']);
    check(out.replaceAll('poi', 'water'));
  });

  test('PBF glyph rong hop le', () {
    final List<int> b = emptyGlyphPbf('DejaVuSans-Regular', '0-255');
    expect(b.first, 10); // field 1, length-delimited
    expect(b.length, greaterThan(20));
  });

  test('schema khac OpenMapTiles -> null (dung style tu sinh)', () {
    expect(
      adaptStyleForOffline(
          styleJson: '{"version":8,"sources":{},"layers":[]}',
          port: 1,
          minZoom: 0,
          maxZoom: 14,
          availableLayers: <String>{'roads', 'earth'}),
      isNull,
    );
  });

  test('4 style that trong assets/styles deu chuyen duoc, khong con lop online', () {
    for (final String k in <String>['standard-day', 'standard-night', 'modern-day', 'modern-night']) {
      final String src = File('assets/styles/$k.json').readAsStringSync();
      final String out = adaptStyleForOffline(
          styleJson: src, port: 1234, minZoom: 0, maxZoom: 14, availableLayers: omt.union(<String>{'transportation_name', 'place', 'water_name'}))!;
      check(out);
      final List<dynamic> layers = (jsonDecode(out) as Map<String, dynamic>)['layers'] as List<dynamic>;
      expect(layers.any((dynamic l) => (l as Map<String, dynamic>)['type'] == 'fill-extrusion'), isTrue, reason: k);
      expect(layers.any((dynamic l) => (l as Map<String, dynamic>)['type'] == 'symbol'), isTrue, reason: '$k can co nhan chu');
    }
  });
}
