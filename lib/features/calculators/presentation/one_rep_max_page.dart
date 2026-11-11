import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/calculation.dart';
import 'calculator_widgets.dart';
import 'one_rep_max_cubit.dart';

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
              children: [
                NumberField(
                  label: l10n.calcLiftedWeight(format.weightUnitLabel),
                  onChanged: cubit.weightChanged,
                  errorText: format.errorFor(
                    CalculatorInput.liftedWeight,
                    state.result,
                  ),
                ),
                NumberField(
                  label: l10n.calcReps,
                  onChanged: cubit.repsChanged,
                  errorText: format.errorFor(
                    CalculatorInput.reps,
                    state.result,
                  ),
                  wholeNumber: true,
                ),
                if (state.result case Calculated(:final value)) ...[
                  ResultTile(
                    label: l10n.calcOneRepMaxResult,
                    value: format.weight(value.estimateKg),
                  ),
                  const Divider(),
                  for (final load in value.loads.reversed)
                    ResultTile(
                      label: l10n.calcPercentOfMax('${load.percent}'),
                      value: format.weight(load.weightKg),
                    ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}
