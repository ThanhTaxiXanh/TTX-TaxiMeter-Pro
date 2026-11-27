import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/traffic/sign_catalog.dart';

Color _bg(String g) => g == 'W' ? const Color(0xFFFFD600) : (g == 'P' ? Colors.white : const Color(0xFF1565C0));
Color _fg(String g) => (g == 'W' || g == 'P') ? Colors.black : Colors.white;

/// Bang chon bien trong danh muc QCVN: tab theo nhom, tim theo ma hoac ten.
Future<CatalogSign?> showSignPicker(BuildContext context) {
  return showModalBottomSheet<CatalogSign>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext c) => FractionallySizedBox(heightFactor: 0.92, child: const _SignPicker()),
  );
}

class _SignPicker extends ConsumerStatefulWidget {
  const _SignPicker();

  @override
  ConsumerState<_SignPicker> createState() => _SignPickerState();
}

class _SignPickerState extends ConsumerState<_SignPicker> {
  String _group = 'P';
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final List<CatalogSign>? all = ref.watch(signCatalogProvider).valueOrNull;
    final List<CatalogSign> shown = all == null ? const <CatalogSign>[] : filterCatalog(all, _group, _q);
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Chọn biển báo', style: Theme.of(context).textTheme.titleLarge),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            key: const Key('sign_search'),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Tìm theo tên hoặc mã (vd P.103a)'),
            onChanged: (String v) => setState(() => _q = v),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: <Widget>[
              for (final MapEntry<String, String> e in signGroupLabels.entries)
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
        Expanded(
          child: all == null
              ? const Center(child: CircularProgressIndicator())
              : shown.isEmpty
                  ? const Center(child: Text('Không có biển phù hợp.'))
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (BuildContext c, int i) {
                        final CatalogSign s = shown[i];
                        return ListTile(
                          key: Key('sign_${s.code}'),
                          leading: Container(
                            width: 64,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _bg(s.group),
                              borderRadius: BorderRadius.circular(s.group == 'W' || s.group == 'I' ? 6 : 20),
                              border: Border.all(color: s.group == 'P' ? Colors.red : Colors.white24, width: 2),
                            ),
                            child: Text(s.code, style: TextStyle(color: _fg(s.group), fontSize: 12, fontWeight: FontWeight.w800)),
                          ),
                          title: Text(s.name.isEmpty ? 'Chưa có tên' : s.name),
                          onTap: () => Navigator.pop(context, s),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
