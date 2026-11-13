import 'package:forge_core/forge_core.dart';

import '../../cardio/domain/cardio_session.dart';
import '../../programs/domain/active_program.dart';
import '../../programs/domain/calendar_date.dart';
import '../../programs/domain/program.dart';
import '../../workout/domain/workout.dart';
import 'calendar_month.dart';

/// A date of the calendar's list and what is on it: what was done, newest
/// first, then the program days not done yet.
class CalendarDay extends Equatable {
  const CalendarDay(this.date, this.entries);
  final CalendarDate date;

  /// Empty only for a date asked to be shown.
  final List<CalendarEntry> entries;

  @override
  List<Object?> get props => [date, entries];
}

/// The first date of the calendar's list, which ends on the last day of
/// the week starting on [weekStart]: the date of the oldest of [workouts]
/// (the history loaded so far, newest first), or [weekStart] when that is
/// earlier. While [more] older workouts may follow, only some workouts of
/// that date may be loaded yet; see [listShows].
CalendarDate listStart(
  List<Workout> workouts, {
  required bool more,
  required CalendarDate weekStart,
}) {
  final oldest = workouts.lastOrNull?.startDate;
  if (oldest == null) return weekStart;
  return more || oldest.isBefore(weekStart) ? oldest : weekStart;
}

/// Whether the list from [start] (see [listStart]) to [end] shows [date]
/// in full: the start only once no [more] workouts may follow.
bool listShows(
  CalendarDate date, {
  required CalendarDate start,
  required CalendarDate end,
  required bool more,
}) =>
    !date.isAfter(end) && (more ? start.isBefore(date) : !date.isBefore(start));

/// The calendar's list: the dates from [end] back to [start] (see
/// [listStart]) with entries, newest first. [workouts] are the history
/// loaded so far, newest first; [cardio] and the [active] program's days
/// not done yet fill in the dates, as in [calendarEntries]. While [more]
/// older workouts may follow, [start] shows only its workouts: the rest of
/// that date waits for its other workouts, which may decide that a program
/// day was done.
///
/// [revealed], a date the user asked for, is listed even without entries
/// when the list shows it (see [listShows]).
List<CalendarDay> calendarDays({
  required CalendarDate today,
  required CalendarDate start,
  required CalendarDate end,
  required List<Workout> workouts,
  required bool more,
  required List<CardioSession> cardio,
  ActiveProgram? active,
  Program? program,
  CalendarDate? revealed,
}) {
  final entries = calendarEntries(
    from: start,
    to: end,
    today: today,
    workouts: workouts,
    cardio: cardio,
    active: active,
    program: program,
  );
  if (more) entries[start]?.removeWhere((e) => e is! WorkoutEntry);
  if (revealed != null &&
      listShows(revealed, start: start, end: end, more: more)) {
    entries.putIfAbsent(revealed, () => []);
  }
  final dates = entries.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final date in dates) _day(date, entries[date]!)];
}

/// [date] on its own, for a date the list does not show: its [workouts]
/// and [cardio], and the [active] program's day on it not done yet, as in
/// [calendarEntries].
CalendarDay calendarDay(
  CalendarDate date, {
  required CalendarDate today,
  required List<Workout> workouts,
  required List<CardioSession> cardio,
  ActiveProgram? active,
  Program? program,
}) => _day(
  date,
  calendarEntries(
        from: date,
        to: date,
        today: today,
        workouts: workouts,
        cardio: cardio,
        active: active,
        program: program,
      )[date] ??
      const [],
);

/// calendarEntries lists what was done oldest first; the list shows it
/// newest first.
CalendarDay _day(CalendarDate date, List<CalendarEntry> entries) =>
    CalendarDay(date, [
      ...entries.where((e) => e is! PlanEntry).toList().reversed,
      ...entries.whereType<PlanEntry>(),
    ]);
