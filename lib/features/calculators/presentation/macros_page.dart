import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/calculation.dart';
import '../domain/macros.dart';
import 'calculator_widgets.dart';
import 'macros_cubit.dart';

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
              children: [
                NumberField(
                  label: l10n.calcCalories,
                  onChanged: cubit.caloriesChanged,
                  errorText: format.errorFor(
                    CalculatorInput.calories,
                    state.result,
                  ),
                ),
                NumberField(
                  label: l10n.calcBodyWeight(format.weightUnitLabel),
                  value: state.weight,
                  onChanged: cubit.weightChanged,
                  errorText: format.errorFor(
                    CalculatorInput.bodyWeight,
                    state.result,
                  ),
                ),
                Text(
                  l10n.calcProteinPerKg(
                    format.number(state.proteinGPerKg, decimals: 1),
                  ),
                ),
                Slider(
                  value: state.proteinGPerKg,
                  min: proteinRangeGPerKg.min,
                  max: proteinRangeGPerKg.max,
                  divisions: 12,
                  onChanged: cubit.proteinChanged,
                ),
                Text(l10n.calcFatShare(format.number(state.fatPercent))),
                Slider(
                  value: state.fatPercent,
                  min: fatRangePercent.min,
                  max: fatRangePercent.max,
                  divisions: 15,
                  onChanged: cubit.fatChanged,
                ),
                if (problem != null) InputProblem(problem),
                if (state.result case Calculated(:final value)) ...[
                  ResultTile(
                    label: l10n.calcProtein,
                    value: grams(value.proteinG),
                  ),
                  ResultTile(label: l10n.calcFat, value: grams(value.fatG)),
                  ResultTile(label: l10n.calcCarbs, value: grams(value.carbsG)),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}
