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

  /// Empty only for the date asked to be shown; see [calendarDays].
  final List<CalendarEntry> entries;

  @override
  List<Object?> get props => [date, entries];
}

/// The oldest date the calendar's list shows in full: the date of the
/// oldest of [workouts] (the history loaded so far, newest first) while
/// [more] older ones may follow, when only some of its workouts may be
/// loaded yet; null when everything is loaded.
CalendarDate? listFloor(List<Workout> workouts, {required bool more}) =>
    more ? workouts.lastOrNull?.startDate : null;

/// Whether the calendar's list shows [date] in full: it is after the
/// [floor] (see [listFloor]), or there is none.
bool listCovers(CalendarDate date, CalendarDate? floor) =>
    floor == null || floor.isBefore(date);

/// The calendar's list: the dates with entries, newest first, from [to]
/// back to the oldest of [workouts] loaded (the history, newest first; see
/// [listFloor]). On the floor only workouts show: the rest of that date
/// waits for its other workouts, which may decide that a program day was
/// done. [cardio] and the [active] program's days not done yet fill in the
/// dates between, as in [calendarEntries].
///
/// [revealed], a date the user asked for, is listed even without entries
/// once the list covers it (see [listCovers]), and stretches [to] when
/// later.
List<CalendarDay> calendarDays({
  required CalendarDate today,
  required CalendarDate to,
  required List<Workout> workouts,
  required bool more,
  required List<CardioSession> cardio,
  ActiveProgram? active,
  Program? program,
  CalendarDate? revealed,
}) {
  final floor = listFloor(workouts, more: more);
  final last = revealed != null && revealed.isAfter(to) ? revealed : to;
  final entries = calendarEntries(
    from:
        floor ??
        [
          today,
          ?revealed,
          ?workouts.lastOrNull?.startDate,
          for (final session in cardio) CardioEntry(session).date,
          ?active?.nextDate,
        ].reduce((a, b) => a.isBefore(b) ? a : b),
    to: last,
    today: today,
    workouts: workouts,
    cardio: cardio,
    active: active,
    program: program,
  );
  if (floor != null) entries[floor]?.removeWhere((e) => e is! WorkoutEntry);
  if (revealed != null && listCovers(revealed, floor)) {
    entries.putIfAbsent(revealed, () => []);
  }
  final dates = entries.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final date in dates)
      CalendarDay(date, [
        // calendarEntries lists what was done oldest first.
        ...entries[date]!.where((e) => e is! PlanEntry).toList().reversed,
        ...entries[date]!.whereType<PlanEntry>(),
      ]),
  ];
}
