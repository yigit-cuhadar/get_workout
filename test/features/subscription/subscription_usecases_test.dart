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
        ('c', PaywallLayout.list),
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
