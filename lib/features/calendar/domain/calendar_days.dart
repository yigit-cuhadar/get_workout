import 'package:forge_core/forge_core.dart';

import '../../programs/domain/calendar_date.dart';
import '../../programs/domain/program_schedule.dart';
import 'calendar_month.dart';

/// What the calendar shows: everything, or only workouts (with the
/// program's planned and missed days) or only cardio.
enum CalendarFilter { all, workouts, cardio }

/// [entries] that [filter] keeps.
List<CalendarEntry> filterEntries(
  List<CalendarEntry> entries,
  CalendarFilter filter,
) => switch (filter) {
  CalendarFilter.all => entries,
  CalendarFilter.workouts => [
    for (final entry in entries)
      if (entry is! CardioEntry) entry,
  ],
  CalendarFilter.cardio => [
    for (final entry in entries)
      if (entry is CardioEntry) entry,
  ],
};

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

/// [date] with its [entries] as the list shows them.
CalendarDay calendarDay(CalendarDate date, List<CalendarEntry> entries) =>
    CalendarDay(date, [
      ...entries.where((e) => e is! PlanEntry).toList().reversed,
      ...entries.whereType<PlanEntry>(),
    ]);

/// Which part of a month a [CalendarSection] holds.
enum CalendarSectionKind {
  /// The current week, of the current month.
  thisWeek,

  /// The current month's days before this week.
  earlierThisMonth,

  /// A week of another month, within that month.
  week,
}

/// One section of a month's list: its [kind], its first and [last] dates
/// and its [days] with entries, newest first.
class CalendarSection extends Equatable {
  const CalendarSection(this.kind, this.first, this.last, this.days);

  final CalendarSectionKind kind;
  final CalendarDate first;
  final CalendarDate last;
  final List<CalendarDay> days;

  @override
  List<Object?> get props => [kind, first, last, days];
}

/// The list of [month]'s month: for the current one (holding [today]) this
/// week (today first, then the days to come in date order, then its past
/// days newest first), then the month's days before it; for any other month
/// its weeks (from ISO weekday [firstWeekday], within the month), newest
/// first.
/// Days without entries, and sections without days, are left out.
/// [entriesOn] gives a date's entries, already filtered.
List<CalendarSection> monthSections(
  CalendarDate month, {
  required CalendarDate today,
  required int firstWeekday,
  required List<CalendarEntry> Function(CalendarDate date) entriesOn,
}) {
  final first = monthOf(month);
  final last = addMonths(first, 1).addDays(-1);
  CalendarSection? section(
    CalendarSectionKind kind,
    CalendarDate from,
    CalendarDate to,
  ) {
    final days = [
      for (var date = to; !date.isBefore(from); date = date.addDays(-1))
        if (entriesOn(date) case final entries when entries.isNotEmpty)
          calendarDay(date, entries),
    ];
    return days.isEmpty ? null : CalendarSection(kind, from, to, days);
  }

  if (monthOf(today) == first) {
    final week = today.startOfWeek(firstWeekday);
    final thisWeek = section(
      CalendarSectionKind.thisWeek,
      week,
      week.addDays(6),
    );
    int rank(CalendarDate date) => date == today
        ? 0
        : date.isAfter(today)
        ? 1
        : 2;
    return [
      if (thisWeek != null)
        CalendarSection(
          thisWeek.kind,
          thisWeek.first,
          thisWeek.last,
          [...thisWeek.days]..sort((a, b) {
            final byRank = rank(a.date).compareTo(rank(b.date));
            if (byRank != 0) return byRank;
            // Days to come ascend; past days descend.
            return rank(a.date) == 1
                ? a.date.compareTo(b.date)
                : b.date.compareTo(a.date);
          }),
        ),
      if (week.isAfter(first))
        ?section(CalendarSectionKind.earlierThisMonth, first, week.addDays(-1)),
    ];
  }
  return [
    for (final week in monthWeeks(first, firstWeekday: firstWeekday).reversed)
      ?section(
        CalendarSectionKind.week,
        week.first.isBefore(first) ? first : week.first,
        week.last.isAfter(last) ? last : week.last,
      ),
  ];
}

/// Counts of [month]'s month for its summary line.
typedef MonthCounts = ({int workouts, int cardio, int missed});

/// What [entriesOn] (already filtered) holds over [month]'s month.
MonthCounts monthCounts(
  CalendarDate month,
  List<CalendarEntry> Function(CalendarDate date) entriesOn,
) {
  var (workouts, cardio, missed) = (0, 0, 0);
  final first = monthOf(month);
  final next = addMonths(first, 1);
  for (var date = first; date.isBefore(next); date = date.addDays(1)) {
    for (final entry in entriesOn(date)) {
      switch (entry) {
        case WorkoutEntry():
          workouts++;
        case CardioEntry():
          cardio++;
        case PlanEntry(:final day) when day.status == PlannedStatus.missed:
          missed++;
        case PlanEntry():
      }
    }
  }
  return (workouts: workouts, cardio: cardio, missed: missed);
}
