import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';

/// An exercise with defaults for everything a test does not care about.
Exercise exercise(
  String id, {
  String? name,
  List<String> aliases = const [],
  int popularity = 50,
  List<Muscle> main = const [Muscle.pec],
  List<Muscle> secondary = const [],
  List<Equipment> equipment = const [Equipment.bodyweight],
  List<List<Equipment>> equipmentAlternatives = const [],
  Level level = Level.beginner,
  MovementPattern pattern = MovementPattern.horizontalPush,
  String family = 'family',
  int familyRank = 1,
  List<String> pinned = const [],
  List<String> excluded = const [],
  Map<String, ExerciseText> translations = const {},
}) => Exercise(
  id: id,
  loggingType: LoggingType.reps,
  mechanic: Mechanic.compound,
  laterality: Laterality.bilateral,
  level: level,
  force: Force.push,
  movementPattern: pattern,
  position: Position.standing,
  equipment: equipment,
  equipmentAlternatives: equipmentAlternatives,
  mainMuscles: main,
  secondaryMuscles: secondary,
  family: family,
  familyRank: familyRank,
  pinnedAlternatives: pinned,
  excludedAlternatives: excluded,
  defaultRestS: 60,
  popularity: popularity,
  l10n: {
    'en': ExerciseText(name: name ?? id, aliases: aliases),
    ...translations,
  },
);

List<String> ids(List<Exercise> exercises) => [for (final e in exercises) e.id];
