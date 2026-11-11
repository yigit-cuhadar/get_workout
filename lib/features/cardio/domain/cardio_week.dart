import 'package:forge_core/forge_core.dart';

import 'cardio_session.dart';

/// The sessions of one week, which runs from Monday 00:00 local time.
class CardioWeek extends Equatable {
  const CardioWeek(this.start, this.sessions);

  /// Local midnight of the week's Monday.
  final DateTime start;
  final List<CardioSession> sessions;

  Duration get duration =>
      sessions.fold(Duration.zero, (sum, session) => sum + session.duration);

  @override
  List<Object?> get props => [start, sessions];
}

/// Local midnight of the Monday of [time]'s week. Built from calendar fields,
/// so a daylight saving change inside the week does not shift it.
DateTime weekStart(DateTime time) {
  final local = time.toLocal();
  return DateTime(local.year, local.month, local.day - (local.weekday - 1));
}

/// The weeks that have sessions, newest first; [sessions] must be sorted
/// newest first and keep that order within each week.
List<CardioWeek> groupByWeek(List<CardioSession> sessions) {
  final weeks = <DateTime, List<CardioSession>>{};
  for (final session in sessions) {
    weeks.putIfAbsent(weekStart(session.date), () => []).add(session);
  }
  return [
    for (final MapEntry(:key, :value) in weeks.entries) CardioWeek(key, value),
  ];
}

/// The [count] weeks up to and including [now]'s, oldest first, empty weeks
/// included.
List<CardioWeek> lastWeeks(
  List<CardioSession> sessions, {
  required DateTime now,
  int count = 12,
}) {
  final current = weekStart(now);
  final starts = [
    for (var i = count - 1; i >= 0; i--)
      DateTime(current.year, current.month, current.day - 7 * i),
  ];
  final byWeek = {for (final start in starts) start: <CardioSession>[]};
  for (final session in sessions) {
    byWeek[weekStart(session.date)]?.add(session);
  }
  return [for (final start in starts) CardioWeek(start, byWeek[start]!)];
}
