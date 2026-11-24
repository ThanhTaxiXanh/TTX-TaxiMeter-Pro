import 'package:flutter/material.dart';

void main() {
  runApp(const TtxApp());
}

/// Khung ung dung tam thoi (Phase 1). UI that su o Phase 2 tro di.
class TtxApp extends StatelessWidget {
  const TtxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TTX TaxiMeter Pro',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: const Scaffold(
        body: Center(child: Text('TTX TaxiMeter Pro')),
      ),
    );
  }
}
