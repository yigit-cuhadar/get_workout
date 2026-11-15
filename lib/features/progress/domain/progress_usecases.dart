import 'package:forge_core/forge_core.dart';

import '../../strength/domain/strength.dart';
import '../../workout/domain/exercise_stats.dart';
import '../../workout/domain/workout_repository.dart';

/// How an exercise's estimated one-rep max moved: [kg] over [weeks].
typedef E1rmChange = ({double kg, int weeks});

/// The exercise the Progress tab's Strength card shows: its latest
/// workout's best estimated one-rep max, in kg, and its [change] since the
/// first one of the last 12 weeks; null with a single one there.
class StrengthHighlight extends Equatable {
  const StrengthHighlight({
    required this.exerciseId,
    required this.e1rmKg,
    this.change,
  });

  final String exerciseId;
  final double e1rmKg;
  final E1rmChange? change;

  @override
  List<Object?> get props => [exerciseId, e1rmKg, change];
}

/// The most recently trained exercise of [stats] that has an estimated
/// one-rep max (ties by id), as of [now]; null when none has.
StrengthHighlight? strengthHighlight(
  Map<String, ExerciseStats> stats, {
  required DateTime now,
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
  final start = StrengthRange.weeks12.start(now)!;
  // The latest is the last point, so one in the 12 weeks exists if it is.
  final first = latest.date.isBefore(start)
      ? latest
      : newest.points.firstWhere((point) => !point.date.isBefore(start));
  return StrengthHighlight(
    exerciseId: newest.id,
    e1rmKg: latest.bestE1rmKg!,
    change: identical(first, latest)
        ? null
        : (
            kg: latest.bestE1rmKg! - first.bestE1rmKg!,
            // A change within a week still reads "in 1 week".
            weeks: (latest.date.difference(first.date).inDays / 7)
                .round()
                .clamp(1, 12),
          ),
  );
}

/// A user's [strengthHighlight], and whether they have trained at all.
typedef StrengthHighlights = ({StrengthHighlight? highlight, bool trained});

/// [StrengthHighlights] of user [String], again on every change.
class WatchStrengthHighlights {
  const WatchStrengthHighlights(this._repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final WorkoutRepository _repository;
  final DateTime Function() _clock;

  Stream<StrengthHighlights> call(String uid) => _repository
      .watchAllStats(uid)
      .map(
        (stats) => (
          highlight: strengthHighlight(stats, now: _clock()),
          trained: stats.isNotEmpty,
        ),
      );
}
