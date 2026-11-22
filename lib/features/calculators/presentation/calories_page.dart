import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/calculation.dart';
import '../domain/calories.dart';
import 'calculator_format.dart';
import 'calculator_widgets.dart';
import 'calories_cubit.dart';
import 'widgets/calculator_result.dart';

class CaloriesPage extends StatelessWidget {
  const CaloriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CalculatorScaffold<CaloriesCubit>(
      title: l10n.calcCaloriesTitle,
      create: (units) => CaloriesCubit(
        sl(),
        sl(),
        sl(),
        weightUnit: units.weight,
        lengthUnit: units.length,
      ),
      children: (context, format) => [
        BlocBuilder<CaloriesCubit, CaloriesState>(
          builder: (context, state) {
            final cubit = context.read<CaloriesCubit>();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: calculatorGap,
              children: [
                ListRowCard(
                  children: [
                    CalculatorChoiceRow(
                      title: l10n.calcSex,
                      values: Sex.values,
                      selected: state.sex,
                      labelOf: l10n.calcSexLabel,
                      onChanged: cubit.sexChanged,
                    ),
                    CalculatorInputRow(
                      input: CalculatorInput.age,
                      format: format,
                      title: l10n.calcKnownAge,
                      text: state.age,
                      known: state.known[CalculatorInput.age],
                      result: state.result,
                      onChanged: cubit.ageChanged,
                    ),
                    CalculatorInputRow(
                      input: CalculatorInput.height,
                      format: format,
                      title: l10n.calcKnownHeight,
                      unit: format.lengthUnitLabel,
                      text: state.height,
                      known: state.known[CalculatorInput.height],
                      result: state.result,
                      onChanged: cubit.heightChanged,
                    ),
                    CalculatorInputRow(
                      input: CalculatorInput.bodyWeight,
                      format: format,
                      title: l10n.calcKnownWeight,
                      unit: format.weightUnitLabel,
                      text: state.weight,
                      known: state.known[CalculatorInput.bodyWeight],
                      result: state.result,
                      onChanged: cubit.weightChanged,
                    ),
                    CalculatorChoiceRow(
                      title: l10n.calcActivity,
                      values: ActivityLevel.values,
                      selected: state.activity,
                      labelOf: l10n.calcActivityLabel,
                      onChanged: cubit.activityChanged,
                    ),
                  ],
                ),
                switch (state.result) {
                  Calculated(:final value) => _Estimate(value, format),
                  null => CalculatorResult.missing(
                    caption: l10n.calcDailyEnergy,
                    note: format.addToSee([
                      if (state.sex == null) l10n.calcMissingSex,
                      if (state.age.isEmpty) l10n.calcMissingAge,
                      if (state.height.isEmpty) l10n.calcMissingHeight,
                      if (state.weight.isEmpty) l10n.calcMissingBodyweight,
                      if (state.activity == null) l10n.calcMissingActivity,
                    ]),
                  ),
                  // A value outside its range says so on its row.
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

class _Estimate extends StatelessWidget {
  const _Estimate(this.estimate, this.format);

  final CalorieEstimate estimate;
  final CalculatorFormat format;

  @override
  Widget build(BuildContext context) {
    final l10n = format.l10n;
    final change = weeklyChangeKg(format.weightUnit);
    String kcal(double value) => format.number(value);
    CalculatorRow target(
      String label,
      CalorieTarget? target,
    ) => switch (target) {
      null => CalculatorRow(label, l10n.bodyNoValue, note: l10n.calcNoDeficit),
      CalorieTarget(:final kcal, floored: true) => CalculatorRow(
        label,
        format.number(kcal),
        note: l10n.calcFloored(format.kcal(kcal)),
      ),
      CalorieTarget(:final kcal) => CalculatorRow(label, format.number(kcal)),
    };
    return CalculatorResult(
      caption: l10n.calcDailyEnergy,
      value: format.kcal(estimate.maintenance),
      rows: [
        target(
          l10n.calcLosePerWeek(format.weeklyRate(change.lose)),
          estimate.lose,
        ),
        CalculatorRow(l10n.calcKeepWeight, kcal(estimate.maintenance)),
        target(
          l10n.calcGainPerWeek(format.weeklyRate(change.gain)),
          estimate.gain,
        ),
      ],
    );
  }
}
