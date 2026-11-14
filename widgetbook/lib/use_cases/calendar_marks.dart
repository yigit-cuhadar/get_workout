import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:get_workout/features/calendar/presentation/calendar_marks.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

// GetWorkout's meanings drawn by Forge's WeekStrip and MonthGrid. The days
// here are the circles calendarDayState gives the card's sample week.

const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

WeekStrip _week(String title, int first, List<DayState> states) => WeekStrip(
  title: title,
  days: [
    for (final (i, state) in states.indexed)
      WeekStripDay(weekday: _letters[i], number: '${first + i}', state: state),
  ],
  onDayTap: (_) {},
);

@widgetbook.UseCase(
  name: 'CalendarMarks · this week and next week',
  type: WeekStrip,
)
Widget calendarMarksWeeks(BuildContext context) => SingleChildScrollView(
  padding: const EdgeInsets.all(Gap.md),
  child: Column(
    spacing: Gap.sm,
    children: [
      _week('This week', 9, const [
        DayState.done,
        DayState.light,
        DayState.missed,
        DayState.light,
        DayState.today,
        DayState.none,
        DayState.none,
      ]),
      _week('Next week', 16, const [
        DayState.planned,
        DayState.none,
        DayState.planned,
        DayState.none,
        DayState.planned,
        DayState.none,
        DayState.none,
      ]),
    ],
  ),
);

@widgetbook.UseCase(name: 'CalendarMarks · month', type: MonthGrid)
Widget calendarMarksMonth(BuildContext context) => SingleChildScrollView(
  padding: const EdgeInsets.all(Gap.md),
  child: MonthGrid(
    month: DateTime(2026, 11),
    firstWeekday: DateTime.monday,
    weekdays: _letters,
    summary: '4 workouts · 4 cardio · 1 missed',
    legend: calendarLegend(AppLocalizations.of(context)),
    stateOf: (day) => switch ((day.month, day.day)) {
      (11, 2 || 6 || 9) => DayState.done,
      (11, 4 || 8 || 10 || 12) => DayState.light,
      (11, 11) => DayState.missed,
      (11, 13) => DayState.today,
      (11, 16 || 18 || 20) => DayState.planned,
      _ => DayState.none,
    },
  ),
);
