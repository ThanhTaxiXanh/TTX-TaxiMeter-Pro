import 'package:screen_brightness/screen_brightness.dart';

abstract class BrightnessControl {
  Future<void> setMax();
  Future<void> restore();
}

class ScreenBrightnessControl implements BrightnessControl {
  @override
  Future<void> setMax() async {
    try {
      await ScreenBrightness().setScreenBrightness(1.0);
    } catch (_) {}
  }

  @override
  Future<void> restore() async {
    try {
      await ScreenBrightness().resetScreenBrightness();
    } catch (_) {}
  }
}
