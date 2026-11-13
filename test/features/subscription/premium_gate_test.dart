import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:get_workout/app/router.dart';
import 'package:get_workout/features/subscription/presentation/premium.dart';
import 'package:get_workout/features/subscription/subscription_module.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

void main() {
  late FakePurchasesRepository store;
  late EntitlementCubit entitlement;
  late GoRouter router;
  late ValueNotifier<int> refresh;
  bool? allowed;
  var redirectPaywall = false;

  setUp(() {
    allowed = null;
    redirectPaywall = false;
    store = FakePurchasesRepository(
      plans: fakePlans,
      purchaseDelay: Duration.zero,
    );
    entitlement = EntitlementCubit(
      configure: ConfigurePurchases(store),
      watchEntitlement: WatchEntitlement(store),
      identify: IdentifyPurchaser(store),
      reset: ResetPurchaser(store),
      refresh: RefreshEntitlement(store),
      getManagementUrl: GetManagementUrl(store),
      // Past every expiry, so no expiry timer outlives a test.
      clock: () => DateTime(9999),
    );
  });

  tearDown(() => entitlement.close());

  Future<void> pump(WidgetTester tester) async {
    refresh = ValueNotifier(0);
    addTearDown(refresh.dispose);
    router = GoRouter(
      // Like the app's: pushes are parsed asynchronously.
      onEnter: (_, _, _, _) => const Allow(),
      refreshListenable: refresh,
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () async => allowed = await context.requirePremium(),
              child: const Text('Open'),
            ),
          ),
        ),
        GoRoute(
          path: Routes.paywall,
          redirect: (_, _) => redirectPaywall ? '/elsewhere' : null,
          builder: (context, _) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () async {
                    await store.purchase(fakePlans.first);
                    if (context.mounted) context.pop(true);
                  },
                  child: const Text('Buy'),
                ),
                // The result before the entitlement has caught up.
                TextButton(
                  onPressed: () => context.pop(true),
                  child: const Text('Unlocked'),
                ),
              ],
            ),
          ),
        ),
        GoRoute(path: '/elsewhere', builder: (_, _) => const Text('Elsewhere')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      BlocProvider.value(
        value: entitlement,
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    // The first location is parsed asynchronously too.
    await tester.pump();
  }

  int paywalls() =>
      openLocations(router.routerDelegate.currentConfiguration)
          .where((location) => location == Routes.paywall)
          .length;

  Future<void> free(WidgetTester tester) async {
    await pump(tester);
    await tester.runAsync(() => entitlement.identify('u1'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  test('the programs\' premium status follows the entitlement', () async {
    final seen = <bool?>[];
    final subscription = EntitlementPremium(entitlement)
        .watch()
        .listen(seen.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    expect(seen, [null]);

    await entitlement.identify('u1');
    await pumpEventQueue();
    expect(seen, [null, false]);

    await store.purchase(fakePlans.first);
    await pumpEventQueue();
    expect(seen, [null, false, true]);
  });

  testWidgets('unknown: no paywall, the user is asked to wait', (tester) async {
    await pump(tester);
    await tap(tester, 'Open');

    expect(find.text('Buy'), findsNothing);
    expect(find.textContaining('Checking your subscription'), findsOneWidget);
    expect(allowed, isFalse);
  });

  testWidgets('premium: allowed without a paywall', (tester) async {
    await pump(tester);
    await tester.runAsync(() => entitlement.identify('u1'));
    await tester.runAsync(() => store.purchase(fakePlans.first));
    await tester.pumpAndSettle();
    expect(entitlement.isActive, isTrue);

    await tap(tester, 'Open');

    expect(find.text('Buy'), findsNothing);
    expect(allowed, isTrue);
  });

  testWidgets('free: the paywall, then allowed once bought', (tester) async {
    await pump(tester);
    await tester.runAsync(() => entitlement.identify('u1'));
    await tester.pumpAndSettle();

    await tap(tester, 'Open');
    expect(find.text('Buy'), findsOneWidget);
    await tap(tester, 'Buy');

    expect(allowed, isTrue);
  });

  testWidgets('free: closing the paywall is not allowed', (tester) async {
    await pump(tester);
    await tester.runAsync(() => entitlement.identify('u1'));
    await tester.pumpAndSettle();

    await tap(tester, 'Open');
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect(allowed, isFalse);
  });

  testWidgets('a second call while the paywall is open opens no other', (
    tester,
  ) async {
    await pump(tester);
    await tester.runAsync(() => entitlement.identify('u1'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(paywalls(), 1);
    expect(allowed, isFalse);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect(find.text('Buy'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('the result it pops with is returned', (tester) async {
    await pump(tester);
    await tester.runAsync(() => entitlement.identify('u1'));
    await tester.pumpAndSettle();

    await tap(tester, 'Open');
    await tap(tester, 'Unlocked');

    expect(entitlement.isActive, isFalse);
    expect(allowed, isTrue);
  });

  testWidgets('removed by a go, it is not allowed and opens again', (
    tester,
  ) async {
    await pump(tester);
    await tester.runAsync(() => entitlement.identify('u1'));
    await tester.pumpAndSettle();

    await tap(tester, 'Open');
    router.go('/elsewhere');
    await tester.pumpAndSettle();
    expect(find.text('Buy'), findsNothing);
    expect(allowed, isFalse);

    router.go('/');
    await tester.pumpAndSettle();
    allowed = null;
    await tap(tester, 'Open');

    expect(find.text('Buy'), findsOneWidget);
    expect(allowed, isNull);
  });

  testWidgets('a go before the push is parsed: not allowed, opens again', (
    tester,
  ) async {
    await free(tester);

    final opened = tester.element(find.text('Open')).openPaywall();
    router.go('/elsewhere');
    await tester.pumpAndSettle();
    expect(paywalls(), 0);
    expect(await opened, isFalse);

    router.go('/');
    await tester.pumpAndSettle();
    await tap(tester, 'Open');
    expect(paywalls(), 1);
  });

  testWidgets('a redirected push removed by a go: not allowed, opens again', (
    tester,
  ) async {
    await free(tester);
    redirectPaywall = true;

    await tap(tester, 'Open');
    expect(find.text('Elsewhere'), findsOneWidget);
    expect(allowed, isNull);
    router.go('/');
    await tester.pumpAndSettle();
    expect(allowed, isFalse);

    redirectPaywall = false;
    allowed = null;
    await tap(tester, 'Open');
    expect(paywalls(), 1);
    expect(allowed, isNull);
  });

  testWidgets('after a refresh, its result is still returned', (tester) async {
    await free(tester);

    await tap(tester, 'Open');
    refresh.value++;
    await tester.pumpAndSettle();
    expect(paywalls(), 1);
    await tap(tester, 'Unlocked');

    expect(allowed, isTrue);
  });
}
