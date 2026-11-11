import 'dart:async';

import 'package:gellsoft_rentpro/subscription/billing.dart';

/// A pretend Google Play for tests.
class FakeBilling implements BillingGateway {
  FakeBilling({this.plans = const [], this.unavailable = false});

  List<PlanOption> plans;
  bool unavailable;

  final _stream = StreamController<List<PurchaseUpdate>>.broadcast();
  final bought = <String>[];
  final acknowledged = <PurchaseUpdate>[];
  int restoreCalls = 0;
  Object? buyError;
  Object? restoreError;

  /// What Google sends back after [restore] is asked.
  List<PurchaseUpdate> restoreResult = const [];

  void emit(List<PurchaseUpdate> u) => _stream.add(u);

  @override
  Stream<List<PurchaseUpdate>> get updates => _stream.stream;

  @override
  Future<List<PlanOption>?> loadPlans() async => unavailable ? null : plans;

  @override
  Future<void> buy(PlanOption plan) async {
    if (buyError != null) throw buyError!;
    bought.add(plan.id);
  }

  @override
  Future<void> restore() async {
    restoreCalls++;
    if (restoreError != null) throw restoreError!;
    if (restoreResult.isNotEmpty) emit(restoreResult);
  }

  @override
  Future<void> acknowledge(PurchaseUpdate update) async =>
      acknowledged.add(update);
}

const monthlyPlan = PlanOption(
  id: 'monthly',
  period: 'monthly',
  price: '₹99.00',
);
const yearlyPlan = PlanOption(id: 'yearly', period: 'yearly', price: '₹899.00');
