import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';

/// A [ForgeBottomSheet] titled [title], with [subtitle] under it if
/// given, offering [values] as a [ChoiceGrid.list], [selected] marked, if
/// any, each with its [detailOf] line if given (under it, unless [form]
/// puts it beside); a tap picks a value and closes it. Null when closed
/// without a pick.
Future<T?> showChoiceSheet<T extends Object>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<T> values,
  required T? selected,
  required String Function(T value) labelOf,
  String? Function(T value)? detailOf,
  ChoiceListForm? form,
}) => showForgeBottomSheet<T>(
  context: context,
  builder: (context) {
    final details = [for (final value in values) detailOf?.call(value)];
    final index = selected == null ? -1 : values.indexOf(selected);
    return ForgeBottomSheet(
      title: title,
      subtitle: subtitle,
      child: SingleChildScrollView(
        child: ChoiceGrid.list(
          form:
              form ??
              (details.any((detail) => detail != null)
                  ? ChoiceListForm.stacked
                  : ChoiceListForm.inline),
          options: [
            for (final (i, value) in values.indexed)
              ChoiceOption(label: labelOf(value), hint: details[i]),
          ],
          selected: index < 0 ? null : index,
          onSelected: (i) => Navigator.pop(context, values[i]),
        ),
      ),
    );
  },
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
