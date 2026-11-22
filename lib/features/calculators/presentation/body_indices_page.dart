import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/body_indices.dart';
import '../domain/calculation.dart';
import 'body_indices_cubit.dart';
import 'calculator_widgets.dart';
import 'widgets/calculator_result.dart';

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
            String index(double value) => format.number(value, decimals: 1);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: calculatorGap,
              children: [
                ListRowCard(
                  children: [
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
                      input: CalculatorInput.bodyFat,
                      format: format,
                      title: l10n.calcBodyFatResult,
                      label: l10n.calcBodyFatOptional,
                      unit: l10n.calcUnitPercent,
                      text: state.bodyFat,
                      known: state.known[CalculatorInput.bodyFat],
                      result: state.result,
                      onChanged: cubit.bodyFatChanged,
                    ),
                  ],
                ),
                switch (state.result) {
                  Calculated(:final value) => switch (value) {
                    BodyIndices(:final ffmi?, :final normalizedFfmi?) =>
                      CalculatorResult(
                        caption: l10n.calcBmi,
                        value: index(value.bmi),
                        rows: [
                          CalculatorRow(l10n.calcFfmi, index(ffmi)),
                          CalculatorRow(
                            l10n.calcNormalizedFfmi,
                            index(normalizedFfmi),
                          ),
                        ],
                        note: l10n.calcFfmiInfo,
                      ),
                    _ => CalculatorResult(
                      caption: l10n.calcBmi,
                      value: index(value.bmi),
                      note: l10n.calcFfmiNeedsBodyFat,
                    ),
                  },
                  null => CalculatorResult.missing(
                    caption: l10n.calcBmi,
                    note: format.addToSee([
                      if (state.weight.isEmpty) l10n.calcMissingBodyweight,
                      if (state.height.isEmpty) l10n.calcMissingHeight,
                    ]),
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
