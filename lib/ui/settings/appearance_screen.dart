import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode m = ref.watch(themeModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Giao diện')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text('Giao diện ứng dụng'),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            key: const Key('theme_mode'),
            segments: const <ButtonSegment<ThemeMode>>[
              ButtonSegment<ThemeMode>(value: ThemeMode.dark, label: Text('Tối'), icon: Icon(Icons.dark_mode)),
              ButtonSegment<ThemeMode>(value: ThemeMode.light, label: Text('Sáng'), icon: Icon(Icons.light_mode)),
              ButtonSegment<ThemeMode>(value: ThemeMode.system, label: Text('Hệ thống'), icon: Icon(Icons.phone_android)),
            ],
            selected: <ThemeMode>{m},
            onSelectionChanged: (Set<ThemeMode> v) => ref.read(themeModeProvider.notifier).set(v.first),
          ),
          const SizedBox(height: 16),
          const Text('Giao diện bản đồ (Sáng/Tối/Tự động) chỉnh ở mục Bản đồ.'),
        ],
      ),
    );
  }
}
