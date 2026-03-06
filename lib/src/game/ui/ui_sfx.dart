import 'package:flutter/services.dart';

/// Lightweight UI feedback helper.
class UiSfx {
  UiSfx._();

  static Future<void> tap() async {
    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {
      // Ignore missing platform support.
    }
  }
}
