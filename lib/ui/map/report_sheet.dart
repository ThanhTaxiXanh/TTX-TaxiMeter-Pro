import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/traffic/sign_catalog.dart';
import '../../domain/traffic/traffic_geojson.dart';
import '../../domain/traffic/traffic_models.dart';
import 'sign_picker.dart';

/// Bao cao nhanh mot bien/camera tai vi tri hien tai (luu cuc bo, cho duyet).
Future<bool> showReportSheet(
  BuildContext context,
  WidgetRef ref, {
  required int latE7,
  required int lngE7,
}) async {
  SignKind? kind = SignKind.maxSpeed;
  CatalogSign? picked;
  bool missing = true; // true = bien thieu, false = bien sai/khong con
  final TextEditingController speed = TextEditingController();
  final TextEditingController note = TextEditingController();
  String? err;
  final bool? ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext c) => StatefulBuilder(
      builder: (BuildContext c, StateSetter set) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(c).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Ở đây có biển gì?', style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text('Báo cáo được lưu trên máy này, kèm vị trí hiện tại.'),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const <ButtonSegment<bool>>[
                  ButtonSegment<bool>(value: true, label: Text('Thiếu biển')),
                  ButtonSegment<bool>(value: false, label: Text('Biển sai/không còn')),
                ],
                selected: <bool>{missing},
                onSelectionChanged: (Set<bool> v) => set(() => missing = v.first),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final SignKind k in SignKind.values.where((SignKind v) => v != SignKind.other))
                    ChoiceChip(
                      key: Key('rk_${k.name}'),
                      label: Text(signLabel(k)),
                      selected: kind == k && picked == null,
                      onSelected: (_) => set(() {
                        kind = k;
                        picked = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('pick_catalog'),
                icon: const Icon(Icons.search),
                label: Text(picked == null ? 'Chọn từ danh mục biển báo…' : '${picked!.code} ${picked!.name}'),
                onPressed: () async {
                  final CatalogSign? r = await showSignPicker(c);
                  if (r == null) return;
                  set(() {
                    picked = r;
                    // P.127 = bien toc do toi da: dung luong bao cao toc do.
                    kind = r.code == 'P.127' ? SignKind.maxSpeed : null;
                  });
                },
              ),
              if (kind == SignKind.maxSpeed || picked?.code == 'P.127')
                TextField(
                  key: const Key('report_speed'),
                  controller: speed,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Tốc độ tối đa (km/h)'),
                ),
              TextField(
                key: const Key('report_note'),
                controller: note,
                decoration: const InputDecoration(labelText: 'Ghi chú (không bắt buộc)'),
              ),
              if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: Colors.redAccent))),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('report_send'),
                onPressed: () {
                  if (kind == SignKind.maxSpeed && missing && int.tryParse(speed.text.trim()) == null) {
                    set(() => err = 'Nhập tốc độ tối đa (số).');
                    return;
                  }
                  Navigator.pop(c, true);
                },
                child: const Text('Lưu báo cáo'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (ok != true || (kind == null && picked == null)) return false;
  await ref.read(trafficReportRepositoryProvider).create(
        kind: (picked != null && picked!.code != 'P.127') ? picked!.code : (kind ?? SignKind.maxSpeed).name,
        proposed: <String, dynamic>{
          if (picked != null) 'name': picked!.name,
          'action': missing ? 'ADD' : 'REMOVE',
          if (kind == SignKind.maxSpeed && int.tryParse(speed.text.trim()) != null)
            'speedKmh': int.parse(speed.text.trim()),
          if (note.text.trim().isNotEmpty) 'note': note.text.trim(),
        },
        latE7: latE7,
        lngE7: lngE7,
        nowMs: ref.read(clockProvider)(),
      );
  return true;
}
