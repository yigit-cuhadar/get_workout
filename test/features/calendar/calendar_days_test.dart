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

  test('dates with entries, newest first, newest first within one', () {
    final days = calendarDays(
      today: today,
      to: sunday,
      workouts: [evening, morning, older, oldest],
      more: false,
      cardio: [lunchRun, earlyRun, firstRun],
      active: active,
      program: upperLower,
    );
    expect(dates(days), [
      d(2026, 11, 13),
      today,
      d(2026, 11, 9),
      d(2026, 11, 3),
      d(2026, 11, 1),
      d(2026, 10, 20),
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

  test('nothing planned after the last date', () {
    final days = calendarDays(
      today: today,
      to: d(2026, 11, 12),
      workouts: const [],
      more: false,
      cardio: const [],
      active: active,
      program: upperLower,
    );
    expect(dates(days), [d(2026, 11, 9)]);
  });

  test('while older workouts may follow, nothing before the oldest', () {
    final days = calendarDays(
      today: today,
      to: sunday,
      workouts: [morning, older],
      more: true,
      cardio: [lunchRun, earlyRun, firstRun],
    );
    // Its date shows only its workouts: the early run waits.
    expect(dates(days), [today, d(2026, 11, 3)]);
    expect(days.last.entries, [WorkoutEntry(older)]);
    expect(listFloor([morning, older], more: true), d(2026, 11, 3));
    expect(listFloor([morning, older], more: false), isNull);
  });

  test('a date asked for is listed once covered, even empty', () {
    final days = calendarDays(
      today: today,
      to: sunday,
      workouts: [morning, older],
      more: true,
      cardio: const [],
      revealed: d(2026, 11, 5),
    );
    expect(dates(days), [today, d(2026, 11, 5), d(2026, 11, 3)]);
    expect(days[1].entries, isEmpty);

    // Not on the floor, nor before it.
    for (final date in [d(2026, 11, 3), d(2026, 11, 2)]) {
      expect(listCovers(date, d(2026, 11, 3)), isFalse);
      expect(
        dates(
          calendarDays(
            today: today,
            to: sunday,
            workouts: [morning, older],
            more: true,
            cardio: const [],
            revealed: date,
          ),
        ),
        [today, d(2026, 11, 3)],
      );
    }
  });

  test('a later date asked for lists the plan up to it', () {
    final days = calendarDays(
      today: today,
      to: sunday,
      workouts: const [],
      more: false,
      cardio: const [],
      active: active,
      program: upperLower,
      revealed: d(2026, 11, 18),
    );
    expect(dates(days), [
      d(2026, 11, 18),
      d(2026, 11, 16),
      d(2026, 11, 13),
      d(2026, 11, 9),
    ]);
    expect(days.first.entries, isEmpty);
  });

  test('without more, everything loaded is listed', () {
    final days = calendarDays(
      today: today,
      to: sunday,
      workouts: const [],
      more: false,
      cardio: [firstRun],
      revealed: d(2025, 1, 1),
    );
    expect(dates(days), [d(2026, 10, 20), d(2025, 1, 1)]);
  });
}
