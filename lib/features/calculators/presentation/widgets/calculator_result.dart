import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

/// The result card of a calculator: a [caption], the main figure ([value])
/// in mono, then [rows], one per goal or breakdown, each its label and
/// value. [CalculatorResult.missing] stands in while an input is missing:
/// "—" and what to add ([message]).
class CalculatorResult extends StatelessWidget {
  const CalculatorResult({
    super.key,
    required this.caption,
    required String this.value,
    this.rows = const [],
  }) : message = null;

  const CalculatorResult.missing({
    super.key,
    required this.caption,
    required String this.message,
  }) : value = null,
       rows = const [];

  final String caption;
  final String? value;
  final List<(String, String)> rows;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final colors = style.colors;
    final text = Theme.of(context).textTheme;
    final value = this.value;
    final message = this.message;
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
          if (message != null)
            Text(
              message,
              style: text.bodySmall!.copyWith(color: colors.inkMuted),
            ),
          if (rows.isNotEmpty)
            Container(
              decoration: _card(style),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (i, (label, figure)) in rows.indexed)
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
                          Expanded(child: Text(label, style: text.bodySmall)),
                          Text(
                            figure,
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
