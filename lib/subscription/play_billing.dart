import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'billing.dart';
import 'license_config.dart';

/// Google Play Billing through the `in_app_purchase` plugin.
class GooglePlayBilling implements BillingGateway {
  GooglePlayBilling({InAppPurchase? iap})
    : _iap = iap ?? InAppPurchase.instance;
  final InAppPurchase _iap;

  @override
  Stream<List<PurchaseUpdate>> get updates => _iap.purchaseStream.map((list) {
    return [
      for (final p in list)
        PurchaseUpdate(
          stage: switch (p.status) {
            PurchaseStatus.purchased ||
            PurchaseStatus.restored => PurchaseStage.purchased,
            PurchaseStatus.pending => PurchaseStage.pending,
            PurchaseStatus.canceled => PurchaseStage.cancelled,
            PurchaseStatus.error => PurchaseStage.failed,
          },
          productId: p.productID,
          token: p.verificationData.serverVerificationData,
          handle: p,
        ),
    ];
  });

  @override
  Future<List<PlanOption>?> loadPlans() async {
    if (!await _iap.isAvailable()) return null;
    final res = await _iap.queryProductDetails({proProductId});
    if (res.error != null) return null;

    final plans = <PlanOption>[];
    for (final d in res.productDetails.whereType<GooglePlayProductDetails>()) {
      final index = d.subscriptionIndex;
      final offers = d.productDetails.subscriptionOfferDetails;
      if (index == null || offers == null) continue;
      final offer = offers[index];
      if (offer.offerId != null) continue; // promotions: only plain plans
      final phase = offer.pricingPhases.isEmpty
          ? null
          : offer.pricingPhases.last;
      final period = switch (phase?.billingPeriod) {
        'P1M' => 'monthly',
        'P1Y' => 'yearly',
        _ => 'other',
      };
      plans.add(
        PlanOption(
          id: offer.basePlanId,
          period: period,
          price: phase?.formattedPrice ?? d.price,
          handle: d,
        ),
      );
    }
    const order = {'monthly': 0, 'yearly': 1, 'other': 2};
    plans.sort((a, b) => order[a.period]!.compareTo(order[b.period]!));
    return plans;
  }

  @override
  Future<void> buy(PlanOption plan) async {
    final d = plan.handle as GooglePlayProductDetails;
    final started = await _iap.buyNonConsumable(
      purchaseParam: GooglePlayPurchaseParam(
        productDetails: d,
        offerToken: d.offerToken,
      ),
    );
    if (!started) throw StateError('purchase did not start');
  }

  @override
  Future<void> restore() => _iap.restorePurchases();

  @override
  Future<void> acknowledge(PurchaseUpdate update) async {
    final p = update.handle;
    if (p is PurchaseDetails && p.pendingCompletePurchase) {
      await _iap.completePurchase(p);
    }
  }
}
