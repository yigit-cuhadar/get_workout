import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';

/// What the Profile tab's Premium card says, most urgent first.
sealed class SubscriptionSummary extends Equatable {
  const SubscriptionSummary();

  factory SubscriptionSummary.of(EntitlementState state) => switch (state) {
    EntitlementUnknown() => const SubscriptionChecking(),
    EntitlementInactive() => const SubscriptionFree(),
    EntitlementActive(:final entitlement) => switch (entitlement) {
      Entitlement(hasBillingIssue: true) => const SubscriptionBillingIssue(),
      Entitlement(expiresAt: null) => const SubscriptionLifetime(),
      Entitlement(isInTrial: true, :final expiresAt?) => SubscriptionTrial(
        expiresAt,
      ),
      Entitlement(willRenew: true, :final expiresAt?) => SubscriptionRenews(
        expiresAt,
      ),
      Entitlement(:final expiresAt?) => SubscriptionEnds(expiresAt),
    },
  };

  @override
  List<Object?> get props => [];
}

/// Not resolved yet; the card offers no action.
final class SubscriptionChecking extends SubscriptionSummary {
  const SubscriptionChecking();
}

/// Offers the paywall.
final class SubscriptionFree extends SubscriptionSummary {
  const SubscriptionFree();
}

/// The rest but [SubscriptionLifetime] offer the store's manage page.
final class SubscriptionBillingIssue extends SubscriptionSummary {
  const SubscriptionBillingIssue();
}

final class SubscriptionLifetime extends SubscriptionSummary {
  const SubscriptionLifetime();
}

sealed class SubscriptionDated extends SubscriptionSummary {
  const SubscriptionDated(this.date);
  final DateTime date;

  @override
  List<Object?> get props => [date];
}

/// In the free trial until [date]; renews then unless cancelled.
final class SubscriptionTrial extends SubscriptionDated {
  const SubscriptionTrial(super.date);
}

final class SubscriptionRenews extends SubscriptionDated {
  const SubscriptionRenews(super.date);
}

/// Auto-renew is off: Premium ends on [date].
final class SubscriptionEnds extends SubscriptionDated {
  const SubscriptionEnds(super.date);
}
