import 'dart:math' as math;

import '../../settings/domain/user_settings.dart';
import '../../workout/domain/exercise_stats.dart';

/// The time ranges of an exercise's e1RM chart. Free users see
/// [StrengthRange.free]; the longer ones are Premium.
enum StrengthRange {
  weeks12,
  months6,
  year1,
  all;

  static const free = weeks12;

  bool get premium => this != free;

  /// The first day shown, from its local midnight; null for [all].
  DateTime? start(DateTime now) => switch (this) {
    weeks12 => DateTime(now.year, now.month, now.day - 7 * 12),
    months6 => _monthsBefore(now, 6),
    year1 => _monthsBefore(now, 12),
    all => null,
  };

  /// What a user with [premium] (null: not known yet) is shown when they
  /// chose this range.
  StrengthRange allowed(bool? premium) =>
      this.premium && premium != true ? free : this;
}

/// [now]'s day [months] months earlier, at midnight; past the end of that
/// month (August 31 to February), its last day.
DateTime _monthsBefore(DateTime now, int months) {
  final month = DateTime(now.year, now.month - months);
  final lastDay = DateTime(month.year, month.month + 1, 0).day;
  return DateTime(month.year, month.month, math.min(now.day, lastDay));
}

/// One workout's best estimated one-rep max, in the user's weight unit.
typedef E1rmPoint = ({DateTime date, double value, String workoutId});

/// The workouts of [history] in [range] (see [StrengthRange.start]) that
/// have an e1RM, oldest first, their value in [unit].
List<E1rmPoint> e1rmSeries(
  List<HistoryPoint> history, {
  required StrengthRange range,
  required DateTime now,
  required WeightUnit unit,
}) {
  final start = range.start(now);
  return [
    for (final point in history)
      if (point.bestE1rmKg case final kg?)
        if (start == null || !point.date.isBefore(start))
          (
            date: point.date,
            value: unit.fromKg(kg),
            workoutId: point.workoutId,
          ),
  ];
}

/// Whether [history] has an e1RM from before [range] starts: results a free
/// user is told exist, behind Premium.
bool hasE1rmBefore(
  List<HistoryPoint> history, {
  required StrengthRange range,
  required DateTime now,
}) {
  final start = range.start(now);
  return start != null &&
      history.any(
        (point) => point.bestE1rmKg != null && point.date.isBefore(start),
      );
}

typedef RecordEntry = ({RecordKind kind, StatRecord record});

/// The order records are listed in.
const recordOrder = [
  RecordKind.heaviestWeight,
  RecordKind.bestE1rm,
  RecordKind.mostReps,
  RecordKind.bestSetVolume,
  RecordKind.longestDuration,
];

/// [stats]' records in [recordOrder]; kinds without one are left out.
List<RecordEntry> orderedRecords(ExerciseStats stats) => [
  for (final kind in recordOrder)
    if (stats.records[kind] case final record?) (kind: kind, record: record),
];

typedef TrainedExercise = ({String exerciseId, DateTime lastTrained});

/// The exercises of [stats] by when they were last done, most recent
/// first; stats with no workout are left out.
List<TrainedExercise> byLastTrained(Map<String, ExerciseStats> stats) {
  final trained = [
    for (final MapEntry(key: id, value: stats) in stats.entries)
      if (stats.last?.date ?? stats.history.lastOrNull?.date case final date?)
        (exerciseId: id, lastTrained: date),
  ];
  return trained..sort((a, b) {
    final byDate = b.lastTrained.compareTo(a.lastTrained);
    return byDate != 0 ? byDate : a.exerciseId.compareTo(b.exerciseId);
  });
}
