import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/calculation.dart';
import '../domain/calories.dart';
import 'calculator_format.dart';
import 'calculator_widgets.dart';
import 'calories_cubit.dart';

class CaloriesPage extends StatelessWidget {
  const CaloriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CalculatorScaffold<CaloriesCubit>(
      title: l10n.calcCaloriesTitle,
      create: (units) => CaloriesCubit(
        sl(),
        weightUnit: units.weight,
        lengthUnit: units.length,
      ),
      children: (context, format) => [
        BlocBuilder<CaloriesCubit, CaloriesState>(
          builder: (context, state) {
            final cubit = context.read<CaloriesCubit>();
            String? error(CalculatorInput input) =>
                format.errorFor(input, state.result);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SexSelector(selected: state.sex, onChanged: cubit.sexChanged),
                NumberField(
                  label: l10n.calcBodyWeight(format.weightUnitLabel),
                  onChanged: cubit.weightChanged,
                  errorText: error(CalculatorInput.bodyWeight),
                ),
                NumberField(
                  label: l10n.calcHeight(format.lengthUnitLabel),
                  onChanged: cubit.heightChanged,
                  errorText: error(CalculatorInput.height),
                ),
                NumberField(
                  label: l10n.calcAge,
                  onChanged: cubit.ageChanged,
                  errorText: error(CalculatorInput.age),
                  wholeNumber: true,
                ),
                DropdownButtonFormField<ActivityLevel>(
                  initialValue: state.activity,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l10n.calcActivity),
                  items: [
                    for (final level in ActivityLevel.values)
                      DropdownMenuItem(
                        value: level,
                        child: Text(_activityLabel(l10n, level)),
                      ),
                  ],
                  onChanged: (level) {
                    if (level != null) cubit.activityChanged(level);
                  },
                ),
                const SizedBox(height: Gap.md),
                if (state.result case Calculated(:final value))
                  _Estimate(value, format),
              ],
            );
          },
        ),
      ],
    );
  }

  static String _activityLabel(AppLocalizations l10n, ActivityLevel level) =>
      switch (level) {
        ActivityLevel.sedentary => l10n.calcActivitySedentary,
        ActivityLevel.light => l10n.calcActivityLight,
        ActivityLevel.moderate => l10n.calcActivityModerate,
        ActivityLevel.active => l10n.calcActivityActive,
        ActivityLevel.veryActive => l10n.calcActivityVeryActive,
      };
}

class _Estimate extends StatelessWidget {
  const _Estimate(this.estimate, this.format);

  final CalorieEstimate estimate;
  final CalculatorFormat format;

  @override
  Widget build(BuildContext context) {
    final l10n = format.l10n;
    Widget target(String label, CalorieTarget? target) => target == null
        ? ResultTile(label: label, value: '', note: l10n.calcNoDeficit)
        : ResultTile(
            label: label,
            value: format.kcal(target.kcal),
            note: target.floored
                ? l10n.calcFloored(format.kcal(target.kcal))
                : null,
          );
    return Column(
      children: [
        ResultTile(label: l10n.calcBmr, value: format.kcal(estimate.bmr)),
        ResultTile(
          label: l10n.calcMaintenance,
          value: format.kcal(estimate.maintenance),
        ),
        target(l10n.calcLose, estimate.lose),
        target(l10n.calcLoseSlowly, estimate.loseSlowly),
        target(l10n.calcGain, estimate.gain),
      ],
    );
  }
}
