import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/backup/purge_service.dart';
import '../../platform/files.dart';

class CleanupScreen extends ConsumerStatefulWidget {
  const CleanupScreen({super.key});

  @override
  ConsumerState<CleanupScreen> createState() => _CleanupScreenState();
}

class _CleanupScreenState extends ConsumerState<CleanupScreen> {
  int _expired = 0;
  int _keepDays = 90;
  String? _msg;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final int n = await ref.read(purgeServiceProvider).expiredTrashCount(ref.read(clockProvider)());
    if (mounted) setState(() => _expired = n);
  }

  Future<void> _exportAll() async {
    setState(() => _busy = true);
    try {
      final int now = ref.read(clockProvider)();
      final Directory dir = await appSubDir('exports');
      final File f = File('${dir.path}/chuyen-di-${fileStamp(now)}.csv');
      await f.writeAsString(await ref.read(purgeServiceProvider).exportAllTripsCsv(), flush: true);
      setState(() => _msg = 'Đã xuất ${f.path.split('/').last}.');
      await shareFile(f.path);
    } catch (e) {
      setState(() => _msg = 'Không xuất được: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _purgeTrash() async {
    setState(() => _busy = true);
    try {
      final int now = ref.read(clockProvider)();
      final Directory dir = await appSubDir('exports');
      String? saved;
      final int n = await ref.read(purgeServiceProvider).purgeExpiredTrash(
            nowMs: now,
            saveCsv: (String csv, int count) async {
              final File f = File('${dir.path}/thung-rac-${fileStamp(now)}.csv');
              await f.writeAsString(csv, flush: true);
              saved = f.path.split('/').last;
            },
          );
      setState(() => _msg = n == 0 ? 'Không có chuyến nào quá $trashRetentionDays ngày.' : 'Đã xóa $n chuyến (CSV: $saved). Mỗi chuyến đã được ghi vào "chuyến đã xóa".');
      await _load();
    } catch (e) {
      setState(() => _msg = 'Không dọn được, chưa xóa gì: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _purgeGps() async {
    setState(() => _busy = true);
    try {
      final int n = await ref
          .read(purgeServiceProvider)
          .purgeRawGps(nowMs: ref.read(clockProvider)(), keepDays: _keepDays);
      setState(() => _msg = 'Đã xóa $n điểm GPS thô cũ hơn $_keepDays ngày (giữ mã băm để kiểm chứng).');
    } catch (e) {
      setState(() => _msg = 'Không xóa được: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dọn dẹp dữ liệu')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('Thùng rác giữ chuyến $trashRetentionDays ngày. Có $_expired chuyến đã quá hạn. '
              'App tự dọn khi mở; trước khi xóa luôn xuất CSV.'),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('purge_trash'),
            onPressed: _busy || _expired == 0 ? null : _purgeTrash,
            child: const Text('Dọn thùng rác quá hạn (xuất CSV trước)'),
          ),
          const Divider(height: 32),
          const Text('Điểm GPS thô chỉ dùng để kiểm chứng cước; xóa bớt để nhẹ máy.'),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            key: const Key('gps_days'),
            segments: const <ButtonSegment<int>>[
              ButtonSegment<int>(value: 30, label: Text('30 ngày')),
              ButtonSegment<int>(value: 90, label: Text('90 ngày')),
              ButtonSegment<int>(value: 180, label: Text('180 ngày')),
            ],
            selected: <int>{_keepDays},
            onSelectionChanged: (Set<int> v) => setState(() => _keepDays = v.first),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('purge_gps'),
            onPressed: _busy ? null : _purgeGps,
            child: Text('Xóa GPS thô cũ hơn $_keepDays ngày'),
          ),
          const Divider(height: 32),
          OutlinedButton.icon(
            key: const Key('export_csv'),
            onPressed: _busy ? null : _exportAll,
            icon: const Icon(Icons.table_view),
            label: const Text('Xuất toàn bộ chuyến ra CSV'),
          ),
          if (_msg != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_msg!)),
        ],
      ),
    );
  }
}
