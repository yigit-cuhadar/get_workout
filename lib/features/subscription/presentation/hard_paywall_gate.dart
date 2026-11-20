import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../domain/paywall_moment.dart';
import '../domain/subscription_usecases.dart';
import 'premium.dart';

/// Keeps a free user out of the app while the current offering is hard
/// ([GetOfferingHard]): the paywall at [PaywallMoment.appOpen] shows on
/// every app open (each launch, and [appOpened]), whenever the entitlement
/// turns inactive (Premium lapsed, another user) and whenever it was taken
/// away without Premium, until the user has Premium.
///
/// It waits until every open page is past the start ([isPastStart]: not
/// over onboarding, its end or the email verification page), the app is
/// not [blocked] and no other paywall is open, then [check]s. Unknown never
/// blocks: an unknown entitlement waits for its answer, and an offering
/// that cannot be loaded lets the user in until the next open.
class HardPaywallGate {
  HardPaywallGate({
    required this._router,
    required this._entitlement,
    required this._offeringHard,
    required this._blocked,
  }) {
    _router.routerDelegate.addListener(_routed);
    _entitlements = _entitlement.stream.listen((state) {
      if (state is EntitlementInactive) appOpened();
    });
    check();
  }

  final GoRouter _router;
  final EntitlementCubit _entitlement;
  final GetOfferingHard _offeringHard;
  final bool Function() _blocked;
  late final StreamSubscription<EntitlementState> _entitlements;

  /// Whether the paywall is to be checked for: from launch until it is
  /// shown or found not needed.
  bool _due = true;
  bool _checking = false;
  bool _cancelled = false;

  /// The app came back from the background.
  void appOpened() {
    _due = true;
    check();
  }

  /// Shows the paywall now if it is due and may show.
  void check() => unawaited(_check());

  /// After the frame: never from inside the router delegate's notification,
  /// and once a closed paywall has let go of its [paywallOpen].
  void _routed() => SchedulerBinding.instance
    ..addPostFrameCallback((_) => check())
    ..ensureVisualUpdate();

  bool _mayShow() {
    final open = openLocations(_router.routerDelegate.currentConfiguration);
    return open.isNotEmpty &&
        open.every(isPastStart) &&
        !_blocked() &&
        !paywallOpen(_router);
  }

  Future<void> _check() async {
    if (_cancelled || !_due || _checking || !_mayShow()) return;
    switch (premiumStatusOf(_entitlement.state)) {
      case PremiumStatus.unknown:
        return;
      case PremiumStatus.premium:
        _due = false;
        return;
      case PremiumStatus.free:
        break;
    }
    _checking = true;
    final hard = await _offeringHard();
    _checking = false;
    if (_cancelled) return;
    if (hard.valueOrNull != true) {
      _due = false;
      return;
    }
    // Things moved while the offering loaded: still due, for the next
    // change to check again.
    final context = _router.routerDelegate.navigatorKey.currentContext;
    if (_entitlement.state is! EntitlementInactive ||
        !_mayShow() ||
        context == null ||
        !context.mounted) {
      return;
    }
    _due = false;
    await context.openPaywall(moment: PaywallMoment.appOpen);
    // Closed with Premium, or taken away without (a `go`, a failed load
    // that let it close): checked again.
    if (!_cancelled) appOpened();
  }

  Future<void> cancel() async {
    _cancelled = true;
    _router.routerDelegate.removeListener(_routed);
    await _entitlements.cancel();
  }
}
