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

ActiveProgram active({
  List<int> weekdays = const [1, 3, 5],
  int nextDayIndex = 0,
  required CalendarDate nextDate,
  DateTime? startedAt,
}) => ActiveProgram(
  programId: 'p1',
  weekdays: weekdays,
  nextDayIndex: nextDayIndex,
  nextDate: nextDate,
  startedAt: startedAt ?? DateTime(2026, 11, 2, 18),
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

List<(int, CalendarDate)> take(ProgramSchedule schedule, int count) => [
  for (final day in schedule.upcoming().take(count)) (day.dayIndex, day.date),
];

void main() {
  group('CalendarDate', () {
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
        expect(date.daysUntil(next), 1, reason: '$date');
        expect(next.toLocalDateTime().hour, 0, reason: '$next');
        expect(
          next.toLocalDateTime(),
          DateTime(2026, 1, 2 + i),
          reason: '$next',
        );
        date = next;
      }
    });

    test('counts days across DST changes', () {
      expect(d(2026, 10, 24).daysUntil(d(2026, 10, 26)), 2);
      expect(d(2026, 10, 31).daysUntil(d(2026, 11, 2)), 2);
      expect(d(2026, 3, 28).daysUntil(d(2026, 3, 30)), 2);
      expect(d(2026, 11, 2).daysUntil(d(2026, 10, 31)), -2);
    });

    test('takes the date a local time shows, late at night too', () {
      expect(CalendarDate.of(DateTime(2026, 10, 25, 23, 59)), d(2026, 10, 25));
      expect(CalendarDate.of(DateTime(2026, 10, 25, 0, 1)), d(2026, 10, 25));
      expect(CalendarDate.of(DateTime(2026, 3, 29, 2, 30)), d(2026, 3, 29));
    });

    test('starts its week on Monday, also across month and year ends', () {
      expect(d(2026, 11, 11).weekStart, d(2026, 11, 9));
      expect(d(2026, 11, 9).weekStart, d(2026, 11, 9));
      expect(d(2026, 11, 15).weekStart, d(2026, 11, 9));
      expect(d(2026, 12, 3).weekStart, d(2026, 11, 30));
      expect(d(2027, 1, 3).weekStart, d(2026, 12, 28));
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

  group('weekdays', () {
    test('suggestions spread one weekday per day over the week', () {
      expect(ProgramSchedule.suggestedWeekdays(1), [1]);
      expect(ProgramSchedule.suggestedWeekdays(2), [1, 4]);
      expect(ProgramSchedule.suggestedWeekdays(3), [1, 3, 5]);
      for (var days = 1; days <= 7; days++) {
        expect(
          ProgramSchedule.isValidWeekdays(
            ProgramSchedule.suggestedWeekdays(days),
            days,
          ),
          isTrue,
          reason: '$days',
        );
      }
    });

    test('valid weekdays are distinct, 1 to 7, one per day', () {
      expect(ProgramSchedule.isValidWeekdays(const [7, 1], 2), isTrue);
      expect(ProgramSchedule.isValidWeekdays(const [1, 1], 2), isFalse);
      expect(ProgramSchedule.isValidWeekdays(const [1, 3], 3), isFalse);
      expect(ProgramSchedule.isValidWeekdays(const [0, 3], 2), isFalse);
      expect(ProgramSchedule.isValidWeekdays(const [3, 8], 2), isFalse);
      expect(ProgramSchedule.isValidWeekdays(const [], 0), isTrue);
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
  });

  group('start', () {
    test('plans day one for the first selected weekday from today', () {
      final now = DateTime(2026, 11, 11, 21);
      expect(
        ProgramSchedule.start(
          programId: 'p1',
          weekdays: const [5, 1, 3],
          today: d(2026, 11, 11),
          startedAt: now,
        ),
        active(nextDate: d(2026, 11, 11), startedAt: now),
      );
      expect(
        ProgramSchedule.start(
          programId: 'p1',
          weekdays: const [1, 3, 5],
          today: d(2026, 11, 14),
          startedAt: now,
        ).nextDate,
        d(2026, 11, 16),
      );
    });
  });

  group('upcoming', () {
    test('each next day falls on the next selected weekday', () {
      final plan = schedule(active(nextDate: d(2026, 11, 11), nextDayIndex: 1));
      expect(take(plan, 5), [
        (1, d(2026, 11, 11)),
        (2, d(2026, 11, 13)),
        (0, d(2026, 11, 16)),
        (1, d(2026, 11, 18)),
        (2, d(2026, 11, 20)),
      ]);
    });

    test('follows a next date off the selected weekdays', () {
      final plan = schedule(active(nextDate: d(2026, 11, 12)));
      expect(take(plan, 2), [(0, d(2026, 11, 12)), (1, d(2026, 11, 13))]);
    });

    test('runs across month and year ends', () {
      final plan = schedule(
        active(weekdays: const [4], nextDate: d(2026, 12, 24)),
        dayCount: 2,
      );
      expect(take(plan, 3), [
        (0, d(2026, 12, 24)),
        (1, d(2026, 12, 31)),
        (0, d(2027, 1, 7)),
      ]);
    });

    test('keeps calendar dates across DST changes', () {
      final plan = schedule(
        active(
          weekdays: const [1, 2, 3, 4, 5, 6, 7],
          nextDate: d(2026, 10, 24),
        ),
        dayCount: 7,
      );
      expect(
        [for (final (_, date) in take(plan, 10)) date],
        [for (var day = 24; day <= 33; day++) d(2026, 10, day)],
      );
    });

    test('a program that lost days continues inside it', () {
      final plan = schedule(
        active(nextDayIndex: 4, nextDate: d(2026, 11, 11)),
        dayCount: 3,
      );
      expect(plan.nextDayIndex, 1);
      expect(take(plan, 1), [(1, d(2026, 11, 11))]);
    });

    test('more days than weekdays cycle over the weeks', () {
      final plan = schedule(
        active(weekdays: const [2, 4], nextDate: d(2026, 11, 10)),
        dayCount: 3,
      );
      expect(take(plan, 4), [
        (0, d(2026, 11, 10)),
        (1, d(2026, 11, 12)),
        (2, d(2026, 11, 17)),
        (0, d(2026, 11, 19)),
      ]);
    });
  });

  group('weekPlan', () {
    test('marks done days and plans the rest of the week', () {
      final plan = schedule(active(nextDayIndex: 1, nextDate: d(2026, 11, 11)));
      expect(
        plan.weekPlan(
          d(2026, 11, 11),
          completed: [CompletedDay(date: d(2026, 11, 9), dayIndex: 0)],
        ),
        [
          done(d(2026, 11, 9), 0),
          planned(d(2026, 11, 11), 1),
          planned(d(2026, 11, 13), 2),
        ],
      );
    });

    test('a passed day that was not done is missed', () {
      final plan = schedule(active(nextDayIndex: 1, nextDate: d(2026, 11, 11)));
      expect(plan.weekPlan(d(2026, 11, 12)), [
        missed(d(2026, 11, 11), 1),
        planned(d(2026, 11, 13), 2),
      ]);
    });

    test('today is planned, not missed', () {
      final plan = schedule(active(nextDate: d(2026, 11, 13)));
      expect(plan.weekPlan(d(2026, 11, 13)), [planned(d(2026, 11, 13), 0)]);
    });

    test('a day missed last week pushes this week on by one', () {
      final plan = schedule(active(nextDayIndex: 2, nextDate: d(2026, 11, 6)));
      expect(plan.weekPlan(d(2026, 11, 11)), [
        missed(d(2026, 11, 9), 0),
        planned(d(2026, 11, 11), 1),
        planned(d(2026, 11, 13), 2),
      ]);
    });

    test('shows nothing before the first planned day', () {
      final plan = schedule(
        active(weekdays: const [3], nextDate: d(2026, 11, 11)),
        dayCount: 1,
      );
      expect(plan.weekPlan(d(2026, 11, 10)), [planned(d(2026, 11, 11), 0)]);
    });

    test('done days outside the week are left out', () {
      final plan = schedule(active(nextDate: d(2026, 11, 16)));
      expect(
        plan.weekPlan(
          d(2026, 11, 15),
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
        active(weekdays: const [1, 4], nextDate: d(2026, 11, 30)),
        dayCount: 2,
      );
      expect(plan.weekPlan(d(2026, 12, 1)), [
        missed(d(2026, 11, 30), 0),
        planned(d(2026, 12, 3), 1),
      ]);
    });

    test('a week across a year end', () {
      final plan = schedule(
        active(
          weekdays: const [2, 5, 7],
          nextDayIndex: 1,
          nextDate: d(2027, 1, 1),
        ),
      );
      expect(
        plan.weekPlan(
          d(2026, 12, 31),
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
        active(weekdays: const [6, 7], nextDate: d(2026, 10, 24)),
        dayCount: 2,
      );
      expect(plan.weekPlan(d(2026, 10, 25)), [
        missed(d(2026, 10, 24), 0),
        planned(d(2026, 10, 25), 1),
      ]);
    });
  });

  group('missed days', () {
    final missedMonday = active(nextDayIndex: 1, nextDate: d(2026, 11, 9));

    test('a next date before today is missed', () {
      expect(schedule(missedMonday).isMissed(d(2026, 11, 10)), isTrue);
      expect(schedule(missedMonday).isMissed(d(2026, 11, 9)), isFalse);
      expect(schedule(missedMonday).isMissed(d(2026, 11, 8)), isFalse);
    });

    test('do it today: the following days follow from today', () {
      final next = schedule(missedMonday).doToday(d(2026, 11, 12));
      expect(next, missedMonday.copyWith(nextDate: d(2026, 11, 12)));
      expect(take(schedule(next), 3), [
        (1, d(2026, 11, 12)),
        (2, d(2026, 11, 13)),
        (0, d(2026, 11, 16)),
      ]);
      expect(schedule(next).isMissed(d(2026, 11, 12)), isFalse);
    });

    test('move: to the next selected weekday after today', () {
      final fromThursday = schedule(missedMonday)
          .moveToNextWeekday(d(2026, 11, 12));
      expect(fromThursday.nextDate, d(2026, 11, 13));
      expect(fromThursday.nextDayIndex, 1);
      // Today is a training day: the missed day goes after it.
      final fromWednesday = schedule(missedMonday)
          .moveToNextWeekday(d(2026, 11, 11));
      expect(take(schedule(fromWednesday), 3), [
        (1, d(2026, 11, 13)),
        (2, d(2026, 11, 16)),
        (0, d(2026, 11, 18)),
      ]);
    });

    test('skip: the day after comes next, from today on', () {
      final onTrainingDay = schedule(missedMonday).skip(d(2026, 11, 11));
      expect(
        onTrainingDay,
        missedMonday.copyWith(nextDayIndex: 2, nextDate: d(2026, 11, 11)),
      );
      final onRestDay = schedule(missedMonday).skip(d(2026, 11, 12));
      expect(onRestDay.nextDate, d(2026, 11, 13));
    });

    test('skipping the last day wraps to the first', () {
      final last = active(nextDayIndex: 2, nextDate: d(2026, 11, 9));
      expect(schedule(last).skip(d(2026, 11, 10)).nextDayIndex, 0);
    });

    test('resolutions work across a year end', () {
      final missedNewYearsEve = active(
        weekdays: const [4],
        nextDate: d(2026, 12, 31),
      );
      final today = d(2027, 1, 2);
      final plan = schedule(missedNewYearsEve, dayCount: 2);
      expect(plan.moveToNextWeekday(today).nextDate, d(2027, 1, 7));
      expect(
        plan.skip(today),
        missedNewYearsEve.copyWith(nextDayIndex: 1, nextDate: d(2027, 1, 7)),
      );
      expect(plan.doToday(today).nextDate, today);
    });
  });

  group('complete', () {
    test('on a planned day: the next day on the next weekday', () {
      final plan = schedule(active(nextDayIndex: 1, nextDate: d(2026, 11, 11)));
      expect(
        plan.complete(dayIndex: 1, on: d(2026, 11, 11)),
        active(nextDayIndex: 2, nextDate: d(2026, 11, 13)),
      );
    });

    test('on a day off the plan still advances', () {
      final plan = schedule(active(nextDayIndex: 1, nextDate: d(2026, 11, 11)));
      expect(
        plan.complete(dayIndex: 1, on: d(2026, 11, 10)),
        active(nextDayIndex: 2, nextDate: d(2026, 11, 11)),
      );
      expect(
        plan.complete(dayIndex: 1, on: d(2026, 11, 14)),
        active(nextDayIndex: 2, nextDate: d(2026, 11, 16)),
      );
    });

    test('the last day wraps to the first', () {
      final plan = schedule(active(nextDayIndex: 2, nextDate: d(2026, 11, 13)));
      expect(
        plan.complete(dayIndex: 2, on: d(2026, 11, 13)),
        active(nextDayIndex: 0, nextDate: d(2026, 11, 16)),
      );
    });

    test('one weekday a week: a week later, across the year end', () {
      final plan = schedule(
        active(weekdays: const [4], nextDate: d(2026, 12, 31)),
        dayCount: 1,
      );
      expect(
        plan.complete(dayIndex: 0, on: d(2026, 12, 31)),
        active(weekdays: const [4], nextDate: d(2027, 1, 7)),
      );
    });

    test('a missed day done late moves the plan on from then', () {
      final plan = schedule(active(nextDate: d(2026, 11, 9)));
      expect(
        plan.complete(dayIndex: 0, on: d(2026, 11, 12)),
        active(nextDayIndex: 1, nextDate: d(2026, 11, 13)),
      );
    });
  });

  group('withWeekdays', () {
    test('replans a missed day from today', () {
      final plan = schedule(active(nextDate: d(2026, 11, 9)));
      expect(
        plan.withWeekdays(const [2, 4, 6], d(2026, 11, 12)),
        active(weekdays: const [2, 4, 6], nextDate: d(2026, 11, 12)),
      );
    });

    test('a day planned after today stays after today', () {
      final plan = schedule(active(nextDayIndex: 1, nextDate: d(2026, 11, 13)));
      expect(
        plan.withWeekdays(const [2, 3, 7], d(2026, 11, 11)),
        active(
          weekdays: const [2, 3, 7],
          nextDayIndex: 1,
          nextDate: d(2026, 11, 15),
        ),
      );
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
      final days = twoWeeks(d(2026, 11, 11)).upcoming().toList();
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
      expect(twoWeeks(d(2026, 11, 23)).weekPlan(d(2026, 11, 23)), [
        planned(d(2026, 11, 23), 0),
      ]);
      expect(twoWeeks(d(2026, 11, 25)).weekPlan(d(2026, 11, 25)), isEmpty);
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
