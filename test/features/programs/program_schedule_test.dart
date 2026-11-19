import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/completed_days.dart';
import 'package:get_workout/features/programs/domain/program_schedule.dart';

// Run with TZ=Europe/Berlin and TZ=America/New_York too: daylight saving
// ends on 25 Oct 2026 in Europe and on 1 Nov 2026 in the US, and starts on
// 29 Mar and 8 Mar. In UTC every test still holds.
//
// November 2026: Mon 9, Wed 11, Fri 13, Mon 16; Mon 30 Nov, Thu 31 Dec,
// Fri 1 Jan 2027.
CalendarDate d(int year, int month, int day) => CalendarDate(year, month, day);

/// By default Monday day 0, Wednesday day 1, Friday day 2.
ActiveProgram active({
  Map<int, int> schedule = const {1: 0, 3: 1, 5: 2},
  int nextDayIndex = 0,
  required CalendarDate nextDate,
  DateTime? startedAt,
}) => ActiveProgram(
  programId: 'p1',
  schedule: schedule,
  nextDayIndex: nextDayIndex,
  nextDate: nextDate,
  startedAt: startedAt ?? DateTime(2026, 11, 2, 18),
);

/// A two-day program on four days: Monday A, Tuesday B, Thursday A,
/// Friday B.
ActiveProgram ab({
  int nextDayIndex = 0,
  required CalendarDate nextDate,
  DateTime? startedAt,
}) => active(
  schedule: const {1: 0, 2: 1, 4: 0, 5: 1},
  nextDayIndex: nextDayIndex,
  nextDate: nextDate,
  startedAt: startedAt,
);

ProgramSchedule schedule(
  ActiveProgram active, {
  int dayCount = 3,
  int? lengthWeeks,
}) => ProgramSchedule(active, dayCount: dayCount, lengthWeeks: lengthWeeks);

PlannedDay planned(CalendarDate date, int dayIndex) =>
    PlannedDay(date: date, dayIndex: dayIndex, status: PlannedStatus.planned);
PlannedDay missed(CalendarDate date, int dayIndex) =>
    PlannedDay(date: date, dayIndex: dayIndex, status: PlannedStatus.missed);
PlannedDay done(CalendarDate date, int dayIndex) =>
    PlannedDay(date: date, dayIndex: dayIndex, status: PlannedStatus.done);

/// The first [count] upcoming days as planned on [today], by default the
/// next day's date.
List<(int, CalendarDate)> take(
  ProgramSchedule schedule,
  int count, {
  CalendarDate? today,
}) => [
  for (final day
      in schedule.upcoming(today ?? schedule.active.nextDate).take(count))
    (day.dayIndex, day.date),
];

void main() {
  group('CalendarDate', () {
    test('counts the days since another date', () {
      expect(d(2026, 11, 9).daysSince(d(2026, 11, 2)), 7);
      expect(d(2026, 11, 2).daysSince(d(2026, 11, 9)), -7);
      expect(d(2027, 1, 1).daysSince(d(2026, 12, 31)), 1);
    });

    test('knows its ISO weekday', () {
      expect(d(2026, 11, 9).weekday, DateTime.monday);
      expect(d(2026, 11, 15).weekday, DateTime.sunday);
      expect(d(2027, 1, 1).weekday, DateTime.friday);
    });

    test('adds days across months, years and leap days', () {
      expect(d(2026, 11, 30).addDays(1), d(2026, 12, 1));
      expect(d(2026, 12, 31).addDays(1), d(2027, 1, 1));
      expect(d(2027, 1, 1).addDays(-1), d(2026, 12, 31));
      expect(d(2028, 2, 28).addDays(1), d(2028, 2, 29));
      expect(d(2027, 2, 28).addDays(1), d(2027, 3, 1));
      expect(d(2026, 1, 1).addDays(365), d(2027, 1, 1));
    });

    test('every day of a year with DST changes is one day apart', () {
      var date = d(2026, 1, 1);
      for (var i = 0; i < 366; i++) {
        final next = date.addDays(1);
        expect(next.toLocalDateTime().hour, 0, reason: '$next');
        expect(
          next.toLocalDateTime(),
          DateTime(2026, 1, 2 + i),
          reason: '$next',
        );
        date = next;
      }
    });

    test('adds days across DST changes', () {
      expect(d(2026, 10, 24).addDays(2), d(2026, 10, 26));
      expect(d(2026, 10, 31).addDays(2), d(2026, 11, 2));
      expect(d(2026, 3, 28).addDays(2), d(2026, 3, 30));
      expect(d(2026, 11, 2).addDays(-2), d(2026, 10, 31));
    });

    test('takes the date a local time shows, late at night too', () {
      expect(CalendarDate.of(DateTime(2026, 10, 25, 23, 59)), d(2026, 10, 25));
      expect(CalendarDate.of(DateTime(2026, 10, 25, 0, 1)), d(2026, 10, 25));
      expect(CalendarDate.of(DateTime(2026, 3, 29, 2, 30)), d(2026, 3, 29));
    });

    test('starts its week on Monday, also across month and year ends', () {
      expect(d(2026, 11, 11).startOfWeek(DateTime.monday), d(2026, 11, 9));
      expect(d(2026, 11, 9).startOfWeek(DateTime.monday), d(2026, 11, 9));
      expect(d(2026, 11, 15).startOfWeek(DateTime.monday), d(2026, 11, 9));
      expect(d(2026, 12, 3).startOfWeek(DateTime.monday), d(2026, 11, 30));
      expect(d(2027, 1, 3).startOfWeek(DateTime.monday), d(2026, 12, 28));
    });

    test('lists the weekdays of a week in its order', () {
      expect(weekdaysFrom(DateTime.monday), [1, 2, 3, 4, 5, 6, 7]);
      expect(weekdaysFrom(DateTime.sunday), [7, 1, 2, 3, 4, 5, 6]);
      expect(weekdaysFrom(DateTime.saturday), [6, 7, 1, 2, 3, 4, 5]);
    });

    test('starts its week on any weekday a locale uses', () {
      // Wednesday 11 November 2026.
      expect(d(2026, 11, 11).startOfWeek(DateTime.sunday), d(2026, 11, 8));
      expect(d(2026, 11, 8).startOfWeek(DateTime.sunday), d(2026, 11, 8));
      expect(d(2026, 11, 14).startOfWeek(DateTime.sunday), d(2026, 11, 8));
      expect(d(2026, 11, 11).startOfWeek(DateTime.saturday), d(2026, 11, 7));
      expect(d(2026, 11, 13).startOfWeek(DateTime.saturday), d(2026, 11, 7));
      expect(d(2026, 11, 14).startOfWeek(DateTime.saturday), d(2026, 11, 14));
      expect(d(2027, 1, 2).startOfWeek(DateTime.sunday), d(2026, 12, 27));
    });

    test('reads and writes YYYY-MM-DD', () {
      expect(d(2026, 3, 7).toIso(), '2026-03-07');
      expect(CalendarDate.tryParse('2026-03-07'), d(2026, 3, 7));
      expect(CalendarDate.tryParse('2028-02-29'), d(2028, 2, 29));
      for (final bad in [
        '2026-02-30',
        '2026-13-01',
        '2026-3-7',
        '07.03.2026',
        '',
        null,
        20260307,
      ]) {
        expect(CalendarDate.tryParse(bad), isNull, reason: '$bad');
      }
    });

    test('orders by date', () {
      expect(d(2026, 12, 31).isBefore(d(2027, 1, 1)), isTrue);
      expect(d(2027, 1, 1).isAfter(d(2026, 12, 31)), isTrue);
      expect(d(2026, 5, 5).isBefore(d(2026, 5, 5)), isFalse);
    });
  });

  group('ActiveProgram', () {
    test('keeps its schedule by weekday, its weekdays ascending', () {
      final program = active(
        schedule: const {5: 1, 1: 0, 4: 0, 2: 1},
        nextDate: d(2026, 11, 9),
      );
      expect(program.schedule.keys, [1, 2, 4, 5]);
      expect(program.weekdays, [1, 2, 4, 5]);
      expect(program, ab(nextDate: d(2026, 11, 9)));
      expect(() => program.schedule[3] = 0, throwsUnsupportedError);
    });
  });

  group('schedules', () {
    test('suggestions do the days in turn, one weekday each', () {
      expect(ProgramSchedule.suggestedSchedule(1), {1: 0});
      expect(ProgramSchedule.suggestedSchedule(2), {1: 0, 4: 1});
      expect(ProgramSchedule.suggestedSchedule(3), {1: 0, 3: 1, 5: 2});
      for (var days = 1; days <= 7; days++) {
        final suggested = ProgramSchedule.suggestedSchedule(days);
        expect(suggested.values.toSet(), hasLength(days), reason: '$days');
        expect(
          ProgramSchedule.isValidSchedule(suggested, days),
          isTrue,
          reason: '$days',
        );
      }
    });

    test('in turn: by ascending weekday, cycling through the days', () {
      expect(ProgramSchedule.inTurn(const [5, 1, 3], 3), {1: 0, 3: 1, 5: 2});
      expect(ProgramSchedule.inTurn(const [5, 1, 4, 2], 2), {
        1: 0,
        2: 1,
        4: 0,
        5: 1,
      });
      expect(ProgramSchedule.inTurn(const [3, 3, 1], 3), {1: 0, 3: 1});
      expect(ProgramSchedule.inTurn(const [], 3), isEmpty);
    });

    test('valid: 1-7 weekdays from 1 to 7, each on a day the program has', () {
      expect(ProgramSchedule.isValidSchedule(const {7: 0, 1: 1}, 2), isTrue);
      expect(
        ProgramSchedule.isValidSchedule(const {1: 0, 2: 1, 4: 0, 5: 1}, 2),
        isTrue,
      );
      // Days may be left out, or done every day.
      expect(ProgramSchedule.isValidSchedule(const {3: 2}, 3), isTrue);
      expect(
        ProgramSchedule.isValidSchedule({for (var w = 1; w <= 7; w++) w: 0}, 1),
        isTrue,
      );
      for (final schedule in [
        const <int, int>{},
        const {1: 2},
        const {1: -1},
        const {0: 0},
        const {8: 0},
      ]) {
        expect(
          ProgramSchedule.isValidSchedule(schedule, 2),
          isFalse,
          reason: '$schedule',
        );
      }
    });

    test('the next weekday counts from the given date on', () {
      const mwf = [1, 3, 5];
      expect(
        ProgramSchedule.nextWeekday(mwf, from: d(2026, 11, 11)),
        d(2026, 11, 11),
      );
      expect(
        ProgramSchedule.nextWeekday(mwf, from: d(2026, 11, 12)),
        d(2026, 11, 13),
      );
      expect(
        ProgramSchedule.nextWeekday(mwf, from: d(2026, 11, 14)),
        d(2026, 11, 16),
      );
      expect(
        ProgramSchedule.nextWeekday(const [2], from: d(2026, 12, 30)),
        d(2027, 1, 5),
      );
    });

    test('a weekday does its own day, inside a program that lost days', () {
      final plan = schedule(active(nextDate: d(2026, 11, 9)), dayCount: 2);
      expect(
        [
          for (final w in const [1, 3, 5]) plan.dayOn(w),
        ],
        [0, 1, 0],
      );
    });
  });

  group('start', () {
    test('plans the first training weekday from today, with its day', () {
      final now = DateTime(2026, 11, 11, 21);
      expect(
        ProgramSchedule.start(
          programId: 'p1',
          schedule: const {5: 2, 1: 0, 3: 1},
          today: d(2026, 11, 11),
          startedAt: now,
        ),
        active(nextDayIndex: 1, nextDate: d(2026, 11, 11), startedAt: now),
      );
      expect(
        ProgramSchedule.start(
          programId: 'p1',
          schedule: const {1: 0, 3: 1, 5: 2},
          today: d(2026, 11, 14),
          startedAt: now,
        ),
        active(nextDate: d(2026, 11, 16), startedAt: now),
      );
    });

    test('an A/B program started on a rest day begins with the next A', () {
      final now = DateTime(2026, 11, 11, 21);
      expect(
        ProgramSchedule.start(
          programId: 'p1',
          schedule: const {1: 0, 2: 1, 4: 0, 5: 1},
          today: d(2026, 11, 11),
          startedAt: now,
        ),
        ab(nextDate: d(2026, 11, 12), startedAt: now),
      );
    });
  });

  group('upcoming', () {
    test('each training weekday does its own day, every week', () {
      final plan = schedule(ab(nextDate: d(2026, 11, 9)), dayCount: 2);
      expect(take(plan, 8), [
        (0, d(2026, 11, 9)),
        (1, d(2026, 11, 10)),
        (0, d(2026, 11, 12)),
        (1, d(2026, 11, 13)),
        (0, d(2026, 11, 16)),
        (1, d(2026, 11, 17)),
        (0, d(2026, 11, 19)),
        (1, d(2026, 11, 20)),
      ]);
    });

    test('one day per weekday follows the weekdays', () {
      final plan = schedule(active(nextDate: d(2026, 11, 11), nextDayIndex: 1));
      expect(take(plan, 5), [
        (1, d(2026, 11, 11)),
        (2, d(2026, 11, 13)),
        (0, d(2026, 11, 16)),
        (1, d(2026, 11, 18)),
        (2, d(2026, 11, 20)),
      ]);
    });

    test('a day moved off the training weekdays keeps its own day', () {
      final plan = schedule(active(nextDate: d(2026, 11, 12)));
      expect(take(plan, 3), [
        (0, d(2026, 11, 12)),
        (2, d(2026, 11, 13)),
        (0, d(2026, 11, 16)),
      ]);
    });

    test('a day moved onto a training weekday takes that date\'s place', () {
      final plan = schedule(active(nextDate: d(2026, 11, 13)));
      expect(take(plan, 3), [
        (0, d(2026, 11, 13)),
        (0, d(2026, 11, 16)),
        (1, d(2026, 11, 18)),
      ]);
    });

    test('runs across month and year ends', () {
      final plan = schedule(
        active(
          schedule: const {4: 1},
          nextDayIndex: 1,
          nextDate: d(2026, 12, 24),
        ),
        dayCount: 2,
      );
      expect(take(plan, 3), [
        (1, d(2026, 12, 24)),
        (1, d(2026, 12, 31)),
        (1, d(2027, 1, 7)),
      ]);
    });

    test('keeps calendar dates across DST changes', () {
      final plan = schedule(
        active(
          schedule: {for (var w = 1; w <= 7; w++) w: w - 1},
          nextDayIndex: 5,
          nextDate: d(2026, 10, 24),
        ),
        dayCount: 7,
      );
      final days = take(plan, 10);
      expect(
        [for (final (_, date) in days) date],
        [for (var day = 24; day <= 33; day++) d(2026, 10, day)],
      );
      expect([
        for (final (index, date) in days) index == date.weekday - 1,
      ], everyElement(isTrue));
    });

    test('a program that lost days continues inside it', () {
      final plan = schedule(
        active(nextDayIndex: 4, nextDate: d(2026, 11, 11)),
        dayCount: 2,
      );
      expect(plan.nextDayIndex, 0);
      expect(take(plan, 3), [
        (0, d(2026, 11, 11)),
        (0, d(2026, 11, 13)),
        (0, d(2026, 11, 16)),
      ]);
    });

    test('a missed next day comes first again, on the first training '
        'weekday from today, in place of its own day', () {
      final plan = schedule(ab(nextDate: d(2026, 11, 9)), dayCount: 2);
      // Wednesday is a rest day: Monday's A goes on Thursday.
      expect(take(plan, 3, today: d(2026, 11, 11)), [
        (0, d(2026, 11, 12)),
        (1, d(2026, 11, 13)),
        (0, d(2026, 11, 16)),
      ]);
      // On Tuesday it comes in place of Tuesday's B.
      expect(take(plan, 3, today: d(2026, 11, 10)), [
        (0, d(2026, 11, 10)),
        (0, d(2026, 11, 12)),
        (1, d(2026, 11, 13)),
      ]);
    });
  });

  group('weekPlan', () {
    test('covers the week from the first weekday given', () {
      final plan = schedule(active(nextDate: d(2026, 11, 16)));
      // Sunday 15 November ends a Monday week and starts a Sunday one.
      expect(
        plan.weekPlan(d(2026, 11, 15), firstWeekday: DateTime.monday),
        isEmpty,
      );
      expect(plan.weekPlan(d(2026, 11, 15), firstWeekday: DateTime.sunday), [
        planned(d(2026, 11, 16), 0),
        planned(d(2026, 11, 18), 1),
        planned(d(2026, 11, 20), 2),
      ]);
    });

    test('an A/B week: done days, then the rest as the weekdays give', () {
      final plan = schedule(ab(nextDate: d(2026, 11, 12)), dayCount: 2);
      final week = plan.weekPlan(
        d(2026, 11, 11),
        firstWeekday: DateTime.monday,
        completed: [
          CompletedDay(date: d(2026, 11, 9), dayIndex: 0),
          CompletedDay(date: d(2026, 11, 10), dayIndex: 1),
        ],
      );
      expect(week, [
        done(d(2026, 11, 9), 0),
        done(d(2026, 11, 10), 1),
        planned(d(2026, 11, 12), 0),
        planned(d(2026, 11, 13), 1),
      ]);
      // 2 of 4 days this week.
      expect(
        week.where((day) => day.status == PlannedStatus.done),
        hasLength(2),
      );
      expect(week, hasLength(4));
    });

    test('marks done days and plans the rest of the week', () {
      final plan = schedule(active(nextDayIndex: 1, nextDate: d(2026, 11, 11)));
      expect(
        plan.weekPlan(
          d(2026, 11, 11),
          firstWeekday: DateTime.monday,
          completed: [CompletedDay(date: d(2026, 11, 9), dayIndex: 0)],
        ),
        [
          done(d(2026, 11, 9), 0),
          planned(d(2026, 11, 11), 1),
          planned(d(2026, 11, 13), 2),
        ],
      );
    });

    test('a missed day shows once; the same day is planned from today', () {
      final plan = schedule(active(nextDayIndex: 1, nextDate: d(2026, 11, 11)));
      expect(plan.weekPlan(d(2026, 11, 12), firstWeekday: DateTime.monday), [
        missed(d(2026, 11, 11), 1),
        planned(d(2026, 11, 13), 1),
      ]);
    });

    test('no later day is planned before the missed one', () {
      // Mon/Wed/Fri, day 0 missed on Monday, looked at on Friday.
      final plan = schedule(active(nextDate: d(2026, 11, 9)));
      expect(plan.weekPlan(d(2026, 11, 13), firstWeekday: DateTime.monday), [
        missed(d(2026, 11, 9), 0),
        planned(d(2026, 11, 13), 0),
      ]);
      // On Thursday, a rest day, the missed day waits for Friday.
      expect(plan.weekPlan(d(2026, 11, 12), firstWeekday: DateTime.monday), [
        missed(d(2026, 11, 9), 0),
        planned(d(2026, 11, 13), 0),
      ]);
    });

    test('today is planned, not missed', () {
      final plan = schedule(active(nextDayIndex: 2, nextDate: d(2026, 11, 13)));
      expect(plan.weekPlan(d(2026, 11, 13), firstWeekday: DateTime.monday), [
        planned(d(2026, 11, 13), 2),
      ]);
    });

    test('a day missed last week is planned again this week', () {
      final plan = schedule(active(nextDayIndex: 2, nextDate: d(2026, 11, 6)));
      expect(plan.weekPlan(d(2026, 11, 11), firstWeekday: DateTime.monday), [
        planned(d(2026, 11, 11), 2),
        planned(d(2026, 11, 13), 2),
      ]);
    });

    test('shows nothing before the first planned day', () {
      final plan = schedule(
        active(schedule: const {3: 0}, nextDate: d(2026, 11, 11)),
        dayCount: 1,
      );
      expect(plan.weekPlan(d(2026, 11, 10), firstWeekday: DateTime.monday), [
        planned(d(2026, 11, 11), 0),
      ]);
    });

    test('done days outside the week are left out', () {
      final plan = schedule(active(nextDate: d(2026, 11, 16)));
      expect(
        plan.weekPlan(
          d(2026, 11, 15),
          firstWeekday: DateTime.monday,
          completed: [
            CompletedDay(date: d(2026, 11, 8), dayIndex: 1),
            CompletedDay(date: d(2026, 11, 13), dayIndex: 2),
          ],
        ),
        [done(d(2026, 11, 13), 2)],
      );
    });

    test('a week across a month end', () {
      final plan = schedule(
        active(schedule: const {1: 0, 4: 1}, nextDate: d(2026, 11, 30)),
        dayCount: 2,
      );
      expect(plan.weekPlan(d(2026, 12, 1), firstWeekday: DateTime.monday), [
        missed(d(2026, 11, 30), 0),
        planned(d(2026, 12, 3), 0),
      ]);
    });

    test('a week across a year end', () {
      final plan = schedule(
        active(
          schedule: const {2: 0, 5: 1, 7: 2},
          nextDayIndex: 1,
          nextDate: d(2027, 1, 1),
        ),
      );
      expect(
        plan.weekPlan(
          d(2026, 12, 31),
          firstWeekday: DateTime.monday,
          completed: [CompletedDay(date: d(2026, 12, 29), dayIndex: 0)],
        ),
        [
          done(d(2026, 12, 29), 0),
          planned(d(2027, 1, 1), 1),
          planned(d(2027, 1, 3), 2),
        ],
      );
    });

    test('a week across a DST change', () {
      final plan = schedule(
        active(schedule: const {6: 0, 7: 1}, nextDate: d(2026, 10, 24)),
        dayCount: 2,
      );
      expect(plan.weekPlan(d(2026, 10, 25), firstWeekday: DateTime.monday), [
        missed(d(2026, 10, 24), 0),
        planned(d(2026, 10, 25), 0),
      ]);
    });
  });

  group('plan', () {
    test('a day done twice on one date shows once', () {
      final plan = schedule(active(nextDayIndex: 1, nextDate: d(2026, 11, 11)));
      final twice = CompletedDay(date: d(2026, 11, 9), dayIndex: 0);
      expect(
        plan.weekPlan(
          d(2026, 11, 11),
          firstWeekday: DateTime.monday,
          completed: [twice, twice],
        ),
        [
          done(d(2026, 11, 9), 0),
          planned(d(2026, 11, 11), 1),
          planned(d(2026, 11, 13), 2),
        ],
      );
    });

    test('a planned day done on its date shows only as done', () {
      // Done today, but the program did not move on.
      final plan = schedule(active(nextDayIndex: 1, nextDate: d(2026, 11, 11)));
      expect(
        plan.weekPlan(
          d(2026, 11, 11),
          firstWeekday: DateTime.monday,
          completed: [CompletedDay(date: d(2026, 11, 11), dayIndex: 1)],
        ),
        [done(d(2026, 11, 11), 1), planned(d(2026, 11, 13), 2)],
      );
    });

    test('a missed day done on its date is not missed', () {
      // Wednesday's day 1 was done, but the program did not move on.
      final plan = schedule(active(nextDayIndex: 1, nextDate: d(2026, 11, 11)));
      expect(
        plan.weekPlan(
          d(2026, 11, 12),
          firstWeekday: DateTime.monday,
          completed: [CompletedDay(date: d(2026, 11, 11), dayIndex: 1)],
        ),
        [done(d(2026, 11, 11), 1), planned(d(2026, 11, 13), 1)],
      );
    });

    test('another day done on a planned date leaves it planned', () {
      final plan = schedule(active(nextDayIndex: 1, nextDate: d(2026, 11, 11)));
      expect(
        plan.weekPlan(
          d(2026, 11, 11),
          firstWeekday: DateTime.monday,
          completed: [CompletedDay(date: d(2026, 11, 11), dayIndex: 2)],
        ),
        [
          done(d(2026, 11, 11), 2),
          planned(d(2026, 11, 11), 1),
          planned(d(2026, 11, 13), 2),
        ],
      );
    });

    test('covers any range, both ends included', () {
      final plan = schedule(active(nextDayIndex: 1, nextDate: d(2026, 11, 11)));
      expect(
        plan.plan(d(2026, 11, 11), from: d(2026, 11, 13), to: d(2026, 11, 20)),
        [
          planned(d(2026, 11, 13), 2),
          planned(d(2026, 11, 16), 0),
          planned(d(2026, 11, 18), 1),
          planned(d(2026, 11, 20), 2),
        ],
      );
    });

    test('a range in the past plans nothing but its missed day', () {
      final plan = schedule(active(nextDayIndex: 2, nextDate: d(2026, 10, 30)));
      expect(
        plan.plan(d(2026, 11, 11), from: d(2026, 10, 1), to: d(2026, 10, 31)),
        [missed(d(2026, 10, 30), 2)],
      );
      expect(
        plan.plan(d(2026, 11, 11), from: d(2026, 9, 1), to: d(2026, 9, 30)),
        isEmpty,
      );
    });

    test('ends with the program', () {
      // Four weeks from Monday 2 November: the last day is 27 November.
      final plan = schedule(
        active(schedule: const {5: 0}, nextDate: d(2026, 11, 13)),
        dayCount: 1,
        lengthWeeks: 4,
      );
      expect(
        plan.plan(d(2026, 11, 12), from: d(2026, 11, 1), to: d(2026, 12, 31)),
        [
          planned(d(2026, 11, 13), 0),
          planned(d(2026, 11, 20), 0),
          planned(d(2026, 11, 27), 0),
        ],
      );
    });
  });

  group('missed days', () {
    // Monday A, Tuesday B, Thursday A, Friday B; Monday's A missed.
    final missedMonday = ab(nextDate: d(2026, 11, 9));
    ProgramSchedule plan() => schedule(missedMonday, dayCount: 2);

    test('a next date before today is missed', () {
      expect(plan().isMissed(d(2026, 11, 10)), isTrue);
      expect(plan().isMissed(d(2026, 11, 9)), isFalse);
      expect(plan().isMissed(d(2026, 11, 8)), isFalse);
    });

    test('do it today: today, then the weekdays\' own days', () {
      final onRestDay = plan().doToday(d(2026, 11, 11));
      expect(onRestDay, missedMonday.copyWith(nextDate: d(2026, 11, 11)));
      expect(take(schedule(onRestDay, dayCount: 2), 3), [
        (0, d(2026, 11, 11)),
        (0, d(2026, 11, 12)),
        (1, d(2026, 11, 13)),
      ]);
      expect(
        schedule(onRestDay, dayCount: 2).isMissed(d(2026, 11, 11)),
        isFalse,
      );
      // On Tuesday, A takes the place of Tuesday's B.
      final onTuesday = plan().doToday(d(2026, 11, 10));
      expect(take(schedule(onTuesday, dayCount: 2), 2), [
        (0, d(2026, 11, 10)),
        (0, d(2026, 11, 12)),
      ]);
    });

    test('move: to the next training weekday after today, keeping its day', () {
      final fromTuesday = plan().moveToNextWeekday(d(2026, 11, 10));
      expect(fromTuesday, missedMonday.copyWith(nextDate: d(2026, 11, 12)));
      final fromThursday = plan().moveToNextWeekday(d(2026, 11, 12));
      // A on Friday, in place of Friday's B.
      expect(take(schedule(fromThursday, dayCount: 2), 3), [
        (0, d(2026, 11, 13)),
        (0, d(2026, 11, 16)),
        (1, d(2026, 11, 17)),
      ]);
    });

    test('skip: the first training weekday from today does its own day', () {
      expect(
        plan().skip(d(2026, 11, 10)),
        missedMonday.copyWith(nextDayIndex: 1, nextDate: d(2026, 11, 10)),
      );
      expect(
        plan().skip(d(2026, 11, 11)),
        missedMonday.copyWith(nextDayIndex: 0, nextDate: d(2026, 11, 12)),
      );
    });

    test('resolutions work across a year end', () {
      final missedNewYearsEve = active(
        schedule: const {4: 1},
        nextDayIndex: 1,
        nextDate: d(2026, 12, 31),
      );
      final today = d(2027, 1, 2);
      final plan = schedule(missedNewYearsEve, dayCount: 2);
      expect(
        plan.moveToNextWeekday(today),
        missedNewYearsEve.copyWith(nextDate: d(2027, 1, 7)),
      );
      expect(
        plan.skip(today),
        missedNewYearsEve.copyWith(nextDate: d(2027, 1, 7)),
      );
      expect(plan.doToday(today).nextDate, today);
    });
  });

  group('complete', () {
    test('on a planned day: the next training weekday with its day', () {
      final plan = schedule(active(nextDayIndex: 1, nextDate: d(2026, 11, 11)));
      expect(
        plan.complete(on: d(2026, 11, 11)),
        active(nextDayIndex: 2, nextDate: d(2026, 11, 13)),
      );
    });

    test('an A/B week: A, B, A, B and A again on Monday', () {
      var program = ab(nextDate: d(2026, 11, 9));
      final days = <(int, CalendarDate)>[];
      for (var i = 0; i < 5; i++) {
        days.add((program.nextDayIndex, program.nextDate));
        program = schedule(program, dayCount: 2).complete(on: program.nextDate);
      }
      expect(days, [
        (0, d(2026, 11, 9)),
        (1, d(2026, 11, 10)),
        (0, d(2026, 11, 12)),
        (1, d(2026, 11, 13)),
        (0, d(2026, 11, 16)),
      ]);
    });

    test('on a day off the plan still moves on from then', () {
      final plan = schedule(active(nextDayIndex: 1, nextDate: d(2026, 11, 11)));
      expect(
        plan.complete(on: d(2026, 11, 10)),
        active(nextDayIndex: 1, nextDate: d(2026, 11, 11)),
      );
      expect(
        plan.complete(on: d(2026, 11, 14)),
        active(nextDate: d(2026, 11, 16)),
      );
    });

    test('one weekday a week: a week later, across the year end', () {
      final plan = schedule(
        active(schedule: const {4: 0}, nextDate: d(2026, 12, 31)),
        dayCount: 1,
      );
      expect(
        plan.complete(on: d(2026, 12, 31)),
        active(schedule: const {4: 0}, nextDate: d(2027, 1, 7)),
      );
    });

    test('a missed or moved day done late: the next weekday\'s own day', () {
      final missedPlan = schedule(active(nextDate: d(2026, 11, 9)));
      expect(
        missedPlan.complete(on: d(2026, 11, 12)),
        active(nextDayIndex: 2, nextDate: d(2026, 11, 13)),
      );
      final moved = schedule(active(nextDate: d(2026, 11, 12)));
      expect(
        moved.complete(on: d(2026, 11, 12)),
        active(nextDayIndex: 2, nextDate: d(2026, 11, 13)),
      );
    });
  });

  group('moving the next day', () {
    // Monday A, Tuesday B, Thursday A, Friday B; Thursday's A is next.
    final thursday = ab(nextDate: d(2026, 11, 12));
    ProgramSchedule plan(ActiveProgram active) => schedule(active, dayCount: 2);

    test('earlier: it takes its date along, so that weekday rests', () {
      final moved = plan(thursday).moveNext(d(2026, 11, 11));
      expect(
        moved,
        thursday.copyWith(
          nextDate: d(2026, 11, 11),
          movedFrom: () => d(2026, 11, 12),
        ),
      );
      expect(take(plan(moved), 3, today: d(2026, 11, 10)), [
        (0, d(2026, 11, 11)),
        (1, d(2026, 11, 13)),
        (0, d(2026, 11, 16)),
      ]);
      expect(
        plan(moved).weekPlan(d(2026, 11, 10), firstWeekday: DateTime.monday),
        [planned(d(2026, 11, 11), 0), planned(d(2026, 11, 13), 1)],
      );
    });

    test('earlier: done, the weekday after its own date comes next', () {
      final moved = plan(thursday).moveNext(d(2026, 11, 11));
      expect(
        plan(moved).complete(on: d(2026, 11, 11)),
        ab(nextDayIndex: 1, nextDate: d(2026, 11, 13)),
      );
    });

    test('earlier twice: it keeps the first date it came from', () {
      final once = plan(thursday).moveNext(d(2026, 11, 11));
      final twice = plan(once).moveNext(d(2026, 11, 10));
      expect(twice.movedFrom, d(2026, 11, 12));
      expect(take(plan(twice), 2, today: d(2026, 11, 10)), [
        (0, d(2026, 11, 10)),
        (1, d(2026, 11, 13)),
      ]);
    });

    test('later: the training weekdays between are left out', () {
      final moved = plan(thursday).moveNext(d(2026, 11, 14));
      expect(moved, thursday.copyWith(nextDate: d(2026, 11, 14)));
      expect(take(plan(moved), 3), [
        (0, d(2026, 11, 14)),
        (0, d(2026, 11, 16)),
        (1, d(2026, 11, 17)),
      ]);
    });

    test('earlier, then missed: it comes back on its own date', () {
      final moved = plan(thursday).moveNext(d(2026, 11, 11));
      final missed = plan(moved);
      expect(missed.isMissed(d(2026, 11, 12)), isTrue);
      expect(take(missed, 2, today: d(2026, 11, 12)), [
        (0, d(2026, 11, 12)),
        (1, d(2026, 11, 13)),
      ]);
      // Skipped, its own date still rests.
      expect(
        missed.skip(d(2026, 11, 12)),
        ab(nextDayIndex: 1, nextDate: d(2026, 11, 13)),
      );
    });

    test('new training days forget where it came from', () {
      final moved = plan(thursday).moveNext(d(2026, 11, 11));
      expect(
        plan(moved).withSchedule(const {4: 0, 5: 1}, d(2026, 11, 10)),
        active(schedule: const {4: 0, 5: 1}, nextDate: d(2026, 11, 12)),
      );
    });
  });

  group('withSchedule', () {
    test('replans a missed day from today, with today\'s day', () {
      final plan = schedule(active(nextDate: d(2026, 11, 9)));
      expect(
        plan.withSchedule(const {2: 0, 4: 1, 6: 2}, d(2026, 11, 12)),
        active(
          schedule: const {2: 0, 4: 1, 6: 2},
          nextDayIndex: 1,
          nextDate: d(2026, 11, 12),
        ),
      );
    });

    test('a day planned after today stays after today', () {
      final plan = schedule(active(nextDayIndex: 2, nextDate: d(2026, 11, 13)));
      expect(
        plan.withSchedule(const {2: 0, 3: 1, 7: 2}, d(2026, 11, 11)),
        active(
          schedule: const {2: 0, 3: 1, 7: 2},
          nextDayIndex: 2,
          nextDate: d(2026, 11, 15),
        ),
      );
    });

    test('today\'s day not done yet stays today, as the new one gives', () {
      final plan = schedule(active(nextDayIndex: 1, nextDate: d(2026, 11, 11)));
      expect(
        plan.withSchedule(const {3: 0, 5: 1}, d(2026, 11, 11)),
        active(schedule: const {3: 0, 5: 1}, nextDate: d(2026, 11, 11)),
      );
    });

    test('an A/B program on four days', () {
      final plan = schedule(
        active(schedule: const {1: 0, 4: 1}, nextDate: d(2026, 11, 9)),
        dayCount: 2,
      );
      final changed = plan.withSchedule(const {
        1: 0,
        2: 1,
        4: 0,
        5: 1,
      }, d(2026, 11, 10));
      expect(changed, ab(nextDayIndex: 1, nextDate: d(2026, 11, 10)));
      expect(take(schedule(changed, dayCount: 2), 4), [
        (1, d(2026, 11, 10)),
        (0, d(2026, 11, 12)),
        (1, d(2026, 11, 13)),
        (0, d(2026, 11, 16)),
      ]);
    });
  });

  group('length', () {
    // Started Wednesday evening; two weeks end before Wednesday 25 Nov.
    final start = DateTime(2026, 11, 11, 20);
    ProgramSchedule twoWeeks(CalendarDate nextDate, {int nextDayIndex = 0}) =>
        schedule(
          active(
            nextDate: nextDate,
            nextDayIndex: nextDayIndex,
            startedAt: start,
          ),
          lengthWeeks: 2,
        );

    test('ends the given weeks after the start date', () {
      expect(twoWeeks(d(2026, 11, 11)).end, d(2026, 11, 25));
      expect(schedule(active(nextDate: d(2026, 11, 11))).end, isNull);
    });

    test('has one day per selected weekday and week', () {
      final days = twoWeeks(d(2026, 11, 11)).upcoming(d(2026, 11, 11)).toList();
      expect(days, hasLength(6));
      expect(days.last.date, d(2026, 11, 23));
    });

    test('is finished once the next day falls on or after the end', () {
      expect(twoWeeks(d(2026, 11, 23)).isFinished(d(2026, 11, 20)), isFalse);
      expect(twoWeeks(d(2026, 11, 25)).isFinished(d(2026, 11, 24)), isTrue);
      expect(twoWeeks(d(2026, 11, 30)).isFinished(d(2026, 11, 24)), isTrue);
    });

    test('is finished once today reaches the end, days missed or not', () {
      final behind = twoWeeks(d(2026, 11, 23));
      expect(behind.isFinished(d(2026, 11, 24)), isFalse);
      expect(behind.isMissed(d(2026, 11, 24)), isTrue);
      expect(behind.isFinished(d(2026, 11, 25)), isTrue);
      expect(behind.isMissed(d(2026, 11, 25)), isFalse);
    });

    test('the plan of the last week stops at the end', () {
      expect(
        twoWeeks(d(2026, 11, 23))
            .weekPlan(d(2026, 11, 23), firstWeekday: DateTime.monday),
        [planned(d(2026, 11, 23), 0)],
      );
      expect(
        twoWeeks(d(2026, 11, 25))
            .weekPlan(d(2026, 11, 25), firstWeekday: DateTime.monday),
        isEmpty,
      );
    });

    test('counts weeks from the start date, within the length', () {
      final plan = twoWeeks(d(2026, 11, 11));
      expect(plan.week(d(2026, 11, 10)), 1);
      expect(plan.week(d(2026, 11, 11)), 1);
      expect(plan.week(d(2026, 11, 17)), 1);
      expect(plan.week(d(2026, 11, 18)), 2);
      expect(plan.week(d(2026, 12, 30)), 2);
      expect(
        schedule(active(nextDate: d(2026, 11, 11))).week(d(2026, 12, 30)),
        9,
      );
    });

    test('a run week is none before the run started', () {
      final plan = twoWeeks(d(2026, 11, 11));
      expect(plan.runWeek(d(2026, 11, 10)), isNull);
      expect(plan.runWeek(d(2026, 11, 11)), 1);
      expect(plan.runWeek(d(2026, 11, 18)), 2);
    });

    test('without a length a program never finishes', () {
      expect(
        schedule(active(nextDate: d(2030, 1, 1))).isFinished(d(2031, 1, 1)),
        isFalse,
      );
    });

    test('counts from the local start date across a DST change', () {
      // 23:30 on the night the clocks change, in Europe or the US.
      for (final started in [
        DateTime(2026, 10, 24, 23, 30),
        DateTime(2026, 10, 31, 23, 30),
        DateTime(2026, 3, 28, 23, 30),
      ]) {
        final plan = schedule(
          active(nextDate: CalendarDate.of(started), startedAt: started),
          lengthWeeks: 1,
        );
        expect(
          plan.end,
          CalendarDate.of(started).addDays(7),
          reason: '$started',
        );
      }
    });
  });
}
