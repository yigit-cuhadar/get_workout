import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../settings/domain/user_settings.dart';

/// A number field showing [value] (in display units), with [hint] while
/// empty. It keeps what the user types while that still means the stored
/// value, and shows [value] when that changes from elsewhere, e.g. a tick
/// filling in the suggestion.
class NumberCell extends StatefulWidget {
  const NumberCell({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint,
    this.label,
  }) : stored = value,
       toStored = null,
       decimal = false;

  /// A lifted weight stored as [kg], shown in [unit] as
  /// [WeightUnitConversion.shownFromKg] shows it.
  NumberCell.weight({
    super.key,
    required double? kg,
    required WeightUnit unit,
    required this.onChanged,
    this.hint,
    this.label,
  }) : value = kg == null ? null : unit.shownFromKg(kg),
       stored = kg,
       toStored = unit.toKg,
       decimal = true;

  final double? value;
  final String? hint;

  /// Shown above the field, so [hint] shows while it is empty.
  final String? label;
  final bool decimal;
  final ValueChanged<String> onChanged;

  /// What [value] stands for, and how a typed number is stored, when that
  /// differs from what is shown; null [toStored] stores numbers as typed.
  final double? stored;
  final double Function(double typed)? toStored;

  @override
  State<NumberCell> createState() => _NumberCellState();
}

/// The text a number cell holding [text] shows instead, or null to keep
/// it: kept while it stores as [stored] (or already reads as [value]).
String? numberCellText(
  String text, {
  required double? value,
  required double? stored,
  double Function(double typed)? toStored,
}) {
  final typed = double.tryParse(text.trim().replaceAll(',', '.'));
  final typedStored = typed == null ? null : toStored?.call(typed) ?? typed;
  final same = typedStored == null || stored == null
      ? typedStored == stored
      : (typedStored - stored).abs() < 1e-9;
  final shown = _numberText(value);
  return same || shown == text ? null : shown;
}

String _numberText(double? value) => value == null
    ? ''
    : value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

class _NumberCellState extends State<NumberCell> {
  late final _controller = TextEditingController(
    text: _numberText(widget.value),
  );

  @override
  void didUpdateWidget(NumberCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final text = numberCellText(
      _controller.text,
      value: widget.value,
      stored: widget.stored,
      toStored: widget.toStored,
    );
    if (text != null) _controller.text = text;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
    child: TextField(
      controller: _controller,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal),
      inputFormatters: [
        widget.decimal
            ? FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
            : FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(widget.decimal ? 7 : 5),
      ],
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint,
        labelText: widget.label,
        floatingLabelBehavior: widget.label == null
            ? null
            : FloatingLabelBehavior.always,
      ),
      onChanged: widget.onChanged,
    ),
  );
}
