import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/body_indices.dart';
import '../domain/calculation.dart';
import 'body_indices_cubit.dart';
import 'calculator_widgets.dart';

class BodyIndicesPage extends StatelessWidget {
  const BodyIndicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CalculatorScaffold<BodyIndicesCubit>(
      title: l10n.calcBodyIndicesTitle,
      create: (units) => BodyIndicesCubit(
        sl(),
        sl(),
        sl(),
        weightUnit: units.weight,
        lengthUnit: units.length,
      ),
      children: (context, format) => [
        BlocBuilder<BodyIndicesCubit, BodyIndicesState>(
          builder: (context, state) {
            final cubit = context.read<BodyIndicesCubit>();
            String? error(CalculatorInput input) =>
                format.errorFor(input, state.result);
            String index(double value) => format.number(value, decimals: 1);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KnownNumberField(
                  known: state.known[CalculatorInput.bodyWeight],
                  onEdit: () => cubit.edit(CalculatorInput.bodyWeight),
                  name: l10n.calcKnownWeight,
                  unit: format.weightUnitLabel,
                  label: l10n.calcBodyWeight(format.weightUnitLabel),
                  value: state.weight,
                  onChanged: cubit.weightChanged,
                  errorText: error(CalculatorInput.bodyWeight),
                ),
                KnownNumberField(
                  known: state.known[CalculatorInput.height],
                  onEdit: () => cubit.edit(CalculatorInput.height),
                  name: l10n.calcKnownHeight,
                  unit: format.lengthUnitLabel,
                  label: l10n.calcHeight(format.lengthUnitLabel),
                  value: state.height,
                  onChanged: cubit.heightChanged,
                  errorText: error(CalculatorInput.height),
                ),
                KnownNumberField(
                  known: state.known[CalculatorInput.bodyFat],
                  onEdit: () => cubit.edit(CalculatorInput.bodyFat),
                  name: l10n.calcBodyFatResult,
                  unit: l10n.calcUnitPercent,
                  label: l10n.calcBodyFatOptional,
                  value: state.bodyFat,
                  onChanged: cubit.bodyFatChanged,
                  errorText: error(CalculatorInput.bodyFat),
                ),
                if (state.result case Calculated(:final value)) ...[
                  ResultTile(label: l10n.calcBmi, value: index(value.bmi)),
                  CalculatorNote(l10n.calcBmiInfo),
                  if (value case BodyIndices(
                    :final ffmi?,
                    :final normalizedFfmi?,
                  )) ...[
                    ResultTile(label: l10n.calcFfmi, value: index(ffmi)),
                    CalculatorNote(l10n.calcFfmiInfo),
                    ResultTile(
                      label: l10n.calcNormalizedFfmi,
                      value: index(normalizedFfmi),
                    ),
                    CalculatorNote(l10n.calcNormalizedFfmiInfo),
                  ] else
                    CalculatorNote(l10n.calcFfmiNeedsBodyFat),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}
