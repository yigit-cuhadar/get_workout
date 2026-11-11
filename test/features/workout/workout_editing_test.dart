import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_validation.dart';
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
          item('gone', group: 'A'),
          item('squat', group: 'A', sets: 4, targetKg: 100),
          item('lunge', group: 'A'),
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
