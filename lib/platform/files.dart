import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/backup/backup_service.dart';
import '../domain/time/local_time.dart';

/// Thu muc lam viec cua app (backups, exports) trong bo nho rieng cua app.
Future<Directory> appSubDir(String name) async {
  final Directory base = await getApplicationDocumentsDirectory();
  final Directory d = Directory('${base.path}/$name');
  await d.create(recursive: true);
  return d;
}

/// Moc thoi gian dung trong ten tep: ddMMyyyy-HHmm theo gio Viet Nam.
String fileStamp(int nowMs) {
  final String digits = formatLocalDateTime(nowMs).replaceAll(RegExp(r'[^0-9]'), '');
  return digits.length >= 12 ? '${digits.substring(0, 8)}-${digits.substring(8, 12)}' : '$nowMs';
}

Future<void> shareFile(String path, {String? text}) async {
  await Share.shareXFiles(<XFile>[XFile(path)], text: text);
}

/// Chon mot tep tu dien thoai va doc noi dung; null neu huy.
Future<Uint8List?> pickFileBytes({List<String>? extensions}) async {
  final FilePickerResult? res = await FilePicker.platform.pickFiles(
    type: extensions == null ? FileType.any : FileType.custom,
    allowedExtensions: extensions,
    withData: true,
  );
  if (res == null || res.files.isEmpty) return null;
  final PlatformFile f = res.files.single;
  if (f.bytes != null) return f.bytes;
  if (f.path != null) return File(f.path!).readAsBytes();
  return null;
}

Future<Map<String, Object?>> readBackupPrefs() async {
  final SharedPreferences sp = await SharedPreferences.getInstance();
  return <String, Object?>{
    for (final String k in backupPrefKeys)
      if (sp.get(k) != null) k: sp.get(k),
  };
}

Future<void> applyBackupPrefs(Map<String, Object?> prefs) async {
  final SharedPreferences sp = await SharedPreferences.getInstance();
  for (final String k in backupPrefKeys) {
    final Object? v = prefs[k];
    if (v is String) {
      await sp.setString(k, v);
    } else if (v is int) {
      await sp.setInt(k, v);
    }
  }
}

Future<void> resetBackupPrefs() async {
  final SharedPreferences sp = await SharedPreferences.getInstance();
  for (final String k in backupPrefKeys) {
    await sp.remove(k);
  }
}
