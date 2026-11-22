import 'package:material_ui/material_ui.dart';
import 'package:forge_ui/forge_ui.dart';

/// One row of a [CalculatorResult]: its [label] and [value], and a muted
/// [note] under the label when the figure needs one.
class CalculatorRow {
  const CalculatorRow(this.label, this.value, {this.note});

  final String label;
  final String value;
  final String? note;
}

/// The result card of a calculator: a [caption], the main figure ([value])
/// in mono, then [rows], one per goal or breakdown, and a muted [note]
/// under everything. [CalculatorResult.missing] stands in while an input is
/// missing: "—" and what to add ([note]).
class CalculatorResult extends StatelessWidget {
  const CalculatorResult({
    super.key,
    required this.caption,
    required String this.value,
    this.rows = const [],
    this.note,
  });

  const CalculatorResult.missing({
    super.key,
    required this.caption,
    required String this.note,
  }) : value = null,
       rows = const [];

  final String caption;
  final String? value;
  final List<CalculatorRow> rows;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final colors = style.colors;
    final text = Theme.of(context).textTheme;
    final value = this.value;
    final note = this.note;
    final captionText = Text(
      caption,
      style: text.labelMedium!.copyWith(
        fontWeight: FontWeight.w400,
        color: colors.inkMuted,
      ),
    );
    final missing = value == null;
    return Container(
      decoration: _card(style),
      padding: missing
          ? const EdgeInsets.fromLTRB(Gap.md, 14, Gap.md, Gap.md)
          : const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: missing ? 12 : Gap.sm,
        children: [
          captionText,
          Text(
            value ?? '—',
            style: style.dataLg.copyWith(
              fontSize: missing ? 28 : 30,
              height: 1.2,
              color: missing ? colors.inkSubtle : colors.ink,
            ),
          ),
          if (rows.isNotEmpty)
            Container(
              decoration: _card(style),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (i, row) in rows.indexed)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: i == 0
                          ? null
                          : BoxDecoration(
                              border: Border(
                                top: BorderSide(color: colors.line),
                              ),
                            ),
                      child: Row(
                        spacing: 10,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(row.label, style: text.bodySmall),
                                if (row.note case final note?)
                                  Text(
                                    note,
                                    style: text.labelMedium!.copyWith(
                                      fontWeight: FontWeight.w400,
                                      color: colors.inkMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            row.value,
                            style: style.data.copyWith(
                              fontSize: 13,
                              color: colors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (note != null)
            Text(note, style: text.bodySmall!.copyWith(color: colors.inkMuted)),
        ],
      ),
    );
  }

  static BoxDecoration _card(ForgeStyle style) => BoxDecoration(
    color: style.colors.surface,
    borderRadius: BorderRadius.circular(style.radii.lg),
    border: style.cardBorder == 0
        ? null
        : Border.all(color: style.colors.line, width: style.cardBorder),
  );
}
