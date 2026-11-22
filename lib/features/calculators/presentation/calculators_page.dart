import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import 'calculator_list.dart';
import 'calculator_widgets.dart';

/// The calculators in two groups, Body and Training.
class CalculatorsPage extends StatelessWidget {
  const CalculatorsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final calculators = calculatorsOf(l10n);
    Widget group(String label, bool training) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(label),
        const SizedBox(height: calculatorGap - Gap.xs),
        ListRowCard(
          children: [
            for (final entry in calculators.where(
              (entry) => entry.training == training,
            ))
              ListRow(
                title: entry.title,
                detail: entry.subtitle,
                end: ListRowEnd.chevron,
                onTap: () => openCalculator(context, entry),
              ),
          ],
        ),
      ],
    );
    return Scaffold(
      appBar: ForgeAppBar(title: l10n.calculatorsTitle),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.md),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: calculatorGap,
            children: [
              group(l10n.calcGroupBody, false),
              group(l10n.calcGroupTraining, true),
            ],
          ),
        ],
      ),
    );
  }
}
