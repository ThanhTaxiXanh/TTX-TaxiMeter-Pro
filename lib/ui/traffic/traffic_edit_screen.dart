import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/traffic/traffic_geojson.dart';
import '../../domain/traffic/traffic_models.dart';
import '../../domain/traffic/traffic_overrides.dart';
import '../../platform/current_position.dart';

/// Them / sua mot diem giao thong nhap tay (gioi han toc do, bien, camera).
class TrafficEditScreen extends ConsumerStatefulWidget {
  const TrafficEditScreen({super.key, this.item, this.initialLatE7, this.initialLngE7});
  final TrafficOverrideItem? item;
  final int? initialLatE7;
  final int? initialLngE7;

  @override
  ConsumerState<TrafficEditScreen> createState() => _TrafficEditScreenState();
}

class _TrafficEditScreenState extends ConsumerState<TrafficEditScreen> {
  late String _kind = widget.item?.kind ?? 'SPEED_LIMIT';
  late SignKind _sign = _initSign();
  late String _camera = widget.item?.cameraType ?? 'speedCamera';
  late final TextEditingController _lat = TextEditingController(
      text: _fmt(widget.item?.latE7 ?? widget.initialLatE7));
  late final TextEditingController _lng = TextEditingController(
      text: _fmt(widget.item?.lngE7 ?? widget.initialLngE7));
  late final TextEditingController _speed = TextEditingController(text: widget.item?.speedKmh?.toString() ?? '');
  late final TextEditingController _note = TextEditingController(text: widget.item?.note ?? '');
  String? _error;
  bool _busy = false;

  static String _fmt(int? e7) => e7 == null ? '' : formatDegreesE7(e7);

  SignKind _initSign() {
    final String? c = widget.item?.signCode;
    for (final SignKind k in SignKind.values) {
      if (k.name == c) return k;
    }
    return SignKind.tollBooth;
  }

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    _speed.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _useHere() async {
    setState(() => _busy = true);
    final ({int latE7, int lngE7})? p = await currentPositionE7();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (p == null) {
        _error = 'Không lấy được vị trí GPS.';
      } else {
        _lat.text = formatDegreesE7(p.latE7);
        _lng.text = formatDegreesE7(p.lngE7);
        _error = null;
      }
    });
  }

  Future<void> _save() async {
    final int? lat = parseDegreesE7(_lat.text);
    final int? lng = parseDegreesE7(_lng.text);
    final int? speed = int.tryParse(_speed.text.trim());
    final bool needSpeed = _kind == 'SPEED_LIMIT' || (_kind == 'SIGN' && _sign == SignKind.maxSpeed);
    final String? signCode = _kind == 'SIGN' ? _sign.name : null;
    final String? cam = _kind == 'CAMERA' ? _camera : null;
    final int? sp = needSpeed ? speed : null;
    final String note = _note.text.trim();
    final int now = ref.read(clockProvider)();
    try {
      if (widget.item == null) {
        await ref.read(trafficRepositoryProvider).create(
            kind: _kind, latE7: lat, lngE7: lng, speedKmh: sp, signCode: signCode, cameraType: cam,
            note: note.isEmpty ? null : note, nowMs: now);
      } else {
        await ref.read(trafficRepositoryProvider).update(
            id: widget.item!.id, kind: _kind, latE7: lat, lngE7: lng, speedKmh: sp, signCode: signCode,
            cameraType: cam, note: note.isEmpty ? null : note, nowMs: now);
      }
      ref.invalidate(signIndexProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<SignKind> signKinds = SignKind.values
        .where((SignKind k) => k != SignKind.speedCamera && k != SignKind.streetCamera && k != SignKind.other)
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.item == null ? 'Thêm điểm giao thông' : 'Sửa điểm giao thông')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(value: 'SPEED_LIMIT', label: Text('Tốc độ')),
              ButtonSegment<String>(value: 'SIGN', label: Text('Biển')),
              ButtonSegment<String>(value: 'CAMERA', label: Text('Camera')),
            ],
            selected: <String>{_kind},
            onSelectionChanged: (Set<String> v) => setState(() => _kind = v.first),
          ),
          const SizedBox(height: 12),
          if (_kind == 'SIGN')
            DropdownButtonFormField<SignKind>(
              key: const Key('sign_kind'),
              value: _sign,
              decoration: const InputDecoration(labelText: 'Loại biển'),
              items: signKinds
                  .map((SignKind k) => DropdownMenuItem<SignKind>(value: k, child: Text(signLabel(k))))
                  .toList(),
              onChanged: (SignKind? v) => setState(() => _sign = v ?? _sign),
            ),
          if (_kind == 'CAMERA')
            SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(value: 'speedCamera', label: Text('Bắn tốc độ')),
                ButtonSegment<String>(value: 'streetCamera', label: Text('Giám sát')),
              ],
              selected: <String>{_camera},
              onSelectionChanged: (Set<String> v) => setState(() => _camera = v.first),
            ),
          if (_kind == 'SPEED_LIMIT' || (_kind == 'SIGN' && _sign == SignKind.maxSpeed))
            TextField(
              key: const Key('edit_speed'),
              controller: _speed,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Tốc độ tối đa (km/h)'),
            ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('edit_lat'),
            controller: _lat,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(labelText: 'Vĩ độ (ví dụ 10.7769)'),
          ),
          TextField(
            key: const Key('edit_lng'),
            controller: _lng,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(labelText: 'Kinh độ (ví dụ 106.7009)'),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('use_here'),
              onPressed: _busy ? null : _useHere,
              icon: const Icon(Icons.my_location),
              label: const Text('Dùng vị trí hiện tại'),
            ),
          ),
          TextField(
            key: const Key('edit_note'),
            controller: _note,
            decoration: const InputDecoration(labelText: 'Ghi chú (không bắt buộc)'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 16),
          FilledButton(key: const Key('edit_save'), onPressed: _save, child: const Text('Lưu')),
        ],
      ),
    );
  }
}
