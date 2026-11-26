import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/trip/trip_models.dart';
import '../../domain/time/local_time.dart';
import '../common/format.dart';

enum RevenuePeriod { today, week, month }

class RevenueScreen extends ConsumerStatefulWidget {
  const RevenueScreen({super.key});

  @override
  ConsumerState<RevenueScreen> createState() => _RevenueScreenState();
}

class _RevenueScreenState extends ConsumerState<RevenueScreen> {
  RevenuePeriod _p = RevenuePeriod.today;
  RevenueSummary? _s;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final int now = ref.read(clockProvider)();
    final int dayStart = localDayStartMs(now);
    const int day = 86400000;
    late final int from;
    switch (_p) {
      case RevenuePeriod.today:
        from = dayStart;
      case RevenuePeriod.week:
        from = dayStart - 6 * day;
      case RevenuePeriod.month:
        from = localMonthStartMs(now);
    }
    final List<TripListItem> trips =
        await ref.read(tripRepositoryProvider).tripsInRange(from, dayStart + day);
    if (mounted) setState(() => _s = RevenueSummary.from(trips));
  }

  @override
  Widget build(BuildContext context) {
    final RevenueSummary? s = _s;
    Widget row(String k, String v, {Key? key}) => ListTile(title: Text(k), trailing: Text(v, key: key));
    return Scaffold(
      appBar: AppBar(title: const Text('Doanh thu')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SegmentedButton<RevenuePeriod>(
            segments: const <ButtonSegment<RevenuePeriod>>[
              ButtonSegment<RevenuePeriod>(value: RevenuePeriod.today, label: Text('Hôm nay')),
              ButtonSegment<RevenuePeriod>(value: RevenuePeriod.week, label: Text('7 ngày')),
              ButtonSegment<RevenuePeriod>(value: RevenuePeriod.month, label: Text('Tháng này')),
            ],
            selected: <RevenuePeriod>{_p},
            onSelectionChanged: (Set<RevenuePeriod> v) {
              setState(() => _p = v.first);
              _reload();
            },
          ),
          const SizedBox(height: 16),
          if (s == null)
            const Center(child: CircularProgressIndicator())
          else ...<Widget>[
            row('Tổng doanh thu', formatVnd(s.totalVnd), key: const Key('rev_total')),
            row('Số chuyến', '${s.tripCount}', key: const Key('rev_count')),
            row('Quãng đường', formatKm(s.distanceM)),
            const Divider(),
            row('Tiền mặt đã thu', formatVnd(s.cashVnd), key: const Key('rev_cash')),
            row('Chuyển khoản đã nhận', formatVnd(s.qrPaidVnd), key: const Key('rev_qr')),
            row('Chưa thu', formatVnd(s.unpaidVnd), key: const Key('rev_unpaid')),
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('Không tính chuyến chạy thử và chuyến trong thùng rác.'),
            ),
          ],
        ],
      ),
    );
  }
}
