import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cloud_backup.dart';
import 'billing.dart';
import 'clock_gate.dart';
import 'license_state.dart';
import 'license_sync.dart';
import 'plan.dart';

/// Runs once when the app opens, in the background; booking never waits for it.
///
/// - starts listening for Google Play purchases (Google re-delivers a purchase
///   that was paid for but not yet confirmed with the license server);
/// - renews the license if it is missing or older than a quarter of an hour;
/// - once per install, quietly restores an earlier Play purchase.
///
/// Any failure (offline, no Play Store, server busy) is ignored: the app keeps
/// working with the license it already has.
Future<void> startSubscriptionServices(WidgetRef ref) async {
  try {
    ref.read(billingProvider);
    final sync = ref.read(licenseSyncProvider);
    if (await sync.isStale()) {
      final r = await sync.refresh();
      if (r.result == SyncResult.updated) ref.invalidate(licenseProvider);
    }
    // Is the phone's date still right? (A restarted phone asks the server.)
    ref.read(clockGuardProvider.notifier).check(allowSync: true);
    // A reinstall or new phone has a new install id and no purchase token, but
    // Google still knows the subscription: ask once, quietly.
    if (await sync.shouldAutoRestore()) {
      final asked = await ref.read(billingProvider.notifier).restoreQuietly();
      if (asked) await sync.markAutoRestored();
    }
  } catch (_) {
    // never let this break the app
  }
}

/// The daily Google Drive backup, for plans that include it. Runs when the app
/// opens and whenever it comes back to the front; it does nothing unless Drive
/// backup is on and a day has passed. Quiet: no screens, and any failure is
/// ignored (it waits an hour, then tries again).
Future<void> runAutoBackup(WidgetRef ref) async {
  try {
    final license = await ref.read(licenseProvider.future);
    if (!license.entitlement.allows(ProFeature.autoBackup)) return;
    await ref.read(cloudBackupProvider).autoBackupIfDue();
  } catch (_) {
    // never let this break the app
  }
}
