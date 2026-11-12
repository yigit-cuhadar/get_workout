import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/notifications/domain/reminder_plan.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/completed_days.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_schedule.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';

import '../programs/fixtures.dart';

void main() {
  group('PlanWorkoutReminders', () {
    const plan = PlanWorkoutReminders();
    const on = WorkoutReminderSettings(enabled: true, minute: 8 * 60);
    // Wednesday 11 November 2026, 07:00.
    final now = DateTime(2026, 11, 11, 7);
    final today = CalendarDate(2026, 11, 11);

    /// Monday, Wednesday and Friday, the next day planned for [next].
    ActiveProgram active({CalendarDate? next, int dayIndex = 0}) =>
        ActiveProgram(
          programId: 'p1',
          weekdays: const [1, 3, 5],
          nextDayIndex: dayIndex,
          nextDate: next ?? today,
          startedAt: DateTime(2026, 11, 2),
        );

    List<WorkoutReminder> run({
      WorkoutReminderSettings settings = on,
      ActiveProgram? activeProgram,
      Program? withProgram,
      bool noProgram = false,
      List<CompletedDay> done = const [],
      bool open = true,
      DateTime? at,
    }) => plan((
      settings: settings,
      active: activeProgram ?? active(),
      program: noProgram ? null : withProgram ?? program(id: 'p1'),
      done: done,
      open: open,
      now: at ?? now,
    ));

    test('one per planned date for 28 days, at the chosen time', () {
      final reminders = run();

      expect(reminders, hasLength(12));
      expect(reminders.first.at, DateTime(2026, 11, 11, 8));
      expect(reminders[1].at, DateTime(2026, 11, 13, 8));
      expect(reminders.last.at, DateTime(2026, 12, 7, 8));
      expect(
        reminders.every((r) => r.at.isBefore(DateTime(2026, 12, 9))),
        isTrue,
      );
    });

    test('only the next one names its day', () {
      final reminders = run(activeProgram: active(dayIndex: 1));

      expect(reminders.first.day?.index, 1);
      expect(reminders.first.day?.day.name, 'Lower');
      expect(reminders.skip(1).every((r) => r.day == null), isTrue);
      expect(reminders.every((r) => r.programName == 'Upper Lower'), isTrue);
    });

    test('ids are unique and a date keeps its id from day to day', () {
      final first = run();
      final later = run(at: DateTime(2026, 11, 12, 7));

      expect(first.map((r) => r.id).toSet(), hasLength(first.length));
      expect(
        first.every(
          (r) =>
              r.id >= ReminderIds.workoutBase &&
              r.id < ReminderIds.workoutBase + ReminderIds.workoutDays,
        ),
        isTrue,
      );
      final friday = DateTime(2026, 11, 13, 8);
      expect(
        later.firstWhere((r) => r.at == friday).id,
        first.firstWhere((r) => r.at == friday).id,
      );
    });

    test('none today once the time has passed', () {
      final reminders = run(at: DateTime(2026, 11, 11, 9));

      expect(reminders.first.at, DateTime(2026, 11, 13, 8));
      // The next day is still the one the user has to do.
      expect(reminders.first.day?.index, isNull);
    });

    test('none for a day already done today', () {
      final reminders = run(done: [CompletedDay(date: today, dayIndex: 0)]);

      expect(reminders.first.at, DateTime(2026, 11, 13, 8));
    });

    test('a missed day is reminded on the next training day', () {
      final reminders = run(
        activeProgram: active(next: CalendarDate(2026, 11, 9)),
        at: DateTime(2026, 11, 10, 7),
      );

      expect(reminders.first.at, DateTime(2026, 11, 11, 8));
      expect(reminders.first.day?.index, 0);
    });

    test('stops where a program of a set length ends', () {
      final reminders = run(withProgram: program(id: 'p1', lengthWeeks: 2));

      // Started on 2 November: two weeks end on 16 November.
      expect(reminders.last.at, DateTime(2026, 11, 13, 8));
    });

    test('new weekdays move the reminders with them', () {
      final changed = ProgramSchedule(
        active(),
        dayCount: 2,
      ).withWeekdays(const [2, 4], today);

      final reminders = run(activeProgram: changed);

      expect(reminders.take(3).map((r) => r.at), [
        DateTime(2026, 11, 12, 8),
        DateTime(2026, 11, 17, 8),
        DateTime(2026, 11, 19, 8),
      ]);
    });

    test('a missed day moved to the next training day is reminded there', () {
      final missed = ProgramSchedule(
        active(next: CalendarDate(2026, 11, 9)),
        dayCount: 2,
      );

      final reminders = run(activeProgram: missed.moveToNextWeekday(today));

      expect(reminders.first.at, DateTime(2026, 11, 13, 8));
      expect(reminders.first.day?.index, 0);
    });

    test('a skipped missed day reminds of the day after it', () {
      final missed = ProgramSchedule(
        active(next: CalendarDate(2026, 11, 9)),
        dayCount: 2,
      );

      final reminders = run(activeProgram: missed.skip(today));

      expect(reminders.first.at, DateTime(2026, 11, 11, 8));
      expect(reminders.first.day?.day.name, 'Lower');
    });

    test('none when off, without a program, or a locked one', () {
      expect(run(settings: const WorkoutReminderSettings()), isEmpty);
      expect(run(noProgram: true), isEmpty);
      expect(run(open: false), isEmpty);
      expect(
        plan((
          settings: on,
          active: null,
          program: null,
          done: const [],
          open: true,
          now: now,
        )),
        isEmpty,
      );
    });
  });

  group('PlanMeasurementReminders', () {
    const plan = PlanMeasurementReminders();
    final from = CalendarDate(2026, 11, 1); // A Sunday.

    List<MeasurementReminder> run(
      DateTime now, {
      int everyWeeks = 4,
      bool enabled = true,
      CalendarDate? start,
      Set<CalendarDate> measured = const {},
    }) => plan((
      settings: MeasurementReminderSettings(
        enabled: enabled,
        everyWeeks: everyWeeks,
        from: start ?? from,
        minute: 9 * 60,
      ),
      measured: measured,
      now: now,
    ));

    test('the next four of the series, at the chosen time', () {
      final reminders = run(DateTime(2026, 11, 12));

      expect(reminders.map((r) => r.at), [
        DateTime(2026, 11, 29, 9),
        DateTime(2026, 12, 27, 9),
        DateTime(2027, 1, 24, 9),
        DateTime(2027, 2, 21, 9),
      ]);
    });

    test('the first date counts while its time is ahead', () {
      expect(run(DateTime(2026, 11, 1, 8)).first.at, DateTime(2026, 11, 1, 9));
      expect(
        run(DateTime(2026, 11, 1, 10)).first.at,
        DateTime(2026, 11, 29, 9),
      );
    });

    test('a series starting later starts there', () {
      final reminders = run(
        DateTime(2026, 11, 12),
        start: CalendarDate(2026, 11, 15),
        everyWeeks: 1,
      );

      expect(reminders.first.at, DateTime(2026, 11, 15, 9));
      expect(reminders.last.at, DateTime(2026, 12, 6, 9));
    });

    test('an occurrence keeps its id as the series moves on', () {
      final now = run(DateTime(2026, 11, 12));
      final later = run(DateTime(2026, 12, 1));

      expect(now.map((r) => r.id).toSet(), hasLength(4));
      expect(later.first.at, now[1].at);
      expect(later.first.id, now[1].id);
    });

    test('a date already measured is skipped', () {
      final reminders = run(
        DateTime(2026, 11, 12),
        measured: {CalendarDate(2026, 11, 29)},
      );

      expect(reminders.map((r) => r.at), [
        DateTime(2026, 12, 27, 9),
        DateTime(2027, 1, 24, 9),
        DateTime(2027, 2, 21, 9),
        DateTime(2027, 3, 21, 9),
      ]);
    });

    test('none when off or never started', () {
      expect(run(DateTime(2026, 11, 12), enabled: false), isEmpty);
      expect(
        plan((
          settings: const MeasurementReminderSettings(enabled: true),
          measured: const {},
          now: DateTime(2026, 11, 12),
        )),
        isEmpty,
      );
    });
  });
}
