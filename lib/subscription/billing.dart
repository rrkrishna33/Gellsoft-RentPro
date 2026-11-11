import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'license_state.dart';
import 'license_sync.dart';
import 'license_config.dart';
import 'play_billing.dart';

/// One thing the user can buy, as Google Play describes it.
class PlanOption {
  const PlanOption({
    required this.id,
    required this.period,
    required this.price,
    this.handle,
  });

  /// Stable key for the UI, e.g. 'monthly'.
  final String id;

  /// monthly | yearly | other
  final String period;

  /// Already formatted by Google for the user's country, e.g. "₹99.00".
  final String price;

  /// The gateway's own object for this plan (opaque to the UI).
  final Object? handle;
}

enum PurchaseStage { purchased, pending, failed, cancelled }

/// A purchase event from Google Play.
class PurchaseUpdate {
  const PurchaseUpdate({
    required this.stage,
    required this.productId,
    this.token,
    this.handle,
  });
  final PurchaseStage stage;
  final String productId;

  /// Google's purchase token (what the license server checks).
  final String? token;
  final Object? handle;
}

/// The only part that touches Google Play; faked in tests.
abstract class BillingGateway {
  Stream<List<PurchaseUpdate>> get updates;

  /// null when Play billing cannot be used (sideloaded app, no Play Store).
  Future<List<PlanOption>?> loadPlans();

  Future<void> buy(PlanOption plan);
  Future<void> restore();

  /// Tells Google the purchase was received (otherwise Google refunds it
  /// after 3 days).
  Future<void> acknowledge(PurchaseUpdate update);
}

enum BillingNote {
  none,
  checking,
  pending,
  activated,
  notActivated,
  offline,
  cancelled,
  failed,
  restoredNothing,
}

class BillingState {
  const BillingState({
    this.plans,
    this.loading = false,
    this.busy = false,
    this.note = BillingNote.none,
  });

  /// null = not known yet or Play billing unavailable (see [loading]).
  final List<PlanOption>? plans;
  final bool loading;
  final bool busy;
  final BillingNote note;

  BillingState copyWith({
    List<PlanOption>? plans,
    bool? loading,
    bool? busy,
    BillingNote? note,
  }) => BillingState(
    plans: plans ?? this.plans,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    note: note ?? this.note,
  );
}

class BillingController extends Notifier<BillingState> {
  /// How long Restore waits for Google to send earlier purchases.
  static Duration restoreWait = const Duration(seconds: 4);

  StreamSubscription<List<PurchaseUpdate>>? _sub;
  bool _restoring = false;
  bool _gotRestored = false;

  /// True during the automatic restore at startup: no messages on the Pro
  /// screen, the purchase is still confirmed with the server.
  bool _quiet = false;

  /// The purchase being confirmed with the server right now, if any.
  Future<void>? _activation;

  @override
  BillingState build() {
    final gateway = ref.watch(billingGatewayProvider);
    // Listen from the start: Google re-delivers purchases that were paid for
    // but not yet confirmed (for example if the phone was offline).
    _sub = gateway.updates.listen(_onUpdates);
    ref.onDispose(() => _sub?.cancel());
    return const BillingState();
  }

  /// Forgets the last message ("Pro is now active", ...) so it is not shown
  /// again when the Pro screen is opened later.
  void clearNote() {
    if (state.note != BillingNote.none && !state.busy) {
      state = state.copyWith(note: BillingNote.none);
    }
  }

  Future<void> loadPlans() async {
    state = state.copyWith(loading: true);
    List<PlanOption>? plans;
    try {
      plans = await ref.read(billingGatewayProvider).loadPlans();
    } catch (_) {
      plans = null;
    }
    state = BillingState(plans: plans, note: state.note);
  }

  Future<void> buy(PlanOption plan) async {
    state = state.copyWith(busy: true, note: BillingNote.none);
    try {
      await ref.read(billingGatewayProvider).buy(plan);
    } catch (_) {
      state = state.copyWith(busy: false, note: BillingNote.failed);
    }
    // The result arrives on the update stream.
  }

  Future<void> restore() async {
    state = state.copyWith(busy: true, note: BillingNote.checking);
    _restoring = true;
    _gotRestored = false;
    try {
      await ref.read(billingGatewayProvider).restore();
      // Restored purchases arrive on the stream; give them a moment.
      await Future<void>.delayed(restoreWait);
    } catch (_) {
      state = state.copyWith(busy: false, note: BillingNote.failed);
    }
    if (_restoring) {
      _restoring = false;
      if (!_gotRestored && state.note == BillingNote.checking) {
        state = state.copyWith(busy: false, note: BillingNote.restoredNothing);
      }
    }
  }

  /// Restores an earlier purchase without touching what the Pro screen shows.
  /// Returns false if Google could not be asked (so it can be tried again).
  Future<bool> restoreQuietly() async {
    _quiet = true;
    try {
      await ref.read(billingGatewayProvider).restore();
      await Future<void>.delayed(restoreWait);
      // A purchase found by the restore is confirmed with the server; stay
      // quiet until that has finished, however long it takes.
      await _activation;
      return true;
    } catch (_) {
      return false;
    } finally {
      _quiet = false;
    }
  }

  void _say(bool busy, BillingNote note) {
    if (!_quiet) state = state.copyWith(busy: busy, note: note);
  }

  Future<void> _onUpdates(List<PurchaseUpdate> updates) async {
    for (final u in updates) {
      if (u.productId != proProductId) continue;
      switch (u.stage) {
        case PurchaseStage.pending:
          _say(false, BillingNote.pending);
        case PurchaseStage.cancelled:
          _say(false, BillingNote.cancelled);
        case PurchaseStage.failed:
          _say(false, BillingNote.failed);
        case PurchaseStage.purchased:
          _gotRestored = true;
          final activation = _activate(u);
          _activation = activation;
          await activation;
      }
    }
  }

  Future<void> _activate(PurchaseUpdate u) async {
    final token = u.token;
    if (token == null || token.isEmpty) {
      _say(false, BillingNote.failed);
      return;
    }
    _say(true, BillingNote.checking);
    final r = await ref.read(licenseSyncProvider).refresh(purchaseToken: token);
    if (r.result == SyncResult.updated) {
      // The server has checked it with Google, so Google can be told it is
      // received, whether or not it unlocked Pro on this phone.
      try {
        await ref.read(billingGatewayProvider).acknowledge(u);
      } catch (_) {
        // Google will deliver it again next time.
      }
      ref.invalidate(licenseProvider);
      _say(
        false,
        r.claims?.tier == 'pro'
            ? BillingNote.activated
            : BillingNote.notActivated,
      );
    } else {
      // Not confirmed yet: leave it unacknowledged so Google delivers it again
      // the next time the app starts with a connection.
      _say(
        false,
        r.result == SyncResult.unavailable
            ? BillingNote.offline
            : BillingNote.notActivated,
      );
    }
  }
}

final billingGatewayProvider = Provider<BillingGateway>(
  (ref) => GooglePlayBilling(),
);

final billingProvider = NotifierProvider<BillingController, BillingState>(
  BillingController.new,
);
