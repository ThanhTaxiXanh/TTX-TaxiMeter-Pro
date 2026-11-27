import 'dart:convert';

/// Chuyen style OpenMapTiles (nguon truc tuyen) thanh style chay offline tren PMTiles cuc bo:
///  - nguon `openmaptiles` tro ve may chu tile 127.0.0.1;
///  - bo nguon/lop raster (anh ve tinh, Natural Earth) va moi lop chu/bieu tuong
///    (symbol) vi khong co font/sprite offline;
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
  style.remove('glyphs');
  style['sources'] = <String, dynamic>{
    'openmaptiles': <String, dynamic>{
      'type': 'vector',
      'tiles': <String>['http://127.0.0.1:$port/tiles/{z}/{x}/{y}.mvt'],
      'minzoom': minZoom,
      'maxzoom': maxZoom,
    },
  };
  final List<dynamic> layers = (style['layers'] as List<dynamic>).where((dynamic l) {
    final Map<String, dynamic> m = l as Map<String, dynamic>;
    final String type = m['type'] as String;
    if (type == 'symbol' || type == 'raster') return false;
    if (type == 'background') return true;
    if (m['source'] != 'openmaptiles') return false;
    final Object? sl = m['source-layer'];
    return sl is String && availableLayers.contains(sl);
  }).toList();
  style['layers'] = layers;
  return jsonEncode(style);
}
