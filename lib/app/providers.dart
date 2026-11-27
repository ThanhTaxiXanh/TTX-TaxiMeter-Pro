import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/backup/backup_service.dart';
import '../data/backup/purge_service.dart';
import '../data/tariff/tariff_repository.dart';
import '../data/bank/bank_repository.dart';
import '../data/db/app_database.dart';
import '../data/map/map_source_service.dart';
import '../domain/traffic/traffic_models.dart';
import '../data/payment/payment_repository.dart';
import '../data/traffic/traffic_repository.dart';
import '../domain/traffic/sign_catalog.dart';
import '../domain/traffic/traffic_overrides.dart';
import '../data/traffic/traffic_report_repository.dart';
import '../data/trip/tombstone_repository.dart';
import '../data/trip/trip_repository.dart';
import '../data/trip/trip_store.dart';
import '../platform/brightness_control.dart';
import '../platform/files.dart';
import '../platform/location_service.dart';
import '../platform/screen_awake.dart';

/// Phai duoc override trong main() / test.
final Provider<AppDatabase> databaseProvider = Provider<AppDatabase>(
  (Ref ref) => throw UnimplementedError('databaseProvider chua duoc override'),
);

final Provider<TripStore> tripStoreProvider =
    Provider<TripStore>((Ref ref) => DriftTripStore(ref.watch(databaseProvider)));

final Provider<LocationService> locationServiceProvider =
    Provider<LocationService>((Ref ref) => GeolocatorLocationService());

final Provider<ScreenAwake> screenAwakeProvider =
    Provider<ScreenAwake>((Ref ref) => WakelockScreenAwake());

/// Dong ho he thong (ms). Tach ra de test.
final Provider<int Function()> clockProvider = Provider<int Function()>(
  (Ref ref) => () => DateTime.now().millisecondsSinceEpoch,
);

final Provider<BankRepository> bankRepositoryProvider =
    Provider<BankRepository>((Ref ref) => BankRepository(ref.watch(databaseProvider)));

final Provider<PaymentRepository> paymentRepositoryProvider = Provider<PaymentRepository>(
    (Ref ref) => PaymentRepository(ref.watch(databaseProvider)));

final Provider<BrightnessControl> brightnessProvider =
    Provider<BrightnessControl>((Ref ref) => ScreenBrightnessControl());

final Provider<TripRepository> tripRepositoryProvider =
    Provider<TripRepository>((Ref ref) => TripRepository(ref.watch(databaseProvider)));

final Provider<TombstoneRepository> tombstoneRepositoryProvider =
    Provider<TombstoneRepository>((Ref ref) => TombstoneRepository(ref.watch(databaseProvider)));

/// Chi muc ~71k bien bao (assets/data/signs.bin), nap mot lan.
final FutureProvider<SignIndex> signIndexProvider = FutureProvider<SignIndex>((Ref ref) async {
  final ByteData d = await rootBundle.load('assets/data/signs.bin');
  final SignIndex base = SignIndex.fromBytes(d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes));
  // Gop du lieu sua tay (them diem, an bien khong con). Loi DB khong chan ban do.
  try {
    final List<TrafficOverrideItem> ov = await ref.watch(trafficRepositoryProvider).list();
    if (ov.isEmpty) return base;
    return SignIndex(applyOverrides(base.signs, ov, ref.read(clockProvider)()));
  } catch (_) {
    return base;
  }
});

final FutureProvider<List<Poi>> poiProvider = FutureProvider<List<Poi>>((Ref ref) async {
  return parsePoiJson(await rootBundle.loadString('assets/data/poi.json'));
});

final Provider<MapSourceService> mapSourceServiceProvider =
    Provider<MapSourceService>((Ref ref) => MapSourceService());

final Provider<TrafficReportRepository> trafficReportRepositoryProvider =
    Provider<TrafficReportRepository>((Ref ref) => TrafficReportRepository(ref.watch(databaseProvider)));

final Provider<TrafficRepository> trafficRepositoryProvider =
    Provider<TrafficRepository>((Ref ref) => TrafficRepository(ref.watch(databaseProvider)));

final FutureProvider<List<CatalogSign>> signCatalogProvider = FutureProvider<List<CatalogSign>>((Ref ref) async {
  return parseSignCatalog(await rootBundle.loadString('assets/data/sign_catalog.json'));
});

final Provider<BackupService> backupServiceProvider =
    Provider<BackupService>((Ref ref) => BackupService(ref.watch(databaseProvider)));

final Provider<PurgeService> purgeServiceProvider =
    Provider<PurgeService>((Ref ref) => PurgeService(ref.watch(databaseProvider)));

final Provider<TariffRepository> tariffRepositoryProvider =
    Provider<TariffRepository>((Ref ref) => TariffRepository(ref.watch(databaseProvider)));

/// Che do giao dien ung dung (mac dinh toi), luu o SharedPreferences `ui_theme`.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _load();
    return ThemeMode.dark;
  }

  Future<void> _load() async {
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final ThemeMode? m = themeModeFromName(sp.getString('ui_theme'));
      if (m != null) state = m;
    } catch (_) {}
  }

  Future<void> set(ThemeMode m) async {
    state = m;
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      await sp.setString('ui_theme', m.name);
    } catch (_) {}
  }
}

ThemeMode? themeModeFromName(String? n) {
  for (final ThemeMode m in ThemeMode.values) {
    if (m.name == n) return m;
  }
  return null;
}

final NotifierProvider<ThemeModeNotifier, ThemeMode> themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// Chay mot lan khi mo app: don thung rac qua 30 ngay (CSV luu o thu muc exports cua app). Loi bi bo qua.
final FutureProvider<int> autoMaintenanceProvider = FutureProvider<int>((Ref ref) async {
  try {
    final int now = ref.read(clockProvider)();
    final Directory dir = await appSubDir('exports');
    return await ref.read(purgeServiceProvider).purgeExpiredTrash(
          nowMs: now,
          saveCsv: (String csv, int n) async {
            await File('${dir.path}/thung-rac-${fileStamp(now)}.csv').writeAsString(csv, flush: true);
          },
        );
  } catch (_) {
    return 0;
  }
});
