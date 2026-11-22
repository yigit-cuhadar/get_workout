import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../core/widgets/settings_group.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/calculation.dart';
import 'bar_plates_cubit.dart';
import 'calculator_format.dart';

/// The user's bars (barbell, EZ bar, trap bar) and plates, used by the
/// Plates calculator and the workout's plate breakdown. Every change is
/// saved at once. Needs [SettingsCubit] above it.
class BarPlatesPage extends StatelessWidget {
  const BarPlatesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final units = context.select(
      (SettingsCubit cubit) => (
        weight: cubit.state.settings.weightUnit,
        length: cubit.state.settings.lengthUnit,
      ),
    );
    final unit = units.weight;
    return Scaffold(
      appBar: ForgeAppBar(title: l10n.settingsBarPlates),
      body: BlocProvider(
        key: ValueKey(unit),
        create: (context) => BarPlatesCubit(
          sl(),
          sl(),
          weightUnit: unit,
          plates: context.read<SettingsCubit>().state.settings.plates,
        ),
        child: BlocListener<SettingsCubit, SettingsState>(
          listenWhen: (previous, current) =>
              previous.settings.plates != current.settings.plates,
          listener: (context, state) => context
              .read<BarPlatesCubit>()
              .platesChanged(state.settings.plates),
          child: _Equipment(
            CalculatorFormat(l10n, weightUnit: unit, lengthUnit: units.length),
          ),
        ),
      ),
    );
  }
}

class _Equipment extends StatelessWidget {
  const _Equipment(this.format);

  final CalculatorFormat format;

  @override
  Widget build(BuildContext context) {
    final l10n = format.l10n;
    final settingsCubit = context.read<SettingsCubit>();
    final settings = context.select(
      (SettingsCubit cubit) => cubit.state.settings,
    );
    final plates = context.watch<BarPlatesCubit>().state;
    final custom =
        settings.customBarWeightKg != null ||
        settings.customEzBarWeightKg != null ||
        settings.customTrapBarWeightKg != null ||
        settings.customPlates != null;

    Future<void> editBar(Equipment bar, String name) async {
      final kg = await showForgeDialog<double>(
        context: context,
        builder: (_) => _BarDialog(
          cubit: context.read<BarPlatesCubit>(),
          format: format,
          title: name,
          kg: settings.barWeightKgFor(bar),
        ),
      );
      if (kg != null) {
        await settingsCubit.update(
          settingsCubit.state.settings.withBarWeight(bar, kg),
        );
      }
    }

    Future<void> editPlate(Plate? plate) async {
      final edited = await showForgeBottomSheet<List<Plate>>(
        context: context,
        builder: (_) => _PlateSheet(
          cubit: context.read<BarPlatesCubit>(),
          format: format,
          plate: plate,
        ),
      );
      if (edited != null) {
        await settingsCubit.update(
          settingsCubit.state.settings.copyWith(customPlates: edited),
        );
      }
    }

    Widget barRow(Equipment bar, String name) => ListRow(
      title: name,
      value: format.weight(settings.barWeightKgFor(bar), maxDecimals: 2),
      end: ListRowEnd.chevron,
      onTap: () => editBar(bar, name),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.md),
      children: [
        SettingsColumn(
          children: [
            SettingsGroup(
              title: l10n.barPlatesBars,
              rows: [
                barRow(Equipment.barbell, l10n.barPlatesBarbell),
                barRow(Equipment.ezBar, l10n.barPlatesEzBar),
                barRow(Equipment.trapBar, l10n.barPlatesTrapBar),
              ],
            ),
            SettingsGroup(
              title: l10n.barPlatesPlates,
              rows: [
                for (final plate in plates)
                  ListRow(
                    title: format.weight(plate.weightKg, maxDecimals: 2),
                    value: l10n.calcPairs(plate.pairs),
                    end: ListRowEnd.chevron,
                    onTap: () => editPlate(plate),
                  ),
              ],
            ),
            if (plates.length < maxPlateSizes)
              ForgeAddButton(
                label: l10n.calcAddPlate,
                onPressed: () => editPlate(null),
              ),
            if (custom)
              ForgeButton(
                label: l10n.calcUseStandardSet,
                variant: ForgeButtonVariant.text,
                onPressed: () => settingsCubit.update(
                  settingsCubit.state.settings.withStandardEquipment(),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Edits one bar's weight; pops with it in kg.
class _BarDialog extends StatefulWidget {
  const _BarDialog({
    required this.cubit,
    required this.format,
    required this.title,
    required this.kg,
  });

  final BarPlatesCubit cubit;
  final CalculatorFormat format;
  final String title;
  final double kg;

  @override
  State<_BarDialog> createState() => _BarDialogState();
}

class _BarDialogState extends State<_BarDialog> {
  late final _text = TextEditingController(
    text: widget.format.editableWeight(widget.kg),
  );
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final format = widget.format;
    final l10n = format.l10n;
    return Form(
      key: _form,
      child: ForgeDialog(
        title: widget.title,
        message: l10n.barPlatesBarMessage,
        field: ForgeTextField(
          label: l10n.calcBarWeight(format.weightUnitLabel),
          controller: _text,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          validator: (text) => format.errorFor(
            CalculatorInput.barWeight,
            // Empty reads as out of range, which says what is allowed.
            widget.cubit.checkBar((text ?? '').trim().isEmpty ? '-1' : text!),
          ),
        ),
        action: ForgeButton(
          label: l10n.save,
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            final check = widget.cubit.checkBar(_text.text);
            if (check case Calculated(:final value)) {
              Navigator.pop(context, value);
            }
          },
        ),
        cancel: ForgeButton(
          label: l10n.cancel,
          variant: ForgeButtonVariant.secondary,
          onPressed: () => Navigator.pop(context),
        ),
      ),
    );
  }
}

/// Adds a plate, or edits or removes [plate]; pops with the new plate list.
class _PlateSheet extends StatefulWidget {
  const _PlateSheet({required this.cubit, required this.format, this.plate});

  final BarPlatesCubit cubit;
  final CalculatorFormat format;
  final Plate? plate;

  @override
  State<_PlateSheet> createState() => _PlateSheetState();
}

class _PlateSheetState extends State<_PlateSheet> {
  late final _weight = TextEditingController(
    text: switch (widget.plate) {
      final plate? => widget.format.editableWeight(plate.weightKg),
      null => '',
    },
  );
  late final _pairs = TextEditingController(
    text: '${widget.plate?.pairs ?? 1}',
  );
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _weight.dispose();
    _pairs.dispose();
    super.dispose();
  }

  /// The check of both fields; an empty one reads as out of range.
  Calculation<Plate>? _check() => widget.cubit.checkPlate(
    _weight.text.trim().isEmpty ? '0' : _weight.text,
    _pairs.text.trim().isEmpty ? '-1' : _pairs.text,
  );

  @override
  Widget build(BuildContext context) {
    final format = widget.format;
    final l10n = format.l10n;
    final cubit = widget.cubit;
    final plate = widget.plate;
    return Form(
      key: _form,
      child: ForgeBottomSheet(
        title: plate == null ? l10n.calcAddPlate : l10n.calcEditPlate,
        headerAction: plate == null
            ? null
            : ForgeButton(
                label: l10n.calcRemovePlate,
                variant: ForgeButtonVariant.dangerText,
                onPressed: () =>
                    Navigator.pop(context, cubit.withoutPlate(plate)),
              ),
        action: ForgeButton(
          label: l10n.save,
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            if (_check() case Calculated(:final value)) {
              Navigator.pop(context, cubit.withPlate(value, replacing: plate));
            }
          },
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Gap.md,
          children: [
            ForgeTextField(
              label: l10n.calcPlateWeight(format.weightUnitLabel),
              controller: _weight,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofocus: true,
              validator: (_) =>
                  format.errorFor(CalculatorInput.plateWeight, _check()),
            ),
            ForgeTextField(
              label: l10n.calcPlatePairs,
              controller: _pairs,
              keyboardType: TextInputType.number,
              validator: (_) =>
                  format.errorFor(CalculatorInput.platePairs, _check()),
            ),
          ],
        ),
      ),
    );
  }
}
