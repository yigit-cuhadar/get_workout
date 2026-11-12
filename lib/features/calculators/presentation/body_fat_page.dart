import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/calculation.dart';
import '../domain/calories.dart';
import 'body_fat_cubit.dart';
import 'calculator_widgets.dart';

class BodyFatPage extends StatelessWidget {
  const BodyFatPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CalculatorScaffold<BodyFatCubit>(
      title: l10n.calcBodyFatTitle,
      create: (units) =>
          BodyFatCubit(sl(), sl(), sl(), lengthUnit: units.length),
      children: (context, format) => [
        CalculatorNote(l10n.calcBodyFatHowTo),
        BlocBuilder<BodyFatCubit, BodyFatState>(
          builder: (context, state) {
            final cubit = context.read<BodyFatCubit>();
            final unit = format.lengthUnitLabel;
            String? error(CalculatorInput input) =>
                format.errorFor(input, state.result);
            final problem = format.generalError(state.result);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SexSelector(selected: state.sex, onChanged: cubit.sexChanged),
                KnownNumberField(
                  known: state.known[CalculatorInput.height],
                  onEdit: () => cubit.edit(CalculatorInput.height),
                  name: l10n.calcKnownHeight,
                  unit: unit,
                  label: l10n.calcHeight(unit),
                  value: state.height,
                  onChanged: cubit.heightChanged,
                  errorText: error(CalculatorInput.height),
                ),
                KnownNumberField(
                  known: state.known[CalculatorInput.neck],
                  onEdit: () => cubit.edit(CalculatorInput.neck),
                  name: l10n.calcKnownNeck,
                  unit: unit,
                  label: l10n.calcNeck(unit),
                  value: state.neck,
                  onChanged: cubit.neckChanged,
                  errorText: error(CalculatorInput.neck),
                ),
                KnownNumberField(
                  known: state.known[CalculatorInput.waist],
                  onEdit: () => cubit.edit(CalculatorInput.waist),
                  name: state.sex == Sex.male
                      ? l10n.calcKnownAbdomen
                      : l10n.calcKnownWaist,
                  unit: unit,
                  label: state.sex == Sex.male
                      ? l10n.calcWaistAtNavel(unit)
                      : l10n.calcWaist(unit),
                  value: state.waist,
                  onChanged: cubit.waistChanged,
                  errorText: error(CalculatorInput.waist),
                ),
                if (state.sex == Sex.female)
                  KnownNumberField(
                    known: state.known[CalculatorInput.hip],
                    onEdit: () => cubit.edit(CalculatorInput.hip),
                    name: l10n.calcKnownHips,
                    unit: unit,
                    label: l10n.calcHip(unit),
                    value: state.hip,
                    onChanged: cubit.hipChanged,
                    errorText: error(CalculatorInput.hip),
                  ),
                if (problem != null) InputProblem(problem),
                if (state.result case Calculated(:final value))
                  ResultTile(
                    label: l10n.calcBodyFatResult,
                    value: l10n.calcPercent(format.number(value, decimals: 1)),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
