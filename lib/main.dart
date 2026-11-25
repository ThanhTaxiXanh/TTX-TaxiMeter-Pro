import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/providers.dart';
import 'data/db/open_database.dart';
import 'ui/dashboard/dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ProviderScope(
    overrides: <Override>[
      databaseProvider.overrideWith((Ref ref) {
        final db = openAppDatabase();
        ref.onDispose(db.close);
        return db;
      }),
    ],
    child: const TtxApp(),
  ));
}

class TtxApp extends StatelessWidget {
  const TtxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TTX TaxiMeter Pro',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.green,
      ),
      home: const DashboardScreen(),
    );
  }
}
