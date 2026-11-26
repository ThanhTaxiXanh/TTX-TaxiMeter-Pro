import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/bank/bank_repository.dart';

/// Cai dat tai khoan ngan hang nhan tien (dung de sinh VietQR offline).
class BankSettingsScreen extends ConsumerStatefulWidget {
  const BankSettingsScreen({super.key});

  @override
  ConsumerState<BankSettingsScreen> createState() => _BankSettingsScreenState();
}

class _BankSettingsScreenState extends ConsumerState<BankSettingsScreen> {
  final TextEditingController _acc = TextEditingController();
  final TextEditingController _holder = TextEditingController();
  List<BankInfo> _banks = <BankInfo>[];
  String? _bin;
  bool _loading = true;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final BankRepository repo = ref.read(bankRepositoryProvider);
    await repo.ensureSeeded(ref.read(clockProvider)());
    final List<BankInfo> banks = await repo.listBanks();
    final DriverAccount? a = await repo.getDriverAccount();
    if (!mounted) return;
    setState(() {
      _banks = banks;
      _bin = a?.bin;
      _acc.text = a?.accountNumber ?? '';
      _holder.text = a?.holder ?? '';
      _loading = false;
    });
  }

  Future<void> _save() async {
    final String acc = _acc.text.trim();
    final String holder = _holder.text.trim();
    if (_bin == null || acc.isEmpty || holder.isEmpty) {
      setState(() => _msg = 'Vui lòng chọn ngân hàng và nhập đủ số tài khoản, tên chủ tài khoản.');
      return;
    }
    await ref.read(bankRepositoryProvider).saveDriverAccount(
          DriverAccount(bin: _bin!, accountNumber: acc, holder: holder.toUpperCase()),
          ref.read(clockProvider)(),
        );
    if (!mounted) return;
    setState(() => _msg = 'Đã lưu tài khoản nhận tiền.');
  }

  @override
  void dispose() {
    _acc.dispose();
    _holder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tài khoản nhận tiền')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                DropdownButtonFormField<String>(
                  key: const Key('bank'),
                  value: _bin,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Ngân hàng'),
                  items: _banks
                      .map((BankInfo b) => DropdownMenuItem<String>(
                            value: b.bin,
                            child: Text('${b.shortName} (${b.bin})'),
                          ))
                      .toList(),
                  onChanged: (String? v) => setState(() => _bin = v),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('account'),
                  controller: _acc,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(19),
                  ],
                  decoration: const InputDecoration(labelText: 'Số tài khoản'),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('holder'),
                  controller: _holder,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Tên chủ tài khoản (không dấu)'),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('save'),
                  onPressed: _save,
                  child: const Text('Lưu'),
                ),
                if (_msg != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_msg!)),
                const SizedBox(height: 24),
                const Text(
                  'Mã QR được tạo ngay trên máy, không gửi dữ liệu đi đâu. '
                  'Số tài khoản được lưu trong cơ sở dữ liệu của app và đi theo bản sao lưu.',
                ),
              ],
            ),
    );
  }
}
