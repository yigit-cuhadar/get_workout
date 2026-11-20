import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:get_workout/app/router.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/features/subscription/domain/paywall_moment.dart';
import 'package:get_workout/features/subscription/presentation/premium.dart';
import 'package:get_workout/features/subscription/subscription_module.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

void main() {
  late FakePurchasesRepository store;
  late MockSettingsCubit settings;
  String? paywallMoment;
  late EntitlementCubit entitlement;
  late GoRouter router;
  late ValueNotifier<int> refresh;
  bool? allowed;
  var redirectPaywall = false;

  setUpAll(() => registerFallbackValue(Tip.effort));

  setUp(() {
    paywallMoment = null;
    settings = MockSettingsCubit();
    when(
      () => settings.state,
    ).thenReturn(SettingsState(UserSettings.defaultsFor(null), loaded: true));
    when(() => settings.tipSeen(any())).thenAnswer((_) async {});
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
            body: Column(
              children: [
                TextButton(
                  onPressed: () async =>
                      allowed = await context.requirePremium(),
                  child: const Text('Open'),
                ),
                TextButton(
                  onPressed: () =>
                      context.paywallMoment(PaywallMoment.onboarding),
                  child: const Text('Moment'),
                ),
              ],
            ),
          ),
        ),
        GoRoute(
          path: Routes.paywall,
          redirect: (_, _) => redirectPaywall ? '/elsewhere' : null,
          builder: (context, state) => Scaffold(
            key: ValueKey(
              paywallMoment = state.uri.queryParameters['moment'] ?? 'none',
            ),
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
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: entitlement),
          BlocProvider<SettingsCubit>.value(value: settings),
        ],
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

  group('a paywall moment', () {
    testWidgets('opens once for a free user and is marked shown', (
      tester,
    ) async {
      await free(tester);
      await tap(tester, 'Moment');

      expect(find.text('Buy'), findsOneWidget);
      expect(paywallMoment, 'onboarding');
      verify(() => settings.tipSeen(Tip.onboardingPaywall)).called(1);
    });

    testWidgets('does not open once shown', (tester) async {
      when(() => settings.state).thenReturn(
        SettingsState(
          UserSettings.defaultsFor(null)
              .copyWith(seenTips: {Tip.onboardingPaywall}),
          loaded: true,
        ),
      );
      await free(tester);
      await tap(tester, 'Moment');

      expect(find.text('Buy'), findsNothing);
      verifyNever(() => settings.tipSeen(any()));
    });

    testWidgets('does not open while Premium is unknown or owned', (
      tester,
    ) async {
      await pump(tester);
      await tap(tester, 'Moment');
      expect(find.text('Buy'), findsNothing);

      await tester.runAsync(() async {
        await entitlement.identify('u1');
        await store.purchase(fakePlans.first);
      });
      await tester.pumpAndSettle();
      await tap(tester, 'Moment');
      expect(find.text('Buy'), findsNothing);
      verifyNever(() => settings.tipSeen(any()));
    });
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
