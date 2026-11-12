import 'package:forge_core/forge_core.dart';

import '../../cardio/domain/cardio_session.dart';
import '../../programs/domain/active_program.dart';
import '../../programs/domain/calendar_date.dart';
import '../../programs/domain/program.dart';
import '../../programs/domain/program_schedule.dart';
import '../../workout/domain/workout.dart';

/// Something on a date of the calendar.
sealed class CalendarEntry extends Equatable {
  const CalendarEntry();

  CalendarDate get date;
}

/// A finished workout, on the local date it started.
class WorkoutEntry extends CalendarEntry {
  const WorkoutEntry(this.workout);
  final Workout workout;

  @override
  CalendarDate get date => workout.startDate;

  @override
  List<Object?> get props => [workout];
}

/// A cardio session, on the local date it started.
class CardioEntry extends CalendarEntry {
  const CardioEntry(this.session);
  final CardioSession session;

  @override
  CalendarDate get date => CalendarDate.of(session.date.toLocal());

  @override
  List<Object?> get props => [session];
}

/// A day of the active [program] not done yet: planned, or missed on its
/// date.
class PlanEntry extends CalendarEntry {
  const PlanEntry(this.program, this.day);
  final Program program;
  final PlannedDay day;

  @override
  CalendarDate get date => day.date;

  @override
  List<Object?> get props => [program, day];
}

/// The first day of [date]'s month.
CalendarDate monthOf(CalendarDate date) =>
    CalendarDate(date.year, date.month, 1);

/// The first day of the month [months] after [month]'s, before it when
/// negative.
CalendarDate addMonths(CalendarDate month, int months) =>
    CalendarDate(month.year, month.month + months, 1);

/// The weeks shown for [month]'s month, each seven dates from a
/// [firstWeekday] (ISO, 1 Monday to 7 Sunday): from the week of its first
/// day to the week of its last, so the first and last week may hold dates
/// of the months around it.
List<List<CalendarDate>> monthWeeks(
  CalendarDate month, {
  required int firstWeekday,
}) {
  assert(firstWeekday >= 1 && firstWeekday <= 7);
  final first = monthOf(month);
  final last = addMonths(first, 1).addDays(-1);
  var start = first.addDays(-((first.weekday - firstWeekday) % 7));
  return [
    for (; !start.isAfter(last); start = start.addDays(7))
      [for (var i = 0; i < 7; i++) start.addDays(i)],
  ];
}

/// The dates loaded for [month]'s month: every date its weeks can show,
/// whatever the first weekday.
({CalendarDate from, CalendarDate to}) monthRange(CalendarDate month) {
  final first = monthOf(month);
  return (
    from: first.addDays(-6), // Six days after the last.
    to: addMonths(first, 1).addDays(5),
  );
}

/// The entries of each date from [from] to [to], both included: the
/// [workouts] and [cardio] sessions by start time, then the days of the
/// [active] program not done yet, as its [ProgramSchedule.plan] gives them
/// on [today]. A program day counts as done when one of [workouts] did it,
/// so it shows once, as that workout. [program] is the active program as
/// it is now; without it nothing is planned.
Map<CalendarDate, List<CalendarEntry>> calendarEntries({
  required CalendarDate from,
  required CalendarDate to,
  required CalendarDate today,
  required List<Workout> workouts,
  required List<CardioSession> cardio,
  ActiveProgram? active,
  Program? program,
}) {
  bool inRange(CalendarDate date) => !date.isBefore(from) && !date.isAfter(to);
  final done = <({DateTime at, CalendarEntry entry})>[
    for (final workout in workouts)
      (at: workout.startedAt, entry: WorkoutEntry(workout)),
    for (final session in cardio)
      (at: session.date, entry: CardioEntry(session)),
  ]..sort((a, b) => a.at.compareTo(b.at));
  final entries = <CalendarDate, List<CalendarEntry>>{};
  void add(CalendarEntry entry) {
    if (inRange(entry.date)) {
      entries.putIfAbsent(entry.date, () => []).add(entry);
    }
  }

  for (final (:entry, at: _) in done) {
    add(entry);
  }
  if (active != null &&
      program != null &&
      program.id == active.programId &&
      program.days.isNotEmpty) {
    final schedule = ProgramSchedule(
      active,
      dayCount: program.days.length,
      lengthWeeks: program.lengthWeeks,
    );
    for (final day in schedule.plan(
      today,
      from: from,
      to: to,
      completed: completedDaysOf(workouts, active.programId),
    )) {
      if (day.status != PlannedStatus.done) add(PlanEntry(program, day));
    }
  }
  return entries;
}
