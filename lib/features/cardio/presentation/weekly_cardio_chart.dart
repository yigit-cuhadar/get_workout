import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/cardio_week.dart';
import 'cardio_text.dart';

/// Minutes per week as plain bars, oldest week first. A stand-in until the
/// Progress features choose a chart library.
class WeeklyCardioChart extends StatelessWidget {
  const WeeklyCardioChart({super.key, required this.weeks});

  final List<CardioWeek> weeks;

  /// Width to height of the bar area.
  static const _aspectRatio = 3.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dates = MaterialLocalizations.of(context);
    final longest = weeks.fold(
      Duration.zero,
      (longest, week) => week.duration > longest ? week.duration : longest,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.cardioChartCaption, style: theme.textTheme.labelLarge),
        const SizedBox(height: Gap.sm),
        AspectRatio(
          aspectRatio: _aspectRatio,
          child: Row(
            children: [
              for (final week in weeks)
                Expanded(
                  child: Tooltip(
                    message:
                        '${l10n.cardioWeekOf(dates.formatShortMonthDay(week.start))}'
                        ': ${l10n.cardioMinutesOf(week.duration)}',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          widthFactor: 1,
                          heightFactor: longest == Duration.zero
                              ? 0
                              : week.duration.inSeconds / longest.inSeconds,
                          child: ColoredBox(color: theme.colorScheme.primary),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Divider(),
        if (weeks.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                dates.formatShortMonthDay(weeks.first.start),
                style: theme.textTheme.labelSmall,
              ),
              Text(
                dates.formatShortMonthDay(weeks.last.start),
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
      ],
    );
  }
}
