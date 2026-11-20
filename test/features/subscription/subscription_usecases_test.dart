import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_remote_config/forge_remote_config.dart';
import 'package:get_workout/features/subscription/domain/paywall_layout.dart';
import 'package:get_workout/features/subscription/domain/subscription_usecases.dart';
import 'package:get_workout/features/subscription/subscription_module.dart';
import 'package:mocktail/mocktail.dart';

class MockTelemetry extends Mock implements Telemetry {}

void main() {
  group('GetOfferingHard', () {
    test('is true only when the metadata says not dismissible', () async {
      final store = FakePurchasesRepository(plans: fakePlans);
      final hard = GetOfferingHard(GetPaywallOffering(store));

      expect((await hard()).valueOrNull, isFalse);
      store.metadata = const {'dismissible': false};
      expect((await hard()).valueOrNull, isTrue);
      store.metadata = const {'dismissible': 'false'};
      expect((await hard()).valueOrNull, isTrue);
    });

    test('passes a failure through', () async {
      final store = FakePurchasesRepository(plans: fakePlans)
        ..metadata = const {'dismissible': false}
        ..failure = const NetworkFailure();

      expect(
        (await GetOfferingHard(GetPaywallOffering(store))()).isOk,
        isFalse,
      );
    });
  });

  group('GetPaywallOffering', () {
    test('puts yearly before monthly, whatever the store\'s order', () async {
      final store = FakePurchasesRepository(plans: fakePlans);

      final offering = (await GetPaywallOffering(store)()).valueOrNull!;

      expect(fakePlans.first.period, PlanPeriod.monthly);
      expect(offering.plans.map((plan) => plan.period), [
        PlanPeriod.yearly,
        PlanPeriod.monthly,
      ]);
    });

    test("keeps the offering's metadata", () async {
      final store = FakePurchasesRepository(plans: fakePlans)
        ..metadata = const {'dismissible': false};

      final offering = (await GetPaywallOffering(store)()).valueOrNull!;

      expect(offering.metadata, {'dismissible': false});
    });

    test('passes a failure through', () async {
      final result = await GetPaywallOffering(
        FakePurchasesRepository(plans: const []),
      )();

      expect(result.isOk, isFalse);
    });
  });

  group('GetPremiumTrial', () {
    test('is the trial of the plan the paywall shows first', () async {
      const monthlyTrial = Plan(
        id: 'premium_monthly',
        period: PlanPeriod.monthly,
        price: r'$4.99',
        priceAmount: 4.99,
        currencyCode: 'USD',
        trial: OfferPeriod(3, PeriodUnit.day),
      );
      final store = FakePurchasesRepository(
        plans: [monthlyTrial, fakePlans.last],
      );

      final trial = await GetPremiumTrial(GetPaywallOffering(store))();

      expect(trial.valueOrNull, const OfferPeriod(7, PeriodUnit.day));
    });

    test('is null when no plan has one', () async {
      final store = FakePurchasesRepository(plans: [fakePlans.first]);

      final trial = await GetPremiumTrial(GetPaywallOffering(store))();

      expect(trial.isOk, isTrue);
      expect(trial.valueOrNull, isNull);
    });
  });

  group('GetPaywallLayout', () {
    late FakeRemoteConfigRepository config;

    setUp(
      () => config = FakeRemoteConfigRepository(
        SubscriptionModule.remoteConfigDefaults,
      ),
    );

    test('is A until the server sends a layout', () {
      expect(GetPaywallLayout(config)(), PaywallLayout.list);
    });

    test('maps the server\'s code; anything else is A', () {
      for (final (code, layout) in [
        ('a', PaywallLayout.list),
        ('b', PaywallLayout.cards),
        ('', PaywallLayout.list),
        ('c', PaywallLayout.single),
        ('d', PaywallLayout.list),
        ('B', PaywallLayout.list),
      ]) {
        config.values[paywallLayoutKey] = code;
        expect(GetPaywallLayout(config)(), layout, reason: code);
      }
    });

    test('a debug override wins until cleared', () {
      config.values[paywallLayoutKey] = 'b';
      final override = PaywallLayoutOverride()..layout = PaywallLayout.list;
      final getLayout = GetPaywallLayout(config, override);

      expect(getLayout(), PaywallLayout.list);
      override.layout = null;
      expect(getLayout(), PaywallLayout.cards);
    });
  });

  group('events', () {
    late MockTelemetry telemetry;

    setUpAll(() => registerFallbackValue(<String, Object>{}));

    setUp(() {
      telemetry = MockTelemetry();
      when(() => telemetry.logEvent(any(), any())).thenAnswer((_) async {});
    });

    test('a view carries the layout', () async {
      await LogPaywallView(telemetry)(PaywallLayout.cards);

      verify(() => telemetry.logEvent('paywall_view', {'layout': 'b'}))
          .called(1);
    });

    test('a purchase carries the plan and the layout', () async {
      await LogPaywallPurchase(telemetry)(
        plan: PlanPeriod.yearly,
        layout: PaywallLayout.list,
      );

      verify(
        () => telemetry.logEvent('paywall_purchase', {
          'plan': 'yearly',
          'layout': 'a',
        }),
      ).called(1);
    });
  });
}
