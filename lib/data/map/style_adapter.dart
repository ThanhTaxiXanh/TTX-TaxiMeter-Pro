import 'dart:convert';

/// Ten font (thu muc assets/glyphs) dung cho nhan chu offline; DejaVu Sans ho tro tieng Viet.
const String fontRegular = 'DejaVuSans-Regular';
const String fontBold = 'DejaVuSans-Bold';
const String fontItalic = 'DejaVuSans-Oblique';

/// Chuyen style OpenMapTiles (nguon truc tuyen) thanh style chay offline tren PMTiles cuc bo:
///  - nguon `openmaptiles` tro ve may chu tile 127.0.0.1, glyphs tro ve /fonts cua may chu do;
///  - bo nguon/lop raster (anh ve tinh, Natural Earth), bieu tuong POI/shield/mui ten (khong co sprite);
///  - giu lop nhan chu (ten duong, dia danh) nhung bo icon-*, chu uu tien name:vi roi name;
///  - bo lop tham chieu source-layer khong co trong file ban do.
/// Khong goi mang. Tra ve null neu file ban do khong theo schema OpenMapTiles.
String? adaptStyleForOffline({
  required String styleJson,
  required int port,
  required int minZoom,
  required int maxZoom,
  required Set<String> availableLayers,
}) {
  if (!availableLayers.contains('transportation') || !availableLayers.contains('water')) return null;
  final Map<String, dynamic> style = jsonDecode(styleJson) as Map<String, dynamic>;
  style.remove('sprite');
  style['glyphs'] = 'http://127.0.0.1:$port/fonts/{fontstack}/{range}.pbf';
  style['sources'] = <String, dynamic>{
    'openmaptiles': <String, dynamic>{
      'type': 'vector',
      'tiles': <String>['http://127.0.0.1:$port/tiles/{z}/{x}/{y}.mvt'],
      'minzoom': minZoom,
      'maxzoom': maxZoom,
    },
  };
  final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
  for (final dynamic l in style['layers'] as List<dynamic>) {
    final Map<String, dynamic> m = Map<String, dynamic>.from(l as Map<String, dynamic>);
    final String type = m['type'] as String;
    if (type == 'raster') continue;
    if (type == 'background') {
      out.add(m);
      continue;
    }
    if (m['source'] != 'openmaptiles') continue;
    final Object? sl = m['source-layer'];
    if (sl is! String || !availableLayers.contains(sl)) continue;
    if (type == 'symbol') {
      final Map<String, dynamic> layout = Map<String, dynamic>.from((m['layout'] as Map<String, dynamic>?) ?? <String, dynamic>{});
      final String id = (m['id'] as String).toLowerCase();
      if (sl == 'poi' || id.contains('shield') || id.contains('arrow') || !layout.containsKey('text-field')) continue;
      layout.removeWhere((String k, dynamic _) => k.startsWith('icon-'));
      layout['text-field'] = <Object>[
        'coalesce',
        <Object>['get', 'name:vi'],
        <Object>['get', 'name'],
      ];
      layout['text-font'] = <String>[_fontFor(layout['text-font'])];
      m['layout'] = layout;
    }
    out.add(m);
  }
  style['layers'] = out;
  return jsonEncode(style);
}

String _fontFor(Object? f) {
  final String s = f is List && f.isNotEmpty ? f.first.toString().toLowerCase() : '';
  if (s.contains('bold')) return fontBold;
  if (s.contains('italic') || s.contains('oblique')) return fontItalic;
  return fontRegular;
}

/// PBF glyph rong hop le (khong co ky tu) cho dai khong co du lieu — tranh loi 404.
List<int> emptyGlyphPbf(String stack, String range) {
  List<int> varint(int n) {
    final List<int> o = <int>[];
    while (n > 0x7F) {
      o.add((n & 0x7F) | 0x80);
      n >>= 7;
    }
    o.add(n);
    return o;
  }

  List<int> ld(int field, List<int> data) => <int>[(field << 3) | 2, ...varint(data.length), ...data];
  final List<int> body = <int>[...ld(1, utf8.encode(stack)), ...ld(2, utf8.encode(range))];
  return ld(1, body);
}
