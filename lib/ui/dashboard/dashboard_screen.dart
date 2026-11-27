import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/taximeter_engine.dart';
import '../../app/providers.dart';
import '../common/format.dart';
import '../map/map_screen.dart';
import '../settings/settings_screen.dart';
import '../traffic/traffic_list_screen.dart';
import '../map/speed_limit_sign.dart';
import '../payment/bank_settings_screen.dart';
import '../trips/trip_list_screen.dart';
import '../payment/payment_dialog.dart';
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
    // Nap san du lieu bien bao/POI de ban do va canh bao khong phai cho.
    ref.read(signIndexProvider);
    ref.read(poiProvider);
    ref.read(autoMaintenanceProvider);
    Future<void>.microtask(() async {
      final TripController c = ref.read(tripControllerProvider.notifier);
      await c.requestPermissionsOnLaunch();
      await c.restoreOnLaunch();
    });
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
          barrierDismissible: false,
          builder: (BuildContext c) => PaymentDialog(
            tripId: next.finishedTripId!,
            startedAtMs: next.finishedStartedAtMs!,
            amountVnd: f.fareTotal,
            distanceM: f.distanceM,
            waitingSec: f.waitingSec,
          ),
        ).then((_) => ctl.dismissFinished());
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('TTX TaxiMeter Pro'),
        actions: <Widget>[
          IconButton(
            key: const Key('map'),
            tooltip: 'Bản đồ',
            icon: const Icon(Icons.map),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const MapScreen()),
            ),
          ),
          IconButton(
            key: const Key('traffic_list'),
            tooltip: 'Biển báo & camera',
            icon: const Icon(Icons.traffic),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TrafficListScreen()),
            ),
          ),
          IconButton(
            key: const Key('trip_list'),
            tooltip: 'Chuyến đi',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TripListScreen()),
            ),
          ),
          IconButton(
            key: const Key('bank_settings'),
            tooltip: 'Tài khoản nhận tiền',
            icon: const Icon(Icons.account_balance),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const BankSettingsScreen()),
            ),
          ),
          IconButton(
            key: const Key('settings'),
            tooltip: 'Cài đặt',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
          _GpsChip(status: s.gps),
        ],
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
                          _Metric(
                            label: 'TỐC ĐỘ',
                            value: formatSpeedKmh(s.speedMmps),
                            k: 'speed',
                            danger: s.speedLimitKmh > 0 &&
                                s.speedMmps >= 0 &&
                                s.speedMmps * 36 ~/ 1000 > s.speedLimitKmh * 10,
                          ),
                        ],
                      ),
                      if (s.running && (s.speedLimitKmh > 0 || s.cameraAheadM >= 0))
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              if (s.speedLimitKmh > 0) SpeedLimitSign(kmh: s.speedLimitKmh, size: 64),
                              if (s.cameraAheadM >= 0)
                                Padding(
                                  padding: const EdgeInsets.only(left: 16),
                                  child: Chip(
                                    key: const Key('camera_warning'),
                                    avatar: const Icon(Icons.videocam, size: 18),
                                    label: Text('Camera cách ${s.cameraAheadM} m'),
                                  ),
                                ),
                            ],
                          ),
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
  const _Metric({required this.label, required this.value, required this.k, this.highlight = false, this.danger = false});
  final String label;
  final String value;
  final String k;
  final bool highlight;
  final bool danger;

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
              color: danger ? t.colorScheme.error : (highlight ? t.colorScheme.tertiary : null),
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
