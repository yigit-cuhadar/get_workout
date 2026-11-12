import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../subscription/presentation/premium.dart';

/// Opens the generator for a user with premium; others get the paywall
/// first and go on only if they unlocked it there.
Future<void> openGenerator(BuildContext context) async {
  if (await context.requirePremium() && context.mounted) {
    context.go(Routes.programGenerator);
  }
}

/// The way into the generator, shown to everyone; locked without premium.
class GeneratorEntry extends StatelessWidget {
  const GeneratorEntry({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locked = context.watchPremium() == PremiumStatus.free;
    return ListTile(
      leading: const Icon(Icons.tune),
      title: Text(l10n.generatorTitle),
      subtitle: Text(l10n.generatorEntryInfo),
      trailing: locked
          ? Icon(Icons.lock_outline, semanticLabel: l10n.catalogueLockedLabel)
          : const Icon(Icons.chevron_right),
      onTap: () => openGenerator(context),
    );
  }
}

/// The generator as a button, e.g. while there are no programs; locked
/// without premium.
class GeneratorButton extends StatelessWidget {
  const GeneratorButton({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locked = context.watchPremium() == PremiumStatus.free;
    return OutlinedButton.icon(
      icon: Icon(
        locked ? Icons.lock_outline : Icons.tune,
        semanticLabel: locked ? l10n.catalogueLockedLabel : null,
      ),
      label: Text(l10n.generatorTitle),
      onPressed: () => openGenerator(context),
    );
  }
}
