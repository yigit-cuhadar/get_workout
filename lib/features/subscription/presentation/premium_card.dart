import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../core/open_link.dart';
import '../../../l10n/app_localizations.dart';
import 'premium.dart';
import 'subscription_summary.dart';
import 'subscription_text.dart';

/// The Profile tab's Premium card: what Premium is and the user's state, with
/// Get Premium (the paywall) for a free user and the store's manage page for
/// a subscriber; no action while the status is unknown or for Premium with
/// no expiry.
class PremiumCard extends StatelessWidget {
  const PremiumCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = colors.onPrimaryContainer;
    final summary = context.select(
      (EntitlementCubit cubit) => SubscriptionSummary.of(cubit.state),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
      child: Card(
        margin: EdgeInsets.zero,
        color: colors.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.workspace_premium_outlined, color: foreground),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.premiumTitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: foreground,
                          ),
                        ),
                        Text(
                          l10n.subscriptionSummary(summary),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: foreground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.sm),
              Text(
                l10n.premiumCardPitch,
                style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
              ),
              switch (summary) {
                // Lifetime or granted Premium has no subscription to manage.
                SubscriptionChecking() ||
                SubscriptionLifetime() => const SizedBox.shrink(),
                SubscriptionFree() => Padding(
                  padding: const EdgeInsets.only(top: Gap.md),
                  child: ForgeButton(
                    label: l10n.premiumGet,
                    onPressed: context.openPaywall,
                  ),
                ),
                _ => Padding(
                  padding: const EdgeInsets.only(top: Gap.md),
                  child: OutlinedButton(
                    onPressed: () => _manage(context),
                    child: Text(l10n.premiumManage),
                  ),
                ),
              },
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _manage(BuildContext context) async {
    final failed = AppLocalizations.of(context).premiumManageFailed;
    final messenger = ScaffoldMessenger.of(context);
    final url = await context.read<EntitlementCubit>().managementUrl();
    final opened = url.valueOrNull != null && await openLink(url.valueOrNull!);
    if (!opened) messenger.showSnackBar(SnackBar(content: Text(failed)));
  }
}
