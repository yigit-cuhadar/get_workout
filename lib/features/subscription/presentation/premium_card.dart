import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../core/widgets/featured_card.dart';
import '../../../l10n/app_localizations.dart';
import 'premium.dart';
import 'premium_trial_cubit.dart';
import 'subscription_summary.dart';
import 'subscription_text.dart';

/// The Profile tab's Premium card. For a free user a plain card: Premium's
/// name with the store's trial as a tag, its benefits checked and Get
/// Premium (the paywall); needs a [PremiumTrialCubit] above. Otherwise a
/// [FeaturedCard] prompt: the user's state as the title over what Premium
/// is, with the store's manage page for a subscriber. No action while the
/// status is unknown or for Premium with no expiry.
class PremiumCard extends StatelessWidget {
  const PremiumCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final summary = context.select(
      (EntitlementCubit cubit) => SubscriptionSummary.of(cubit.state),
    );
    final state = l10n.subscriptionState(summary);
    if (state == null) return const _FreeCard();
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

class _FreeCard extends StatelessWidget {
  const _FreeCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final trial = context.watch<PremiumTrialCubit>().state;
    final style = ForgeStyle.of(context);
    // Profile's other cards: a plain surface card.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.colors.surface,
        borderRadius: BorderRadius.circular(style.radii.lg),
        border: style.cardBorder == 0
            ? null
            : Border.all(color: style.colors.line, width: style.cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Gap.md,
          children: [
            // The tag goes under the title when both do not fit (larger
            // text).
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Gap.sm,
              runSpacing: Gap.xs,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    l10n.premiumTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (trial != null)
                  ForgeTag(l10n.paywallCardTrial(l10n.offerPeriod(trial))),
              ],
            ),
            BenefitList.checked([
              l10n.paywallBenefitGenerator,
              l10n.paywallBenefitPrograms,
              l10n.paywallBenefitCharts,
            ]),
            ForgeButton(label: l10n.premiumGet, onPressed: context.openPaywall),
          ],
        ),
      ),
    );
  }
}
