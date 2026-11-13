import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/calendar/domain/calendar_days.dart';
import 'package:get_workout/features/calendar/domain/calendar_month.dart';
import 'package:get_workout/features/cardio/domain/cardio_session.dart';
import 'package:get_workout/features/cardio/domain/cardio_type.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/program_schedule.dart';

import '../programs/fixtures.dart';
import '../workout/fixtures.dart' show workout;

CalendarDate d(int year, int month, int day) => CalendarDate(year, month, day);

void main() {
  // Wednesday 11 November 2026; the week ends on Sunday the 15th.
  final today = d(2026, 11, 11);
  final monday = d(2026, 11, 9);
  final sunday = d(2026, 11, 15);
  final upperLower = program(id: 'p1');
  // Upper was planned on Monday the 9th and missed; it comes again on
  // Friday the 13th, Lower on Monday the 16th.
  final active = ActiveProgram(
    programId: 'p1',
    weekdays: const [1, 5],
    nextDayIndex: 0,
    nextDate: d(2026, 11, 9),
    startedAt: DateTime(2026, 11, 2),
  );
  final morning = workout('w3', const [], startedAt: DateTime(2026, 11, 11, 7));
  final evening = workout(
    'w4',
    const [],
    startedAt: DateTime(2026, 11, 11, 19),
  );
  final older = workout('w2', const [], startedAt: DateTime(2026, 11, 3, 18));
  final oldest = workout('w1', const [], startedAt: DateTime(2026, 11, 1, 18));
  CardioSession run(String id, DateTime date) => CardioSession(
    id: id,
    type: CardioType.treadmillRun,
    date: date,
    duration: const Duration(minutes: 30),
  );
  final lunchRun = run('c1', DateTime(2026, 11, 11, 12));
  final earlyRun = run('c2', DateTime(2026, 11, 3, 6));
  final firstRun = run('c3', DateTime(2026, 10, 20, 6));

  List<CalendarDate> dates(List<CalendarDay> days) => [
    for (final day in days) day.date,
  ];

  test('the list starts at the oldest workout loaded, or this week', () {
    expect(listStart(const [], more: false, weekStart: monday), monday);
    expect(listStart([morning], more: false, weekStart: monday), monday);
    expect(
      listStart([morning, older], more: false, weekStart: monday),
      d(2026, 11, 3),
    );
    // Older ones to come: its own date, even in this week.
    expect(listStart([evening, morning], more: true, weekStart: monday), today);
  });

  test('the list shows its dates, its start once nothing more follows', () {
    final start = d(2026, 11, 3);
    bool shows(CalendarDate date, {required bool more}) =>
        listShows(date, start: start, end: sunday, more: more);
    expect(shows(sunday, more: true), isTrue);
    expect(shows(d(2026, 11, 16), more: false), isFalse);
    expect(shows(d(2026, 11, 4), more: true), isTrue);
    expect(shows(start, more: true), isFalse);
    expect(shows(start, more: false), isTrue);
    expect(shows(d(2026, 11, 2), more: false), isFalse);
  });

  test('dates with entries, newest first, newest first within one', () {
    final days = calendarDays(
      today: today,
      start: d(2026, 11, 1),
      end: sunday,
      workouts: [evening, morning, older, oldest],
      more: false,
      cardio: [lunchRun, earlyRun, firstRun],
      active: active,
      program: upperLower,
    );
    // Not the run before the start, nor the plan after the end.
    expect(dates(days), [
      d(2026, 11, 13),
      today,
      d(2026, 11, 9),
      d(2026, 11, 3),
      d(2026, 11, 1),
    ]);
    expect(days[1].entries, [
      WorkoutEntry(evening),
      CardioEntry(lunchRun),
      WorkoutEntry(morning),
    ]);
    expect(days[0].entries, [
      PlanEntry(
        upperLower,
        PlannedDay(
          date: d(2026, 11, 13),
          dayIndex: 0,
          status: PlannedStatus.planned,
        ),
      ),
    ]);
    expect(days[2].entries, [
      PlanEntry(
        upperLower,
        PlannedDay(
          date: d(2026, 11, 9),
          dayIndex: 0,
          status: PlannedStatus.missed,
        ),
      ),
    ]);
  });

  test('while older workouts may follow, the start shows only those', () {
    final days = calendarDays(
      today: today,
      start: d(2026, 11, 3),
      end: sunday,
      workouts: [morning, older],
      more: true,
      cardio: [lunchRun, earlyRun],
    );
    expect(dates(days), [today, d(2026, 11, 3)]);
    expect(days.last.entries, [WorkoutEntry(older)]);
  });

  test('a date asked for is listed in place, even empty, if shown', () {
    List<CalendarDate> revealing(CalendarDate date) => dates(
      calendarDays(
        today: today,
        start: d(2026, 11, 3),
        end: sunday,
        workouts: [morning, older],
        more: true,
        cardio: const [],
        revealed: date,
      ),
    );
    expect(revealing(d(2026, 11, 5)), [today, d(2026, 11, 5), d(2026, 11, 3)]);
    for (final date in [d(2026, 11, 3), d(2026, 11, 2), d(2026, 11, 18)]) {
      expect(revealing(date), [today, d(2026, 11, 3)], reason: '$date');
    }
  });

  test('a date on its own: what was done and the plan on it', () {
    final later = calendarDay(
      d(2026, 11, 20),
      today: today,
      workouts: const [],
      cardio: const [],
      active: active,
      program: upperLower,
    );
    expect(later.entries, [
      PlanEntry(
        upperLower,
        PlannedDay(
          date: d(2026, 11, 20),
          dayIndex: 0,
          status: PlannedStatus.planned,
        ),
      ),
    ]);
    // Only that date: not the Monday between.
    expect(
      calendarDay(
        d(2026, 11, 17),
        today: today,
        workouts: const [],
        cardio: const [],
        active: active,
        program: upperLower,
      ).entries,
      isEmpty,
    );
    expect(
      calendarDay(
        d(2026, 11, 3),
        today: today,
        workouts: [older],
        cardio: [earlyRun],
      ),
      CalendarDay(d(2026, 11, 3), [WorkoutEntry(older), CardioEntry(earlyRun)]),
    );
  });
}
