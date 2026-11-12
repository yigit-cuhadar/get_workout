import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/calendar/domain/calendar_month.dart';
import 'package:get_workout/features/cardio/domain/cardio_session.dart';
import 'package:get_workout/features/cardio/domain/cardio_type.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/program_schedule.dart';
import 'package:get_workout/features/workout/domain/workout.dart';

import '../programs/fixtures.dart';
import '../workout/fixtures.dart' show workout;

// Run with TZ=Europe/Berlin and TZ=America/New_York too: daylight saving
// starts on 29 Mar 2026 in Europe and on 8 Mar in the US, and ends on
// 25 Oct and 1 Nov.
CalendarDate d(int year, int month, int day) => CalendarDate(year, month, day);

/// The first date of each week.
List<CalendarDate> starts(List<List<CalendarDate>> weeks) => [
  for (final week in weeks) week.first,
];

void main() {
  group('monthWeeks', () {
    test('weeks of seven consecutive dates', () {
      final weeks = monthWeeks(d(2026, 11, 12), firstWeekday: 1);
      final all = weeks.expand((week) => week).toList();
      for (var i = 1; i < all.length; i++) {
        expect(all[i], all[i - 1].addDays(1));
      }
      expect(weeks.every((week) => week.length == 7), isTrue);
    });

    test('from the week of the first day to the week of the last', () {
      // November 2026 starts on a Sunday and ends on a Monday.
      expect(starts(monthWeeks(d(2026, 11, 1), firstWeekday: 1)), [
        d(2026, 10, 26),
        d(2026, 11, 2),
        d(2026, 11, 9),
        d(2026, 11, 16),
        d(2026, 11, 23),
        d(2026, 11, 30),
      ]);
      expect(starts(monthWeeks(d(2026, 11, 1), firstWeekday: 7)), [
        d(2026, 11, 1),
        d(2026, 11, 8),
        d(2026, 11, 15),
        d(2026, 11, 22),
        d(2026, 11, 29),
      ]);
    });

    test('weeks start on the given weekday', () {
      for (var first = 1; first <= 7; first++) {
        final weeks = monthWeeks(d(2026, 11, 1), firstWeekday: first);
        expect(weeks.every((week) => week.first.weekday == first), isTrue);
        expect(weeks.first.contains(d(2026, 11, 1)), isTrue);
        expect(weeks.last.contains(d(2026, 11, 30)), isTrue);
      }
    });

    test('a month filling exactly four weeks', () {
      // February 2026 starts on a Sunday and has 28 days.
      final weeks = monthWeeks(d(2026, 2, 1), firstWeekday: 7);
      expect(weeks, hasLength(4));
      expect(weeks.last.last, d(2026, 2, 28));
    });

    test('a leap February', () {
      final weeks = monthWeeks(d(2028, 2, 1), firstWeekday: 1);
      expect(weeks.expand((w) => w), contains(d(2028, 2, 29)));
      expect(weeks.last.last, d(2028, 3, 5));
    });

    test('across the year end', () {
      final weeks = monthWeeks(d(2026, 12, 31), firstWeekday: 1);
      expect(weeks.first.first, d(2026, 11, 30));
      expect(weeks.last.last, d(2027, 1, 3));
    });

    test('across daylight saving changes every date shows once', () {
      for (final month in [d(2026, 3, 1), d(2026, 10, 1), d(2026, 11, 1)]) {
        final all = monthWeeks(month, firstWeekday: 1).expand((w) => w);
        expect(all.toSet(), hasLength(all.length));
        expect(
          all.where((date) => date.month == month.month),
          hasLength(addMonths(month, 1).addDays(-1).day),
        );
      }
    });
  });

  group('months', () {
    test('monthOf is the first day', () {
      expect(monthOf(d(2026, 11, 30)), d(2026, 11, 1));
    });

    test('addMonths rolls over years both ways', () {
      expect(addMonths(d(2026, 12, 1), 1), d(2027, 1, 1));
      expect(addMonths(d(2026, 1, 1), -1), d(2025, 12, 1));
    });

    test('monthRange covers every week start', () {
      final range = monthRange(d(2026, 11, 20));
      expect(range.from, d(2026, 10, 26));
      expect(range.to, d(2026, 12, 6));
      for (var first = 1; first <= 7; first++) {
        final weeks = monthWeeks(d(2026, 11, 1), firstWeekday: first);
        expect(weeks.first.first.isBefore(range.from), isFalse);
        expect(weeks.last.last.isAfter(range.to), isFalse);
      }
    });
  });

  group('calendarEntries', () {
    // Wednesday 11 November 2026; Mon/Wed/Fri, day 1 next, today.
    final today = d(2026, 11, 11);
    final upperLower = program(id: 'p1');
    final threeDays = upperLower.copyWith(
      days: [...upperLower.days, upperLower.days.first],
    );
    final active = ActiveProgram(
      programId: 'p1',
      weekdays: const [1, 3, 5],
      nextDayIndex: 1,
      nextDate: today,
      startedAt: DateTime(2026, 11, 2, 18),
    );

    CardioSession run(DateTime at) => CardioSession(
      id: 'c$at',
      type: CardioType.treadmillRun,
      date: at,
      duration: const Duration(minutes: 30),
    );

    Map<CalendarDate, List<CalendarEntry>> entries({
      List<Workout> workouts = const [],
      List<CardioSession> cardio = const [],
      ActiveProgram? activeProgram,
      bool withProgram = true,
      CalendarDate? from,
      CalendarDate? to,
    }) => calendarEntries(
      from: from ?? d(2026, 11, 9),
      to: to ?? d(2026, 11, 15),
      today: today,
      workouts: workouts,
      cardio: cardio,
      active: activeProgram ?? active,
      program: withProgram ? threeDays : null,
    );

    PlanEntry plan(CalendarDate date, int day, [PlannedStatus? status]) =>
        PlanEntry(
          threeDays,
          PlannedDay(
            date: date,
            dayIndex: day,
            status: status ?? PlannedStatus.planned,
          ),
        );

    test('a day with several entries: done ones by time, then planned', () {
      final morning = workout(
        'w1',
        const [],
        startedAt: DateTime(2026, 11, 11, 7),
      );
      final evening = workout(
        'w2',
        const [],
        startedAt: DateTime(2026, 11, 11, 19),
        programId: 'p1',
        dayIndex: 2,
      );
      final noon = run(DateTime(2026, 11, 11, 12));
      expect(entries(workouts: [evening, morning], cardio: [noon])[today], [
        WorkoutEntry(morning),
        CardioEntry(noon),
        WorkoutEntry(evening),
        plan(today, 1),
      ]);
    });

    test('a program day done shows once, as its workout', () {
      final done = workout(
        'w1',
        const [],
        startedAt: DateTime(2026, 11, 11, 18),
        programId: 'p1',
        dayIndex: 1,
      );
      final result = entries(workouts: [done]);
      expect(result[today], [WorkoutEntry(done)]);
      expect(result[d(2026, 11, 13)], [plan(d(2026, 11, 13), 2)]);
    });

    test('a workout of another program does not count as done', () {
      final other = workout(
        'w1',
        const [],
        startedAt: DateTime(2026, 11, 11, 18),
        programId: 'p2',
        dayIndex: 1,
      );
      expect(entries(workouts: [other])[today], [
        WorkoutEntry(other),
        plan(today, 1),
      ]);
    });

    test('a workout late in the evening is on its local date', () {
      final late = workout(
        'w1',
        const [],
        startedAt: DateTime(2026, 11, 9, 23, 59),
      );
      expect(entries(workouts: [late])[d(2026, 11, 9)], [WorkoutEntry(late)]);
    });

    test('plans the active program through the range, missed day included', () {
      final missedMonday = active.copyWith(nextDate: d(2026, 11, 9));
      expect(entries(activeProgram: missedMonday), {
        d(2026, 11, 9): [plan(d(2026, 11, 9), 1, PlannedStatus.missed)],
        today: [plan(today, 1)],
        d(2026, 11, 13): [plan(d(2026, 11, 13), 2)],
      });
    });

    test('nothing planned without the program or for another one', () {
      expect(entries(withProgram: false), isEmpty);
      final elsewhere = ActiveProgram(
        programId: 'p9',
        weekdays: const [3],
        nextDayIndex: 0,
        nextDate: today,
        startedAt: DateTime(2026, 11, 2),
      );
      expect(entries(activeProgram: elsewhere), isEmpty);
    });

    test('leaves out what falls outside the range', () {
      final before = workout(
        'w1',
        const [],
        startedAt: DateTime(2026, 11, 8, 12),
      );
      final after = run(DateTime(2026, 11, 16, 7));
      final result = entries(
        workouts: [before],
        cardio: [after],
        withProgram: false,
      );
      expect(result, isEmpty);
    });

    test('plans a month across a daylight saving change', () {
      // Europe falls back on 25 October, the US on 1 November.
      final weekly = ActiveProgram(
        programId: 'p1',
        weekdays: const [7],
        nextDayIndex: 0,
        nextDate: d(2026, 10, 18),
        startedAt: DateTime(2026, 10, 1),
      );
      final result = calendarEntries(
        from: d(2026, 10, 18),
        to: d(2026, 11, 8),
        today: d(2026, 10, 18),
        workouts: const [],
        cardio: const [],
        active: weekly,
        program: threeDays,
      );
      expect(result.keys, [
        d(2026, 10, 18),
        d(2026, 10, 25),
        d(2026, 11, 1),
        d(2026, 11, 8),
      ]);
    });
  });
}
