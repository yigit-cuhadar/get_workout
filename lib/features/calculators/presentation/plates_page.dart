import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

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
          sl(),
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
              children: [
                NumberField(
                  label: l10n.calcTargetWeight(format.weightUnitLabel),
                  onChanged: context.read<PlatesCubit>().targetChanged,
                  errorText: format.errorFor(
                    CalculatorInput.targetWeight,
                    state.result,
                  ),
                ),
                if (state.result case Calculated(:final value))
                  _Load(value, format),
                const Divider(),
                _Equipment(state, format),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Load extends StatelessWidget {
  const _Load(this.load, this.format);

  final PlateLoad load;
  final CalculatorFormat format;

  @override
  Widget build(BuildContext context) {
    final l10n = format.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.calcPerSide, style: Theme.of(context).textTheme.titleSmall),
        if (load.perSide.isEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.calcBarOnly),
          ),
        for (final plate in load.perSide)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              l10n.calcPlateCount(
                plate.count,
                format.weight(plate.weightKg, maxDecimals: 2),
              ),
            ),
          ),
        ResultTile(label: l10n.calcTotal, value: format.weight(load.totalKg)),
        if (!load.exact) CalculatorNote(l10n.calcClosestBelow),
      ],
    );
  }
}

/// The bar and plate editor. Changes are saved to the user's settings.
class _Equipment extends StatelessWidget {
  const _Equipment(this.state, this.format);

  final PlatesState state;
  final CalculatorFormat format;

  @override
  Widget build(BuildContext context) {
    final l10n = format.l10n;
    final settingsCubit = context.read<SettingsCubit>();
    final cubit = context.read<PlatesCubit>();
    UserSettings settings() => settingsCubit.state.settings;
    final custom = context.select(
      (SettingsCubit cubit) =>
          cubit.state.settings.customBarWeightKg != null ||
          cubit.state.settings.customPlates != null,
    );

    Future<void> editPlate(Plate? plate) async {
      final plates = await showDialog<List<Plate>>(
        context: context,
        builder: (_) =>
            _PlateDialog(cubit: cubit, format: format, plate: plate),
      );
      if (plates != null) {
        await settingsCubit.update(settings().copyWith(customPlates: plates));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.calcEquipment, style: Theme.of(context).textTheme.titleSmall),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.calcBar),
          trailing: Text(format.weight(state.barKg)),
          onTap: () async {
            final barKg = await showDialog<double>(
              context: context,
              builder: (_) => _BarDialog(cubit: cubit, format: format),
            );
            if (barKg != null) {
              await settingsCubit.update(
                settings().copyWith(customBarWeightKg: barKg),
              );
            }
          },
        ),
        for (final plate in state.plates)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(format.weight(plate.weightKg, maxDecimals: 2)),
            trailing: Text(l10n.calcPairs(plate.pairs)),
            onTap: () => editPlate(plate),
          ),
        Wrap(
          children: [
            TextButton(
              onPressed: () => editPlate(null),
              child: Text(l10n.calcAddPlate),
            ),
            if (custom)
              TextButton(
                onPressed: () =>
                    settingsCubit.update(settings().withStandardEquipment()),
                child: Text(l10n.calcUseStandardSet),
              ),
          ],
        ),
      ],
    );
  }
}

class _BarDialog extends StatefulWidget {
  const _BarDialog({required this.cubit, required this.format});

  final PlatesCubit cubit;
  final CalculatorFormat format;

  @override
  State<_BarDialog> createState() => _BarDialogState();
}

class _BarDialogState extends State<_BarDialog> {
  late String _text = widget.format.editableWeight(widget.cubit.state.barKg);

  @override
  Widget build(BuildContext context) {
    final l10n = widget.format.l10n;
    final check = widget.cubit.checkBar(_text);
    return AlertDialog(
      title: Text(l10n.calcBar),
      content: NumberField(
        label: l10n.calcBarWeight(widget.format.weightUnitLabel),
        initialValue: _text,
        onChanged: (text) => setState(() => _text = text),
        errorText: widget.format.errorFor(CalculatorInput.barWeight, check),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: check is Calculated<double>
              ? () => Navigator.pop(context, check.value)
              : null,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

/// Adds a plate, or edits or removes [plate]. Pops with the new plate list.
class _PlateDialog extends StatefulWidget {
  const _PlateDialog({required this.cubit, required this.format, this.plate});

  final PlatesCubit cubit;
  final CalculatorFormat format;
  final Plate? plate;

  @override
  State<_PlateDialog> createState() => _PlateDialogState();
}

class _PlateDialogState extends State<_PlateDialog> {
  late String _weight = switch (widget.plate) {
    final plate? => widget.format.editableWeight(plate.weightKg),
    null => '',
  };
  late String _pairs = '${widget.plate?.pairs ?? 1}';

  @override
  Widget build(BuildContext context) {
    final format = widget.format;
    final l10n = format.l10n;
    final cubit = widget.cubit;
    final plate = widget.plate;
    final check = cubit.checkPlate(_weight, _pairs);
    return AlertDialog(
      title: Text(plate == null ? l10n.calcAddPlate : l10n.calcEditPlate),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NumberField(
            label: l10n.calcPlateWeight(format.weightUnitLabel),
            initialValue: _weight,
            onChanged: (text) => setState(() => _weight = text),
            errorText: format.errorFor(CalculatorInput.plateWeight, check),
          ),
          NumberField(
            label: l10n.calcPlatePairs,
            initialValue: _pairs,
            wholeNumber: true,
            onChanged: (text) => setState(() => _pairs = text),
            errorText: format.errorFor(CalculatorInput.platePairs, check),
          ),
        ],
      ),
      actions: [
        if (plate != null)
          TextButton(
            onPressed: () => Navigator.pop(context, cubit.withoutPlate(plate)),
            child: Text(l10n.calcRemovePlate),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: check is Calculated<Plate>
              ? () => Navigator.pop(
                  context,
                  cubit.withPlate(check.value, replacing: plate),
                )
              : null,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
