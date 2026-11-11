import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/workout/domain/workout.dart';

export '../programs/fixtures.dart' show item, move;

/// A done set of [kg] × [reps].
WorkoutSet lift(
  double kg,
  int reps, {
  SetType type = SetType.normal,
  bool done = true,
  List<Drop> drops = const [],
}) =>
    WorkoutSet(type: type, weightKg: kg, reps: reps, drops: drops, done: done);

WorkoutExercise exercise(
  String id,
  List<WorkoutSet> sets, {
  LoggingType type = LoggingType.weightReps,
  String? group,
}) => WorkoutExercise(
  exerciseId: id,
  name: id,
  loggingType: type,
  mainMuscles: const [Muscle.quads],
  group: group,
  sets: sets,
);

Workout workout(
  String id,
  List<WorkoutExercise> exercises, {
  DateTime? startedAt,
  DateTime? finishedAt,
  String? programId,
  int? dayIndex,
}) {
  final start = startedAt ?? DateTime(2026, 11, 11, 18);
  return Workout(
    id: id,
    startedAt: start,
    finishedAt: finishedAt,
    programId: programId,
    dayIndex: dayIndex,
    name: 'Workout $id',
    exercises: exercises,
  );
}
