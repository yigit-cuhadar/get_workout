import '../../programs/domain/calendar_date.dart';
import '../../workout/domain/exercise_stats.dart';
import '../../workout/domain/workout_repository.dart';

/// An exercise's best estimated one-rep max, in kg.
typedef StrengthHighlight = ({String exerciseId, double e1rmKg});

/// The [count] most recently trained exercises of [stats] that have a best
/// estimated one-rep max, most recent first; ties by id.
List<StrengthHighlight> strengthHighlights(
  Map<String, ExerciseStats> stats, {
  int count = 3,
}) {
  final trained = <({String exerciseId, double e1rmKg, DateTime date})>[];
  for (final MapEntry(key: id, value: stats) in stats.entries) {
    final kg = stats.records[RecordKind.bestE1rm]?.value;
    final date = stats.last?.date ?? stats.history.lastOrNull?.date;
    if (kg != null && date != null) {
      trained.add((exerciseId: id, e1rmKg: kg, date: date));
    }
  }
  trained.sort((a, b) {
    final byDate = b.date.compareTo(a.date);
    return byDate != 0 ? byDate : a.exerciseId.compareTo(b.exerciseId);
  });
  return [
    for (final item in trained.take(count))
      (exerciseId: item.exerciseId, e1rmKg: item.e1rmKg),
  ];
}

/// A user's [strengthHighlights], and whether they have trained at all.
typedef StrengthHighlights = ({List<StrengthHighlight> top, bool trained});

/// [StrengthHighlights] of user [String], again on every change.
class WatchStrengthHighlights {
  const WatchStrengthHighlights(this._repository);
  final WorkoutRepository _repository;

  Stream<StrengthHighlights> call(String uid) => _repository
      .watchAllStats(uid)
      .map(
        (stats) => (top: strengthHighlights(stats), trained: stats.isNotEmpty),
      );
}

/// [uid]'s finished workouts in the month of [day], counted.
typedef MonthQuery = ({String uid, CalendarDate day});

class WatchWorkoutCountInMonth {
  const WatchWorkoutCountInMonth(this._repository);
  final WorkoutRepository _repository;

  Stream<int> call(MonthQuery query) {
    final day = query.day;
    return _repository
        .watchWorkoutsBetween(
          query.uid,
          from: CalendarDate(day.year, day.month, 1),
          // Day 0 of the next month is this month's last.
          to: CalendarDate(day.year, day.month + 1, 0),
        )
        .map((workouts) => workouts.length);
  }
}
