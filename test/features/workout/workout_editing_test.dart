import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_validation.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/domain/workout_editing.dart';

import 'fixtures.dart';

void main() {
  final start = DateTime(2026, 11, 11, 18);
  final catalogue = {
    for (final e in [
      move('squat', name: 'Back Squat', rest: 120),
      move('lunge'),
      move('plank', type: LoggingType.duration, rest: 45),
      move('dip', type: LoggingType.assistedBodyweight),
    ])
      e.id: e,
  };
  final legs = Program(
    id: 'p1',
    name: 'Legs',
    days: [
      ProgramDay(
        name: 'A',
        items: [
          // Saved before groups were kept in step.
          item('gone', group: 'A', sets: 4),
          item('squat', group: 'A', sets: 4, targetKg: 100),
          item('lunge', group: 'A', restS: 60),
          item('plank', repMin: null, repMax: null, durationS: 60),
        ],
      ),
      ProgramDay(name: 'B', items: [item('lunge')]),
    ],
  );

  group('workoutFromProgramDay', () {
    final built = workoutFromProgramDay(
      id: 'w1',
      startedAt: start,
      name: 'Legs · A',
      program: legs,
      dayIndex: 0,
      catalogue: catalogue,
      language: 'en',
      warmups: null,
    );

    test('copies the exercises with their goals and empty sets', () {
      expect(built.programId, 'p1');
      expect(built.dayIndex, 0);
      final squat = built.exercises.first;
      expect(squat.name, 'Back Squat');
      expect(squat.loggingType, LoggingType.weightReps);
      expect(squat.mainMuscles, [Muscle.quads]);
      expect(squat.sets, List.filled(4, const WorkoutSet()));
      expect(squat.goal!.targetKg, 100);
      expect(squat.goal!.group, isNull);
    });

    test('with warm-ups, weighted exercises start with two', () {
      final warmed = workoutFromProgramDay(
        id: 'w1',
        startedAt: start,
        name: 'Legs · A',
        program: legs,
        dayIndex: 0,
        catalogue: catalogue,
        language: 'en',
        warmups: const WarmupSettings(),
      );
      expect(warmed.exercises.map((e) => e.sets.length), [6, 6, 3]);
      expect(warmed.exercises.first.sets.take(2).map((s) => s.type), [
        SetType.warmup,
        SetType.warmup,
      ]);
      // The plank is timed.
      expect(warmed.exercises.last.sets.any((s) => s.isWarmup), isFalse);
    });

    test('a group takes its first sets and last rest, as the builder', () {
      expect(
        built.exercises.map(
          (e) => (e.sets.length, e.goal!.sets, e.goal!.restS),
        ),
        [(4, 4, 60), (4, 4, 60), (3, 3, 90)],
      );
    });

    test('leaves out unavailable exercises and relabels groups', () {
      expect(built.exercises.map((e) => e.exerciseId), [
        'squat',
        'lunge',
        'plank',
      ]);
      expect(built.exercises.map((e) => e.group), ['A', 'A', null]);
    });
  });

  group('swapExercise', () {
    final squat = exerciseFor(
      catalogue['squat']!,
      'en',
      goal: item('squat', targetKg: 100, sets: 2),
    ).copyWith(group: () => 'A', sets: [lift(100, 5), const WorkoutSet()]);

    test('keeps sets of the same logging type', () {
      final swapped = swapExercise(squat, catalogue['lunge']!, 'en');
      expect(swapped.exerciseId, 'lunge');
      expect(swapped.name, 'lunge');
      expect(swapped.sets, squat.sets);
      expect(swapped.group, 'A');
      expect(swapped.goal!.exerciseId, 'lunge');
    });

    test('starts the sets over and fits the goal for another type', () {
      final swapped = swapExercise(squat, catalogue['plank']!, 'en');
      expect(swapped.loggingType, LoggingType.duration);
      expect(swapped.sets, const [WorkoutSet(), WorkoutSet()]);
      expect(swapped.goal!.durationS, 30);
      expect(swapped.goal!.repMin, isNull);
      expect(swapped.goal!.targetKg, isNull);
    });
  });

  group('changedProgramDay', () {
    final day = Program(
      id: 'p1',
      name: 'Legs',
      days: [
        ProgramDay(
          name: 'A',
          items: [
            item('squat', sets: 2, repMin: 5, repMax: 5, targetKg: 100),
            item('lunge'),
          ],
        ),
      ],
    );
    Workout done(List<WorkoutExercise> exercises) =>
        workout('w1', exercises, programId: 'p1', dayIndex: 0);
    final squat = exercise('squat', [lift(105, 5), lift(105, 5)]);
    final lunge = exercise('lunge', [lift(20, 10), lift(20, 10), lift(20, 9)]);

    test('reps and weights do not count', () {
      expect(changedProgramDay(done([squat, lunge]), day, catalogue), isNull);
    });

    test('a set count, order or rest change gives the new items', () {
      final more = done([
        squat.copyWith(sets: [...squat.sets, lift(105, 5, done: false)]),
        lunge,
      ]);
      final items = changedProgramDay(more, day, catalogue)!;
      expect(items.first.sets, 3);
      expect(items.first.targetKg, 100);
      expect(
        changedProgramDay(
          done([lunge, squat]),
          day,
          catalogue,
        )!.map((i) => i.exerciseId),
        ['lunge', 'squat'],
      );
      expect(
        changedProgramDay(
          done([squat.copyWith(restS: () => 180), lunge]),
          day,
          catalogue,
        )!.first.restS,
        180,
      );
    });

    test('an added exercise gets an item from its sets', () {
      final plank = exercise('plank', [
        const WorkoutSet(durationS: 40, done: true),
      ], type: LoggingType.duration);
      final items = changedProgramDay(
        done([squat, lunge, plank]),
        day,
        catalogue,
      )!;
      expect(items.last.exerciseId, 'plank');
      expect(items.last.durationS, 40);
      expect(items.last.restS, 45);
    });

    test('another program or a free workout is never changed', () {
      expect(changedProgramDay(workout('w', [lunge]), day, catalogue), isNull);
    });
  });

  group('swapKeepingLogged', () {
    final lunge = catalogue['lunge']!;

    test('is a plain swap while nothing is done', () {
      final list = [
        exercise('squat', [lift(100, 5, done: false)]),
      ];
      final result = swapKeepingLogged(list, 0, lunge, 'en');
      expect(result.swapped, 0);
      expect(result.exercises.single.exerciseId, 'lunge');
      expect(result.exercises.single.sets, list.single.sets);
    });

    test('keeps the done sets and moves the others right after', () {
      final list = [
        exercise('squat', [
          lift(100, 5),
          lift(100, 5),
          lift(100, 5, done: false),
        ]).copyWith(note: () => 'Belt'),
        exercise('plank', []),
      ];
      final result = swapKeepingLogged(list, 0, lunge, 'en');
      expect(result.swapped, 1);
      expect(result.exercises.map((e) => e.exerciseId), [
        'squat',
        'lunge',
        'plank',
      ]);
      expect(result.exercises[0].sets, [lift(100, 5), lift(100, 5)]);
      expect(result.exercises[0].note, 'Belt');
      expect(result.exercises[1].sets, [lift(100, 5, done: false)]);
      expect(result.exercises[1].note, isNull);
    });

    test('gives the replacement one empty set when all are done', () {
      final list = [
        exercise('squat', [lift(100, 5)]),
      ];
      final result = swapKeepingLogged(list, 0, lunge, 'en');
      expect(result.exercises[1].sets, const [WorkoutSet()]);
    });

    test('in a group the replacement takes its place, the done one leaves', () {
      final list = [
        exercise('plank', [], group: 'A'),
        exercise('squat', [
          lift(100, 5),
          lift(100, 5, done: false),
        ], group: 'A'),
        exercise('dip', [], group: 'A'),
      ];
      final result = swapKeepingLogged(list, 1, lunge, 'en');
      expect(result.swapped, 2);
      expect(
        [for (final e in result.exercises) (e.exerciseId, e.group)],
        [('squat', null), ('plank', 'A'), ('lunge', 'A'), ('dip', 'A')],
      );
    });
  });

  test('a new warm-up goes after the warm-ups, other sets at the end', () {
    final warmup = lift(40, 10, type: SetType.warmup);
    final working = exercise('squat', [lift(100, 5), lift(100, 5)]);
    expect(newSetPosition(working, SetType.warmup), 0);
    expect(newSetPosition(working, SetType.normal), 2);
    final warmed = exercise('squat', [warmup, warmup, lift(100, 5)]);
    expect(newSetPosition(warmed, SetType.warmup), 2);
    expect(newSetPosition(warmed, SetType.drop), 3);
    expect(newSetPosition(exercise('squat', []), SetType.warmup), 0);
  });

  test('a set that becomes or stops being a warm-up moves to their end', () {
    final warmup = lift(40, 10, type: SetType.warmup);
    final sets = exercise('squat', [warmup, lift(100, 5), lift(100, 5)]);
    expect(retypedSetPosition(sets, 2, SetType.warmup), 1);
    expect(retypedSetPosition(sets, 1, SetType.warmup), 1);
    expect(retypedSetPosition(sets, 0, SetType.normal), 0);
    expect(retypedSetPosition(sets, 2, SetType.drop), 2);
    expect(retypedSetPosition(sets, 0, SetType.warmup), 0);
    final warmed = exercise('squat', [warmup, warmup, lift(100, 5)]);
    expect(retypedSetPosition(warmed, 0, SetType.drop), 1);
    final working = exercise('squat', [lift(100, 5), lift(100, 5)]);
    expect(retypedSetPosition(working, 1, SetType.warmup), 0);
  });

  test('finishWorkout keeps done sets and drops empty exercises', () {
    final draft = workout('w1', [
      exercise('squat', [lift(100, 5), lift(100, 5, done: false)], group: 'A'),
      exercise('lunge', [lift(40, 8, done: false)], group: 'A'),
      exercise('plank', [lift(0, 1)]),
    ]);
    final end = start.add(const Duration(hours: 1));
    final finished = finishWorkout(draft, end);
    expect(finished.finishedAt, end);
    expect(finished.exercises.map((e) => e.exerciseId), ['squat', 'plank']);
    expect(finished.exercises.first.sets, [lift(100, 5)]);
    expect(finished.exercises.first.group, isNull);
  });

  test('finishWorkout never ends before the start', () {
    final draft = workout('w1', [
      exercise('squat', [lift(100, 5)]),
    ], startedAt: start);
    final earlier = start.subtract(const Duration(minutes: 5));
    expect(finishWorkout(draft, earlier).finishedAt, start);
  });

  test('fitsLimits checks name, note, exercises and sets', () {
    final ok = workout('w1', [
      exercise('squat', [lift(100, 5)]),
    ]);
    expect(fitsLimits(ok), isTrue);
    expect(
      fitsLimits(
        Workout(id: 'w1', startedAt: start, name: '', exercises: ok.exercises),
      ),
      isFalse,
    );
    expect(fitsLimits(ok.copyWith(note: () => 'x' * 1001)), isFalse);
    expect(
      fitsLimits(
        ok.copyWith(
          exercises: [
            exercise('squat', [lift(100, 5).copyWith(note: () => 'x' * 201)]),
          ],
        ),
      ),
      isFalse,
    );
    expect(
      fitsLimits(
        ok.copyWith(
          exercises: List.filled(
            WorkoutLimits.maxExercises + 1,
            ok.exercises.single,
          ),
        ),
      ),
      isFalse,
    );
    expect(
      fitsLimits(
        ok.copyWith(
          exercises: [
            exercise(
              'squat',
              List.filled(WorkoutLimits.maxSets + 1, lift(1, 1)),
            ),
          ],
        ),
      ),
      isFalse,
    );
  });

  group('advancesProgram', () {
    final active = ActiveProgram(
      programId: 'p1',
      weekdays: const [1, 3],
      nextDayIndex: 1,
      nextDate: CalendarDate(2026, 11, 11),
      startedAt: DateTime(2026, 11, 1),
    );
    Workout from(String? programId, int? day) =>
        workout('w1', const [], programId: programId, dayIndex: day);

    test('only for the next day of the active program', () {
      expect(advancesProgram(from('p1', 1), active, legs), isTrue);
      expect(advancesProgram(from('p1', 0), active, legs), isFalse);
      expect(advancesProgram(from('p2', 1), active, legs), isFalse);
      expect(advancesProgram(from(null, null), active, legs), isFalse);
      expect(advancesProgram(from('p1', 1), null, legs), isFalse);
      expect(advancesProgram(from('p1', 1), active, null), isFalse);
    });

    test('counts the next day within a program that lost days', () {
      final shrunk = legs.copyWith(days: [legs.days.first]);
      expect(advancesProgram(from('p1', 0), active, shrunk), isTrue);
    });
  });

  group('programFromWorkout', () {
    final done = workout('w1', [
      exercise('squat', [
        lift(60, 10, type: SetType.warmup),
        lift(100, 8),
        lift(105, 6),
      ], group: 'A'),
      exercise('gone', [lift(10, 10)], group: 'A'),
      exercise('plank', [
        const WorkoutSet(durationS: 45, done: true),
        const WorkoutSet(durationS: 70, done: true),
      ], type: LoggingType.duration),
      exercise('dip', [
        lift(30, 8),
        lift(20, 10),
      ], type: LoggingType.assistedBodyweight),
    ]);
    final program = programFromWorkout(
      done,
      name: '  Friday  ',
      catalogue: catalogue,
    );

    test('repeats the working sets as targets', () {
      expect(program.name, 'Friday');
      expect(program.origin, ProgramOrigin.own);
      expect(program.days.single.items, [
        item('squat', sets: 2, repMin: 6, repMax: 8, restS: 120, targetKg: 105),
        item(
          'plank',
          sets: 2,
          repMin: null,
          repMax: null,
          durationS: 70,
          restS: 45,
        ),
        item('dip', sets: 2, repMin: 8, repMax: 10, targetKg: 20),
      ]);
    });

    test('is a valid program', () {
      expect(
        validateProgram(program, {
          for (final e in catalogue.values) e.id: e.loggingType,
        }).isValid,
        isTrue,
      );
    });
  });
}
