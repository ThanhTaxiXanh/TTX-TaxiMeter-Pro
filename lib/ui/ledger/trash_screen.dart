import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/trip/tombstone_repository.dart';
import '../../data/trip/trip_models.dart';
import '../../domain/time/local_time.dart';
import '../common/format.dart';

const Map<String, String> reasonLabels = <String, String>{
  'DUPLICATE': 'Trùng chuyến',
  'TEST': 'Chạy thử',
  'WRONG_ENTRY': 'Nhập sai',
  'OTHER': 'Lý do khác',
};

class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  List<TripListItem>? _items;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<TripListItem> t = await ref.read(tripRepositoryProvider).listTrash();
    if (mounted) setState(() => _items = t);
  }

  Future<void> _restore(TripListItem t) async {
    await ref.read(tripRepositoryProvider).restoreFromTrash(t.tripId);
    await _reload();
  }

  Future<void> _deleteForever(TripListItem t) async {
    String reason = 'WRONG_ENTRY';
    final TextEditingController note = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => StatefulBuilder(
        builder: (BuildContext c, StateSetter set) => AlertDialog(
          title: const Text('Xóa vĩnh viễn?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('${formatVnd(t.effectiveTotalVnd)} · ${formatLocalDateTime(t.startedAt)}'),
              const SizedBox(height: 8),
              const Text('Chuyến sẽ được ghi vào "chuyến đã xóa" để đối soát. Không thể hoàn tác trong thùng rác.'),
              DropdownButton<String>(
                key: const Key('reason'),
                value: reason,
                isExpanded: true,
                items: tombstoneReasons
                    .map((String r) => DropdownMenuItem<String>(value: r, child: Text(reasonLabels[r]!)))
                    .toList(),
                onChanged: (String? v) => set(() => reason = v ?? reason),
              ),
              TextField(
                key: const Key('del_note'),
                controller: note,
                decoration: const InputDecoration(labelText: 'Ghi chú (không bắt buộc)'),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hủy')),
            FilledButton(
              key: const Key('del_ok'),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Xóa vĩnh viễn'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await ref.read(tombstoneRepositoryProvider).deletePermanently(
            tripId: t.tripId,
            reason: reason,
            note: note.text.trim().isEmpty ? null : note.text.trim(),
            nowMs: ref.read(clockProvider)(),
          );
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<TripListItem>? items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Thùng rác')),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(child: Text('Thùng rác trống.'))
              : ListView(
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Chuyến trong thùng rác được giữ 30 ngày.'),
                    ),
                    for (final TripListItem t in items)
                      ListTile(
                        key: Key('trash_${t.tripId}'),
                        title: Text(formatVnd(t.effectiveTotalVnd)),
                        subtitle: Text(
                            '${formatLocalDateTime(t.startedAt)} · ${formatKm(t.distanceM)}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                          IconButton(
                            key: Key('restore_${t.tripId}'),
                            tooltip: 'Khôi phục',
                            icon: const Icon(Icons.restore),
                            onPressed: () => _restore(t),
                          ),
                          IconButton(
                            key: Key('forever_${t.tripId}'),
                            tooltip: 'Xóa vĩnh viễn',
                            icon: const Icon(Icons.delete_forever),
                            onPressed: () => _deleteForever(t),
                          ),
                        ]),
                      ),
                  ],
                ),
    );
  }
}
