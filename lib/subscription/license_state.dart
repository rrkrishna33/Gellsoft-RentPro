import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/ids.dart';
import '../data/booking_repo.dart';
import 'license_token.dart';
import 'plan.dart';
import 'trusted_clock.dart';

/// What the app knows about this install's plan.
class LicenseState {
  const LicenseState({
    required this.entitlement,
    required this.installId,
    required this.now,
    this.claims,
  });

  final Entitlement entitlement;

  /// The verified license behind [entitlement], if the server has given one.
  final LicenseClaims? claims;

  /// Random id made on first launch. Shown in the Pro screen so support can
  /// find an install, and sent to the license server later.
  final String installId;

  /// The time to trust: the phone's clock, unless it was moved backwards.
  final DateTime now;
}

/// Keeps the install id, trial start and plan flags on the phone.
///
/// These preferences belong to this phone and are never put into a backup file.
class LicenseStore {
  static const installIdKey = 'e_install_id';
  static const trialStartKey = 'e_trial_start';
  static const lastSeenKey = 'e_last_seen';
  static const proUntilKey = 'e_pro_until';
  static const enforceKey = 'e_enforce';
  static const licenseKey = 'e_license';
  static const purchaseTokenKey = 'e_purchase_token';
  static const restoreTriedKey = 'e_restore_tried';
  static const clockServerKey = 'e_clk_server';
  static const clockLocalKey = 'e_clk_local';
  static const clockMonoKey = 'e_clk_mono';
  static const clockBootKey = 'e_clk_boot';

  /// Checks licenses; tests give it their own public key.
  LicenseStore({Uint8List? publicKey}) : _publicKey = publicKey;
  final Uint8List? _publicKey;

  /// Reads the saved state (creating the install id and starting the trial on
  /// first use) and works out the current plan.
  ///
  /// A license from the server, once saved and verified, decides the trial end,
  /// the Pro end and whether the paywall is on. Without one (never online yet,
  /// or the saved one does not verify) the phone works it out by itself.
  Future<LicenseState> load([DateTime? clock]) async {
    final sp = await SharedPreferences.getInstance();
    final real = clock ?? DateTime.now();

    final lastSeenMs = sp.getInt(lastSeenKey);
    final lastSeen = lastSeenMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(lastSeenMs);
    final now = TimeGuard.effective(real, lastSeen);
    if (lastSeen == null || now.isAfter(lastSeen)) {
      await sp.setInt(lastSeenKey, now.millisecondsSinceEpoch);
    }

    final installId = await _ensureInstallId(sp);

    var trialStartMs = sp.getInt(trialStartKey);
    if (trialStartMs == null) {
      trialStartMs = now.millisecondsSinceEpoch;
      await sp.setInt(trialStartKey, trialStartMs);
    }

    final proMs = sp.getInt(proUntilKey);
    var trialStart = DateTime.fromMillisecondsSinceEpoch(trialStartMs);
    var proUntil = proMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(proMs);
    var enforced = sp.getBool(enforceKey) ?? false;
    DateTime? paidUntil;

    final saved = sp.getString(licenseKey);
    final claims = saved == null
        ? null
        : await verifyLicense(
            saved,
            installId: installId,
            publicKey: _publicKey,
          );
    if (claims != null) {
      enforced = claims.enforce;
      final end = claims.trialEnd;
      if (end != null) {
        trialStart = end.subtract(const Duration(days: trialLengthDays));
      }
      // Pro is trusted until the license runs out, or the subscription ends,
      // whichever is sooner; after that the app must reach the server again.
      final until = claims.proUntil;
      proUntil = (claims.tier == 'pro' && until != null)
          ? (until.isBefore(claims.expires) ? until : claims.expires)
          : null;
      // what the Pro screen shows: the subscription's real end date
      paidUntil = (claims.tier == 'pro') ? until : null;
    }

    return LicenseState(
      installId: installId,
      now: now,
      entitlement: Entitlement.derive(
        now: now,
        trialStart: trialStart,
        proUntil: proUntil,
        paidUntil: paidUntil,
        enforced: enforced,
      ),
      claims: claims,
    );
  }

  Future<String> _ensureInstallId(SharedPreferences sp) async {
    var id = sp.getString(installIdKey);
    if (id == null || id.isEmpty) {
      id = newUuid();
      await sp.setString(installIdKey, id);
    }
    return id;
  }

  /// This install's id (made on first use). Does not touch the clock record.
  Future<String> installId() async =>
      _ensureInstallId(await SharedPreferences.getInstance());

  /// Keeps a license from the server (the caller has already verified it).
  Future<void> saveLicense(String license) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(licenseKey, license);
  }

  Future<String?> purchaseToken() async =>
      (await SharedPreferences.getInstance()).getString(purchaseTokenKey);

  Future<void> savePurchaseToken(String token) async =>
      (await SharedPreferences.getInstance()).setString(
        purchaseTokenKey,
        token,
      );

  /// Whether this install has already looked for an earlier Play purchase by
  /// itself (done once, so a reinstall gets Pro back without the user asking).
  Future<bool> restoreTried() async =>
      (await SharedPreferences.getInstance()).getBool(restoreTriedKey) ?? false;

  Future<void> markRestoreTried() async =>
      (await SharedPreferences.getInstance()).setBool(restoreTriedKey, true);

  /// Remembers the server's time and the phone's clocks at the moment of a
  /// license check, to notice later if the phone's date is changed.
  Future<void> saveClockReference(ClockReference r) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(clockServerKey, r.serverMs);
    await sp.setInt(clockLocalKey, r.localMs);
    final mono = r.monoMs;
    final boot = r.bootCount;
    if (mono == null) {
      await sp.remove(clockMonoKey);
    } else {
      await sp.setInt(clockMonoKey, mono);
    }
    if (boot == null) {
      await sp.remove(clockBootKey);
    } else {
      await sp.setInt(clockBootKey, boot);
    }
  }

  Future<ClockReference?> clockReference() async {
    final sp = await SharedPreferences.getInstance();
    final server = sp.getInt(clockServerKey);
    final local = sp.getInt(clockLocalKey);
    if (server == null || local == null) return null;
    return ClockReference(
      serverMs: server,
      localMs: local,
      monoMs: sp.getInt(clockMonoKey),
      bootCount: sp.getInt(clockBootKey),
    );
  }

  /// Used by the license server integration (phase 3).
  Future<void> save({DateTime? proUntil, bool? enforced}) async {
    final sp = await SharedPreferences.getInstance();
    if (proUntil == null) {
      await sp.remove(proUntilKey);
    } else {
      await sp.setInt(proUntilKey, proUntil.millisecondsSinceEpoch);
    }
    if (enforced != null) await sp.setBool(enforceKey, enforced);
  }
}

/// How many bookings were made in the calendar month containing [now].
/// Cancelled ones count, so cancelling and redoing a booking cannot dodge
/// the limit.
class BookingQuotaRepo {
  Future<int> bookingsInMonth(DateTime now) =>
      BookingRepo().createdInMonth(now);
}

class LicenseNotifier extends AsyncNotifier<LicenseState> {
  @override
  Future<LicenseState> build() => LicenseStore().load();
}

final licenseProvider = AsyncNotifierProvider<LicenseNotifier, LicenseState>(
  LicenseNotifier.new,
);

final bookingQuotaRepoProvider = Provider((_) => BookingQuotaRepo());

/// Bookings made this month (null while loading).
final bookingsThisMonthProvider = FutureProvider.autoDispose<int>((ref) async {
  final license = await ref.watch(licenseProvider.future);
  return ref.watch(bookingQuotaRepoProvider).bookingsInMonth(license.now);
});

/// The plan to use when asked synchronously; before it has loaded nothing is
/// locked, so a slow start can never block a sale.
const unlockedWhileLoading = Entitlement(tier: Tier.free, enforced: false);
