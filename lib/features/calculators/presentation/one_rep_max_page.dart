import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/calculation.dart';
import 'calculator_widgets.dart';
import 'one_rep_max_cubit.dart';
import 'widgets/calculator_result.dart';

class OneRepMaxPage extends StatelessWidget {
  const OneRepMaxPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CalculatorScaffold<OneRepMaxCubit>(
      title: l10n.calcOneRepMaxTitle,
      create: (units) => OneRepMaxCubit(sl(), weightUnit: units.weight),
      children: (context, format) => [
        BlocBuilder<OneRepMaxCubit, OneRepMaxState>(
          builder: (context, state) {
            final cubit = context.read<OneRepMaxCubit>();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: calculatorGap,
              children: [
                ListRowCard(
                  children: [
                    CalculatorInputRow(
                      input: CalculatorInput.liftedWeight,
                      format: format,
                      title: l10n.calcLiftedWeightTitle,
                      unit: format.weightUnitLabel,
                      text: state.weight,
                      result: state.result,
                      onChanged: cubit.weightChanged,
                    ),
                    CalculatorInputRow(
                      input: CalculatorInput.reps,
                      format: format,
                      title: l10n.calcReps,
                      text: state.reps,
                      result: state.result,
                      onChanged: cubit.repsChanged,
                    ),
                  ],
                ),
                switch (state.result) {
                  Calculated(:final value) => CalculatorResult(
                    caption: l10n.calcOneRepMaxResult,
                    value: format.weight(value.estimateKg),
                    rows: [
                      for (final load in value.loads.reversed)
                        CalculatorRow(
                          l10n.calcPercentOfMax('${load.percent}'),
                          format.weight(load.weightKg),
                        ),
                    ],
                  ),
                  null => CalculatorResult.missing(
                    caption: l10n.calcOneRepMaxResult,
                    note: l10n.calcOneRepMaxMissing,
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
