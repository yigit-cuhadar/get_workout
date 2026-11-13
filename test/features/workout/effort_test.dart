import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/workout/domain/effort.dart';
import 'package:get_workout/features/workout/domain/workout.dart';

void main() {
  WorkoutSet stored(int? rir, {bool toFailure = false}) =>
      WorkoutSet(rir: rir, toFailure: toFailure);

  test('every scale ends with failed', () {
    for (final scale in EffortScale.values) {
      expect(scale.steps.last, EffortStep.failure);
    }
    expect(EffortScale.byFeel.steps, const [
      EffortStep.reserve(4),
      EffortStep.reserve(2),
      EffortStep.reserve(1),
      EffortStep.reserve(0),
      EffortStep.failure,
    ]);
    expect(EffortScale.rir.steps.map((s) => s.rir), [5, 4, 3, 2, 1, 0, 0]);
    // RPE 6 or less (4 left and more) up to RPE 10.
    expect(EffortScale.rpe.steps.map((s) => s.rir), [4, 3, 2, 1, 0, 0]);
  });

  test('a picked step reads back as itself on every scale', () {
    for (final scale in EffortScale.values) {
      for (final step in scale.steps) {
        expect(scale.stepOf(const WorkoutSet().withEffort(step)), step);
      }
    }
  });

  test('failed is stored as to failure with rir 0', () {
    final set = const WorkoutSet().withEffort(EffortStep.failure);
    expect((set.rir, set.toFailure), (0, true));
    final cleared = set.withEffort(null);
    expect((cleared.rir, cleared.toFailure), (null, false));
    final easy = set.withEffort(const EffortStep.reserve(4));
    expect((easy.rir, easy.toFailure), (4, false));
  });

  test('by feel groups stored reps in reserve', () {
    final feel = EffortScale.byFeel;
    expect(feel.stepOf(stored(5)), const EffortStep.reserve(4));
    expect(feel.stepOf(stored(4)), const EffortStep.reserve(4));
    expect(feel.stepOf(stored(3)), const EffortStep.reserve(2));
    expect(feel.stepOf(stored(2)), const EffortStep.reserve(2));
    expect(feel.stepOf(stored(1)), const EffortStep.reserve(1));
    expect(feel.stepOf(stored(0)), const EffortStep.reserve(0));
  });

  test('RIR and RPE show the stored reps in reserve', () {
    expect(EffortScale.rir.stepOf(stored(3)), const EffortStep.reserve(3));
    expect(EffortScale.rpe.stepOf(stored(0)), const EffortStep.reserve(0));
    expect(EffortScale.rir.stepOf(stored(5)), const EffortStep.reserve(5));
    // More than 4 left is RPE 6 or less.
    expect(EffortScale.rpe.stepOf(stored(5)), const EffortStep.reserve(4));
  });

  test('older sets: to failure with any rir, or none, shows failed', () {
    for (final scale in EffortScale.values) {
      expect(scale.stepOf(stored(3, toFailure: true)), EffortStep.failure);
      expect(scale.stepOf(stored(null, toFailure: true)), EffortStep.failure);
      expect(scale.stepOf(stored(null)), isNull);
    }
  });

  test('a set has an effort once rated or failed', () {
    expect(stored(null).hasEffort, isFalse);
    expect(stored(0).hasEffort, isTrue);
    expect(stored(null, toFailure: true).hasEffort, isTrue);
  });
}
