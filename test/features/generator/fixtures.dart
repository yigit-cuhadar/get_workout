import 'dart:convert';
import 'dart:io';

import 'package:get_workout/features/exercises/data/exercise_map.dart';
import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/generator/domain/generator_answers.dart';

/// The live exercises of `content/exercises/*.json`: the library the app
/// ships with.
List<Exercise> contentLibrary() => [
  for (final file in Directory(
    'content/exercises',
  ).listSync().whereType<File>())
    if (file.path.endsWith('.json'))
      for (final entry in (jsonDecode(
        file.readAsStringSync(),
      ) as List<Object?>).cast<Map<String, Object?>>())
        if (entry['status'] == ExerciseStatus.live.code)
          exerciseFromMap(entry['id']! as String, entry),
];

GeneratorAnswers answers({
  Goal goal = Goal.buildMuscle,
  Level level = Level.intermediate,
  int days = 4,
  int minutes = 60,
  Set<Equipment>? equipment,
  Set<Muscle> focus = const {},
  Set<String> excluded = const {},
  EasyArea? easyArea,
  TrainingSplit? split,
}) => GeneratorAnswers(
  goal: goal,
  level: level,
  daysPerWeek: days,
  sessionMinutes: minutes,
  equipment: equipment ?? EquipmentProfile.fullGym.equipment,
  focus: focus,
  excluded: excluded,
  easyArea: easyArea,
  split: split,
);

/// A catalogue exercise for [main], with defaults for the rest.
Exercise lift(
  String id,
  List<Muscle> main, {
  Mechanic mechanic = Mechanic.compound,
  Level level = Level.beginner,
  List<Equipment> equipment = const [Equipment.barbell],
  LoggingType type = LoggingType.weightReps,
  MovementPattern pattern = MovementPattern.squat,
  List<Muscle> secondary = const [],
  int popularity = 1,
}) => Exercise(
  id: id,
  loggingType: type,
  mechanic: mechanic,
  laterality: Laterality.bilateral,
  level: level,
  force: Force.push,
  movementPattern: pattern,
  position: Position.standing,
  equipment: equipment,
  mainMuscles: main,
  secondaryMuscles: secondary,
  family: id,
  familyRank: 1,
  defaultRestS: 90,
  popularity: popularity,
  l10n: {'en': ExerciseText(name: id)},
);
