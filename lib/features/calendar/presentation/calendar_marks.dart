import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../programs/domain/calendar_date.dart';
import '../domain/calendar_month.dart';

/// A date's marks as small icons, for `MonthGrid`: done as filled dots,
/// program days not done yet as rings, a missed one in the error colour.
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
