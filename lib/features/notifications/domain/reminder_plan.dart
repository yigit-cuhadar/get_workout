import 'package:forge_core/forge_core.dart';

import '../../programs/domain/active_program.dart';
import '../../programs/domain/calendar_date.dart';
import '../../programs/domain/completed_days.dart';
import '../../programs/domain/program.dart';
import '../../programs/domain/program_schedule.dart';
import '../../settings/domain/user_settings.dart';

enum ReminderKind { workout, measurement }

/// A training day to remind of.
class WorkoutReminder extends Equatable {
  const WorkoutReminder({
    required this.id,
    required this.at,
    required this.programName,
    this.day,
  });

  final int id;
  final DateTime at;
  final String programName;

  /// The program day due, only for the next one: the days after it are
  /// due then only if the user keeps to the plan meanwhile.
  final ({int index, ProgramDay day})? day;

  @override
  List<Object?> get props => [id, at, programName, day];
}

/// A measurement day to remind of.
class MeasurementReminder extends Equatable {
  const MeasurementReminder({required this.id, required this.at});

  final int id;
  final DateTime at;

  @override
  List<Object?> get props => [id, at];
}

/// The notification ids of each kind of reminder; the rest notification
/// and announcements use others.
abstract final class ReminderIds {
  static const workoutBase = 100;

  /// Days ahead workout reminders are planned for, which is also how many
  /// ids they own: one per date, so a date keeps its id from plan to plan.
  static const workoutDays = 28;
  static const measurementBase = 200;

  /// Measurement reminders planned ahead, which is also how many ids they
  /// own.
  static const measurementCount = 4;

  /// The [count] ids from [base] that [kind] owns.
  static ({int base, int count}) of(ReminderKind kind) => switch (kind) {
    ReminderKind.workout => (base: workoutBase, count: workoutDays),
    ReminderKind.measurement => (
      base: measurementBase,
      count: measurementCount,
    ),
  };
}

typedef WorkoutReminderInput = ({
  WorkoutReminderSettings settings,
  ActiveProgram? active,

  /// The active program, null when there is none or it no longer exists.
  Program? program,

  /// Days already done; only today's matter.
  List<CompletedDay> done,

  /// Whether the program may be trained (a premium copy without premium
  /// may not).
  bool open,
  DateTime now,
});

/// The workout reminders to have: one at the chosen time on every date the
/// active program plans a day for, from now to [ReminderIds.workoutDays]
/// days ahead, as planned today (a missed day falls on the next training
/// day). None for a day done already, a program that has run its length,
/// or one that may not be trained.
class PlanWorkoutReminders {
  const PlanWorkoutReminders();

  List<WorkoutReminder> call(WorkoutReminderInput input) {
    final active = input.active;
    final program = input.program;
    if (!input.settings.enabled ||
        !input.open ||
        active == null ||
        program == null ||
        program.days.isEmpty) {
      return const [];
    }
    final today = CalendarDate.of(input.now);
    final end = today.addDays(ReminderIds.workoutDays);
    final schedule = ProgramSchedule(
      active,
      dayCount: program.days.length,
      lengthWeeks: program.lengthWeeks,
    );
    final upcoming = schedule
        .upcoming(today)
        .takeWhile((day) => day.date.isBefore(end))
        .toList();
    return [
      for (final (i, day) in upcoming.indexed)
        if (_at(day.date, input.settings.minute) case final at
            when at.isAfter(input.now) &&
                !input.done.contains(
                  CompletedDay(date: day.date, dayIndex: day.dayIndex),
                ))
          WorkoutReminder(
            id:
                ReminderIds.workoutBase +
                _dayNumber(day.date) % ReminderIds.workoutDays,
            at: at,
            programName: program.name,
            day: i == 0
                ? (index: day.dayIndex, day: program.days[day.dayIndex])
                : null,
          ),
    ];
  }
}

typedef MeasurementReminderInput = ({
  MeasurementReminderSettings settings,

  /// Dates that already have a measurement; their occurrence is skipped.
  Set<CalendarDate> measured,
  DateTime now,
});

/// The next [ReminderIds.measurementCount] measurement reminders: every
/// `everyWeeks` weeks from `from` at the chosen time, but none on a date
/// already measured. Occurrence `k` of the series keeps id
/// `measurementBase + k % measurementCount`.
class PlanMeasurementReminders {
  const PlanMeasurementReminders();

  List<MeasurementReminder> call(MeasurementReminderInput input) {
    final settings = input.settings;
    final from = settings.from;
    if (!settings.enabled || from == null) return const [];
    final period = 7 * settings.everyWeeks;
    final today = CalendarDate.of(input.now);
    final elapsed = _dayNumber(today) - _dayNumber(from);
    var k = elapsed <= 0 ? 0 : elapsed ~/ period;
    final reminders = <MeasurementReminder>[];
    while (reminders.length < ReminderIds.measurementCount) {
      final date = from.addDays(period * k);
      final at = _at(date, settings.minute);
      if (at.isAfter(input.now) && !input.measured.contains(date)) {
        reminders.add(
          MeasurementReminder(
            id: ReminderIds.measurementBase + k % ReminderIds.measurementCount,
            at: at,
          ),
        );
      }
      k++;
    }
    return reminders;
  }
}

/// Local [minute] after midnight on [date].
DateTime _at(CalendarDate date, int minute) =>
    DateTime(date.year, date.month, date.day, minute ~/ 60, minute % 60);

/// Days since 1970-01-01.
int _dayNumber(CalendarDate date) =>
    DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;
