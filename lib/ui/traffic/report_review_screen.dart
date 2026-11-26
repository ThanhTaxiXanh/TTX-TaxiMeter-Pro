import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/traffic/traffic_report_repository.dart';
import '../../domain/time/local_time.dart';
import '../../domain/traffic/traffic_geojson.dart';
import '../../domain/traffic/traffic_models.dart';
import '../../domain/traffic/traffic_overrides.dart';

/// Duyet bao cao bien/camera tu ban do: dong y -> thanh diem sua tay; tu choi -> bo qua.
class ReportReviewScreen extends ConsumerStatefulWidget {
  const ReportReviewScreen({super.key});

  @override
  ConsumerState<ReportReviewScreen> createState() => _ReportReviewScreenState();
}

class _ReportReviewScreenState extends ConsumerState<ReportReviewScreen> {
  List<TrafficReportItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<TrafficReportItem> l = await ref.read(trafficReportRepositoryProvider).list();
    if (mounted) setState(() => _items = l);
  }

  String _title(TrafficReportItem r) {
    SignKind? k;
    for (final SignKind v in SignKind.values) {
      if (v.name == r.kind) k = v;
    }
    final String name = k == null ? r.kind : signLabel(k);
    final bool remove = r.proposed['action'] == 'REMOVE';
    final Object? sp = r.proposed['speedKmh'];
    return '${remove ? 'Không còn' : 'Thiếu'}: $name${sp != null ? ' $sp km/h' : ''}';
  }

  String _statusLabel(String s) => s == 'PENDING' ? 'Chờ duyệt' : (s == 'APPROVED' ? 'Đã duyệt' : 'Đã từ chối');

  Future<void> _approve(TrafficReportItem r) async {
    try {
      await ref.read(trafficRepositoryProvider).approveReport(r, nowMs: ref.read(clockProvider)());
      ref.invalidate(signIndexProvider);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
    await _reload();
  }

  Future<void> _reject(TrafficReportItem r) async {
    await ref.read(trafficRepositoryProvider).rejectReport(r.id, nowMs: ref.read(clockProvider)());
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final List<TrafficReportItem>? items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Duyệt báo cáo')),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(child: Text('Chưa có báo cáo nào.'))
              : ListView(
                  children: <Widget>[
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                    for (final TrafficReportItem r in items)
                      Card(
                        key: Key('report_${r.id}'),
                        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(_title(r), style: Theme.of(context).textTheme.titleMedium),
                              Text('${r.latE7 == null ? '' : '${formatDegreesE7(r.latE7!)}, ${formatDegreesE7(r.lngE7 ?? 0)} · '}'
                                  '${formatLocalDateTime(r.reportedAt)} · ${_statusLabel(r.status)}'),
                              if (r.proposed['note'] != null) Text('Ghi chú: ${r.proposed['note']}'),
                              if (r.status == 'PENDING')
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: <Widget>[
                                    TextButton(
                                      key: Key('reject_${r.id}'),
                                      onPressed: () => _reject(r),
                                      child: const Text('Từ chối'),
                                    ),
                                    FilledButton(
                                      key: Key('approve_${r.id}'),
                                      onPressed: () => _approve(r),
                                      child: const Text('Đồng ý'),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
    );
  }
}
