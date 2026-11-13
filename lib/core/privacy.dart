import 'package:flutter/services.dart';

/// Small privacy helpers that need the Android side.
class Privacy {
  static const _channel = MethodChannel('gellsoft/privacy');

  /// Hides (or shows again) this app's preview in the recent-apps list.
  /// Used while the app lock is on. A no-op where it is not supported.
  static Future<void> hideRecentsPreview(bool hide) async {
    try {
      await _channel.invokeMethod<void>('hideRecentsPreview', {'hide': hide});
    } on MissingPluginException {
      // Not running on Android (or in a test): nothing to do.
    } on PlatformException {
      // Best effort only.
    }
  }
}
