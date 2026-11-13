import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/workout/domain/set_logging.dart';
import 'package:get_workout/features/workout/domain/warmups.dart';
import 'package:get_workout/features/workout/domain/workout.dart';

import 'fixtures.dart';

void main() {
  const warmup = WorkoutSet(type: SetType.warmup);
  const standard = WarmupSettings();
  const kg = WeightUnit.kg;
  final two = WarmupScheme.standard.presetSteps;

  WorkoutExercise lift3(String id, {Muscle? muscle, String? group}) => exercise(
    id,
    const [WorkoutSet()],
    group: group,
  ).copyWith(mainMuscles: muscle == null ? const [] : [muscle]);

  int warmups(WorkoutExercise e) => e.sets.where((s) => s.isWarmup).length;

  group('warmedUp', () {
    test("puts the scheme's empty warm-ups before the sets", () {
      final squat = exercise('squat', const [WorkoutSet(), WorkoutSet()]);
      expect(warmedUp(squat, const [], standard).sets, const [
        warmup,
        warmup,
        WorkoutSet(),
        WorkoutSet(),
      ]);
      for (final (scheme, count) in [
        (WarmupScheme.off, 0),
        (WarmupScheme.light, 1),
        (WarmupScheme.full, 3),
      ]) {
        expect(
          warmups(warmedUp(squat, const [], WarmupSettings(scheme: scheme))),
          count,
          reason: '$scheme',
        );
      }
      const custom = WarmupSettings(
        scheme: WarmupScheme.custom,
        custom: [
          WarmupStep(30, 10),
          WarmupStep(45, 8),
          WarmupStep(60, 6),
          WarmupStep(70, 4),
          WarmupStep(85, 1),
        ],
      );
      expect(warmups(warmedUp(squat, const [], custom)), 5);
    });

    test('only for weight and reps', () {
      for (final type in LoggingType.values) {
        final added = warmedUp(
          exercise('x', const [WorkoutSet()], type: type),
          const [],
          standard,
        );
        expect(
          added.sets.length,
          type == LoggingType.weightReps ? 3 : 1,
          reason: '$type',
        );
      }
    });

    test('none when it has a warm-up or no room for them', () {
      final warmed = exercise('squat', [lift(40, 10, type: SetType.warmup)]);
      expect(warmedUp(warmed, const [], standard), warmed);
      final full = exercise(
        'squat',
        List.filled(WorkoutLimits.maxSets - 1, const WorkoutSet()),
      );
      expect(warmedUp(full, const [], standard), full);
    });

    group('first exercise for each muscle group', () {
      const first = WarmupSettings(scope: WarmupScope.firstPerMuscle);

      test('in order: a later one for a muscle done before gets none', () {
        final day = warmedUpAll(
          [
            lift3('squat', muscle: Muscle.quads),
            lift3('bench', muscle: Muscle.pec),
            lift3('leg press', muscle: Muscle.quads),
            lift3('fly', muscle: Muscle.pec),
          ],
          const [],
          first,
        );
        expect(day.map(warmups), [2, 2, 0, 0]);
      });

      test('added later, against the exercises before it', () {
        final before = [lift3('squat', muscle: Muscle.quads)];
        expect(
          warmups(
            warmedUp(lift3('lunge', muscle: Muscle.quads), before, first),
          ),
          0,
        );
        expect(
          warmups(warmedUp(lift3('row', muscle: Muscle.lat), before, first)),
          2,
        );
        // Every exercise: the muscle does not matter.
        expect(
          warmups(
            warmedUp(lift3('lunge', muscle: Muscle.quads), before, standard),
          ),
          2,
        );
      });

      test('one without a main muscle is a group of its own', () {
        final day = warmedUpAll(
          [lift3('a'), lift3('b'), lift3('squat', muscle: Muscle.quads)],
          const [],
          first,
        );
        expect(day.map(warmups), [2, 2, 2]);
      });

      test('superset members count one after the other', () {
        final day = warmedUpAll(
          [
            lift3('bench', muscle: Muscle.pec, group: 'A'),
            lift3('row', muscle: Muscle.lat, group: 'A'),
            lift3('fly', muscle: Muscle.pec, group: 'B'),
            lift3('pullover', muscle: Muscle.lat, group: 'B'),
          ],
          const [],
          first,
        );
        expect(day.map(warmups), [2, 2, 0, 0]);
      });
    });
  });

  group('withoutUnusedWarmups', () {
    final squat = exercise('squat', [
      warmup,
      lift(40, 8, type: SetType.warmup),
      const WorkoutSet(),
    ]);

    test('drops untouched warm-ups for an exercise that takes none', () {
      final plank = squat.copyWith(
        loggingType: LoggingType.duration,
        sets: const [warmup, warmup, WorkoutSet()],
      );
      expect(withoutUnusedWarmups(squat, plank).sets, const [
        warmup,
        WorkoutSet(),
      ]);
    });

    test('keeps them for one that takes warm-ups', () {
      expect(withoutUnusedWarmups(squat, squat), squat);
    });
  });

  group('rampedWarmup', () {
    test('by position through the sets, the last repeating', () {
      expect(rampedWarmup(0, 100, kg, two), (weightKg: 50, reps: 8));
      expect(rampedWarmup(1, 100, kg, two), (weightKg: 75, reps: 4));
      expect(rampedWarmup(2, 100, kg, two), (weightKg: 75, reps: 4));
      final light = WarmupScheme.light.presetSteps;
      expect(rampedWarmup(0, 100, kg, light), (weightKg: 60, reps: 6));
      final full = WarmupScheme.full.presetSteps;
      expect(
        [for (var i = 0; i < 3; i++) rampedWarmup(i, 100, kg, full)!.weightKg],
        [40, 60, 80],
      );
      const five = [
        WarmupStep(30, 10),
        WarmupStep(45, 8),
        WarmupStep(60, 6),
        WarmupStep(70, 4),
        WarmupStep(95, 1),
      ];
      expect(
        [for (var i = 0; i < 5; i++) rampedWarmup(i, 101, kg, five)!.weightKg],
        [30, 45, 60, 70, 95],
      );
    });

    test('rounds to 2.5 kg', () {
      expect(rampedWarmup(0, 63, kg, two)!.weightKg, 32.5);
      expect(rampedWarmup(1, 63, kg, two)!.weightKg, 47.5);
    });

    test('rounds to 5 lb', () {
      final working = WeightUnit.lb.toKg(185);
      final first = rampedWarmup(0, working, WeightUnit.lb, two)!;
      final second = rampedWarmup(1, working, WeightUnit.lb, two)!;
      expect(WeightUnit.lb.fromKg(first.weightKg), closeTo(95, 1e-9));
      expect(WeightUnit.lb.fromKg(second.weightKg), closeTo(140, 1e-9));
    });

    test('never below one step nor above the working weight', () {
      expect(rampedWarmup(0, 4, kg, two)!.weightKg, 2.5);
      expect(rampedWarmup(1, 2, kg, two)!.weightKg, 2);
      // 95 % of 41 kg rounds up to 40, still below; of 39 to 37.5.
      const high = [WarmupStep(95, 1)];
      expect(rampedWarmup(0, 41, kg, high)!.weightKg, 40);
      expect(rampedWarmup(0, 39, kg, high)!.weightKg, 37.5);
      expect(rampedWarmup(0, 2.4, kg, high)!.weightKg, 2.4);
      expect(
        WeightUnit.lb.fromKg(rampedWarmup(0, 4, WeightUnit.lb, two)!.weightKg),
        closeTo(5, 1e-9),
      );
    });

    test('nothing without a working weight or sets', () {
      expect(rampedWarmup(0, null, kg, two), isNull);
      expect(rampedWarmup(0, 0, kg, two), isNull);
      expect(rampedWarmup(0, 100, kg, const []), isNull);
    });
  });

  group('warm-up suggestions', () {
    final ramp = (unit: kg, steps: two);

    test('follow the first working set, typed or suggested', () {
      final squat = exercise('squat', const [
        warmup,
        warmup,
        WorkoutSet(weightKg: 100),
      ]);
      expect(suggestedValues(squat, 0, const [], ramp: ramp), (
        weightKg: 50.0,
        reps: 8,
        durationS: null,
      ));
      expect(suggestedValues(squat, 1, const [], ramp: ramp), (
        weightKg: 75.0,
        reps: 4,
        durationS: null,
      ));
      final fromLastTime = squat.copyWith(
        sets: const [warmup, warmup, WorkoutSet()],
      );
      expect(
        suggestedValues(fromLastTime, 1, [lift(80, 5)], ramp: ramp).weightKg,
        60,
      );
    });

    test('follow the scheme given', () {
      final squat = exercise('squat', const [
        warmup,
        warmup,
        warmup,
        WorkoutSet(weightKg: 100),
      ]);
      final full = (unit: kg, steps: WarmupScheme.full.presetSteps);
      expect(
        [
          for (var i = 0; i < 3; i++)
            suggestedValues(squat, i, const [], ramp: full).reps,
        ],
        [8, 5, 2],
      );
    });

    test('are empty while the working weight is unknown', () {
      final squat = exercise('squat', const [warmup, WorkoutSet()]);
      expect(suggestedValues(squat, 0, const [], ramp: ramp), (
        weightKg: null,
        reps: null,
        durationS: null,
      ));
    });

    test('only with a ramp, and only for weight and reps', () {
      final squat = exercise('squat', const [
        warmup,
        WorkoutSet(weightKg: 100),
      ]);
      expect(suggestedValues(squat, 0, const []).weightKg, isNull);
      final dip = exercise('dip', const [
        warmup,
        WorkoutSet(weightKg: 20),
      ], type: LoggingType.weightedBodyweight);
      expect(suggestedValues(dip, 0, const [], ramp: ramp).weightKg, isNull);
    });
  });
}
