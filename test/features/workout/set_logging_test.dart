import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
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
        validateSet(
          lift(60, 8).copyWith(rir: () => 11),
          LoggingType.weightReps,
        ),
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
}
