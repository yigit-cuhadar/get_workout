import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/workout/domain/set_logging.dart';
import 'package:get_workout/features/workout/domain/warmups.dart';
import 'package:get_workout/features/workout/domain/workout.dart';

import 'fixtures.dart';

void main() {
  const warmup = WorkoutSet(type: SetType.warmup);

  group('withWarmups', () {
    test('puts two empty warm-ups before the sets of a weighted lift', () {
      final squat = withWarmups(
        exercise('squat', const [WorkoutSet(), WorkoutSet()]),
      );
      expect(squat.sets, const [warmup, warmup, WorkoutSet(), WorkoutSet()]);
    });

    test('only for weight and reps', () {
      for (final type in LoggingType.values) {
        final added = withWarmups(
          exercise('x', const [WorkoutSet()], type: type),
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
      expect(withWarmups(warmed), warmed);
      final full = exercise(
        'squat',
        List.filled(WorkoutLimits.maxSets - 1, const WorkoutSet()),
      );
      expect(withWarmups(full), full);
    });
  });

  group('rampedWarmup', () {
    test('half the weight for 8, then three quarters for 4', () {
      expect(rampedWarmup(0, 100, WeightUnit.kg), (weightKg: 50, reps: 8));
      expect(rampedWarmup(1, 100, WeightUnit.kg), (weightKg: 75, reps: 4));
      // A third warm-up repeats the last step.
      expect(rampedWarmup(2, 100, WeightUnit.kg), (weightKg: 75, reps: 4));
    });

    test('rounds to 2.5 kg', () {
      expect(rampedWarmup(0, 63, WeightUnit.kg)!.weightKg, 32.5);
      expect(rampedWarmup(1, 63, WeightUnit.kg)!.weightKg, 47.5);
    });

    test('rounds to 5 lb', () {
      final working = WeightUnit.lb.toKg(185);
      final first = rampedWarmup(0, working, WeightUnit.lb)!;
      final second = rampedWarmup(1, working, WeightUnit.lb)!;
      expect(WeightUnit.lb.fromKg(first.weightKg), closeTo(95, 1e-9));
      expect(WeightUnit.lb.fromKg(second.weightKg), closeTo(140, 1e-9));
    });

    test('never below one step nor above the working weight', () {
      expect(rampedWarmup(0, 4, WeightUnit.kg)!.weightKg, 2.5);
      expect(rampedWarmup(1, 2, WeightUnit.kg)!.weightKg, 2);
      expect(
        WeightUnit.lb.fromKg(rampedWarmup(0, 4, WeightUnit.lb)!.weightKg),
        closeTo(5, 1e-9),
      );
    });

    test('nothing without a working weight', () {
      expect(rampedWarmup(0, null, WeightUnit.kg), isNull);
      expect(rampedWarmup(0, 0, WeightUnit.kg), isNull);
    });
  });

  group('warm-up suggestions', () {
    test('follow the first working set, typed or suggested', () {
      final squat = exercise('squat', const [
        warmup,
        warmup,
        WorkoutSet(weightKg: 100),
      ]);
      expect(suggestedValues(squat, 0, const [], warmupUnit: WeightUnit.kg), (
        weightKg: 50.0,
        reps: 8,
        durationS: null,
      ));
      expect(suggestedValues(squat, 1, const [], warmupUnit: WeightUnit.kg), (
        weightKg: 75.0,
        reps: 4,
        durationS: null,
      ));
      final fromLastTime = squat.copyWith(
        sets: const [warmup, warmup, WorkoutSet()],
      );
      expect(
        suggestedValues(fromLastTime, 1, [
          lift(80, 5),
        ], warmupUnit: WeightUnit.kg).weightKg,
        60,
      );
    });

    test('are empty while the working weight is unknown', () {
      final squat = exercise('squat', const [warmup, WorkoutSet()]);
      expect(suggestedValues(squat, 0, const [], warmupUnit: WeightUnit.kg), (
        weightKg: null,
        reps: null,
        durationS: null,
      ));
    });

    test('only with a unit, and only for weight and reps', () {
      final squat = exercise('squat', const [
        warmup,
        WorkoutSet(weightKg: 100),
      ]);
      expect(suggestedValues(squat, 0, const []).weightKg, isNull);
      final dip = exercise('dip', const [
        warmup,
        WorkoutSet(weightKg: 20),
      ], type: LoggingType.weightedBodyweight);
      expect(
        suggestedValues(dip, 0, const [], warmupUnit: WeightUnit.kg).weightKg,
        isNull,
      );
    });
  });
}
