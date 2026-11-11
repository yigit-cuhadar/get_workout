import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import 'subscription_summary.dart';
import 'subscription_text.dart';

/// The Profile tab's Premium row: the paywall for a free user, the store's
/// manage page for a subscriber, nothing while the status is unknown.
class PremiumTile extends StatelessWidget {
  const PremiumTile({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final summary = context.select(
      (EntitlementCubit cubit) => SubscriptionSummary.of(cubit.state),
    );
    return ListTile(
      leading: const Icon(Icons.workspace_premium_outlined),
      title: Text(l10n.premiumTitle),
      subtitle: Text(l10n.subscriptionSummary(summary)),
      trailing: summary is SubscriptionChecking
          ? null
          : const Icon(Icons.chevron_right),
      onTap: switch (summary) {
        SubscriptionChecking() => null,
        SubscriptionFree() => () => context.push<bool>(Routes.paywall),
        _ => () => _manage(context),
      },
    );
  }

  Future<void> _manage(BuildContext context) async {
    final failed = AppLocalizations.of(context).premiumManageFailed;
    final messenger = ScaffoldMessenger.of(context);
    final url = await context.read<EntitlementCubit>().managementUrl();
    final opened =
        url.valueOrNull != null &&
        await launchUrl(
          url.valueOrNull!,
          mode: LaunchMode.externalApplication,
        ).catchError((_) => false);
    if (!opened) messenger.showSnackBar(SnackBar(content: Text(failed)));
  }
}
