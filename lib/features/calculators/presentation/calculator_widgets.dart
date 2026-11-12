import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/calories.dart';
import 'calculator_format.dart';

typedef Units = ({WeightUnit weight, LengthUnit length});

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
      appBar: AppBar(title: Text(title)),
      body: BlocProvider<C>(
        key: ValueKey(units),
        create: (_) => create(units),
        child: Builder(
          builder: (context) => ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: children(context, format),
          ),
        ),
      ),
    );
  }
}

/// A decimal or whole-number input that reports every change. A new
/// [value] other than the text typed, such as a value known only once
/// loaded, replaces the text.
// ForgeTextField has no onChanged or errorText yet, which live results need.
class NumberField extends StatefulWidget {
  const NumberField({
    super.key,
    required this.label,
    required this.onChanged,
    this.errorText,
    this.value = '',
    this.wholeNumber = false,
  });

  final String label;
  final ValueChanged<String> onChanged;
  final String? errorText;
  final String value;
  final bool wholeNumber;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.md),
    child: TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      keyboardType: TextInputType.numberWithOptions(
        decimal: !widget.wholeNumber,
      ),
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.errorText,
        errorMaxLines: 3,
      ),
    ),
  );
}

class SexSelector extends StatelessWidget {
  const SexSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Sex? selected;
  final ValueChanged<Sex> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: SegmentedButton<Sex>(
        segments: [
          ButtonSegment(value: Sex.male, label: Text(l10n.calcSexMale)),
          ButtonSegment(value: Sex.female, label: Text(l10n.calcSexFemale)),
        ],
        selected: {?selected},
        emptySelectionAllowed: true,
        onSelectionChanged: (selection) {
          if (selection.isNotEmpty) onChanged(selection.first);
        },
      ),
    );
  }
}

/// One result: what it is, its value, and an optional note.
class ResultTile extends StatelessWidget {
  const ResultTile({
    super.key,
    required this.label,
    required this.value,
    this.note,
  });

  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: note == null ? null : Text(note!),
    trailing: Text(value, style: Theme.of(context).textTheme.titleMedium),
  );
}

/// A problem with the inputs as a whole, shown where the result would be.
class InputProblem extends StatelessWidget {
  const InputProblem(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      message,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.error,
      ),
    );
  }
}

/// A short neutral explanation under a result.
class CalculatorNote extends StatelessWidget {
  const CalculatorNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.md),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}
