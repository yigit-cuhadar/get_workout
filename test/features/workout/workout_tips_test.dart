import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/domain/workout_tips.dart';

import 'fixtures.dart';

void main() {
  const warmup = WorkoutSet(type: SetType.warmup);

  group('effort', () {
    test('due once a set is ticked', () {
      final fresh = workout('w', [
        exercise('squat', const [WorkoutSet()]),
      ]);
      expect(effortTipDue(fresh, const {}), isFalse);
      final ticked = workout('w', [
        exercise('squat', [lift(100, 5)]),
      ]);
      expect(effortTipDue(ticked, const {}), isTrue);
    });

    test('not once seen or once an effort is logged', () {
      final ticked = workout('w', [
        exercise('squat', [lift(100, 5)]),
      ]);
      expect(effortTipDue(ticked, const {Tip.effort}), isFalse);
      final rated = workout('w', [
        exercise('squat', [lift(100, 5), const WorkoutSet(rir: 2)]),
      ]);
      expect(effortTipDue(rated, const {}), isFalse);
      final failed = workout('w', [
        exercise('squat', [lift(100, 5), const WorkoutSet(toFailure: true)]),
      ]);
      expect(effortTipDue(failed, const {}), isFalse);
    });
  });

  test('set types: due until seen', () {
    expect(setTypesTipDue(const {}), isTrue);
    expect(setTypesTipDue(const {Tip.setTypes}), isFalse);
  });

  group('automatic warm-ups', () {
    final warmed = workout('w', [
      exercise('squat', const [warmup, WorkoutSet()]),
    ]);

    test('due while on and a weighted exercise has a warm-up', () {
      expect(autoWarmupsTipDue(warmed, const {}, autoWarmups: true), isTrue);
      expect(autoWarmupsTipDue(warmed, const {}, autoWarmups: false), isFalse);
      expect(
        autoWarmupsTipDue(warmed, const {Tip.autoWarmups}, autoWarmups: true),
        isFalse,
      );
    });

    test('not for other exercises or without warm-ups', () {
      final cold = workout('w', [
        exercise('squat', const [WorkoutSet()]),
      ]);
      expect(autoWarmupsTipDue(cold, const {}, autoWarmups: true), isFalse);
      final timed = workout('w', [
        exercise('plank', const [warmup], type: LoggingType.duration),
      ]);
      expect(autoWarmupsTipDue(timed, const {}, autoWarmups: true), isFalse);
    });
  });
}
