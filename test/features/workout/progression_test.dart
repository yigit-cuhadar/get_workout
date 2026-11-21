import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/features/workout/domain/progression.dart';
import 'package:get_workout/features/workout/domain/workout.dart';

import 'fixtures.dart';

void main() {
  const kg = WeightUnit.kg;

  group('the best set', () {
    test('is the heaviest, then the one with most reps', () {
      final best = bestSet([
        lift(100, 3, type: SetType.warmup),
        lift(80, 8),
        lift(82.5, 5),
        lift(82.5, 6),
      ], LoggingType.weightReps);
      expect(best, lift(82.5, 6));
    });

    test('is the least assistance for an assisted exercise', () {
      final best = bestSet([
        lift(30, 8),
        lift(20, 6),
      ], LoggingType.assistedBodyweight);
      expect(best, lift(20, 6));
    });

    test('is the longest of timed sets', () {
      final best = bestSet(const [
        WorkoutSet(durationS: 40),
        WorkoutSet(durationS: 45),
      ], LoggingType.duration);
      expect(best?.durationS, 45);
    });

    test('is none without a working set', () {
      expect(
        bestSet([lift(40, 8, type: SetType.warmup)], LoggingType.weightReps),
        isNull,
      );
    });
  });

  group('the progression', () {
    final squat = exercise('squat', const [
      WorkoutSet(),
    ]).copyWith(goal: () => item('squat', repMin: 6, repMax: 8));

    LastSession last(List<WorkoutSet> sets) =>
        LastSession(date: DateTime(2026, 11, 6), workoutId: 'w0', sets: sets);

    test('needs every working set at the top of the range', () {
      expect(progression(squat, last([lift(80, 8), lift(80, 8)]), kg), (
        kg: 82.5,
        reps: 8,
      ));
      expect(progression(squat, last([lift(80, 8), lift(80, 7)]), kg), isNull);
    });

    test("steps by the exercise's increment when it has one", () {
      final sets = last([lift(20, 8)]);
      expect(progression(squat, sets, kg, incrementKg: 1.25), (
        kg: 21.25,
        reps: 8,
      ));
      expect(progression(squat, sets, kg, incrementKg: 5), (kg: 25.0, reps: 8));
      expect(progression(squat, sets, kg, incrementKg: 0), (kg: 22.5, reps: 8));
    });

    test('in lb the increment rounds to 2.5 lb, at least 2.5', () {
      // 100 lb lifted, typed in lb.
      final sets = last([lift(WeightUnit.lb.toKg(100), 8)]);
      double lbOf(({double kg, int reps})? p) =>
          WeightUnit.lb.shownFromKg(p!.kg);
      expect(
        lbOf(progression(squat, sets, WeightUnit.lb, incrementKg: 2.5)),
        105,
      );
      expect(
        lbOf(progression(squat, sets, WeightUnit.lb, incrementKg: 1.25)),
        102.5,
      );
      expect(lbOf(progression(squat, sets, WeightUnit.lb)), 105);
    });

    test('ignores warm-ups', () {
      expect(
        progression(
          squat,
          last([lift(40, 5, type: SetType.warmup), lift(80, 8)]),
          kg,
        ),
        (kg: 82.5, reps: 8),
      );
    });

    test('needs a rep range and a load lifted for reps', () {
      final free = squat.copyWith(goal: () => null);
      expect(progression(free, last([lift(80, 8)]), kg), isNull);
      final pullUp = exercise('pull', const [
        WorkoutSet(),
      ], type: LoggingType.weightedBodyweight).copyWith(goal: () => squat.goal);
      expect(progression(pullUp, last([lift(10, 8)]), kg), isNull);
      expect(progression(squat, null, kg), isNull);
    });

    test('stays open while a working set to do lifts less', () {
      expect(progressionOpen(squat, 82.5), isTrue);
      final filled = squat.copyWith(
        sets: [lift(82.5, 0, done: false), lift(80, 8)],
      );
      expect(progressionOpen(filled, 82.5), isFalse);
    });
  });
}
