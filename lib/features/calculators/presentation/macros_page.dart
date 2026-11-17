import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/calculation.dart';
import '../domain/macros.dart';
import 'calculator_widgets.dart';
import 'macros_cubit.dart';
import 'widgets/calculator_result.dart';

class MacrosPage extends StatelessWidget {
  const MacrosPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CalculatorScaffold<MacrosCubit>(
      title: l10n.calcMacrosTitle,
      create: (units) =>
          MacrosCubit(sl(), sl(), sl(), weightUnit: units.weight),
      children: (context, format) => [
        BlocBuilder<MacrosCubit, MacrosState>(
          builder: (context, state) {
            final cubit = context.read<MacrosCubit>();
            final problem = format.generalError(state.result);
            String grams(double value) => l10n.calcGrams(format.number(value));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: calculatorGap,
              children: [
                ListRowCard(
                  children: [
                    CalculatorInputRow(
                      input: CalculatorInput.calories,
                      format: format,
                      title: l10n.calcCaloriesTitle,
                      label: l10n.calcCalories,
                      unit: l10n.calcUnitKcal,
                      text: state.calories,
                      result: state.result,
                      onChanged: cubit.caloriesChanged,
                    ),
                    CalculatorInputRow(
                      input: CalculatorInput.bodyWeight,
                      format: format,
                      title: l10n.calcKnownWeight,
                      label: l10n.calcBodyWeight(format.weightUnitLabel),
                      unit: format.weightUnitLabel,
                      text: state.weight,
                      known: state.known[CalculatorInput.bodyWeight],
                      result: state.result,
                      onChanged: cubit.weightChanged,
                    ),
                  ],
                ),
                ForgeSlider(
                  label: l10n.calcProtein,
                  unit: l10n.calcUnitGPerKg,
                  min: proteinRangeGPerKg.min,
                  max: proteinRangeGPerKg.max,
                  step: 0.1,
                  value: state.proteinGPerKg,
                  onChanged: cubit.proteinChanged,
                ),
                ForgeSlider(
                  label: l10n.calcFat,
                  unit: l10n.calcUnitPercentOfCalories,
                  min: fatRangePercent.min,
                  max: fatRangePercent.max,
                  step: 1,
                  value: state.fatPercent,
                  onChanged: cubit.fatChanged,
                ),
                if (problem != null)
                  InputProblem(problem)
                else
                  switch (state.result) {
                    Calculated(:final value) => CalculatorResult(
                      caption: l10n.calcProtein,
                      value: grams(value.proteinG),
                      rows: [
                        CalculatorRow(l10n.calcFat, grams(value.fatG)),
                        CalculatorRow(l10n.calcCarbs, grams(value.carbsG)),
                      ],
                    ),
                    null => CalculatorResult.missing(
                      caption: l10n.calcProtein,
                      note: state.calories.isEmpty
                          ? l10n.calcMacrosMissing
                          : format.addToSee([l10n.calcMissingBodyweight]),
                    ),
                    _ => const SizedBox.shrink(),
                  },
              ],
            );
          },
        ),
      ],
    );
  }
}
