import '../../exercises/domain/vocabulary.dart';
import '../../programs/domain/program.dart';
import '../domain/workout.dart';

/// Maps of a workout's exercises and sets, the same in Firestore and in the
/// file of the workout in progress: they hold only strings, numbers, bools,
/// lists and maps. Reading is lenient: values of the wrong type read as
/// missing, and exercises or sets that cannot be read are left out, so one
/// bad entry never loses a workout.
abstract final class WorkoutMaps {
  /// Far above any real value, far below where rounding fails.
  static const _maxWhole = 1e9;

  /// [withGoal] keeps the program goal, which only the workout in progress
  /// has.
  static Map<String, Object?> exerciseToMap(
    WorkoutExercise exercise, {
    bool withGoal = false,
  }) => {
    'exerciseId': exercise.exerciseId,
    'name': exercise.name,
    'loggingType': exercise.loggingType.code,
    'mainMuscles': [for (final muscle in exercise.mainMuscles) muscle.code],
    'secondaryMuscles': [
      for (final muscle in exercise.secondaryMuscles) muscle.code,
    ],
    'group': ?exercise.group,
    'note': ?exercise.note,
    'sets': [for (final set in exercise.sets) setToMap(set)],
    if (withGoal && exercise.goal != null) 'goal': _goalToMap(exercise.goal!),
  };

  static Map<String, Object?> setToMap(WorkoutSet set) => {
    'type': set.type.code,
    'weightKg': ?set.weightKg,
    'reps': ?set.reps,
    'durationS': ?set.durationS,
    'toFailure': set.toFailure,
    'rir': ?set.rir,
    'note': ?set.note,
    if (set.drops.isNotEmpty)
      'drops': [
        for (final drop in set.drops)
          {'weightKg': ?drop.weightKg, 'reps': ?drop.reps},
      ],
    'done': set.done,
  };

  static Map<String, Object?> _goalToMap(ProgramItem goal) => {
    'sets': goal.sets,
    'repMin': ?goal.repMin,
    'repMax': ?goal.repMax,
    'durationS': ?goal.durationS,
    'restS': goal.restS,
    'targetKg': ?goal.targetKg,
  };

  /// Null for anything without an exercise id, a name and a known logging
  /// type.
  static WorkoutExercise? exerciseFromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['exerciseId'];
    final name = raw['name'];
    final type = LoggingType.values.byCode(raw['loggingType']);
    if (id is! String || id.isEmpty || name is! String || type == null) {
      return null;
    }
    final group = raw['group'];
    return WorkoutExercise(
      exerciseId: id,
      name: name,
      loggingType: type,
      mainMuscles: _muscles(raw['mainMuscles']),
      secondaryMuscles: _muscles(raw['secondaryMuscles']),
      group: group is String && group.isNotEmpty ? group : null,
      note: _text(raw['note']),
      sets: setsFromList(raw['sets']),
      goal: _goalFromMap(id, raw['goal']),
    );
  }

  static List<WorkoutSet> setsFromList(Object? raw) => [
    if (raw is List)
      for (final set in raw) ?setFromMap(set),
  ];

  /// Null for anything but a map; an unknown type reads as normal.
  static WorkoutSet? setFromMap(Object? raw) {
    if (raw is! Map) return null;
    final drops = raw['drops'];
    return WorkoutSet(
      type: SetType.values.byCode(raw['type']) ?? SetType.normal,
      weightKg: decimal(raw['weightKg']),
      reps: whole(raw['reps']),
      durationS: whole(raw['durationS']),
      toFailure: raw['toFailure'] == true,
      rir: whole(raw['rir']),
      note: _text(raw['note']),
      drops: [
        if (drops is List)
          for (final drop in drops)
            if (drop is Map)
              Drop(
                weightKg: decimal(drop['weightKg']),
                reps: whole(drop['reps']),
              ),
      ],
      done: raw['done'] == true,
    );
  }

  static ProgramItem? _goalFromMap(String exerciseId, Object? raw) {
    if (raw is! Map) return null;
    return ProgramItem(
      exerciseId: exerciseId,
      sets: whole(raw['sets']) ?? 1,
      repMin: whole(raw['repMin']),
      repMax: whole(raw['repMax']),
      durationS: whole(raw['durationS']),
      restS: whole(raw['restS']) ?? 0,
      targetKg: decimal(raw['targetKg']),
    );
  }

  static List<Muscle> _muscles(Object? raw) => [
    if (raw is List)
      for (final code in raw) ?Muscle.values.byCode(code),
  ];

  static String? _text(Object? raw) => raw is String ? raw : null;

  static int? whole(Object? value) =>
      value is num && value.abs() <= _maxWhole ? value.round() : null;

  static double? decimal(Object? value) =>
      value is num && value.isFinite ? value.toDouble() : null;
}
