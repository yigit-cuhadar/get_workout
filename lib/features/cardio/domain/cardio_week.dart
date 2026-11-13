import 'package:forge_core/forge_core.dart';

import 'cardio_session.dart';

/// The sessions of one week, which runs from 00:00 local time of its first
/// day.
class CardioWeek extends Equatable {
  const CardioWeek(this.start, this.sessions);

  /// Local midnight of the week's first day.
  final DateTime start;
  final List<CardioSession> sessions;

  Duration get duration =>
      sessions.fold(Duration.zero, (sum, session) => sum + session.duration);

  /// The distance of the sessions that have one; null when none has.
  double? get distanceKm {
    final distances = sessions.map((s) => s.distanceKm).nonNulls;
    return distances.isEmpty ? null : distances.reduce((a, b) => a + b);
  }

  @override
  List<Object?> get props => [start, sessions];
}

/// Local midnight of the first day of [time]'s week, for weeks starting on
/// ISO weekday [firstWeekday] (1 Monday to 7 Sunday). Built from calendar
/// fields, so a daylight saving change inside the week does not shift it.
DateTime weekStart(DateTime time, int firstWeekday) {
  final local = time.toLocal();
  return DateTime(
    local.year,
    local.month,
    local.day - (local.weekday - firstWeekday) % DateTime.daysPerWeek,
  );
}

/// The weeks that have sessions, newest first, starting on ISO weekday
/// [firstWeekday]; [sessions] must be sorted newest first and keep that
/// order within each week.
List<CardioWeek> groupByWeek(List<CardioSession> sessions, int firstWeekday) {
  final weeks = <DateTime, List<CardioSession>>{};
  for (final session in sessions) {
    weeks
        .putIfAbsent(weekStart(session.date, firstWeekday), () => [])
        .add(session);
  }
  return [
    for (final MapEntry(:key, :value) in weeks.entries) CardioWeek(key, value),
  ];
}

/// The [count] weeks up to and including [now]'s, oldest first, empty weeks
/// included, starting on ISO weekday [firstWeekday].
List<CardioWeek> lastWeeks(
  List<CardioSession> sessions,
  int firstWeekday, {
  required DateTime now,
  int count = 12,
}) {
  final current = weekStart(now, firstWeekday);
  final starts = [
    for (var i = count - 1; i >= 0; i--)
      DateTime(current.year, current.month, current.day - 7 * i),
  ];
  final byWeek = {for (final start in starts) start: <CardioSession>[]};
  for (final session in sessions) {
    byWeek[weekStart(session.date, firstWeekday)]?.add(session);
  }
  return [for (final start in starts) CardioWeek(start, byWeek[start]!)];
}
