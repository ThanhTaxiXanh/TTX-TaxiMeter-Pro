import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/tariff/tariff_repository.dart';
import '../../domain/tariff/default_tariff.dart';
import '../../platform/files.dart';
import '../common/format.dart';
import 'tariff_edit_screen.dart';

class TariffSettingsScreen extends ConsumerStatefulWidget {
  const TariffSettingsScreen({super.key});

  @override
  ConsumerState<TariffSettingsScreen> createState() => _TariffSettingsScreenState();
}

class _TariffSettingsScreenState extends ConsumerState<TariffSettingsScreen> {
  List<TariffSummary>? _items;
  String? _msg;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<TariffSummary> l = await ref.read(tariffRepositoryProvider).listConfigs();
    if (mounted) setState(() => _items = l);
  }

  void _say(String m, {bool error = false}) => setState(() {
        _msg = m;
        _error = error;
      });

  Future<void> _import() async {
    try {
      final bytes = await pickFileBytes(extensions: <String>['json']);
      if (bytes == null) return;
      final cfg = await ref
          .read(tariffRepositoryProvider)
          .importJson(utf8.decode(bytes), nowMs: ref.read(clockProvider)());
      _say('Đã nhập và chọn dùng biểu giá ${cfg.configId} phiên bản ${cfg.configVersion}.');
      await _reload();
    } catch (e) {
      _say(e.toString(), error: true);
    }
  }

  Future<void> _edit(Map<String, dynamic> base, {required bool isNew, required bool active}) async {
    final bool? ok = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
      builder: (_) => TariffEditScreen(base: base, isNew: isNew, wasActive: active),
    ));
    if (ok == true) {
      _say('Đã lưu biểu giá.');
      await _reload();
    }
  }

  Future<void> _select(TariffSummary t) async {
    try {
      await ref.read(tariffRepositoryProvider).select(t.configId, nowMs: ref.read(clockProvider)());
      _say('Đang dùng biểu giá ${t.configId} cho chuyến mới.');
      await _reload();
    } catch (e) {
      _say(e.toString(), error: true);
    }
  }

  String _summary(Map<String, dynamic> j) {
    final int tiers = (j['distanceTiers'] as List<dynamic>).length;
    final Map<String, dynamic> o = j['opening'] as Map<String, dynamic>;
    return 'Mở cửa ${formatVnd(o['fareVnd'] as int)} · $tiers bậc giá';
  }

  @override
  Widget build(BuildContext context) {
    final List<TariffSummary>? items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Biểu giá')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('tariff_new'),
        onPressed: () => _edit(defaultTariffJson(effectiveFromMs: 0)..['configId'] = 'bieu-gia-moi', isNew: true, active: false),
        icon: const Icon(Icons.add),
        label: const Text('Thêm biểu giá'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: <Widget>[
          const Text('Có thể lưu nhiều biểu giá (vd xe 4 chỗ, 7 chỗ) và chọn một biểu giá dùng cho chuyến mới. '
              'Mỗi lần sửa tạo phiên bản mới; mỗi chuyến giữ nguyên biểu giá lúc bắt đầu. Biểu giá mặc định chỉ là MẪU.'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('tariff_import'),
            onPressed: _import,
            icon: const Icon(Icons.upload_file),
            label: const Text('Nhập biểu giá từ tệp JSON'),
          ),
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_msg!, style: TextStyle(color: _error ? Theme.of(context).colorScheme.error : null)),
            ),
          const SizedBox(height: 16),
          if (items == null) const Center(child: CircularProgressIndicator()),
          if (items != null)
            for (final TariffSummary t in items)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(children: <Widget>[
                        Icon(t.active ? Icons.check_circle : Icons.radio_button_unchecked, color: t.active ? Colors.green : null),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${t.configId} · v${t.version}', style: Theme.of(context).textTheme.titleMedium)),
                      ]),
                      Padding(
                        padding: const EdgeInsets.only(left: 32, top: 4),
                        child: Text('${t.active ? 'Đang dùng · ' : ''}${_summary(t.json)}'),
                      ),
                      Wrap(spacing: 8, children: <Widget>[
                        if (!t.active)
                          TextButton(key: Key('tariff_use_${t.configId}'), onPressed: () => _select(t), child: const Text('Chọn dùng')),
                        TextButton(key: Key('tariff_edit_${t.configId}'), onPressed: () => _edit(t.json, isNew: false, active: t.active), child: const Text('Sửa')),
                        TextButton(
                          key: Key('tariff_copy_${t.configId}'),
                          onPressed: () => _edit(<String, dynamic>{...t.json, 'configId': '${t.configId}-ban-sao'}, isNew: true, active: false),
                          child: const Text('Nhân bản'),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
