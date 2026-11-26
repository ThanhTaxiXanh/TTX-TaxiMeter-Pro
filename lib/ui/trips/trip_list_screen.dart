import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../app/providers.dart';
import '../../data/trip/trip_models.dart';
import '../../domain/time/local_time.dart';
import '../common/format.dart';
import '../ledger/reconciliation_screen.dart';
import '../ledger/revenue_screen.dart';
import '../ledger/tombstone_screen.dart';
import '../ledger/trash_screen.dart';
import 'trip_detail_screen.dart';

String paymentLabel(String? method, String? state) {
  if (method == null) return 'Chưa chọn thanh toán';
  final String m = method == 'CASH' ? 'Tiền mặt' : 'Chuyển khoản';
  switch (state) {
    case 'PAID':
      return '$m · đã thu';
    case 'VOID':
      return '$m · hủy';
    default:
      return '$m · chưa thu';
  }
}

class TripListScreen extends ConsumerStatefulWidget {
  const TripListScreen({super.key});

  @override
  ConsumerState<TripListScreen> createState() => _TripListScreenState();
}

class _TripListScreenState extends ConsumerState<TripListScreen> {
  List<TripListItem>? _trips;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<TripListItem> t = await ref.read(tripRepositoryProvider).listTrips();
    if (mounted) setState(() => _trips = t);
  }

  Future<void> _trash(TripListItem t) async {
    await ref.read(tripRepositoryProvider).moveToTrash(t.tripId, null, ref.read(clockProvider)());
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: const Text('Đã chuyển vào thùng rác (giữ 30 ngày)')),
    );
  }

  Future<void> _open(Widget w) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final List<TripListItem>? trips = _trips;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chuyến đi'),
        actions: <Widget>[
          PopupMenuButton<int>(
            key: const Key('menu'),
            onSelected: (int i) {
              switch (i) {
                case 0:
                  _open(const RevenueScreen());
                case 1:
                  _open(const TrashScreen());
                case 2:
                  _open(const TombstoneScreen());
                case 3:
                  _open(const ReconciliationScreen());
              }
            },
            itemBuilder: (_) => const <PopupMenuEntry<int>>[
              PopupMenuItem<int>(value: 0, child: Text('Doanh thu')),
              PopupMenuItem<int>(value: 1, child: Text('Thùng rác')),
              PopupMenuItem<int>(value: 2, child: Text('Chuyến đã xóa vĩnh viễn')),
              PopupMenuItem<int>(value: 3, child: Text('Đối soát')),
            ],
          ),
        ],
      ),
      body: trips == null
          ? const Center(child: CircularProgressIndicator())
          : trips.isEmpty
              ? const Center(child: Text('Chưa có chuyến nào.'))
              : ListView.builder(
                  itemCount: trips.length,
                  itemBuilder: (BuildContext c, int i) {
                    final TripListItem t = trips[i];
                    // Chua 20px mep trai de khong tranh cu chi quay lai cua Android.
                    return Padding(
                      padding: const EdgeInsets.only(left: 20),
                      child: Slidable(
                        key: ValueKey<String>(t.tripId),
                        endActionPane: ActionPane(
                          motion: const DrawerMotion(),
                          children: <Widget>[
                            SlidableAction(
                              onPressed: (_) => _trash(t),
                              backgroundColor: Theme.of(context).colorScheme.error,
                              foregroundColor: Colors.white,
                              icon: Icons.delete,
                              label: 'Thùng rác',
                            ),
                          ],
                        ),
                        child: ListTile(
                          key: Key('trip_${t.tripId}'),
                          title: Text(formatVnd(t.effectiveTotalVnd),
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                              '${formatLocalDateTime(t.startedAt)} · ${formatKm(t.distanceM)}\n'
                              '${paymentLabel(t.paymentMethod, t.paymentState)}'
                              '${t.isTest ? ' · CHẠY THỬ' : ''}'),
                          isThreeLine: true,
                          onTap: () => _open(TripDetailScreen(tripId: t.tripId)),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
