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
  /// asked to wait and it is false.
  Future<bool> requirePremium() async {
    final entitlement = read<EntitlementCubit>();
    switch (premiumStatusOf(entitlement.state)) {
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
        // The paywall pops with true before the cubit may have caught up.
        final unlocked = await push<bool>(Routes.paywall);
        return unlocked == true || entitlement.isActive;
    }
  }
}
