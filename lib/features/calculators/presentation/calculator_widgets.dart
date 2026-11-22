import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:intl/intl.dart';

import '../../../core/number_text.dart';
import '../../../core/widgets/choice_sheet.dart';
import '../../../core/widgets/number_sheet.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/calculation.dart';
import 'calculator_format.dart';
import 'calculator_input.dart';

typedef Units = ({WeightUnit weight, LengthUnit length});

/// Space between the parts of a calculator page.
const double calculatorGap = 10;

/// A calculator screen: creates its cubit for the user's current units and
/// recreates it, clearing the inputs, if they change.
class CalculatorScaffold<C extends Cubit<Object?>> extends StatelessWidget {
  const CalculatorScaffold({
    super.key,
    required this.title,
    required this.create,
    required this.children,
  });

  final String title;
  final C Function(Units units) create;
  final List<Widget> Function(BuildContext context, CalculatorFormat format)
  children;

  @override
  Widget build(BuildContext context) {
    final units = context.select(
      (SettingsCubit cubit) => (
        weight: cubit.state.settings.weightUnit,
        length: cubit.state.settings.lengthUnit,
      ),
    );
    final format = CalculatorFormat(
      AppLocalizations.of(context),
      weightUnit: units.weight,
      lengthUnit: units.length,
    );
    return Scaffold(
      appBar: ForgeAppBar(title: title),
      body: BlocProvider<C>(
        key: ValueKey(units),
        create: (_) => create(units),
        child: Builder(
          builder: (context) => ListView(
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.md),
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: calculatorGap,
                children: children(context, format),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A number input of a calculator as a chevron row: its [title], the
/// value with its [unit] or "—", and, while it holds the value the app
/// [known]s from the body log, the day it was measured. A tap opens a
/// number sheet titled [title] with a field labelled [label] (else the
/// title) and the unit in its box; what is saved there goes to
/// [onChanged] as text, empty when cleared. The row's line says what is
/// wrong with the value for [result].
class CalculatorInputRow extends StatelessWidget {
  const CalculatorInputRow({
    super.key,
    required this.input,
    required this.format,
    required this.title,
    this.label,
    required this.text,
    required this.onChanged,
    this.unit,
    this.known,
    this.result,
  });

  final CalculatorInput input;
  final CalculatorFormat format;
  final String title;
  final String? label;
  final String text;
  final ValueChanged<String> onChanged;
  final String? unit;
  final KnownInput? known;
  final Calculation<Object?>? result;

  @override
  Widget build(BuildContext context) {
    final l10n = format.l10n;
    final value = readNumber(text);
    final shown = value == null || value.isNaN
        ? null
        : format.shown(input, value);
    final date = known?.date;
    return ListRow(
      title: title,
      detail: date == null ? null : l10n.calcMeasuredOn(_day(date, l10n)),
      error: format.errorFor(input, result),
      value: switch ((shown, unit)) {
        (null, _) => l10n.bodyNoValue,
        (final shown?, null) => shown,
        (final shown?, final unit?) => l10n.calcKnownValue(shown, unit),
      },
      end: ListRowEnd.chevron,
      onTap: () => _pick(context, value),
    );
  }

  Future<void> _pick(BuildContext context, double? value) async {
    final bounds = format.boundsOf(input);
    final picked = await showNumberSheet(
      context,
      title: title,
      label: label ?? title,
      unit: unit,
      bounds: bounds,
      error: format.rangeError(input),
      value: value == null || value.isNaN ? null : value,
    );
    if (picked == null) return;
    final next = switch (picked.value) {
      final value? => formatDecimal(value, bounds.decimals),
      null => '',
    };
    if (next != text) onChanged(next);
  }

  /// The year only when it is not this one.
  static String _day(DateTime date, AppLocalizations l10n) =>
      (date.year == DateTime.now().year
              ? DateFormat.MMMd(l10n.localeName)
              : DateFormat.yMMMd(l10n.localeName))
          .format(date);
}

/// A choice input of a calculator as a chevron row: its [title] and the
/// [selected] value's label, or "—"; a tap offers [values] in a choice
/// sheet.
class CalculatorChoiceRow<T extends Object> extends StatelessWidget {
  const CalculatorChoiceRow({
    super.key,
    required this.title,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final String title;
  final List<T> values;
  final T? selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = this.selected;
    return ListRow(
      title: title,
      value: selected == null
          ? AppLocalizations.of(context).bodyNoValue
          : labelOf(selected),
      end: ListRowEnd.chevron,
      onTap: () async {
        final picked = await showChoiceSheet(
          context,
          title: title,
          values: values,
          selected: selected,
          labelOf: labelOf,
        );
        if (picked != null && picked != selected) onChanged(picked);
      },
    );
  }
}

/// A problem with the inputs as a whole, shown where the result would be.
class InputProblem extends StatelessWidget {
  const InputProblem(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodySmall!
          .copyWith(color: ForgeStyle.of(context).colors.danger),
    ),
  );
}

/// A short muted explanation on a calculator page.
class CalculatorNote extends StatelessWidget {
  const CalculatorNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall!
          .copyWith(color: ForgeStyle.of(context).colors.inkMuted),
    ),
  );
}
