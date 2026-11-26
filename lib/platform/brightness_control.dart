import 'package:screen_brightness/screen_brightness.dart';

abstract class BrightnessControl {
  Future<void> setMax();
  Future<void> restore();
}

class ScreenBrightnessControl implements BrightnessControl {
  @override
  Future<void> setMax() async {
    try {
      await ScreenBrightness().setApplicationScreenBrightness(1.0);
    } catch (_) {}
  }

  @override
  Future<void> restore() async {
    try {
      await ScreenBrightness().resetApplicationScreenBrightness();
    } catch (_) {}
  }
}
