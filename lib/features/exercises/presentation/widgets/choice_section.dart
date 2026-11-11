import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

/// A titled group of filter chips, any number selected. [error] shows
/// under the chips.
class ChoiceSection<T> extends StatelessWidget {
  const ChoiceSection({
    super.key,
    required this.title,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onToggle,
    this.error,
  });

  final String title;
  final List<T> values;
  final Set<T> selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onToggle;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = this.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(dense: true, title: Text(title)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
          child: Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.xs,
            children: [
              for (final value in values)
                FilterChip(
                  label: Text(labelOf(value)),
                  selected: selected.contains(value),
                  onSelected: (_) => onToggle(value),
                ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, 0),
            child: Text(
              error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}
