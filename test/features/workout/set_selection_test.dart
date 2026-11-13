import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/workout/domain/rest.dart';
import 'package:get_workout/features/workout/domain/set_selection.dart';
import 'package:get_workout/features/workout/domain/workout.dart';

import 'fixtures.dart';

void main() {
  WorkoutSet todo() => lift(60, 8, done: false);
  WorkoutSet warmup({bool done = false}) =>
      lift(40, 10, type: SetType.warmup, done: done);

  group('resolveSelection', () {
    test('follows the next set to do until something is picked', () {
      final w = workout('w', [
        exercise('squat', [lift(100, 5), todo()]),
        exercise('bench', [todo()]),
      ]);
      expect(resolveSelection(w, null), (exercise: 0, set: 1));
      expect(resolveSelection(w, (exercise: 1, set: 0)), (exercise: 1, set: 0));
    });

    test('a pick that no longer points into the workout is dropped', () {
      final w = workout('w', [
        exercise('squat', [todo()]),
      ]);
      expect(resolveSelection(w, (exercise: 0, set: 3)), (exercise: 0, set: 0));
      expect(resolveSelection(w, (exercise: 2, set: 0)), (exercise: 0, set: 0));
      // An exercise with sets always has one selected.
      expect(resolveSelection(w, (exercise: 0, set: null)), (
        exercise: 0,
        set: 0,
      ));
    });

    test('with every set done, the first exercise\'s last set', () {
      final w = workout('w', [
        exercise('squat', [lift(100, 5), lift(100, 5)]),
        exercise('bench', [lift(60, 8)]),
      ]);
      expect(resolveSelection(w, null), (exercise: 0, set: 1));
    });

    test('an exercise without sets opens with none selected', () {
      final w = workout('w', [exercise('squat', [])]);
      expect(resolveSelection(w, null), (exercise: 0, set: null));
      expect(resolveSelection(w, (exercise: 0, set: null)), (
        exercise: 0,
        set: null,
      ));
    });

    test('nothing without a workout or exercises', () {
      expect(resolveSelection(null, null), isNull);
      expect(resolveSelection(workout('w', []), null), isNull);
    });
  });

  test('opening an exercise selects its first undone set, else its last', () {
    final w = workout('w', [
      exercise('squat', [lift(100, 5), todo(), todo()]),
      exercise('bench', [lift(60, 8), lift(60, 8)]),
    ]);
    expect(openedExercise(w, 0), (exercise: 0, set: 1));
    expect(openedExercise(w, 1), (exercise: 1, set: 1));
  });

  group('after a tick', () {
    test('the next set of the exercise, then the next exercise', () {
      final w = workout('w', [
        exercise('squat', [lift(100, 5), todo()]),
        exercise('bench', [todo()]),
      ]);
      expect(selectionAfterTick(w, (exercise: 0, set: 0)), (
        exercise: 0,
        set: 1,
      ));
      final squatDone = workout('w', [
        exercise('squat', [lift(100, 5), lift(100, 5)]),
        exercise('bench', [todo()]),
      ]);
      expect(selectionAfterTick(squatDone, (exercise: 0, set: 1)), (
        exercise: 1,
        set: 0,
      ));
    });

    test('a skipped set earlier comes back once the end is reached', () {
      final w = workout('w', [
        exercise('squat', [todo(), lift(100, 5)]),
        exercise('bench', [lift(60, 8)]),
      ]);
      expect(selectionAfterTick(w, (exercise: 1, set: 0)), (
        exercise: 0,
        set: 0,
      ));
    });

    test('a superset goes round by round, warm-ups first', () {
      final w = workout('w', [
        exercise('squat', [
          warmup(done: true),
          lift(100, 5),
          todo(),
        ], group: 'A'),
        exercise('row', [todo(), todo()], group: 'A'),
      ]);
      // A1 round 1 done: B round 1.
      expect(selectionAfterTick(w, (exercise: 0, set: 1)), (
        exercise: 1,
        set: 0,
      ));
      final round1 = workout('w', [
        exercise('squat', [
          warmup(done: true),
          lift(100, 5),
          todo(),
        ], group: 'A'),
        exercise('row', [lift(50, 10), todo()], group: 'A'),
      ]);
      // Round 1 complete: round 2 starts with the first exercise.
      expect(selectionAfterTick(round1, (exercise: 1, set: 0)), (
        exercise: 0,
        set: 2,
      ));
    });

    test('the last set of the workout stays selected', () {
      final w = workout('w', [
        exercise('squat', [lift(100, 5)]),
      ]);
      expect(selectionAfterTick(w, (exercise: 0, set: 0)), (
        exercise: 0,
        set: 0,
      ));
    });
  });

  group('after moving a set', () {
    const moved = (exercise: 0, set: 3);

    test('the moved set is followed', () {
      expect(selectionAfterSetMoved((exercise: 0, set: 3), moved, 1), (
        exercise: 0,
        set: 1,
      ));
    });

    test('sets it passes shift, others stay', () {
      expect(selectionAfterSetMoved((exercise: 0, set: 1), moved, 1), (
        exercise: 0,
        set: 2,
      ));
      expect(selectionAfterSetMoved((exercise: 0, set: 0), moved, 1), (
        exercise: 0,
        set: 0,
      ));
      expect(selectionAfterSetMoved((exercise: 0, set: 4), moved, 1), (
        exercise: 0,
        set: 4,
      ));
      expect(
        selectionAfterSetMoved((exercise: 0, set: 2), (exercise: 0, set: 0), 2),
        (exercise: 0, set: 1),
      );
    });

    test('another exercise or no set is left alone', () {
      expect(selectionAfterSetMoved((exercise: 1, set: 1), moved, 0), (
        exercise: 1,
        set: 1,
      ));
      expect(selectionAfterSetMoved((exercise: 0, set: null), moved, 0), (
        exercise: 0,
        set: null,
      ));
      expect(selectionAfterSetMoved(null, moved, 0), isNull);
    });
  });

  group('after removing a set', () {
    final after = workout('w', [
      exercise('squat', [todo(), todo()]),
      exercise('bench', [todo()]),
    ]);
    const removed = (exercise: 0, set: 1);

    test('a later set of the exercise moves up, others stay', () {
      expect(selectionAfterSetRemoved(after, (exercise: 0, set: 2), removed), (
        exercise: 0,
        set: 1,
      ));
      expect(selectionAfterSetRemoved(after, (exercise: 0, set: 0), removed), (
        exercise: 0,
        set: 0,
      ));
      expect(selectionAfterSetRemoved(after, (exercise: 1, set: 0), removed), (
        exercise: 1,
        set: 0,
      ));
    });

    test('the removed one gives way to the next, else the one before', () {
      expect(selectionAfterSetRemoved(after, (exercise: 0, set: 1), removed), (
        exercise: 0,
        set: 1,
      ));
      expect(
        selectionAfterSetRemoved(
          after,
          (exercise: 0, set: 2),
          (exercise: 0, set: 2),
        ),
        (exercise: 0, set: 1),
      );
    });

    test('the last set leaves the exercise open without one', () {
      final emptied = workout('w', [exercise('squat', [])]);
      expect(
        selectionAfterSetRemoved(
          emptied,
          (exercise: 0, set: 0),
          (exercise: 0, set: 0),
        ),
        (exercise: 0, set: null),
      );
    });
  });

  test(
    'after removing an exercise, later ones move up; its own is dropped',
    () {
      expect(selectionAfterExerciseRemoved((exercise: 2, set: 1), 1), (
        exercise: 1,
        set: 1,
      ));
      expect(selectionAfterExerciseRemoved((exercise: 0, set: 1), 1), (
        exercise: 0,
        set: 1,
      ));
      expect(selectionAfterExerciseRemoved((exercise: 1, set: 1), 1), isNull);
    },
  );

  test('after a move, the selection follows its exercise and group', () {
    final before = [
      exercise('squat', []),
      exercise('bench', [], group: 'A'),
      exercise('row', [], group: 'A'),
      exercise('plank', []),
    ];
    // Plank to the top: everything else moves down.
    expect(selectionAfterExerciseMoved(before, (exercise: 2, set: 1), 3, 0), (
      exercise: 3,
      set: 1,
    ));
    // Squat down onto the group: the whole group moves up past it.
    expect(selectionAfterExerciseMoved(before, (exercise: 0, set: 0), 0, 1), (
      exercise: 2,
      set: 0,
    ));
    expect(selectionAfterExerciseMoved(before, (exercise: 1, set: 0), 0, 1), (
      exercise: 0,
      set: 0,
    ));
    // Within the group, only the exercise moves.
    expect(selectionAfterExerciseMoved(before, (exercise: 2, set: 0), 2, 1), (
      exercise: 1,
      set: 0,
    ));
  });

  group('after adding exercises', () {
    final added = exercise('bench', [todo()]);

    test('the first added opens when nothing was left to do', () {
      final before = workout('w', [
        exercise('squat', [lift(100, 5)]),
      ]);
      final after = workout('w', [...before.exercises, added, added]);
      expect(
        selectionAfterExercisesAdded(before, after, (exercise: 0, set: 0)),
        (exercise: 1, set: 0),
      );
    });

    test('the selection stays while sets are left to do', () {
      final before = workout('w', [
        exercise('squat', [todo()]),
      ]);
      final after = workout('w', [...before.exercises, added]);
      expect(
        selectionAfterExercisesAdded(before, after, (exercise: 0, set: 0)),
        (exercise: 0, set: 0),
      );
    });
  });

  group('effort', () {
    final w = workout('w', [
      exercise('squat', [
        lift(40, 8, type: SetType.warmup),
        lift(100, 5),
        lift(100, 5, done: false),
      ]),
    ]);

    test(
      'the bar asks about a done working set whose tick started no rest',
      () {
        SetRef? asked(SetRef? ref, {bool withRest = false}) =>
            questionSet(w, ref, withRest: withRest);
        expect(asked((exercise: 0, set: 1)), (exercise: 0, set: 1));
        expect(asked((exercise: 0, set: 1), withRest: true), isNull);
        expect(asked(null), isNull);
        expect(asked((exercise: 0, set: 0)), isNull);
        expect(asked((exercise: 0, set: 2)), isNull);
        expect(asked((exercise: 3, set: 0)), isNull);
      },
    );

    test('the rest strip asks while the rest its tick started runs', () {
      const ref = (exercise: 0, set: 1);
      final at = DateTime(2026, 11, 11, 18);
      final rest = Rest(
        endsAt: at.add(const Duration(seconds: 90)),
        after: ref,
      );
      SetRef? asked(Rest? rest, {DateTime? now, bool withRest = true}) =>
          restQuestionSet(
            w,
            ref,
            withRest: withRest,
            rest: rest,
            now: now ?? at,
          );
      expect(asked(rest), ref);
      expect(asked(rest, withRest: false), isNull);
      expect(asked(null), isNull);
      expect(asked(rest.detached()), isNull);
      expect(asked(rest, now: rest.endsAt), isNull);
      expect(asked(rest.extendedAt(at), now: rest.endsAt), ref);
    });

    test('the effort row is the selected set when it is done', () {
      expect(effortRowSet(w, (exercise: 0, set: 1)), (exercise: 0, set: 1));
      expect(effortRowSet(w, (exercise: 0, set: 2)), isNull);
      expect(effortRowSet(w, (exercise: 0, set: 0)), isNull);
      expect(effortRowSet(w, (exercise: 0, set: null)), isNull);
    });
  });
}
