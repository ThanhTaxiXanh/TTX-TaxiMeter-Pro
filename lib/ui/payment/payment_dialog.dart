import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/providers.dart';
import '../../data/bank/bank_repository.dart';
import '../../payment/qr_content_generator.dart';
import '../../payment/vietqr_payload_builder.dart';
import '../common/format.dart';
import 'bank_settings_screen.dart';

/// Hop thoai thanh toan sau khi ket thuc chuyen: Tien mat hoac QR chuyen khoan.
class PaymentDialog extends ConsumerStatefulWidget {
  const PaymentDialog({
    super.key,
    required this.tripId,
    required this.startedAtMs,
    required this.amountVnd,
    required this.distanceM,
    required this.waitingSec,
  });

  final String tripId;
  final int startedAtMs;
  final int amountVnd;
  final int distanceM;
  final int waitingSec;

  @override
  ConsumerState<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<PaymentDialog> {
  String? _qr;
  String? _content;
  DriverAccount? _acc;
  String? _bankName;
  String? _error;
  bool _paid = false;

  Future<void> _cash() async {
    await ref.read(paymentRepositoryProvider).record(
          tripId: widget.tripId,
          method: 'CASH',
          state: 'PAID',
          amountVnd: widget.amountVnd,
          nowMs: ref.read(clockProvider)(),
        );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _showQr() async {
    final BankRepository banks = ref.read(bankRepositoryProvider);
    final int now = ref.read(clockProvider)();
    await banks.ensureSeeded(now);
    final DriverAccount? acc = await banks.getDriverAccount();
    if (acc == null) {
      setState(() => _error = 'Chưa cài tài khoản nhận tiền. Bấm "Cài tài khoản" để nhập.');
      return;
    }
    try {
      final int seq = await ref.read(paymentRepositoryProvider).sequenceInDay(widget.startedAtMs);
      final String content =
          transferContent(tripStartedAtMs: widget.startedAtMs, sequenceInDay: seq);
      final String payload = VietQrPayload.build(
        bin: acc.bin,
        account: acc.accountNumber,
        amountVnd: widget.amountVnd,
        content: content,
      );
      await ref.read(paymentRepositoryProvider).record(
            tripId: widget.tripId,
            method: 'QR',
            state: 'UNPAID',
            amountVnd: widget.amountVnd,
            nowMs: now,
            qrContent: payload,
            bankBin: acc.bin,
            bankAccount: acc.accountNumber,
            accountHolder: acc.holder,
          );
      final BankInfo? bank = await banks.findByBin(acc.bin);
      await ref.read(brightnessProvider).setMax();
      if (!mounted) return;
      setState(() {
        _qr = payload;
        _content = content;
        _acc = acc;
        _bankName = bank?.shortName ?? acc.bin;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Không tạo được mã QR: $e');
    }
  }

  Future<void> _confirmPaid() async {
    await ref.read(paymentRepositoryProvider).markPaid(widget.tripId, ref.read(clockProvider)());
    await ref.read(brightnessProvider).restore();
    if (mounted) {
      setState(() => _paid = true);
      Navigator.pop(context);
    }
  }

  Future<void> _close() async {
    await ref.read(brightnessProvider).restore();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    final bool qrStage = _qr != null;
    return PopScope(
      canPop: false,
      // Dung Dialog (khong phai AlertDialog): QrImageView dung LayoutBuilder,
      // khong do duoc intrinsic size cua AlertDialog.
      child: Dialog(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text(qrStage ? 'Quét mã để thanh toán' : 'Đã lưu chuyến',
                  style: t.textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(formatVnd(widget.amountVnd),
                  key: const Key('pay_amount'),
                  style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (!qrStage) ...<Widget>[
                Text('Quãng đường: ${formatKm(widget.distanceM)}'),
                Text('Chờ: ${formatDuration(widget.waitingSec)}'),
              ] else ...<Widget>[
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(8),
                  child: QrImageView(
                    key: const Key('qr'),
                    data: _qr!,
                    size: 240,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                ),
                const SizedBox(height: 8),
                Text('$_bankName · ${_acc!.accountNumber}'),
                Text(_acc!.holder),
                Text('Nội dung: $_content'),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(color: t.colorScheme.error)),
                ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: qrStage
            ? <Widget>[
                TextButton(key: const Key('qr_close'), onPressed: _close, child: const Text('Đóng (chưa thu)')),
                FilledButton(
                  key: const Key('qr_paid'),
                  onPressed: _paid ? null : _confirmPaid,
                  child: const Text('Đã nhận tiền'),
                ),
              ]
            : <Widget>[
                if (_error != null)
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const BankSettingsScreen()),
                    ),
                    child: const Text('Cài tài khoản'),
                  ),
                TextButton(
                  key: const Key('pay_later'),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Để sau'),
                ),
                TextButton(key: const Key('pay_qr'), onPressed: _showQr, child: const Text('Chuyển khoản QR')),
                FilledButton(key: const Key('pay_cash'), onPressed: _cash, child: const Text('Tiền mặt')),
              ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
