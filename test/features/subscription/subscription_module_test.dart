import 'package:flutter_test/flutter_test.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:get_it/get_it.dart';
import 'package:get_workout/features/subscription/data/unavailable_purchases_repository.dart';
import 'package:get_workout/features/subscription/presentation/paywall_layout.dart';
import 'package:get_workout/features/subscription/subscription_module.dart';

void main() {
  late GetIt sl;

  setUp(() => sl = GetIt.asNewInstance());

  tearDown(() => sl.reset());

  test('without a backend the store is unavailable, never the fake', () async {
    const SubscriptionModule(backend: null).register(sl);

    expect(sl<PurchasesRepository>(), isA<UnavailablePurchasesRepository>());
    expect(sl.isRegistered<FakePurchasesRepository>(), isFalse);
    expect(SubscriptionModule.debugControls(sl), isNull);

    final entitlement = sl<EntitlementCubit>();
    expect((await entitlement.identify('u1')).isOk, isTrue);
    expect(entitlement.state, const EntitlementInactive());
    await entitlement.close();
  });

  test('the fake backend registers the fake and its debug controls', () {
    const SubscriptionModule(backend: FakeBackend(fakePlans)).register(sl);

    expect(sl<PurchasesRepository>(), isA<FakePurchasesRepository>());
    expect(SubscriptionModule.debugControls(sl), isNotNull);
  });

  test('the paywall shows layout A until users are assigned', () {
    const SubscriptionModule(backend: FakeBackend(fakePlans)).register(sl);

    expect(sl<PaywallLayoutChoice>().layout, PaywallLayout.list);
  });
}
