import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_remote_config/forge_remote_config.dart';
import 'package:get_workout/features/subscription/domain/paywall_layout.dart';
import 'package:get_workout/features/subscription/domain/subscription_usecases.dart';
import 'package:get_workout/features/subscription/presentation/premium_paywall_cubit.dart';
import 'package:get_workout/features/subscription/subscription_module.dart';
import 'package:mocktail/mocktail.dart';

class MockTelemetry extends Mock implements Telemetry {}

void main() {
  late FakePurchasesRepository store;
  late FakeRemoteConfigRepository config;
  late MockTelemetry telemetry;
  late bool premium;

  setUpAll(() => registerFallbackValue(<String, Object>{}));

  setUp(() {
    config = FakeRemoteConfigRepository(
      SubscriptionModule.remoteConfigDefaults,
    );
    telemetry = MockTelemetry();
    premium = false;
    when(() => telemetry.logEvent(any(), any())).thenAnswer((_) async {});
  });

  PremiumPaywallCubit build(List<Plan> plans) {
    store = FakePurchasesRepository(plans: plans, purchaseDelay: Duration.zero);
    return PremiumPaywallCubit(
      getOffering: GetOffering(store),
      purchasePlan: PurchasePlan(store),
      restorePurchases: RestorePurchases(store),
      getLayout: GetPaywallLayout(config),
      logView: LogPaywallView(telemetry),
      logPurchase: LogPaywallPurchase(telemetry),
      isPremium: () => premium,
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

  test('a failed load selects nothing and logs no view', () async {
    final cubit = build(const []);
    await cubit.load();

    expect(cubit.state.status, PaywallStatus.loadFailed);
    expect(cubit.state.selected, isNull);
    verifyNever(() => telemetry.logEvent(any(), any()));
    await cubit.close();
  });

  test('reads the layout once, when created', () async {
    config.values[paywallLayoutKey] = 'b';
    final cubit = build(fakePlans);
    config.values[paywallLayoutKey] = 'a';

    expect(cubit.layout, PaywallLayout.cards);
    await cubit.close();
  });

  test('logs one view with the layout, however often it loads', () async {
    config.values[paywallLayoutKey] = 'b';
    final cubit = build(fakePlans);
    await cubit.load();
    await cubit.load();

    verify(() => telemetry.logEvent('paywall_view', {'layout': 'b'})).called(1);
    await cubit.close();
  });

  test('logs no view for a subscriber', () async {
    premium = true;
    final cubit = build(fakePlans);
    await cubit.load();

    expect(cubit.state.status, PaywallStatus.ready);
    verifyNever(() => telemetry.logEvent('paywall_view', any()));
    await cubit.close();
  });

  test('logs a purchase with its plan and the layout', () async {
    final cubit = build(fakePlans);
    await store.configure();
    await cubit.load();
    await cubit.purchase();

    expect(cubit.state.outcome, PaywallOutcome.purchased);
    verify(
      () => telemetry.logEvent('paywall_purchase', {
        'plan': 'yearly',
        'layout': 'a',
      }),
    ).called(1);
    await cubit.close();
  });

  test('logs no purchase when it does not go through', () async {
    final cubit = build(fakePlans);
    await store.configure();
    await cubit.load();
    store.failure = const PurchaseFailure(PurchaseFailureReason.cancelled);
    await cubit.purchase();
    store.failure = const PurchaseFailure(PurchaseFailureReason.pending);
    await cubit.purchase();

    verifyNever(() => telemetry.logEvent('paywall_purchase', any()));
    await cubit.close();
  });
}
