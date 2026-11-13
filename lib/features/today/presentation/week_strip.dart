import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../calendar/presentation/calendar_marks.dart';
import '../../calendar/presentation/month_grid.dart';
import 'today_week_cubit.dart';

/// The [TodayWeekCubit]'s week as one calendar row, each day opening
/// [onOpen]; while loading the dates show without marks, as on the
/// calendar, and a failure offers a retry below: [onRetry], or the week's
/// own.
class WeekStrip extends StatelessWidget {
  const WeekStrip({super.key, required this.onOpen, this.onRetry});

  final VoidCallback onOpen;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<TodayWeekCubit>().state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.sm, 0, Gap.sm, Gap.sm),
          child: MonthGrid(
            weeks: [state.days],
            selected: state.today,
            today: state.today,
            onSelected: (_) => onOpen(),
            marks: (date) => calendarMarkIcons(context, state.entriesOn(date)),
            semanticLabel: (date) =>
                calendarDayLabel(context, date, state.entriesOn(date)),
          ),
        ),
        if (state.status == TodayWeekStatus.failure)
          ErrorView(
            message: l10n.todayWeekLoadFailed,
            retryLabel: l10n.retry,
            onRetry: onRetry ?? context.read<TodayWeekCubit>().retry,
          ),
      ],
    );
  }
}
