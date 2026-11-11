import 'package:forge_purchases/forge_purchases.dart';

/// The package's paywall with the yearly plan selected by default, when the
/// offering has one.
class PremiumPaywallCubit extends PaywallCubit {
  PremiumPaywallCubit({
    required super.getOffering,
    required super.purchasePlan,
    required super.restorePurchases,
  });

  @override
  Future<void> load() async {
    await super.load();
    if (isClosed) return;
    for (final plan in state.plans) {
      if (plan.period == PlanPeriod.yearly) return select(plan);
    }
  }
}
