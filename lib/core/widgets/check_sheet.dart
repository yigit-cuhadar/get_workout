import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

/// One answer of a check sheet: its [label] with a checkbox at the end; a
/// tap anywhere on it ticks or unticks it.
class CheckRow extends StatelessWidget {
  const CheckRow({
    super.key,
    required this.label,
    required this.checked,
    required this.onChanged,
  });

  final String label;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: ListRow(
      title: label,
      trailing: ForgeCheckbox(value: checked, onChanged: onChanged),
      onTap: () => onChanged(!checked),
    ),
  );
}

/// A [ForgeBottomSheet] titled [title] offering [values] as [CheckRow]s,
/// lines between them, [selected] ticked, and a full-width [saveLabel]
/// button. Completes with the ticked values once saved, in [values]' order,
/// or null when closed without saving. It stacks over a sheet it is opened
/// from and returns to it.
Future<Set<T>?> showCheckSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<T> values,
  required Set<T> selected,
  required String Function(T value) labelOf,
  required String saveLabel,
}) => showForgeBottomSheet<Set<T>>(
  context: context,
  builder: (_) => CheckSheet<T>(
    title: title,
    subtitle: subtitle,
    values: values,
    initial: selected,
    labelOf: labelOf,
    saveLabel: saveLabel,
  ),
);

/// The sheet [showCheckSheet] opens; the ticks stay in it until Save.
class CheckSheet<T> extends StatefulWidget {
  const CheckSheet({
    super.key,
    required this.title,
    this.subtitle,
    required this.values,
    required this.initial,
    required this.labelOf,
    required this.saveLabel,
  });

  final String title;
  final String? subtitle;
  final List<T> values;
  final Set<T> initial;
  final String Function(T value) labelOf;
  final String saveLabel;

  @override
  State<CheckSheet<T>> createState() => _CheckSheetState<T>();
}

class _CheckSheetState<T> extends State<CheckSheet<T>> {
  late final Set<T> _ticked = {...widget.initial};

  @override
  Widget build(BuildContext context) => ForgeBottomSheet(
    title: widget.title,
    subtitle: widget.subtitle,
    action: ForgeButton(
      label: widget.saveLabel,
      size: ForgeButtonSize.large,
      onPressed: () => Navigator.pop(context, {
        for (final value in widget.values)
          if (_ticked.contains(value)) value,
      }),
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, value) in widget.values.indexed) ...[
            if (i > 0) const Divider(),
            CheckRow(
              label: widget.labelOf(value),
              checked: _ticked.contains(value),
              onChanged: (checked) => setState(
                () => checked ? _ticked.add(value) : _ticked.remove(value),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
