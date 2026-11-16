import 'package:forge_core/forge_core.dart';

import '../../../core/one_rep_max.dart';
import '../../exercises/domain/muscle_volume.dart';
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
    this.set,
  });

  final double value;

  /// When the workout started.
  final DateTime date;
  final String workoutId;

  /// The set that made it; null in stats stored before sets were kept.
  final SetValues? set;

  @override
  List<Object?> get props => [value, date, workoutId, set];
}

/// The exercise's working sets in its latest workout, shown as "last
/// time".
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
    this.bestSet,
    this.workoutName,
  });

  final DateTime date;
  final String workoutId;
  final double? bestE1rmKg;
  final double volumeKg;

  /// The workout's best working set (see [bestSetOf]) and its name; null
  /// in stats stored before they were kept.
  final SetValues? bestSet;
  final String? workoutName;

  @override
  List<Object?> get props => [
    date,
    workoutId,
    bestE1rmKg,
    volumeKg,
    bestSet,
    workoutName,
  ];
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

  /// Stored before records kept their set and history points their best
  /// set and workout name; [rebuildStats] brings it up to date.
  bool get outdated =>
      records.values.any((record) => record.set == null) ||
      history.any(
        (point) => point.bestSet == null || point.workoutName == null,
      );

  @override
  List<Object?> get props => [records, last, history];
}

/// An exercise that beat its records in a workout: its heaviest working
/// [set] (the most reps among equals), the record [kinds] it beat, and the
/// [gain] of the first of them in [gainOrder].
class SummaryRecord extends Equatable {
  const SummaryRecord({
    required this.exerciseId,
    required this.name,
    required this.loggingType,
    required this.set,
    required this.kinds,
    required this.gain,
  });

  final String exerciseId;
  final String name;
  final LoggingType loggingType;
  final WorkoutSet set;
  final List<RecordKind> kinds;
  final ({RecordKind kind, double amount}) gain;

  /// Which beaten record's gain is shown: the heaviest weight first, then
  /// reps and time for exercises without one.
  static const gainOrder = [
    RecordKind.heaviestWeight,
    RecordKind.mostReps,
    RecordKind.longestDuration,
    RecordKind.bestE1rm,
    RecordKind.bestSetVolume,
  ];

  @override
  List<Object?> get props => [exerciseId, name, loggingType, set, kinds, gain];
}

/// With no record beaten, the exercise whose heaviest set came closest to
/// its heaviest weight, [kg] short of it.
typedef ClosestRecord = ({String name, double kg});

/// What a workout of the same program day amounted to, to compare with.
typedef WorkoutTotals = ({
  DateTime startedAt,
  Duration duration,
  double volumeKg,
  int setCount,
});

/// What a finished workout amounted to.
class WorkoutSummary extends Equatable {
  const WorkoutSummary({
    required this.duration,
    required this.volumeKg,
    required this.setCount,
    required this.exerciseCount,
    this.records = const [],
    this.closest,
    this.firstWorkout = false,
    this.programUnknown = false,
    this.programWeek,
    this.previous,
    this.muscleSets = const {},
  });

  final Duration duration;
  final double volumeKg;

  /// Done working sets; warm-ups do not count.
  final int setCount;
  final int exerciseCount;
  final List<SummaryRecord> records;

  /// With no record: how close the best came; null when nothing compares.
  final ClosestRecord? closest;

  /// None of its exercises had been done before: records start now.
  final bool firstWorkout;

  /// The workout came from a program whose state was not known when it
  /// finished, so the program was not moved on.
  final bool programUnknown;

  /// The active program's week it was done in.
  final int? programWeek;

  /// The program day's previous workout; null for a free workout or the
  /// day's first.
  final WorkoutTotals? previous;

  /// Working sets per muscle, as weekly volume counts them.
  final Map<Muscle, double> muscleSets;

  WorkoutSummary copyWith({
    int? Function()? programWeek,
    WorkoutTotals? Function()? previous,
  }) => WorkoutSummary(
    duration: duration,
    volumeKg: volumeKg,
    setCount: setCount,
    exerciseCount: exerciseCount,
    records: records,
    closest: closest,
    firstWorkout: firstWorkout,
    programUnknown: programUnknown,
    programWeek: programWeek != null ? programWeek() : this.programWeek,
    previous: previous != null ? previous() : this.previous,
    muscleSets: muscleSets,
  );

  @override
  List<Object?> get props => [
    duration,
    volumeKg,
    setCount,
    exerciseCount,
    records,
    closest,
    firstWorkout,
    programUnknown,
    programWeek,
    previous,
    muscleSets,
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

/// The values of [set] that a record or a best set keeps.
SetValues setValues(WorkoutSet set) =>
    (weightKg: set.weightKg, reps: set.reps, durationS: set.durationS);

/// Orders sets of [type] from worst to best (see [bestSetOf]).
int _compareSets(WorkoutSet a, WorkoutSet b, LoggingType type) {
  int by(num? x, num? y) => (x ?? 0).compareTo(y ?? 0);
  int chain(List<int> orders) =>
      orders.firstWhere((order) => order != 0, orElse: () => 0);
  return switch (type) {
    LoggingType.weightReps || LoggingType.weightedBodyweight => chain([
      by(setE1rm(a, type), setE1rm(b, type)),
      by(a.weightKg, b.weightKg),
      by(a.reps, b.reps),
    ]),
    // Less assistance is better (an empty one is none).
    LoggingType.assistedBodyweight => chain([
      by(b.weightKg, a.weightKg),
      by(a.reps, b.reps),
    ]),
    LoggingType.reps => by(a.reps, b.reps),
    LoggingType.duration => by(a.durationS, b.durationS),
    LoggingType.weightDuration => chain([
      by(a.weightKg, b.weightKg),
      by(a.durationS, b.durationS),
    ]),
  };
}

/// The best of [sets]' done working sets for [type]: the highest e1RM
/// (then the heavier, then more reps) for a load, the least assistance
/// (then more reps), the most reps, the longest time, or the heaviest
/// timed set (then the longer). Null without a done working set.
WorkoutSet? bestSetOf(Iterable<WorkoutSet> sets, LoggingType type) =>
    workingSets(sets).fold<WorkoutSet?>(
      null,
      (best, set) =>
          best == null || _compareSets(set, best, type) > 0 ? set : best,
    );

/// The best value of each record kind of [type] among [sets]' done working
/// sets, with the set that made it: among equal values the heavier (the
/// one with more reps for the heaviest weight). Kinds without a value above
/// zero are left out.
Map<RecordKind, ({double value, WorkoutSet set})> sessionBests(
  Iterable<WorkoutSet> sets,
  LoggingType type,
) {
  final kinds = RecordKind.of(type);
  final best = <RecordKind, ({double value, WorkoutSet set})>{};
  void offer(RecordKind kind, num? value, WorkoutSet set) {
    if (!kinds.contains(kind) || value == null || !(value > 0)) return;
    final current = best[kind];
    final better =
        current == null ||
        value > current.value ||
        value == current.value &&
            ((set.weightKg ?? 0) > (current.set.weightKg ?? 0) ||
                kind == RecordKind.heaviestWeight &&
                    (set.reps ?? 0) > (current.set.reps ?? 0));
    if (better) best[kind] = (value: value.toDouble(), set: set);
  }

  for (final set in workingSets(sets)) {
    offer(RecordKind.heaviestWeight, set.weightKg, set);
    offer(RecordKind.bestE1rm, setE1rm(set, type), set);
    offer(RecordKind.bestSetVolume, setVolume(set, type), set);
    offer(RecordKind.mostReps, set.reps, set);
    offer(RecordKind.longestDuration, set.durationS, set);
  }
  return best;
}

/// The sets of [workout] holding a record its exercise still keeps:
/// for each record of [stats] (by exercise id) set by [workout], the
/// first done working set with that record's value, as (exercise index,
/// set index).
Set<(int, int)> heldRecordSets(
  Workout workout,
  Map<String, ExerciseStats> stats,
) {
  final held = <(int, int)>{};
  for (final (e, exercise) in workout.exercises.indexed) {
    final records = stats[exercise.exerciseId]?.records ?? const {};
    final type = exercise.loggingType;
    for (final MapEntry(key: kind, value: record) in records.entries) {
      if (record.workoutId != workout.id) continue;
      for (final (s, set) in exercise.sets.indexed) {
        if (!set.done || set.isWarmup) continue;
        final value = switch (kind) {
          RecordKind.heaviestWeight => set.weightKg,
          RecordKind.bestE1rm => setE1rm(set, type),
          RecordKind.bestSetVolume => setVolume(set, type),
          RecordKind.mostReps => set.reps,
          RecordKind.longestDuration => set.durationS,
        };
        if (value != null && (value - record.value).abs() < 1e-6) {
          held.add((e, s));
          break;
        }
      }
    }
  }
  return held;
}

/// Volume of [sets]' done working sets.
double sessionVolume(Iterable<WorkoutSet> sets, LoggingType type) =>
    workingSets(sets).fold(0, (sum, set) => sum + setVolume(set, type));

/// [stats] (null: none yet) with [workout]'s working sets of [exerciseId]
/// added: records it beats, `last` when it is the latest workout, and its
/// history point, replacing one of the same workout. Unchanged when
/// [workout] has no done working set of the exercise (warm-ups only).
/// Applying a workout twice changes nothing the second time.
ExerciseStats? applyWorkout(
  ExerciseStats? stats,
  Workout workout,
  String exerciseId,
) {
  final entries = [
    for (final exercise in workout.exercises)
      if (exercise.exerciseId == exerciseId) exercise,
  ];
  final done = workingSets([for (final entry in entries) ...entry.sets]);
  if (done.isEmpty) return stats;
  final type = entries.first.loggingType;
  final date = workout.startedAt;
  final records = {...?stats?.records};
  for (final MapEntry(key: kind, value: (:value, :set)) in sessionBests(
    done,
    type,
  ).entries) {
    final current = records[kind];
    if (current == null || value > current.value) {
      records[kind] = StatRecord(
        value: value,
        date: date,
        workoutId: workout.id,
        set: setValues(set),
      );
    }
  }
  final last = stats?.last;
  final bests = [for (final set in done) ?setE1rm(set, type)];
  final history = [
    for (final point in stats?.history ?? const <HistoryPoint>[])
      if (point.workoutId != workout.id) point,
    HistoryPoint(
      date: date,
      workoutId: workout.id,
      bestE1rmKg: bests.isEmpty ? null : bests.reduce((a, b) => a > b ? a : b),
      volumeKg: sessionVolume(done, type),
      bestSet: setValues(bestSetOf(done, type)!),
      workoutName: workout.name,
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

/// The totals of finished [workout].
WorkoutTotals workoutTotals(Workout workout) => (
  startedAt: workout.startedAt,
  duration: (workout.finishedAt ?? workout.startedAt).difference(
    workout.startedAt,
  ),
  volumeKg: workout.exercises.fold(
    0,
    (sum, e) => sum + sessionVolume(e.sets, e.loggingType),
  ),
  setCount: workout.exercises.fold(
    0,
    (count, e) => count + workingSets(e.sets).length,
  ),
);

/// The summary of finished [workout] with the records it beat, judged
/// against each exercise's stats [before] it (an id missing: unreadable).
/// See [WorkoutSummary.closest] and [WorkoutSummary.firstWorkout].
WorkoutSummary summarizeWorkout(
  Workout workout, {
  Map<String, ExerciseStats?> before = const {},
  Map<String, ExerciseStats> after = const {},
  bool programUnknown = false,
}) {
  final totals = workoutTotals(workout);
  final records = <SummaryRecord>[];
  ClosestRecord? closest;
  final muscles = <Muscle, double>{};
  for (final exercise in workout.exercises) {
    addMuscleSets(
      muscles,
      muscleSets(
        main: exercise.mainMuscles,
        secondary: exercise.secondaryMuscles,
        sets: workingSets(exercise.sets).length,
      ),
    );
  }
  for (final id in workout.exerciseIds) {
    final entries = [
      for (final e in workout.exercises)
        if (e.exerciseId == id) e,
    ];
    final done = workingSets([for (final e in entries) ...e.sets]);
    if (done.isEmpty) continue;
    final type = entries.first.loggingType;
    final previous = before[id]?.records;
    final kinds = beatenRecords(before[id], after[id], workout);
    final heaviest = done.reduce(
      (a, b) =>
          (b.weightKg ?? 0) > (a.weightKg ?? 0) ||
              (b.weightKg ?? 0) == (a.weightKg ?? 0) &&
                  (b.reps ?? 0) > (a.reps ?? 0)
          ? b
          : a,
    );
    if (kinds.isNotEmpty) {
      final kind = SummaryRecord.gainOrder.firstWhere(kinds.contains);
      records.add(
        SummaryRecord(
          exerciseId: id,
          name: entries.first.name,
          loggingType: type,
          set: heaviest,
          kinds: kinds,
          gain: (
            kind: kind,
            amount: after[id]!.records[kind]!.value - previous![kind]!.value,
          ),
        ),
      );
      continue;
    }
    final best = previous?[RecordKind.heaviestWeight]?.value;
    final kg = heaviest.weightKg;
    if (best != null && kg != null && kg < best) {
      if (closest == null || best - kg < closest.kg) {
        closest = (name: entries.first.name, kg: best - kg);
      }
    }
  }
  return WorkoutSummary(
    duration: totals.duration,
    volumeKg: totals.volumeKg,
    setCount: totals.setCount,
    exerciseCount: workout.exerciseIds.length,
    records: records,
    closest: records.isEmpty ? closest : null,
    firstWorkout:
        before.isNotEmpty &&
        workout.exerciseIds.every(
          (id) => before.containsKey(id) && before[id] == null,
        ),
    programUnknown: programUnknown,
    muscleSets: muscles,
  );
}
