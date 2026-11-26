import 'package:geolocator/geolocator.dart';

/// Vi tri hien tai dang E7 (lat, lng) hoac null neu khong lay duoc.
Future<({int latE7, int lngE7})?> currentPositionE7() async {
  try {
    final Position p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
    );
    return (latE7: (p.latitude * 10000000).round(), lngE7: (p.longitude * 10000000).round());
  } catch (_) {
    return null;
  }
}
