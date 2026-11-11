import 'package:forge_core/forge_core.dart';

import 'active_program.dart';
import 'calendar_date.dart';
import 'completed_days.dart';

enum PlannedStatus { done, missed, planned }

/// A program day on a date of the plan.
class PlannedDay extends Equatable {
  const PlannedDay({
    required this.date,
    required this.dayIndex,
    required this.status,
  });

  final CalendarDate date;
  final int dayIndex;
  final PlannedStatus status;

  @override
  List<Object?> get props => [date, dayIndex, status];
}

/// When the days of an active program fall. The next day is planned for
/// [ActiveProgram.nextDate]; every following one for the next selected
/// weekday after the one before, cycling through the program's days. Dates
/// are calendar dates, so daylight saving changes never shift them.
class ProgramSchedule {
  ProgramSchedule(this.active, {required this.dayCount, this.lengthWeeks})
    : assert(dayCount > 0);

  final ActiveProgram active;

  /// The program's days now; it may have changed since it was started.
  final int dayCount;
  final int? lengthWeeks;

  /// A program started on [today]: its first day, on the first selected
  /// weekday from today on.
  static ActiveProgram start({
    required String programId,
    required List<int> weekdays,
    required CalendarDate today,
    required DateTime startedAt,
  }) => ActiveProgram(
    programId: programId,
    weekdays: weekdays,
    nextDayIndex: 0,
    nextDate: nextWeekday(weekdays, from: today),
    startedAt: startedAt,
  );

  /// Weekdays to offer for a program of [dayCount] days, spread over the
  /// week.
  static List<int> suggestedWeekdays(int dayCount) => switch (dayCount) {
    <= 1 => const [1],
    2 => const [1, 4],
    3 => const [1, 3, 5],
    4 => const [1, 2, 4, 5],
    5 => const [1, 2, 3, 4, 5],
    6 => const [1, 2, 3, 4, 5, 6],
    _ => const [1, 2, 3, 4, 5, 6, 7],
  };

  /// One distinct ISO weekday per program day.
  static bool isValidWeekdays(List<int> weekdays, int dayCount) =>
      weekdays.length == dayCount &&
      weekdays.toSet().length == weekdays.length &&
      weekdays.every((day) => day >= 1 && day <= 7);

  /// The first date from [from] on, [from] included, on one of [weekdays].
  static CalendarDate nextWeekday(
    List<int> weekdays, {
    required CalendarDate from,
  }) {
    for (var offset = 0; offset < 7; offset++) {
      final date = from.addDays(offset);
      if (weekdays.contains(date.weekday)) return date;
    }
    throw ArgumentError.value(weekdays, 'weekdays', 'no weekday from 1 to 7');
  }

  /// [ActiveProgram.nextDayIndex], kept inside a program that lost days.
  int get nextDayIndex => active.nextDayIndex % dayCount;

  /// The first date after the program, when it has a length: [lengthWeeks]
  /// weeks after the date it was started.
  CalendarDate? get end {
    final weeks = lengthWeeks;
    if (weeks == null) return null;
    return CalendarDate.of(active.startedAt.toLocal()).addDays(weeks * 7);
  }

  /// Whether the program is over: the next day could only fall on or after
  /// [end].
  bool isFinished(CalendarDate today) {
    final end = this.end;
    if (end == null) return false;
    final latest = active.nextDate.isAfter(today) ? active.nextDate : today;
    return !latest.isBefore(end);
  }

  /// The next day's date has passed without it being done.
  bool isMissed(CalendarDate today) =>
      !isFinished(today) && active.nextDate.isBefore(today);

  /// The program days from the next one on, with their dates, up to [end],
  /// as planned on [today]. A missed next day is not done yet, so it comes
  /// first again, on the first selected weekday from today on.
  Iterable<({int dayIndex, CalendarDate date})> upcoming(
    CalendarDate today,
  ) sync* {
    final end = this.end;
    var dayIndex = nextDayIndex;
    var date = active.nextDate.isBefore(today)
        ? nextWeekday(active.weekdays, from: today)
        : active.nextDate;
    while (end == null || date.isBefore(end)) {
      yield (dayIndex: dayIndex, date: date);
      dayIndex = (dayIndex + 1) % dayCount;
      date = nextWeekday(active.weekdays, from: date.addDays(1));
    }
  }

  /// The plan of [today]'s week, Monday to Sunday, by date: the [completed]
  /// days of the week as done, a missed next day once on the date it was
  /// planned for, and the [upcoming] days falling in the week.
  List<PlannedDay> weekPlan(
    CalendarDate today, {
    List<CompletedDay> completed = const [],
  }) {
    final start = today.weekStart;
    final next = start.addDays(7);
    bool inWeek(CalendarDate date) =>
        !date.isBefore(start) && date.isBefore(next);
    final plan = [
      for (final day in completed)
        if (inWeek(day.date))
          PlannedDay(
            date: day.date,
            dayIndex: day.dayIndex,
            status: PlannedStatus.done,
          ),
      if (isMissed(today) && inWeek(active.nextDate))
        PlannedDay(
          date: active.nextDate,
          dayIndex: nextDayIndex,
          status: PlannedStatus.missed,
        ),
      for (final day in upcoming(
        today,
      ).takeWhile((day) => day.date.isBefore(next)))
        PlannedDay(
          date: day.date,
          dayIndex: day.dayIndex,
          status: PlannedStatus.planned,
        ),
    ];
    // Stable, so a date's done day stays before its planned one.
    return plan..sort((a, b) => a.date.compareTo(b.date));
  }

  /// Missed day, option 1: do it today; the following days follow from
  /// there.
  ActiveProgram doToday(CalendarDate today) =>
      active.copyWith(nextDayIndex: nextDayIndex, nextDate: today);

  /// Missed day, option 2: move it to the first selected weekday after
  /// today, shifting the following days.
  ActiveProgram moveToNextWeekday(CalendarDate today) => active.copyWith(
    nextDayIndex: nextDayIndex,
    nextDate: nextWeekday(active.weekdays, from: today.addDays(1)),
  );

  /// Missed day, option 3: leave it out and plan the day after it for the
  /// first selected weekday from today on.
  ActiveProgram skip(CalendarDate today) => active.copyWith(
    nextDayIndex: (nextDayIndex + 1) % dayCount,
    nextDate: nextWeekday(active.weekdays, from: today),
  );

  /// Program day [dayIndex] was done [on] that date, planned or not: the day
  /// after it comes next, on the first selected weekday after [on].
  ActiveProgram complete({required int dayIndex, required CalendarDate on}) =>
      active.copyWith(
        nextDayIndex: (dayIndex + 1) % dayCount,
        nextDate: nextWeekday(active.weekdays, from: on.addDays(1)),
      );

  /// Trains on [weekdays] from now on. The next day moves to the first of
  /// them from today on, or from tomorrow when it was already planned
  /// after today (today's day may be done).
  ActiveProgram withWeekdays(List<int> weekdays, CalendarDate today) =>
      active.copyWith(
        weekdays: weekdays,
        nextDayIndex: nextDayIndex,
        nextDate: nextWeekday(
          weekdays,
          from: active.nextDate.isAfter(today) ? today.addDays(1) : today,
        ),
      );
}
