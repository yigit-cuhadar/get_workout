import 'package:flutter_test/flutter_test.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/router.dart';
import 'package:get_workout/features/account/presentation/account_page.dart';
import 'package:get_workout/features/subscription/presentation/paywall_page.dart';

import 'flow_harness.dart';

void main() {
  late FlowApp app;

  setUpAll(registerFlowFallbacks);
  setUp(() => app = FlowApp());
  tearDown(() => app.dispose());

  Future<void> tapText(WidgetTester tester, String text) =>
      app.tapText(tester, text);

  /// A free guest on Profile.
  Future<void> openProfile(WidgetTester tester) async {
    await app.startAs(tester, guest);
    await app.entitlement.identify(guest.id);
    await app.tapTab(tester, 'Profile');
  }

  Future<void> openPaywall(WidgetTester tester) async {
    await openProfile(tester);
    await tapText(tester, 'Get Premium');
    expect(find.byType(PaywallPage), findsOneWidget);
  }

  ForgeButton button(WidgetTester tester, String label) =>
      tester.widget<ForgeButton>(find.widgetWithText(ForgeButton, label));

  testWidgets('Get Premium lists Yearly first and selected', (tester) async {
    await openPaywall(tester);

    final yearly = tester.getTopLeft(find.text(r'$39.99 / year'));
    final monthly = tester.getTopLeft(find.text(r'$7.99 / month'));
    expect(yearly.dy, lessThan(monthly.dy));
    // The purchase button is the yearly plan's trial.
    expect(find.text('Start 7-day free trial'), findsOneWidget);
    expect(button(tester, 'Start 7-day free trial').onPressed, isNotNull);
  });

  testWidgets("a purchase from Account's Premium row closes the paywall and "
      'the row shows the trial', (tester) async {
    await openProfile(tester);
    app.router.go(Routes.account);
    await tester.pumpAndSettle();
    expect(find.byType(AccountPage), findsOneWidget);
    expect(find.text('You are on Free'), findsOneWidget);

    await tapText(tester, 'GetWorkout Premium');
    expect(find.byType(PaywallPage), findsOneWidget);
    await tapText(tester, 'Start 7-day free trial');

    expect(find.byType(PaywallPage), findsNothing);
    expect(find.byType(AccountPage), findsOneWidget);
    expect(find.text('Welcome to Premium!'), findsOneWidget);
    expect(find.textContaining('Free trial until'), findsOneWidget);
    expect(find.text('You are on Free'), findsNothing);
  });

  testWidgets('a restore with nothing to restore keeps the paywall open', (
    tester,
  ) async {
    await openPaywall(tester);

    await tapText(tester, 'Restore purchases');

    expect(find.text('Nothing to restore.'), findsOneWidget);
    expect(find.byType(PaywallPage), findsOneWidget);
    expect(button(tester, 'Start 7-day free trial').onPressed, isNotNull);
    expect(app.entitlement.isActive, isFalse);
  });

  testWidgets('Got it closes a pending purchase; Premium waits for it', (
    tester,
  ) async {
    await openPaywall(tester);
    app.store.failure = const PurchaseFailure(PurchaseFailureReason.pending);

    await tapText(tester, 'Start 7-day free trial');
    expect(find.text('Waiting for approval'), findsOneWidget);

    await tapText(tester, 'Got it');

    expect(find.byType(PaywallPage), findsNothing);
    expect(find.text('Get Premium'), findsOneWidget);
    expect(app.entitlement.isActive, isFalse);
  });

  testWidgets('an unavailable store disables Subscribe until Retry loads the '
      'plans', (tester) async {
    await openProfile(tester);
    app.store.failure = const PurchaseFailure(
      PurchaseFailureReason.storeUnavailable,
    );
    await tapText(tester, 'Get Premium');

    expect(
      find.text('Purchases are not available yet. Try again later.'),
      findsOneWidget,
    );
    expect(button(tester, 'Subscribe').onPressed, isNull);

    app.store.failure = null;
    await tapText(tester, 'Retry');

    expect(
      find.text('Purchases are not available yet. Try again later.'),
      findsNothing,
    );
    expect(button(tester, 'Start 7-day free trial').onPressed, isNotNull);
  });
}
