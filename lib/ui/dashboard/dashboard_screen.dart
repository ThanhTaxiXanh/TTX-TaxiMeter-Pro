import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/taximeter_engine.dart';
import '../common/format.dart';
import 'trip_controller.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Khoi phuc chuyen dang do sau khi app bi tat.
    Future<void>.microtask(
        () => ref.read(tripControllerProvider.notifier).restoreOnLaunch());
  }

  Future<void> _confirmStop() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Kết thúc chuyến?'),
        content: const Text('Cước sẽ được chốt và ghi vào sổ. Không thể sửa số tiền sau đó.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Tiếp tục chạy')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kết thúc')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(tripControllerProvider.notifier).stopTrip();
    }
  }

  @override
  Widget build(BuildContext context) {
    final TripUiState s = ref.watch(tripControllerProvider);
    final TripController ctl = ref.read(tripControllerProvider.notifier);
    final ThemeData t = Theme.of(context);

    ref.listen<TripUiState>(tripControllerProvider, (TripUiState? prev, TripUiState next) {
      if (next.finished != null && prev?.finished == null) {
        final FareResult f = next.finished!;
        showDialog<void>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            title: const Text('Đã lưu chuyến'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(formatVnd(f.fareTotal),
                    style: Theme.of(c).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Quãng đường: ${formatKm(f.distanceM)}'),
                Text('Chờ: ${formatDuration(f.waitingSec)}'),
              ],
            ),
            actions: <Widget>[
              FilledButton(
                onPressed: () {
                  Navigator.pop(c);
                  ctl.dismissFinished();
                },
                child: const Text('Xong'),
              ),
            ],
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('TTX TaxiMeter Pro'),
        actions: <Widget>[_GpsChip(status: s.gps)],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              if (s.error != null)
                MaterialBanner(
                  content: Text(s.error!),
                  actions: <Widget>[TextButton(onPressed: ctl.dismissError, child: const Text('Đóng'))],
                ),
              if (s.restored && s.running)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Đã khôi phục chuyến đang chạy.'),
                ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text('CƯỚC', style: t.textTheme.labelLarge),
                      FittedBox(
                        child: Text(
                          formatVnd(s.fareVnd),
                          key: const Key('fare'),
                          style: t.textTheme.displayLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: t.colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: <Widget>[
                          _Metric(label: 'QUÃNG ĐƯỜNG', value: formatKm(s.distanceM), k: 'distance'),
                          _Metric(label: 'THỜI GIAN', value: formatDuration(s.elapsedSec), k: 'elapsed'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: <Widget>[
                          _Metric(
                            label: s.waitingNow ? 'ĐANG CHỜ' : 'CHỜ',
                            value: formatDuration(s.waitingSec),
                            k: 'waiting',
                            highlight: s.waitingNow,
                          ),
                          _Metric(label: 'TỐC ĐỘ', value: formatSpeedKmh(s.speedMmps), k: 'speed'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 64,
                child: s.running
                    ? FilledButton.icon(
                        key: const Key('stop'),
                        style: FilledButton.styleFrom(backgroundColor: t.colorScheme.error),
                        onPressed: _confirmStop,
                        icon: const Icon(Icons.stop),
                        label: const Text('KẾT THÚC CHUYẾN', style: TextStyle(fontSize: 18)),
                      )
                    : FilledButton.icon(
                        key: const Key('start'),
                        onPressed: s.phase == TripPhase.saving ? null : ctl.startTrip,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('BẮT ĐẦU CHUYẾN', style: TextStyle(fontSize: 18)),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.k, this.highlight = false});
  final String label;
  final String value;
  final String k;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(label, style: t.textTheme.labelSmall),
          Text(
            value,
            key: Key(k),
            style: t.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: highlight ? t.colorScheme.tertiary : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _GpsChip extends StatelessWidget {
  const _GpsChip({required this.status});
  final GpsStatus status;

  @override
  Widget build(BuildContext context) {
    late final String text;
    late final Color color;
    switch (status) {
      case GpsStatus.none:
        text = 'GPS: chưa chạy';
        color = Colors.grey;
      case GpsStatus.searching:
        text = 'GPS: đang tìm';
        color = Colors.amber;
      case GpsStatus.good:
        text = 'GPS: tốt';
        color = Colors.green;
      case GpsStatus.weak:
        text = 'GPS: yếu';
        color = Colors.orange;
    }
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Chip(
        key: const Key('gps'),
        avatar: Icon(Icons.circle, size: 12, color: color),
        label: Text(text),
      ),
    );
  }
}
