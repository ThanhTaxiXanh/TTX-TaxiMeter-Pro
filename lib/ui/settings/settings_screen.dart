import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../payment/bank_settings_screen.dart';
import '../traffic/traffic_list_screen.dart';
import 'about_screen.dart';
import 'appearance_screen.dart';
import 'backup_screen.dart';
import 'cleanup_screen.dart';
import 'danger_zone_screen.dart';
import 'map_settings_screen.dart';
import 'tariff_settings_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void open(Widget w) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));
    final List<(String key, IconData icon, String title, String sub, Widget page)> items =
        <(String, IconData, String, String, Widget)>[
      ('tariff', Icons.payments, 'Biểu giá', 'Xem và nhập biểu giá', const TariffSettingsScreen()),
      ('bank', Icons.account_balance, 'Tài khoản nhận tiền', 'Ngân hàng, số tài khoản, QR', const BankSettingsScreen()),
      ('map', Icons.map, 'Bản đồ', 'File bản đồ, kiểu, giao diện, cảnh báo biển', const MapSettingsScreen()),
      ('traffic', Icons.traffic, 'Biển báo & camera', 'Điểm nhập tay, duyệt báo cáo', const TrafficListScreen()),
      ('appearance', Icons.palette, 'Giao diện', 'Tối / Sáng / Theo hệ thống', const AppearanceScreen()),
      ('backup', Icons.backup, 'Sao lưu & khôi phục', 'Tệp ZIP có checksum', const BackupScreen()),
      ('cleanup', Icons.cleaning_services, 'Dọn dẹp dữ liệu', 'Thùng rác 30 ngày, GPS thô, xuất CSV', const CleanupScreen()),
      ('danger', Icons.warning_amber, 'Vùng nguy hiểm', 'Xóa dữ liệu — phải gõ XOA', const DangerZoneScreen()),
      ('about', Icons.info_outline, 'Giới thiệu', 'Phiên bản, quyền riêng tư', const AboutScreen()),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (BuildContext c, int i) {
          final (String key, IconData icon, String title, String sub, Widget page) it = items[i];
          return ListTile(
            key: Key('set_${it.$1}'),
            leading: Icon(it.$2, color: it.$1 == 'danger' ? Theme.of(c).colorScheme.error : null),
            title: Text(it.$3),
            subtitle: Text(it.$4),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => open(it.$5),
          );
        },
      ),
    );
  }
}
