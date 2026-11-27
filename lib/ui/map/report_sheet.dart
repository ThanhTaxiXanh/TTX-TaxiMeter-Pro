import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/traffic/sign_catalog.dart';
import '../../domain/traffic/traffic_models.dart';
import 'sign_glyph.dart';
import 'speed_limit_sign.dart';

/// Nhom bien duoc bao cao: chi Bien cam (P) va Hieu lenh (R).
const Map<String, String> reportGroups = <String, String>{'P': 'Biển cấm', 'R': 'Hiệu lệnh'};

/// Toc do hay gap, cham la gui ngay (P.127).
const List<int> quickSpeeds = <int>[40, 50, 60, 70, 80, 90, 100, 120];

/// Bao cao nhanh bien tai vi tri hien tai: chon bien (Bien cam / Hieu lenh) la luu ngay,
/// bao cao luu tren may kem vi tri, cho duyet.
Future<bool> showReportSheet(
  BuildContext context,
  WidgetRef ref, {
  required int latE7,
  required int lngE7,
}) async {
  final bool? ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext c) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _ReportBody(ref: ref, latE7: latE7, lngE7: lngE7),
    ),
  );
  return ok == true;
}

class _ReportBody extends ConsumerStatefulWidget {
  const _ReportBody({required this.ref, required this.latE7, required this.lngE7});
  final WidgetRef ref;
  final int latE7;
  final int lngE7;

  @override
  ConsumerState<_ReportBody> createState() => _ReportBodyState();
}

class _ReportBodyState extends ConsumerState<_ReportBody> {
  String _group = 'P';
  String _q = '';
  bool _missing = true; // true: thieu bien; false: bien sai/khong con

  Future<void> _send({required String kind, required Map<String, dynamic> extra}) async {
    await ref.read(trafficReportRepositoryProvider).create(
          kind: kind,
          proposed: <String, dynamic>{'action': _missing ? 'ADD' : 'REMOVE', ...extra},
          latE7: widget.latE7,
          lngE7: widget.lngE7,
          nowMs: ref.read(clockProvider)(),
        );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final List<CatalogSign>? all = ref.watch(signCatalogProvider).valueOrNull;
    final List<CatalogSign> shown = all == null ? const <CatalogSign>[] : filterCatalog(all, _group, _q);
    final ThemeData t = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Ở đây có biển gì?', style: t.textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Chỉ báo tấm biển bạn đang nhìn thấy tại chỗ này. Báo cáo lưu trên máy, kèm vị trí hiện tại.',
                style: t.textTheme.bodyMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: true, label: Text('Thiếu biển')),
                ButtonSegment<bool>(value: false, label: Text('Biển sai/không còn')),
              ],
              selected: <bool>{_missing},
              onSelectionChanged: (Set<bool> v) => setState(() => _missing = v.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              key: const Key('sign_search'),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Tìm theo tên hoặc mã (P.103a)'),
              onChanged: (String v) => setState(() => _q = v),
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: <Widget>[
                for (final MapEntry<String, String> e in reportGroups.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: ChoiceChip(
                      key: Key('group_${e.key}'),
                      label: Text(e.value),
                      selected: _group == e.key,
                      onSelected: (_) => setState(() => _group = e.key),
                    ),
                  ),
              ],
            ),
          ),
          if (_group == 'P' && _q.isEmpty)
            SizedBox(
              height: 64,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: <Widget>[
                  for (final int v in quickSpeeds)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: InkWell(
                        key: Key('quick_$v'),
                        borderRadius: BorderRadius.circular(32),
                        onTap: () => _send(kind: SignKind.maxSpeed.name, extra: <String, dynamic>{'speedKmh': v, 'name': 'Tốc độ tối đa $v km/h'}),
                        child: SpeedLimitSign(kmh: v, size: 56),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: all == null
                ? const Center(child: CircularProgressIndicator())
                : shown.isEmpty
                    ? const Center(child: Text('Không có biển phù hợp.'))
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          mainAxisExtent: 92,
                        ),
                        itemCount: shown.length,
                        itemBuilder: (BuildContext c, int i) {
                          final CatalogSign s = shown[i];
                          return Material(
                            color: t.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              key: Key('sign_${s.code}'),
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _send(
                                kind: s.code == 'P.127' ? SignKind.maxSpeed.name : s.code,
                                extra: <String, dynamic>{'name': s.name, 'code': s.code},
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Row(
                                  children: <Widget>[
                                    SignGlyph(code: s.code, group: s.group, size: 52),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(s.name.isEmpty ? 'Chưa có tên' : s.name, maxLines: 3, overflow: TextOverflow.ellipsis),
                                          Text(s.code, style: t.textTheme.bodySmall),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: OutlinedButton(key: const Key('report_cancel'), onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
            ),
          ),
        ],
      ),
    );
  }
}
