import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../l10n/app_localizations.dart';
import '../number_text.dart';

/// The range a number sheet accepts and how many decimals it takes.
class NumberBounds {
  const NumberBounds(this.min, this.max, {this.decimals = 0});

  final double min;
  final double max;
  final int decimals;
}

/// A sheet titled [title] to type a value in a field labelled [label],
/// its [unit] inside the box after the value: Clear in the header while there is a [value], and a full-width Save,
/// which keeps the sheet open with [error] in the field for a value outside
/// [bounds]. Saving an empty field clears the value. Null when closed
/// without either.
Future<({double? value})?> showNumberSheet(
  BuildContext context, {
  required String title,
  required String label,
  required String? unit,
  required NumberBounds bounds,
  required String error,
  required double? value,
}) => showForgeBottomSheet<({double? value})>(
  context: context,
  builder: (_) => _NumberSheet(
    title: title,
    label: label,
    unit: unit,
    bounds: bounds,
    error: error,
    value: value,
  ),
);

class _NumberSheet extends StatefulWidget {
  const _NumberSheet({
    required this.title,
    required this.label,
    required this.unit,
    required this.bounds,
    required this.error,
    required this.value,
  });

  final String title;
  final String label;
  final String? unit;
  final NumberBounds bounds;
  final String error;
  final double? value;

  @override
  State<_NumberSheet> createState() => _NumberSheetState();
}

class _NumberSheetState extends State<_NumberSheet> {
  late final _controller = TextEditingController(
    text: switch (widget.value) {
      final value? => formatDecimal(value, widget.bounds.decimals),
      null => '',
    },
  );
  bool _invalid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final bounds = widget.bounds;
    final read = readNumber(_controller.text);
    if (read == null) {
      Navigator.pop(context, (value: null));
      return;
    }
    // NaN fails both comparisons.
    if (!(read >= bounds.min - 1e-9 && read <= bounds.max + 1e-9) ||
        (bounds.decimals == 0 && read != read.roundToDouble())) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.pop(context, (value: read));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final signed = widget.bounds.min < 0;
    final decimal = widget.bounds.decimals > 0;
    return ForgeBottomSheet(
      title: widget.title,
      headerAction: widget.value == null
          ? null
          : ForgeButton(
              label: l10n.clear,
              variant: ForgeButtonVariant.text,
              onPressed: () => Navigator.pop(context, (value: null)),
            ),
      action: ForgeButton(
        label: l10n.save,
        size: ForgeButtonSize.large,
        onPressed: _save,
      ),
      child: ForgeTextField(
        label: widget.label,
        unit: widget.unit,
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(
          decimal: decimal,
          signed: signed,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            RegExp('[0-9${decimal ? '.,' : ''}${signed ? '-' : ''}]'),
          ),
          LengthLimitingTextInputFormatter(7),
        ],
        errorText: _invalid ? widget.error : null,
        textInputAction: TextInputAction.done,
        onChanged: (_) {
          if (_invalid) setState(() => _invalid = false);
        },
        onSubmitted: (_) => _save(),
      ),
    );
  }
}
