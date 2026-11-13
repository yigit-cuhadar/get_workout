import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/workout/domain/set_logging.dart';
import 'package:get_workout/features/workout/domain/workout.dart';

import 'fixtures.dart';

void main() {
  group('validateSet', () {
    test('weight and reps need both', () {
      expect(validateSet(lift(60, 8), LoggingType.weightReps), isEmpty);
      expect(validateSet(const WorkoutSet(reps: 8), LoggingType.weightReps), {
        SetIssue.weightMissing,
      });
      expect(
        validateSet(const WorkoutSet(weightKg: 60), LoggingType.weightReps),
        {SetIssue.repsMissing},
      );
    });

    test('bodyweight types take no weight as none added', () {
      for (final type in [
        LoggingType.reps,
        LoggingType.weightedBodyweight,
        LoggingType.assistedBodyweight,
      ]) {
        expect(validateSet(const WorkoutSet(reps: 10), type), isEmpty);
      }
    });

    test('duration types need a duration, not reps', () {
      expect(
        validateSet(const WorkoutSet(durationS: 45), LoggingType.duration),
        isEmpty,
      );
      expect(validateSet(const WorkoutSet(), LoggingType.duration), {
        SetIssue.durationMissing,
      });
      expect(
        validateSet(
          const WorkoutSet(durationS: 45),
          LoggingType.weightDuration,
        ),
        {SetIssue.weightMissing},
      );
    });

    test('values out of range, NaN included, are refused', () {
      expect(validateSet(lift(-1, 8), LoggingType.weightReps), {
        SetIssue.weightOutOfRange,
      });
      expect(validateSet(lift(double.nan, 8), LoggingType.weightReps), {
        SetIssue.weightOutOfRange,
      });
      expect(validateSet(lift(1001, 8), LoggingType.weightReps), {
        SetIssue.weightOutOfRange,
      });
      expect(validateSet(lift(60, 0), LoggingType.weightReps), {
        SetIssue.repsOutOfRange,
      });
      expect(
        validateSet(const WorkoutSet(durationS: 0), LoggingType.duration),
        {SetIssue.durationOutOfRange},
      );
      expect(
        validateSet(lift(60, 8).copyWith(rir: () => 6), LoggingType.weightReps),
        {SetIssue.rirOutOfRange},
      );
    });

    test('drops need weight and reps on a drop set only', () {
      final drop = lift(
        60,
        8,
        type: SetType.drop,
        drops: const [Drop(weightKg: 40, reps: 6)],
      );
      expect(validateSet(drop, LoggingType.weightReps), isEmpty);
      expect(
        validateSet(
          drop.copyWith(drops: const [Drop(weightKg: 40)]),
          LoggingType.weightReps,
        ),
        {SetIssue.dropsInvalid},
      );
      expect(
        validateSet(
          drop.copyWith(type: SetType.normal),
          LoggingType.weightReps,
        ),
        {SetIssue.dropsInvalid},
      );
      expect(
        validateSet(
          drop.copyWith(
            drops: List.filled(6, const Drop(weightKg: 1, reps: 1)),
          ),
          LoggingType.weightReps,
        ),
        {SetIssue.dropsInvalid},
      );
    });
  });

  group('suggestedValues', () {
    final squat = exercise('squat', const [WorkoutSet(), WorkoutSet()]);

    test('last time at the same place first', () {
      expect(suggestedValues(squat, 1, [lift(50, 10), lift(60, 8)]), (
        weightKg: 60,
        reps: 8,
        durationS: null,
      ));
    });

    test('this workout\'s previous done set of the same type first', () {
      final carried = exercise('bench', [
        lift(40, 10, type: SetType.warmup),
        lift(80, 6),
        lift(85, 5, done: false),
        const WorkoutSet(),
        const WorkoutSet(type: SetType.warmup),
      ]);
      // A first-time exercise carries the weight over.
      expect(suggestedValues(carried, 3, const []), (
        weightKg: 80,
        reps: 6,
        durationS: null,
      ));
      expect(suggestedValues(carried, 4, [lift(100, 5)]), (
        weightKg: 40,
        reps: 10,
        durationS: null,
      ));
    });

    test('per value, the next source fills what the first lacks', () {
      final partial = exercise(
        'dip',
        [const WorkoutSet(reps: 12, done: true), const WorkoutSet()],
        type: LoggingType.weightedBodyweight,
      ).copyWith(goal: () => item('dip', targetKg: 10));
      expect(suggestedValues(partial, 1, const []), (
        weightKg: 10,
        reps: 12,
        durationS: null,
      ));
    });

    test('a warm-up gets nothing from last time or the goal', () {
      final warm = exercise('squat', const [
        WorkoutSet(type: SetType.warmup),
      ]).copyWith(goal: () => item('squat', targetKg: 100));
      expect(suggestedValues(warm, 0, [lift(100, 5)]), (
        weightKg: null,
        reps: null,
        durationS: null,
      ));
    });

    test('then the goal, at the bottom of its range', () {
      final planned = squat.copyWith(
        goal: () => item('squat', repMin: 6, repMax: 10, targetKg: 80),
      );
      expect(suggestedValues(planned, 1, [lift(50, 10)]), (
        weightKg: 80,
        reps: 6,
        durationS: null,
      ));
      expect(suggestedValues(squat, 0, const []), (
        weightKg: null,
        reps: null,
        durationS: null,
      ));
    });
  });

  test('lastTimeSet matches working sets in order, warm-ups none', () {
    final today = exercise('squat', [
      const WorkoutSet(type: SetType.warmup),
      const WorkoutSet(),
      const WorkoutSet(),
    ]);
    final last = [lift(100, 5), lift(105, 3)];
    expect(lastTimeSet(today, 0, last), isNull);
    expect(lastTimeSet(today, 1, last), lift(100, 5));
    expect(lastTimeSet(today, 2, last), lift(105, 3));
    expect(lastTimeSet(today, 3, last), isNull);
  });

  group('completeSet', () {
    const hint = (weightKg: 60.0, reps: 8, durationS: 30);

    test('fills only the empty values the type records', () {
      expect(
        completeSet(
          const WorkoutSet(weightKg: 70),
          LoggingType.weightReps,
          hint,
        ),
        const WorkoutSet(weightKg: 70, reps: 8, done: true),
      );
      expect(
        completeSet(const WorkoutSet(), LoggingType.reps, hint),
        const WorkoutSet(reps: 8, done: true),
      );
    });

    test('is null while the set is still invalid', () {
      expect(
        completeSet(const WorkoutSet(), LoggingType.weightReps, (
          weightKg: null,
          reps: 8,
          durationS: null,
        )),
        isNull,
      );
    });
  });

  group('steppers', () {
    test('a weight moves by 2.5 kg or 5 lb from what is shown', () {
      const kg = WeightUnit.kg;
      const lb = WeightUnit.lb;
      expect(steppedWeightKg(60, null, 1, kg), 62.5);
      expect(steppedWeightKg(60, null, -1, kg), 57.5);
      expect(lb.shownFromKg(steppedWeightKg(lb.toKg(135), null, 1, lb)), 140);
      // 135 lb (61.23 kg) shows as 61 kg: the step starts there.
      expect(steppedWeightKg(lb.toKg(135), null, 1, kg), 63.5);
    });

    test('an empty weight starts from the suggestion, else from none', () {
      expect(steppedWeightKg(null, 100, 1, WeightUnit.kg), 102.5);
      expect(steppedWeightKg(null, null, 1, WeightUnit.kg), 2.5);
    });

    test('a weight stays within its limits', () {
      expect(steppedWeightKg(0, null, -1, WeightUnit.kg), 0);
      expect(steppedWeightKg(1, null, -1, WeightUnit.kg), 0);
      expect(
        steppedWeightKg(WorkoutLimits.maxWeightKg, null, 1, WeightUnit.kg),
        WorkoutLimits.maxWeightKg,
      );
    });

    test('reps and seconds move by one, from the suggestion, from 1', () {
      expect(steppedCount(8, null, 1, 1000), 9);
      expect(steppedCount(8, 5, -1, 1000), 7);
      expect(steppedCount(null, 5, 1, 1000), 6);
      expect(steppedCount(null, null, 1, 1000), 1);
      expect(steppedCount(null, null, -1, 1000), 1);
      expect(steppedCount(1, null, -1, 1000), 1);
      expect(steppedCount(1000, null, 1, 1000), 1000);
    });
  });
}
