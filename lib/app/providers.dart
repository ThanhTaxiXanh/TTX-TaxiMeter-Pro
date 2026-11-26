import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/bank/bank_repository.dart';
import '../data/db/app_database.dart';
import '../data/map/map_source_service.dart';
import '../domain/traffic/traffic_models.dart';
import '../data/payment/payment_repository.dart';
import '../data/trip/tombstone_repository.dart';
import '../data/trip/trip_repository.dart';
import '../data/trip/trip_store.dart';
import '../platform/brightness_control.dart';
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
  return SignIndex.fromBytes(d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes));
});

final FutureProvider<List<Poi>> poiProvider = FutureProvider<List<Poi>>((Ref ref) async {
  return parsePoiJson(await rootBundle.loadString('assets/data/poi.json'));
});

final Provider<MapSourceService> mapSourceServiceProvider =
    Provider<MapSourceService>((Ref ref) => MapSourceService());
