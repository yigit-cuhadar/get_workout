import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../calendar/presentation/calendar_marks.dart';
import '../../programs/domain/calendar_date.dart';
import 'today_week_cubit.dart';

/// The [TodayWeekCubit]'s week as day circles in a SectionCard; it, and
/// every day of it, opens the calendar, which has no route for a given
/// date. Today calls it "This week"; with [range] it is the Progress
/// tab's "Calendar" card, the week's dates as its detail.
class WeekCard extends StatelessWidget {
  const WeekCard({super.key}) : range = false;

  const WeekCard.range({super.key}) : range = true;

  final bool range;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final weekdays = MaterialLocalizations.of(context).narrowWeekdays;
    final state = context.watch<TodayWeekCubit>().state;
    void open() => context.go(Routes.calendar);
    final title = range ? l10n.progressCalendar : l10n.todayWeekTitle;
    return switch (state.status) {
      TodayWeekStatus.loading => SectionCard.loading(title: title, onTap: open),
      TodayWeekStatus.failure => SectionCard.error(
        title: title,
        onTap: open,
        message: l10n.todayWeekLoadFailed,
        retryLabel: l10n.retry,
        onRetry: context.read<TodayWeekCubit>().retry,
      ),
      TodayWeekStatus.ready => SectionCard(
        title: title,
        detail: range ? _rangeText(context, state.days) : null,
        onTap: open,
        child: WeekStrip.plain(
          days: [
            for (final date in state.days)
              _weekDay(l10n, weekdays, date, state),
          ],
          onDayTap: (_) => open(),
        ),
      ),
    };
  }
}

/// "Nov 9–15", or "Oct 30–Nov 5" across two months.
String _rangeText(BuildContext context, List<CalendarDate> days) {
  final l10n = AppLocalizations.of(context);
  final dates = MaterialLocalizations.of(context);
  final (first, last) = (days.first, days.last);
  return l10n.progressWeekRange(
    dates.formatShortMonthDay(first.toLocalDateTime()),
    first.month == last.month
        ? '${last.day}'
        : dates.formatShortMonthDay(last.toLocalDateTime()),
  );
}

WeekStripDay _weekDay(
  AppLocalizations l10n,
  List<String> weekdays,
  CalendarDate date,
  TodayWeekState week,
) {
  final state = calendarDayState(
    week.entriesOn(date),
    today: date == week.today,
  );
  return WeekStripDay(
    // Index 0 is Sunday, ISO weekday 7.
    weekday: weekdays[date.weekday % 7],
    number: '${date.day}',
    state: state,
    semanticLabel: weekDayLabel(l10n, date, state),
  );
}
