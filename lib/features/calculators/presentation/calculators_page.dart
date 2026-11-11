import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';

class CalculatorsPage extends StatelessWidget {
  const CalculatorsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final calculators = [
      (l10n.calcCaloriesTitle, l10n.calcCaloriesSubtitle, Routes.calories),
      (l10n.calcBodyFatTitle, l10n.calcBodyFatSubtitle, Routes.bodyFat),
      (l10n.calcOneRepMaxTitle, l10n.calcOneRepMaxSubtitle, Routes.oneRepMax),
      (l10n.calcPlatesTitle, l10n.calcPlatesSubtitle, Routes.plates),
      (l10n.calcMacrosTitle, l10n.calcMacrosSubtitle, Routes.macros),
      (
        l10n.calcBodyIndicesTitle,
        l10n.calcBodyIndicesSubtitle,
        Routes.bodyIndices,
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.calculatorsTitle)),
      body: ListView(
        children: [
          for (final (title, subtitle, route) in calculators)
            ListTile(
              title: Text(title),
              subtitle: Text(subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(route),
            ),
        ],
      ),
    );
  }
}
