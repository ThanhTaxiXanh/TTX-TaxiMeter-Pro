import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/trip/trip_models.dart';
import '../../domain/time/local_time.dart';
import '../common/format.dart';
import 'trash_screen.dart' show reasonLabels;

/// Doi soat cac chuyen da xoa vinh vien: danh dau da doi chieu voi so/tien mat.
class ReconciliationScreen extends ConsumerStatefulWidget {
  const ReconciliationScreen({super.key});

  @override
  ConsumerState<ReconciliationScreen> createState() => _ReconciliationScreenState();
}

class _ReconciliationScreenState extends ConsumerState<ReconciliationScreen> {
  List<TombstoneItem>? _items;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<TombstoneItem> t =
        await ref.read(tombstoneRepositoryProvider).list(reconciled: false);
    if (mounted) setState(() => _items = t);
  }

  Future<void> _reconcile(TombstoneItem t) async {
    final TextEditingController note = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Đánh dấu đã đối soát'),
        content: TextField(
          key: const Key('rec_note'),
          controller: note,
          decoration: const InputDecoration(labelText: 'Ghi chú đối soát'),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hủy')),
          FilledButton(key: const Key('rec_ok'), onPressed: () => Navigator.pop(c, true), child: const Text('Xác nhận')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(tombstoneRepositoryProvider).setReconciled(
            tripId: t.tripId,
            reconciled: true,
            note: note.text.trim().isEmpty ? null : note.text.trim(),
            nowMs: ref.read(clockProvider)(),
          );
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<TombstoneItem>? items = _items;
    int sum = 0;
    for (final TombstoneItem t in items ?? const <TombstoneItem>[]) {
      sum += t.fareTotalVnd;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Đối soát')),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(child: Text('Không còn chuyến nào cần đối soát.'))
              : ListView(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('${items.length} chuyến chưa đối soát, tổng ${formatVnd(sum)}',
                          key: const Key('rec_summary')),
                    ),
                    for (final TombstoneItem t in items)
                      ListTile(
                        key: Key('rec_${t.tripId}'),
                        title: Text(formatVnd(t.fareTotalVnd)),
                        subtitle: Text(
                            '${formatLocalDateTime(t.tripStartedAt)} · ${reasonLabels[t.deletedReason] ?? t.deletedReason}'),
                        trailing: TextButton(
                          key: Key('rec_btn_${t.tripId}'),
                          onPressed: () => _reconcile(t),
                          child: const Text('Đã đối soát'),
                        ),
                      ),
                  ],
                ),
    );
  }
}
