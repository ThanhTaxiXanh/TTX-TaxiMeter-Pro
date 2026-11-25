import 'package:wakelock_plus/wakelock_plus.dart';

abstract class ScreenAwake {
  Future<void> enable();
  Future<void> disable();
}

class WakelockScreenAwake implements ScreenAwake {
  @override
  Future<void> enable() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {}
  }

  @override
  Future<void> disable() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }
}
