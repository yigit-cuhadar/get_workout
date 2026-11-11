import 'package:forge_core/forge_core.dart';

import 'exercise.dart';
import 'vocabulary.dart';

/// What the user writes about an exercise of their own; becomes an
/// [Exercise] once stored ([toExercise]).
class CustomExercise extends Equatable {
  const CustomExercise({
    this.id,
    required this.name,
    this.loggingType = LoggingType.weightReps,
    this.mainMuscles = const [],
    this.secondaryMuscles = const [],
    this.equipment = const [],
    this.note,
  });

  /// The stored custom exercise [exercise] (see [Exercise.isCustom]).
  CustomExercise.of(Exercise exercise)
    : id = exercise.id,
      name = exercise.text(Exercise.fallbackLanguage).name,
      loggingType = exercise.loggingType,
      mainMuscles = exercise.mainMuscles,
      secondaryMuscles = exercise.secondaryMuscles,
      equipment = exercise.equipment,
      note = exercise.note;

  /// Null until stored; then starts with [Exercise.customIdPrefix].
  final String? id;
  final String name;
  final LoggingType loggingType;
  final List<Muscle> mainMuscles;
  final List<Muscle> secondaryMuscles;

  /// Empty when not given.
  final List<Equipment> equipment;
  final String? note;

  /// Needs an [id].
  Exercise toExercise() => Exercise.custom(
    id: id!,
    name: name,
    loggingType: loggingType,
    mainMuscles: mainMuscles,
    secondaryMuscles: secondaryMuscles,
    equipment: equipment,
    note: note,
  );

  @override
  List<Object?> get props => [
    id,
    name,
    loggingType,
    mainMuscles,
    secondaryMuscles,
    equipment,
    note,
  ];
}

/// A reason a custom exercise cannot be saved; each belongs to one field.
enum CustomExerciseIssue {
  nameMissing,
  nameTooLong,
  mainMusclesMissing,

  /// A muscle is listed twice, or as both main and secondary.
  musclesRepeated,

  /// Equipment is listed twice, or bodyweight with anything else.
  equipmentInvalid,
  noteTooLong,
}

/// Mirrored in `firestore.rules`.
abstract final class CustomExerciseLimits {
  static const maxNameLength = 60;
  static const maxNoteLength = 500;

  /// Per user.
  static const maxCount = 500;

  /// What saving a new one returns once a user has [maxCount].
  static const limitReached = ValidationFailure('custom exercise limit');
}

/// Everything wrong with [exercise]; empty when it can be saved. The name
/// counts without surrounding whitespace; the note may be null, never blank.
Set<CustomExerciseIssue> validateCustomExercise(CustomExercise exercise) {
  final name = exercise.name.trim();
  final muscles = [...exercise.mainMuscles, ...exercise.secondaryMuscles];
  final equipment = exercise.equipment;
  return {
    if (name.isEmpty) CustomExerciseIssue.nameMissing,
    if (name.length > CustomExerciseLimits.maxNameLength)
      CustomExerciseIssue.nameTooLong,
    if (exercise.mainMuscles.isEmpty) CustomExerciseIssue.mainMusclesMissing,
    if (muscles.toSet().length != muscles.length)
      CustomExerciseIssue.musclesRepeated,
    if (equipment.toSet().length != equipment.length ||
        (equipment.contains(Equipment.bodyweight) && equipment.length > 1))
      CustomExerciseIssue.equipmentInvalid,
    if ((exercise.note?.length ?? 0) > CustomExerciseLimits.maxNoteLength)
      CustomExerciseIssue.noteTooLong,
  };
}
