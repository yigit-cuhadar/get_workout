import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:get_workout/features/subscription/domain/subscription_usecases.dart';
import 'package:get_workout/features/subscription/presentation/premium_trial_cubit.dart';
import 'package:get_workout/features/subscription/subscription_module.dart';

void main() {
  PremiumTrialCubit cubitOn(List<Plan> plans) => PremiumTrialCubit(
    GetPremiumTrial(GetPaywallOffering(FakePurchasesRepository(plans: plans))),
  );

  test('knows no trial before it loads', () {
    expect(cubitOn(fakePlans).state, isNull);
  });

  blocTest<PremiumTrialCubit, OfferPeriod?>(
    'loads the store\'s trial',
    build: () => cubitOn(fakePlans),
    act: (cubit) => cubit.load(),
    expect: () => [const OfferPeriod(7, PeriodUnit.day)],
  );

  blocTest<PremiumTrialCubit, OfferPeriod?>(
    'stays without a trial when the store has none to offer',
    build: () => cubitOn(const []),
    act: (cubit) => cubit.load(),
    expect: () => <OfferPeriod?>[],
  );
}
