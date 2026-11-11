import 'package:flutter/material.dart';

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
