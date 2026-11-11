import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/domain/catalogue_program.dart';
import 'package:get_workout/features/programs/domain/program.dart';

/// An exercise with defaults for everything a program test does not care
/// about.
Exercise move(
  String id, {
  LoggingType type = LoggingType.weightReps,
  int rest = 90,
  String? name,
}) => Exercise(
  id: id,
  loggingType: type,
  mechanic: Mechanic.compound,
  laterality: Laterality.bilateral,
  level: Level.beginner,
  force: Force.push,
  movementPattern: MovementPattern.squat,
  position: Position.standing,
  equipment: const [Equipment.barbell],
  mainMuscles: const [Muscle.quads],
  family: id,
  familyRank: 1,
  defaultRestS: rest,
  popularity: 1,
  l10n: {'en': ExerciseText(name: name ?? id)},
);

ProgramItem item(
  String exerciseId, {
  int sets = 3,
  int? repMin = 8,
  int? repMax = 12,
  int? durationS,
  int restS = 90,
  double? targetKg,
  String? group,
}) => ProgramItem(
  exerciseId: exerciseId,
  sets: sets,
  repMin: repMin,
  repMax: repMax,
  durationS: durationS,
  restS: restS,
  targetKg: targetKg,
  group: group,
);

/// A valid two-day program of weighted rep exercises `a` to `d`.
Program program({String? id, String name = 'Upper Lower', int? lengthWeeks}) =>
    Program(
      id: id,
      name: name,
      lengthWeeks: lengthWeeks,
      days: [
        ProgramDay(name: 'Upper', items: [item('a'), item('b')]),
        ProgramDay(name: 'Lower', items: [item('c'), item('d')]),
      ],
    );

const loggingTypes = {
  'a': LoggingType.weightReps,
  'b': LoggingType.weightReps,
  'c': LoggingType.weightReps,
  'd': LoggingType.weightReps,
  'plank': LoggingType.duration,
  'pushup': LoggingType.reps,
};

/// A ready-made program's card; free, beginner, three days of dumbbell work
/// unless told otherwise.
CatalogueProgram card(
  String id, {
  bool premium = false,
  Level level = Level.beginner,
  Goal goal = Goal.buildMuscle,
  int daysPerWeek = 3,
  int? lengthWeeks,
  List<Equipment> equipment = const [Equipment.dumbbell, Equipment.bench],
  EquipmentProfile profile = EquipmentProfile.dumbbells,
  int order = 1,
}) => CatalogueProgram(
  id: id,
  premium: premium,
  level: level,
  goal: goal,
  daysPerWeek: daysPerWeek,
  lengthWeeks: lengthWeeks,
  equipment: equipment,
  equipmentProfile: profile,
  order: order,
  l10n: {'en': CatalogueText(name: 'Program $id', summary: 'For $id.')},
);
