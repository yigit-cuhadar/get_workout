import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';

/// What a premium call to action does: the subscription feature opens its
/// paywall here.
class PremiumPrompt {
  const PremiumPrompt(this.show);

  final void Function(BuildContext context) show;
}

/// Until the subscription feature exists: says premium is coming.
void showPremiumComingSoon(BuildContext context) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).premiumComingSoon)),
    );

/// Why something is locked, and the premium call to action.
class PremiumLock extends StatelessWidget {
  const PremiumLock({super.key, required this.message, required this.prompt});

  final String message;
  final PremiumPrompt prompt;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Icon(Icons.lock_outline),
          const SizedBox(width: Gap.sm),
          Expanded(child: Text(message)),
        ],
      ),
      const SizedBox(height: Gap.sm),
      ForgeButton(
        label: AppLocalizations.of(context).catalogueGetPremium,
        onPressed: () => prompt.show(context),
      ),
    ],
  );
}
