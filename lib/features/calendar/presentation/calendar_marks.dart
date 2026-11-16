import 'package:forge_ui/forge_ui.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../programs/domain/calendar_date.dart';
import '../domain/calendar_month.dart';

/// GetWorkout's meaning of Forge's day circle, the same in WeekStrip and
/// MonthGrid: a workout is done (on [today] also ringed in ink), cardio
/// light, a passed program day without its workout missed, a program day
/// ahead planned, and a [today] without a workout or cardio the thick ink
/// ring. No dots.
DayState calendarDayState(List<CalendarEntry> entries, {required bool today}) {
  final marks = calendarMarks(entries);
  if (marks.contains(CalendarMark.workout)) {
    return today ? DayState.todayDone : DayState.done;
  }
  if (marks.contains(CalendarMark.cardio)) return DayState.light;
  if (today) return DayState.today;
  if (marks.contains(CalendarMark.missed)) return DayState.missed;
  if (marks.contains(CalendarMark.planned)) return DayState.planned;
  return DayState.none;
}

/// What a screen reader says for a week day: its weekday and number, then
/// what its circle [state] means, such as "Friday 13, Workout done".
String weekDayLabel(AppLocalizations l10n, CalendarDate date, DayState state) {
  final day = l10n.calendarWeekDay(
    DateFormat.EEEE(l10n.localeName).format(date.toLocalDateTime()),
    date.day,
  );
  final meaning = switch (state) {
    DayState.none => null,
    DayState.done => l10n.calendarWorkoutMark,
    DayState.light => l10n.calendarCardioMark,
    DayState.planned => l10n.calendarPlannedMark,
    DayState.missed => l10n.calendarMissedMark,
    DayState.today => l10n.calendarMarksToday,
    DayState.todayDone => l10n.calendarTodayDone,
  };
  return meaning == null ? day : '$day, $meaning';
}

/// The day circles a month can show, in the legend's order, with their
/// names.
Map<DayState, String> calendarLegend(AppLocalizations l10n) => {
  DayState.done: l10n.calendarMarksWorkout,
  DayState.light: l10n.calendarMarksCardio,
  DayState.planned: l10n.calendarMarksPlanned,
  DayState.missed: l10n.calendarMarksMissed,
  DayState.today: l10n.calendarMarksToday,
};
