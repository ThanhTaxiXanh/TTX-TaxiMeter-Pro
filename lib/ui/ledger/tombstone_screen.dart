import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/trip/trip_models.dart';
import '../../domain/time/local_time.dart';
import '../common/format.dart';
import 'trash_screen.dart' show reasonLabels;

/// Lich su chuyen da xoa vinh vien (bia mo). Giu vinh vien.
class TombstoneScreen extends ConsumerStatefulWidget {
  const TombstoneScreen({super.key});

  @override
  ConsumerState<TombstoneScreen> createState() => _TombstoneScreenState();
}

class _TombstoneScreenState extends ConsumerState<TombstoneScreen> {
  List<TombstoneItem>? _items;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<TombstoneItem> t = await ref.read(tombstoneRepositoryProvider).list();
    if (mounted) setState(() => _items = t);
  }

  Future<void> _restore(TombstoneItem t) async {
    try {
      await ref.read(tombstoneRepositoryProvider).restore(t.tripId, ref.read(clockProvider)());
      _msg = 'Đã khôi phục chuyến vào danh sách.';
    } catch (e) {
      _msg = 'Không khôi phục được: $e';
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final List<TombstoneItem>? items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Chuyến đã xóa vĩnh viễn')),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(child: Text('Chưa có chuyến nào bị xóa vĩnh viễn.'))
              : ListView(
                  children: <Widget>[
                    if (_msg != null) Padding(padding: const EdgeInsets.all(16), child: Text(_msg!)),
                    for (final TombstoneItem t in items)
                      ListTile(
                        key: Key('tomb_${t.tripId}'),
                        title: Text(formatVnd(t.fareTotalVnd)),
                        subtitle: Text(
                          '${formatLocalDateTime(t.tripStartedAt)} · ${reasonLabels[t.deletedReason] ?? t.deletedReason}\n'
                          'Xóa lúc ${formatLocalDateTime(t.deletedAt)}'
                          '${t.reconciled ? ' · đã đối soát' : ''}'
                          '${t.restoredAt != null ? ' · đã khôi phục' : ''}',
                        ),
                        isThreeLine: true,
                        trailing: t.restoredAt == null
                            ? IconButton(
                                key: Key('tomb_restore_${t.tripId}'),
                                tooltip: 'Khôi phục chuyến',
                                icon: const Icon(Icons.restore_from_trash),
                                onPressed: () => _restore(t),
                              )
                            : null,
                      ),
                  ],
                ),
    );
  }
}
