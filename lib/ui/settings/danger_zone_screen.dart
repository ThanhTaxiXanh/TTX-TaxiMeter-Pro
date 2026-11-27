import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/backup/purge_service.dart';
import '../../platform/files.dart';

/// Moi thao tac xoa phai go dung "XOA"; xoa so doi soat (tombstone) can xac nhan rieng.
class DangerZoneScreen extends ConsumerWidget {
  const DangerZoneScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vùng nguy hiểm')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('Các thao tác dưới đây không hoàn tác được. Gõ đúng $deleteConfirmWord để mở nút xóa.',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 12),
          _DangerCard(
            id: 'trash',
            title: 'Dọn sạch thùng rác ngay',
            body: 'Xóa vĩnh viễn mọi chuyến đang trong thùng rác (kể cả chưa quá 30 ngày). '
                'CSV được xuất trước; mỗi chuyến ghi vào "chuyến đã xóa".',
            action: 'Dọn sạch thùng rác',
            run: (WidgetRef r) async {
              final int now = r.read(clockProvider)();
              final Directory dir = await appSubDir('exports');
              final int n = await r.read(purgeServiceProvider).purgeExpiredTrash(
                    nowMs: now,
                    all: true,
                    saveCsv: (String csv, int c) =>
                        File('${dir.path}/thung-rac-${fileStamp(now)}.csv').writeAsString(csv, flush: true),
                  );
              return 'Đã xóa $n chuyến trong thùng rác.';
            },
          ),
          _DangerCard(
            id: 'gps',
            title: 'Xóa toàn bộ GPS thô',
            body: 'Xóa mọi điểm GPS đã lưu của các chuyến đã kết thúc. Cước và mã băm vẫn giữ.',
            action: 'Xóa GPS thô',
            run: (WidgetRef r) async {
              final int n = await r.read(purgeServiceProvider).purgeRawGps(nowMs: r.read(clockProvider)(), keepDays: 0);
              return 'Đã xóa $n điểm GPS.';
            },
          ),
          _DangerCard(
            id: 'tomb',
            title: 'Xóa toàn bộ "chuyến đã xóa" (sổ đối soát)',
            body: 'Tombstone là bằng chứng đối soát doanh thu. Chỉ xóa khi chắc chắn không cần đối soát nữa. '
                'Xác nhận này riêng, không đi kèm thao tác khác.',
            action: 'Xóa sổ đối soát',
            run: (WidgetRef r) async {
              final int n = await r.read(purgeServiceProvider).deleteAllTombstones();
              return 'Đã xóa $n bản ghi đối soát.';
            },
          ),
          _DangerCard(
            id: 'prefs',
            title: 'Đặt lại cài đặt giao diện và bản đồ',
            body: 'Đưa giao diện, kiểu bản đồ, cảnh báo biển về mặc định. Không đụng tới chuyến hay biểu giá.',
            action: 'Đặt lại cài đặt',
            run: (WidgetRef r) async {
              await resetBackupPrefs();
              await r.read(themeModeProvider.notifier).set(ThemeMode.dark);
              return 'Đã đặt lại cài đặt.';
            },
          ),
        ],
      ),
    );
  }
}

class _DangerCard extends ConsumerStatefulWidget {
  const _DangerCard({required this.id, required this.title, required this.body, required this.action, required this.run});
  final String id;
  final String title;
  final String body;
  final String action;
  final Future<String> Function(WidgetRef ref) run;

  @override
  ConsumerState<_DangerCard> createState() => _DangerCardState();
}

class _DangerCardState extends ConsumerState<_DangerCard> {
  final TextEditingController _c = TextEditingController();
  String? _msg;
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      final String m = await widget.run(ref);
      if (mounted) {
        setState(() {
          _msg = m;
          _c.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _msg = 'Không thực hiện được, chưa mất dữ liệu: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool ok = isDeleteConfirmed(_c.text);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(widget.body),
            TextField(
              key: Key('confirm_${widget.id}'),
              controller: _c,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: 'Gõ $deleteConfirmWord để xác nhận'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: Key('run_${widget.id}'),
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: ok && !_busy ? _go : null,
              child: Text(widget.action),
            ),
            if (_msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!)),
          ],
        ),
      ),
    );
  }
}
