import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../data/trip/trip_store.dart';
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
