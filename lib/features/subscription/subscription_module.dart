import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:get_it/get_it.dart';

import '../programs/domain/premium_status.dart' as programs;
import 'data/unavailable_purchases_repository.dart';
import 'presentation/fake_store_controls.dart';
import 'presentation/paywall_layout.dart';
import 'presentation/premium.dart';
import 'presentation/premium_paywall_cubit.dart';
import 'presentation/purchaser_session.dart';

/// The RevenueCat entitlement every Premium product is attached to.
const premiumEntitlementId = 'premium';

/// RevenueCat when this platform's public SDK key is passed with
/// `--dart-define=REVENUECAT_IOS_KEY=appl_…` / `REVENUECAT_ANDROID_KEY=goog_…`;
/// otherwise the fake in debug and profile builds, and none (purchases
/// unavailable) in release builds.
PurchasesBackend? purchasesBackend({
  required TargetPlatform platform,
  required bool release,
  String iosKey = const String.fromEnvironment('REVENUECAT_IOS_KEY'),
  String androidKey = const String.fromEnvironment('REVENUECAT_ANDROID_KEY'),
}) {
  final key = platform == TargetPlatform.android ? androidKey : iosKey;
  if (key.isNotEmpty) {
    return RevenueCatBackend(appleApiKey: iosKey, googleApiKey: androidKey);
  }
  return release ? null : const FakeBackend(fakePlans);
}

/// The fake store's plans, as SPEC's monetization decision describes them.
const fakePlans = [
  Plan(
    id: 'premium_monthly',
    period: PlanPeriod.monthly,
    price: r'$4.99',
    priceAmount: 4.99,
    currencyCode: 'USD',
  ),
  Plan(
    id: 'premium_yearly',
    period: PlanPeriod.yearly,
    price: r'$39.99',
    priceAmount: 39.99,
    currencyCode: 'USD',
    trial: OfferPeriod(7, PeriodUnit.day),
  ),
];

/// Registers purchases on [backend] (null: unavailable), the session that
/// keeps the store's user in step with the signed-in user, and the paywall.
/// Needs `AuthModule`.
class SubscriptionModule implements FeatureModule {
  const SubscriptionModule({required this.backend});

  final PurchasesBackend? backend;

  /// The fake store's controls, with the paywall layout's, in a debug build
  /// running on the fake.
  static Widget? debugControls(GetIt sl) =>
      kDebugMode && sl.isRegistered<FakePurchasesRepository>()
      ? FakeStoreControls(sl(), paywallLayout: sl())
      : null;

  /// The programs feature's premium status: the entitlement's.
  static programs.PremiumStatus premiumStatus(GetIt sl) =>
      EntitlementPremium(sl());

  /// The programs feature's premium action: the paywall.
  static void showPaywall(BuildContext context) =>
      unawaited(context.openPaywall());

  @override
  void register(GetIt sl) {
    final backend = this.backend;
    if (backend != null) {
      PurchasesModule(
        entitlementId: premiumEntitlementId,
        backend: backend,
      ).register(sl);
    } else {
      // The package has no "unavailable" backend: register it with an empty
      // fake, then swap the repository before anything has resolved it.
      const PurchasesModule(
        entitlementId: premiumEntitlementId,
        backend: FakeBackend([]),
      ).register(sl);
      sl
        ..unregister<PurchasesRepository>()
        ..unregister<FakePurchasesRepository>()
        ..registerLazySingleton<PurchasesRepository>(
          () => const UnavailablePurchasesRepository(),
        );
    }
    sl
      ..registerLazySingleton(
        () => PurchaserSession(watchAuthUser: sl(), entitlement: sl()),
        dispose: (session) => session.cancel(),
      )
      ..registerLazySingleton(PaywallLayoutChoice.new)
      ..registerFactory(
        () => PremiumPaywallCubit(
          getOffering: sl(),
          purchasePlan: sl(),
          restorePurchases: sl(),
        ),
      );
  }
}
