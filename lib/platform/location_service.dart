import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/models/gps_sample.dart';

enum LocationPermissionState { granted, denied, deniedForever, serviceOff }

abstract class LocationService {
  Future<LocationPermissionState> ensurePermission();

  /// Android 13+: xin quyen hien thi thong bao (thong bao cua dich vu GPS).
  Future<void> requestNotificationPermission();

  /// Bat dau nhan GPS (Foreground Service khi chay ngam).
  Stream<GpsSample> start();
}

/// geolocator + thong bao Foreground Service (Android).
class GeolocatorLocationService implements LocationService {
  @override
  Future<void> requestNotificationPermission() async {
    try {
      await Permission.notification.request();
    } catch (_) {}
  }

  @override
  Future<LocationPermissionState> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationPermissionState.serviceOff;
    }
    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.deniedForever) {
      return LocationPermissionState.deniedForever;
    }
    if (p == LocationPermission.denied) return LocationPermissionState.denied;
    return LocationPermissionState.granted;
  }

  @override
  Stream<GpsSample> start() {
    final AndroidSettings settings = AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 1),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'TTX TaxiMeter Pro',
        notificationText: 'Đang ghi hành trình',
        notificationChannelName: 'Hành trình',
        // Bat buoc co icon nho hop le, neu khong Android se giet app khi bat dich vu.
        notificationIcon: AndroidResource(name: 'ic_notification', defType: 'drawable'),
        enableWakeLock: true,
      ),
    );
    return Geolocator.getPositionStream(locationSettings: settings)
        .map(_toSample);
  }

  /// Bien gioi nền tảng: double (do he dieu hanh tra) -> so nguyen MOT LAN.
  static GpsSample _toSample(Position p) => GpsSample(
        tsMs: p.timestamp.millisecondsSinceEpoch,
        latE7: (p.latitude * 10000000).round(),
        lngE7: (p.longitude * 10000000).round(),
        accuracyMm: (p.accuracy * 1000).round(),
        speedMmps: p.speed < 0 ? -1 : (p.speed * 1000).round(),
        isMock: p.isMocked,
        source: 'GPS',
      );
}
