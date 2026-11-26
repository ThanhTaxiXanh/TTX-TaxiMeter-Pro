import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/time/local_time.dart';
import '../../domain/traffic/traffic_geojson.dart';
import '../../domain/traffic/traffic_overrides.dart';
import 'report_review_screen.dart';
import 'traffic_edit_screen.dart';

String overrideTitle(TrafficOverrideItem o) {
  final String name = o.signKind == null ? o.kind : signLabel(o.signKind!);
  final String sp = o.speedKmh != null ? ' ${o.speedKmh} km/h' : '';
  return o.isRemoval ? 'Ẩn: $name' : '$name$sp';
}

/// Danh sach diem giao thong nhap tay / da duyet tu bao cao.
class TrafficListScreen extends ConsumerStatefulWidget {
  const TrafficListScreen({super.key});

  @override
  ConsumerState<TrafficListScreen> createState() => _TrafficListScreenState();
}

class _TrafficListScreenState extends ConsumerState<TrafficListScreen> {
  List<TrafficOverrideItem>? _items;
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final repo = ref.read(trafficRepositoryProvider);
    final List<TrafficOverrideItem> l = await repo.list();
    final int p = await repo.pendingCount();
    if (mounted) {
      setState(() {
        _items = l;
        _pending = p;
      });
    }
  }

  Future<void> _open({TrafficOverrideItem? item}) async {
    await Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => TrafficEditScreen(item: item)));
    await _reload();
  }

  Future<void> _delete(TrafficOverrideItem o) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Xóa điểm này?'),
        content: Text(overrideTitle(o)),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hủy')),
          FilledButton(key: const Key('del_override_ok'), onPressed: () => Navigator.pop(c, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(trafficRepositoryProvider).delete(o.id);
      ref.invalidate(signIndexProvider);
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<TrafficOverrideItem>? items = _items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Biển báo & camera'),
        actions: <Widget>[
          IconButton(
            key: const Key('review_reports'),
            tooltip: 'Duyệt báo cáo',
            icon: Badge(isLabelVisible: _pending > 0, label: Text('$_pending'), child: const Icon(Icons.rule)),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ReportReviewScreen()));
              await _reload();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add_override'),
        onPressed: () => _open(),
        icon: const Icon(Icons.add),
        label: const Text('Thêm điểm'),
      ),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Chưa có điểm nhập tay. Bấm "Thêm điểm" hoặc duyệt báo cáo từ bản đồ.',
                      textAlign: TextAlign.center)))
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (BuildContext c, int i) {
                    final TrafficOverrideItem o = items[i];
                    return ListTile(
                      key: Key('ov_${o.id}'),
                      leading: Icon(o.isRemoval ? Icons.visibility_off : Icons.place),
                      title: Text(overrideTitle(o)),
                      subtitle: Text('${formatDegreesE7(o.latE7 ?? 0)}, ${formatDegreesE7(o.lngE7 ?? 0)}'
                          ' · ${formatLocalDateTime(o.updatedAt)}'
                          '${o.source == sourceReport ? ' · từ báo cáo' : ''}'),
                      onTap: o.isRemoval ? null : () => _open(item: o),
                      trailing: IconButton(
                        tooltip: 'Xóa',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(o),
                      ),
                    );
                  },
                ),
    );
  }
}
