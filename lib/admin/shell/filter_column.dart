import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';

/// The width of a list page's filter column.
const filterColumnWidth = 240.0;

/// A list page's filters in a card on the left of its table: each child is
/// a [FilterRadios], a [FilterDropdown] or a [FilterSwitch]. With
/// [onClear], the header offers "Clear filters".
class FilterColumn extends StatelessWidget {
  const FilterColumn({super.key, required this.children, this.onClear});

  final List<Widget> children;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: filterColumnWidth,
      child: SingleChildScrollView(
        child: SectionCard.plain(
          title: 'Filters',
          actionLabel: onClear == null ? null : 'Clear filters',
          onAction: onClear,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Gap.md,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// One choice of a filter: its [value] (null for "any") and [label].
typedef FilterOption<T> = ({T? value, String label});

/// A filter whose few options are all shown, one picked.
class FilterRadios<T> extends StatelessWidget {
  const FilterRadios({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<FilterOption<T>> options;
  final T? selected;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        for (final option in options)
          Semantics(
            selected: option.value == selected,
            child: InkWell(
              onTap: () => onChanged(option.value),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                child: Row(
                  spacing: Gap.sm,
                  children: [
                    RadioMark(selected: option.value == selected),
                    Expanded(child: Text(option.label)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A filter with many options, picked from a menu.
class FilterDropdown<T> extends StatelessWidget {
  const FilterDropdown({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<FilterOption<T>> options;
  final T? selected;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.xs,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        DropdownButtonFormField<T?>(
          initialValue: selected,
          isExpanded: true,
          items: [
            for (final option in options)
              DropdownMenuItem(value: option.value, child: Text(option.label)),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// A filter that is on or off.
class FilterSwitch extends StatelessWidget {
  const FilterSwitch({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Row(
        spacing: Gap.sm,
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          ForgeSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
