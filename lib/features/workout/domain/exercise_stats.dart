import 'package:forge_core/forge_core.dart';

import '../../../core/one_rep_max.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../programs/domain/program.dart';
import 'set_logging.dart';
import 'workout.dart';

/// The records kept per exercise. Weights are kg, durations seconds, volume
/// kg (weight × reps).
enum RecordKind implements Coded {
  heaviestWeight('heaviestWeight'),
  bestE1rm('bestE1rm'),
  bestSetVolume('bestSetVolume'),
  mostReps('mostReps'),
  longestDuration('longestDuration');

  const RecordKind(this.code);
  @override
  final String code;

  /// The records an exercise of [type] has. Assistance is never a record:
  /// less of it is better, and it is no load.
  static Set<RecordKind> of(LoggingType type) => {
    if (type.logsWeight && type != LoggingType.assistedBodyweight)
      heaviestWeight,
    if (type.logsLoad) ...{bestE1rm, bestSetVolume},
    if (type.logsReps) mostReps,
    if (type.isDurationBased) longestDuration,
  };
}

class StatRecord extends Equatable {
  const StatRecord({
    required this.value,
    required this.date,
    required this.workoutId,
  });

  final double value;

  /// When the workout started.
  final DateTime date;
  final String workoutId;

  @override
  List<Object?> get props => [value, date, workoutId];
}

/// The exercise's sets in its latest workout, shown as "last time".
class LastSession extends Equatable {
  const LastSession({
    required this.date,
    required this.workoutId,
    required this.sets,
  });

  final DateTime date;
  final String workoutId;
  final List<WorkoutSet> sets;

  @override
  List<Object?> get props => [date, workoutId, sets];
}

/// One workout's result for the exercise's progress chart.
class HistoryPoint extends Equatable {
  const HistoryPoint({
    required this.date,
    required this.workoutId,
    this.bestE1rmKg,
    this.volumeKg = 0,
  });

  final DateTime date;
  final String workoutId;
  final double? bestE1rmKg;
  final double volumeKg;

  @override
  List<Object?> get props => [date, workoutId, bestE1rmKg, volumeKg];
}

/// The summary of an exercise's workouts
/// (`users/{uid}/exerciseStats/{exerciseId}`), the only derived numbers
/// that are stored. Everything here follows from the workouts, so
/// [rebuildStats] recreates it after one is edited or deleted.
class ExerciseStats extends Equatable {
  const ExerciseStats({
    this.records = const {},
    this.last,
    this.history = const [],
  });

  /// The most points kept, oldest dropped first; years of training.
  static const maxHistory = 1000;

  final Map<RecordKind, StatRecord> records;
  final LastSession? last;

  /// Oldest first, one point per workout.
  final List<HistoryPoint> history;

  @override
  List<Object?> get props => [records, last, history];
}

/// A record [workoutId] set, beating an earlier one.
class NewRecord extends Equatable {
  const NewRecord({
    required this.exerciseId,
    required this.name,
    required this.kind,
    required this.value,
  });

  final String exerciseId;
  final String name;
  final RecordKind kind;
  final double value;

  @override
  List<Object?> get props => [exerciseId, name, kind, value];
}

/// What a finished workout amounted to.
class WorkoutSummary extends Equatable {
  const WorkoutSummary({
    required this.duration,
    required this.volumeKg,
    required this.setCount,
    required this.exerciseCount,
    this.records = const [],
  });

  final Duration duration;
  final double volumeKg;

  /// Done working sets; warm-ups do not count.
  final int setCount;
  final int exerciseCount;
  final List<NewRecord> records;

  @override
  List<Object?> get props => [
    duration,
    volumeKg,
    setCount,
    exerciseCount,
    records,
  ];
}

/// Weight × reps of [set], drops included; zero for types without a load.
double setVolume(WorkoutSet set, LoggingType type) {
  if (!type.logsLoad) return 0;
  double part(double? kg, int? reps) => (kg ?? 0) * (reps ?? 0);
  return set.drops.fold(
    part(set.weightKg, set.reps),
    (sum, drop) => sum + part(drop.weightKg, drop.reps),
  );
}

/// The estimated one-rep max of [set]'s main part; null where it does not
/// apply. See [epleyOneRepMax].
double? setE1rm(WorkoutSet set, LoggingType type) {
  final weight = set.weightKg;
  final reps = set.reps;
  if (!type.logsLoad || weight == null || reps == null) return null;
  return epleyOneRepMax(weight, reps);
}

/// The done working sets of [sets]: what records and volume count.
List<WorkoutSet> workingSets(Iterable<WorkoutSet> sets) => [
  for (final set in sets)
    if (set.done && !set.isWarmup) set,
];

/// The best value of each record kind of [type] among [sets]' done working
/// sets. Kinds without a value above zero are left out.
Map<RecordKind, double> sessionBests(
  Iterable<WorkoutSet> sets,
  LoggingType type,
) {
  final kinds = RecordKind.of(type);
  final best = <RecordKind, double>{};
  void offer(RecordKind kind, num? value) {
    if (!kinds.contains(kind) || value == null || !(value > 0)) return;
    final current = best[kind];
    if (current == null || value > current) best[kind] = value.toDouble();
  }

  for (final set in workingSets(sets)) {
    offer(RecordKind.heaviestWeight, set.weightKg);
    offer(RecordKind.bestE1rm, setE1rm(set, type));
    offer(RecordKind.bestSetVolume, setVolume(set, type));
    offer(RecordKind.mostReps, set.reps);
    offer(RecordKind.longestDuration, set.durationS);
  }
  return best;
}

/// Volume of [sets]' done working sets.
double sessionVolume(Iterable<WorkoutSet> sets, LoggingType type) =>
    workingSets(sets).fold(0, (sum, set) => sum + setVolume(set, type));

/// [stats] (null: none yet) with [workout]'s sets of [exerciseId] added:
/// records it beats, `last` when it is the latest workout, and its history
/// point, replacing one of the same workout. Unchanged when [workout] has
/// no done set of the exercise. Applying a workout twice changes nothing
/// the second time.
ExerciseStats? applyWorkout(
  ExerciseStats? stats,
  Workout workout,
  String exerciseId,
) {
  final entries = [
    for (final exercise in workout.exercises)
      if (exercise.exerciseId == exerciseId) exercise,
  ];
  final done = [for (final entry in entries) ...entry.doneSets];
  if (done.isEmpty) return stats;
  final type = entries.first.loggingType;
  final date = workout.startedAt;
  final records = {...?stats?.records};
  for (final MapEntry(key: kind, :value) in sessionBests(done, type).entries) {
    final current = records[kind];
    if (current == null || value > current.value) {
      records[kind] = StatRecord(
        value: value,
        date: date,
        workoutId: workout.id,
      );
    }
  }
  final last = stats?.last;
  final bests = [for (final set in workingSets(done)) ?setE1rm(set, type)];
  final history = [
    for (final point in stats?.history ?? const <HistoryPoint>[])
      if (point.workoutId != workout.id) point,
    HistoryPoint(
      date: date,
      workoutId: workout.id,
      bestE1rmKg: bests.isEmpty ? null : bests.reduce((a, b) => a > b ? a : b),
      volumeKg: sessionVolume(done, type),
    ),
  ]..sort((a, b) => a.date.compareTo(b.date));
  return ExerciseStats(
    records: records,
    last: last == null || !date.isBefore(last.date)
        ? LastSession(date: date, workoutId: workout.id, sets: done)
        : last,
    history: history.length > ExerciseStats.maxHistory
        ? history.sublist(history.length - ExerciseStats.maxHistory)
        : history,
  );
}

/// The stats of [exerciseId] from scratch, from every workout doing it;
/// null when none does.
ExerciseStats? rebuildStats(String exerciseId, Iterable<Workout> workouts) {
  final ordered = [...workouts]
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  return ordered.fold<ExerciseStats?>(
    null,
    (stats, workout) => applyWorkout(stats, workout, exerciseId),
  );
}

/// The records [workout] set in [after] that beat a record of [before]. A
/// first workout of an exercise sets no new record: there is nothing to
/// beat.
List<RecordKind> beatenRecords(
  ExerciseStats? before,
  ExerciseStats? after,
  Workout workout,
) => [
  for (final kind in RecordKind.values)
    if ((after?.records[kind], before?.records[kind])
        case (final record?, final previous?)
        when record.workoutId == workout.id && previous.workoutId != workout.id)
      kind,
];

/// The summary of finished [workout] with the [records] it set.
WorkoutSummary summarizeWorkout(Workout workout, List<NewRecord> records) {
  final finished = workout.finishedAt ?? workout.startedAt;
  return WorkoutSummary(
    duration: finished.difference(workout.startedAt),
    volumeKg: workout.exercises.fold(
      0,
      (sum, e) => sum + sessionVolume(e.sets, e.loggingType),
    ),
    setCount: workout.exercises.fold(
      0,
      (count, e) => count + workingSets(e.sets).length,
    ),
    exerciseCount: workout.exerciseIds.length,
    records: records,
  );
}
