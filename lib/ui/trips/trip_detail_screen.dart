import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/trip/trip_models.dart';
import '../../domain/time/local_time.dart';
import '../common/format.dart';
import 'trip_list_screen.dart' show paymentLabel;

class TripDetailScreen extends ConsumerStatefulWidget {
  const TripDetailScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends ConsumerState<TripDetailScreen> {
  TripDetail? _d;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final TripDetail? d = await ref.read(tripRepositoryProvider).getTrip(widget.tripId);
    if (mounted) setState(() => _d = d);
  }

  Future<void> _edit() async {
    final TripDetail d = _d!;
    final TextEditingController note = TextEditingController(text: d.item.note ?? '');
    bool test = d.item.isTest;
    final bool? ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext c) => StatefulBuilder(
        builder: (BuildContext c, StateSetter set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(c).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('Sửa thông tin chuyến'),
              TextField(
                key: const Key('note'),
                controller: note,
                decoration: const InputDecoration(labelText: 'Ghi chú'),
              ),
              SwitchListTile(
                key: const Key('test'),
                title: const Text('Chuyến chạy thử (không tính doanh thu)'),
                value: test,
                onChanged: (bool v) => set(() => test = v),
              ),
              const Text('Số tiền cước không sửa được. Muốn đổi tiền hãy dùng "Điều chỉnh tiền".'),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('edit_save'),
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Lưu'),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) {
      await ref.read(tripRepositoryProvider).editMeta(
            tripId: d.item.tripId,
            note: note.text,
            isTest: test,
            nowMs: ref.read(clockProvider)(),
          );
      await _reload();
    }
  }

  Future<void> _adjust() async {
    final TextEditingController amount = TextEditingController();
    final TextEditingController reason = TextEditingController();
    String? err;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => StatefulBuilder(
        builder: (BuildContext c, StateSetter set) => AlertDialog(
          title: const Text('Điều chỉnh tiền'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                key: const Key('adj_amount'),
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(signed: true),
                decoration: const InputDecoration(labelText: 'Số tiền (+ tăng, - giảm), VND'),
              ),
              TextField(
                key: const Key('adj_reason'),
                controller: reason,
                decoration: const InputDecoration(labelText: 'Lý do (bắt buộc)'),
              ),
              if (err != null) Text(err!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hủy')),
            FilledButton(
              key: const Key('adj_ok'),
              onPressed: () {
                final int? v = int.tryParse(amount.text.trim());
                if (v == null || v == 0 || reason.text.trim().isEmpty) {
                  set(() => err = 'Nhập số tiền khác 0 và lý do.');
                  return;
                }
                Navigator.pop(c, true);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await ref.read(tripRepositoryProvider).addAdjustment(
            tripId: widget.tripId,
            amountVnd: int.parse(amount.text.trim()),
            reason: reason.text,
            nowMs: ref.read(clockProvider)(),
          );
      await _reload();
    }
  }

  Future<void> _trash() async {
    await ref.read(tripRepositoryProvider).moveToTrash(widget.tripId, null, ref.read(clockProvider)());
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final TripDetail? d = _d;
    if (d == null) {
      return Scaffold(appBar: AppBar(title: const Text('Chi tiết chuyến')), body: const Center(child: CircularProgressIndicator()));
    }
    final TripListItem t = d.item;
    Widget row(String k, String v, {Key? key}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[Text(k), Text(v, key: key)],
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết chuyến')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Center(
            child: Text(formatVnd(t.effectiveTotalVnd),
                key: const Key('total'),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
          ),
          if (t.adjustmentVnd != 0) Center(child: Text('Cước gốc ${formatVnd(t.fareTotalVnd)}, điều chỉnh ${formatVnd(t.adjustmentVnd)}')),
          const SizedBox(height: 16),
          row('Bắt đầu', formatLocalDateTime(t.startedAt)),
          row('Kết thúc', formatLocalDateTime(t.endedAt)),
          row('Thời gian', formatDuration(t.durationSec)),
          row('Quãng đường', formatKm(t.distanceM)),
          row('Chờ', formatDuration(t.waitingSec)),
          const Divider(),
          row('Mở cửa', formatVnd(d.fareOpening)),
          row('Quãng đường', formatVnd(d.fareDistance)),
          row('Chờ', formatVnd(d.fareWaiting)),
          row('Phụ phí', formatVnd(d.fareSurcharge)),
          const Divider(),
          row('Thanh toán', paymentLabel(t.paymentMethod, t.paymentState)),
          row('Biểu giá', '${d.configId} v${d.configVersion}'),
          row('Mã băm cước', d.fareHash.substring(0, 12)),
          if (t.note != null) row('Ghi chú', t.note!),
          if (t.isTest) const Text('Chuyến chạy thử: không tính vào doanh thu.'),
          if (d.isReconstructed) const Text('Chuyến được khôi phục từ bản ghi đã xóa.'),
          if (d.adjustments.isNotEmpty) ...<Widget>[
            const Divider(),
            const Text('Điều chỉnh tiền'),
            for (final Adjustment a in d.adjustments)
              ListTile(
                dense: true,
                title: Text(formatVnd(a.amountVnd)),
                subtitle: Text('${a.reason} · ${formatLocalDateTime(a.createdAt)}'),
              ),
          ],
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
            OutlinedButton(key: const Key('btn_edit'), onPressed: _edit, child: const Text('Sửa ghi chú')),
            OutlinedButton(key: const Key('btn_adjust'), onPressed: _adjust, child: const Text('Điều chỉnh tiền')),
            OutlinedButton(key: const Key('btn_trash'), onPressed: _trash, child: const Text('Chuyển vào thùng rác')),
          ]),
        ],
      ),
    );
  }
}
