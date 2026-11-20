import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../analytics/domain/analytics.dart';
import '../../subscription/presentation/premium.dart';

/// Opens the generator for a user with premium; others get the paywall
/// first and go on only if they unlocked it there.
Future<void> openGenerator(BuildContext context) async {
  if (await context.requirePremium(PremiumFeature.generator) &&
      context.mounted) {
    await context.push(Routes.programGenerator);
  }
}

/// The way into the generator as a row, shown to everyone; locked without
/// premium.
class GeneratorEntry extends StatelessWidget {
  const GeneratorEntry({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locked = context.watchPremium() == PremiumStatus.free;
    return ListRow(
      title: l10n.generatorTitle,
      detail: l10n.generatorEntryInfo,
      // A locked row keeps full colour and opens the paywall.
      trailing: locked
          ? ForgeTag(l10n.cataloguePremium, kind: ForgeTagKind.premium)
          : null,
      end: locked ? ListRowEnd.none : ListRowEnd.chevron,
      onTap: () => openGenerator(context),
    );
  }
}
