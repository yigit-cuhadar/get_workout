import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../programs/domain/calendar_date.dart';

/// A month as rows of [weeks] under the weekday names, one tappable cell
/// per date with the [marks] of that date below its number. Dates outside
/// [month]'s month are dimmed; [today] is outlined and [selected] filled.
/// One week without a [month] is a week strip, nothing dimmed.
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.weeks,
    this.month,
    required this.selected,
    required this.today,
    required this.onSelected,
    required this.marks,
    required this.semanticLabel,
  });

  /// Each seven dates; see `monthWeeks`.
  final List<List<CalendarDate>> weeks;
  final CalendarDate? month;
  final CalendarDate selected;
  final CalendarDate today;
  final ValueChanged<CalendarDate> onSelected;

  /// Small marks for a date, e.g. coloured icons; shown in one row.
  final List<Widget> Function(CalendarDate date) marks;

  /// What a screen reader says for a date, its marks included.
  final String Function(CalendarDate date) semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final names = MaterialLocalizations.of(context).narrowWeekdays;
    final month = this.month;
    return Column(
      children: [
        ExcludeSemantics(
          child: Row(
            children: [
              // Index 0 is Sunday, ISO weekday 7.
              for (final date in weeks.first)
                Expanded(
                  child: Center(
                    child: Text(
                      names[date.weekday % 7],
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Gap.xs),
        for (final week in weeks)
          Row(
            children: [
              for (final date in week)
                Expanded(
                  child: _DayCell(
                    date: date,
                    inMonth: month == null || date.month == month.month,
                    selected: date == selected,
                    today: date == today,
                    marks: marks(date),
                    semanticLabel: semanticLabel(date),
                    onTap: () => onSelected(date),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.inMonth,
    required this.selected,
    required this.today,
    required this.marks,
    required this.semanticLabel,
    required this.onTap,
  });

  final CalendarDate date;
  final bool inMonth;
  final bool selected;
  final bool today;
  final List<Widget> marks;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: selected
          ? colors.onPrimary
          : inMonth
          ? colors.onSurface
          : colors.outline,
    );
    return Semantics(
      label: semanticLabel,
      selected: selected,
      button: true,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.xs),
          child: Column(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? colors.primary : null,
                  border: today && !selected
                      ? Border.all(color: colors.primary)
                      : null,
                ),
                child: SizedBox.square(
                  dimension: Gap.xl,
                  child: Center(child: Text('${date.day}', style: textStyle)),
                ),
              ),
              const SizedBox(height: Gap.xs),
              SizedBox(
                height: Gap.sm,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: marks,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
