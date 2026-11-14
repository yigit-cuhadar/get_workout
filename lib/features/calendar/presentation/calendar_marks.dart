import 'package:flutter/material.dart';
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
  DayState.missed: l10n.calendarMarksMissed,
  DayState.planned: l10n.calendarMarksPlanned,
  DayState.today: l10n.calendarMarksToday,
};

/// A date's marks as small icons, for the app's own `MonthGrid`: done as
/// filled dots, program days not done yet as rings, a missed one in the
/// error colour.
List<Widget> calendarMarkIcons(
  BuildContext context,
  List<CalendarEntry> entries,
) {
  final colors = Theme.of(context).colorScheme;
  return [
    for (final mark in calendarMarks(entries))
      Icon(
        switch (mark) {
          CalendarMark.workout || CalendarMark.cardio => Icons.circle,
          CalendarMark.planned || CalendarMark.missed => Icons.circle_outlined,
        },
        size: Gap.sm,
        color: switch (mark) {
          CalendarMark.workout || CalendarMark.planned => colors.primary,
          CalendarMark.cardio => colors.tertiary,
          CalendarMark.missed => colors.error,
        },
      ),
  ];
}

/// What a screen reader says for [date]: the date, then its marks.
String calendarDayLabel(
  BuildContext context,
  CalendarDate date,
  List<CalendarEntry> entries,
) {
  final l10n = AppLocalizations.of(context);
  return [
    MaterialLocalizations.of(context).formatFullDate(date.toLocalDateTime()),
    for (final mark in calendarMarks(entries))
      switch (mark) {
        CalendarMark.workout => l10n.calendarWorkoutMark,
        CalendarMark.cardio => l10n.calendarCardioMark,
        CalendarMark.planned => l10n.calendarPlannedMark,
        CalendarMark.missed => l10n.calendarMissedMark,
      },
  ].join(', ');
}
