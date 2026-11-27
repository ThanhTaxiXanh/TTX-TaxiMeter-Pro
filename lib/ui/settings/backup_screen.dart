import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/backup/backup_service.dart';
import '../../platform/files.dart';
import 'about_screen.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  String? _msg;
  bool _error = false;
  bool _busy = false;

  void _say(String m, {bool error = false}) => setState(() {
        _msg = m;
        _error = error;
      });

  Future<void> _backup() async {
    setState(() => _busy = true);
    try {
      final int now = ref.read(clockProvider)();
      final Directory dir = await appSubDir('backups');
      final Uint8List zip = await ref.read(backupServiceProvider).createBackupZip(
            workDir: dir,
            prefs: await readBackupPrefs(),
            nowMs: now,
            appVersion: appVersion,
          );
      final File f = File('${dir.path}/ttx-backup-${fileStamp(now)}.zip');
      await f.writeAsBytes(zip, flush: true);
      _say('Đã tạo ${f.path.split('/').last} (${(zip.length / 1024).round()} KB). Hãy lưu bản này ra nơi an toàn.');
      await shareFile(f.path, text: 'Bản sao lưu TTX TaxiMeter Pro');
    } catch (e) {
      _say('Không tạo được bản sao lưu: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final Uint8List? zip = await pickFileBytes(extensions: <String>['zip']);
    if (zip == null || !mounted) return;
    final BackupInfo info;
    try {
      info = BackupService.verifyZip(zip).info;
    } catch (e) {
      _say(e.toString(), error: true);
      return;
    }
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Khôi phục dữ liệu?'),
        content: Text('Tệp hợp lệ (checksum khớp, app ${info.appVersion}).\n\n'
            'Toàn bộ dữ liệu hiện tại sẽ được thay bằng dữ liệu trong bản sao lưu. '
            'App tự sao lưu bản hiện tại trước khi khôi phục; lỗi giữa chừng sẽ giữ nguyên dữ liệu cũ.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hủy')),
          FilledButton(key: const Key('restore_ok'), onPressed: () => Navigator.pop(c, true), child: const Text('Khôi phục')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final r = await ref.read(backupServiceProvider).restore(
            zip: zip,
            workDir: await appSubDir('backups'),
            currentPrefs: await readBackupPrefs(),
            nowMs: ref.read(clockProvider)(),
            appVersion: appVersion,
          );
      await applyBackupPrefs(r.prefs);
      ref.invalidate(signIndexProvider);
      _say('Đã khôi phục. Bản sao lưu cũ của máy này: ${r.autoBackupPath.split('/').last}. Hãy tắt và mở lại app.');
    } catch (e) {
      _say('Khôi phục thất bại, dữ liệu cũ được giữ nguyên: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sao lưu & khôi phục')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text('Bản sao lưu là tệp ZIP gồm cơ sở dữ liệu, cài đặt và checksum SHA-256 từng tệp. '
              'Số tài khoản nhận tiền nằm trong cơ sở dữ liệu nên khôi phục xong không phải nhập lại.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('backup_now'),
            onPressed: _busy ? null : _backup,
            icon: const Icon(Icons.backup),
            label: const Text('Tạo bản sao lưu và chia sẻ'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('restore_pick'),
            onPressed: _busy ? null : _restore,
            icon: const Icon(Icons.restore),
            label: const Text('Khôi phục từ tệp ZIP…'),
          ),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_msg!, style: TextStyle(color: _error ? Theme.of(context).colorScheme.error : null)),
            ),
        ],
      ),
    );
  }
}
