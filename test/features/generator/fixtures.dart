import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/data/exercise_map.dart';
import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/generator/domain/generated_program.dart';
import 'package:get_workout/features/generator/domain/generator_answers.dart';
import 'package:get_workout/features/generator/domain/generator_options.dart';
import 'package:get_workout/features/generator/domain/generator_repository.dart';
import 'package:get_workout/features/programs/domain/program.dart';

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

/// A catalogue exercise for [main], with defaults for the rest.
Exercise lift(
  String id,
  List<Muscle> main, {
  LoggingType type = LoggingType.weightReps,
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
  mainMuscles: main,
  secondaryMuscles: const [],
  family: id,
  familyRank: 1,
  defaultRestS: 90,
  popularity: 1,
  l10n: {'en': ExerciseText(name: id)},
);

GeneratorAnswers answers({
  Goal goal = Goal.buildMuscle,
  Level level = Level.intermediate,
  int days = 3,
  int minutes = 60,
  Set<Equipment>? equipment,
  Set<FocusArea> focus = const {},
  Set<FocusArea> skip = const {},
  Set<SensitiveArea> sensitive = const {},
  EquipmentStyle style = EquipmentStyle.any,
  String? split,
}) => GeneratorAnswers(
  goal: goal,
  level: level,
  daysPerWeek: days,
  sessionMinutes: minutes,
  equipment: equipment ?? EquipmentProfile.fullGym.equipment,
  focus: focus,
  skip: skip,
  sensitive: sensitive,
  equipmentStyle: style,
  splitId: split,
);

GeneratorSplit split(String id, List<SplitFit> fits) => GeneratorSplit(
  id: id,
  l10n: {'en': (name: 'Split $id', info: 'About $id')},
  fits: fits,
);

/// Full body for 2-3 days, upper/lower for 4, push/pull/legs for 3 and 6.
final options = GeneratorOptions(
  splits: [
    split('full_body', [
      for (final days in [2, 3])
        SplitFit(days: days, levels: Level.values.toSet()),
    ]),
    split('upper_lower', [SplitFit(days: 4, levels: Level.values.toSet())]),
    split('ppl', [
      const SplitFit(
        days: 3,
        levels: {Level.intermediate, Level.advanced},
        goals: {Goal.buildMuscle},
      ),
      SplitFit(days: 6, levels: Level.values.toSet()),
    ]),
  ],
  sessionMinutes: const [30, 45, 60, 75, 90],
  maxFocusAreas: 2,
  maxSkipAreas: 3,
  focusAreas: areas,
  skipAreas: areas,
);

/// Every muscle in one area, as the rules' seed has them.
const areas = {
  FocusArea.chest: {Muscle.pec},
  FocusArea.back: {Muscle.lat, Muscle.trap, Muscle.erector},
  FocusArea.shoulders: {Muscle.frontDelt, Muscle.midDelt, Muscle.rearDelt},
  FocusArea.arms: {Muscle.biceps, Muscle.triceps, Muscle.forearm},
  FocusArea.core: {Muscle.abdominal, Muscle.oblique},
  FocusArea.glutes: {Muscle.glute},
  FocusArea.legs: {
    Muscle.quads,
    Muscle.hamstring,
    Muscle.calf,
    Muscle.adductor,
    Muscle.abductor,
  },
};

/// An item of [exerciseId], 3 × 8-12.
ProgramItem item(String exerciseId, {int sets = 3}) => ProgramItem(
  exerciseId: exerciseId,
  sets: sets,
  repMin: 8,
  repMax: 12,
  restS: 90,
);

/// A program as the server makes it, [days] of item ids.
GeneratedProgram generated(
  List<List<String>> days, {
  Set<Muscle> targeted = const {},
  Set<Muscle> uncovered = const {},
}) => GeneratedProgram(
  splitName: 'Full body',
  lengthWeeks: 8,
  days: [
    for (final (i, ids) in days.indexed)
      ProgramDay(
        name: 'Full body ${String.fromCharCode(65 + i)}',
        items: [for (final id in ids) item(id)],
      ),
  ],
  targeted: targeted,
  uncovered: uncovered,
);

/// A [GeneratorRepository] in memory: [generate] answers from [answer]
/// (the first library exercises when not set), recording each request;
/// [watchOptions] gives [options].
class FakeGeneratorRepository implements GeneratorRepository {
  FakeGeneratorRepository({this.library = const []});

  final List<Exercise> library;
  final requests = <GenerationRequest>[];
  Result<GeneratedProgram> Function(GenerationRequest request)? answer;
  Stream<GeneratorOptions> Function() watch = () => Stream.value(options);

  @override
  Future<Result<GeneratedProgram>> generate(GenerationRequest request) async {
    requests.add(request);
    return answer?.call(request) ?? Ok(_fromLibrary(request));
  }

  /// A day of four exercises per day, the next four for the next seed;
  /// kept items stay on their day.
  GeneratedProgram _fromLibrary(GenerationRequest request) {
    final days = request.answers.daysPerWeek;
    return GeneratedProgram(
      splitName: 'Full body',
      lengthWeeks: 8,
      days: [
        for (var d = 0; d < days; d++)
          ProgramDay(
            name: 'Day ${String.fromCharCode(65 + d)}',
            items: [
              ...request.kept.elementAtOrNull(d) ?? const <ProgramItem>[],
              for (var i = 0; i < 4; i++)
                if (library[(request.seed * 4 * days + d * 4 + i) %
                        library.length]
                    case final exercise
                    when !(request.kept.elementAtOrNull(d) ?? const []).any(
                      (kept) => kept.exerciseId == exercise.id,
                    ))
                  ProgramItem(
                    exerciseId: exercise.id,
                    sets: 3,
                    repMin: exercise.loggingType.isDurationBased ? null : 8,
                    repMax: exercise.loggingType.isDurationBased ? null : 12,
                    durationS: exercise.loggingType.isDurationBased ? 30 : null,
                    restS: 90,
                  ),
            ],
          ),
      ],
    );
  }

  @override
  Stream<GeneratorOptions> watchOptions() => watch();
}

/// A stream that never emits, for options still loading.
Stream<GeneratorOptions> pending() =>
    StreamController<GeneratorOptions>().stream;
