import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/open_link.dart';
import '../../../l10n/app_localizations.dart';
import '../../analytics/domain/analytics.dart';
import '../../programs/domain/premium_status.dart' as programs;
import '../../settings/presentation/settings_cubit.dart';
import '../domain/paywall_moment.dart';

/// Whether the signed-in user has Premium. [unknown] while it resolves:
/// never show a paywall or a lock then.
enum PremiumStatus { unknown, free, premium }

PremiumStatus premiumStatusOf(EntitlementState state) => switch (state) {
  EntitlementUnknown() => PremiumStatus.unknown,
  EntitlementInactive() => PremiumStatus.free,
  EntitlementActive() => PremiumStatus.premium,
};

/// [EntitlementCubit]'s status as features outside the widget tree take it:
/// null while unknown.
class EntitlementPremium implements programs.PremiumStatus {
  const EntitlementPremium(this._entitlement);

  final EntitlementCubit _entitlement;

  @override
  Stream<bool?> watch() async* {
    yield _premium(_entitlement.state);
    yield* _entitlement.stream.map(_premium).distinct();
  }

  static bool? _premium(EntitlementState state) =>
      switch (premiumStatusOf(state)) {
        PremiumStatus.unknown => null,
        PremiumStatus.free => false,
        PremiumStatus.premium => true,
      };
}

/// The gate every premium feature uses: [watchPremium] to show a lock,
/// [requirePremium] before entering.
extension PremiumGate on BuildContext {
  /// Rebuilds the caller when the status changes.
  PremiumStatus watchPremium() =>
      select((EntitlementCubit cubit) => premiumStatusOf(cubit.state));

  /// True when the user has Premium. A free user gets the paywall (a
  /// lock tap on [feature]) and true only if they unlocked it there; while
  /// the status is unknown the user is asked to wait and it is false, as it
  /// is while a paywall is open.
  Future<bool> requirePremium(PremiumFeature feature) async {
    switch (premiumStatusOf(read<EntitlementCubit>().state)) {
      case PremiumStatus.premium:
        return true;
      case PremiumStatus.unknown:
        ScaffoldMessenger.of(this).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(this).premiumStillChecking),
          ),
        );
        return false;
      case PremiumStatus.free:
        return unlockPremium(feature);
    }
  }

  /// The paywall for a free user's tap on the locked [feature].
  Future<bool> unlockPremium(PremiumFeature feature) {
    unawaited(read<Analytics>().premiumLockTap(feature));
    return openPaywall();
  }

  /// Opens the paywall unless one is already open, and tells whether the
  /// user has Premium afterwards. The only way the app opens it; [moment]
  /// when the app offers it by itself.
  Future<bool> openPaywall({PaywallMoment? moment}) async {
    final router = GoRouter.of(this);
    if (_paywallOpen[router] ?? false) return false;
    _paywallOpen[router] = true;
    final bool? unlocked;
    try {
      unlocked = await _pushPaywall(
        router,
        moment == null ? Routes.paywall : Routes.paywallAt(moment),
      );
    } finally {
      _paywallOpen[router] = false;
    }
    // The paywall pops with true before the cubit may have caught up.
    return unlocked == true || (mounted && read<EntitlementCubit>().isActive);
  }

  /// Shows the paywall at a once-per-user [moment] if it is due
  /// ([paywallMomentDue]) and marks it shown, so it never shows again for
  /// this user; completes once it closed, at once when not due.
  Future<void> paywallMoment(PaywallMoment moment) async {
    final settings = read<SettingsCubit>();
    final due = paywallMomentDue(
      moment,
      premium: switch (premiumStatusOf(read<EntitlementCubit>().state)) {
        PremiumStatus.unknown => null,
        PremiumStatus.free => false,
        PremiumStatus.premium => true,
      },
      seen: settings.state.loaded ? settings.state.settings.seenTips : null,
    );
    if (!due) return;
    if (moment.tip case final tip?) unawaited(settings.tipSeen(tip));
    await openPaywall(moment: moment);
  }

  /// Manages the subscription: on iOS RevenueCat's Customer Center, whose
  /// cancel path offers a free month; elsewhere, or where it cannot show,
  /// the store's page. Google Play keeps the store's page until Play is set
  /// up.
  Future<void> manageSubscription() async {
    unawaited(read<Analytics>().manageSubscription());
    final failed = AppLocalizations.of(this).premiumManageFailed;
    final entitlement = read<EntitlementCubit>();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final presented = await entitlement.presentCustomerCenter();
      if (presented.valueOrNull ?? false) return;
    }
    final url = await entitlement.managementUrl();
    final opened = url.valueOrNull != null && await openLink(url.valueOrNull!);
    if (!opened && mounted) {
      showForgeSnackbar(this, message: failed, error: true);
    }
  }
}

/// One paywall at a time per router, whoever asks for it: true from the
/// call until the paywall has left the page stack.
final _paywallOpen = Expando<bool>();

/// Whether a paywall is open on [router] ([PremiumGate.openPaywall]).
bool paywallOpen(GoRouter router) => _paywallOpen[router] ?? false;

/// Pushes the paywall at [location] on [router] and completes once that
/// push has left the page stack: with its result when popped, with null when a `go` (a
/// notification tap, a tab switch, a redirect) removed it, or when the push
/// never reached the stack because a later navigation replaced it before it
/// was parsed. go_router completes the push itself only on a pop, and not
/// even then once a refresh has rebuilt the stack.
Future<bool?> _pushPaywall(GoRouter router, String location) {
  final provider = router.routeInformationProvider;
  final delegate = router.routerDelegate;
  final closed = Completer<bool?>();
  void close(FutureOr<bool?> result) {
    if (!closed.isCompleted) closed.complete(result);
  }

  // The push's own navigation: set before the push returns, and pending
  // while it is still the provider's value.
  final pushed = router.push<bool>(location);
  final navigation = provider.value.state;
  final completer = navigation is RouteInformationState
      ? navigation.completer
      : null;
  bool pending() => identical(provider.value.state, navigation);

  // Found by its completer once parsed, then by its page key: a refresh
  // rebuilds the stack's pushed pages with new completers.
  ImperativeRouteMatch? shown;
  void track() {
    final match = _pushedIn(
      delegate.currentConfiguration.matches,
      (match) => shown == null
          ? identical(match.completer, completer)
          : match.pageKey == shown!.pageKey,
    );
    if (match != null) {
      shown = match;
    } else if (shown case final gone?) {
      // A pop completes the page's match before it leaves the stack.
      close(
        gone.completer.isCompleted
            ? gone.completer.future.then((result) => result == true)
            : null,
      );
    } else if (!pending()) {
      close(null);
    }
  }

  delegate.addListener(track);
  provider.addListener(track);
  // Without an `onEnter` or async redirect the push is parsed at once.
  track();
  unawaited(pushed.then(close));
  return closed.future.whenComplete(() {
    delegate.removeListener(track);
    provider.removeListener(track);
  });
}

/// The page pushed onto [matches] that [test] picks, also inside a shell.
ImperativeRouteMatch? _pushedIn(
  List<RouteMatchBase> matches,
  bool Function(ImperativeRouteMatch match) test,
) {
  for (final match in matches) {
    final found = switch (match) {
      ImperativeRouteMatch() when test(match) => match,
      ShellRouteMatch() => _pushedIn(match.matches, test),
      _ => null,
    };
    if (found != null) return found;
  }
  return null;
}
