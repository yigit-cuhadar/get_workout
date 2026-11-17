import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_purchases/forge_purchases.dart';

import '../../../core/widgets/featured_card.dart';
import '../../../l10n/app_localizations.dart';
import 'premium.dart';
import 'subscription_summary.dart';
import 'subscription_text.dart';

/// The Profile tab's Premium card, a [FeaturedCard] prompt: what Premium
/// is with Get Premium (the paywall) for a free user; otherwise the user's
/// state as the title over what Premium is, with the store's manage page
/// for a subscriber. No action while the status is unknown or for Premium
/// with no expiry.
class PremiumCard extends StatelessWidget {
  const PremiumCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final summary = context.select(
      (EntitlementCubit cubit) => SubscriptionSummary.of(cubit.state),
    );
    final state = l10n.subscriptionState(summary);
    if (state == null) {
      return FeaturedCard(
        form: FeaturedCardForm.prompt,
        eyebrow: l10n.premiumTitle,
        title: l10n.premiumCardPitch,
        action: FeaturedAction(l10n.premiumGet, context.openPaywall),
      );
    }
    return FeaturedCard(
      form: FeaturedCardForm.prompt,
      eyebrow: l10n.premiumTitle,
      title: state,
      titleTone: switch (summary) {
        SubscriptionChecking() => FeaturedTitleTone.muted,
        SubscriptionBillingIssue() => FeaturedTitleTone.danger,
        _ => FeaturedTitleTone.ink,
      },
      note: l10n.premiumCardPitch,
      moreActions: [
        // Lifetime or granted Premium has no subscription to manage.
        if (summary is! SubscriptionChecking &&
            summary is! SubscriptionLifetime)
          FeaturedAction(l10n.premiumManage, context.manageSubscription),
      ],
    );
  }
}
