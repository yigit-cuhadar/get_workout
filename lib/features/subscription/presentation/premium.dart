import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';

/// Whether the signed-in user has Premium. [unknown] while it resolves:
/// never show a paywall or a lock then.
enum PremiumStatus { unknown, free, premium }

PremiumStatus premiumStatusOf(EntitlementState state) => switch (state) {
  EntitlementUnknown() => PremiumStatus.unknown,
  EntitlementInactive() => PremiumStatus.free,
  EntitlementActive() => PremiumStatus.premium,
};

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
      unlocked = await router.push<bool>(Routes.paywall);
    } finally {
      _paywallOpen[router] = false;
    }
    // The paywall pops with true before the cubit may have caught up.
    return unlocked == true || (mounted && read<EntitlementCubit>().isActive);
  }
}

/// One paywall at a time per router, whoever asks for it.
final _paywallOpen = Expando<bool>();
