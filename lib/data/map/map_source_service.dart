import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_tile_server.dart';
import 'pmtiles_reader.dart';

/// Quan ly file ban do .pmtiles (chon tu dien thoai) va may chu tile cuc bo.
class MapSourceService {
  static const String _prefKey = 'pmtiles_path';

  PmTilesReader? _reader;
  LocalHttpTileServer? _server;

  PmTilesHeader? get header => _reader?.header;
  String? get styleUrl => _server?.styleUrl;

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
    _server = await LocalHttpTileServer.start(r);
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
