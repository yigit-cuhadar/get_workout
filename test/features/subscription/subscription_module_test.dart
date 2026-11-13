import 'package:flutter_test/flutter_test.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:get_it/get_it.dart';
import 'package:get_workout/features/subscription/data/unavailable_purchases_repository.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_remote_config/forge_remote_config.dart';
import 'package:get_workout/features/subscription/domain/paywall_layout.dart';
import 'package:get_workout/features/subscription/presentation/premium_paywall_cubit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:get_workout/features/subscription/subscription_module.dart';

class MockTelemetry extends Mock implements Telemetry {}

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

  test('the paywall reads its layout from Remote Config; a debug build '
      'overrides it', () async {
    const RemoteConfigModule(
      defaults: SubscriptionModule.remoteConfigDefaults,
      backend: FakeRemoteConfigBackend(),
    ).register(sl);
    sl.registerSingleton<Telemetry>(MockTelemetry());
    const SubscriptionModule(backend: FakeBackend(fakePlans)).register(sl);

    Future<PaywallLayout> layout() async {
      final cubit = sl<PremiumPaywallCubit>();
      await cubit.close();
      return cubit.layout;
    }

    expect(await layout(), PaywallLayout.list);
    sl<FakeRemoteConfigRepository>().values[paywallLayoutKey] = 'b';
    expect(await layout(), PaywallLayout.cards);
    // Tests run as a debug build.
    sl<PaywallLayoutOverride>().layout = PaywallLayout.list;
    expect(await layout(), PaywallLayout.list);
  });
}
