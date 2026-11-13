/// The plan rules: what is free, what is Pro, and the limits.
///
/// Nothing here touches the phone or the network, so it is easy to test.
library;

import '../l10n/strings.dart';

/// What the free plan allows. The limits live here only, so changing one is a
/// one-line edit and every screen follows.
class FreePlan {
  /// New bookings a shop may create in one calendar month before Pro is
  /// needed. Existing bookings stay fully usable.
  static const bookingsPerMonth = 12;

  /// Photos kept on one booking (pickup and return together).
  static const photosPerBooking = 2;
}

/// From this many bookings the app starts telling the user how many are left.
const warnAtBookings = 9;

/// Length of the Pro trial every phone gets once.
const trialLengthDays = 7;

enum Tier { free, trial, pro }

/// Things that need Pro. `en` is the wording shown on the Pro prompt and in
/// the feature list.
enum ProFeature {
  unlimitedBookings('Unlimited bookings every month'),
  unlimitedPhotos('Unlimited photos on every booking'),
  notifications('Daily and custom reminder notifications'),
  autoBackup('Automatic daily backup to Google Drive'),
  multiShop('More than one shop, each kept separately'),
  staff('Staff logins (Admin, Staff, Cashier)');

  /// English wording; also the translation key (see `tr`).
  final String en;
  const ProFeature(this.en);

  String get label => tr(en);
}

enum BookingState { ok, nearLimit, blocked }

/// What this install is allowed to do right now.
class Entitlement {
  const Entitlement({
    required this.tier,
    this.enforced = false,
    this.trialEnds,
    this.proUntil,
    this.paidUntil,
  });

  final Tier tier;

  /// false = the launch period: everything is unlocked whatever the tier.
  /// (The license server turns this on when the paywall goes live.)
  final bool enforced;

  final DateTime? trialEnds;

  /// How long the app trusts Pro WITHOUT asking the server again: the
  /// subscription's end, or the license's own expiry if that comes first.
  final DateTime? proUntil;

  /// When the subscription itself ends (what Google Play says). Only for
  /// showing to the user: access is decided by [proUntil].
  final DateTime? paidUntil;

  /// Nothing is locked: the paywall is off, or the plan includes Pro.
  bool get unlocked => !enforced || tier != Tier.free;

  bool allows(ProFeature feature) => unlocked;

  /// Where a shop with [usedThisMonth] bookings stands against the free limit.
  BookingState bookingState(int usedThisMonth) {
    if (unlocked) return BookingState.ok;
    if (usedThisMonth >= FreePlan.bookingsPerMonth) return BookingState.blocked;
    if (usedThisMonth >= warnAtBookings) return BookingState.nearLimit;
    return BookingState.ok;
  }

  /// Whole days of trial left (a started day counts), or null if not on trial.
  int? trialDaysLeft(DateTime now) {
    final ends = trialEnds;
    if (tier != Tier.trial || ends == null) return null;
    final left = ends.difference(now);
    return left.isNegative ? 0 : (left.inMinutes / (24 * 60)).ceil();
  }

  /// The plan for an install, from what is known locally.
  static Entitlement derive({
    required DateTime now,
    required DateTime trialStart,
    DateTime? proUntil,
    DateTime? paidUntil,
    bool enforced = false,
  }) {
    final trialEnds = trialStart.add(const Duration(days: trialLengthDays));
    final tier = (proUntil != null && proUntil.isAfter(now))
        ? Tier.pro
        : now.isBefore(trialEnds)
        ? Tier.trial
        : Tier.free;
    return Entitlement(
      tier: tier,
      enforced: enforced,
      trialEnds: trialEnds,
      proUntil: proUntil,
      paidUntil: paidUntil,
    );
  }
}

/// Stops the phone's clock being used to cheat the monthly limit or the trial.
///
/// If the clock is moved back, the latest time ever seen is used instead.
/// Moving it forward cannot help (it only uses up the trial sooner).
class TimeGuard {
  static const tolerance = Duration(minutes: 5);

  static DateTime effective(DateTime now, DateTime? latestSeen) {
    if (latestSeen != null && now.isBefore(latestSeen.subtract(tolerance))) {
      return latestSeen;
    }
    return now;
  }
}

/// First instant of the calendar month containing [t], and of the next one.
({DateTime from, DateTime to}) monthBounds(DateTime t) =>
    (from: DateTime(t.year, t.month), to: DateTime(t.year, t.month + 1));
