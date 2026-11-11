import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../core/device.dart';
import 'license_client.dart';
import 'license_state.dart';
import 'license_token.dart';
import 'trusted_clock.dart';

enum SyncResult {
  /// A genuine license was received and saved.
  updated,

  /// The server could not answer now. The old license stays in use.
  unavailable,

  /// The server answered with something that is not a valid license for this
  /// install. Ignored; the old license stays in use.
  invalid,
}

/// Asks the server for a fresh license and keeps it.
class LicenseSync {
  LicenseSync({
    LicenseApi? api,
    LicenseStore? store,
    String? appVersion,
    Uint8List? publicKey,
    DateTime Function()? clock,
    DeviceInfo? device,
  }) : _api = api ?? HttpLicenseApi(),
       _device = device ?? PlatformDeviceInfo(),
       _clock = clock ?? DateTime.now,
       _publicKey = publicKey,
       _store = store ?? LicenseStore(publicKey: publicKey),
       _appVersion = appVersion ?? AppInfo.version;

  final LicenseApi _api;
  final DeviceInfo _device;
  final LicenseStore _store;
  final String _appVersion;
  final Uint8List? _publicKey;
  final DateTime Function() _clock;

  /// A saved license younger than this is left alone. Older than this, the
  /// app asks the server again in the background (at startup, when it comes
  /// back to the front, and every few minutes while it is open), so a refund,
  /// a grant or a change of the paywall shows up within minutes. The request is
  /// tiny and carries no shop data.
  static const staleAfter = Duration(minutes: 15);

  /// Whether the phone's date and time can be trusted right now.
  Future<ClockStatus> clockStatus() async => assessClock(
    reference: await _store.clockReference(),
    localNow: _clock(),
    info: await _device.clock(),
  );

  DateTime? _lastRenewTry;

  /// True when the saved license should be renewed now: there is none, it is
  /// old, or it says Pro but the Pro period it knows about has run out (a
  /// subscription that renewed meanwhile is only known to the server).
  Future<bool> needsRenewal() async {
    final now = _clock();
    final c = (await _store.load(now)).claims;
    if (c == null || now.difference(c.issuedAt) > staleAfter) return true;
    final until = c.proUntil;
    if (c.tier != 'pro' || until == null) return false;
    final end = until.isBefore(c.expires) ? until : c.expires;
    return !end.isAfter(now);
  }

  /// Asks the server again if [needsRenewal], but not more often than
  /// [retryAfter] (an offline phone must not try every few seconds). True when
  /// a fresh license was received.
  Future<bool> renewIfNeeded({
    Duration retryAfter = const Duration(minutes: 5),
  }) async {
    final now = _clock();
    final last = _lastRenewTry;
    if (last != null && now.difference(last) < retryAfter) return false;
    if (!await needsRenewal()) return false;
    _lastRenewTry = now;
    final r = await refresh();
    return r.result == SyncResult.updated;
  }

  /// True when there is no license yet, or it is old enough to renew.
  Future<bool> isStale([DateTime? now]) async {
    final c = (await _store.load(now ?? _clock())).claims;
    return c == null || (now ?? _clock()).difference(c.issuedAt) > staleAfter;
  }

  /// True when this install should look for an earlier Play purchase by
  /// itself: the paywall is on, it is not Pro, it holds no purchase token and
  /// has not tried before (a reinstall or a new phone).
  Future<bool> shouldAutoRestore() async {
    if (await _store.restoreTried()) return false;
    if (await _store.purchaseToken() != null) return false;
    final c = (await _store.load(_clock())).claims;
    return c != null && c.enforce && c.tier != 'pro';
  }

  Future<void> markAutoRestored() => _store.markRestoreTried();

  /// [purchaseToken] is given right after a purchase or a restore; it is kept
  /// (only if it turned out to be Pro) so renewals can be checked later.
  Future<({SyncResult result, LicenseClaims? claims})> refresh({
    String? purchaseToken,
  }) async {
    final installId = await _store.installId();
    final token = purchaseToken ?? await _store.purchaseToken();
    final String license;
    try {
      license = await _api.refresh(
        installId: installId,
        appVersion: _appVersion,
        purchaseToken: token,
        deviceId: await _device.deviceId(),
      );
    } on LicenseUnavailable {
      return (result: SyncResult.unavailable, claims: null);
    }
    final claims = await verifyLicense(
      license,
      installId: installId,
      publicKey: _publicKey,
    );
    if (claims == null) return (result: SyncResult.invalid, claims: null);

    await _store.saveLicense(license);
    // The license is signed and carries the server's time: from now on the
    // phone's date can be checked against it.
    final info = await _device.clock();
    await _store.saveClockReference(
      ClockReference(
        serverMs: claims.issuedAt.millisecondsSinceEpoch,
        localMs: _clock().millisecondsSinceEpoch,
        monoMs: info?.elapsedMs,
        bootCount: info?.bootCount,
      ),
    );
    if (purchaseToken != null && claims.tier == 'pro') {
      await _store.savePurchaseToken(purchaseToken);
    }
    return (result: SyncResult.updated, claims: claims);
  }
}

final licenseSyncProvider = Provider((_) => LicenseSync());
