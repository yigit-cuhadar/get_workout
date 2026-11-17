import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/number_text.dart';
import '../../../core/page_parts.dart';
import '../../../core/widgets/plate_calculator.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/calculation.dart';
import '../domain/plates.dart';
import 'calculator_format.dart';
import 'calculator_widgets.dart';
import 'plates_cubit.dart';

class PlatesPage extends StatelessWidget {
  const PlatesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CalculatorScaffold<PlatesCubit>(
      title: l10n.calcPlatesTitle,
      create: (units) {
        final settings = context.read<SettingsCubit>().state.settings;
        return PlatesCubit(
          sl(),
          weightUnit: units.weight,
          barKg: settings.barWeightKg,
          plates: settings.plates,
        );
      },
      children: (context, format) => [
        BlocListener<SettingsCubit, SettingsState>(
          listenWhen: (previous, current) =>
              previous.settings != current.settings,
          listener: (context, state) =>
              context.read<PlatesCubit>().equipmentChanged(
                state.settings.barWeightKg,
                state.settings.plates,
              ),
          child: BlocBuilder<PlatesCubit, PlatesState>(
            builder: (context, state) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: calculatorGap,
              children: [
                ListRowCard(
                  children: [
                    CalculatorInputRow(
                      input: CalculatorInput.targetWeight,
                      format: format,
                      title: l10n.calcTargetWeightTitle,
                      label: l10n.calcTargetWeight(format.weightUnitLabel),
                      unit: format.weightUnitLabel,
                      text: state.target,
                      result: state.result,
                      onChanged: context.read<PlatesCubit>().targetChanged,
                    ),
                  ],
                ),
                if (state.result case Calculated(:final value))
                  _Load(
                    value,
                    format,
                    target: format.weightUnit.toKg(readNumber(state.target)!),
                    barKg: state.barKg,
                  ),
                _Equipment(state, format),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The load as a [PlateCalculator]; the closest one below the [target]
/// (in kg) when the plates can't make it.
class _Load extends StatelessWidget {
  const _Load(
    this.load,
    this.format, {
    required this.target,
    required this.barKg,
  });

  final PlateLoad load;
  final CalculatorFormat format;
  final double target;
  final double barKg;

  @override
  Widget build(BuildContext context) {
    final plates = [
      for (final plate in load.perSide)
        PlateStack(
          kg: plate.weightKg,
          weight: format.weight(plate.weightKg, maxDecimals: 2),
          short: format.weightNumber(plate.weightKg, maxDecimals: 2),
          count: plate.count,
        ),
    ];
    if (!load.exact) {
      return PlateCalculator.closest(
        target: format.weight(target),
        closest: format.weight(load.totalKg),
        plates: plates,
      );
    }
    return PlateCalculator(
      target: format.weight(load.totalKg),
      bar: format.weight(barKg),
      plates: plates,
      perSide: format.weight((load.totalKg - barKg) / 2, maxDecimals: 2),
    );
  }
}

/// The bar and plates the calculator uses, opening their settings page.
class _Equipment extends StatelessWidget {
  const _Equipment(this.state, this.format);

  final PlatesState state;
  final CalculatorFormat format;

  @override
  Widget build(BuildContext context) {
    final l10n = format.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(l10n.calcEquipment),
        const SizedBox(height: calculatorGap - Gap.xs),
        ListRowCard(
          children: [
            ListRow(
              title: l10n.settingsBarPlates,
              detail: l10n.calcEquipmentSummary(
                format.weight(state.barKg, maxDecimals: 2),
                state.plates.length,
              ),
              end: ListRowEnd.chevron,
              onTap: () => context.push(Routes.barPlates),
            ),
          ],
        ),
      ],
    );
  }
}
