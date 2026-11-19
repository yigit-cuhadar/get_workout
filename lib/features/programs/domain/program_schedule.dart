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
/// [ActiveProgram.nextDate]; after it, every training weekday does the day
/// [ActiveProgram.schedule] gives it. A day moved to another date keeps
/// its own day there, in place of that date's. Dates are calendar dates,
/// so daylight saving changes never shift them.
class ProgramSchedule {
  ProgramSchedule(this.active, {required this.dayCount, this.lengthWeeks})
    : assert(dayCount > 0);

  final ActiveProgram active;

  /// The program's days now; it may have changed since it was started.
  final int dayCount;
  final int? lengthWeeks;

  /// A program started on [today]: the first training weekday from today
  /// on, with its day.
  static ActiveProgram start({
    required String programId,
    required Map<int, int> schedule,
    required CalendarDate today,
    required DateTime startedAt,
  }) {
    final date = nextWeekday(schedule.keys, from: today);
    return ActiveProgram(
      programId: programId,
      schedule: schedule,
      nextDayIndex: schedule[date.weekday]!,
      nextDate: date,
      startedAt: startedAt,
    );
  }

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

  /// [weekdays] doing the program's days in turn, by ascending weekday:
  /// the first day on the first weekday, the second on the next, and so on.
  static Map<int, int> inTurn(Iterable<int> weekdays, int dayCount) {
    final sorted = weekdays.toSet().toList()..sort();
    return {for (final (i, weekday) in sorted.indexed) weekday: i % dayCount};
  }

  /// [suggestedWeekdays] doing the program's days in turn.
  static Map<int, int> suggestedSchedule(int dayCount) =>
      inTurn(suggestedWeekdays(dayCount), dayCount);

  /// At least one training weekday, each from 1 to 7 doing a day of the
  /// program.
  static bool isValidSchedule(Map<int, int> schedule, int dayCount) =>
      schedule.isNotEmpty &&
      schedule.entries.every(
        (entry) =>
            entry.key >= 1 &&
            entry.key <= 7 &&
            entry.value >= 0 &&
            entry.value < dayCount,
      );

  /// The first date from [from] on, [from] included, on one of [weekdays].
  static CalendarDate nextWeekday(
    Iterable<int> weekdays, {
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

  /// The day [ActiveProgram.schedule] gives training weekday [weekday],
  /// kept inside a program that lost days.
  int dayOn(int weekday) => active.schedule[weekday]! % dayCount;

  /// The next day planned for the first training weekday from [from] on,
  /// with that weekday's own day.
  ActiveProgram _nextFrom(CalendarDate from) {
    final date = nextWeekday(active.weekdays, from: from);
    return active.copyWith(nextDayIndex: dayOn(date.weekday), nextDate: date);
  }

  /// The first date after the program, when it has a length: [lengthWeeks]
  /// weeks after the date it was started.
  CalendarDate? get end {
    final weeks = lengthWeeks;
    if (weeks == null) return null;
    return CalendarDate.of(active.startedAt.toLocal()).addDays(weeks * 7);
  }

  /// The program's week [today] falls in, counted in whole weeks from the
  /// date it was started (as [end] is), from 1 and at most [lengthWeeks].
  int week(CalendarDate today) {
    final started = CalendarDate.of(active.startedAt.toLocal());
    final week = today.daysSince(started) ~/ 7 + 1;
    final weeks = lengthWeeks;
    if (week < 1) return 1;
    return weeks != null && week > weeks ? weeks : week;
  }

  /// The week of this run a workout on [date] falls in (see [week]); null
  /// before the run started, when the workout belongs to an earlier one.
  int? runWeek(CalendarDate date) =>
      date.isBefore(CalendarDate.of(active.startedAt.toLocal()))
      ? null
      : week(date);

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
  /// as planned on [today]: the next day, then each training weekday's own
  /// day. A missed next day is not done yet, so it comes first again, on
  /// the first training weekday from today on.
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
      date = nextWeekday(active.weekdays, from: date.addDays(1));
      dayIndex = dayOn(date.weekday);
    }
  }

  /// The plan of [today]'s week, starting on ISO weekday [firstWeekday];
  /// see [plan].
  List<PlannedDay> weekPlan(
    CalendarDate today, {
    required int firstWeekday,
    List<CompletedDay> completed = const [],
  }) {
    final start = today.startOfWeek(firstWeekday);
    return plan(today, from: start, to: start.addDays(6), completed: completed);
  }

  /// The plan from [from] to [to], both included, as planned on [today],
  /// by date: the [completed] days in the range as done, each once, a
  /// missed next day once on the date it was planned for, and the
  /// [upcoming] days falling in the range. A day not done yet that was
  /// done on its date anyway (the program did not move on) shows only as
  /// done.
  List<PlannedDay> plan(
    CalendarDate today, {
    required CalendarDate from,
    required CalendarDate to,
    List<CompletedDay> completed = const [],
  }) {
    final after = to.addDays(1);
    bool inRange(CalendarDate date) =>
        !date.isBefore(from) && date.isBefore(after);
    final done = {
      for (final day in completed)
        if (inRange(day.date)) day,
    };
    bool undone(CalendarDate date, int dayIndex) =>
        !done.contains(CompletedDay(date: date, dayIndex: dayIndex));
    final plan = [
      for (final day in done)
        PlannedDay(
          date: day.date,
          dayIndex: day.dayIndex,
          status: PlannedStatus.done,
        ),
      if (isMissed(today) &&
          inRange(active.nextDate) &&
          undone(active.nextDate, nextDayIndex))
        PlannedDay(
          date: active.nextDate,
          dayIndex: nextDayIndex,
          status: PlannedStatus.missed,
        ),
      for (final day in upcoming(
        today,
      ).takeWhile((day) => day.date.isBefore(after)))
        if (inRange(day.date) && undone(day.date, day.dayIndex))
          PlannedDay(
            date: day.date,
            dayIndex: day.dayIndex,
            status: PlannedStatus.planned,
          ),
    ];
    // Stable, so a date's done day stays before its planned one.
    return plan..sort((a, b) => a.date.compareTo(b.date));
  }

  /// The next day moved to [date]; the days after it follow from there.
  ActiveProgram moveNext(CalendarDate date) => active.copyWith(nextDate: date);

  /// The dates the next day may move to on [today]: from today to the
  /// last day of its planned date's week (today's when it was missed),
  /// weeks starting on ISO weekday [firstWeekday]; its own date included
  /// when not missed.
  List<CalendarDate> moveDates(
    CalendarDate today, {
    required int firstWeekday,
  }) {
    final planned = active.nextDate;
    final week = (planned.isBefore(today) ? today : planned).startOfWeek(
      firstWeekday,
    );
    final last = week.addDays(6);
    return [
      for (var date = today; !date.isAfter(last); date = date.addDays(1)) date,
    ];
  }

  /// Missed day, option 1: do it today; the following days follow from
  /// there.
  ActiveProgram doToday(CalendarDate today) =>
      active.copyWith(nextDayIndex: nextDayIndex, nextDate: today);

  /// Missed day, option 2: move it to the first training weekday after
  /// today, in place of that weekday's own day.
  ActiveProgram moveToNextWeekday(CalendarDate today) => active.copyWith(
    nextDayIndex: nextDayIndex,
    nextDate: nextWeekday(active.weekdays, from: today.addDays(1)),
  );

  /// Missed day, option 3: leave it out; the first training weekday from
  /// today on does its own day.
  ActiveProgram skip(CalendarDate today) => _nextFrom(today);

  /// The next day was done [on] that date, planned or not: the first
  /// training weekday after [on] comes next, with its own day.
  ActiveProgram complete({required CalendarDate on}) =>
      _nextFrom(on.addDays(1));

  /// Trains on [schedule] from now on. The next day is the first of its
  /// weekdays from today on, or from tomorrow when it was already planned
  /// after today (today's day may be done), with that weekday's day.
  ActiveProgram withSchedule(Map<int, int> schedule, CalendarDate today) =>
      ProgramSchedule(
        active.copyWith(schedule: schedule),
        dayCount: dayCount,
        lengthWeeks: lengthWeeks,
      )._nextFrom(active.nextDate.isAfter(today) ? today.addDays(1) : today);
}
