import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

/// One answer of a choice sheet: a line above it, the radio and its
/// [label]; a tap picks it.
class ChoiceRow extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  static const double _minHeight = 48;

  @override
  Widget build(BuildContext context) {
    final colors = ForgeStyle.of(context).colors;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: _minHeight),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.line)),
          ),
          child: Row(
            spacing: 12,
            children: [
              RadioMark(selected: selected),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A [ForgeBottomSheet] titled [title] offering [values] as [ChoiceRow]s,
/// [selected] marked; a tap picks a value and closes it. Null when closed
/// without a pick.
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<T> values,
  required T selected,
  required String Function(T value) labelOf,
}) => showForgeBottomSheet<T>(
  context: context,
  builder: (context) => ForgeBottomSheet(
    title: title,
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final value in values)
            ChoiceRow(
              label: labelOf(value),
              selected: value == selected,
              onTap: () => Navigator.pop(context, value),
            ),
        ],
      ),
    ),
  ),
);

/// A settings row showing the [selected] value of [values]; a tap offers
/// them in a choice sheet titled [title].
class ChoiceSettingRow<T> extends StatelessWidget {
  const ChoiceSettingRow({
    super.key,
    required this.title,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final String title;
  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => ListRow(
    title: title,
    value: labelOf(selected),
    end: ListRowEnd.chevron,
    onTap: () async {
      final picked = await showChoiceSheet(
        context,
        title: title,
        values: values,
        selected: selected,
        labelOf: labelOf,
      );
      if (picked != null) onChanged(picked);
    },
  );
}
