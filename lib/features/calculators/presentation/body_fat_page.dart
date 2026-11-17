import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/calculation.dart';
import '../domain/calories.dart';
import 'body_fat_cubit.dart';
import 'calculator_format.dart';
import 'calculator_widgets.dart';
import 'widgets/calculator_result.dart';

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
            final male = state.sex == Sex.male;
            final female = state.sex == Sex.female;
            final problem = format.generalError(state.result);
            CalculatorInputRow row(
              CalculatorInput input, {
              required String title,
              required String label,
              required String text,
              required ValueChanged<String> onChanged,
            }) => CalculatorInputRow(
              input: input,
              format: format,
              title: title,
              label: label,
              unit: unit,
              text: text,
              known: state.known[input],
              result: state.result,
              onChanged: onChanged,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: calculatorGap,
              children: [
                ForgeSegmentedControl<Sex?>(
                  segments: [
                    for (final sex in Sex.values)
                      ForgeSegment(value: sex, label: l10n.calcSexLabel(sex)),
                  ],
                  selected: state.sex,
                  onChanged: (sex) => cubit.sexChanged(sex!),
                ),
                ListRowCard(
                  children: [
                    row(
                      CalculatorInput.height,
                      title: l10n.calcKnownHeight,
                      label: l10n.calcHeight(unit),
                      text: state.height,
                      onChanged: cubit.heightChanged,
                    ),
                    row(
                      CalculatorInput.neck,
                      title: l10n.calcKnownNeck,
                      label: l10n.calcNeck(unit),
                      text: state.neck,
                      onChanged: cubit.neckChanged,
                    ),
                    row(
                      CalculatorInput.waist,
                      title: male ? l10n.calcKnownAbdomen : l10n.calcKnownWaist,
                      label: male
                          ? l10n.calcWaistAtNavel(unit)
                          : l10n.calcWaist(unit),
                      text: state.waist,
                      onChanged: cubit.waistChanged,
                    ),
                    if (female)
                      row(
                        CalculatorInput.hip,
                        title: l10n.calcKnownHips,
                        label: l10n.calcHip(unit),
                        text: state.hip,
                        onChanged: cubit.hipChanged,
                      ),
                  ],
                ),
                if (problem != null)
                  InputProblem(problem)
                else
                  switch (state.result) {
                    Calculated(:final value) => CalculatorResult(
                      caption: l10n.calcBodyFatResult,
                      value: l10n.calcPercent(
                        format.number(value, decimals: 1),
                      ),
                    ),
                    null => CalculatorResult.missing(
                      caption: l10n.calcBodyFatResult,
                      note: format.addToSee([
                        if (state.sex == null) l10n.calcMissingSex,
                        if (state.height.isEmpty) l10n.calcMissingHeight,
                        if (state.neck.isEmpty) l10n.calcMissingNeck,
                        if (state.waist.isEmpty)
                          male
                              ? l10n.calcMissingAbdomen
                              : l10n.calcMissingWaist,
                        if (female && state.hip.isEmpty) l10n.calcMissingHips,
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
