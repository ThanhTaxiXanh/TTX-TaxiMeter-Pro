import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/tariff/tariff_repository.dart';
import '../../domain/time/local_time.dart';
import '../../platform/files.dart';

class TariffSettingsScreen extends ConsumerStatefulWidget {
  const TariffSettingsScreen({super.key});

  @override
  ConsumerState<TariffSettingsScreen> createState() => _TariffSettingsScreenState();
}

class _TariffSettingsScreenState extends ConsumerState<TariffSettingsScreen> {
  List<TariffListItem>? _items;
  String? _msg;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<TariffListItem> l = await ref.read(tariffRepositoryProvider).list();
    if (mounted) setState(() => _items = l);
  }

  Future<void> _import() async {
    try {
      final bytes = await pickFileBytes(extensions: <String>['json']);
      if (bytes == null) return;
      final cfg = await ref
          .read(tariffRepositoryProvider)
          .importJson(utf8.decode(bytes), nowMs: ref.read(clockProvider)());
      setState(() {
        _error = false;
        _msg = 'Đã áp dụng biểu giá ${cfg.configId} phiên bản ${cfg.configVersion}. Chuyến đang chạy giữ biểu giá cũ.';
      });
      await _reload();
    } catch (e) {
      setState(() {
        _error = true;
        _msg = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<TariffListItem>? items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Biểu giá')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text('Biểu giá mặc định chỉ là MẪU. Hãy nhập biểu giá thật của bạn (tệp JSON schema 2.0). '
              'Biểu giá mới áp dụng từ chuyến kế tiếp; mỗi chuyến giữ nguyên biểu giá lúc bắt đầu.'),
          const SizedBox(height: 12),
          FilledButton.icon(
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
            for (final TariffListItem t in items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(t.status == 'ACTIVE' ? Icons.check_circle : Icons.history),
                title: Text('${t.configId} · v${t.version}'),
                subtitle: Text('${t.status == 'ACTIVE' ? 'Đang dùng' : 'Đã thay'} · từ ${formatLocalDateTime(t.effectiveFrom)}'),
              ),
        ],
      ),
    );
  }
}
