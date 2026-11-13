import 'dart:io';

import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';

import '../l10n/strings.dart';

/// Asks Google Play, when the app opens, whether a newer version is out.
///
/// A normal update downloads in the background while the app is used, then a
/// bar offers to restart. An update marked urgent in Play (priority 4 or 5)
/// is shown full screen. This only works for copies installed from Google
/// Play; anywhere else, or offline, it quietly does nothing.
class AppUpdate {
  AppUpdate._();

  /// Lets the "update ready" bar show from outside any screen.
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  static bool _checked = false;

  static Future<void> check() async {
    if (_checked || !Platform.isAndroid) return;
    _checked = true;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return;
      }
      if (info.updatePriority >= 4 && info.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
      } else if (info.flexibleUpdateAllowed) {
        final result = await InAppUpdate.startFlexibleUpdate();
        if (result == AppUpdateResult.success) _offerRestart();
      }
    } catch (_) {
      // not from Play, no network, or Play is busy: carry on without it
    }
  }

  static void _offerRestart() {
    final messenger = messengerKey.currentState;
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(tr('Update downloaded')),
        duration: const Duration(days: 1),
        action: SnackBarAction(
          label: tr('Restart'),
          onPressed: () {
            InAppUpdate.completeFlexibleUpdate().catchError((_) {});
          },
        ),
      ),
    );
  }
}
