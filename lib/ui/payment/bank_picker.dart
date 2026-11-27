import 'package:flutter/material.dart';

import '../../data/bank/bank_repository.dart';
import '../../domain/traffic/sign_catalog.dart' show foldVi;

/// Loc ngan hang theo ten, ma hoac BIN (khong phan biet dau).
List<BankInfo> filterBanks(List<BankInfo> all, String query) {
  final String q = foldVi(query.trim()).replaceAll(' ', '');
  if (q.isEmpty) return all;
  return all.where((BankInfo b) {
    return foldVi(b.shortName).replaceAll(' ', '').contains(q) ||
        foldVi(b.code).contains(q) ||
        b.bin.contains(q);
  }).toList();
}

/// Bang chon ngan hang co o tim nhanh.
Future<BankInfo?> showBankPicker(BuildContext context, List<BankInfo> banks) {
  return showModalBottomSheet<BankInfo>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext c) => FractionallySizedBox(heightFactor: 0.85, child: _BankPicker(banks)),
  );
}

class _BankPicker extends StatefulWidget {
  const _BankPicker(this.banks);
  final List<BankInfo> banks;

  @override
  State<_BankPicker> createState() => _BankPickerState();
}

class _BankPickerState extends State<_BankPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final List<BankInfo> shown = filterBanks(widget.banks, _q);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Chọn ngân hàng', style: Theme.of(context).textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: const Key('bank_search'),
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Tìm tên, mã hoặc BIN (vd vcb, 970436)'),
              onChanged: (String v) => setState(() => _q = v),
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? const Center(child: Text('Không có ngân hàng phù hợp.'))
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (BuildContext c, int i) {
                      final BankInfo b = shown[i];
                      return ListTile(
                        key: Key('bank_${b.bin}'),
                        leading: CircleAvatar(child: Text(b.code.substring(0, b.code.length < 2 ? b.code.length : 2))),
                        title: Text(b.shortName),
                        subtitle: Text('${b.code} · ${b.bin}'),
                        onTap: () => Navigator.pop(context, b),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
