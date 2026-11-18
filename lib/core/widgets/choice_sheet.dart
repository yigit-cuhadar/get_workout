import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

/// One answer of a choice sheet: a line above it, the radio and its
/// [label], with a muted [detail] under it if given; a tap picks it.
class ChoiceRow extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.label,
    this.detail,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  static const double _minHeight = 48;

  @override
  Widget build(BuildContext context) {
    final colors = ForgeStyle.of(context).colors;
    final text = Theme.of(context).textTheme;
    final detail = this.detail;
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
          padding: detail == null
              ? null
              : const EdgeInsets.symmetric(vertical: Gap.sm),
          child: Row(
            spacing: 12,
            children: [
              RadioMark(selected: selected),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(label, style: text.bodyLarge),
                    if (detail != null)
                      Text(
                        detail,
                        style: text.bodySmall!.copyWith(color: colors.inkMuted),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A [ForgeBottomSheet] titled [title], with [subtitle] under it if
/// given, offering [values] as [ChoiceRow]s,
/// [selected] marked, if any, each with its [detailOf] line if given; a
/// tap picks a value and closes it. Null when closed without a pick.
Future<T?> showChoiceSheet<T extends Object>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<T> values,
  required T? selected,
  required String Function(T value) labelOf,
  String? Function(T value)? detailOf,
}) => showForgeBottomSheet<T>(
  context: context,
  builder: (context) => ForgeBottomSheet(
    title: title,
    subtitle: subtitle,
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final value in values)
            ChoiceRow(
              label: labelOf(value),
              detail: detailOf?.call(value),
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
class ChoiceSettingRow<T extends Object> extends StatelessWidget {
  const ChoiceSettingRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.values,
    required this.selected,
    required this.labelOf,
    this.detailOf,
    required this.onChanged,
  });

  final String title;

  /// The sheet's line under its title.
  final String? subtitle;
  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;

  /// A value's line under it in the sheet.
  final String? Function(T value)? detailOf;
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
        subtitle: subtitle,
        values: values,
        selected: selected,
        labelOf: labelOf,
        detailOf: detailOf,
      );
      if (picked != null) onChanged(picked);
    },
  );
}
