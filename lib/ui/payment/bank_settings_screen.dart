import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/bank/bank_repository.dart';
import '../../payment/vietqr_payload_builder.dart';
import '../../platform/files.dart';
import '../../platform/image_resize.dart';
import 'bank_picker.dart';
import 'qr_with_logos.dart';

/// Danh sach tai khoan nhan tien (nhieu tai khoan, 1 mac dinh) dung de sinh VietQR offline.
class BankSettingsScreen extends ConsumerStatefulWidget {
  const BankSettingsScreen({super.key});

  @override
  ConsumerState<BankSettingsScreen> createState() => _BankSettingsScreenState();
}

class _BankSettingsScreenState extends ConsumerState<BankSettingsScreen> {
  List<DriverAccount> _accounts = <DriverAccount>[];
  Map<String, String> _bankNames = <String, String>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final BankRepository repo = ref.read(bankRepositoryProvider);
    await repo.ensureSeeded(ref.read(clockProvider)());
    final List<BankInfo> banks = await repo.listBanks();
    final List<DriverAccount> acc = await repo.listAccounts();
    if (!mounted) return;
    setState(() {
      _bankNames = <String, String>{for (final BankInfo b in banks) b.bin: b.shortName};
      _accounts = acc;
      _loading = false;
    });
  }

  Future<void> _edit(DriverAccount? a) async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => BankAccountEditScreen(account: a)),
    );
    if (saved == true) await _load();
  }

  Future<void> _delete(DriverAccount a) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Xóa tài khoản này?'),
        content: Text('${_bankNames[a.bin] ?? a.bin} · ${a.accountNumber}'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hủy')),
          FilledButton(key: const Key('confirm_delete_account'), onPressed: () => Navigator.pop(c, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(bankRepositoryProvider).deleteAccount(a.id!);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tài khoản nhận tiền')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add_account'),
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('Thêm tài khoản'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: <Widget>[
                if (_accounts.isEmpty) const Text('Chưa có tài khoản. Bấm "Thêm tài khoản" để nhập.'),
                for (final DriverAccount a in _accounts)
                  Card(
                    child: ListTile(
                      key: Key('account_${a.id}'),
                      leading: Icon(a.isDefault ? Icons.star : Icons.account_balance, color: a.isDefault ? Colors.amber : null),
                      title: Text('${_bankNames[a.bin] ?? a.bin} · ${a.accountNumber}'),
                      subtitle: Text('${a.holder}${a.label.isEmpty ? '' : ' · ${a.label}'}${a.isDefault ? ' · Mặc định' : ''}'),
                      onTap: () => _edit(a),
                      trailing: PopupMenuButton<String>(
                        key: Key('menu_${a.id}'),
                        onSelected: (String v) async {
                          if (v == 'default') {
                            await ref.read(bankRepositoryProvider).setDefault(a.id!);
                            await _load();
                          } else if (v == 'delete') {
                            await _delete(a);
                          } else {
                            await _edit(a);
                          }
                        },
                        itemBuilder: (_) => <PopupMenuEntry<String>>[
                          if (!a.isDefault) const PopupMenuItem<String>(value: 'default', child: Text('Đặt làm mặc định')),
                          const PopupMenuItem<String>(value: 'edit', child: Text('Sửa')),
                          const PopupMenuItem<String>(value: 'delete', child: Text('Xóa')),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'Tài khoản mặc định dùng để tạo mã QR khi thu tiền; có thể đổi tài khoản ngay trên màn hình QR. '
                  'Mã QR tạo ngay trên máy, không gửi dữ liệu đi đâu. Số tài khoản và logo nằm trong cơ sở dữ liệu và đi theo bản sao lưu.',
                ),
              ],
            ),
    );
  }
}

/// Them/sua mot tai khoan: ngan hang (tim nhanh), so TK, chu TK, logo giua va logo duoi QR, xem truoc QR.
class BankAccountEditScreen extends ConsumerStatefulWidget {
  const BankAccountEditScreen({super.key, this.account});
  final DriverAccount? account;

  @override
  ConsumerState<BankAccountEditScreen> createState() => _BankAccountEditScreenState();
}

class _BankAccountEditScreenState extends ConsumerState<BankAccountEditScreen> {
  final TextEditingController _acc = TextEditingController();
  final TextEditingController _holder = TextEditingController();
  final TextEditingController _label = TextEditingController();
  List<BankInfo> _banks = <BankInfo>[];
  BankInfo? _bank;
  Uint8List? _center;
  Uint8List? _bottom;
  bool _default = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    final DriverAccount? a = widget.account;
    if (a != null) {
      _acc.text = a.accountNumber;
      _holder.text = a.holder;
      _label.text = a.label;
      _center = a.centerLogo;
      _bottom = a.bottomLogo;
      _default = a.isDefault;
    }
    _load();
  }

  Future<void> _load() async {
    final BankRepository repo = ref.read(bankRepositoryProvider);
    await repo.ensureSeeded(ref.read(clockProvider)());
    final List<BankInfo> banks = await repo.listBanks();
    if (!mounted) return;
    setState(() {
      _banks = banks;
      final String? bin = widget.account?.bin;
      if (bin != null) {
        for (final BankInfo b in banks) {
          if (b.bin == bin) _bank = b;
        }
      }
    });
  }

  Future<void> _pickBank() async {
    final BankInfo? b = await showBankPicker(context, _banks);
    if (b != null) setState(() => _bank = b);
  }

  Future<void> _pickLogo({required bool center}) async {
    try {
      final Uint8List? raw = await pickFileBytes(extensions: <String>['png', 'jpg', 'jpeg', 'webp']);
      if (raw == null) return;
      final Uint8List png = await shrinkToPng(raw, maxSide: center ? 192 : 400);
      setState(() => center ? _center = png : _bottom = png);
    } catch (e) {
      setState(() => _msg = 'Không đọc được ảnh: $e');
    }
  }

  Future<void> _save() async {
    final String acc = _acc.text.trim();
    final String holder = _holder.text.trim();
    if (_bank == null || acc.isEmpty || holder.isEmpty) {
      setState(() => _msg = 'Vui lòng chọn ngân hàng và nhập đủ số tài khoản, tên chủ tài khoản.');
      return;
    }
    final DriverAccount base = widget.account ??
        DriverAccount(bin: _bank!.bin, accountNumber: acc, holder: holder);
    await ref.read(bankRepositoryProvider).saveAccount(
          DriverAccount(
            id: base.id,
            label: _label.text,
            bin: _bank!.bin,
            accountNumber: acc,
            holder: holder.toUpperCase(),
            isDefault: _default,
            centerLogo: _center,
            bottomLogo: _bottom,
          ),
          ref.read(clockProvider)(),
        );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _acc.dispose();
    _holder.dispose();
    _label.dispose();
    super.dispose();
  }

  String? _preview() {
    if (_bank == null || _acc.text.trim().isEmpty) return null;
    try {
      return VietQrPayload.build(bin: _bank!.bin, account: _acc.text.trim(), amountVnd: 10000, content: 'XEM TRUOC');
    } catch (_) {
      return null;
    }
  }

  Widget _logoRow(String title, Uint8List? data, bool center) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: data == null
            ? const SizedBox(width: 48, height: 48, child: Icon(Icons.image_outlined))
            : Image.memory(data, width: 48, height: 48, fit: BoxFit.contain),
        title: Text(title),
        trailing: Wrap(
          spacing: 4,
          children: <Widget>[
            OutlinedButton(key: Key(center ? 'logo_center' : 'logo_bottom'), onPressed: () => _pickLogo(center: center), child: Text(data == null ? 'Chọn ảnh' : 'Đổi')),
            if (data != null)
              IconButton(
                key: Key(center ? 'logo_center_clear' : 'logo_bottom_clear'),
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => center ? _center = null : _bottom = null),
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final String? prev = _preview();
    return Scaffold(
      appBar: AppBar(title: Text(widget.account == null ? 'Thêm tài khoản' : 'Sửa tài khoản')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          InkWell(
            key: const Key('bank'),
            onTap: _pickBank,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Ngân hàng', suffixIcon: Icon(Icons.search)),
              child: Text(_bank == null ? 'Bấm để tìm và chọn' : '${_bank!.shortName} (${_bank!.bin})'),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('account'),
            controller: _acc,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(19)],
            decoration: const InputDecoration(labelText: 'Số tài khoản'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('holder'),
            controller: _holder,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Tên chủ tài khoản (không dấu)'),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('label'),
            controller: _label,
            decoration: const InputDecoration(labelText: 'Tên gợi nhớ (không bắt buộc)'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            key: const Key('is_default'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Dùng làm tài khoản mặc định'),
            value: _default,
            onChanged: (bool v) => setState(() => _default = v),
          ),
          const Divider(),
          _logoRow('Logo giữa mã QR', _center, true),
          _logoRow('Logo dưới mã QR', _bottom, false),
          if (prev != null) ...<Widget>[
            const SizedBox(height: 12),
            const Text('Xem trước (số tiền mẫu 10.000 đ):'),
            const SizedBox(height: 8),
            Center(child: QrWithLogos(data: prev, size: 200, centerLogo: _center, bottomLogo: _bottom)),
          ],
          const SizedBox(height: 24),
          FilledButton(key: const Key('save'), onPressed: _save, child: const Text('Lưu')),
          if (_msg != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_msg!)),
        ],
      ),
    );
  }
}
