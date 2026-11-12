import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/exercise_queries.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/generator/domain/generator_answers.dart';
import 'package:get_workout/features/generator/domain/generator_usecases.dart';
import 'package:get_workout/features/generator/domain/program_generator.dart';
import 'package:get_workout/features/programs/domain/catalogue_rules.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_editing.dart';
import 'package:get_workout/features/programs/domain/program_validation.dart';

import 'fixtures.dart';

void main() {
  final library = contentLibrary();
  final byId = {for (final e in library) e.id: e};
  final loggingTypes = {for (final e in library) e.id: e.loggingType};

  GeneratedProgram generate(GeneratorAnswers answers, {int seed = 0}) =>
      generateProgram(answers, library, seed: seed).valueOrNull!;

  GenerationIssue? issueOf(Result<GeneratedProgram> result) =>
      (result.failureOrNull as GenerationFailure?)?.issue;

  Iterable<Exercise> exercisesOf(GeneratedProgram program) => [
    for (final day in program.days)
      for (final item in day.items) byId[item.exerciseId]!,
  ];

  /// What the catalogue rules ask of a ready-made program, and what the
  /// generator promises on top.
  void expectSound(GeneratedProgram generated, GeneratorAnswers answers) {
    final reason = '$answers';
    final program = generated.toProgram(
      name: 'Generated',
      dayName: (day) => day.kind.name,
    );
    expect(
      validateProgram(program, loggingTypes).isValid,
      isTrue,
      reason: reason,
    );
    expect(generated.days, hasLength(answers.daysPerWeek), reason: reason);
    expect(
      generated.days.map((d) => d.kind),
      splitDays(generated.split, answers.daysPerWeek),
      reason: reason,
    );
    for (final day in generated.days) {
      expect(day.items, isNotEmpty, reason: reason);
      expect(day.items.length, lessThanOrEqualTo(10), reason: reason);
      final ids = day.items.map((i) => i.exerciseId);
      expect(ids.toSet(), hasLength(day.items.length), reason: reason);
      expect(
        estimateDay(ProgramDay(items: day.items)),
        lessThanOrEqualTo(Duration(minutes: answers.sessionMinutes)),
        reason: reason,
      );
      for (final item in day.items) {
        expect(item.sets, inInclusiveRange(2, 5), reason: reason);
        expect(item.group, isNull, reason: reason);
      }
    }
    for (final exercise in exercisesOf(generated)) {
      final why = '${exercise.id} in $answers';
      expect(exercise.isCustom, isFalse, reason: why);
      expect(exercise.isDoableWith(answers.equipment), isTrue, reason: why);
      expect(
        exercise.level!.index,
        lessThanOrEqualTo(answers.level.index + 1),
        reason: why,
      );
      expect(answers.excluded, isNot(contains(exercise.id)), reason: why);
      expect(
        exercise.movementPattern,
        isNot(anyOf(MovementPattern.mobility, MovementPattern.explosive)),
        reason: why,
      );
      for (final muscle in answers.easyArea?.muscles ?? const <Muscle>{}) {
        expect(exercise.mainMuscles, isNot(contains(muscle)), reason: why);
      }
    }
    expect(generated.uncovered, {
      for (final muscle in generated.targets.keys)
        if (!exercisesOf(generated).any((e) => e.mainMuscles.contains(muscle)))
          muscle,
    }, reason: reason);
    generated.weeklySets.forEach((muscle, sets) {
      if (generated.targets.containsKey(muscle)) {
        expect(
          sets,
          lessThanOrEqualTo(maxWeeklySets),
          reason: '${muscle.code} in $reason',
        );
      }
    });
  }

  test('the library ships with exercises', () {
    expect(library.length, greaterThan(300));
  });

  group('every combination of days, split, equipment and level', () {
    for (final profile in EquipmentProfile.values) {
      test('works with the ${profile.code} equipment', () {
        var combination = 0;
        for (
          var days = GeneratorLimits.minDays;
          days <= GeneratorLimits.maxDays;
          days++
        ) {
          for (final split in [null, ...TrainingSplit.values]) {
            for (final level in Level.values) {
              // Goals and session lengths take turns, so each is met with
              // every other answer somewhere.
              combination++;
              final given = answers(
                goal: Goal.values[combination % Goal.values.length],
                level: level,
                days: days,
                minutes:
                    GeneratorLimits.sessionMinutes[combination %
                        GeneratorLimits.sessionMinutes.length],
                equipment: profile.equipment,
                split: split,
              );
              final result = generateProgram(given, library, seed: days);
              if (split == TrainingSplit.pushPullLegs && days < 3) {
                expect(issueOf(result), GenerationIssue.splitNeedsMoreDays);
                continue;
              }
              expectSound(result.valueOrNull!, given);
            }
          }
        }
      });
    }
  });

  test('every goal and session length gives a sound program', () {
    for (final goal in Goal.values) {
      for (final minutes in GeneratorLimits.sessionMinutes) {
        final given = answers(goal: goal, minutes: minutes, days: 3);
        expectSound(generate(given), given);
      }
    }
  });

  group('weekly sets', () {
    for (final (days, minutes, level) in [
      (4, 60, Level.beginner),
      (4, 60, Level.intermediate),
      (4, 75, Level.advanced),
      (5, 60, Level.intermediate),
      (6, 75, Level.advanced),
      (3, 60, Level.beginner),
    ]) {
      test('are in the 10-20 band for every major muscle when $days days of '
          '$minutes minutes allow it (${level.code})', () {
        for (var seed = 0; seed < 5; seed++) {
          final generated = generate(
            answers(days: days, minutes: minutes, level: level),
            seed: seed,
          );
          for (final muscle in majorMuscles) {
            expect(
              generated.weeklySets[muscle],
              inInclusiveRange(10, 20),
              reason: '${muscle.code}, seed $seed',
            );
          }
          // Calves and abs, last in importance, still get theirs.
          for (final muscle in [Muscle.calf, Muscle.abdominal]) {
            expect(
              generated.weeklySets[muscle],
              greaterThanOrEqualTo(generated.targets[muscle]! - 1),
              reason: '${muscle.code}, seed $seed',
            );
          }
          expect(generated.uncovered, isEmpty, reason: 'seed $seed');
        }
      });
    }

    test('are shared fairly when the sessions are short', () {
      for (final minutes in [30, 45]) {
        for (var seed = 0; seed < 5; seed++) {
          final generated = generate(
            answers(days: 3, minutes: minutes),
            seed: seed,
          );
          final shares = [
            for (final MapEntry(key: muscle, value: target)
                in generated.targets.entries)
              (generated.weeklySets[muscle] ?? 0) / target,
          ];
          final reason =
              '$minutes minutes, seed $seed: '
              '${generated.weeklySets}';
          expect(generated.uncovered, isEmpty, reason: reason);
          expect(shares.reduce(math.min), greaterThan(0.25), reason: reason);
          expect(
            shares.reduce(math.max) - shares.reduce(math.min),
            lessThan(0.9),
            reason: reason,
          );
        }
      }
    });

    test('count 1 for a main and 0.5 for a secondary muscle', () {
      final generated = generate(answers());
      final expected = <Muscle, double>{};
      for (final day in generated.days) {
        for (final item in day.items) {
          final exercise = byId[item.exerciseId]!;
          for (final m in exercise.mainMuscles) {
            expected[m] = (expected[m] ?? 0) + item.sets;
          }
          for (final m in exercise.secondaryMuscles) {
            expected[m] = (expected[m] ?? 0) + item.sets * 0.5;
          }
        }
      }
      expect(generated.weeklySets, expected);
    });

    test('grow with a focus muscle', () {
      final plain = generate(answers());
      final focused = generate(answers(focus: {Muscle.biceps}));
      expect(focused.targets[Muscle.biceps], 18);
      expect(
        focused.weeklySets[Muscle.biceps],
        greaterThan(plain.weeklySets[Muscle.biceps]!),
      );
      expect(focused.weeklySets[Muscle.biceps], greaterThanOrEqualTo(16));
    });

    test('a focus muscle comes first on its days', () {
      final generated = generate(answers(focus: {Muscle.calf}));
      for (final day in generated.days.where((d) => d.kind == DayKind.lower)) {
        expect(
          byId[day.items.first.exerciseId]!.mainMuscles,
          contains(Muscle.calf),
        );
      }
    });

    test('a shorter session gives fewer sets', () {
      int total(int minutes) =>
          generate(answers(minutes: minutes)).days
              .expand((d) => d.items)
              .fold(0, (sum, item) => sum + item.sets);
      expect(total(30), lessThan(total(60)));
      expect(total(60), lessThan(total(90)));
    });
  });

  group('weeklyTargets', () {
    test('trains the major muscles by level, calves and abs half', () {
      for (final level in Level.values) {
        final targets = weeklyTargets(answers(level: level));
        final base = baseWeeklySets[level]!;
        expect(targets.keys.toSet(), {
          ...majorMuscles,
          Muscle.calf,
          Muscle.abdominal,
        });
        for (final muscle in majorMuscles) {
          expect(targets[muscle], base);
        }
        expect(targets[Muscle.calf], base ~/ 2);
        expect(base, inInclusiveRange(10, 20));
        expect(
          base,
          inInclusiveRange(
            weeklySetBands[level]!.min,
            weeklySetBands[level]!.max,
          ),
        );
      }
    });

    test('adds focus muscles, capped at 20', () {
      final targets = weeklyTargets(
        answers(level: Level.advanced, focus: {Muscle.pec, Muscle.trap}),
      );
      expect(targets[Muscle.pec], maxWeeklySets);
      expect(targets[Muscle.trap], maxWeeklySets);
    });

    test('leaves out the area to go easy on, focus or not', () {
      final targets = weeklyTargets(
        answers(easyArea: EasyArea.shoulders, focus: {Muscle.midDelt}),
      );
      expect(targets.keys, isNot(contains(Muscle.midDelt)));
      expect(targets.keys, isNot(contains(Muscle.frontDelt)));
    });
  });

  group('split', () {
    test('suits the days when none is chosen', () {
      TrainingSplit auto(int days, [Level level = Level.intermediate]) =>
          splitFor(answers(days: days, level: level));
      expect(auto(2), TrainingSplit.fullBody);
      expect(auto(3), TrainingSplit.fullBody);
      expect(auto(4), TrainingSplit.upperLower);
      expect(auto(5), TrainingSplit.pushPullLegs);
      expect(auto(6), TrainingSplit.pushPullLegs);
      expect(auto(5, Level.beginner), TrainingSplit.upperLower);
      expect(auto(6, Level.beginner), TrainingSplit.upperLower);
    });

    test('keeps the chosen one', () {
      expect(
        splitFor(answers(days: 6, split: TrainingSplit.fullBody)),
        TrainingSplit.fullBody,
      );
    });

    test('lays out the days of each split', () {
      expect(splitDays(TrainingSplit.upperLower, 3), [
        DayKind.upper,
        DayKind.lower,
        DayKind.upper,
      ]);
      expect(splitDays(TrainingSplit.pushPullLegs, 5), [
        DayKind.push,
        DayKind.pull,
        DayKind.legs,
        DayKind.upper,
        DayKind.lower,
      ]);
      for (var days = 3; days <= GeneratorLimits.maxDays; days++) {
        for (final split in TrainingSplit.values) {
          expect(splitDays(split, days), hasLength(days));
        }
      }
    });

    test('names repeated days by variant', () {
      final generated = generate(
        answers(days: 3, split: TrainingSplit.upperLower),
      );
      expect(generated.days.map((d) => (d.kind, d.variant)), [
        (DayKind.upper, 0),
        (DayKind.lower, null),
        (DayKind.upper, 1),
      ]);
    });

    test('every muscle has a priority', () {
      expect(musclePriority.toSet(), Muscle.values.toSet());
      expect(musclePriority, hasLength(Muscle.values.length));
    });
  });

  group('seed', () {
    test('the same answers and seed give the same program', () {
      expect(generate(answers(), seed: 7), generate(answers(), seed: 7));
    });

    test('other seeds give other programs', () {
      final programs = {
        for (var seed = 0; seed < 10; seed++) generate(answers(), seed: seed),
      };
      expect(programs.length, greaterThan(1));
    });
  });

  group('exclusions and limits', () {
    test('never uses an excluded exercise', () {
      final first = exercisesOf(generate(answers())).map((e) => e.id).toSet();
      final given = answers(excluded: first);
      final generated = generate(given);
      expectSound(generated, given);
      expect(
        exercisesOf(generated).map((e) => e.id),
        isNot(anyElement(isIn(first))),
      );
    });

    test('reports a muscle no usable exercise works', () {
      final pec = {
        for (final e in library)
          if (e.mainMuscles.contains(Muscle.pec)) e.id,
      };
      final generated = generate(answers(excluded: pec));
      expect(generated.uncovered, {Muscle.pec});
      expect(generated.weeklySets[Muscle.pec] ?? 0, lessThan(10));
    });

    test('goes easy on an area: no direct work for it', () {
      for (final area in EasyArea.values) {
        final given = answers(easyArea: area);
        final generated = generate(given);
        expectSound(generated, given);
        for (final muscle in area.muscles) {
          expect(generated.targets.keys, isNot(contains(muscle)));
        }
      }
    });

    test('prefers exercises that spare the area to go easy on', () {
      final generated = generate(answers(easyArea: EasyArea.lowerBack));
      expect(
        exercisesOf(generated)
            .where((e) => e.secondaryMuscles.contains(Muscle.erector)),
        isEmpty,
      );
    });

    test('a beginner gets no advanced exercise', () {
      final given = answers(level: Level.beginner);
      expect(
        exercisesOf(generate(given)).map((e) => e.level),
        isNot(contains(Level.advanced)),
      );
    });

    test('never uses custom exercises', () {
      final mine = Exercise.custom(
        id: '${Exercise.customIdPrefix}1',
        name: 'My squat',
        loggingType: LoggingType.weightReps,
        mainMuscles: const [Muscle.quads],
      );
      final generated = generateProgram(answers(), [
        mine,
        ...library,
      ]).valueOrNull!;
      expect(exercisesOf(generated), isNot(contains(mine)));
    });

    test('sets reps by goal and a duration for timed exercises', () {
      final library = [
        lift('squat', [Muscle.quads]),
        lift(
          'curl',
          [Muscle.biceps],
          mechanic: Mechanic.isolation,
          pattern: MovementPattern.isolation,
        ),
        lift('plank', [Muscle.abdominal], type: LoggingType.duration),
        lift('pushup', [Muscle.pec], type: LoggingType.reps),
      ];
      ProgramItem itemOf(Goal goal, String id) => generateProgram(
        answers(goal: goal, days: 2, split: TrainingSplit.fullBody),
        library,
      ).valueOrNull!.days.first.items.firstWhere((i) => i.exerciseId == id);
      final squat = itemOf(Goal.getStronger, 'squat');
      expect((squat.repMin, squat.repMax), (4, 6));
      final curl = itemOf(Goal.buildMuscle, 'curl');
      expect((curl.repMin, curl.repMax), (10, 15));
      // Nothing to load, so no strength range.
      final pushup = itemOf(Goal.getStronger, 'pushup');
      expect((pushup.repMin, pushup.repMax), (6, 10));
      final plank = itemOf(Goal.buildMuscle, 'plank');
      expect((plank.repMin, plank.durationS), (null, 40));
      expect(itemOf(Goal.loseFat, 'squat').restS, 60);
    });
  });

  group('impossible answers', () {
    test('days outside 2-6', () {
      for (final days in [0, 1, 7]) {
        expect(
          issueOf(generateProgram(answers(days: days), library)),
          GenerationIssue.daysOutOfRange,
        );
      }
    });

    test('push/pull/legs on two days', () {
      expect(
        issueOf(
          generateProgram(
            answers(days: 2, split: TrainingSplit.pushPullLegs),
            library,
          ),
        ),
        GenerationIssue.splitNeedsMoreDays,
      );
    });

    test('no exercise left for a day', () {
      expect(
        issueOf(generateProgram(answers(), const [])),
        GenerationIssue.noExercises,
      );
      expect(
        issueOf(
          generateProgram(
            answers(excluded: {for (final e in library) e.id}),
            library,
          ),
        ),
        GenerationIssue.noExercises,
      );
      // Only barbell work, and only bands at hand.
      expect(
        issueOf(
          generateProgram(
            answers(equipment: EquipmentProfile.bands.equipment),
            [
              lift('squat', [Muscle.quads]),
              lift('bench', [Muscle.pec]),
            ],
          ),
        ),
        GenerationIssue.noExercises,
      );
    });

    test('a day whose muscles have no exercise, others do', () {
      // Upper days have exercises, lower days none.
      final result = generateProgram(answers(split: TrainingSplit.upperLower), [
        lift('bench', [Muscle.pec]),
        lift('row', [Muscle.lat]),
      ]);
      expect(issueOf(result), GenerationIssue.noExercises);
    });
  });

  test('the stored program is a generated, editable one', () {
    final generated = generate(
      answers(days: 2, split: TrainingSplit.upperLower),
    );
    final program = generated.toProgram(
      name: 'Mine',
      dayName: (day) => '${day.kind.name} ${day.variant}',
    );
    expect(program.origin, ProgramOrigin.generated);
    expect(program.premium, isFalse);
    expect(program.id, isNull);
    expect(program.lengthWeeks, isNull);
    expect(program.days.map((d) => d.name), ['upper null', 'lower null']);
    expect(program.days.first.items, generated.days.first.items);
  });

  test('GenerateProgram runs the generator', () async {
    final given = answers();
    final result = await const GenerateProgram()((
      answers: given,
      exercises: library,
      seed: 3,
    ));
    expect(result.valueOrNull, generate(given, seed: 3));
    final failed = await const GenerateProgram()((
      answers: answers(days: 1),
      exercises: library,
      seed: 0,
    ));
    expect(issueOf(failed), GenerationIssue.daysOutOfRange);
  });
}
