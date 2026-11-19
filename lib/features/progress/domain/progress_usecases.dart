import 'package:forge_core/forge_core.dart';

import '../../strength/domain/strength.dart';
import '../../workout/domain/exercise_stats.dart';

/// How a value in kg moved over a card's weeks: [kg] over [weeks].
typedef KgChange = ({double kg, int weeks});

/// The weeks a Progress card's line covers: the free charts' window, 12
/// with Premium ([premium] null while unknown).
int cardWeeks(bool? premium) =>
    premium == true ? premiumCardWeeks : StrengthRange.freeWeeks;

const premiumCardWeeks = 12;

/// The whole weeks from [first] to [last], 1 to [premiumCardWeeks]: a
/// change within a week still reads "in 1 week".
int changeWeeks(DateTime first, DateTime last) =>
    (last.difference(first).inDays / 7).round().clamp(1, premiumCardWeeks);

/// The exercise the Progress tab's Strength card shows: its latest
/// workout's best estimated one-rep max, in kg, its [change] since the
/// first one of the card's weeks (null with a single one there) and its
/// [trend], the bests of those weeks, oldest first.
class StrengthHighlight extends Equatable {
  const StrengthHighlight({
    required this.exerciseId,
    required this.e1rmKg,
    this.change,
    this.trend = const [],
  });

  final String exerciseId;
  final double e1rmKg;
  final KgChange? change;
  final List<double> trend;

  @override
  List<Object?> get props => [exerciseId, e1rmKg, change, trend];
}

/// The most recently trained exercise of [stats] that has an estimated
/// one-rep max (ties by id), as of [now] over the last [weeks]; null when
/// none has.
StrengthHighlight? strengthHighlight(
  Map<String, ExerciseStats> stats, {
  required DateTime now,
  required int weeks,
}) {
  ({String id, List<HistoryPoint> points})? newest;
  for (final MapEntry(key: id, value: stats) in stats.entries) {
    final points = [
      for (final point in stats.history)
        if (point.bestE1rmKg != null) point,
    ];
    if (points.isEmpty) continue;
    final order = switch (newest) {
      null => 1,
      final newest => switch (points.last.date.compareTo(
        newest.points.last.date,
      )) {
        0 => newest.id.compareTo(id),
        final byDate => byDate,
      },
    };
    if (order > 0) newest = (id: id, points: points);
  }
  if (newest == null) return null;
  final latest = newest.points.last;
  final start = weeksBefore(now, weeks);
  final recent = [
    for (final point in newest.points)
      if (!point.date.isBefore(start)) point,
  ];
  final first = recent.firstOrNull;
  return StrengthHighlight(
    exerciseId: newest.id,
    e1rmKg: latest.bestE1rmKg!,
    change: first == null || identical(first, latest)
        ? null
        : (
            kg: latest.bestE1rmKg! - first.bestE1rmKg!,
            weeks: changeWeeks(first.date, latest.date),
          ),
    trend: [for (final point in recent) point.bestE1rmKg!],
  );
}
