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
  final october = workout('w1', const [], startedAt: DateTime(2026, 10, 6, 18));
  CardioSession run(String id, DateTime date) => CardioSession(
    id: id,
    type: CardioType.treadmillRun,
    date: date,
    duration: const Duration(minutes: 30),
  );
  final lunchRun = run('c1', DateTime(2026, 11, 11, 12));
  final earlyRun = run('c2', DateTime(2026, 11, 3, 6));

  Map<CalendarDate, List<CalendarEntry>> entries(CalendarDate month) {
    final (:from, :to) = monthRange(month);
    return calendarEntries(
      from: from,
      to: to,
      today: today,
      workouts: [october, older, morning, evening],
      cardio: [earlyRun, lunchRun],
      active: active,
      program: upperLower,
    );
  }

  List<CalendarEntry> Function(CalendarDate) on(
    Map<CalendarDate, List<CalendarEntry>> entries, [
    CalendarFilter filter = CalendarFilter.all,
  ]) =>
      (date) => filterEntries(entries[date] ?? const [], filter);

  test('a day lists what was done newest first, then its plan', () {
    final day = calendarDay(today, entries(d(2026, 11, 1))[today]!);
    expect(day.entries, [
      WorkoutEntry(evening),
      CardioEntry(lunchRun),
      WorkoutEntry(morning),
    ]);
  });

  test('the filter keeps workouts and program days, or cardio', () {
    final all = entries(d(2026, 11, 1));
    expect(on(all, CalendarFilter.cardio)(today), [CardioEntry(lunchRun)]);
    expect(on(all, CalendarFilter.workouts)(today), [
      WorkoutEntry(morning),
      WorkoutEntry(evening),
    ]);
    expect(on(all, CalendarFilter.workouts)(d(2026, 11, 9)), hasLength(1));
  });

  test('this month: this week, then the days before it', () {
    final november = d(2026, 11, 1);
    final sections = monthSections(
      november,
      today: today,
      firstWeekday: DateTime.monday,
      entriesOn: on(entries(november)),
    );
    expect(sections.map((s) => s.kind), [
      CalendarSectionKind.thisWeek,
      CalendarSectionKind.earlierThisMonth,
    ]);
    expect(sections.first.first, d(2026, 11, 9));
    expect(sections.first.last, d(2026, 11, 15));
    // Today, then the days to come in date order, then the past ones.
    expect(sections.first.days.map((day) => day.date), [
      today,
      d(2026, 11, 13),
      d(2026, 11, 9),
    ]);
    expect(sections.last.days.map((day) => day.date), [d(2026, 11, 3)]);
  });

  test('this week: today, the days to come ascending, the past descending', () {
    final listed = {9, 10, 11, 13, 15};
    final sections = monthSections(
      d(2026, 11, 1),
      today: today,
      firstWeekday: DateTime.monday,
      entriesOn: (date) => date.month == 11 && listed.contains(date.day)
          ? [WorkoutEntry(morning)]
          : const [],
    );
    expect(sections.first.days.map((day) => day.date.day), [11, 13, 15, 10, 9]);
  });

  test('another month: its weeks within it, newest first, empty ones left '
      'out', () {
    final octoberMonth = d(2026, 10, 1);
    final sections = monthSections(
      octoberMonth,
      today: today,
      firstWeekday: DateTime.monday,
      entriesOn: on(entries(octoberMonth)),
    );
    expect(sections, hasLength(1));
    expect(sections.single.kind, CalendarSectionKind.week);
    expect(sections.single.first, d(2026, 10, 5));
    expect(sections.single.last, d(2026, 10, 11));
  });

  test('a month ahead lists its planned weeks, clipped to the month', () {
    final december = d(2026, 12, 1);
    final sections = monthSections(
      december,
      today: today,
      firstWeekday: DateTime.monday,
      entriesOn: on(entries(december)),
    );
    expect(sections.first.last, d(2026, 12, 31));
    expect(sections.last.first, d(2026, 12, 1));
    expect(
      sections
          .expand((s) => s.days)
          .every((day) => day.entries.first is PlanEntry),
      isTrue,
    );
  });

  test('counts the month\'s workouts, cardio and missed days', () {
    final november = d(2026, 11, 1);
    final all = entries(november);
    expect(monthCounts(november, on(all)), (workouts: 3, cardio: 2, missed: 1));
    expect(monthCounts(november, on(all, CalendarFilter.cardio)), (
      workouts: 0,
      cardio: 2,
      missed: 0,
    ));
    expect(
      entries(november)[d(2026, 11, 9)]!.single,
      isA<PlanEntry>().having(
        (e) => e.day.status,
        'status',
        PlannedStatus.missed,
      ),
    );
  });
}
