import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';

/// Compares two values of a sorted column: [ascending] or not, but an unset
/// value (null) always last.
int compareBlanksLast<T extends Comparable<Object?>>(
  T? a,
  T? b, {
  required bool ascending,
}) => switch ((a, b)) {
  (null, null) => 0,
  (null, _) => 1,
  (_, null) => -1,
  (final T x, final T y) => ascending ? x.compareTo(y) : y.compareTo(x),
};

/// A table column's header: a tap sorts the table by the column, and the
/// column it is sorted by shows an arrow for the direction.
class SortHeader extends StatelessWidget {
  const SortHeader({
    super.key,
    required this.label,
    required this.ascending,
    required this.onTap,
  });

  final String label;

  /// The direction when the table is sorted by this column, else null.
  final bool? ascending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: ForgeStyle.of(context).colors.inkMuted);
    return Semantics(
      button: true,
      selected: ascending != null,
      child: InkWell(
        onTap: onTap,
        child: Row(
          spacing: Gap.xs,
          children: [
            Flexible(child: Text(label, style: style)),
            if (ascending case final ascending?)
              Icon(
                ascending ? Icons.arrow_upward : Icons.arrow_downward,
                size: style?.fontSize,
                color: style?.color,
                semanticLabel: ascending ? 'ascending' : 'descending',
              ),
          ],
        ),
      ),
    );
  }
}
