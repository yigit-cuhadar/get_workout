import 'package:forge_core/forge_core.dart';

import '../../../core/grouping.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../programs/domain/calendar_date.dart';
import '../../programs/domain/completed_days.dart';
import '../../programs/domain/program.dart';

enum SetType implements Coded {
  normal('normal'),
  warmup('warmup'),

  /// The set continues with lighter [WorkoutSet.drops]; it counts as one
  /// set.
  drop('drop');

  const SetType(this.code);
  @override
  final String code;
}

/// A set of a workout: its exercise's index and its own.
typedef SetRef = ({int exercise, int set});

/// Limits of what a workout holds. Lengths count UTF-16 code units, as the
/// rules do.
abstract final class WorkoutLimits {
  static const maxNameLength = 100;
  static const maxNoteLength = 1000;
  static const maxExerciseNoteLength = 500;
  static const maxSetNoteLength = 200;
  static const maxExercises = 40;
  static const maxSets = 30;
  static const maxDrops = 5;
  static const maxReps = 1000;
  static const maxWeightKg = 1000.0;
  static const maxDurationS = 86400;

  /// The longest a stored workout can be set to last.
  static const maxWorkoutDuration = Duration(hours: 24);

  /// 5 stands for "5 or more".
  static const maxRir = 5;
}

/// One lighter part of a drop set.
class Drop extends Equatable {
  const Drop({this.weightKg, this.reps});

  final double? weightKg;
  final int? reps;

  Drop copyWith({double? Function()? weightKg, int? Function()? reps}) => Drop(
    weightKg: weightKg != null ? weightKg() : this.weightKg,
    reps: reps != null ? reps() : this.reps,
  );

  @override
  List<Object?> get props => [weightKg, reps];
}

/// One set. Which values it needs depends on its exercise's logging type;
/// see `validateSet`. [weightKg] is the load, the added weight of a weighted
/// bodyweight exercise or the assistance of an assisted one.
class WorkoutSet extends Equatable {
  const WorkoutSet({
    this.type = SetType.normal,
    this.weightKg,
    this.reps,
    this.durationS,
    this.toFailure = false,
    this.rir,
    this.note,
    this.drops = const [],
    this.done = false,
  });

  final SetType type;
  final double? weightKg;
  final int? reps;
  final int? durationS;
  final bool toFailure;

  /// Reps in reserve; RPE is `10 - rir`.
  final int? rir;
  final String? note;

  /// Only for [SetType.drop].
  final List<Drop> drops;
  final bool done;

  bool get isWarmup => type == SetType.warmup;

  WorkoutSet copyWith({
    SetType? type,
    double? Function()? weightKg,
    int? Function()? reps,
    int? Function()? durationS,
    bool? toFailure,
    int? Function()? rir,
    String? Function()? note,
    List<Drop>? drops,
    bool? done,
  }) => WorkoutSet(
    type: type ?? this.type,
    weightKg: weightKg != null ? weightKg() : this.weightKg,
    reps: reps != null ? reps() : this.reps,
    durationS: durationS != null ? durationS() : this.durationS,
    toFailure: toFailure ?? this.toFailure,
    rir: rir != null ? rir() : this.rir,
    note: note != null ? note() : this.note,
    drops: drops ?? this.drops,
    done: done ?? this.done,
  );

  @override
  List<Object?> get props => [
    type,
    weightKg,
    reps,
    durationS,
    toFailure,
    rir,
    note,
    drops,
    done,
  ];
}

/// One exercise of a workout. Its name, logging type and muscles are copied
/// from the catalogue, so history survives edits and deletions there.
class WorkoutExercise extends Equatable implements Groupable<WorkoutExercise> {
  const WorkoutExercise({
    required this.exerciseId,
    required this.name,
    required this.loggingType,
    this.mainMuscles = const [],
    this.secondaryMuscles = const [],
    this.group,
    this.note,
    this.sets = const [],
    this.goal,
  });

  final String exerciseId;
  final String name;
  final LoggingType loggingType;
  final List<Muscle> mainMuscles;
  final List<Muscle> secondaryMuscles;

  /// As in programs: adjacent exercises sharing it form a superset or
  /// circuit.
  @override
  final String? group;
  final String? note;
  final List<WorkoutSet> sets;

  /// The program's target while the workout runs; never stored with the
  /// finished workout.
  final ProgramItem? goal;

  List<WorkoutSet> get doneSets => [
    for (final set in sets)
      if (set.done) set,
  ];

  WorkoutExercise copyWith({
    String? exerciseId,
    String? name,
    LoggingType? loggingType,
    List<Muscle>? mainMuscles,
    List<Muscle>? secondaryMuscles,
    String? Function()? group,
    String? Function()? note,
    List<WorkoutSet>? sets,
    ProgramItem? Function()? goal,
  }) => WorkoutExercise(
    exerciseId: exerciseId ?? this.exerciseId,
    name: name ?? this.name,
    loggingType: loggingType ?? this.loggingType,
    mainMuscles: mainMuscles ?? this.mainMuscles,
    secondaryMuscles: secondaryMuscles ?? this.secondaryMuscles,
    group: group != null ? group() : this.group,
    note: note != null ? note() : this.note,
    sets: sets ?? this.sets,
    goal: goal != null ? goal() : this.goal,
  );

  @override
  WorkoutExercise withGroup(String? group) => copyWith(group: () => group);

  @override
  List<Object?> get props => [
    exerciseId,
    name,
    loggingType,
    mainMuscles,
    secondaryMuscles,
    group,
    note,
    sets,
    goal,
  ];
}

/// A workout, in progress (no [finishedAt]) or finished
/// (`users/{uid}/workouts/{id}`). The id is made when it starts, so writing
/// it twice stores it once.
class Workout extends Equatable {
  const Workout({
    required this.id,
    required this.startedAt,
    this.finishedAt,
    this.programId,
    this.dayIndex,
    required this.name,
    this.note,
    this.exercises = const [],
  });

  final String id;

  /// Device-clock times, so a workout done offline keeps its real times.
  final DateTime startedAt;
  final DateTime? finishedAt;

  /// The program and day it was started from.
  final String? programId;
  final int? dayIndex;
  final String name;
  final String? note;
  final List<WorkoutExercise> exercises;

  bool get isFromProgram => programId != null && dayIndex != null;

  /// No exercise yet, so no set either (a note alone does not count): not
  /// yet a workout in progress. It is not kept on the device, shows nowhere
  /// as running, never blocks starting another and is never stored; leaving
  /// it ends it. A program day starts with its exercises, so it is not
  /// empty; removing the last exercise makes any workout empty again.
  bool get isEmpty => exercises.isEmpty;

  /// The local date it started, the date a program day counts as done on.
  CalendarDate get startDate => CalendarDate.of(startedAt.toLocal());

  /// Each exercise once, in order.
  List<String> get exerciseIds => [
    ...{for (final exercise in exercises) exercise.exerciseId},
  ];

  int get doneSetCount =>
      exercises.fold(0, (count, e) => count + e.doneSets.length);

  bool get hasUndoneSets => exercises.any((e) => e.sets.any((s) => !s.done));

  Workout copyWith({
    DateTime? startedAt,
    DateTime? finishedAt,
    String? name,
    String? Function()? note,
    List<WorkoutExercise>? exercises,
  }) => Workout(
    id: id,
    startedAt: startedAt ?? this.startedAt,
    finishedAt: finishedAt ?? this.finishedAt,
    programId: programId,
    dayIndex: dayIndex,
    name: name ?? this.name,
    note: note != null ? note() : this.note,
    exercises: exercises ?? this.exercises,
  );

  @override
  List<Object?> get props => [
    id,
    startedAt,
    finishedAt,
    programId,
    dayIndex,
    name,
    note,
    exercises,
  ];
}

/// The days of program [programId] that [workouts] did, by date.
List<CompletedDay> completedDaysOf(
  Iterable<Workout> workouts,
  String programId,
) => [
  for (final workout in workouts)
    if (workout.programId == programId && workout.dayIndex != null)
      CompletedDay(date: workout.startDate, dayIndex: workout.dayIndex!),
]..sort((a, b) => a.date.compareTo(b.date));
