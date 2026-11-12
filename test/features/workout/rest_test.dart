import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/workout/domain/rest.dart';
import 'package:get_workout/features/workout/domain/workout.dart';

import 'fixtures.dart';

void main() {
  const settings = RestTimerSettings(defaultS: 75);
  final exerciseRest = {'squat': 150, 'bench': 120};
  int? exerciseRestS(String id) => exerciseRest[id];

  WorkoutSet open() => const WorkoutSet();
  WorkoutExercise withGoal(WorkoutExercise exercise, int restS) =>
      exercise.copyWith(goal: () => item(exercise.exerciseId, restS: restS));

  Duration? rest(Workout w, SetRef ref, {RestTimerSettings? using}) =>
      restAfterTick(
        w,
        ref,
        settings: using ?? settings,
        exerciseRestS: exerciseRestS,
      );

  group('restAfterTick', () {
    test('the program rest comes first', () {
      final w = workout('w', [
        withGoal(exercise('squat', [lift(100, 5)]), 180),
      ]);
      expect(rest(w, (exercise: 0, set: 0)), const Duration(seconds: 180));
    });

    test('without a program rest, the exercise default', () {
      final w = workout('w', [
        exercise('squat', [lift(100, 5)]),
      ]);
      expect(rest(w, (exercise: 0, set: 0)), const Duration(seconds: 150));
    });

    test('without either, the settings default', () {
      final w = workout('w', [
        exercise('custom_1', [lift(20, 10)]),
      ]);
      expect(rest(w, (exercise: 0, set: 0)), const Duration(seconds: 75));
    });

    test('a program rest of 0 means none', () {
      final w = workout('w', [
        withGoal(exercise('squat', [lift(100, 5)]), 0),
      ]);
      expect(rest(w, (exercise: 0, set: 0)), isNull);
    });

    test('none while the timer is off', () {
      final w = workout('w', [
        exercise('squat', [lift(100, 5)]),
      ]);
      expect(
        rest(w, (
          exercise: 0,
          set: 0,
        ), using: settings.copyWith(enabled: false)),
        isNull,
      );
    });

    test('a warm-up starts none, a drop set one', () {
      final w = workout('w', [
        exercise('squat', [
          lift(60, 5, type: SetType.warmup),
          lift(100, 8, type: SetType.drop, drops: const [Drop(weightKg: 80)]),
        ]),
      ]);
      expect(rest(w, (exercise: 0, set: 0)), isNull);
      expect(rest(w, (exercise: 0, set: 1)), const Duration(seconds: 150));
    });

    test('none for a set that does not exist', () {
      final w = workout('w', [
        exercise('squat', [lift(100, 5)]),
      ]);
      expect(rest(w, (exercise: 0, set: 3)), isNull);
      expect(rest(w, (exercise: 2, set: 0)), isNull);
    });

    group('in a superset or circuit', () {
      final w = workout('w', [
        exercise('row', [open()]),
        withGoal(exercise('bench', [open(), open(), open()], group: 'A'), 60),
        withGoal(exercise('fly', [open(), open()], group: 'A'), 45),
        exercise('squat', [open()]),
      ]);

      test('only the round\'s last item starts a rest', () {
        expect(rest(w, (exercise: 1, set: 0)), isNull);
        expect(rest(w, (exercise: 2, set: 0)), const Duration(seconds: 45));
      });

      test('a round the last item has no set for ends earlier', () {
        expect(rest(w, (exercise: 1, set: 2)), const Duration(seconds: 45));
      });

      test('the group\'s last exercise gives the rest', () {
        final circuit = workout('w', [
          exercise('squat', [open()], group: 'A'),
          exercise('bench', [open()], group: 'A'),
          exercise('custom_1', [open()], group: 'A'),
        ]);
        expect(
          rest(circuit, (exercise: 2, set: 0)),
          const Duration(seconds: 75),
        );
      });

      test('exercises outside the group rest on their own', () {
        expect(rest(w, (exercise: 0, set: 0)), const Duration(seconds: 75));
        expect(rest(w, (exercise: 3, set: 0)), const Duration(seconds: 150));
      });
    });
  });

  group('nextSet', () {
    test('goes set after set, then to the next exercise', () {
      final w = workout('w', [
        exercise('squat', [lift(100, 5), open()]),
        exercise('bench', [open()]),
      ]);
      expect(nextSet(w, (exercise: 0, set: 0)), (exercise: 0, set: 1));
      expect(nextSet(w, (exercise: 0, set: 1)), (exercise: 1, set: 0));
    });

    test('goes round by round in a group', () {
      final w = workout('w', [
        exercise('bench', [lift(60, 8), open(), open()], group: 'A'),
        exercise('fly', [lift(10, 12), open()], group: 'A'),
        exercise('squat', [open()]),
      ]);
      expect(nextSet(w, (exercise: 1, set: 0)), (exercise: 0, set: 1));
      expect(nextSet(w, (exercise: 0, set: 1)), (exercise: 1, set: 1));
      expect(nextSet(w, (exercise: 1, set: 1)), (exercise: 0, set: 2));
      expect(nextSet(w, (exercise: 0, set: 2)), (exercise: 2, set: 0));
    });

    test('skips done sets and comes back to ones left behind', () {
      final w = workout('w', [
        exercise('squat', [open(), lift(100, 5)]),
        exercise('bench', [lift(60, 8)]),
      ]);
      expect(nextSet(w, (exercise: 1, set: 0)), (exercise: 0, set: 0));
    });

    test('without a set to start from, the first one not done', () {
      final w = workout('w', [
        exercise('squat', [lift(100, 5), open()]),
      ]);
      expect(nextSet(w, null), (exercise: 0, set: 1));
    });

    test('null when every set is done', () {
      final w = workout('w', [
        exercise('squat', [lift(100, 5)]),
      ]);
      expect(nextSet(w, (exercise: 0, set: 0)), isNull);
    });
  });

  group('warm-ups in a group', () {
    // A = [W, 1, 2, 3], B = [1, 2, 3]: A's warm-up shifts no round.
    WorkoutSet warmup() => const WorkoutSet(type: SetType.warmup);
    final w = workout('w', [
      exercise('bench', [warmup(), open(), open(), open()], group: 'A'),
      withGoal(exercise('fly', [open(), open(), open()], group: 'A'), 45),
    ]);

    test('rounds count working sets', () {
      expect(rest(w, (exercise: 0, set: 0)), isNull);
      expect(rest(w, (exercise: 0, set: 1)), isNull);
      expect(rest(w, (exercise: 1, set: 0)), const Duration(seconds: 45));
      expect(rest(w, (exercise: 0, set: 3)), isNull);
      expect(rest(w, (exercise: 1, set: 2)), const Duration(seconds: 45));
    });

    test('the next set follows the same rounds, warm-ups first', () {
      expect(nextSet(w, null), (exercise: 0, set: 0));
      expect(nextSet(w, (exercise: 0, set: 0)), (exercise: 0, set: 1));
      expect(nextSet(w, (exercise: 0, set: 1)), (exercise: 1, set: 0));
      expect(nextSet(w, (exercise: 1, set: 0)), (exercise: 0, set: 2));
      expect(nextSet(w, (exercise: 0, set: 3)), (exercise: 1, set: 2));
    });
  });

  group('edits', () {
    final before = workout('w', [
      exercise('squat', [lift(100, 5), open()]),
      exercise('bench', [open()]),
    ]);
    Workout edited(List<WorkoutExercise> exercises) => workout('w', exercises);
    final end = DateTime(2026, 11, 11, 18, 2);
    final rest = Rest(endsAt: end, after: (exercise: 0, set: 0));

    test('newlyDone finds the ticked set', () {
      final after = edited([
        exercise('squat', [lift(100, 5), lift(100, 5)]),
        exercise('bench', [open()]),
      ]);
      expect(newlyDone(before, after), (exercise: 0, set: 1));
      expect(newlyDone(after, before), isNull);
    });

    test('newlyDone ignores edits that change the shape', () {
      final after = edited([
        exercise('bench', [lift(60, 8)]),
        exercise('squat', [lift(100, 5), open()]),
      ]);
      expect(newlyDone(before, after), isNull);
    });

    test('the rest ends when its set is unticked', () {
      final after = edited([
        exercise('squat', [open(), open()]),
        exercise('bench', [open()]),
      ]);
      expect(rest.followEdit(after, movesSets: false), isNull);
    });

    test('the rest goes on through other edits', () {
      final after = edited([
        exercise('squat', [lift(100, 5), open(), open()]),
        exercise('bench', [open()]),
        exercise('row', [open()]),
      ]);
      expect(rest.followEdit(after, movesSets: false), rest);
    });

    test('an edit that moves sets forgets the set', () {
      expect(rest.followEdit(before, movesSets: true), Rest(endsAt: end));
    });

    test('an empty workout has no rest, even an unlinked one', () {
      final empty = edited(const []);
      expect(empty.isEmpty, isTrue);
      expect(before.isEmpty, isFalse);
      expect(rest.followEdit(empty, movesSets: true), isNull);
      expect(Rest(endsAt: end).followEdit(empty, movesSets: false), isNull);
    });
  });

  group('Rest', () {
    final end = DateTime(2026, 11, 11, 18, 2);
    final rest = Rest(endsAt: end, after: (exercise: 1, set: 2));

    test('runs until its end', () {
      expect(rest.runsAt(end.subtract(const Duration(seconds: 1))), isTrue);
      expect(rest.runsAt(end), isFalse);
    });

    test('+15 s moves the end and keeps the set', () {
      final now = end.subtract(const Duration(minutes: 1));
      expect(
        rest.extendedAt(now),
        Rest(endsAt: end.add(const Duration(seconds: 15)), after: rest.after),
      );
    });

    test('+15 s never goes past the cap', () {
      final now = end.subtract(maxRestAhead);
      expect(rest.extendedAt(now).endsAt, end);
    });

    test('an end further ahead than the cap does not run', () {
      final now = end
          .subtract(maxRestAhead)
          .subtract(const Duration(seconds: 1));
      expect(rest.runsAt(now), isFalse);
    });

    test('detached forgets the set', () {
      expect(rest.detached(), Rest(endsAt: end));
    });
  });
}
