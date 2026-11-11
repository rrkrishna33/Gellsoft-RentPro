import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'license_state.dart';
import 'plan.dart';

/// The plan right now. Until the license has loaded nothing is locked, so a
/// slow start can never block a booking.
final entitlementProvider = Provider<Entitlement>(
  (ref) =>
      ref.watch(licenseProvider).valueOrNull?.entitlement ?? unlockedWhileLoading,
);

/// Whether Pro things are open: true on Pro, on the trial and in the launch
/// period before the paywall is switched on. Tests override it.
final isProProvider = Provider<bool>(
  (ref) => ref.watch(entitlementProvider).unlocked,
);
