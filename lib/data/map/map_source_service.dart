import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_tile_server.dart';
import 'pmtiles_reader.dart';
import 'street_name.dart';

/// Quan ly file ban do .pmtiles (chon tu dien thoai) va may chu tile cuc bo.
class MapSourceService {
  static const String _prefKey = 'pmtiles_path';

  PmTilesReader? _reader;
  LocalHttpTileServer? _server;

  PmTilesHeader? get header => _reader?.header;
  String? get styleUrl => _server?.styleUrl;
  /// Ten duong gan vi tri nhat doc truc tiep tu tile (offline); null neu khong tim thay.
  Future<String?> streetNameAt(int latE7, int lngE7) async {
    final PmTilesReader? r = _reader;
    if (r == null) return null;
    try {
      return await streetNameFromReader(r, latE7, lngE7);
    } catch (_) {
      return null;
    }
  }

  String? styleUrlFor({required bool light, String family = 'standard'}) =>
      _server?.styleUrlFor(light: light, family: family);

  /// Kieu ban do: standard | modern.
  Future<String> loadFamily() async {
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final String? t = sp.getString('map_family');
      if (t == 'standard' || t == 'modern') return t!;
    } catch (_) {}
    return 'standard';
  }

  Future<void> saveFamily(String f) async {
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      await sp.setString('map_family', f);
    } catch (_) {}
  }

  /// Khoang cach canh bao bien (m): 200 | 300 | 500.
  Future<int> loadWarnM() async {
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final int? v = sp.getInt('warn_m');
      if (v == 200 || v == 300 || v == 500) return v!;
    } catch (_) {}
    return 300;
  }

  Future<void> saveWarnM(int m) async {
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      await sp.setInt('warn_m', m);
    } catch (_) {}
  }

  static const List<String> _styleKeys = <String>[
    'standard-day',
    'standard-night',
    'modern-day',
    'modern-night',
  ];

  Future<Map<String, String>> _loadBaseStyles() async {
    final Map<String, String> m = <String, String>{};
    for (final String k in _styleKeys) {
      try {
        m[k] = await rootBundle.loadString('assets/styles/$k.json');
      } catch (_) {}
    }
    return m;
  }

  /// Che do giao dien ban do: auto | light | dark.
  Future<String> loadTheme() async {
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final String? t = sp.getString('map_theme');
      if (t == 'light' || t == 'dark' || t == 'auto') return t!;
    } catch (_) {}
    return 'auto';
  }

  Future<void> saveTheme(String t) async {
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      await sp.setString('map_theme', t);
    } catch (_) {}
  }

  Future<String?> savedPath() async {
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final String? path = sp.getString(_prefKey);
      if (path != null && File(path).existsSync()) return path;
    } catch (_) {}
    return null;
  }

  /// Mo file ban do + bat may chu tile. Tra ve style URL, hoac nem FormatException.
  Future<String> startFromPath(String path) async {
    await stop();
    final PmTilesReader r = await PmTilesReader.open(path);
    _reader = r;
    _server = await LocalHttpTileServer.start(r,
        baseStyles: await _loadBaseStyles(),
        glyphLoader: (String stack, String range) async {
          final ByteData d = await rootBundle.load('assets/glyphs/$stack/$range.pbf');
          return d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
        });
    return _server!.styleUrl;
  }

  /// Nguoi dung chon file; kiem tra hop le roi chuyen vao thu muc rieng cua app.
  /// Tra ve null neu huy.
  Future<String?> pickAndImport() async {
    final FilePickerResult? res = await FilePicker.platform.pickFiles(type: FileType.any);
    final String? picked = res?.files.single.path;
    if (picked == null) return null;
    // Kiem tra truoc khi ghi de file cu.
    final PmTilesReader probe = await PmTilesReader.open(picked);
    await probe.close();
    final Directory dir = await getApplicationSupportDirectory();
    final String dest = p.join(dir.path, 'map.pmtiles');
    await stop();
    final File src = File(picked);
    if (p.equals(picked, dest)) return dest;
    final File out = File(dest);
    if (out.existsSync()) out.deleteSync();
    try {
      await src.rename(dest);
    } catch (_) {
      await src.copy(dest);
      try {
        await src.delete();
      } catch (_) {}
    }
    final SharedPreferences sp = await SharedPreferences.getInstance();
    await sp.setString(_prefKey, dest);
    return dest;
  }

  Future<void> stop() async {
    await _server?.stop();
    await _reader?.close();
    _server = null;
    _reader = null;
  }
}
