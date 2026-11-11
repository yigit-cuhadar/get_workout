import 'package:flutter_test/flutter_test.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:get_workout/features/subscription/presentation/premium_paywall_cubit.dart';
import 'package:get_workout/features/subscription/subscription_module.dart';

void main() {
  PremiumPaywallCubit build(List<Plan> plans) {
    final store = FakePurchasesRepository(
      plans: plans,
      purchaseDelay: Duration.zero,
    );
    return PremiumPaywallCubit(
      getOffering: GetOffering(store),
      purchasePlan: PurchasePlan(store),
      restorePurchases: RestorePurchases(store),
    );
  }

  test('selects the yearly plan wherever the offering lists it', () async {
    final cubit = build(fakePlans);
    await cubit.load();

    expect(fakePlans.first.period, PlanPeriod.monthly);
    expect(cubit.state.status, PaywallStatus.ready);
    expect(cubit.state.selected?.period, PlanPeriod.yearly);
    await cubit.close();
  });

  test('keeps the first plan when there is no yearly one', () async {
    final monthly = fakePlans.first;
    final cubit = build([monthly]);
    await cubit.load();

    expect(cubit.state.selected, monthly);
    await cubit.close();
  });

  test('a failed load selects nothing', () async {
    final cubit = build(const []);
    await cubit.load();

    expect(cubit.state.status, PaywallStatus.loadFailed);
    expect(cubit.state.selected, isNull);
    await cubit.close();
  });
}
