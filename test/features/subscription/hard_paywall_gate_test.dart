import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:get_workout/app/router.dart';
import 'package:get_workout/features/subscription/domain/paywall_moment.dart';
import 'package:get_workout/features/subscription/domain/subscription_usecases.dart';
import 'package:get_workout/features/subscription/presentation/hard_paywall_gate.dart';
import 'package:get_workout/features/subscription/presentation/premium.dart';
import 'package:get_workout/features/subscription/subscription_module.dart';
import 'package:go_router/go_router.dart';

void main() {
  late FakePurchasesRepository store;
  late EntitlementCubit entitlement;
  late GoRouter router;
  late HardPaywallGate gate;
  late int offeringLoads;
  var blocked = false;

  setUp(() {
    blocked = false;
    offeringLoads = 0;
    store = FakePurchasesRepository(
      plans: fakePlans,
      purchaseDelay: Duration.zero,
    )..metadata = const {dismissibleKey: false};
    entitlement = EntitlementCubit(
      configure: ConfigurePurchases(store),
      watchEntitlement: WatchEntitlement(store),
      identify: IdentifyPurchaser(store),
      reset: ResetPurchaser(store),
      refresh: RefreshEntitlement(store),
      getManagementUrl: GetManagementUrl(store),
      presentCustomerCenter: PresentCustomerCenter(store),
      // Past every expiry, so no expiry timer outlives a test.
      clock: () => DateTime(9999),
    );
  });

  tearDown(() => entitlement.close());

  /// The app at [location], with the gate on it.
  Future<void> pump(WidgetTester tester, {String location = '/'}) async {
    router = GoRouter(
      initialLocation: location,
      // Like the app's: pushes are parsed asynchronously.
      onEnter: (_, _, _, _) => const Allow(),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.openPaywall(),
              child: const Text('Get Premium'),
            ),
          ),
        ),
        GoRoute(
          path: Routes.onboarding,
          builder: (_, _) => const Text('Onboarding'),
        ),
        GoRoute(
          path: Routes.verifyEmail,
          builder: (_, _) => const Text('Verify'),
        ),
        GoRoute(
          path: Routes.paywall,
          // Closes on Premium, as the real one does.
          builder: (context, state) =>
              BlocListener<EntitlementCubit, EntitlementState>(
                listenWhen: (_, current) => current is EntitlementActive,
                listener: (context, _) => context.pop(true),
                child: Scaffold(
                  body: Column(
                    children: [
                      Text('Paywall ${state.uri.queryParameters['moment']}'),
                      TextButton(
                        onPressed: () => context.pop(false),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ),
        ),
        GoRoute(path: '/elsewhere', builder: (_, _) => const Text('Else')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      BlocProvider.value(
        value: entitlement,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    gate = HardPaywallGate(
      router: router,
      entitlement: entitlement,
      offeringHard: GetOfferingHard(
        _CountingOffering(store, () => offeringLoads++),
      ),
      blocked: () => blocked,
    );
    addTearDown(gate.cancel);
    await tester.pumpAndSettle();
  }

  Future<void> identify(WidgetTester tester) async {
    await tester.runAsync(() => entitlement.identify('u1'));
    await tester.pumpAndSettle();
  }

  int paywalls() =>
      openLocations(router.routerDelegate.currentConfiguration)
          .where((location) => location == Routes.paywall)
          .length;

  final hardPaywall = find.text('Paywall ${PaywallMoment.appOpen.name}');

  Future<void> buy(WidgetTester tester) async {
    // The store's events run where it was identified: outside fake time.
    await tester.runAsync(() async {
      await store.purchase(fakePlans.first);
      await pumpEventQueue();
    });
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets('a cold start of a free user blocks while the offering is '
      'hard', (tester) async {
    await pump(tester);
    await identify(tester);

    expect(hardPaywall, findsOneWidget);
    expect(paywalls(), 1);
  });

  testWidgets('Premium passes, also once bought on the paywall', (
    tester,
  ) async {
    await pump(tester);
    await identify(tester);
    await buy(tester);
    expect(paywalls(), 0);
    gate.appOpened();
    await tester.pumpAndSettle();
    expect(paywalls(), 0);
  });

  testWidgets('a subscriber passes on launch', (tester) async {
    blocked = true;
    await pump(tester);
    await identify(tester);
    await buy(tester);
    blocked = false;
    gate.appOpened();
    await tester.pumpAndSettle();

    expect(entitlement.isActive, isTrue);
    expect(paywalls(), 0);
  });

  testWidgets('an unknown entitlement lets the user in until it is known', (
    tester,
  ) async {
    await pump(tester);

    expect(paywalls(), 0);
    expect(offeringLoads, 0);
    await identify(tester);
    expect(hardPaywall, findsOneWidget);
  });

  testWidgets('a soft offering passes', (tester) async {
    store.metadata = const {};
    await pump(tester);
    await identify(tester);

    expect(paywalls(), 0);
    expect(offeringLoads, 1);
    // Checked once per open, not on every navigation.
    router.go('/elsewhere');
    await tester.pumpAndSettle();
    expect(offeringLoads, 1);
  });

  testWidgets('an offering that cannot be loaded lets the user in until the '
      'next open', (tester) async {
    store.failure = const NetworkFailure();
    await pump(tester);
    await identify(tester);
    expect(paywalls(), 0);

    store.failure = null;
    gate.appOpened();
    await tester.pumpAndSettle();
    expect(hardPaywall, findsOneWidget);
  });

  testWidgets('coming back to the app blocks once the offering is hard', (
    tester,
  ) async {
    store.metadata = const {};
    await pump(tester);
    await identify(tester);
    expect(paywalls(), 0);

    store.metadata = const {dismissibleKey: false};
    gate.appOpened();
    await tester.pumpAndSettle();
    expect(hardPaywall, findsOneWidget);
  });

  testWidgets('coming back with the paywall open opens no second one', (
    tester,
  ) async {
    await pump(tester);
    await identify(tester);

    gate.appOpened();
    await tester.pumpAndSettle();
    expect(paywalls(), 1);
  });

  testWidgets('it waits for onboarding and email verification to be left', (
    tester,
  ) async {
    await pump(tester, location: Routes.onboarding);
    await identify(tester);
    expect(paywalls(), 0);

    router.go(Routes.verifyEmail);
    await tester.pumpAndSettle();
    expect(paywalls(), 0);

    router.go('/');
    await tester.pumpAndSettle();
    expect(hardPaywall, findsOneWidget);
  });

  testWidgets('it waits while blocked (the app gate) and shows when checked '
      'after', (tester) async {
    blocked = true;
    await pump(tester);
    await identify(tester);
    expect(paywalls(), 0);

    blocked = false;
    gate.check();
    await tester.pumpAndSettle();
    expect(hardPaywall, findsOneWidget);
  });

  testWidgets('another paywall open is not stacked on: the hard one follows '
      'once it closes', (tester) async {
    blocked = true;
    await pump(tester);
    await identify(tester);
    await tap(tester, 'Get Premium');
    blocked = false;
    gate.appOpened();
    await tester.pumpAndSettle();
    expect(paywalls(), 1);
    expect(hardPaywall, findsNothing);

    await tap(tester, 'Close');
    expect(hardPaywall, findsOneWidget);
    expect(paywalls(), 1);
  });

  testWidgets('taken away without Premium, it shows again', (tester) async {
    await pump(tester);
    await identify(tester);

    router.go('/elsewhere');
    await tester.pumpAndSettle();
    expect(hardPaywall, findsOneWidget);
  });

  testWidgets('Premium running out blocks again', (tester) async {
    await pump(tester);
    await identify(tester);
    await buy(tester);
    expect(paywalls(), 0);

    await tester.runAsync(() async {
      store.lapse();
      await pumpEventQueue();
    });
    await tester.pumpAndSettle();
    expect(hardPaywall, findsOneWidget);
  });
}

/// Counts the offering loads.
class _CountingOffering extends GetPaywallOffering {
  _CountingOffering(super.repository, this._loaded);

  final void Function() _loaded;

  @override
  Future<Result<Offering>> call([NoParams params = const NoParams()]) {
    _loaded();
    return super.call(params);
  }
}
