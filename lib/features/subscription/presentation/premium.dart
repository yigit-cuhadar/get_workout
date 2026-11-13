import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../programs/domain/premium_status.dart' as programs;

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

  /// True when the user has Premium. A free user gets the paywall and true
  /// only if they unlocked it there; while the status is unknown the user is
  /// asked to wait and it is false, as it is while a paywall is open.
  Future<bool> requirePremium() async {
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
        return openPaywall();
    }
  }

  /// Opens the paywall unless one is already open, and tells whether the
  /// user has Premium afterwards. The only way the app opens it.
  Future<bool> openPaywall() async {
    final router = GoRouter.of(this);
    if (_paywallOpen[router] ?? false) return false;
    _paywallOpen[router] = true;
    final bool? unlocked;
    try {
      unlocked = await _pushPaywall(router);
    } finally {
      _paywallOpen[router] = false;
    }
    // The paywall pops with true before the cubit may have caught up.
    return unlocked == true || (mounted && read<EntitlementCubit>().isActive);
  }
}

/// One paywall at a time per router, whoever asks for it: true from the
/// call until the paywall has left the page stack.
final _paywallOpen = Expando<bool>();

/// Pushes the paywall on [router] and completes once it has left the page
/// stack: with its result when popped, with null when a `go` (a
/// notification tap, a tab switch, a redirect) removed it, which never
/// completes the push itself.
Future<bool?> _pushPaywall(GoRouter router) {
  final delegate = router.routerDelegate;
  final closed = Completer<bool?>();
  void close(FutureOr<bool?> result) {
    if (!closed.isCompleted) closed.complete(result);
  }

  ImperativeRouteMatch? shown;
  void track() {
    final match = _paywallIn(delegate.currentConfiguration);
    if (match != null) {
      shown = match;
    } else if (shown case final gone?) {
      // A pop completes the push before the page leaves the stack.
      close(
        gone.completer.isCompleted
            ? gone.completer.future.then((result) => result as bool?)
            : null,
      );
    }
  }

  delegate.addListener(track);
  // Also completes a push that was redirected and never showed the paywall.
  unawaited(router.push<bool>(Routes.paywall).then(close));
  return closed.future.whenComplete(() => delegate.removeListener(track));
}

/// The paywall's page in [stack], or null while it is not open.
ImperativeRouteMatch? _paywallIn(RouteMatchList stack) => stack.matches
    .whereType<ImperativeRouteMatch>()
    .where((match) => match.matchedLocation == Routes.paywall)
    .lastOrNull;
