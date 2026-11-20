import 'package:flutter_test/flutter_test.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:get_workout/features/subscription/domain/paywall_moment.dart';
import 'package:get_workout/features/subscription/domain/subscription_usecases.dart';
import 'package:get_workout/features/subscription/presentation/hard_paywall_gate.dart';
import 'package:get_workout/features/subscription/presentation/paywall_page.dart';
import 'package:get_workout/features/subscription/subscription_module.dart';

import 'flow_harness.dart';

void main() {
  late FlowApp app;
  late HardPaywallGate gate;

  setUpAll(registerFlowFallbacks);
  setUp(() => app = FlowApp());
  tearDown(() async {
    await gate.cancel();
    await app.dispose();
  });

  /// Launched as a guest past onboarding, with the gate as the app sets it
  /// up; [hard] is the current offering's.
  Future<void> launch(WidgetTester tester, {bool hard = true}) async {
    await app.startAs(tester, guest);
    app.store.metadata = {dismissibleKey: !hard};
    gate = HardPaywallGate(
      router: app.router,
      entitlement: app.entitlement,
      offeringHard: GetOfferingHard(GetPaywallOffering(app.store)),
      blocked: () => app.deletionUnderway.value,
    );
    await tester.pumpAndSettle();
  }

  Future<void> identify(WidgetTester tester) async {
    await app.entitlement.identify(guest.id);
    await tester.pumpAndSettle();
  }

  Future<void> comeBack(WidgetTester tester) async {
    gate.appOpened();
    await tester.pumpAndSettle();
  }

  PaywallPage? paywall(WidgetTester tester) =>
      tester.widgetList<PaywallPage>(find.byType(PaywallPage)).singleOrNull;

  testWidgets('a cold start of a free user opens the hard paywall: no close, '
      'no back, restore offered', (tester) async {
    await launch(tester);
    await identify(tester);

    expect(paywall(tester)?.moment, PaywallMoment.appOpen);
    expect(find.bySemanticsLabel('Close'), findsNothing);
    expect(find.text('Restore purchases'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(paywall(tester), isNotNull);

    await app.tapText(tester, 'Start 7-day free trial');
    expect(paywall(tester), isNull);
    expect(app.entitlement.isActive, isTrue);

    await comeBack(tester);
    expect(paywall(tester), isNull);
  });

  testWidgets('coming back to the app opens it again', (tester) async {
    await launch(tester, hard: false);
    await identify(tester);
    expect(paywall(tester), isNull);

    app.store.metadata = const {dismissibleKey: false};
    await comeBack(tester);
    expect(paywall(tester)?.moment, PaywallMoment.appOpen);
  });

  testWidgets('a subscriber passes', (tester) async {
    app.deletionUnderway.value = true;
    await launch(tester);
    await identify(tester);
    await tester.runAsync(() => app.store.purchase(fakePlans.first));
    await tester.pumpAndSettle();
    app.deletionUnderway.value = false;
    await comeBack(tester);

    expect(app.entitlement.isActive, isTrue);
    expect(paywall(tester), isNull);
  });

  testWidgets('an unknown entitlement passes', (tester) async {
    await launch(tester);

    expect(app.entitlement.state, isA<EntitlementUnknown>());
    expect(paywall(tester), isNull);
  });

  testWidgets('a soft offering passes', (tester) async {
    await launch(tester, hard: false);
    await identify(tester);

    expect(paywall(tester), isNull);
  });

  testWidgets('onboarding is not blocked', (tester) async {
    app.storedProfile = const UserProfile();
    await launch(tester);
    await identify(tester);

    expect(app.path(), '/onboarding');
    expect(paywall(tester), isNull);
  });

  testWidgets('a pending purchase keeps waiting for approval, also on coming '
      'back', (tester) async {
    await launch(tester);
    await identify(tester);
    app.store.failure = const PurchaseFailure(PurchaseFailureReason.pending);

    await app.tapText(tester, 'Start 7-day free trial');
    expect(find.textContaining('waiting for approval'), findsOneWidget);
    expect(find.text('Got it'), findsNothing);

    await comeBack(tester);
    expect(find.byType(PaywallPage), findsOneWidget);
    expect(find.textContaining('waiting for approval'), findsOneWidget);

    app.store
      ..failure = null
      ..approvePending();
    await tester.pumpAndSettle();
    expect(paywall(tester), isNull);
  });
}
